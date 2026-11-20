/**
 * PAN-35652  (root cause refined by PAN-35684)
 *
 * Async Stripe-invoice creator. Processes ONE invoice per Queueable execution so
 * that each invoice gets a fresh 100-callout budget. This is the fix for the
 * DOMINANT failure trigger found in PAN-35684: many small invoices are bulk-inserted
 * together and their record-triggered scheduled paths ran in one shared-limit
 * transaction, collectively blowing the callout limit (138 of 150 affected invoices
 * had only 1-5 line items — batch concurrency, not per-invoice volume).
 *
 * It reuses the existing, working ABT_Generate_Stripe_Payment_Link subflow rather
 * than re-implementing the Stripe calls, and only marks Sent_to_Stripe = true after
 * a Stripe Invoice Id is confirmed — so a failure leaves the record RETRYABLE
 * instead of permanently locked (the old Early_Lock defect).
 *
 * The chain processes invoices one at a time; the retry scheduler
 * (ABT_StripeInvoiceRetryScheduler) is the safety net that re-enqueues anything left
 * Queued/Failed under the retry cap.
 */
public with sharing class ABT_StripeInvoiceProcessor implements Queueable, Database.AllowsCallouts {

    public static final Integer MAX_RETRIES = 3;
    private final List<Id> invoiceIds;

    public ABT_StripeInvoiceProcessor(List<Id> invoiceIds) {
        this.invoiceIds = (invoiceIds == null) ? new List<Id>() : invoiceIds;
    }

    public void execute(QueueableContext ctx) {
        if (invoiceIds.isEmpty()) {
            return;
        }
        Id current = invoiceIds[0];
        List<Id> remaining = new List<Id>();
        for (Integer i = 1; i < invoiceIds.size(); i++) {
            remaining.add(invoiceIds[i]);
        }

        try {
            processOne(current);
        } catch (Exception e) {
            // NOTE: an uncatchable governor LimitException (a single oversized invoice
            // that alone exceeds 100 callouts) will kill this execution and NOT reach
            // here — but because we lock only on success, the invoice stays retryable
            // and the scheduler will re-pick it. Catchable Stripe API faults land here.
            handleFailure(current, ABT_StripeErrorLogger.REASON_API_ERROR, e.getMessage());
        }

        // Chain to the next invoice in a brand-new transaction (fresh callout budget).
        if (!remaining.isEmpty() && !Test.isRunningTest()) {
            System.enqueueJob(new ABT_StripeInvoiceProcessor(remaining));
        }
    }

    private void processOne(Id invoiceId) {
        // FOR UPDATE serialises concurrent chains/recovery waves for the SAME invoice: a second
        // processor blocks here until the first commits, then re-reads the now-populated Stripe
        // Invoice Id and the guard below skips it — preventing a double-create / double-bill.
        // (Verified in-org: a row lock does NOT trigger 'uncommitted work pending' on a later callout.)
        List<ABT_Invoice__c> found = [
            SELECT Id, Sent_to_Stripe__c, ABT_Stripe_Invoice_Id__c, ABT_Netsuite_Invoice_Id__c,
                   ABT_Amount_Paid__c, ABT_Stripe_Retry_Count__c
            FROM ABT_Invoice__c
            WHERE Id = :invoiceId
            LIMIT 1
            FOR UPDATE
        ];
        if (found.isEmpty()) {
            return;
        }
        ABT_Invoice__c inv = found[0];

        // Idempotency guard (replaces the removed Early_Lock): never create twice.
        if (inv.ABT_Stripe_Invoice_Id__c != null || inv.Sent_to_Stripe__c == true) {
            update new ABT_Invoice__c(Id = inv.Id, ABT_Stripe_Processing_Status__c = 'Created');
            return;
        }
        // Zero-amount invoices are handled by the flow's $0 skip; nothing to do here.
        if (inv.ABT_Amount_Paid__c == null || inv.ABT_Amount_Paid__c <= 0) {
            update new ABT_Invoice__c(Id = inv.Id, ABT_Stripe_Processing_Status__c = 'Skipped');
            return;
        }

        // CRITICAL: no DML may precede the creation callout. The row is already 'Queued'; a
        // pre-callout status update would make the subflow's first Stripe call throw
        // 'You have uncommitted work pending. Please commit or rollback before calling out'.
        // (Verified in-org — this was the reason no Stripe invoice was ever created.)
        String flowError = runCreationSubflow(invoiceId);

        // Confirm the outcome from the database, not from the flow's optimism.
        ABT_Invoice__c after = [
            SELECT Id, Name, ABT_Stripe_Invoice_Id__c, ABT_Amount_Paid__c
            FROM ABT_Invoice__c WHERE Id = :invoiceId LIMIT 1
        ];

        if (after.ABT_Stripe_Invoice_Id__c != null) {
            // Lock in success — DML ONLY here (no callout). Reconciliation (a Stripe retrieve = a
            // callout, on top of the subflow's uncommitted DML) is decoupled into its OWN
            // transaction (ABT_StripeInvoiceReconcileJob, swept by ABT_StripeInvoiceRetryScheduler)
            // so we never call out after DML. The authoritative total is persisted there.
            update new ABT_Invoice__c(
                Id = after.Id,
                Sent_to_Stripe__c = true,
                ABT_Stripe_Processing_Status__c = 'Created'
            );
        } else {
            String reason = String.isBlank(flowError)
                ? 'Creation subflow finished without a Stripe Invoice Id (likely a callout-limit or unhandled path).'
                : flowError;
            handleFailure(invoiceId, ABT_StripeErrorLogger.REASON_API_ERROR, reason);
        }
    }

    private void handleFailure(Id invoiceId, String reason, String message) {
        Integer retries = 0;
        Decimal amount;
        for (ABT_Invoice__c i : [
            SELECT ABT_Stripe_Retry_Count__c, ABT_Amount_Paid__c FROM ABT_Invoice__c WHERE Id = :invoiceId
        ]) {
            retries = (i.ABT_Stripe_Retry_Count__c == null) ? 0 : Integer.valueOf(i.ABT_Stripe_Retry_Count__c);
            amount = i.ABT_Amount_Paid__c;
        }
        retries += 1;

        update new ABT_Invoice__c(
            Id = invoiceId,
            Sent_to_Stripe__c = false,                 // stays retryable — never optimistically locked
            ABT_Stripe_Processing_Status__c = 'Failed',
            ABT_Stripe_Retry_Count__c = retries
        );

        ABT_Stripe_Error_Log__c log = ABT_StripeErrorLogger.build(
            ABT_StripeErrorLogger.SRC_INVOICE_CREATION, reason, message,
            invoiceId, null, null, null, null, amount
        );
        log.Retry_Count__c = retries;
        log.Needs_Manual_Review__c = (retries >= MAX_RETRIES);
        ABT_StripeErrorLogger.logAll(new List<ABT_Stripe_Error_Log__c>{ log });
    }

    // Test seam: a unit test sets this to simulate a successful Stripe creation; left null
    // simulates a failed creation. The live managed-package callout subflow cannot run in a test.
    @TestVisible private static String testSimulatedStripeId = null;

    /**
     * Runs the existing creation subflow, which performs all Stripe callouts for THIS
     * invoice inside THIS transaction -> a full 100-callout budget for one invoice.
     * Returns the flow's FlowError output, if any. Isolated for unit-test coverage of the
     * downstream success/failure handling.
     */
    private String runCreationSubflow(Id invoiceId) {
        if (Test.isRunningTest()) {
            if (testSimulatedStripeId != null) {
                update new ABT_Invoice__c(Id = invoiceId, ABT_Stripe_Invoice_Id__c = testSimulatedStripeId);
            }
            return null;
        }
        Flow.Interview flow = Flow.Interview.createInterview(
            'ABT_Generate_Stripe_Payment_Link',
            new Map<String, Object>{ 'recordId' => String.valueOf(invoiceId) }
        );
        flow.start();
        return (String) flow.getVariableValue('FlowError');
    }

}