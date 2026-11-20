/**
 * Runs the existing billing Flow unchanged in its own callout transaction.
 * A preceding DML-only transaction commits ownership before any Stripe call.
 * Ambiguous failures are held for review rather than recreated automatically.
 */
public with sharing class ABT_StripeInvoiceProcessor implements Queueable, Database.AllowsCallouts {
    public static final Integer MAX_RETRIES = 3;
    private List<Id> invoiceIds;
    private Boolean claimed;
    @TestVisible private static Boolean skipEnqueue = false;
    @TestVisible private static String testSimulatedStripeId;
    @TestVisible private static Boolean testSimulatedSent = false;
    @TestVisible private static String testSimulatedError;
    @TestVisible private static Integer testFlowCalls = 0;

    public ABT_StripeInvoiceProcessor(List<Id> invoiceIds) { this(invoiceIds, false); }
    private ABT_StripeInvoiceProcessor(List<Id> invoiceIds, Boolean claimed) {
        this.invoiceIds = invoiceIds == null ? new List<Id>() : invoiceIds.clone();
        this.claimed = claimed;
    }
    public void execute(QueueableContext context) {
        if (invoiceIds.isEmpty()) return;
        if (!claimed) { claimNext(); return; }
        Id current = invoiceIds[0];
        try { processOne(current, context); }
        catch (Exception error) {
            handleFailure(current, 'Billing Flow failed; inspect the failed interview before retrying.');
        }
        List<Id> remaining = invoiceIds.clone(); remaining.remove(0);
        if (!remaining.isEmpty() && !Test.isRunningTest()
                && Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
            System.enqueueJob(new ABT_StripeInvoiceProcessor(remaining));
        }
        // If another existing Flow consumes the async slot, remaining Queued
        // invoices are picked up by the existing scheduler.
    }
    private void claimNext() {
        while (!invoiceIds.isEmpty()) {
            Id current = invoiceIds[0];
            List<ABT_Invoice__c> found = [SELECT Id, Sent_to_Stripe__c, ABT_Status__c,
                ABT_Stripe_Invoice_Id__c, ABT_Stripe_Worker_Id__c, ABT_Stripe_Processing_Status__c,
                ABT_Amount_Paid__c, ABT_Netsuite_Invoice_Id__c
                FROM ABT_Invoice__c WHERE Id = :current LIMIT 1 FOR UPDATE];
            if (found.isEmpty() || found[0].Sent_to_Stripe__c == true || found[0].ABT_Status__c == 'Paid'
                    || String.isNotBlank(found[0].ABT_Stripe_Invoice_Id__c)
                    || String.isNotBlank(found[0].ABT_Stripe_Worker_Id__c)
                    || String.isBlank(found[0].ABT_Netsuite_Invoice_Id__c)
                    || found[0].ABT_Amount_Paid__c == null || found[0].ABT_Amount_Paid__c <= 0
                    || (found[0].ABT_Stripe_Processing_Status__c != null && found[0].ABT_Stripe_Processing_Status__c != 'Queued')) {
                invoiceIds.remove(0); continue;
            }
            String jobId = Test.isRunningTest() && skipEnqueue ? '707000000000001AAA'
                : System.enqueueJob(new ABT_StripeInvoiceProcessor(invoiceIds, true));
            update new ABT_Invoice__c(Id = current, ABT_Stripe_Worker_Id__c = jobId,
                ABT_Stripe_Processing_Status__c = 'Processing');
            claimed = true;
            return;
        }
    }
    private void processOne(Id invoiceId, QueueableContext context) {
        ABT_Invoice__c inv = [SELECT Id, Sent_to_Stripe__c, ABT_Status__c, ABT_Stripe_Invoice_Id__c,
            ABT_Stripe_Worker_Id__c, ABT_Stripe_Processing_Status__c, ABT_Payment_Method__c,
            ABT_Billing_Account_Id__r.ABT_Stripe_Customer_Id__c, ABT_Tax_Percentage__c, ABT_Shipping_Cost__c
            FROM ABT_Invoice__c WHERE Id = :invoiceId];
        String jobId = context == null && Test.isRunningTest() ? '707000000000001AAA'
            : (context == null ? null : String.valueOf(context.getJobId()));
        if (String.isBlank(jobId) || !jobId.equals(inv.ABT_Stripe_Worker_Id__c)
                || inv.ABT_Stripe_Processing_Status__c != 'Processing') return;
        if (inv.Sent_to_Stripe__c == true || inv.ABT_Status__c == 'Paid') return;
        if (String.isNotBlank(inv.ABT_Stripe_Invoice_Id__c)) {
            handleFailure(invoiceId, 'An existing Stripe invoice must be reconciled; it will not be recreated.'); return;
        }
        // Do not start an invoice that cannot fit the existing Flow's callout budget.
        // This is a guard only: no prices, quantities, tax, shipping or amounts change.
        Integer lines = [SELECT COUNT() FROM ABT_InvoiceLineItem__c WHERE ABT_Invoice__c = :invoiceId AND ABT_Product__c != null];
        Integer productCalls = lines;
        if (lines >= 20) productCalls = [SELECT ABT_Product__c FROM ABT_InvoiceLineItem__c
            WHERE ABT_Invoice__c = :invoiceId AND ABT_Product__c != null GROUP BY ABT_Product__c].size();
        Integer estimate = productCalls * 5 + 1 + (inv.ABT_Payment_Method__c == 'Credit Card' ? 6 : 3) + 2;
        if (String.isBlank(inv.ABT_Billing_Account_Id__r?.ABT_Stripe_Customer_Id__c)) estimate++;
        if (inv.ABT_Tax_Percentage__c > 0) estimate += 2;
        if (inv.ABT_Shipping_Cost__c > 0) estimate += 2;
        if (lines == 0 || estimate > Limits.getLimitCallouts() - Limits.getCallouts()) {
            handleFailure(invoiceId, 'Invoice requires review before running the existing Flow: missing lines or insufficient callout budget.'); return;
        }
        // Ownership is already committed. There is NO DML before this Flow call.
        String flowError = runCreationSubflow(invoiceId, jobId);
        ABT_Invoice__c after = [SELECT Id, ABT_Stripe_Invoice_Id__c, ABT_Stripe_Payment_Link__c,
            Sent_to_Stripe__c, ABT_Stripe_Error__c FROM ABT_Invoice__c WHERE Id = :invoiceId];
        if (String.isBlank(flowError) && String.isBlank(after.ABT_Stripe_Error__c)
                && String.isNotBlank(after.ABT_Stripe_Invoice_Id__c)
                && String.isNotBlank(after.ABT_Stripe_Payment_Link__c) && after.Sent_to_Stripe__c == true) {
            update new ABT_Invoice__c(Id = invoiceId, ABT_Stripe_Processing_Status__c = 'Created');
        } else {
            handleFailure(invoiceId, 'Billing Flow did not confirm finalization and delivery/payment. Inspect its failed interview and existing Stripe invoice.');
        }
    }
    private static void handleFailure(Id invoiceId, String message) {
        ABT_Invoice__c inv = [SELECT ABT_Stripe_Retry_Count__c FROM ABT_Invoice__c WHERE Id = :invoiceId];
        Integer attempts = inv.ABT_Stripe_Retry_Count__c == null ? 1 : Integer.valueOf(inv.ABT_Stripe_Retry_Count__c) + 1;
        update new ABT_Invoice__c(Id = invoiceId, ABT_Stripe_Processing_Status__c = 'Review',
            ABT_Stripe_Retry_Count__c = attempts);
        ABT_Stripe_Error_Log__c entry = ABT_StripeErrorLogger.build(ABT_StripeErrorLogger.SRC_INVOICE_CREATION,
            ABT_StripeErrorLogger.REASON_API_ERROR, message, invoiceId, null, null, null, null, null);
        entry.Needs_Manual_Review__c = true;
        ABT_StripeErrorLogger.logAll(new List<ABT_Stripe_Error_Log__c>{entry});
    }
    private String runCreationSubflow(Id invoiceId, String jobId) {
        if (Test.isRunningTest()) {
            testFlowCalls++;
            if (testSimulatedStripeId != null) update new ABT_Invoice__c(Id = invoiceId,
                ABT_Stripe_Invoice_Id__c = testSimulatedStripeId, Sent_to_Stripe__c = testSimulatedSent,
                ABT_Stripe_Payment_Link__c = testSimulatedSent ? 'https://example.invalid/invoice' : null,
                ABT_Stripe_Error__c = testSimulatedError);
            return testSimulatedError;
        }
        Flow.Interview flow = Flow.Interview.createInterview('ABT_Generate_Stripe_Payment_Link',
            new Map<String, Object>{'recordId' => String.valueOf(invoiceId), 'workerJobId' => jobId});
        flow.start();
        return (String) flow.getVariableValue('FlowError');
    }
}
