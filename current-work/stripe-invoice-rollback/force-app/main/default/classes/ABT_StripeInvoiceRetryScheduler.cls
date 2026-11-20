/**
 * PAN-35652 / PAN-35654
 * Safety-net sweep. Re-enqueues any invoice that still needs a Stripe invoice and is
 * under the retry cap, in a bounded batch so the reprocessing itself cannot recreate
 * the batch-concurrency callout failure (PAN-35684).
 *
 * This is ALSO the mechanism the PAN-35654 recovery uses: resetting the affected
 * invoices to Queued and letting this sweep them one-per-transaction, in waves.
 *
 * Schedule (example, hourly):
 *   System.schedule('ABT Stripe Invoice Retry',
 *       '0 0 * * * ?', new ABT_StripeInvoiceRetryScheduler());
 */
public with sharing class ABT_StripeInvoiceRetryScheduler implements Schedulable {

    // Keep each sweep small so one processor chain never approaches limits collectively.
    @TestVisible private static Integer BATCH_SIZE = 8;

    public void execute(SchedulableContext ctx) {
        healBilledStatus();
        enqueuePending();
        reconcilePending();
    }

    /**
     * PAN-35652 status-heal. The creation subflow populates ABT_Stripe_Invoice_Id__c and the
     * payment link inside its own (new/deferred) transaction, which can commit AFTER the
     * processor's synchronous re-read already marked the invoice 'Failed' — a false negative
     * (the money moved and the link exists; only the status label is wrong). An invoice that
     * carries BOTH a Stripe invoice id AND a payment link is finalized + sent = billed, so
     * relabel it 'Created'. This is a PURE relabel of already-billed records: no callouts and
     * no field write that could re-bill or re-create anything. Runs first each sweep so the
     * subsequent reconcilePending() can then persist the authoritative total.
     */
    public static Integer healBilledStatus() {
        List<ABT_Invoice__c> mislabeled = [
            SELECT Id
            FROM ABT_Invoice__c
            WHERE ABT_Stripe_Invoice_Id__c != null
              AND ABT_Stripe_Payment_Link__c != null
              AND ABT_Stripe_Processing_Status__c IN ('Failed', 'Processing', 'Queued')
            LIMIT 500
        ];
        if (mislabeled.isEmpty()) {
            return 0;
        }
        List<ABT_Invoice__c> upd = new List<ABT_Invoice__c>();
        for (ABT_Invoice__c inv : mislabeled) {
            upd.add(new ABT_Invoice__c(Id = inv.Id, ABT_Stripe_Processing_Status__c = 'Created'));
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
              AND ABT_Stripe_Processing_Status__c IN ('Queued', 'Failed')
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