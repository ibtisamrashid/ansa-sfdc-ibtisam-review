@IsTest
private class ABT_DailyInvoiceReportTest {
    private static final Date DAY = Date.newInstance(2026, 10, 30);

    @TestSetup
    static void grantReporting() {
        Id profileId = [SELECT ProfileId FROM User WHERE Id = :UserInfo.getUserId()].ProfileId;
        List<User> users = new List<User>();
        for (String alias : new List<String>{'invrpt', 'invdeny'}) {
            users.add(new User(
                Alias = alias, LastName = 'Daily Invoice Report Test',
                Email = alias + '@example.invalid',
                Username = alias + '.' + UserInfo.getOrganizationId() + '.' + Datetime.now().getTime() + '@example.invalid',
                ProfileId = profileId, TimeZoneSidKey = 'GMT', LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
            ));
        }
        insert users;
        PermissionSet permission = [SELECT Id FROM PermissionSet WHERE Name = 'ABT_Daily_Invoice_Reporting'];
        insert new PermissionSetAssignment(AssigneeId = users[0].Id, PermissionSetId = permission.Id);
    }

    private static User testUser(String alias) {
        return [SELECT Id FROM User WHERE Alias = :alias AND LastName = 'Daily Invoice Report Test' LIMIT 1];
    }

    private class FakeConnector extends ABT_DailyInvoiceReport.Connector {
        List<Map<String, Object>> pages;
        Integer calls = 0;
        List<Map<String, Object>> requests = new List<Map<String, Object>>();
        Boolean fail = false;
        FakeConnector(List<Map<String, Object>> pages) { this.pages = pages; }
        public override Map<String, Object> read(String actionName, Map<String, Object> inputs) {
            if (fail) throw new AuraHandledException('Stripe sandbox unavailable');
            requests.add(inputs);
            return pages[calls++];
        }
    }

    private static Map<String, Object> page(List<Object> data, Boolean more) {
        return new Map<String, Object>{'data' => data, 'hasMore' => more};
    }

    private static Map<String, Object> invoice(String invoiceId, Date day, String currencyCode, Integer total, Integer lines) {
        return new Map<String, Object>{
            'id' => invoiceId, 'created' => Datetime.newInstanceGmt(day, Time.newInstance(0, 0, 0, 0)).getTime() / 1000,
            'livemode' => false, 'r_currency' => currencyCode, 'total' => total,
            'lines' => new Map<String, Object>{'totalCount' => lines}
        };
    }

    @IsTest
    static void salesforceCountsParentsOnceAndIncludesEmptyDays() {
        ABT_DailyInvoiceReport.sandboxOverride = true;
        System.runAs(testUser('invrpt')) {
            System.assertEquals(true, FeatureManagement.checkPermission('ABT_View_Daily_Invoice_Report'), 'Assigned reporter must have the real custom permission');
            String code = UserInfo.getDefaultCurrency();
            ABT_Invoice__c first = new ABT_Invoice__c(ABT_Invoice_Date__c = DAY, ABT_Amount_Paid__c = 125.25, Sent_to_Stripe__c = true);
            ABT_Invoice__c second = new ABT_Invoice__c(ABT_Invoice_Date__c = DAY, ABT_Amount_Paid__c = 0, Sent_to_Stripe__c = true);
            ABT_Invoice__c outside = new ABT_Invoice__c(ABT_Invoice_Date__c = DAY.addDays(-1), ABT_Amount_Paid__c = 999, Sent_to_Stripe__c = true);
            ABT_Invoice__c undated = new ABT_Invoice__c(ABT_Amount_Paid__c = 888, Sent_to_Stripe__c = true);
            insert new List<ABT_Invoice__c>{first, second, outside, undated};
            insert new List<ABT_InvoiceLineItem__c>{
                new ABT_InvoiceLineItem__c(ABT_Invoice__c = first.Id, ABT_Unit_Price__c = 100),
                new ABT_InvoiceLineItem__c(ABT_Invoice__c = first.Id, ABT_Unit_Price__c = 25.25),
                new ABT_InvoiceLineItem__c(ABT_Invoice__c = outside.Id, ABT_Unit_Price__c = 999)
            };
            Test.startTest();
            List<ABT_DailyInvoiceReport.Row> rows = ABT_DailyInvoiceReport.salesforceRows(DAY, DAY.addDays(1), code);
            Test.stopTest();
            System.assertEquals(2, rows.size());
            System.assertEquals(0, rows[0].invoicesCreated, 'Empty day is explicit');
            System.assertEquals(2, rows[1].invoicesCreated, 'Invoice without lines is counted');
            System.assertEquals(2, rows[1].lineItems);
            System.assertEquals(125.25, rows[1].invoiceAmount, 'Parent amount is never multiplied by lines');
        }
    }

    @IsTest
    static void pagesUseUtcDatesAndDoNotMixCurrencies() {
        ABT_DailyInvoiceReport.sandboxOverride = true;
        Map<String, Object> justBefore = invoice('in_before', DAY.addDays(-1), 'usd', 900, 1);
        FakeConnector fake = new FakeConnector(new List<Map<String, Object>>{
            page(new List<Object>{invoice('in_new', DAY.addDays(1), 'usd', 400, 1), invoice('in_usd', DAY, 'usd', 3129039, 72)}, true),
            page(new List<Object>{invoice('in_eur', DAY, 'eur', 500, 2), invoice('in_zero', DAY, 'usd', 0, 0), justBefore}, true)
        });
        ABT_DailyInvoiceReport.connector = fake;
        List<ABT_DailyInvoiceReport.Row> rows = ABT_DailyInvoiceReport.readStripe(DAY, DAY, 'USD', 'synthetic-account');
        System.assertEquals(2, fake.calls);
        stripeGC.ListCreatedParameter created = (stripeGC.ListCreatedParameter) fake.requests[0].get('created');
        System.assertEquals(Datetime.newInstanceGmt(DAY, Time.newInstance(0, 0, 0, 0)).getTime() / 1000, created.gte);
        System.assertEquals(Datetime.newInstanceGmt(DAY.addDays(1), Time.newInstance(0, 0, 0, 0)).getTime() / 1000, created.lt);
        System.assertEquals('in_usd', fake.requests[1].get('startingAfter'));
        System.assertEquals(2, rows[0].invoicesCreated);
        System.assertEquals(72, rows[0].lineItems);
        System.assertEquals(31290.39, rows[0].invoiceAmount);
        System.assertEquals('Stripe (sandbox)', rows[0].systemName);
    }

    @IsTest
    static void linePaginationCountsBeyondEmbeddedPreview() {
        ABT_DailyInvoiceReport.sandboxOverride = true;
        Map<String, Object> inv = invoice('in_lines', DAY, 'usd', 1000, 0);
        inv.put('lines', new Map<String, Object>{'hasMore' => true, 'data' => new List<Object>{new Map<String, Object>{'id' => 'preview'}}});
        FakeConnector fake = new FakeConnector(new List<Map<String, Object>>{
            page(new List<Object>{inv}, false),
            page(new List<Object>{new Map<String, Object>{'id' => 'line_1'}, new Map<String, Object>{'id' => 'line_2'}}, true),
            page(new List<Object>{new Map<String, Object>{'id' => 'line_3'}}, false)
        });
        ABT_DailyInvoiceReport.connector = fake;
        System.assertEquals(3, ABT_DailyInvoiceReport.readStripe(DAY, DAY, 'USD', 'synthetic-account')[0].lineItems);
        System.assertEquals('line_2', fake.requests[2].get('startingAfter'));
        System.assertEquals('in_lines', fake.requests[1].get('invoice'));
    }

    @IsTest
    static void managedInvoiceShapePreservesReportingFields() {
        ABT_DailyInvoiceReport.sandboxOverride = true;
        // Construct managed types through their public interface: cross-namespace
        // JSON deserialization is forbidden by the installed package.
        stripeGC.Invoice typed = new stripeGC.Invoice();
        typed.id = 'in_contract';
        typed.created = Integer.valueOf(String.valueOf(Datetime.newInstanceGmt(DAY, Time.newInstance(0, 0, 0, 0)).getTime() / 1000));
        typed.livemode = false;
        typed.r_currency = 'usd';
        typed.total = 12345;
        typed.lines = new stripeGC.InvoiceLinesList();
        typed.lines.hasMore = true;
        Map<String, Object> normalized = ABT_DailyInvoiceReport.normalizeOutput(
            'stripeGC__v01_ListInvoices', page(new List<Object>{typed}, false)
        );
        FakeConnector fake = new FakeConnector(new List<Map<String, Object>>{
            normalized,
            page(new List<Object>{new Map<String, Object>{'id' => 'il_contract'}}, false)
        });
        ABT_DailyInvoiceReport.connector = fake;
        ABT_DailyInvoiceReport.Row result = ABT_DailyInvoiceReport.readStripe(DAY, DAY, 'USD', 'synthetic-account')[0];
        System.assertEquals(1, result.invoicesCreated);
        System.assertEquals(1, result.lineItems);
        System.assertEquals(123.45, result.invoiceAmount);
        System.assertEquals(2, fake.calls, 'Managed hasMore must trigger complete line retrieval');
    }

    @IsTest
    static void normalizesManagedLinePagesAndCompleteEmbeddedCounts() {
        ABT_DailyInvoiceReport.sandboxOverride = true;
        stripeGC.LineItem line = new stripeGC.LineItem();
        line.id = 'il_complete';
        line.description = 'Synthetic synthesis service';
        Map<String, Object> linePage = ABT_DailyInvoiceReport.normalizeOutput(
            'stripeGC__v01_ListInvoicesLines', page(new List<Object>{line}, false)
        );
        System.assertEquals('il_complete', ((Map<String, Object>) ((List<Object>) linePage.get('data'))[0]).get('id'));
        System.assertEquals('Synthetic synthesis service', ((Map<String, Object>) ((List<Object>) linePage.get('data'))[0]).get('description'));
        System.assertEquals(false, linePage.get('hasMore'));
        stripeGC.Invoice typed = new stripeGC.Invoice();
        typed.lines = new stripeGC.InvoiceLinesList();
        typed.lines.hasMore = false;
        typed.lines.data = new List<stripeGC.LineItem>{line};
        Map<String, Object> invoicePage = ABT_DailyInvoiceReport.normalizeOutput(
            'stripeGC__v01_ListInvoices', page(new List<Object>{typed}, false)
        );
        Map<String, Object> normalized = (Map<String, Object>) ((List<Object>) invoicePage.get('data'))[0];
        System.assertEquals(1, ((Map<String, Object>) normalized.get('lines')).get('totalCount'));
    }

    @IsTest
    static void emptyStripeDayIsZeroAndCurrencyUnitsAreCorrect() {
        ABT_DailyInvoiceReport.sandboxOverride = true;
        ABT_DailyInvoiceReport.connector = new FakeConnector(new List<Map<String, Object>>{page(new List<Object>(), false)});
        System.assertEquals(0, ABT_DailyInvoiceReport.readStripe(DAY, DAY, 'USD', 'synthetic-account')[0].invoiceAmount);
        ABT_DailyInvoiceReport.connector = new FakeConnector(new List<Map<String, Object>>{page(new List<Object>{invoice('in_jpy', DAY, 'jpy', 1200, 1)}, false)});
        System.assertEquals(1200, ABT_DailyInvoiceReport.readStripe(DAY, DAY, 'JPY', 'synthetic-account')[0].invoiceAmount);
        ABT_DailyInvoiceReport.connector = new FakeConnector(new List<Map<String, Object>>{page(new List<Object>{invoice('in_kwd', DAY, 'kwd', 1234, 1)}, false)});
        System.assertEquals(1.234, ABT_DailyInvoiceReport.readStripe(DAY, DAY, 'KWD', 'synthetic-account')[0].invoiceAmount);
    }

    @IsTest
    static void rejectsLiveInvoicesRepeatedPagesAndIncompleteData() {
        ABT_DailyInvoiceReport.sandboxOverride = true;
        Map<String, Object> live = invoice('in_live', DAY, 'usd', 100, 1);
        live.put('livemode', true);
        assertStripeFails(new List<Map<String, Object>>{page(new List<Object>{live}, false)});
        assertStripeFails(new List<Map<String, Object>>{page(new List<Object>(), true)});
        Map<String, Object> inv = invoice('in_repeat', DAY, 'usd', 100, 1);
        assertStripeFails(new List<Map<String, Object>>{page(new List<Object>{inv}, true), page(new List<Object>{inv}, false)});
        assertStripeFails(new List<Map<String, Object>>{new Map<String, Object>()});
    }

    private static void assertStripeFails(List<Map<String, Object>> pages) {
        ABT_DailyInvoiceReport.connector = new FakeConnector(pages);
        try {
            ABT_DailyInvoiceReport.readStripe(DAY, DAY, 'USD', 'synthetic-account');
            System.assert(false, 'Incomplete or unsafe results must never be reported as totals');
        } catch (AuraHandledException expected) {
            System.assertNotEquals(null, expected.getMessage());
        }
    }

    @IsTest
    static void productionUsesLiveRowsAndLinksAndRejectsSandboxResponses() {
        ABT_DailyInvoiceReport.sandboxOverride = false;
        Map<String, Object> live = invoice('in_live', DAY, 'usd', 12345, 1);
        live.put('livemode', true);
        ABT_DailyInvoiceReport.connector = new FakeConnector(new List<Map<String, Object>>{page(new List<Object>{live}, false)});
        List<ABT_DailyInvoiceReport.Row> rows = ABT_DailyInvoiceReport.readStripe(DAY, DAY, 'USD', 'synthetic-account');
        System.assertEquals('Stripe (live)', rows[0].systemName);
        System.assertEquals(123.45, rows[0].invoiceAmount);
        List<ABT_DailyInvoiceReport.LineItem> details = new List<ABT_DailyInvoiceReport.LineItem>();
        ABT_DailyInvoiceReport.connector = new FakeConnector(new List<Map<String, Object>>{
            page(new List<Object>{live}, false),
            page(new List<Object>{new Map<String, Object>{'id' => 'il_live', 'description' => 'Synthetic live service'}}, false)
        });
        ABT_DailyInvoiceReport.readStripe(DAY, DAY, 'USD', 'synthetic-account', details, 'acct_synthetic');
        System.assertEquals('https://dashboard.stripe.com/acct_synthetic/invoices/in_live', details[0].invoiceUrl);
        assertStripeFails(new List<Map<String, Object>>{page(new List<Object>{invoice('in_wrong_mode', DAY, 'usd', 1, 1)}, false)});
    }

    @IsTest
    static void contextFollowsOrgModeAndNeverFallsBackToAnotherConnection() {
        System.runAs(testUser('invrpt')) {
            for (Boolean sandbox : new List<Boolean>{true, false}) {
                ABT_DailyInvoiceReport.sandboxOverride = sandbox;
                ABT_DailyInvoiceReport.ReportContext context = ABT_DailyInvoiceReport.reportContext();
                System.assertEquals(sandbox, context.isSandbox);
                System.assertEquals(sandbox ? 'Stripe (sandbox)' : 'Stripe (live)', context.stripeSource);
                try {
                    ABT_DailyInvoiceReport.stripeRows(DAY, DAY, 'USD');
                    System.assert(false, 'No matching connected account exists in this isolated test');
                } catch (AuraHandledException expected) {
                    System.assert(expected.getMessage().contains(context.stripeSource), 'Error must identify the required environment');
                }
            }
        }
    }

    @IsTest
    static void contextUsesActualOrgFlagWithoutTestOverride() {
        ABT_DailyInvoiceReport.sandboxOverride = null;
        Boolean actualSandbox = [SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox;
        System.runAs(testUser('invrpt')) {
            ABT_DailyInvoiceReport.ReportContext context = ABT_DailyInvoiceReport.reportContext();
            System.assertEquals(actualSandbox, context.isSandbox);
            System.assertEquals(actualSandbox ? 'Stripe (sandbox)' : 'Stripe (live)', context.stripeSource);
        }
    }

    @IsTest
    static void salesforceLineItemsLinkToTheirActualParentInvoices() {
        ABT_DailyInvoiceReport.sandboxOverride = true;
        System.runAs(testUser('invrpt')) {
            ABT_Invoice__c parent = new ABT_Invoice__c(ABT_Invoice_Date__c = DAY, Sent_to_Stripe__c = true);
            ABT_Invoice__c outside = new ABT_Invoice__c(ABT_Invoice_Date__c = DAY.addDays(-1), Sent_to_Stripe__c = true);
            insert new List<ABT_Invoice__c>{parent, outside};
            insert new List<ABT_InvoiceLineItem__c>{
                new ABT_InvoiceLineItem__c(Name = 'Synthetic line A', ABT_Description__c = 'Synthetic DNA fragment', ABT_Invoice__c = parent.Id),
                new ABT_InvoiceLineItem__c(Name = 'Synthetic line B', ABT_Invoice__c = parent.Id),
                new ABT_InvoiceLineItem__c(Name = 'Outside date', ABT_Invoice__c = outside.Id)
            };
            Test.startTest();
            List<ABT_DailyInvoiceReport.LineItem> details = ABT_DailyInvoiceReport.lineItems(DAY, UserInfo.getDefaultCurrency(), 'Salesforce');
            Test.stopTest();
            System.assertEquals(2, details.size(), 'Only line items from the selected invoice date are returned');
            Set<String> names = new Set<String>();
            for (ABT_DailyInvoiceReport.LineItem detail : details) {
                names.add(detail.lineName);
                System.assertEquals('/lightning/r/ABT_Invoice__c/' + parent.Id + '/view', detail.invoiceUrl);
                System.assertNotEquals(null, detail.invoiceName);
            }
            System.assertEquals(new Set<String>{'Synthetic DNA fragment', 'Synthetic line B'}, names, 'Use the item description when present and the record name otherwise');
            System.assertEquals(0, ABT_DailyInvoiceReport.lineItems(DAY.addDays(1), UserInfo.getDefaultCurrency(), 'Salesforce').size());
        }
    }

    @IsTest
    static void stripeLineDetailsRetainParentAcrossPagesAndInvoices() {
        ABT_DailyInvoiceReport.sandboxOverride = true;
        FakeConnector fake = new FakeConnector(new List<Map<String, Object>>{
            page(new List<Object>{invoice('in_first', DAY, 'usd', 1000, 2), invoice('in_second', DAY, 'usd', 2000, 1)}, false),
            page(new List<Object>{new Map<String, Object>{'id' => 'il_one', 'description' => 'Synthetic DNA synthesis'}}, true),
            page(new List<Object>{new Map<String, Object>{'id' => 'il_two'}}, false),
            page(new List<Object>{new Map<String, Object>{'id' => 'il_three'}}, false)
        });
        ABT_DailyInvoiceReport.connector = fake;
        List<ABT_DailyInvoiceReport.LineItem> details = new List<ABT_DailyInvoiceReport.LineItem>();
        ABT_DailyInvoiceReport.readStripe(DAY, DAY, 'USD', 'synthetic-account', details, 'acct_synthetic');
        System.assertEquals(3, details.size());
        System.assertEquals('Synthetic DNA synthesis', details[0].lineName, 'Display the readable invoice item description');
        System.assertEquals('il_two', details[1].lineName, 'Keep the ID fallback for items without descriptions');
        System.assertEquals('il_one', fake.requests[2].get('startingAfter'));
        System.assertEquals('in_second', fake.requests[3].get('invoice'));
        System.assertEquals('in_first', details[0].invoiceName);
        System.assertEquals(details[0].invoiceUrl, details[1].invoiceUrl);
        System.assertEquals('https://dashboard.stripe.com/acct_synthetic/test/invoices/in_first', details[0].invoiceUrl);
        System.assertEquals('https://dashboard.stripe.com/acct_synthetic/test/invoices/in_second', details[2].invoiceUrl);
    }

    @IsTest
    static void rejectsInvalidRangesAndMissingSandbox() {
        ABT_DailyInvoiceReport.sandboxOverride = true;
        System.runAs(testUser('invrpt')) {
            System.assertEquals(true, FeatureManagement.checkPermission('ABT_View_Daily_Invoice_Report'), 'Validate dates and connections as an authorized reporter');
            try {
                ABT_DailyInvoiceReport.salesforceRows(DAY, DAY.addDays(31), 'USD');
                System.assert(false, 'Range must be bounded');
            } catch (AuraHandledException expected) {
                System.assert(expected.getMessage().contains('31 days'));
            }
            try {
                ABT_DailyInvoiceReport.stripeRows(DAY, DAY, 'USD');
                System.assert(false, 'Must not use a live account when a sandbox is missing');
            } catch (AuraHandledException expected) {
                System.assert(expected.getMessage().contains('Stripe (sandbox)'));
            }
        }
    }

    @IsTest
    static void deniedWithoutReportingPermission() {
        ABT_DailyInvoiceReport.sandboxOverride = true;
        System.runAs(testUser('invdeny')) {
            System.assertEquals(false, FeatureManagement.checkPermission('ABT_View_Daily_Invoice_Report'), 'Denied user must never receive the reporting permission');
            try {
                ABT_DailyInvoiceReport.reportContext();
                System.assert(false, 'Context access must enforce the reporting permission');
            } catch (AuraHandledException expected) {
                System.assert(expected.getMessage().contains('permission'));
            }
            try {
                ABT_DailyInvoiceReport.salesforceRows(DAY, DAY, 'USD');
                System.assert(false, 'Permission is mandatory even for a caller with object access');
            } catch (AuraHandledException expected) {
                System.assert(expected.getMessage().contains('permission'));
            }
            try {
                ABT_DailyInvoiceReport.lineItems(DAY, 'USD', 'Salesforce');
                System.assert(false, 'Line details must enforce the reporting permission');
            } catch (AuraHandledException expected) {
                System.assert(expected.getMessage().contains('permission'));
            }
            try {
                ABT_DailyInvoiceReport.stripeRows(DAY, DAY, 'USD');
                System.assert(false, 'Account-wide Stripe reporting also requires permission');
            } catch (AuraHandledException expected) {
                System.assert(expected.getMessage().contains('permission'));
            }
        }
    }
}
