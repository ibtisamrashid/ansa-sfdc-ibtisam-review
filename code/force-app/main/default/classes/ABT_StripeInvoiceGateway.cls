/** Invoice-only payment-method check using the existing Stripe connector. */
public with sharing class ABT_StripeInvoiceGateway {
  public class StripeActionException extends Exception {
  }

  public interface Transport {
    Map<String, Object> invoke(
      String actionName,
      Map<String, Object> parameters
    );
  }
  @TestVisible
  private static Transport testTransport;

  public static Map<String, Object> invoke(
    String actionName,
    Map<String, Object> parameters
  ) {
    if (Test.isRunningTest()) {
      if (testTransport == null) {
        throw new StripeActionException(
          'A synthetic Stripe transport is required in tests.'
        );
      }
      return testTransport.invoke(actionName, parameters);
    }
    Invocable.Action action = Invocable.Action.createCustomAction(
      'apex',
      actionName
    );
    for (String key : parameters.keySet()) {
      action.setInvocationParameter(key, parameters.get(key));
    }
    List<Invocable.Action.Result> results = action.invoke();
    if (results == null || results.size() != 1 || !results[0].isSuccess()) {
      // Do not copy private Stripe payloads into the application log.
      throw new StripeActionException(
        'Stripe action failed: ' +
          actionName +
          '. Review connector logs before retrying.'
      );
    }
    return results[0].getOutputParameters();
  }

  public class PaymentCheck {
    @InvocableVariable(required=true) public String accountRecordId;
    @InvocableVariable(required=true) public String customer;
    @InvocableVariable(required=true) public String paymentMethod;
  }
  @InvocableMethod(callout=true label='Verify Invoice Payment Method' description='Verify or attach the invoice card to its existing Stripe customer before payment.')
  public static void verifyForFlow(List<PaymentCheck> requests) {
    for (PaymentCheck request : requests) verifyPaymentMethod(request.accountRecordId, request.customer, request.paymentMethod);
  }
  public static void verifyPaymentMethod(
    String accountId,
    String customer,
    String paymentMethod
  ) {
    if (String.isBlank(customer) || String.isBlank(paymentMethod)) {
      throw new StripeActionException(
        'A Stripe customer and payment method are required before charging.'
      );
    }
    Map<String, Object> parameters = new Map<String, Object>{
      'accountRecordId' => accountId,
      'paymentMethod' => paymentMethod
    };
    Map<String, Object> pm = invoke(
      'stripeGC__v01_GetPaymentMethods',
      parameters
    );
    String owner = customerId(pm.get('customer'));
    if (String.isBlank(owner)) {
      parameters.put('customer', customer);
      invoke('stripeGC__v01_PostPaymentMethodsAttach', parameters);
      parameters.remove('customer');
      pm = invoke('stripeGC__v01_GetPaymentMethods', parameters);
      owner = customerId(pm.get('customer'));
    }
    if (!customer.equals(owner)) {
      throw new StripeActionException(
        'Payment method ownership was not verified. No payment was attempted.'
      );
    }
  }

  public static String customerId(Object value) {
    if (value == null)
      return null;
    if (value instanceof String)
      return (String) value;
    Map<String, Object> expanded = (Map<String, Object>) JSON.deserializeUntyped(
      JSON.serialize(value)
    );
    return (String) expanded.get('id');
  }
}
