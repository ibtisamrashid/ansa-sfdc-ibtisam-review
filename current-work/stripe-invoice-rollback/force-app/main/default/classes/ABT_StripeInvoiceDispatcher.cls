/**
 * PAN-35652
 * Invocable entry point called from ABT_Create_Payment_Link_On_Invoice (replacing the
 * inline Early_Lock + Generate subflow). Flow bulkifies this call, so it receives all
 * invoices in the scheduled-path batch at once. It marks them Queued and enqueues a
 * SINGLE processor chain that handles them one-per-transaction.
 *
 * The chain gives immediacy; ABT_StripeInvoiceRetryScheduler is the safety net.
 */
public with sharing class ABT_StripeInvoiceDispatcher {

    // Test seam: lets a unit test assert the Queued stamp without the async processor
    // running the live managed-package callout subflow.
    @TestVisible private static Boolean skipEnqueue = false;

    @InvocableMethod(
        label='Enqueue Invoice for Stripe Creation'
        description='PAN-35652: hand a qualifying invoice to the async Stripe-invoice processor (one per transaction).'
    )
    public static void enqueue(List<Id> invoiceIds) {
        if (invoiceIds == null || invoiceIds.isEmpty()) {
            return;
        }
        // Dedupe and re-confirm each invoice still needs creation (idempotent entry).
        Set<Id> ids = new Set<Id>(invoiceIds);
        List<ABT_Invoice__c> toQueue = [
            SELECT Id
            FROM ABT_Invoice__c
            WHERE Id IN :ids
              AND ABT_Stripe_Invoice_Id__c = null
              AND Sent_to_Stripe__c = false
              AND ABT_Amount_Paid__c > 0
              AND ABT_Netsuite_Invoice_Id__c != null
        ];
        if (toQueue.isEmpty()) {
            return;
        }

        List<Id> queuedIds = new List<Id>();
        for (ABT_Invoice__c inv : toQueue) {
            inv.ABT_Stripe_Processing_Status__c = 'Queued';
            queuedIds.add(inv.Id);
        }
        update toQueue;

        // Best-effort immediate enqueue. If the current context can't chain a Queueable
        // (e.g. limit reached), the scheduler will still pick these up because they are
        // marked Queued and remain unlocked.
        try {
            if (!skipEnqueue && !queuedIds.isEmpty()
                    && Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
                System.enqueueJob(new ABT_StripeInvoiceProcessor(queuedIds));
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN,
                'ABT_StripeInvoiceDispatcher enqueue deferred to scheduler: ' + e.getMessage());
        }
    }
}