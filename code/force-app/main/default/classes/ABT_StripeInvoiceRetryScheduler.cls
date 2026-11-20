/**
 * Bounded safety-net sweep for queued, unclaimed invoices and post-creation
 * reconciliation. Failed or ambiguous operations are not automatically replayed.
 */
public with sharing class ABT_StripeInvoiceRetryScheduler implements Schedulable {

    // Keep each sweep small so one processor chain never approaches limits collectively.
    @TestVisible private static Integer BATCH_SIZE = 8;

    public void execute(SchedulableContext ctx) {
        flagInterrupted();
        healBilledStatus();
        enqueuePending();
        reconcilePending();
    }

    /** Surface interrupted jobs without replaying an uncertain external request. */
    public static Integer flagInterrupted() {
        List<ABT_Invoice__c> processing = [SELECT Id, ABT_Stripe_Worker_Id__c
            FROM ABT_Invoice__c WHERE ABT_Stripe_Processing_Status__c = 'Processing'
            AND ABT_Stripe_Worker_Id__c != null LIMIT 500 FOR UPDATE];
        Set<Id> jobIds = new Set<Id>();
        for (ABT_Invoice__c inv : processing) jobIds.add((Id) inv.ABT_Stripe_Worker_Id__c);
        Map<Id, AsyncApexJob> jobs = new Map<Id, AsyncApexJob>([SELECT Id, Status FROM AsyncApexJob WHERE Id IN :jobIds]);
        List<ABT_Invoice__c> updates = new List<ABT_Invoice__c>();
        Set<String> active = new Set<String>{'Queued', 'Holding', 'Preparing', 'Processing'};
        for (ABT_Invoice__c inv : processing) {
            AsyncApexJob owner = jobs.get((Id) inv.ABT_Stripe_Worker_Id__c);
            if (owner == null || !active.contains(owner.Status)) {
                updates.add(new ABT_Invoice__c(Id = inv.Id, ABT_Stripe_Processing_Status__c = 'Review',
                    ABT_Stripe_Error__c = 'Stripe worker stopped before completion. Reconcile Stripe before retrying.'));
            }
        }
        update updates;
        return updates.size();
    }

    /** Relabel only when delivery/payment completion is recorded, not merely an ID or URL. */
    public static Integer healBilledStatus() {
        List<ABT_Invoice__c> mislabeled = [
            SELECT Id, ABT_Stripe_Error__c, Recovery_Sent_At__c, ABT_Status__c
            FROM ABT_Invoice__c
            WHERE ABT_Stripe_Invoice_Id__c != null
              AND ABT_Stripe_Payment_Link__c != null
              AND Sent_to_Stripe__c = true
              AND ABT_Stripe_Processing_Status__c IN ('Failed', 'Processing', 'Queued')
            LIMIT 500
        ];
        if (mislabeled.isEmpty()) {
            return 0;
        }
        List<ABT_Invoice__c> upd = new List<ABT_Invoice__c>();
        for (ABT_Invoice__c inv : mislabeled) {
            if (String.isBlank(inv.ABT_Stripe_Error__c) && (inv.Recovery_Sent_At__c != null || inv.ABT_Status__c == 'Paid')) {
                upd.add(new ABT_Invoice__c(Id = inv.Id, ABT_Stripe_Processing_Status__c = 'Created'));
            }
        }
        update upd;
        return upd.size();
    }

    /**
     * Post-creation reconcile sweep: pick up invoices that were Created but whose authoritative
     * Stripe total has not been persisted yet, and reconcile them in their own callout-first
     * transaction (ABT_StripeInvoiceReconcileJob). Decoupled from creation so we never call out
     * after the creation subflow's uncommitted DML.
     */
    public static Integer reconcilePending() {
        List<ABT_Invoice__c> toReconcile = [
            SELECT Id
            FROM ABT_Invoice__c
            WHERE ABT_Stripe_Invoice_Id__c != null
              AND ABT_Stripe_Processing_Status__c = 'Created'
              AND ABT_Stripe_Invoice_Total__c = null
            ORDER BY CreatedDate DESC
            LIMIT :BATCH_SIZE
        ];
        if (toReconcile.isEmpty()) {
            return 0;
        }
        List<Id> ids = new List<Id>();
        for (ABT_Invoice__c inv : toReconcile) {
            ids.add(inv.Id);
        }
        if (!Test.isRunningTest()) {
            System.enqueueJob(new ABT_StripeInvoiceReconcileJob(ids));
        }
        return ids.size();
    }

    /** Also callable directly (e.g. from an anonymous-apex recovery wave). */
    public static Integer enqueuePending() {
        Integer maxRetries = ABT_StripeInvoiceProcessor.MAX_RETRIES;
        List<ABT_Invoice__c> pending = [
            SELECT Id
            FROM ABT_Invoice__c
            WHERE ABT_Stripe_Invoice_Id__c = null
              AND Sent_to_Stripe__c = false
              AND ABT_Netsuite_Invoice_Id__c != null
              AND ABT_Amount_Paid__c > 0
              AND ABT_Stripe_Processing_Status__c = 'Queued'
              AND ABT_Stripe_Worker_Id__c = null
              AND (ABT_Stripe_Retry_Count__c = null OR ABT_Stripe_Retry_Count__c < :maxRetries)
            ORDER BY CreatedDate ASC
            LIMIT :BATCH_SIZE
        ];
        if (pending.isEmpty()) {
            return 0;
        }
        List<Id> ids = new List<Id>();
        for (ABT_Invoice__c inv : pending) {
            ids.add(inv.Id);
        }
        if (!Test.isRunningTest()) {
            System.enqueueJob(new ABT_StripeInvoiceProcessor(ids));
        }
        return ids.size();
    }
}
