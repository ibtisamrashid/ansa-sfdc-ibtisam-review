/** Populates a direct Account lookup used by the portal buyer Sharing Set. */
public without sharing class SequenceAccountSharingHandler {
  public static void populateAccount(List<Sequence__c> sequences) {
    populateAccount(sequences, null);
  }

  public static void populateAccount(
    List<Sequence__c> sequences,
    Map<Id, Sequence__c> oldSequences
  ) {
    // Recompute derived sharing when a sequence moves to another quote/order.
    // Uploads with an explicit account and unchanged links retain their account.
    if (oldSequences != null) {
      for (Sequence__c sequence : sequences) {
        Sequence__c previous = oldSequences.get(sequence.Id);
        if (
          previous != null &&
          (previous.Quote_Request_Line_Item__c !=
          sequence.Quote_Request_Line_Item__c ||
          previous.Quote_Line_Item__c != sequence.Quote_Line_Item__c ||
          previous.Order_Product__c != sequence.Order_Product__c)
        )
          sequence.Sequence_Account__c = null;
      }
    }
    Set<Id> requestLineItemIds = new Set<Id>();
    Set<Id> quoteLineItemIds = new Set<Id>();
    Set<Id> orderItemIds = new Set<Id>();

    for (Sequence__c sequence : sequences) {
      if (sequence.Sequence_Account__c != null) {
        continue;
      }
      if (sequence.Quote_Request_Line_Item__c != null) {
        requestLineItemIds.add(sequence.Quote_Request_Line_Item__c);
      }
      if (sequence.Quote_Line_Item__c != null) {
        quoteLineItemIds.add(sequence.Quote_Line_Item__c);
      }
      if (sequence.Order_Product__c != null) {
        orderItemIds.add(sequence.Order_Product__c);
      }
    }

    Map<Id, Id> accountByRequestLineItemId = new Map<Id, Id>();
    if (!requestLineItemIds.isEmpty()) {
      for (ABT_Quote_Request_Lineitem__c lineItem : [
        SELECT Id, ABT_Quote_Request__r.ABT_Account__c
        FROM ABT_Quote_Request_Lineitem__c
        WHERE Id IN :requestLineItemIds
      ]) {
        accountByRequestLineItemId.put(
          lineItem.Id,
          lineItem.ABT_Quote_Request__r == null
            ? null
            : lineItem.ABT_Quote_Request__r.ABT_Account__c
        );
      }
    }

    Map<Id, Id> accountByQuoteLineItemId = new Map<Id, Id>();
    if (!quoteLineItemIds.isEmpty()) {
      for (QuoteLineItem lineItem : [
        SELECT Id, Quote.AccountId
        FROM QuoteLineItem
        WHERE Id IN :quoteLineItemIds
      ]) {
        accountByQuoteLineItemId.put(
          lineItem.Id,
          lineItem.Quote == null ? null : lineItem.Quote.AccountId
        );
      }
    }

    Map<Id, Id> accountByOrderItemId = new Map<Id, Id>();
    if (!orderItemIds.isEmpty()) {
      for (OrderItem lineItem : [
        SELECT Id, Order.AccountId
        FROM OrderItem
        WHERE Id IN :orderItemIds
      ]) {
        accountByOrderItemId.put(
          lineItem.Id,
          lineItem.Order == null ? null : lineItem.Order.AccountId
        );
      }
    }

    for (Sequence__c sequence : sequences) {
      if (sequence.Sequence_Account__c != null) {
        continue;
      }
      Id accountId = sequence.Quote_Request_Line_Item__c == null
        ? null
        : accountByRequestLineItemId.get(sequence.Quote_Request_Line_Item__c);
      if (accountId == null && sequence.Quote_Line_Item__c != null) {
        accountId = accountByQuoteLineItemId.get(sequence.Quote_Line_Item__c);
      }
      if (accountId == null && sequence.Order_Product__c != null) {
        accountId = accountByOrderItemId.get(sequence.Order_Product__c);
      }
      sequence.Sequence_Account__c = accountId;
    }
  }
}
