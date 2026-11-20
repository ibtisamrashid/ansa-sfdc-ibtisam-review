/** Invoice creation safety tests; existing reconciliation tests retained below. */
@IsTest
private class ABT_StripeFixTest {
    private static ABT_Invoice__c invoice() {
        ABT_Invoice__c inv = new ABT_Invoice__c(ABT_Status__c='Open', ABT_Amount_Paid__c=50,
            ABT_Netsuite_Invoice_Id__c='SYNTHETIC-001', Sent_to_Stripe__c=false);
        insert inv;
        Product2 product = new Product2(Name='Synthetic invoice product'); insert product;
        insert new ABT_InvoiceLineItem__c(ABT_Invoice__c=inv.Id, ABT_Product__c=product.Id);
        ABT_StripeInvoiceProcessor.skipEnqueue=true;
        ABT_StripeInvoiceDispatcher.skipEnqueue=true;
        return inv;
    }
    private static ABT_Invoice__c read(Id invoiceId) {
        return [SELECT Sent_to_Stripe__c, ABT_Stripe_Invoice_Id__c, ABT_Stripe_Processing_Status__c,
            ABT_Amount_Paid__c, ABT_Stripe_Worker_Id__c FROM ABT_Invoice__c WHERE Id=:invoiceId];
    }
    @IsTest static void dispatcherQueuesEligibleOnly() {
        ABT_Invoice__c inv=invoice();
        ABT_StripeInvoiceDispatcher.enqueue(new List<Id>{inv.Id});
        System.assertEquals('Queued', read(inv.Id).ABT_Stripe_Processing_Status__c);
        update new ABT_Invoice__c(Id=inv.Id, ABT_Stripe_Invoice_Id__c='in_synthetic', ABT_Stripe_Processing_Status__c='Review');
        ABT_StripeInvoiceDispatcher.enqueue(new List<Id>{inv.Id});
        System.assertEquals('Review', read(inv.Id).ABT_Stripe_Processing_Status__c);
        ABT_StripeInvoiceDispatcher.enqueue(null);
        ABT_StripeInvoiceDispatcher.enqueue(new List<Id>());
    }
    @IsTest static void committedOwnerPreventsSecondCreator() {
        ABT_Invoice__c inv=invoice();
        ABT_StripeInvoiceProcessor first=new ABT_StripeInvoiceProcessor(new List<Id>{inv.Id});
        first.execute(null);
        System.assertNotEquals(null,read(inv.Id).ABT_Stripe_Worker_Id__c);
        new ABT_StripeInvoiceProcessor(new List<Id>{inv.Id}).execute(null);
        System.assertEquals(0,ABT_StripeInvoiceProcessor.testFlowCalls);
        ABT_StripeInvoiceProcessor.testSimulatedStripeId='in_synthetic';
        ABT_StripeInvoiceProcessor.testSimulatedSent=true;
        first.execute(null);
        System.assertEquals(1,ABT_StripeInvoiceProcessor.testFlowCalls);
        System.assertEquals('Created',read(inv.Id).ABT_Stripe_Processing_Status__c);
        System.assertEquals(50,read(inv.Id).ABT_Amount_Paid__c,'Invoice amount is preserved');
    }
    @IsTest static void stripeIdAloneIsNotSuccessOrPermissionToRecreate() {
        ABT_Invoice__c inv=invoice();
        ABT_StripeInvoiceProcessor worker=new ABT_StripeInvoiceProcessor(new List<Id>{inv.Id});
        worker.execute(null);
        ABT_StripeInvoiceProcessor.testSimulatedStripeId='in_synthetic_draft';
        worker.execute(null);
        System.assertEquals('Review',read(inv.Id).ABT_Stripe_Processing_Status__c);
        System.assertEquals(false,read(inv.Id).Sent_to_Stripe__c);
        new ABT_StripeInvoiceProcessor(new List<Id>{inv.Id}).execute(null);
        System.assertEquals(1,ABT_StripeInvoiceProcessor.testFlowCalls,'Existing draft is never recreated');
        System.assertEquals(0,ABT_StripeInvoiceRetryScheduler.enqueuePending());
    }
    @IsTest static void flowErrorHoldsForReview() {
        ABT_Invoice__c inv=invoice();
        ABT_StripeInvoiceProcessor worker=new ABT_StripeInvoiceProcessor(new List<Id>{inv.Id});
        worker.execute(null);
        ABT_StripeInvoiceProcessor.testSimulatedError='Synthetic failure';
        worker.execute(null);
        System.assertEquals('Review',read(inv.Id).ABT_Stripe_Processing_Status__c);
        System.assertEquals(1,[SELECT COUNT() FROM ABT_Stripe_Error_Log__c WHERE Needs_Manual_Review__c=true]);
        System.assertEquals(0,ABT_StripeInvoiceRetryScheduler.enqueuePending(),'Ambiguous failure is not replayed');
    }
    @IsTest static void knownStripeIdNeverStartsFlow() {
        ABT_Invoice__c inv=invoice();
        update new ABT_Invoice__c(Id=inv.Id,ABT_Stripe_Invoice_Id__c='in_existing');
        new ABT_StripeInvoiceProcessor(new List<Id>{inv.Id}).execute(null);
        System.assertEquals(0,ABT_StripeInvoiceProcessor.testFlowCalls);
        System.assertEquals(false,read(inv.Id).Sent_to_Stripe__c);
    }
    @IsTest static void oversizedInvoiceStopsBeforeCreatingStripeDraft() {
        ABT_Invoice__c inv=invoice();
        List<Product2> products=new List<Product2>();
        for(Integer i=0;i<19;i++) products.add(new Product2(Name='Synthetic product '+i));
        insert products;
        List<ABT_InvoiceLineItem__c> lines=new List<ABT_InvoiceLineItem__c>();
        for(Product2 product:products) lines.add(new ABT_InvoiceLineItem__c(ABT_Invoice__c=inv.Id,ABT_Product__c=product.Id));
        insert lines;
        ABT_StripeInvoiceProcessor worker=new ABT_StripeInvoiceProcessor(new List<Id>{inv.Id});
        worker.execute(null); worker.execute(null);
        System.assertEquals(0,ABT_StripeInvoiceProcessor.testFlowCalls,'No external invoice starts beyond callout budget');
        System.assertEquals('Review',read(inv.Id).ABT_Stripe_Processing_Status__c);
        System.assertEquals(50,read(inv.Id).ABT_Amount_Paid__c);
    }
    private class CardTransport implements ABT_StripeInvoiceGateway.Transport {
        String owner; Boolean attachWorks; Integer attaches=0;
        CardTransport(String owner,Boolean attachWorks) { this.owner=owner; this.attachWorks=attachWorks; }
        public Map<String,Object> invoke(String name,Map<String,Object> parameters) {
            if(name=='stripeGC__v01_PostPaymentMethodsAttach') {
                attaches++; if(attachWorks) owner=(String)parameters.get('customer');
                return new Map<String,Object>();
            }
            return new Map<String,Object>{'customer'=>owner};
        }
    }
    @IsTest static void unattachedCardIsVerifiedAfterAttachment() {
        CardTransport transport=new CardTransport(null,true);
        ABT_StripeInvoiceGateway.testTransport=transport;
        ABT_StripeInvoiceGateway.verifyPaymentMethod('synthetic_account','cus_synthetic','pm_synthetic');
        System.assertEquals(1,transport.attaches);
    }
    @IsTest static void matchingCardDoesNotRequireReattachment() {
        CardTransport transport=new CardTransport('cus_synthetic',true);
        ABT_StripeInvoiceGateway.testTransport=transport;
        ABT_StripeInvoiceGateway.verifyPaymentMethod('synthetic_account','cus_synthetic','pm_synthetic');
        System.assertEquals(0,transport.attaches);
    }
    @IsTest static void anotherCustomersCardCannotBeMoved() {
        CardTransport transport=new CardTransport('cus_other',true);
        ABT_StripeInvoiceGateway.testTransport=transport;
        Boolean rejected=false;
        try { ABT_StripeInvoiceGateway.verifyPaymentMethod('synthetic_account','cus_synthetic','pm_synthetic'); }
        catch(ABT_StripeInvoiceGateway.StripeActionException expected) { rejected=true; }
        System.assert(rejected); System.assertEquals(0,transport.attaches);
    }
    @IsTest static void unverifiedAttachCannotProceedToPayment() {
        CardTransport transport=new CardTransport(null,false);
        ABT_StripeInvoiceGateway.testTransport=transport;
        Boolean rejected=false;
        try { ABT_StripeInvoiceGateway.verifyPaymentMethod('synthetic_account','cus_synthetic','pm_synthetic'); }
        catch(ABT_StripeInvoiceGateway.StripeActionException expected) { rejected=true; }
        System.assert(rejected);
    }

    @IsTest
    static void reconciler_match_noLog() {
        ABT_Invoice__c inv = new ABT_Invoice__c(ABT_Status__c = 'Open', ABT_Amount_Paid__c = 100,
            ABT_Stripe_Invoice_Id__c = 'in_match');
        insert inv;
        ABT_StripeInvoiceReconciler.Snapshot snap = new ABT_StripeInvoiceReconciler.Snapshot();
        snap.total = 100; snap.lineCount = 0; // no line items on this invoice -> matches
        Test.startTest();
        Boolean ok = ABT_StripeInvoiceReconciler.reconcile(inv, snap);
        Test.stopTest();
        System.assertEquals(true, ok, 'matching count + total -> no mismatch');
        System.assertEquals(0, [SELECT COUNT() FROM ABT_Stripe_Error_Log__c], 'no log on match');
    }

    @IsTest
    static void reconciler_mismatch_logsAndFlags() {
        ABT_Invoice__c inv = new ABT_Invoice__c(ABT_Status__c = 'Open', ABT_Amount_Paid__c = 100,
            ABT_Stripe_Invoice_Id__c = 'in_dup');
        insert inv;
        ABT_StripeInvoiceReconciler.Snapshot snap = new ABT_StripeInvoiceReconciler.Snapshot();
        snap.total = 295; snap.lineCount = 2; // Stripe shows more lines + higher total (a duplicate)
        Test.startTest();
        Boolean ok = ABT_StripeInvoiceReconciler.reconcile(inv, snap);
        Test.stopTest();
        System.assertEquals(false, ok, 'mismatch detected');
        List<ABT_Stripe_Error_Log__c> logs = [
            SELECT Failure_Reason__c, Needs_Manual_Review__c, Amount__c FROM ABT_Stripe_Error_Log__c];
        System.assertEquals(1, logs.size(), 'mismatch logged');
        System.assertEquals(ABT_StripeInvoiceReconciler.REASON_MISMATCH, logs[0].Failure_Reason__c);
        System.assertEquals(true, logs[0].Needs_Manual_Review__c, 'flagged for manual review');
    }

    @IsTest
    static void reconciler_helpers_coverage() {
        System.assertEquals(true, ABT_StripeInvoiceReconciler.reconcile(
            new ABT_Invoice__c(Id = null), null), 'null snapshot -> no block');
        ABT_StripeInvoiceReconciler.Snapshot s =
            ABT_StripeInvoiceReconciler.parseSnapshot(new Map<String, Object>{ 'total' => 17858, 'lines' => 'not-a-list' });
        System.assertEquals(178.58, s.total, 'cents -> dollars');
        System.assertEquals(null, s.lineCount, 'non-list lines -> null count, safely caught');
        System.assertEquals(null, ABT_StripeInvoiceReconciler.retrieve(null), 'null id -> null');
        System.assertEquals(null, ABT_StripeInvoiceReconciler.retrieve(''), 'empty id -> null');
        ABT_StripeInvoiceReconciler.testSnapshot = s;
        System.assertEquals(178.58, ABT_StripeInvoiceReconciler.retrieve('in_x').total);
        ABT_StripeInvoiceReconciler.getStripeAccountId();
        ABT_StripeInvoiceReconciler.getStripeAccountId();
        ABT_StripeInvoiceReconciler.Snapshot empty = ABT_StripeInvoiceReconciler.parseSnapshot(new Map<String, Object>());
        System.assertEquals(null, empty.total);
    }

    @IsTest
    static void reconcileJob_persistsTotal_andReconciles() {
        ABT_Invoice__c inv = new ABT_Invoice__c(ABT_Status__c = 'Open', ABT_Amount_Paid__c = 100,
            ABT_Stripe_Invoice_Id__c = 'in_rec', ABT_Stripe_Processing_Status__c = 'Created'); // total null
        insert inv;
        ABT_StripeInvoiceReconciler.Snapshot snap = new ABT_StripeInvoiceReconciler.Snapshot();
        snap.total = 118; snap.lineCount = 0;
        ABT_StripeInvoiceReconciler.testSnapshot = snap;
        Test.startTest();
        new ABT_StripeInvoiceReconcileJob(new List<Id>{ inv.Id }).execute(null);
        Test.stopTest();
        System.assertEquals(118,
            [SELECT ABT_Stripe_Invoice_Total__c FROM ABT_Invoice__c WHERE Id = :inv.Id].ABT_Stripe_Invoice_Total__c,
            'reconcile job persists the authoritative total (decoupled from creation)');
        System.assertEquals(0, [SELECT COUNT() FROM ABT_Stripe_Error_Log__c], 'match -> no log');
    }

    @IsTest
    static void reconcileJob_emptyAndMissingId_noop() {
        new ABT_StripeInvoiceReconcileJob(new List<Id>()).execute(null);
        new ABT_StripeInvoiceReconcileJob(null).execute(null);
        ABT_Invoice__c inv = new ABT_Invoice__c(ABT_Status__c = 'Open', ABT_Amount_Paid__c = 100); // no Stripe id
        insert inv;
        Test.startTest();
        new ABT_StripeInvoiceReconcileJob(new List<Id>{ inv.Id }).execute(null); // found but no Stripe id -> skip
        Test.stopTest();
        System.assertEquals(null,
            [SELECT ABT_Stripe_Invoice_Total__c FROM ABT_Invoice__c WHERE Id = :inv.Id].ABT_Stripe_Invoice_Total__c,
            'no Stripe id -> nothing reconciled');
    }

    @IsTest
    static void reconcileJob_chains_multipleIds() {
        ABT_Invoice__c a = new ABT_Invoice__c(ABT_Status__c = 'Open', ABT_Amount_Paid__c = 100,
            ABT_Stripe_Invoice_Id__c = 'in_c1', ABT_Stripe_Processing_Status__c = 'Created');
        ABT_Invoice__c b = new ABT_Invoice__c(ABT_Status__c = 'Open', ABT_Amount_Paid__c = 100,
            ABT_Stripe_Invoice_Id__c = 'in_c2', ABT_Stripe_Processing_Status__c = 'Created');
        insert new List<ABT_Invoice__c>{ a, b };
        ABT_StripeInvoiceReconciler.Snapshot snap = new ABT_StripeInvoiceReconciler.Snapshot();
        snap.total = 100; snap.lineCount = 0;
        ABT_StripeInvoiceReconciler.testSnapshot = snap;
        Test.startTest();
        new ABT_StripeInvoiceReconcileJob(new List<Id>{ a.Id, b.Id }).execute(null);
        Test.stopTest();
        System.assertEquals(100,
            [SELECT ABT_Stripe_Invoice_Total__c FROM ABT_Invoice__c WHERE Id = :a.Id].ABT_Stripe_Invoice_Total__c,
            'first invoice reconciled; remaining list built for the chain');
    }

    @IsTest
    static void reconcileScheduler_sweepsCreatedUnreconciled() {
        insert new ABT_Invoice__c(ABT_Status__c = 'Open', ABT_Amount_Paid__c = 100,
            ABT_Stripe_Invoice_Id__c = 'in_sweep', ABT_Stripe_Processing_Status__c = 'Created'); // total null
        Test.startTest();
        Integer n = ABT_StripeInvoiceRetryScheduler.reconcilePending();
        Test.stopTest();
        System.assertEquals(1, n, 'Created + null-total invoice picked up for reconcile');
    }

    @IsTest
    static void errorLogger_directCoverage() {
        // single-row log(), the long-message truncate branch, and the empty/null logAll guards
        String big = 'abcdefghij';
        while (big.length() < 33000) { big += big; }
        ABT_StripeErrorLogger.log(ABT_StripeErrorLogger.SRC_INVOICE_CREATION,
            ABT_StripeErrorLogger.REASON_API_ERROR, big, null, 'cus_x', 'in_x', 10);
        ABT_StripeErrorLogger.logAll(null);
        ABT_StripeErrorLogger.logAll(new List<ABT_Stripe_Error_Log__c>());
        System.assertEquals(1, [SELECT COUNT() FROM ABT_Stripe_Error_Log__c], 'log() inserted one row (message truncated)');
    }
}