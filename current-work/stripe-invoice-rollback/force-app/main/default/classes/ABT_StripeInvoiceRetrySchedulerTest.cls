/**
 * PAN-35652 — coverage for ABT_StripeInvoiceRetryScheduler, focused on the status-heal
 * (false-negative relabel) plus the pending/reconcile sweeps and the schedulable entry point.
 */
@isTest
private class ABT_StripeInvoiceRetrySchedulerTest {

    @isTest
    static void healBilledStatus_relabelsOnlyBilledMislabeled() {
        // Billed but mislabeled: has Stripe id + payment link, yet status is 'Failed' -> should heal to 'Created'.
        ABT_Invoice__c billedFailed = new ABT_Invoice__c(
            Name = 'HEAL-FAILED',
            ABT_Stripe_Invoice_Id__c = 'in_heal_failed',
            ABT_Stripe_Payment_Link__c = 'https://invoice.stripe.com/i/heal_failed',
            ABT_Stripe_Processing_Status__c = 'Failed',
            Sent_to_Stripe__c = true,
            ABT_Amount_Paid__c = 100
        );
        // Billed but 'Processing' -> should heal.
        ABT_Invoice__c billedProcessing = new ABT_Invoice__c(
            Name = 'HEAL-PROCESSING',
            ABT_Stripe_Invoice_Id__c = 'in_heal_processing',
            ABT_Stripe_Payment_Link__c = 'https://invoice.stripe.com/i/heal_processing',
            ABT_Stripe_Processing_Status__c = 'Processing',
            Sent_to_Stripe__c = true,
            ABT_Amount_Paid__c = 200
        );
        // Genuinely failed: 'Failed' but NO Stripe id -> must NOT be relabeled.
        ABT_Invoice__c genuineFailed = new ABT_Invoice__c(
            Name = 'GENUINE-FAILED',
            ABT_Stripe_Processing_Status__c = 'Failed',
            Sent_to_Stripe__c = false,
            ABT_Amount_Paid__c = 300
        );
        // Draft-linked (id but NO payment link, i.e. not finalized/sent) -> must NOT be relabeled.
        ABT_Invoice__c draftOnly = new ABT_Invoice__c(
            Name = 'DRAFT-ONLY',
            ABT_Stripe_Invoice_Id__c = 'in_draft_only',
            ABT_Stripe_Processing_Status__c = 'Failed',
            Sent_to_Stripe__c = false,
            ABT_Amount_Paid__c = 400
        );
        insert new List<ABT_Invoice__c>{ billedFailed, billedProcessing, genuineFailed, draftOnly };

        Test.startTest();
        Integer healed = ABT_StripeInvoiceRetryScheduler.healBilledStatus();
        Test.stopTest();

        System.assertEquals(2, healed, 'Only the two billed+linked invoices should be healed');
        Map<Id, ABT_Invoice__c> after = new Map<Id, ABT_Invoice__c>([
            SELECT Id, ABT_Stripe_Processing_Status__c FROM ABT_Invoice__c
        ]);
        System.assertEquals('Created', after.get(billedFailed.Id).ABT_Stripe_Processing_Status__c);
        System.assertEquals('Created', after.get(billedProcessing.Id).ABT_Stripe_Processing_Status__c);
        System.assertEquals('Failed', after.get(genuineFailed.Id).ABT_Stripe_Processing_Status__c, 'No Stripe id -> stays Failed');
        System.assertEquals('Failed', after.get(draftOnly.Id).ABT_Stripe_Processing_Status__c, 'No payment link -> stays Failed');
    }

    @isTest
    static void healBilledStatus_noMislabeled_returnsZero() {
        insert new ABT_Invoice__c(Name = 'CLEAN', ABT_Stripe_Processing_Status__c = 'Created', ABT_Amount_Paid__c = 50);
        Test.startTest();
        System.assertEquals(0, ABT_StripeInvoiceRetryScheduler.healBilledStatus());
        Test.stopTest();
    }

    @isTest
    static void sweeps_returnCountsAndDoNotThrow() {
        // A pending invoice eligible for enqueuePending (no id, not sent, has NS id, amount>0, Queued).
        insert new ABT_Invoice__c(
            Name = 'PENDING',
            ABT_Stripe_Processing_Status__c = 'Queued',
            Sent_to_Stripe__c = false,
            ABT_Netsuite_Invoice_Id__c = 'NS-1',
            ABT_Amount_Paid__c = 10
        );
        // A Created invoice with no total -> eligible for reconcilePending.
        insert new ABT_Invoice__c(
            Name = 'RECONCILE',
            ABT_Stripe_Invoice_Id__c = 'in_reconcile',
            ABT_Stripe_Processing_Status__c = 'Created',
            ABT_Amount_Paid__c = 20
        );
        Test.startTest();
        Integer pending = ABT_StripeInvoiceRetryScheduler.enqueuePending();
        Integer reconcile = ABT_StripeInvoiceRetryScheduler.reconcilePending();
        Test.stopTest();
        System.assertEquals(1, pending, 'one Queued no-id invoice should be picked up');
        System.assertEquals(1, reconcile, 'one Created total-null invoice should be picked up');
    }

    @isTest
    static void execute_runsFullSweep() {
        Test.startTest();
        new ABT_StripeInvoiceRetryScheduler().execute(null);
        Test.stopTest();
        // execute() chains heal -> enqueue -> reconcile; assertion is that it completes without error.
        System.assert(true);
    }
}