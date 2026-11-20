/**
 * PAN-35652 (A1) — async Stripe invoice CREATION tests: dispatcher queue/idempotency, the
 * one-per-transaction processor (success / failure / retryable), the retry + reconcile sweeps,
 * and the line-count reconciler. B1 payment-matching tests live in ABT_StripeB1Test, which ships
 * with the B1 helper. The live managed-package callout subflow is validated in the sandbox.
 */
@IsTest
private class ABT_StripeFixTest {

    private static Account makeAccount(String stripeCustomerId) {
        Account a = new Account(Name = 'Test Co', ABT_Stripe_Customer_Id__c = stripeCustomerId, AccountNumber = 'NS-1');
        insert a;
        return a;
    }

    @IsTest
    static void dispatcher_marksQueued_forEligibleInvoices() {
        makeAccount('cus_q');
        ABT_Invoice__c inv = new ABT_Invoice__c(ABT_Status__c = 'Open', ABT_Amount_Paid__c = 50,
            ABT_Netsuite_Invoice_Id__c = '999', Sent_to_Stripe__c = false);
        insert inv;
        ABT_StripeInvoiceDispatcher.skipEnqueue = true; // assert the Queued stamp only
        Test.startTest();
        ABT_StripeInvoiceDispatcher.enqueue(new List<Id>{ inv.Id });
        Test.stopTest();
        System.assertEquals('Queued',
            [SELECT ABT_Stripe_Processing_Status__c FROM ABT_Invoice__c WHERE Id = :inv.Id].ABT_Stripe_Processing_Status__c,
            'eligible invoice marked Queued');
    }

    @IsTest
    static void processor_idempotent_skipsAlreadyCreated() {
        makeAccount('cus_done');
        ABT_Invoice__c inv = new ABT_Invoice__c(ABT_Status__c = 'Open', ABT_Amount_Paid__c = 50,
            ABT_Stripe_Invoice_Id__c = 'in_already', Sent_to_Stripe__c = true);
        insert inv;
        Test.startTest();
        new ABT_StripeInvoiceProcessor(new List<Id>{ inv.Id }).execute(null); // already has Stripe id -> no-op
        Test.stopTest();
        System.assertEquals('Created',
            [SELECT ABT_Stripe_Processing_Status__c FROM ABT_Invoice__c WHERE Id = :inv.Id].ABT_Stripe_Processing_Status__c,
            'already-created invoice is idempotently marked Created, not reprocessed');
    }

    @IsTest
    static void retryScheduler_enqueuesPending() {
        makeAccount('cus_r');
        insert new ABT_Invoice__c(ABT_Status__c = 'Open', ABT_Amount_Paid__c = 50,
            ABT_Netsuite_Invoice_Id__c = '111', Sent_to_Stripe__c = false,
            ABT_Stripe_Processing_Status__c = 'Failed', ABT_Stripe_Retry_Count__c = 1);
        Test.startTest();
        Integer n = ABT_StripeInvoiceRetryScheduler.enqueuePending();
        Test.stopTest();
        System.assertEquals(1, n, 'one pending invoice picked up by the safety-net sweep');
    }

    @IsTest
    static void processor_success_locksAndMarksCreated() {
        makeAccount('cus_ok');
        ABT_Invoice__c inv = new ABT_Invoice__c(ABT_Status__c = 'Open', ABT_Amount_Paid__c = 50,
            ABT_Netsuite_Invoice_Id__c = '222', Sent_to_Stripe__c = false);
        insert inv;
        ABT_StripeInvoiceProcessor.testSimulatedStripeId = 'in_ok'; // simulate a confirmed creation
        Test.startTest();
        new ABT_StripeInvoiceProcessor(new List<Id>{ inv.Id }).execute(null);
        Test.stopTest();
        ABT_Invoice__c a = [SELECT Sent_to_Stripe__c, ABT_Stripe_Processing_Status__c FROM ABT_Invoice__c WHERE Id = :inv.Id];
        System.assertEquals(true, a.Sent_to_Stripe__c, 'locked only after a confirmed Stripe Invoice Id');
        System.assertEquals('Created', a.ABT_Stripe_Processing_Status__c);
        System.assertEquals(0, [SELECT COUNT() FROM ABT_Stripe_Error_Log__c], 'no error on success');
    }

    @IsTest
    static void processor_failure_logsAndStaysRetryable() {
        makeAccount('cus_fail');
        ABT_Invoice__c inv = new ABT_Invoice__c(ABT_Status__c = 'Open', ABT_Amount_Paid__c = 50,
            ABT_Netsuite_Invoice_Id__c = '333', Sent_to_Stripe__c = false);
        insert inv;
        ABT_StripeInvoiceProcessor.testSimulatedStripeId = null; // simulate no Stripe invoice produced
        Test.startTest();
        new ABT_StripeInvoiceProcessor(new List<Id>{ inv.Id }).execute(null);
        Test.stopTest();
        ABT_Invoice__c a = [SELECT Sent_to_Stripe__c, ABT_Stripe_Processing_Status__c, ABT_Stripe_Retry_Count__c FROM ABT_Invoice__c WHERE Id = :inv.Id];
        System.assertEquals(false, a.Sent_to_Stripe__c, 'stays unlocked -> retryable (no permanent strand)');
        System.assertEquals('Failed', a.ABT_Stripe_Processing_Status__c);
        System.assertEquals(1, a.ABT_Stripe_Retry_Count__c, 'retry counter incremented');
        System.assertEquals(1, [SELECT COUNT() FROM ABT_Stripe_Error_Log__c], 'failure logged, not silent');
    }

    @IsTest
    static void dispatcher_enqueues_processesToCreated() {
        makeAccount('cus_e2e');
        ABT_Invoice__c inv = new ABT_Invoice__c(ABT_Status__c = 'Open', ABT_Amount_Paid__c = 50,
            ABT_Netsuite_Invoice_Id__c = '444', Sent_to_Stripe__c = false);
        insert inv;
        ABT_StripeInvoiceDispatcher.skipEnqueue = false;
        ABT_StripeInvoiceProcessor.testSimulatedStripeId = 'in_e2e';
        Test.startTest();
        ABT_StripeInvoiceDispatcher.enqueue(new List<Id>{ inv.Id }); // Queued + enqueue
        Test.stopTest(); // processor runs here
        System.assertEquals('Created',
            [SELECT ABT_Stripe_Processing_Status__c FROM ABT_Invoice__c WHERE Id = :inv.Id].ABT_Stripe_Processing_Status__c,
            'dispatcher -> processor -> Created');
    }

    @IsTest
    static void dispatcher_emptyAndIneligible_noop() {
        ABT_StripeInvoiceDispatcher.enqueue(new List<Id>());
        ABT_StripeInvoiceDispatcher.enqueue(null);
        makeAccount('cus_ne');
        ABT_Invoice__c inv = new ABT_Invoice__c(ABT_Status__c = 'Open', ABT_Amount_Paid__c = 50,
            ABT_Stripe_Invoice_Id__c = 'in_has', Sent_to_Stripe__c = true); // already created -> ineligible
        insert inv;
        Test.startTest();
        ABT_StripeInvoiceDispatcher.enqueue(new List<Id>{ inv.Id });
        Test.stopTest();
        System.assertNotEquals('Queued',
            [SELECT ABT_Stripe_Processing_Status__c FROM ABT_Invoice__c WHERE Id = :inv.Id].ABT_Stripe_Processing_Status__c,
            'ineligible invoice is not queued');
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