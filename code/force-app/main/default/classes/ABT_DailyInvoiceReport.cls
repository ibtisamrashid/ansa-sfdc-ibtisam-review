/** Daily comparison of visible Salesforce invoices and Stripe in the org's matching environment. */
public with sharing class ABT_DailyInvoiceReport {
    private static final Integer MAX_PAGES = 50;
    private static final Integer MAX_INVOICES = 10000;
    private static final Integer MAX_DETAIL_LINES = 2000;
    @TestVisible private static Boolean sandboxOverride;
    private static Boolean cachedSandbox;

    public class ReportContext {
        @AuraEnabled public Boolean isSandbox;
        @AuraEnabled public String stripeSource;
    }

    @AuraEnabled(cacheable=true)
    public static ReportContext reportContext() {
        requireReportingPermission();
        ReportContext context = new ReportContext();
        context.isSandbox = isSandbox();
        context.stripeSource = stripeSource();
        return context;
    }

    private static Boolean isSandbox() {
        if (Test.isRunningTest() && sandboxOverride != null) return sandboxOverride;
        if (cachedSandbox == null) cachedSandbox = [SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox;
        return cachedSandbox;
    }

    private static String stripeSource() {
        return isSandbox() ? 'Stripe (sandbox)' : 'Stripe (live)';
    }

    public class LineItem {
        @AuraEnabled public String key;
        @AuraEnabled public String lineName;
        @AuraEnabled public String invoiceName;
        @AuraEnabled public String invoiceUrl;
    }

    public class Row {
        @AuraEnabled public String key;
        @AuraEnabled public Date invoiceDate;
        @AuraEnabled public String systemName;
        @AuraEnabled public String currencyCode;
        @AuraEnabled public Integer invoicesCreated = 0;
        @AuraEnabled public Integer lineItems = 0;
        @AuraEnabled public Decimal invoiceAmount = 0;
    }

    // The same connector interface is used by production and synthetic test fixtures.
    public virtual class Connector {
        public virtual Map<String, Object> read(String actionName, Map<String, Object> inputs) {
            if (Limits.getCallouts() >= 90) {
                throw problem('Stripe pagination exceeded the reporting limit. No partial totals were returned.');
            }
            Invocable.Action action = Invocable.Action.createCustomAction('apex', actionName);
            for (String name : inputs.keySet()) {
                action.setInvocationParameter(name, inputs.get(name));
            }
            List<Invocable.Action.Result> results;
            try {
                results = action.invoke();
            } catch (Exception ignored) {
                throw problem(stripeSource() + ' could not be read. Check the connector and retry.');
            }
            if (results.isEmpty() || !results[0].isSuccess()) {
                throw problem(stripeSource() + ' could not be read. Check the connector and retry.');
            }
            return normalizeOutput(actionName, results[0].getOutputParameters());
        }
    }
    @TestVisible private static Connector connector = new Connector();

    @TestVisible
    private static Map<String, Object> normalizeOutput(String actionName, Map<String, Object> output) {
        // The managed package forbids JSON serialization and deserialization.
        // Copy only the reporting fields through its public typed interface.
        List<Object> data = new List<Object>();
        List<Object> managedData = (List<Object>) output.get('data');
        if (managedData == null) return new Map<String, Object>{'hasMore' => output.get('hasMore')};
        for (Object item : managedData) {
            if (actionName == 'stripeGC__v01_ListInvoices') {
                stripeGC.Invoice invoice = (stripeGC.Invoice) item;
                Map<String, Object> lines;
                if (invoice.lines != null) {
                    lines = new Map<String, Object>{'hasMore' => invoice.lines.hasMore};
                    if (invoice.lines.hasMore == false && invoice.lines.data != null) {
                        lines.put('totalCount', invoice.lines.data.size());
                    }
                }
                data.add(new Map<String, Object>{
                    'id' => invoice.id, 'created' => invoice.created,
                    'livemode' => invoice.livemode, 'r_currency' => invoice.r_currency,
                    'total' => invoice.total, 'lines' => lines
                });
            } else if (actionName == 'stripeGC__v01_ListInvoicesLines') {
                stripeGC.LineItem line = (stripeGC.LineItem) item;
                data.add(new Map<String, Object>{'id' => line.id, 'description' => line.description});
            } else {
                throw problem('Unsupported Stripe reporting action.');
            }
        }
        return new Map<String, Object>{'data' => data, 'hasMore' => output.get('hasMore')};
    }

    @AuraEnabled
    public static List<Row> salesforceRows(Date startDate, Date endDate, String currencyCode) {
        String code = validate(startDate, endDate, currencyCode);
        Map<Date, Row> rows = emptyRows(startDate, endDate, 'Salesforce', code);
        Boolean multiCurrency = Schema.SObjectType.ABT_Invoice__c.fields.getMap().containsKey('CurrencyIsoCode');
        if (!multiCurrency && code != UserInfo.getDefaultCurrency()) {
            throw problem('Choose the Salesforce organization currency: ' + UserInfo.getDefaultCurrency() + '.');
        }
        String currencyFilter = multiCurrency ? ' AND CurrencyIsoCode = :code' : '';
        // Read native amounts rather than aggregate SUM, which converts currencies in multicurrency orgs.
        List<ABT_Invoice__c> invoices = Database.query(
            'SELECT ABT_Invoice_Date__c, ABT_Amount_Paid__c FROM ABT_Invoice__c' +
            ' WHERE ABT_Invoice_Date__c >= :startDate AND ABT_Invoice_Date__c <= :endDate' +
            currencyFilter + ' WITH USER_MODE LIMIT 10001'
        );
        if (invoices.size() > MAX_INVOICES) {
            throw problem('More than 10,000 Salesforce invoices match. Choose a shorter date range.');
        }
        for (ABT_Invoice__c invoice : invoices) {
            Row row = rows.get(invoice.ABT_Invoice_Date__c);
            row.invoicesCreated++;
            row.invoiceAmount += invoice.ABT_Amount_Paid__c == null ? 0 : invoice.ABT_Amount_Paid__c;
        }
        String lineCurrencyFilter = multiCurrency ? ' AND ABT_Invoice__r.CurrencyIsoCode = :code' : '';
        for (AggregateResult result : Database.query(
            'SELECT ABT_Invoice__r.ABT_Invoice_Date__c invoiceDay, COUNT(Id) lineCount' +
            ' FROM ABT_InvoiceLineItem__c WHERE ABT_Invoice__r.ABT_Invoice_Date__c >= :startDate' +
            ' AND ABT_Invoice__r.ABT_Invoice_Date__c <= :endDate' + lineCurrencyFilter +
            ' WITH USER_MODE GROUP BY ABT_Invoice__r.ABT_Invoice_Date__c'
        )) {
            rows.get((Date) result.get('invoiceDay')).lineItems = (Integer) result.get('lineCount');
        }
        return orderedRows(rows, startDate, endDate);
    }

    @AuraEnabled
    public static List<Row> stripeRows(Date startDate, Date endDate, String currencyCode) {
        String code = validate(startDate, endDate, currencyCode);
        stripeGC__Stripe_Account__c account = reportingAccount();
        return readStripe(startDate, endDate, code, String.valueOf(account.Id));
    }

    private static stripeGC__Stripe_Account__c reportingAccount() {
        // The org determines the mode; never fall back to another environment.
        Boolean liveMode = !isSandbox();
        List<stripeGC__Stripe_Account__c> accounts = [
            SELECT Id, stripeGC__Stripe_Account_Id__c FROM stripeGC__Stripe_Account__c
            WHERE stripeGC__Is_Connected__c = true AND stripeGC__Is_Live_Mode__c = :liveMode
            WITH USER_MODE LIMIT 2
        ];
        if (accounts.size() != 1) {
            throw problem('Exactly one connected ' + stripeSource() + ' account must be accessible. Ask an administrator to check access and connections.');
        }
        return accounts[0];
    }

    @AuraEnabled
    public static List<LineItem> lineItems(Date invoiceDate, String currencyCode, String systemName) {
        String code = validate(invoiceDate, invoiceDate, currencyCode);
        List<LineItem> details = new List<LineItem>();
        if (systemName == 'Salesforce') {
            Boolean multiCurrency = Schema.SObjectType.ABT_Invoice__c.fields.getMap().containsKey('CurrencyIsoCode');
            if (!multiCurrency && code != UserInfo.getDefaultCurrency()) {
                throw problem('Choose the Salesforce organization currency: ' + UserInfo.getDefaultCurrency() + '.');
            }
            String currencyFilter = multiCurrency ? ' AND ABT_Invoice__r.CurrencyIsoCode = :code' : '';
            for (ABT_InvoiceLineItem__c line : Database.query(
                'SELECT Id, Name, ABT_Description__c, ABT_Invoice__c, ABT_Invoice__r.Name FROM ABT_InvoiceLineItem__c' +
                ' WHERE ABT_Invoice__r.ABT_Invoice_Date__c = :invoiceDate' + currencyFilter +
                ' WITH USER_MODE ORDER BY ABT_Invoice__c, Id LIMIT 2001'
            )) {
                LineItem detail = new LineItem();
                detail.key = String.valueOf(line.Id);
                detail.lineName = !String.isBlank(line.ABT_Description__c) ? line.ABT_Description__c :
                    (String.isBlank(line.Name) ? String.valueOf(line.Id) : line.Name);
                detail.invoiceName = line.ABT_Invoice__r.Name;
                detail.invoiceUrl = '/lightning/r/ABT_Invoice__c/' + line.ABT_Invoice__c + '/view';
                details.add(detail);
            }
            checkDetailLimit(details);
        } else if (systemName == stripeSource()) {
            stripeGC__Stripe_Account__c account = reportingAccount();
            String externalId = account.stripeGC__Stripe_Account_Id__c;
            if (String.isBlank(externalId) || !Pattern.matches('acct_[A-Za-z0-9]+', externalId)) {
                throw problem('The connected ' + stripeSource() + ' account must have a valid Stripe account ID to open invoices.');
            }
            readStripe(invoiceDate, invoiceDate, code, String.valueOf(account.Id), details, externalId);
        } else {
            throw problem('Choose a Salesforce or ' + stripeSource() + ' report row.');
        }
        return details;
    }

    @TestVisible
    private static List<Row> readStripe(Date startDate, Date endDate, String code, String accountId) {
        return readStripe(startDate, endDate, code, accountId, null, null);
    }

    @TestVisible
    private static List<Row> readStripe(Date startDate, Date endDate, String code, String accountId, List<LineItem> details, String externalAccountId) {
        Boolean liveMode = !isSandbox();
        Map<Date, Row> rows = emptyRows(startDate, endDate, stripeSource(), code);
        String cursor;
        Set<String> seen = new Set<String>();
        // The installed connector's date fields are signed 32-bit epoch seconds.
        if (startDate < Date.newInstance(1970, 1, 1) || endDate > Date.newInstance(2038, 1, 18)) {
            throw problem('This Stripe connector supports dates from 1970-01-01 through 2038-01-18.');
        }
        stripeGC.ListCreatedParameter created = new stripeGC.ListCreatedParameter();
        created.gte = Integer.valueOf(String.valueOf(Datetime.newInstanceGmt(startDate, Time.newInstance(0, 0, 0, 0)).getTime() / 1000));
        created.lt = Integer.valueOf(String.valueOf(Datetime.newInstanceGmt(endDate.addDays(1), Time.newInstance(0, 0, 0, 0)).getTime() / 1000));
        for (Integer page = 0; page < MAX_PAGES; page++) {
            Map<String, Object> inputs = new Map<String, Object>{'accountRecordId' => accountId, 'r_limit' => 100, 'created' => created};
            if (cursor != null) inputs.put('startingAfter', cursor);
            Map<String, Object> output = connector.read('stripeGC__v01_ListInvoices', inputs);
            List<Object> data = pageData(output);
            Boolean older = false;
            for (Object item : data) {
                Map<String, Object> invoice = (Map<String, Object>) item;
                String invoiceId = (String) invoice.get('id');
                if (String.isBlank(invoiceId) || seen.contains(invoiceId) || invoice.get('livemode') != liveMode) {
                    throw problem('Stripe returned an unexpected page or an invoice in the wrong environment. No Stripe totals were returned.');
                }
                seen.add(invoiceId);
                cursor = invoiceId;
                Long seconds = Long.valueOf(String.valueOf(invoice.get('created')));
                Date day = Datetime.newInstance(seconds * 1000).dateGmt();
                if (day < startDate) { older = true; break; }
                if (day > endDate) continue;
                String invoiceCurrency = (String) invoice.get('r_currency');
                if (invoiceCurrency == null) invoiceCurrency = (String) invoice.get('currency');
                if (invoiceCurrency == null) throw problem('Stripe returned an invoice without a currency.');
                if (invoiceCurrency.toUpperCase() != code) continue;
                Row row = rows.get(day);
                row.invoicesCreated++;
                row.invoiceAmount += Decimal.valueOf(String.valueOf(invoice.get('total'))) / divisor(code);
                if (details == null) {
                    row.lineItems += countLines(accountId, invoiceId, (Map<String, Object>) invoice.get('lines'));
                } else {
                    readStripeLines(accountId, invoiceId, externalAccountId, details);
                }
            }
            if (older || output.get('hasMore') == false) return orderedRows(rows, startDate, endDate);
            if (data.isEmpty()) throw problem('Stripe returned an incomplete invoice page. Retry the report.');
        }
        throw problem('Stripe has too many invoices in this period. Choose a shorter date range. No partial totals were returned.');
    }

    private static void readStripeLines(String accountId, String invoiceId, String externalAccountId, List<LineItem> details) {
        String cursor;
        Set<String> seen = new Set<String>();
        for (Integer page = 0; page < MAX_PAGES; page++) {
            Map<String, Object> inputs = new Map<String, Object>{'accountRecordId' => accountId, 'invoice' => invoiceId, 'r_limit' => 100};
            if (cursor != null) inputs.put('startingAfter', cursor);
            Map<String, Object> output = connector.read('stripeGC__v01_ListInvoicesLines', inputs);
            List<Object> data = pageData(output);
            for (Object item : data) {
                Map<String, Object> line = (Map<String, Object>) item;
                String lineId = (String) line.get('id');
                if (String.isBlank(lineId) || seen.contains(lineId)) throw problem('Stripe returned a repeated or invalid line page.');
                seen.add(lineId);
                cursor = lineId;
                LineItem detail = new LineItem();
                detail.key = invoiceId + '-' + lineId;
                String description = (String) line.get('description');
                detail.lineName = String.isBlank(description) ? lineId : description;
                detail.invoiceName = invoiceId;
                detail.invoiceUrl = 'https://dashboard.stripe.com/' + EncodingUtil.urlEncode(externalAccountId, 'UTF-8') +
                    (isSandbox() ? '/test/invoices/' : '/invoices/') + EncodingUtil.urlEncode(invoiceId, 'UTF-8');
                details.add(detail);
                checkDetailLimit(details);
            }
            if (output.get('hasMore') == false) return;
            if (data.isEmpty()) throw problem('Stripe returned an incomplete line page.');
        }
        throw problem('Stripe line pagination exceeded the reporting limit. No partial details were returned.');
    }

    private static void checkDetailLimit(List<LineItem> details) {
        if (details.size() > MAX_DETAIL_LINES) {
            throw problem('This day has more than 2,000 line items. Open the source system to review the full invoice details.');
        }
    }

    private static Integer countLines(String accountId, String invoiceId, Map<String, Object> lines) {
        if (lines == null) throw problem('Stripe returned an invoice without line information.');
        if (lines.get('totalCount') != null) return Integer.valueOf(String.valueOf(lines.get('totalCount')));
        if (lines.get('total_count') != null) return Integer.valueOf(String.valueOf(lines.get('total_count')));
        List<Object> embedded = (List<Object>) lines.get('data');
        if (lines.get('hasMore') == false || lines.get('has_more') == false) {
            if (embedded == null) throw problem('Stripe returned incomplete line information.');
            return embedded.size();
        }
        Integer count = 0;
        String cursor;
        Set<String> seen = new Set<String>();
        for (Integer page = 0; page < MAX_PAGES; page++) {
            if (Limits.getCallouts() >= 90) throw problem('Stripe line pagination exceeded the reporting limit. Choose a shorter range.');
            Map<String, Object> inputs = new Map<String, Object>{'accountRecordId' => accountId, 'invoice' => invoiceId, 'r_limit' => 100};
            if (cursor != null) inputs.put('startingAfter', cursor);
            Map<String, Object> output = connector.read('stripeGC__v01_ListInvoicesLines', inputs);
            List<Object> data = pageData(output);
            for (Object item : data) {
                String lineId = (String) ((Map<String, Object>) item).get('id');
                if (String.isBlank(lineId) || seen.contains(lineId)) throw problem('Stripe returned a repeated line page.');
                seen.add(lineId);
                cursor = lineId;
                count++;
            }
            if (output.get('hasMore') == false) return count;
            if (data.isEmpty()) throw problem('Stripe returned an incomplete line page.');
        }
        throw problem('Stripe line pagination exceeded the reporting limit. No partial totals were returned.');
    }

    private static List<Object> pageData(Map<String, Object> output) {
        if (output == null || output.get('data') == null || output.get('hasMore') == null) {
            throw problem('Stripe returned an incomplete response. No partial totals were returned.');
        }
        return (List<Object>) output.get('data');
    }

    private static String validate(Date startDate, Date endDate, String currencyCode) {
        requireReportingPermission();
        if (startDate == null || endDate == null || endDate < startDate || startDate.daysBetween(endDate) > 30) {
            throw problem('Choose a date range of 1 to 31 days.');
        }
        String code = currencyCode == null ? '' : currencyCode.trim().toUpperCase();
        if (!Pattern.matches('[A-Z]{3}', code)) throw problem('Enter a three-letter currency code.');
        return code;
    }

    private static void requireReportingPermission() {
        if (!FeatureManagement.checkPermission('ABT_View_Daily_Invoice_Report')) {
            throw problem('Daily Invoice Reporting permission is required.');
        }
    }

    private static Decimal divisor(String code) {
        if (new Set<String>{'BIF','CLP','DJF','GNF','JPY','KMF','KRW','MGA','PYG','RWF','VND','VUV','XAF','XOF','XPF'}.contains(code)) return 1;
        if (new Set<String>{'BHD','JOD','KWD','OMR','TND'}.contains(code)) return 1000;
        return 100;
    }

    private static Map<Date, Row> emptyRows(Date startDate, Date endDate, String source, String code) {
        Map<Date, Row> rows = new Map<Date, Row>();
        for (Date day = startDate; day <= endDate; day = day.addDays(1)) {
            Row row = new Row();
            row.key = String.valueOf(day) + '-' + source;
            row.invoiceDate = day;
            row.systemName = source;
            row.currencyCode = code;
            rows.put(day, row);
        }
        return rows;
    }

    private static List<Row> orderedRows(Map<Date, Row> rows, Date startDate, Date endDate) {
        List<Row> ordered = new List<Row>();
        for (Date day = endDate; day >= startDate; day = day.addDays(-1)) ordered.add(rows.get(day));
        return ordered;
    }

    private static AuraHandledException problem(String message) {
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }
}
