/**
 * Main portal Apex: quote requests, cart, checkout, order/account, vectors, collateral downloads.
 * LWC/flow entry point — cart DML is ABT_Cart_Service, Sequence writes are ABT_SequenceSyncService.
 * without sharing because community profiles otherwise miss addresses, INCO, fee add-ons, etc.
 */
public without sharing class ABT_Portal_Controller {
  /** Returned by {@link #createQuoteRequest} for portal new-quote wizard title/cart. */
  public class CreateQuoteRequestResult {
    @AuraEnabled
    public Id quoteRequestId;
    @AuraEnabled
    public String displayQuoteNumber;
  }

  /** Portal order detail header — loaded via Apex so community users get addresses/INCO without layout FLS gaps. */
  public class OrderPortalDetail {
    @AuraEnabled
    public String orderNumber;
    @AuraEnabled
    public String projectName;
    @AuraEnabled
    public String requestorName;
    @AuraEnabled
    public String orderPlaced;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String paymentMethod;
    @AuraEnabled
    public String poNumber;
    @AuraEnabled
    public String shippingMethod;
    @AuraEnabled
    public String incoTerms;
    @AuraEnabled
    public String billingAddress;
    @AuraEnabled
    public String shippingAddress;
    @AuraEnabled
    public String notes;
    @AuraEnabled
    public Decimal subtotal;
    @AuraEnabled
    public Decimal shipping;
    @AuraEnabled
    public Decimal packaging;
    @AuraEnabled
    public Decimal discount;
    @AuraEnabled
    public Decimal tax;
    @AuraEnabled
    public Decimal total;
    @AuraEnabled
    public Boolean taxExempt;
    @AuraEnabled
    public Boolean canEditTaxExempt;
    @AuraEnabled
    public Boolean acceptPartial;
    @AuraEnabled
    public Boolean canEditAcceptPartial;
    @AuraEnabled
    public String ansaQuoteNumber;
    @AuraEnabled
    public String trackingNumber;
  }

  /** Active blanket PO for portal checkout — looked up by account (and optional PO number). */
  public class BpoLookupResult {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String poNumber;
    @AuraEnabled
    public Decimal remainingAmount;
  }

  /**
   * Active BPO for checkout. Optional poNumber pins a specific PO; otherwise the
   * earliest still-open one with remaining balance. End_Date must be today or later.
   */
  @AuraEnabled
  public static BpoLookupResult getActiveBpoForAccount(
    Id accountId,
    String poNumber
  ) {
    if (accountId == null) {
      return null;
    }

    List<Blanket_Purchase_Orders__c> bpos;
    if (String.isNotBlank(poNumber)) {
      bpos = [
        SELECT Id, PO_Number__c, Total_Amount_Remaining__c
        FROM Blanket_Purchase_Orders__c
        WHERE
          Account__c = :accountId
          AND PO_Number__c = :poNumber.trim()
          AND End_Date__c >= :Date.today()
          AND Total_Amount_Remaining__c > 0
        ORDER BY End_Date__c ASC
        LIMIT 1
      ];
    } else {
      bpos = [
        SELECT Id, PO_Number__c, Total_Amount_Remaining__c
        FROM Blanket_Purchase_Orders__c
        WHERE
          Account__c = :accountId
          AND End_Date__c >= :Date.today()
          AND Total_Amount_Remaining__c > 0
        ORDER BY End_Date__c ASC
        LIMIT 1
      ];
    }

    if (bpos.isEmpty()) {
      return null;
    }

    Blanket_Purchase_Orders__c bpo = bpos[0];
    BpoLookupResult result = new BpoLookupResult();
    result.id = bpo.Id;
    result.poNumber = bpo.PO_Number__c;
    result.remainingAmount = bpo.Total_Amount_Remaining__c;
    return result;
  }

  /**
   * Portal user + Account fields for header/account screens: INCO, first-time
   * company flag, Calendly, invoice email, Stripe customer Id, always-accept-partial.
   */
  @AuraEnabled(cacheable=true)
  public static User getUserDetailsById(Id userId) {
    system.debug(userId);
    List<User> users = [
      SELECT
        Id,
        name,
        Email,
        createddate,
        Alias,
        ContactId,
        AccountId,
        CommunityNickname,
        Calendly_Link__c,
        Contact.ABT_Active__c,
        Contact.ABT_Verification_Status__c,
        Contact.Promo_Code__c,
        Contact.Invoice_Email__c,
        Account.ABT_Active__c,
        Account.ABT_Verification_Status__c,
        Account.ABT_Stripe_Customer_Id__c,
        Account.ABT_Is_First_Time_info_Filled__c,
        Account.IncoTerms__c,
        Account.Always_Accept_Partial__c,
        Account.IDT_Channel_Partner__c
      FROM user
      WHERE id = :userId
    ];
    System.debug(users[0]);
    return users[0];
  }

  /**
   * Account invoice-email on the Contact. Used from the account page so AP
   * invoices go to the right inbox.
   */
  @AuraEnabled
  public static void updateContactInvoiceEmail(
    Id contactId,
    String invoiceEmail
  ) {
    try {
      Contact contactToUpdate = new Contact(
        Id = contactId,
        Invoice_Email__c = sanitizeCheckoutInvoiceEmail(invoiceEmail)
      );
      update contactToUpdate;
    } catch (Exception e) {
      throw new AuraHandledException(
        'Error updating contact invoice email: ' + e.getMessage()
      );
    }
  }
  /**
   * Quote-detail URLs sometimes pass Ansa quote # instead of the Salesforce Id.
   * Returns the QR Id so the LWC can load getQuoteRequestById.
   */
  @AuraEnabled(cacheable=true)
  public static Id resolveQuoteRequestIdFromIdentifier(String identifier) {
    if (String.isBlank(identifier)) {
      return null;
    }

    List<ABT_Quote_Request__c> quoteRequests = [
      SELECT Id
      FROM ABT_Quote_Request__c
      WHERE Ansa_Quote_Number__c = :identifier
      LIMIT 1
    ];

    return quoteRequests.isEmpty() ? null : quoteRequests[0].Id;
  }
  /**
   * Quote Request header for the new-quote / quote-detail wizard: product, project,
   * addresses, stage, promo, packaging. Throws if the user can't see the record.
   */
  @AuraEnabled(cacheable=true)
  public static ABT_Quote_Request__c getQuoteRequestById(Id quoteRequestId) {
    if (quoteRequestId == null) {
      throw new AuraHandledException('QuoteRequest ID cannoe null');
    }
    List<ABT_Quote_Request__c> quoteRequest = [
      SELECT
        Id,
        ABT_Product__c,
        ABT_Product_Name__c,
        ABT_Product__r.StockKeepingUnit,
        ABT_Customer_Project_Name__c,
        ABT_IsLineItemContainsFlag__c,
        ABT_Billing_Address_Lookup__r.Name,
        ABT_Billing_Address_Lookup__r.CompanyName,
        ABT_Billing_Address_Lookup__r.Street,
        ABT_Billing_Address_Lookup__r.City,
        ABT_Billing_Address_Lookup__r.State,
        ABT_Billing_Address_Lookup__r.Country,
        ABT_Billing_Address_Lookup__r.PostalCode,
        ABT_Shipping_Address_Lookup__r.Name,
        ABT_Shipping_Address_Lookup__r.CompanyName,
        ABT_Shipping_Address_Lookup__r.Street,
        ABT_Shipping_Address_Lookup__r.City,
        ABT_Shipping_Address_Lookup__r.State,
        ABT_Shipping_Address_Lookup__r.Country,
        ABT_Shipping_Address_Lookup__r.PostalCode,
        ABT_Payment_Method__c,
        ABT_Payment_Method_Lookup__c,
        // ABT_Shipping_Method__c,
        Shipping_Destination__c,
        ABT_Account__c,
        ABT_Account__r.Shipping_Destination__c,
        ABT_Account__r.IDT_Channel_Partner__c,
        ABT_Stage__c,
        ABT_Quote__c,
        ABT_Total_Price__c,
        Vector__c,
        Promo_Code__c,
        Promo_Code__r.Name,
        Promo_Code__r.Discount_Percentage__c,
        Request_Packaging__c
      FROM ABT_Quote_Request__c
      WHERE id = :quoteRequestId
    ];
    if (quoteRequest.isEmpty()) {
      throw new AuraHandledException(
        'Quote request not found or you do not have access.'
      );
    }
    return quoteRequest[0];
  }

  /**
   * Display quote id for portal new-quote UI. Prefers Ansa_Quote_Number__c once the
   * linked Quote exists; falls back to Quote_Number__c or auto-number Name (QR-######).
   */
  @AuraEnabled
  public static String getQuoteRequestDisplayQuoteNumber(Id quoteRequestId) {
    if (quoteRequestId == null) {
      return '';
    }
    List<ABT_Quote_Request__c> rows = [
      SELECT Name, Ansa_Quote_Number__c, Quote_Number__c
      FROM ABT_Quote_Request__c
      WHERE Id = :quoteRequestId
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      return '';
    }
    return resolveQuoteRequestDisplayNumber(rows[0]);
  }

  /** Strip the "Ansa" prefix from product names shown in the customer portal. */
  public static String formatPortalProductName(String productName) {
    if (String.isBlank(productName)) {
      return productName;
    }
    String trimmed = productName.trim();
    if (
      trimmed.length() > 5 && trimmed.substring(0, 5).equalsIgnoreCase('Ansa ')
    ) {
      return trimmed.substring(5).trim();
    }
    return trimmed;
  }

  /** True for glycerol stock add-on products (e.g. Glycerol Stock - Tubes / Plate). */
  public static Boolean isGlycerolStockProduct(String productName) {
    if (String.isBlank(productName)) {
      return false;
    }
    return productName.trim().toLowerCase().contains('glycerol stock');
  }

  /** True when SKU identifies Glycerol Stock fee product (GS-001). */
  public static Boolean isGlycerolStockSku(String sku) {
    return String.isNotBlank(sku) && 'GS-001'.equalsIgnoreCase(sku.trim());
  }

  /** True for Scale Up fee add-on products (SC-001 / legacy CS-200). */
  public static Boolean isScaleUpProduct(String productName, String sku) {
    if (String.isNotBlank(sku)) {
      String normalized = sku.trim().toUpperCase();
      if (normalized == 'SC-001' || normalized == 'CS-200') {
        return true;
      }
    }
    return String.isNotBlank(productName) &&
      productName.trim().toLowerCase().contains('scale up');
  }

  /**
   * Resolve SKU from line Product_SKU__c / Product_Code__c when those are fee addons,
   * then Product2.StockKeepingUnit, then any remaining line SKU/code.
   * Prod glycerol fee lines often reuse the DNA Product2 (SKU 1002 / name Ansa Clonal DNA)
   * with Product_SKU__c = GS-001 on the line itself.
   */
  @TestVisible
  private static String resolveLineItemSku(SObject lineItem) {
    if (lineItem == null) {
      return null;
    }
    Map<String, Object> values = lineItem.getPopulatedFieldsAsMap();
    for (
      String fieldName : new List<String>{ 'Product_SKU__c', 'Product_Code__c' }
    ) {
      if (!values.containsKey(fieldName) || values.get(fieldName) == null) {
        continue;
      }
      String raw = String.valueOf(values.get(fieldName)).trim();
      if (String.isBlank(raw)) {
        continue;
      }
      if (isPortalFeeAddonSku(raw)) {
        return raw;
      }
    }
    Product2 product = relatedProductFromLineItem(lineItem);
    if (product != null && String.isNotBlank(product.StockKeepingUnit)) {
      return product.StockKeepingUnit.trim();
    }
    for (
      String fieldName : new List<String>{ 'Product_SKU__c', 'Product_Code__c' }
    ) {
      if (!values.containsKey(fieldName) || values.get(fieldName) == null) {
        continue;
      }
      String raw = String.valueOf(values.get(fieldName)).trim();
      if (String.isNotBlank(raw)) {
        return raw;
      }
    }
    return null;
  }

  /** Product2 when the relationship was queried; never throw if it was not. */
  private static Product2 relatedProductFromLineItem(SObject lineItem) {
    if (lineItem == null) {
      return null;
    }
    Map<String, Object> values = lineItem.getPopulatedFieldsAsMap();
    if (!values.containsKey('Product2') || values.get('Product2') == null) {
      return null;
    }
    return (Product2) values.get('Product2');
  }

  private static String relatedProductNameFromLineItem(SObject lineItem) {
    Product2 product = relatedProductFromLineItem(lineItem);
    return product != null ? product.Name : null;
  }

  /** True for portal fee-addon SKUs (Scale Up + Glycerol). */
  public static Boolean isPortalFeeAddonSku(String sku) {
    return isGlycerolStockSku(sku) || isScaleUpProduct(null, sku);
  }

  /** True if this OrderItem is the glycerol add-on (SKU or sequence-name fallback). */
  public static Boolean isGlycerolStockOrderItem(OrderItem oi) {
    if (oi == null) {
      return false;
    }
    String productName = relatedProductNameFromLineItem(oi);
    String sku = resolveLineItemSku(oi);
    if (isGlycerolStockProduct(productName) || isGlycerolStockSku(sku)) {
      return true;
    }
    String sequenceName = sequenceNameFromOrderItem(oi);
    return String.isNotBlank(sequenceName) &&
      'glycerol stock'.equalsIgnoreCase(sequenceName.trim());
  }

  /** True if this OrderItem is the Scale Up fee add-on. */
  public static Boolean isScaleUpOrderItem(OrderItem oi) {
    if (oi == null) {
      return false;
    }
    String productName = relatedProductNameFromLineItem(oi);
    String sku = resolveLineItemSku(oi);
    return isScaleUpProduct(productName, sku);
  }

  public static Boolean isGlycerolStockQuoteLineItem(QuoteLineItem qli) {
    if (qli == null) {
      return false;
    }
    String productName = relatedProductNameFromLineItem(qli);
    String sku = resolveLineItemSku(qli);
    return isGlycerolStockProduct(productName) || isGlycerolStockSku(sku);
  }

  public static Boolean isScaleUpQuoteLineItem(QuoteLineItem qli) {
    if (qli == null) {
      return false;
    }
    String productName = relatedProductNameFromLineItem(qli);
    String sku = resolveLineItemSku(qli);
    return isScaleUpProduct(productName, sku);
  }

  /** Fee add-ons that must not count toward portal sequence totals / line lists. */
  public static Boolean isPortalFeeAddonOrderItem(OrderItem oi) {
    return isGlycerolStockOrderItem(oi) || isScaleUpOrderItem(oi);
  }

  public static Boolean isPortalFeeAddonQuoteLineItem(QuoteLineItem qli) {
    if (qli == null) {
      return false;
    }
    if (isGlycerolStockQuoteLineItem(qli) || isScaleUpQuoteLineItem(qli)) {
      return true;
    }
    // Glycerol/scale-up children are parent-linked. Sandbox flows may create the
    // child before SKU/name stamp, so Parent_Line_Item__c is the fallback signal.
    return quoteLineItemParentId(qli) != null;
  }

  /**
   * Product label from quote request header when standard quote/order line items are missing.
   */
  public static String productLabelFromQuoteRequest(ABT_Quote_Request__c qr) {
    if (qr == null) {
      return null;
    }
    if (String.isNotBlank(qr.ABT_Product_Name__c)) {
      return formatPortalProductName(qr.ABT_Product_Name__c);
    }
    SObject prodRel = qr.getSObject('ABT_Product__r');
    if (prodRel != null && String.isNotBlank((String) prodRel.get('Name'))) {
      return formatPortalProductName((String) prodRel.get('Name'));
    }
    return null;
  }

  /** Distinct product names per Quote Id from linked quote requests. */
  public static Map<Id, Set<String>> loadProductNamesByQuoteId(
    Set<Id> quoteIds
  ) {
    Map<Id, Set<String>> result = new Map<Id, Set<String>>();
    if (quoteIds == null || quoteIds.isEmpty()) {
      return result;
    }
    for (ABT_Quote_Request__c qr : [
      SELECT ABT_Quote__c, ABT_Product_Name__c, ABT_Product__r.Name
      FROM ABT_Quote_Request__c
      WHERE ABT_Quote__c IN :quoteIds AND ABT_Stage__c != 'Canceled'
      ORDER BY CreatedDate DESC
    ]) {
      String label = productLabelFromQuoteRequest(qr);
      if (String.isBlank(label) || qr.ABT_Quote__c == null) {
        continue;
      }
      if (!result.containsKey(qr.ABT_Quote__c)) {
        result.put(qr.ABT_Quote__c, new Set<String>());
      }
      result.get(qr.ABT_Quote__c).add(label);
    }
    return result;
  }

  /** Project title per Quote Id from linked quote requests (most recent non-canceled wins). */
  public static Map<Id, String> loadProjectTitleByQuoteId(Set<Id> quoteIds) {
    Map<Id, String> result = new Map<Id, String>();
    if (quoteIds == null || quoteIds.isEmpty()) {
      return result;
    }
    for (ABT_Quote_Request__c qr : [
      SELECT ABT_Quote__c, ABT_Customer_Project_Name__c, Project__r.Name
      FROM ABT_Quote_Request__c
      WHERE ABT_Quote__c IN :quoteIds AND ABT_Stage__c != 'Canceled'
      ORDER BY CreatedDate DESC
    ]) {
      if (qr.ABT_Quote__c == null || result.containsKey(qr.ABT_Quote__c)) {
        continue;
      }
      String title = projectTitleFromQuoteRequest(qr);
      if (String.isNotBlank(title)) {
        result.put(qr.ABT_Quote__c, title);
      }
    }
    return result;
  }

  /** Customer project title from quote request header — not Opportunity name. */
  public static String projectTitleFromQuoteRequest(ABT_Quote_Request__c qr) {
    if (qr == null) {
      return null;
    }
    if (String.isNotBlank(qr.ABT_Customer_Project_Name__c)) {
      return qr.ABT_Customer_Project_Name__c.trim();
    }
    SObject projectRel = qr.getSObject('Project__r');
    if (
      projectRel != null && String.isNotBlank((String) projectRel.get('Name'))
    ) {
      return ((String) projectRel.get('Name')).trim();
    }
    return null;
  }

  /** Distinct product names per project name from quote requests for an account. */
  public static Map<String, Set<String>> loadProductNamesByProjectName(
    Id accountId,
    Set<String> projectNames
  ) {
    Map<String, Set<String>> result = new Map<String, Set<String>>();
    if (accountId == null || projectNames == null || projectNames.isEmpty()) {
      return result;
    }
    for (ABT_Quote_Request__c qr : [
      SELECT
        ABT_Customer_Project_Name__c,
        ABT_Product_Name__c,
        ABT_Product__r.Name
      FROM ABT_Quote_Request__c
      WHERE
        ABT_Account__c = :accountId
        AND ABT_Customer_Project_Name__c IN :projectNames
        AND ABT_Stage__c != 'Canceled'
    ]) {
      String label = productLabelFromQuoteRequest(qr);
      String proj = qr.ABT_Customer_Project_Name__c;
      if (String.isBlank(label) || String.isBlank(proj)) {
        continue;
      }
      if (!result.containsKey(proj)) {
        result.put(proj, new Set<String>());
      }
      result.get(proj).add(label);
    }
    return result;
  }

  /** Comma-join product names for list columns. Strips the "Ansa" prefix first. */
  public static String joinSortedProductNames(Set<String> names) {
    if (names == null || names.isEmpty()) {
      return null;
    }
    Set<String> formatted = new Set<String>();
    for (String name : names) {
      String label = formatPortalProductName(name);
      if (String.isNotBlank(label)) {
        formatted.add(label);
      }
    }
    List<String> sorted = new List<String>(formatted);
    sorted.sort();
    return String.join(sorted, ', ');
  }

  /** Same idea as joinSortedProductNames but without the Ansa-prefix strip. */
  public static String joinSortedDistinctStrings(Set<String> values) {
    if (values == null || values.isEmpty()) {
      return null;
    }
    List<String> sorted = new List<String>();
    for (String value : values) {
      if (String.isNotBlank(value)) {
        sorted.add(value.trim());
      }
    }
    if (sorted.isEmpty()) {
      return null;
    }
    sorted.sort();
    return String.join(sorted, ', ');
  }

  public static Set<String> parseDelimitedTextTokens(String raw) {
    Set<String> tokens = new Set<String>();
    if (String.isBlank(raw)) {
      return tokens;
    }
    for (String part : raw.split(',')) {
      String trimmed = part.trim();
      if (String.isNotBlank(trimmed)) {
        tokens.add(trimmed);
      }
    }
    return tokens;
  }

  /** Distinct Quote Ids per Order from line-item quote links (multi-quote checkout). */
  public static Map<Id, Set<Id>> loadQuoteIdsByOrderId(Set<Id> orderIds) {
    Map<Id, Set<Id>> result = new Map<Id, Set<Id>>();
    if (orderIds == null || orderIds.isEmpty()) {
      return result;
    }

    Map<String, Schema.SObjectField> oiFields = Schema.SObjectType.OrderItem.fields.getMap();
    Boolean hasSalesforceQuoteLineId = oiFields.containsKey(
      'salesforce_quote_line_id__c'
    );

    String oiQuery = 'SELECT Id, OrderId, QuoteLineItemId';
    if (hasSalesforceQuoteLineId) {
      oiQuery += ', Salesforce_Quote_Line_ID__c';
    }
    oiQuery += ', QuoteLineItem.QuoteId FROM OrderItem WHERE OrderId IN :orderIds';

    List<OrderItem> items = Database.query(oiQuery);
    Set<Id> quoteLineItemIds = new Set<Id>();
    for (OrderItem item : items) {
      if (item.QuoteLineItemId != null) {
        quoteLineItemIds.add(item.QuoteLineItemId);
      } else if (hasSalesforceQuoteLineId) {
        String rawLineId = (String) item.get('Salesforce_Quote_Line_ID__c');
        if (String.isNotBlank(rawLineId)) {
          try {
            quoteLineItemIds.add(Id.valueOf(rawLineId.trim()));
          } catch (Exception e) {
            // Ignore malformed line id values.
          }
        }
      }
    }

    Map<Id, QuoteLineItem> quoteLineItemsById = quoteLineItemIds.isEmpty()
      ? new Map<Id, QuoteLineItem>()
      : new Map<Id, QuoteLineItem>(
          [
            SELECT Id, QuoteId
            FROM QuoteLineItem
            WHERE Id IN :quoteLineItemIds
          ]
        );

    for (OrderItem item : items) {
      if (!result.containsKey(item.OrderId)) {
        result.put(item.OrderId, new Set<Id>());
      }

      Id quoteId = item.QuoteLineItem != null
        ? item.QuoteLineItem.QuoteId
        : null;
      if (quoteId == null) {
        Id lineItemId = item.QuoteLineItemId;
        if (lineItemId == null && hasSalesforceQuoteLineId) {
          String rawLineId = (String) item.get('Salesforce_Quote_Line_ID__c');
          if (String.isNotBlank(rawLineId)) {
            try {
              lineItemId = Id.valueOf(rawLineId.trim());
            } catch (Exception e) {
              lineItemId = null;
            }
          }
        }
        if (lineItemId != null && quoteLineItemsById.containsKey(lineItemId)) {
          quoteId = quoteLineItemsById.get(lineItemId).QuoteId;
        }
      }

      if (quoteId != null) {
        result.get(item.OrderId).add(quoteId);
      }
    }

    return result;
  }

  @AuraEnabled(cacheable=true)
  public static stripeGC__Stripe_Account__c getStripeAccount() {
    List<stripeGC__Stripe_Account__c> stripeAccount = [
      SELECT id, stripeGC__Stripe_Account_Id__c
      FROM stripeGC__Stripe_Account__c
    ];
    return stripeAccount[0];
  }

  /**
   * Saved cards on the Account for checkout. Throws if accountId is null.
   * Contact-scoped list is getPaymentMethodsByContact.
   */
  @AuraEnabled(cacheable=true)
  public static List<ABT_Payment_Method__c> getPaymentMethodsByAccount(
    Id accountId
  ) {
    if (accountId == null) {
      throw new AuraHandledException('accountId cannot be null');
    }
    return [
      SELECT Id, ABT_Type__c, ABT_Active__c, ABT_Card_Number__c, CreatedDate
      FROM ABT_Payment_Method__c
      WHERE ABT_Account__c = :accountId
      ORDER BY CreatedDate DESC
    ];
  }

  /**
   * Line items for quote detail: sequence, vector, pricing, glycerol, scale-up.
   * Sequence fields come off Related_Sequence__r.
   */
  @AuraEnabled(cacheable=true)
  public static List<ABT_Quote_Request_Lineitem__c> getQuoteRequestLineitemByQuoteRequest(
    Id quoteRequestId
  ) {
    if (quoteRequestId == null) {
      throw new AuraHandledException('QuoteRequest ID cannot be null');
    }
    return [
      SELECT
        Id,
        ABT_Product_Name__c,
        ABT_BioSecurity_Flag__c,
        Potentially_Toxic__c,
        Reflex_Vector_Opt_In__c,
        ABT_Quote_Line_Created_On__c,
        ABT_Quantity__c,
        ABT_Feasibility_Reason__c,
        ABT_Fwd_Feasibility_Reason__c,
        ABT_Total_Price__c,
        ABT_Complexity_Details__c,
        ABT_Quote_Line_Item__c,
        ABT_Quote_Line_Item__r.Vector__c,
        ABT_Quote_Line_Item__r.Vector__r.Name,
        ABT_Quote_Line_Item__r.Vector__r.Type__c,
        ABT_Quote_Line_Item__r.Vector__r.Active__c,
        ABT_Quote_Line_Item__r.End_Customer_List_Price__c,
        ABT_Quote_Line_Item__r.Scale_Up_Mass__c,
        ABT_Quote_Line_Item__r.Scale_Up_Price__c,
        ABT_Quote_Line_Item__r.Scale_Up_Lead_Time__c,
        Scale_Up_Selected__c,
        Scale_Up_Quantity__c,
        Scale_Up_Glycerol_Stock__c,
        Scale_Up_Buffer__c,
        Scale_Up_Endotoxin_Free__c,
        Scale_Up_Animal_Free__c,
        Scale_Up_Normalization__c,
        Scale_Up_Lead_Time__c,
        Glycerol_Stock__c,
        Glycerol_Price__c,
        ABT_Sales_Price__c,
        Total_Combined_Price__c,
        As_Early_As_Date__c,
        Expected_Ship_Date__c,
        Tranche__c,
        ABT_Quote_Line_Item__r.Tranche__c,
        Related_Sequence__c,
        Related_Sequence__r.Sequence_Name__c,
        Related_Sequence__r.Sequence__c,
        Related_Sequence__r.Sequence_Length__c,
        Related_Sequence__r.Sequence_Classification__c,
        Related_Sequence__r.Feasibility_Classifier__c,
        Related_Sequence__r.Feasibility_Explained__c,
        Related_Sequence__r.Feasibility_Explained_1__c,
        Related_Sequence__r.Feasibility_Explained_2__c,
        Related_Sequence__r.Feasibility_Explained_3__c,
        Related_Sequence__r.Complexity__c,
        Related_Sequence__r.Complexity_Assessment__c,
        Related_Sequence__r.Complexity_Score__c,
        Related_Sequence__r.Sequence_Error__c,
        Related_Sequence__r.Sequence_Flag__c,
        Related_Sequence__r.Recommend_Not_High_Copy_Num_Vector__c,
        Related_Sequence__r.Vector__c,
        Related_Sequence__r.Vector_name__c,
        Related_Sequence__r.Vector__r.Name
      FROM ABT_Quote_Request_Lineitem__c
      WHERE ABT_Quote_Request__c = :quoteRequestId
      ORDER BY CreatedDate ASC
    ];
  }

  /**
   * Delete one Quote Request line from the wizard. Does not touch Sequence__c
   * cleanup here — that's trigger/flow.
   */
  @AuraEnabled
  public static void deleteRecordById(Id recordId) {
    delete [SELECT Id FROM ABT_Quote_Request_Lineitem__c WHERE Id = :recordId];
  }

  /**
   * Cancel/delete a Quote Request. Rejects the linked Quote if it isn't already
   * Ordered. Returns a status string the LWC shows in a toast.
   */
  @AuraEnabled
  public static String deleteQuoteRequest(Id quoteRequestId) {
    try {
      // Get the Quote Request with related Quote
      ABT_Quote_Request__c quoteRequest = [
        SELECT
          Id,
          ABT_Quote__c,
          ABT_Status__c,
          ABT_Stage__c,
          ABT_Customer_Project_Name__c,
          ABT_Quote__r.Status
        FROM ABT_Quote_Request__c
        WHERE Id = :quoteRequestId
        LIMIT 1
      ];

      if (
        quoteRequest.ABT_Stage__c == 'Ordered' ||
        quoteRequest.ABT_Quote__r?.Status == 'Ordered'
      ) {
        throw new AuraHandledException(
          'This quote cannot be deleted because it has been ordered.'
        );
      }

      if (quoteRequest.ABT_Quote__c != null) {
        // Update Quote status to "Rejected"
        Quote q = new Quote();
        q.Id = quoteRequest.ABT_Quote__c;
        q.Status = 'Rejected';
        update q;

        // Add a note about customer deleting the quote
        ContentNote note = new ContentNote();
        note.Title = 'Quote Deletion Note';
        note.Content = Blob.valueOf('Customer deleted quote on portal');
        insert note;

        // Link the note to the Quote
        ContentDocumentLink contentLink = new ContentDocumentLink();
        contentLink.LinkedEntityId = quoteRequest.ABT_Quote__c;
        contentLink.ContentDocumentId = note.Id;
        contentLink.ShareType = 'V'; // Viewer
        insert contentLink;
      }

      // ABT_Stage__c can lag the cart state, so portal cart membership is resolved separately.
      // Clear the cart flag so deleted quotes resolve to Stage = Canceled and drop off the list.
      clearQuoteRequestFromCart(quoteRequestId);

      return 'Quote request deleted successfully';
    } catch (Exception e) {
      throw new AuraHandledException(
        'Error deleting quote request: ' + e.getMessage()
      );
    }
  }

  /**
   * Marks the Quote Ordered and returns the created Order. Used from staff/portal
   * paths that skip the full cart checkout flow.
   */
  @AuraEnabled
  public static Order updateQuoteStatusToOrdered(Id quoteId) {
    return updateQuoteStatusToOrdered(quoteId, true);
  }

  @TestVisible
  private static Order updateQuoteStatusToOrdered(
    Id quoteId,
    Boolean updateQuote
  ) {
    if (updateQuote) {
      Quote q = new Quote();
      q.Id = quoteId;
      q.Status = 'Ordered';
      update q;
    }

    List<Order> orders = [
      SELECT id, OrderNumber
      FROM Order
      WHERE QuoteId = :quoteId
      ORDER BY createddate DESC
      LIMIT 1
    ];
    return orders.isEmpty() ? null : orders[0];
  }

  // Terms & conditions
  @AuraEnabled(cacheable=true)
  public static Boolean getTermsAndCondidtionStatus(Id userId) {
    List<User> users = [
      SELECT ABT_Terms_Conditions_Accepted__c
      FROM User
      WHERE Id = :userId
      LIMIT 1
    ];
    if (users.isEmpty()) {
      return false;
    }
    return users[0].ABT_Terms_Conditions_Accepted__c == true;
  }

  /**
   * Stamp ABT_Terms_Conditions_Accepted__c after the user accepts. Called from
   * the LWR T&Cs page (cacheable=false via ABT_Portal_Login_Controller).
   */
  @AuraEnabled
  public static void setTermsAndCondidtionStatus(Id userId) {
    try {
      User u = new User();
      u.Id = userId;
      u.ABT_Terms_Conditions_Accepted__c = true;
      update u;
    } catch (DmlException e) {
      throw new AuraHandledException(
        'Error deleting record: ' + e.getMessage()
      );
    }
  }

  /**
   * Products offered in the portal new-quote picker. SKU list comes from
   * Label.ABT_Portal_Products_SKU so we can add/remove without a code deploy.
   */
  @AuraEnabled(cacheable=true)
  public static List<Product2> getProductList() {
    String sku = Label.ABT_Portal_Products_SKU;
    List<String> resultList = sku.split(',');
    Set<String> skuSet = new Set<String>();
    for (String skuItem : resultList) {
      String trimmedSku = skuItem.trim();
      if (!String.isBlank(trimmedSku)) {
        skuSet.add(trimmedSku);
      }
    }
    if (skuSet.isEmpty()) {
      return new List<Product2>();
    }

    List<Product2> products = [
      SELECT
        Id,
        Name,
        IsActive,
        Description,
        ABT_Product_Image2__c,
        StockKeepingUnit,
        Allowed_Characters__c,
        Minimum_Length__c,
        Maximum_Length__c
      FROM Product2
      WHERE StockKeepingUnit IN :skuSet AND IsActive = TRUE
    ];

    Id userId = UserInfo.getUserId();
    User currentUser = [
      SELECT Id, ContactId, AccountId, Profile.Name
      FROM User
      WHERE Id = :userId
      LIMIT 1
    ];
    Id accountId = currentUser.AccountId;
    Boolean isSystemAdmin = currentUser.Profile.Name == 'System Administrator';

    Map<String, Product2> productsBySku = new Map<String, Product2>();
    for (Product2 prod : products) {
      if (isSystemAdmin || hasEntitlementForProduct(accountId, prod.Id)) {
        productsBySku.put(prod.StockKeepingUnit, prod);
      }
    }

    List<Product2> orderedProducts = new List<Product2>();
    for (String skuItem : resultList) {
      String trimmedSku = skuItem.trim();
      if (productsBySku.containsKey(trimmedSku)) {
        Product2 prod = productsBySku.get(trimmedSku);
        prod.Name = formatPortalProductName(prod.Name);
        orderedProducts.add(prod);
      }
    }
    return orderedProducts;
  }

  /**
   * Product catalog row for the new-quote wizard (SKU, help text, description).
   */
  @AuraEnabled(cacheable=true)
  public static Product2 getProductById(Id productId) {
    if (productId == null) {
      return null;
    }

    List<Product2> products = [
      SELECT
        Id,
        Name,
        StockKeepingUnit,
        Allowed_Characters__c,
        Minimum_Length__c,
        Maximum_Length__c,
        Glycerol_Stock_Enabled__c,
        Scale_Up_Enabled__c,
        Vector_Enabled__c
      FROM Product2
      WHERE Id = :productId
      LIMIT 1
    ];

    if (products.isEmpty()) {
      return null;
    }
    products[0].Name = formatPortalProductName(products[0].Name);
    return products[0];
  }

  // Related lists on invoice/payment screens — parentApiName picks the child object.
  @AuraEnabled(cacheable=true)
  public static List<SObject> getRelatedList(
    String parentId,
    String parentApiName
  ) {
    switch on parentApiName {
      when 'ABT_Invoice__c' {
        return [
          SELECT
            id,
            Name,
            ABT_Status__c,
            ABT_Amount_Paid__c,
            ABT_Invoice_Date__c,
            ABT_Stripe_Payment_Link__c,
            ABT_Stripe_Error__c
          FROM ABT_Invoice__c
          WHERE ABT_Order__c = :parentId
          ORDER BY CreatedDate DESC
        ];
      }
      when else {
        throw new AuraHandledException(
          parentApiName + ' object is not available for this component'
        );
      }
    }
  }

  /**
   * Files on a Quote Request / Order / Invoice for portal downloads. Ordered by
   * latest first. VersionDataUrl is used by the LWC to fetch without a second Apex call.
   */
  @AuraEnabled(cacheable=true)
  public static List<ContentDocumentLink> getRelatedDocuments(Id recordId) {
    return [
      SELECT
        Id,
        ContentDocumentId,
        ContentDocument.Title,
        ContentDocument.FileExtension,
        ContentDocument.LatestPublishedVersion.VersionDataUrl
      FROM ContentDocumentLink
      WHERE LinkedEntityId = :recordId
      ORDER BY SystemModstamp DESC
    ];
  }

  /**
   * Invoice line items on the portal invoice related list.
   */
  @AuraEnabled(cacheable=true)
  public static List<ABT_InvoiceLineItem__c> getInvoiceItemRelatedList(
    Id recordId
  ) {
    return [
      SELECT Id, ABT_Product__r.Name, Quantity__c, ABT_Unit_Price__c
      FROM ABT_InvoiceLineItem__c
      WHERE ABT_Invoice__c = :recordId
      ORDER BY CreatedDate DESC
    ];
  }

  @AuraEnabled(cacheable=true)
  public static List<ABT_Payment__c> getPaymentRelatedList(Id recordId) {
    return [
      SELECT
        Id,
        ABT_Invoice__c,
        ABT_Status__c,
        ABT_Total_Amount_Paid__c,
        ABT_Transaction_Date__c
      FROM ABT_Payment__c
      WHERE ABT_Invoice__c = :recordId
      ORDER BY CreatedDate DESC
    ];
  }

  // @AuraEnabled(cacheable=true)
  // public static List<Product2> getProductList() {
  //     String sku = Label.ABT_Portal_Products_SKU;
  //     // Split the input string by commas
  //     List<String> resultList = sku.split(',');
  //     String skuString = '(';
  //     // Trim whitespace from each string in the list
  //     for (Integer i = 0; i < resultList.size(); i++) {
  //         skuString += '\'';
  //         skuString += resultList[i].trim();
  //         skuString += '\',';
  //     }
  //     skuString = skuString.substring(0, skuString.length() - 1);
  //     skuString += ')';
  //     System.debug(skuString);
  //     String soqlQuery = 'SELECT id, Name, Description, ABT_Product_Image2__c, StockKeepingUnit FROM Product2 where StockKeepingUnit IN '+ skuString ;
  //     System.debug(soqlQuery);
  //     List<Product2> products = Database.query(soqlQuery);
  //     System.debug(products);

  //     // Check entitlements for the user's account
  //     Id userId = UserInfo.getUserId();
  //     User currentUser = [SELECT Id, ContactId, AccountId FROM User WHERE Id = :userId LIMIT 1];
  //     Id accountId = currentUser.AccountId;

  //     // Create ordered list based on the original SKU list order
  //     Map<String, Product2> productsBySku = new Map<String, Product2>();
  //     for (Product2 prod : products) {
  //         // Check if the account has entitlements for this product
  //         if (hasEntitlementForProduct(accountId, prod.Id)) {
  //             productsBySku.put(prod.StockKeepingUnit, prod);
  //         }
  //     }

  //     List<Product2> orderedProducts = new List<Product2>();
  //     for (String skuItem : resultList) {
  //         String trimmedSku = skuItem.trim();
  //         if (productsBySku.containsKey(trimmedSku)) {
  //             orderedProducts.add(productsBySku.get(trimmedSku));
  //         }
  //     }
  //     system.debug('products :: '+ orderedProducts);
  //     return orderedProducts;
  // }

  // Test-visible flag to bypass entitlement checks in tests
  @TestVisible
  private static Boolean bypassEntitlementCheck = false;

  /**
   * Check if an account has entitlement for a specific product
   * @param accountId The ID of the account to check
   * @param productId The ID of the product to check entitlement for
   * @return Boolean indicating whether the account has entitlement for the product
   */
  @TestVisible
  private static Boolean hasEntitlementForProduct(Id accountId, Id productId) {
    // Allow tests to bypass entitlement check
    if (bypassEntitlementCheck) {
      return true;
    }

    // If no account ID is provided, return false
    if (accountId == null) {
      return false;
    }

    try {
      // Find BuyerGroup associations for this account
      List<BuyerGroupMember> buyerGroupMembers = [
        SELECT BuyerId, BuyerGroupId
        FROM BuyerGroupMember
        WHERE BuyerId = :accountId
      ];

      if (buyerGroupMembers.isEmpty()) {
        return false;
      }

      Set<Id> buyerGroupIds = new Set<Id>();
      for (BuyerGroupMember bg : buyerGroupMembers) {
        buyerGroupIds.add(bg.BuyerGroupId);
      }

      // Check if any entitlement policies exist for these buyer groups and the product
      Integer entitlementCount = [
        SELECT COUNT()
        FROM CommerceEntitlementProduct
        WHERE
          ProductId = :productId
          AND PolicyId IN (
            SELECT PolicyId
            FROM CommerceEntitlementBuyerGroup
            WHERE BuyerGroupId IN :buyerGroupIds
          )
      ];

      return entitlementCount > 0;
    } catch (Exception e) {
      System.debug('Error checking entitlements: ' + e.getMessage());
      return false;
    }
  }

  /**
   * Portal paste-CSV into a Quote Request. Not the staff ContentVersion uploader
   * (that's CSVUploaderController). Parses JSON-wrapped CSV from the wizard.
   */
  @AuraEnabled
  public static void loadCsvData(Id quoteRequestId, string data) {
    system.debug(quoteRequestId + '>>>>quoteRequestId>>>>>>');
    system.debug(data + '>>>>data>>>>>>');
    data = JSON.deserializeUntyped(data).toString();
    system.debug(data + '>>>>data>>>>>>');

    Map<String, Id> mapProductSkuToId = new Map<String, Id>();
    for (Product2 product : [
      SELECT id, StockKeepingUnit
      FROM Product2
      WHERE StockKeepingUnit != ''
      LIMIT 50000
    ]) {
      mapProductSkuToId.put(product.StockKeepingUnit, product.Id);
    }
    system.debug(mapProductSkuToId + '>>>>mapProductSkuToId>>>>>>');

    Map<String, Integer> mapToGetIndex = new Map<String, Integer>();
    List<ABT_SequenceSyncService.LineWithSequenceInput> csvInputs = new List<ABT_SequenceSyncService.LineWithSequenceInput>();

    // Use indexOf/substring instead of split('\n') to avoid Salesforce
    // "Regex too complicated" LimitException on large file inputs
    List<String> filelinesList = new List<String>();
    Integer startIdx = 0;
    Integer nlIdx = data.indexOf('\n');
    while (nlIdx != -1) {
      filelinesList.add(data.substring(startIdx, nlIdx));
      startIdx = nlIdx + 1;
      nlIdx = data.indexOf('\n', startIdx);
    }
    if (startIdx < data.length()) {
      filelinesList.add(data.substring(startIdx));
    }
    String[] filelines = filelinesList;
    system.debug(filelines + '>>>>filelines>>>>>>');
    String[] csvFieldNames = filelines[0].replace('\r', '').split(',');
    system.debug(csvFieldNames + '>>>>csvFieldNames>>>>>>');

    for (Integer i = 0; i < csvFieldNames.size(); i++) {
      mapToGetIndex.put(csvFieldNames[i].trim(), i);
    }
    system.debug(mapToGetIndex + '>>>>mapToGetIndex>>>>>>');

    for (String key : mapToGetIndex.keySet()) {
      System.debug('Key: ' + key + ', Value: ' + mapToGetIndex.get(key));
    }

    //Loop from the second line as from second line only we will have data
    for (Integer i = 1; i < filelines.size(); i++) {
      string[] csvRecordData = filelines[i].split(',');
      system.debug(csvRecordData + '>>>>csvRecordData>>>>>>');
      system.debug(csvRecordData[0] + '>>>>csvRecordData[0]>>>>>>');
      system.debug(csvRecordData[1] + '>>>>csvRecordData[1]>>>>>>');
      system.debug(csvRecordData.size() + '>>>>csvRecordData.size()>>>>>>');

      ABT_SequenceSyncService.LineWithSequenceInput csvInput = new ABT_SequenceSyncService.LineWithSequenceInput();
      csvInput.quoteRequestId = quoteRequestId;

      for (Integer p = 0; p < csvRecordData.size(); p++) {
        system.debug(mapToGetIndex.keySet() + '>>>>');
        system.debug(mapToGetIndex.get('Sequence') + '>>>>');
        if (
          mapToGetIndex.get('Sequence') != null &&
          csvRecordData[mapToGetIndex.get('Sequence')] != null &&
          csvRecordData[mapToGetIndex.get('Sequence')] != ''
        ) {
          csvInput.sequence = csvRecordData[mapToGetIndex.get('Sequence')];
        }
        if (
          mapToGetIndex.get('SequenceName') != null &&
          csvRecordData[mapToGetIndex.get('SequenceName')] != null &&
          csvRecordData[mapToGetIndex.get('SequenceName')] != ''
        ) {
          csvInput.sequenceName = csvRecordData[
            mapToGetIndex.get('SequenceName')
          ];
        }
      }
      csvInputs.add(csvInput);
    }

    system.debug(csvInputs + '>>>>csvInputs>>>>>>');
    try {
      ABT_SequenceSyncService.createQuoteRequestLinesWithSequence(csvInputs);
    } catch (Exception e) {
      system.debug(e.getMessage() + '.getMessage()>>>>>>' + e);
      // throw new AuraHandledException(e.getMessage());
    }
  }

  // @AuraEnabled
  // public static void createQuotePdf(Id quoteRequestId) {
  //     // Initialize the quote URL
  //     String quoteUrl = '/quote/quoteTemplateDataViewer.apexp?';

  //     // Query the ABT_Quote_Request__c record and retrieve the related Quote ID
  //     ABT_Quote_Request__c quoteRequest = [
  //         SELECT Id, ABT_Quote__r.Id
  //         FROM ABT_Quote_Request__c
  //         WHERE Id = :quoteRequestId
  //         LIMIT 1
  //     ];

  //     // Store the related Quote ID in the quoteId variable
  //     Id quoteId = quoteRequest.ABT_Quote__r != null ? quoteRequest.ABT_Quote__r.Id : null;

  //     // Get the Quote Template Id from Custom Settings
  //     String quoteTemplateId = Label.ABT_QuoteTemplateId;

  //     // List variable to get all the Quote Documents
  //     List<QuoteDocument> lstQuoteDoc = new List<QuoteDocument>();

  //     if (quoteId != null) {
  //         // Construct the quote URL to generate PDF
  //         quoteUrl += 'id=' + quoteId;
  //         quoteUrl += '&headerHeight=197&footerHeight=10';
  //         quoteUrl += '&summlid=' + quoteTemplateId;
  //         System.debug('quoteUrl: ' + quoteUrl);

  //         // Call the quote URL
  //         PageReference pageRef = new PageReference(quoteUrl);

  //         // Get the quotePdf
  //         Blob quoteBlob;

  //         if (Test.isRunningTest()) {
  //             quoteBlob = Blob.valueOf('Generate Pdf');
  //         } else {
  //             quoteBlob = pageRef.getContentAsPDF();
  //         }

  //         // Initialize the QuoteDocument to hold the quote pdf for insertion
  //         QuoteDocument quoteDoc = new QuoteDocument();
  //         quoteDoc.Document = quoteBlob;
  //         quoteDoc.QuoteId = quoteId;
  //         lstQuoteDoc.add(quoteDoc);

  //     }

  //     // Insert the Quote Documents if the list is not empty
  //     if (!lstQuoteDoc.isEmpty()) {
  //         Database.insert(lstQuoteDoc);

  //         List<ContentDocumentLink> cdl = [
  //             SELECT
  //              id,
  //              ContentDocumentId,
  //              ShareType,
  //              Visibility
  //             FROM ContentDocumentLink
  //             WHERE LinkedEntityId =:quoteId
  //             ORDER BY SystemModstamp desc
  //         ];

  //         try{
  //             ContentDocumentLink cd = new ContentDocumentLink();
  //             cd.ContentDocumentId = cdl[0].ContentDocumentId;
  //             cd.LinkedEntityId = quoteRequestId;
  //             cd.ShareType = 'V'; // 'V' for Viewer access, 'C' for Collaborator access, etc.
  //             cd.Visibility = 'AllUsers';

  //             insert cd;
  //           }
  //         catch(Exception e){
  //             throw new AuraHandledException(e.getMessage());
  //         }
  //     }
  // }

  // @AuraEnabled
  // public static void createQuotePdf2(Id quoteRequestId){
  //     ABT_Quote_Request__c qr = new ABT_Quote_Request__c();
  //     qr.id = quoteRequestId;
  //     qr.ABT_Generate_PDF__c = true;
  //     update qr;
  // }

  /**
   * Billing/shipping CPAs for checkout. cacheable for first paint; use the Fresh
   * sibling after the address form saves.
   */
  @AuraEnabled(cacheable=true)
  public static List<ContactPointAddress> getContactPointAddresses(
    Id accountId,
    String addressType
  ) {
    return queryContactPointAddresses(accountId, addressType);
  }

  /**
   * Same CPA query, cacheable=false so the form sees a just-saved address.
   */
  @AuraEnabled
  public static List<ContactPointAddress> getContactPointAddressesFresh(
    Id accountId,
    String addressType
  ) {
    return queryContactPointAddresses(accountId, addressType);
  }

  private static List<ContactPointAddress> queryContactPointAddresses(
    Id accountId,
    String addressType
  ) {
    try {
      List<String> addressTypes = resolveContactPointAddressTypes(addressType);
      return [
        SELECT
          Id,
          Name,
          AddressType,
          Street,
          City,
          State,
          PostalCode,
          Country,
          Address,
          IsDefault
        FROM ContactPointAddress
        WHERE ParentId = :accountId AND AddressType IN :addressTypes
        ORDER BY CreatedDate DESC
      ];
    } catch (Exception e) {
      throw new AuraHandledException(
        'Error fetching contact point addresses: ' + e.getMessage()
      );
    }
  }

  private static List<String> resolveContactPointAddressTypes(
    String addressType
  ) {
    Set<String> types = new Set<String>();
    if (String.isBlank(addressType)) {
      types.addAll(
        new List<String>{
          'Billing Address',
          'Shipping Address',
          'Billing',
          'Shipping'
        }
      );
      return new List<String>(types);
    }
    types.add(addressType);
    String lower = addressType.toLowerCase();
    if (lower.contains('bill')) {
      types.add('Billing Address');
      types.add('Billing');
    }
    if (lower.contains('ship')) {
      types.add('Shipping Address');
      types.add('Shipping');
    }
    return new List<String>(types);
  }

  private static String formatOrderAddressLines(
    String street,
    String city,
    String state,
    String postal,
    String country
  ) {
    List<String> streetLine = new List<String>();
    if (String.isNotBlank(street)) {
      streetLine.add(street);
    }
    if (String.isNotBlank(city)) {
      streetLine.add(city);
    }
    if (String.isNotBlank(state)) {
      streetLine.add(state);
    }
    List<String> countryLine = new List<String>();
    if (String.isNotBlank(country)) {
      countryLine.add(country);
    }
    if (String.isNotBlank(postal)) {
      countryLine.add(postal);
    }
    List<String> lines = new List<String>();
    if (!streetLine.isEmpty()) {
      lines.add(String.join(streetLine, ', '));
    }
    if (!countryLine.isEmpty()) {
      lines.add(String.join(countryLine, ', '));
    }
    return lines.isEmpty() ? null : String.join(lines, ' | ');
  }

  private static String resolvePortalPoNumber(Order o) {
    if (o == null) {
      return null;
    }
    if (String.isNotBlank(o.Purchase_Order_Number__c)) {
      return o.Purchase_Order_Number__c.trim();
    }
    if (String.isNotBlank(o.PoNumber)) {
      return o.PoNumber.trim();
    }
    if (String.isNotBlank(o.End_Customer_PO__c)) {
      return o.End_Customer_PO__c.trim();
    }
    return null;
  }

  /**
   * Order header for the portal order-detail page. Loaded via Apex so community
   * users get addresses/INCO without layout FLS gaps.
   */
  @AuraEnabled(cacheable=true)
  public static OrderPortalDetail getOrderPortalDetail(Id orderId) {
    if (orderId == null) {
      throw new AuraHandledException('Order Id is required.');
    }
    try {
      Order o = [
        SELECT
          Id,
          OrderNumber,
          NetSuite_Order_Number__c,
          Status,
          EffectiveDate,
          CreatedDate,
          Customer_Project_Name__c,
          Purchase_Order_Number__c,
          PoNumber,
          End_Customer_PO__c,
          Payment_Method__c,
          Discount__c,
          Taxes__c,
          Tracking_Number__c,
          Ansa_Quote_Number__c,
          Ship_Method__c,
          Customer_Notes_New__c,
          Subtotal__c,
          TotalAmount,
          Shipping_charges__c,
          Total__c,
          Accept_Partial_Shipment__c,
          Tax_Exempt__c,
          BillingStreet,
          BillingCity,
          BillingState,
          BillingPostalCode,
          BillingCountry,
          ShippingStreet,
          ShippingCity,
          ShippingState,
          ShippingPostalCode,
          ShippingCountry,
          QuoteId,
          Quote.Incoterms__c,
          Quote.Discount__c,
          Quote.Discount_Amount__c,
          Promo_Code__c,
          Promo_Code__r.Discount_Percentage__c,
          Order_Contact__c,
          Order_Contact__r.Name,
          Owner.Name
        FROM Order
        WHERE Id = :orderId
        LIMIT 1
      ];

      OrderPortalDetail dto = new OrderPortalDetail();
      dto.orderNumber = resolvePortalOrderDisplayNumber(
        o.OrderNumber,
        o.NetSuite_Order_Number__c
      );
      dto.projectName = resolvePortalOrderProjectName(
        o.QuoteId,
        o.Customer_Project_Name__c,
        null
      );
      dto.requestorName = o.Order_Contact__r != null
        ? o.Order_Contact__r.Name
        : (o.Owner != null ? o.Owner.Name : null);
      dto.orderPlaced = o.EffectiveDate != null
        ? String.valueOf(o.EffectiveDate)
        : String.valueOf(o.CreatedDate.date());
      dto.status = o.Status;
      dto.paymentMethod = o.Payment_Method__c;
      dto.poNumber = resolvePortalPoNumber(o);
      dto.shippingMethod = o.Ship_Method__c;
      dto.ansaQuoteNumber = o.Ansa_Quote_Number__c;
      dto.trackingNumber = o.Tracking_Number__c;
      dto.incoTerms = String.isNotBlank(o.Quote?.Incoterms__c)
        ? o.Quote.Incoterms__c
        : 'FCA';
      dto.billingAddress = formatOrderAddressLines(
        o.BillingStreet,
        o.BillingCity,
        o.BillingState,
        o.BillingPostalCode,
        o.BillingCountry
      );
      dto.shippingAddress = formatOrderAddressLines(
        o.ShippingStreet,
        o.ShippingCity,
        o.ShippingState,
        o.ShippingPostalCode,
        o.ShippingCountry
      );
      dto.notes = o.Customer_Notes_New__c;
      Decimal lineSubtotal = portalOrderProductSubtotal(orderId);
      if (lineSubtotal <= 0 && o.TotalAmount != null) {
        lineSubtotal = o.TotalAmount;
      }
      Decimal discountAmount = resolveStoredOrQuoteDiscount(o, lineSubtotal);
      dto.subtotal = lineSubtotal + discountAmount;
      dto.shipping = o.Shipping_charges__c;
      dto.packaging = 0;
      dto.discount = discountAmount;
      dto.tax = o.Taxes__c;
      Decimal computedTotal =
        lineSubtotal +
        (o.Shipping_charges__c != null ? o.Shipping_charges__c : 0) +
        (o.Taxes__c != null ? o.Taxes__c : 0);
      dto.total = (o.Total__c != null &&
        o.Total__c > computedTotal)
        ? o.Total__c
        : computedTotal;
      dto.taxExempt = o.Tax_Exempt__c == true;
      dto.canEditTaxExempt = canEditOrderTaxExempt(o);
      dto.acceptPartial = o.Accept_Partial_Shipment__c == true;
      dto.canEditAcceptPartial = canEditOrderAcceptPartial(o);
      return dto;
    } catch (Exception e) {
      throw new AuraHandledException(
        'Unable to load order details: ' + e.getMessage()
      );
    }
  }

  private static final Set<String> SHIPPED_ORDER_ITEM_STATUSES = new Set<String>{
    'Packaged',
    'Packaged Below Spec',
    'Fulfilled',
    'Fulfilled Below Spec'
  };

  private static Boolean orderHasShippedLineItems(Id orderId) {
    if (orderId == null) {
      return false;
    }
    return [
        SELECT COUNT()
        FROM OrderItem
        WHERE OrderId = :orderId AND Status__c IN :SHIPPED_ORDER_ITEM_STATUSES
      ] > 0;
  }

  private static Boolean isOrderInProgress(Order o) {
    if (o == null || o.Id == null) {
      return false;
    }
    return o.Status != 'Completed' && o.Status != 'Canceled';
  }

  private static Boolean canEditOrderTaxExempt(Order o) {
    return isOrderInProgress(o);
  }

  private static Boolean canEditOrderAcceptPartial(Order o) {
    if (!isOrderInProgress(o)) {
      return false;
    }
    return !orderHasShippedLineItems(o.Id);
  }

  /**
   * Tax-exempt toggle on the Order. Blocked once any line has shipped.
   */
  @AuraEnabled
  public static void updateOrderTaxExempt(Id orderId, Boolean taxExempt) {
    if (orderId == null) {
      throw new AuraHandledException('Order Id is required.');
    }
    try {
      Order o = [
        SELECT Id, Status, Tax_Exempt__c
        FROM Order
        WHERE Id = :orderId
        LIMIT 1
      ];
      if (!canEditOrderTaxExempt(o)) {
        throw new AuraHandledException(
          'Tax exempt status cannot be changed after the order is completed or canceled.'
        );
      }
      o.Tax_Exempt__c = taxExempt == true;
      update o;
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      throw new AuraHandledException(
        'Unable to update tax exempt status: ' + e.getMessage()
      );
    }
  }

  /**
   * Accept-partial-shipment toggle. Same ship-date lock as tax exempt.
   */
  @AuraEnabled
  public static void updateOrderAcceptPartialShipment(
    Id orderId,
    Boolean acceptPartial
  ) {
    if (orderId == null) {
      throw new AuraHandledException('Order Id is required.');
    }
    try {
      Order o = [
        SELECT Id, Status, Accept_Partial_Shipment__c
        FROM Order
        WHERE Id = :orderId
        LIMIT 1
      ];
      if (!canEditOrderAcceptPartial(o)) {
        throw new AuraHandledException(
          'Partial shipment preference cannot be changed after the order has shipped.'
        );
      }
      o.Accept_Partial_Shipment__c = acceptPartial == true;
      update o;
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      throw new AuraHandledException(
        'Unable to update partial shipment preference: ' + e.getMessage()
      );
    }
  }

  private static Object relatedSequenceField(
    QuoteLineItem qli,
    String fieldName
  ) {
    if (qli == null || String.isBlank(fieldName)) {
      return null;
    }
    SObject relatedSequence = null;
    try {
      relatedSequence = qli.getSObject('Related_Sequence__r');
    } catch (Exception e) {
      relatedSequence = null;
    }
    if (relatedSequence == null) {
      relatedSequence = (SObject) qli.getPopulatedFieldsAsMap()
        .get('Related_Sequence__r');
    }
    if (relatedSequence == null) {
      return null;
    }
    Map<String, Object> relatedFields = relatedSequence.getPopulatedFieldsAsMap();
    if (relatedFields != null && relatedFields.containsKey(fieldName)) {
      return relatedFields.get(fieldName);
    }
    try {
      return relatedSequence.get(fieldName);
    } catch (Exception e) {
      return null;
    }
  }

  private static Id quoteLineItemParentId(QuoteLineItem qli) {
    if (qli == null) {
      return null;
    }
    Map<String, Object> fields = qli.getPopulatedFieldsAsMap();
    if (fields.containsKey('Parent_Line_Item__c')) {
      return (Id) fields.get('Parent_Line_Item__c');
    }
    try {
      return qli.Parent_Line_Item__c;
    } catch (SObjectException e) {
      return null;
    }
  }

  private static String quoteLineItemClassificationStamp(QuoteLineItem qli) {
    if (qli == null) {
      return null;
    }
    Map<String, Object> fields = qli.getPopulatedFieldsAsMap();
    if (fields.containsKey('Sequence_Classification__c')) {
      return (String) fields.get('Sequence_Classification__c');
    }
    try {
      return qli.Sequence_Classification__c;
    } catch (SObjectException e) {
      return null;
    }
  }

  private static String sequenceNameFromQuoteLineItem(QuoteLineItem qli) {
    return (String) relatedSequenceField(qli, 'Sequence_Name__c');
  }

  private static String sequenceTextFromQuoteLineItem(QuoteLineItem qli) {
    return (String) relatedSequenceField(qli, 'Sequence__c');
  }

  private static Decimal sequenceLengthFromQuoteLineItem(QuoteLineItem qli) {
    Object relatedLength = relatedSequenceField(qli, 'Sequence_Length__c');
    if (relatedLength != null) {
      return Decimal.valueOf(String.valueOf(relatedLength));
    }
    String sequenceText = sequenceTextFromQuoteLineItem(qli);
    return String.isNotBlank(sequenceText) ? sequenceText.length() : null;
  }

  private static String sequenceClassificationFromQuoteLineItem(
    QuoteLineItem qli
  ) {
    String fromRelated = (String) relatedSequenceField(
      qli,
      'Sequence_Classification__c'
    );
    if (String.isNotBlank(fromRelated)) {
      return fromRelated;
    }
    // Checkout SOQL can leave Related_Sequence__r out of getPopulatedFieldsAsMap
    // after flow updates. The QLI stamp is the fallback so NCP still blocks.
    return quoteLineItemClassificationStamp(qli);
  }

  private static String feasibilityFromQuoteLineItem(QuoteLineItem qli) {
    return (String) relatedSequenceField(qli, 'Feasibility_Classifier__c');
  }

  /**
   * Order product SKU comes from QuoteLineItem.Product_SKU_RS__c (Related
   * Sequence SKU), matching Order - Create From Quote. Fall back to the
   * sequence field, then the line Product_SKU__c for fee-addon rows.
   */
  private static Object productSkuFromQuoteLineItem(QuoteLineItem qli) {
    if (qli == null) {
      return null;
    }
    Map<String, Object> qliValues = qli.getPopulatedFieldsAsMap();
    Object rsSku = qliValues.get('Product_SKU_RS__c');
    if (rsSku != null && String.isNotBlank(String.valueOf(rsSku))) {
      return rsSku;
    }
    Object relatedSku = relatedSequenceField(qli, 'Product_SKU__c');
    if (relatedSku != null && String.isNotBlank(String.valueOf(relatedSku))) {
      return relatedSku;
    }
    return qliValues.get('Product_SKU__c');
  }

  private static String portalOrderItemSequenceFields(
    Map<String, Schema.SObjectField> oiFields
  ) {
    List<String> fields = new List<String>();
    if (oiFields.containsKey('related_sequence__c')) {
      fields.add(ABT_SequenceSyncService.PORTAL_ORDER_ITEM_SEQUENCE_SUBQUERY);
    }
    if (oiFields.containsKey('sequence_name_rs__c')) {
      fields.add('Sequence_Name_RS__c');
    }
    if (oiFields.containsKey('sequence_classification_rs__c')) {
      fields.add('Sequence_Classification_RS__c');
    }
    if (oiFields.containsKey('feasibility_rs__c')) {
      fields.add('Feasibility_RS__c');
    }
    if (oiFields.containsKey('complexity_rs__c')) {
      fields.add('Complexity_RS__c');
    }
    return fields.isEmpty() ? '' : String.join(fields, ', ') + ', ';
  }

  private static String portalOrderItemQuoteLineSequenceFields(
    Map<String, Schema.SObjectField> qliFields
  ) {
    List<String> fields = new List<String>{
      'QuoteLineItem.Quote.Ansa_Quote_Number__c',
      'QuoteLineItem.Quote.QuoteNumber'
    };
    if (qliFields.containsKey('related_sequence__c')) {
      fields.add(
        ABT_SequenceSyncService.PORTAL_QUOTE_LINE_ITEM_SEQUENCE_SUBQUERY
      );
    }
    if (qliFields.containsKey('parent_line_item__c')) {
      fields.add('QuoteLineItem.Parent_Line_Item__c');
    }
    fields.add('QuoteLineItem.TotalPrice');
    fields.add('QuoteLineItem.UnitPrice');
    fields.add('QuoteLineItem.Quantity');
    if (qliFields.containsKey('scale_up_price__c')) {
      fields.add('QuoteLineItem.Scale_Up_Price__c');
    }
    if (qliFields.containsKey('glycerol_price__c')) {
      fields.add('QuoteLineItem.Glycerol_Price__c');
    }
    return String.join(fields, ', ');
  }

  private static final String SEQUENCE_CLASSIFICATION_NOT_POSSIBLE = 'Not Currently Possible';
  private static final Id INTERNAL_NCP_ORDER_ACCOUNT_ID = '001VH000006eZjdYAE';
  private static final String CHECKOUT_NO_ORDERABLE_LINES_MESSAGE = 'This quote has no orderable sequences. Sequences assessed as Not Currently Possible cannot be included in an order.';
  private static final String CHECKOUT_CART_NO_ORDERABLE_LINES_MESSAGE = 'One or more quotes contain only sequences that are Not Currently Possible and cannot be ordered.';
  private static final String CHECKOUT_ALREADY_ORDERED_MESSAGE = 'Orders have already been placed in Salesforce for one or more selected quotes. Please refresh /my-cart and try again.';
  private static final String SCRIPT_THROWN_EXCEPTION = 'Script-thrown exception';
  @TestVisible
  private static final String CHECKOUT_CUSTOMER_MESSAGE = 'We encountered an issue processing your request. We\'ve alerted our technical teams and they will be reaching out to you within 24 hours with a fix to this issue.';
  private static final String CHECKOUT_ALERT_EMAIL = 'm.souther@ansabio.com';

  /**
   * AuraHandledException.getMessage() is "Script-thrown exception" unless setMessage()
   * was called. Checkout must use this helper so the portal shows the real Flow/DML text.
   */
  @TestVisible
  private static AuraHandledException checkoutAura(String message) {
    String msg = String.isBlank(message)
      ? 'Unable to place order.'
      : message.trim();
    AuraHandledException e = new AuraHandledException(msg);
    e.setMessage(msg);
    return e;
  }

  /** Public so the cart Flow invocable can keep the real DML/Flow error text. */
  public static String checkoutExceptionMessage(Exception e) {
    if (e == null) {
      return 'Unable to place order.';
    }
    if (e instanceof DmlException) {
      DmlException dml = (DmlException) e;
      if (dml.getNumDml() > 0 && String.isNotBlank(dml.getDmlMessage(0))) {
        return dml.getDmlMessage(0);
      }
    }
    String msg = e.getMessage();
    if (String.isBlank(msg)) {
      return 'Unable to place order.';
    }
    return msg;
  }

  private static AuraHandledException checkoutAura(Exception e) {
    if (e instanceof AuraHandledException) {
      AuraHandledException ahe = (AuraHandledException) e;
      String msg = checkoutExceptionMessage(e);
      if (msg != SCRIPT_THROWN_EXCEPTION) {
        ahe.setMessage(msg);
        return ahe;
      }
    }
    return checkoutAura(checkoutExceptionMessage(e));
  }

  /**
   * Known, actionable checkout messages stay on-screen. Unexpected DML/Flow
   * failures are emailed to engineering and replaced with a customer-safe line.
   */
  @TestVisible
  private static AuraHandledException checkoutUnexpected(Exception e) {
    return checkoutUnexpected(e, null);
  }

  @TestVisible
  private static AuraHandledException checkoutUnexpected(
    Exception e,
    List<Id> quoteIds
  ) {
    String technical = checkoutExceptionMessage(e);
    if (isKnownCheckoutMessage(technical)) {
      return checkoutAura(e);
    }
    sendCheckoutFailureAlert(technical, e, quoteIds);
    return checkoutAura(CHECKOUT_CUSTOMER_MESSAGE);
  }

  @TestVisible
  private static AuraHandledException checkoutUnexpected(String message) {
    return checkoutUnexpected(message, null);
  }

  @TestVisible
  private static AuraHandledException checkoutUnexpected(
    String message,
    List<Id> quoteIds
  ) {
    if (isKnownCheckoutMessage(message)) {
      return checkoutAura(message);
    }
    sendCheckoutFailureAlert(message, null, quoteIds);
    return checkoutAura(CHECKOUT_CUSTOMER_MESSAGE);
  }

  @TestVisible
  private static Boolean isKnownCheckoutMessage(String message) {
    if (String.isBlank(message)) {
      return false;
    }
    String msg = message.trim();
    if (
      msg == CHECKOUT_CUSTOMER_MESSAGE ||
      msg == CHECKOUT_ALREADY_ORDERED_MESSAGE ||
      msg == CHECKOUT_NO_ORDERABLE_LINES_MESSAGE ||
      msg == CHECKOUT_CART_NO_ORDERABLE_LINES_MESSAGE ||
      msg == 'No quotes provided for checkout.' ||
      msg == 'You do not have permission to checkout these quotes.' ||
      msg == 'You do not have permission to checkout this quote.' ||
      msg == 'Quote Id is required.' ||
      msg ==
      'Your active cart is empty. Please return to /my-cart and try again.' ||
      msg == 'No valid quotes found for checkout.'
    ) {
      return true;
    }
    return msg.startsWith('No quote is ready for checkout yet.') ||
      msg.contains('no longer in the active cart') ||
      msg.contains('no longer available for checkout') ||
      msg.contains('missing from the checkout set');
  }

  /** Flow-to-Apex Id binding uses this exact text when a blank String is assigned to Id. */
  @TestVisible
  private static Boolean isInvalidCheckoutIdError(String message) {
    if (String.isBlank(message)) {
      return false;
    }
    String msg = message.trim();
    return msg.equalsIgnoreCase('Invalid ID') ||
      msg.toLowerCase().startsWith('invalid id');
  }

  private static void sendCheckoutFailureAlert(
    String technicalMessage,
    Exception e,
    List<Id> quoteIds
  ) {
    try {
      String subject = 'Portal checkout failure';
      String body = buildCheckoutFailureAlertBody(
        technicalMessage,
        e,
        quoteIds
      );
      // PublishImmediately so the email survives the AuraHandledException rollback.
      if (publishCheckoutFailureAlert(subject, body)) {
        return;
      }
      if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
        System.enqueueJob(new CheckoutFailureAlertJob(subject, body));
      } else {
        sendCheckoutAlertNow(subject, body);
      }
    } catch (Exception alertError) {
      System.debug(
        LoggingLevel.ERROR,
        'Failed to queue checkout alert: ' + alertError.getMessage()
      );
    }
  }

  private static Boolean publishCheckoutFailureAlert(
    String emailSubject,
    String emailBody
  ) {
    try {
      Database.SaveResult result = EventBus.publish(
        new Portal_Checkout_Failure__e(
          Email_Subject__c = emailSubject,
          Email_Body__c = emailBody
        )
      );
      return result != null && result.isSuccess();
    } catch (Exception publishError) {
      System.debug(
        LoggingLevel.ERROR,
        'Checkout alert event publish failed: ' + publishError.getMessage()
      );
      return false;
    }
  }

  public static void handleCheckoutFailureEvents(
    List<Portal_Checkout_Failure__e> events
  ) {
    if (events == null || events.isEmpty()) {
      return;
    }
    for (Portal_Checkout_Failure__e evt : events) {
      if (evt == null) {
        continue;
      }
      sendCheckoutAlertNow(evt.Email_Subject__c, evt.Email_Body__c);
    }
  }

  @TestVisible
  private static String buildCheckoutFailureAlertBody(
    String technicalMessage,
    Exception e,
    List<Id> quoteIds
  ) {
    User currentUser;
    try {
      currentUser = [
        SELECT Id, Name, Email, ContactId, AccountId, Account.Name
        FROM User
        WHERE Id = :UserInfo.getUserId()
        LIMIT 1
      ];
    } catch (Exception ignore) {
      currentUser = null;
    }

    List<String> lines = new List<String>();
    lines.add('Portal checkout failed.');
    lines.add('');
    if (currentUser != null) {
      lines.add('User: ' + currentUser.Name + ' (' + currentUser.Email + ')');
      lines.add('User Id: ' + currentUser.Id);
      if (currentUser.ContactId != null) {
        lines.add('Contact Id: ' + currentUser.ContactId);
      }
      if (currentUser.Account != null) {
        lines.add(
          'Account: ' +
            currentUser.Account.Name +
            ' (' +
            currentUser.AccountId +
            ')'
        );
      }
    } else {
      lines.add('User Id: ' + UserInfo.getUserId());
    }
    if (quoteIds != null && !quoteIds.isEmpty()) {
      List<String> quoteIdValues = new List<String>();
      for (Id quoteId : quoteIds) {
        if (quoteId != null) {
          quoteIdValues.add(String.valueOf(quoteId));
        }
      }
      lines.add('Quote Ids: ' + String.join(quoteIdValues, ', '));
    }
    lines.add('When: ' + String.valueOf(Datetime.now()));
    lines.add('');
    lines.add('Error:');
    lines.add(
      String.isBlank(technicalMessage)
        ? 'Unable to place order.'
        : technicalMessage.trim()
    );
    if (e != null && String.isNotBlank(e.getStackTraceString())) {
      lines.add('');
      lines.add('Stack:');
      lines.add(e.getStackTraceString());
    }

    String escaped = String.join(lines, '\n')
      .escapeHtml4()
      .replace('\n', '<br/>');
    return '<pre style="font-family:monospace;white-space:pre-wrap;">' +
      escaped +
      '</pre>';
  }

  @TestVisible
  private static void sendCheckoutAlertNow(
    String emailSubject,
    String emailBody
  ) {
    if (String.isBlank(emailSubject) || String.isBlank(emailBody)) {
      return;
    }
    try {
      Flow.Interview flowInterview = Flow.Interview.createInterview(
        'Cart_Portal_Email_Send',
        new Map<String, Object>{
          'toAddress' => new List<String>{ CHECKOUT_ALERT_EMAIL },
          'emailSubject' => emailSubject,
          'emailBody' => emailBody
        }
      );
      flowInterview.start();
      return;
    } catch (Exception flowError) {
      System.debug(
        LoggingLevel.ERROR,
        'Checkout alert flow failed: ' + flowError.getMessage()
      );
    }
    try {
      Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
      email.setToAddresses(new List<String>{ CHECKOUT_ALERT_EMAIL });
      email.setSubject(emailSubject);
      email.setHtmlBody(emailBody);
      Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });
    } catch (Exception emailError) {
      System.debug(
        LoggingLevel.ERROR,
        'Checkout alert email failed: ' + emailError.getMessage()
      );
    }
  }

  public class CheckoutFailureAlertJob implements Queueable {
    private final String emailSubject;
    private final String emailBody;

    public CheckoutFailureAlertJob(String emailSubject, String emailBody) {
      this.emailSubject = emailSubject;
      this.emailBody = emailBody;
    }

    public void execute(QueueableContext ctx) {
      sendCheckoutAlertNow(emailSubject, emailBody);
    }
  }

  private static void assertQuotesNotAlreadyOrdered(Set<Id> quoteIds) {
    if (quoteIds == null || quoteIds.isEmpty()) {
      return;
    }
    if (!quotesAlreadyOrdered(quoteIds).isEmpty()) {
      throw checkoutAura(CHECKOUT_ALREADY_ORDERED_MESSAGE);
    }
  }

  private static List<Id> toQuoteIds(List<String> rawIds) {
    List<Id> quoteIds = new List<Id>();
    if (rawIds == null) {
      return quoteIds;
    }
    for (String rawId : rawIds) {
      if (String.isBlank(rawId)) {
        continue;
      }
      try {
        quoteIds.add(Id.valueOf(rawId));
      } catch (Exception ignore) {
        // Skip values that are not Salesforce Ids.
      }
    }
    return quoteIds;
  }

  private static Set<Id> quotesAlreadyOrdered(Set<Id> quoteIds) {
    Set<Id> alreadyOrdered = new Set<Id>();
    if (quoteIds == null || quoteIds.isEmpty()) {
      return alreadyOrdered;
    }
    for (Quote quote : [
      SELECT Id
      FROM Quote
      WHERE Id IN :quoteIds AND (Status = 'Ordered' OR Order__c != NULL)
    ]) {
      alreadyOrdered.add(quote.Id);
    }
    for (Order existing : [
      SELECT QuoteId
      FROM Order
      WHERE QuoteId IN :quoteIds
    ]) {
      if (existing.QuoteId != null) {
        alreadyOrdered.add(existing.QuoteId);
      }
    }
    return alreadyOrdered;
  }

  /** Excludes soft-deleted portal sequences. */
  private static Boolean quoteLineItemIsActive(QuoteLineItem qli) {
    return qli != null && qli.Was_Deleted__c != true;
  }

  /** Excludes soft-deleted lines and NCP lines outside the internal account. */
  private static Boolean quoteLineItemIsOrderable(QuoteLineItem qli) {
    return quoteLineItemIsOrderable(qli, null);
  }

  private static Boolean quoteLineItemIsOrderable(
    QuoteLineItem qli,
    Id accountId
  ) {
    if (!quoteLineItemIsActive(qli)) {
      return false;
    }
    if (accountId == INTERNAL_NCP_ORDER_ACCOUNT_ID) {
      return true;
    }
    if (
      sequenceClassificationFromQuoteLineItem(qli) ==
      SEQUENCE_CLASSIFICATION_NOT_POSSIBLE
    ) {
      return false;
    }
    // Prefer Related Sequence when both are present. If that relationship was
    // blank but the QLI stamp is NCP, still block.
    return quoteLineItemClassificationStamp(qli) !=
      SEQUENCE_CLASSIFICATION_NOT_POSSIBLE;
  }

  /**
   * Fee add-ons (glycerol / scale-up) may only check out when linked to an orderable
   * parent sequence line. Orphan fee lines (no Parent Line Item and no Related Sequence)
   * are excluded so glycerol cannot ride through when its clonal parent is NCP-skipped.
   */
  @TestVisible
  private static Boolean quoteLineItemFeeAddonIsOrderable(
    QuoteLineItem feeLine,
    Set<Id> orderableSequenceLineIds,
    Set<Id> orderableRelatedSequenceIds
  ) {
    return quoteLineItemFeeAddonIsOrderable(
      feeLine,
      orderableSequenceLineIds,
      orderableRelatedSequenceIds,
      null
    );
  }

  private static Boolean quoteLineItemFeeAddonIsOrderable(
    QuoteLineItem feeLine,
    Set<Id> orderableSequenceLineIds,
    Set<Id> orderableRelatedSequenceIds,
    Id accountId
  ) {
    if (!quoteLineItemIsActive(feeLine)) {
      return false;
    }

    Map<String, Object> fields = feeLine.getPopulatedFieldsAsMap();
    Id parentLineId = fields.containsKey('Parent_Line_Item__c')
      ? (Id) fields.get('Parent_Line_Item__c')
      : null;
    Id relatedSequenceId = feeLine.Related_Sequence__c;

    if (parentLineId == null && relatedSequenceId == null) {
      return false;
    }

    if (parentLineId != null) {
      return orderableSequenceLineIds != null &&
        orderableSequenceLineIds.contains(parentLineId);
    }

    String relatedClassification = sequenceClassificationFromQuoteLineItem(
      feeLine
    );
    if (
      accountId != INTERNAL_NCP_ORDER_ACCOUNT_ID &&
      relatedClassification == SEQUENCE_CLASSIFICATION_NOT_POSSIBLE
    ) {
      return false;
    }
    return orderableRelatedSequenceIds != null &&
      orderableRelatedSequenceIds.contains(relatedSequenceId);
  }

  /**
   * Sequence lines use standard NCP/active checks. Fee add-ons require a parent/Related
   * Sequence link and are kept only when that parent sequence remains orderable.
   */
  @TestVisible
  private static List<QuoteLineItem> filterOrderableQuoteLineItems(
    List<QuoteLineItem> qlis
  ) {
    return filterOrderableQuoteLineItems(qlis, null);
  }

  @TestVisible
  private static List<QuoteLineItem> filterOrderableQuoteLineItems(
    List<QuoteLineItem> qlis,
    Id accountId
  ) {
    List<QuoteLineItem> orderable = new List<QuoteLineItem>();
    if (qlis == null || qlis.isEmpty()) {
      return orderable;
    }

    Set<Id> orderableSequenceLineIds = new Set<Id>();
    Set<Id> orderableRelatedSequenceIds = new Set<Id>();
    for (QuoteLineItem qli : qlis) {
      if (qli == null || isPortalFeeAddonQuoteLineItem(qli)) {
        continue;
      }
      if (quoteLineItemIsOrderable(qli, accountId)) {
        if (qli.Id != null) {
          orderableSequenceLineIds.add(qli.Id);
        }
        if (qli.Related_Sequence__c != null) {
          orderableRelatedSequenceIds.add(qli.Related_Sequence__c);
        }
      }
    }

    for (QuoteLineItem qli : qlis) {
      if (qli == null) {
        continue;
      }
      if (isPortalFeeAddonQuoteLineItem(qli)) {
        if (
          quoteLineItemFeeAddonIsOrderable(
            qli,
            orderableSequenceLineIds,
            orderableRelatedSequenceIds,
            accountId
          )
        ) {
          orderable.add(qli);
        }
        continue;
      }
      if (quoteLineItemIsOrderable(qli, accountId)) {
        orderable.add(qli);
      }
    }
    return orderable;
  }

  /** Quote Ids that have quote lines but none that can be ordered. */
  private static Set<Id> findQuoteIdsWithOnlyNonOrderableLines(
    List<QuoteLineItem> qlis,
    List<Id> quoteIds
  ) {
    return findQuoteIdsWithOnlyNonOrderableLines(qlis, quoteIds, null);
  }

  @TestVisible
  private static Set<Id> findQuoteIdsWithOnlyNonOrderableLines(
    List<QuoteLineItem> qlis,
    List<Id> quoteIds,
    Id accountId
  ) {
    Set<Id> quotesWithAnyLine = new Set<Id>();
    Set<Id> quotesWithOrderableLine = new Set<Id>();
    for (QuoteLineItem qli : qlis) {
      if (qli == null || qli.QuoteId == null) {
        continue;
      }
      quotesWithAnyLine.add(qli.QuoteId);
      // Fee add-ons must not keep an NCP-only quote orderable.
      if (
        !isPortalFeeAddonQuoteLineItem(qli) &&
        quoteLineItemIsOrderable(qli, accountId)
      ) {
        quotesWithOrderableLine.add(qli.QuoteId);
      }
    }
    Set<Id> blockedQuoteIds = new Set<Id>();
    for (Id quoteId : quoteIds) {
      if (
        quotesWithAnyLine.contains(quoteId) &&
        !quotesWithOrderableLine.contains(quoteId)
      ) {
        blockedQuoteIds.add(quoteId);
      }
    }
    return blockedQuoteIds;
  }

  /** Fields copied from QuoteLineItem → OrderItem when both exist in the org (mirrors Order - Create From Quote). */
  private static final List<String> QUOTE_LINE_TO_ORDER_ITEM_COPY_FIELDS = new List<String>{
    'Related_Sequence__c',
    'Sequence_Length__c',
    'Product_SKU__c',
    'Product_Code__c',
    'Parts__c',
    'Ansa_List_Price__c',
    'Sequence_Classification__c',
    'Vector__c',
    'As_Early_As_Date__c',
    'Complexity__c',
    'Complexity_Assessment__c',
    'OSC_Guaranteed__c',
    'Tranche__c',
    'MFG_Plan_Version__c',
    'Third_Party_BioSecurity_Flag__c',
    'Third_Party_Reference_ID__c',
    'Glycerol_Stock__c',
    'Glycerol_Price__c',
    'Reflex_Vector_Opt_In__c',
    // Do not copy Scale_Up__c. QuoteLineItem.Scale_Up__c looks up QuoteLineItem;
    // OrderItem.Scale_Up__c looks up Scale_Up__c. The checkbox on the order is
    // Scale_Up_Selected__c.
    'Scale_Up_Selected__c',
    'Scale_Up_Quantity__c',
    'Scale_Up_Glycerol_Stock__c',
    'Scale_Up_Buffer__c',
    'Scale_Up_Endotoxin_Free__c',
    'Scale_Up_Animal_Free__c',
    'Scale_Up_Normalization__c',
    'Scale_Up_Lead_Time__c',
    'Scale_Up_Price__c',
    'Scale_Up_Mass__c',
    'Expected_Ship_Date__c',
    'AOTG_Date__c',
    'Order_Line_Original_Promise_Date__c'
  };

  private static final List<String> QUOTE_LINE_ITEM_BASE_FIELDS = new List<String>{
    'Id',
    'QuoteId',
    'Product2Id',
    'Quantity',
    'UnitPrice',
    'TotalPrice',
    'PricebookEntryId',
    'Description',
    'Customer_ID__c',
    'Was_Deleted__c'
  };

  private static final List<String> QUOTE_LINE_SHIP_DATE_SOURCE_FIELDS = new List<String>{
    'Expected_Ship_Date__c',
    'AOTG_Date__c',
    'Order_Line_Original_Promise_Date__c',
    'As_Early_As_Date__c'
  };

  private static String quoteLineItemPortalSelectClause() {
    Map<String, Schema.SObjectField> qliFields = Schema.SObjectType.QuoteLineItem.fields.getMap();
    Set<String> selectFields = new Set<String>(QUOTE_LINE_ITEM_BASE_FIELDS);
    for (String fieldName : QUOTE_LINE_TO_ORDER_ITEM_COPY_FIELDS) {
      if (qliFields.containsKey(fieldName.toLowerCase())) {
        selectFields.add(fieldName);
      }
    }
    if (qliFields.containsKey('quote_request_line_item__c')) {
      selectFields.add('Quote_Request_Line_item__c');
    }
    if (qliFields.containsKey('product_sku_rs__c')) {
      selectFields.add('Product_SKU_RS__c');
    }
    List<String> clauseParts = new List<String>(selectFields);
    if (!selectFields.contains('Related_Sequence__c')) {
      clauseParts.add('Related_Sequence__c');
    }
    clauseParts.add(
      ABT_SequenceSyncService.portalSequenceRelationshipSubquery(
        'Related_Sequence__r'
      )
    );
    clauseParts.add('Product2.Name');
    clauseParts.add('Product2.StockKeepingUnit');
    if (qliFields.containsKey('parent_line_item__c')) {
      clauseParts.add('Parent_Line_Item__c');
    }
    clauseParts.addAll(quoteRequestLineItemRelationshipSelectFields());
    return String.join(clauseParts, ', ');
  }

  /** Subquery fields from linked quote request line (matches portal/cart date display). */
  private static List<String> quoteRequestLineItemRelationshipSelectFields() {
    Map<String, Schema.SObjectField> qliFields = Schema.SObjectType.QuoteLineItem.fields.getMap();
    if (!qliFields.containsKey('quote_request_line_item__c')) {
      return new List<String>();
    }
    Map<String, Schema.SObjectField> qrLiFields = Schema.SObjectType.ABT_Quote_Request_Lineitem__c.fields.getMap();
    List<String> relFields = new List<String>();
    for (
      String fieldName : new List<String>{
        'Expected_Ship_Date__c',
        'As_Early_As_Date__c',
        'Vector__c',
        'Reflex_Vector_Opt_In__c'
      }
    ) {
      if (qrLiFields.containsKey(fieldName.toLowerCase())) {
        relFields.add('Quote_Request_Line_item__r.' + fieldName);
      }
    }
    return relFields;
  }

  private static SObject quoteRequestLineFromQuoteLineItem(QuoteLineItem qli) {
    if (qli == null) {
      return null;
    }
    Map<String, Schema.SObjectField> qliFields = Schema.SObjectType.QuoteLineItem.fields.getMap();
    if (!qliFields.containsKey('quote_request_line_item__c')) {
      return null;
    }
    Map<String, Object> qliValues = qli.getPopulatedFieldsAsMap();
    if (!qliValues.containsKey('Quote_Request_Line_item__r')) {
      return null;
    }
    return qli.getSObject('Quote_Request_Line_item__r');
  }

  private static void putOrderItemFieldIfPresent(
    OrderItem oi,
    Map<String, Schema.SObjectField> oiFields,
    String fieldName,
    Object value
  ) {
    if (value == null) {
      return;
    }
    Schema.SObjectField fieldToken = oiFields.get(fieldName.toLowerCase());
    if (fieldToken == null) {
      return;
    }
    // Portal checkout runs as the community user; do not gate on isCreateable() here.
    // Apex DML is system mode and these fields must copy from QuoteLineItem at placement.
    Schema.DisplayType targetType = fieldToken.getDescribe().getType();
    if (
      targetType == Schema.DisplayType.REFERENCE ||
      targetType == Schema.DisplayType.ID
    ) {
      value = asCheckoutLookupId(value);
      if (value == null) {
        return;
      }
    } else if (
      !(value instanceof String) &&
      (targetType == Schema.DisplayType.String ||
      targetType == Schema.DisplayType.TextArea ||
      targetType == Schema.DisplayType.Picklist)
    ) {
      value = String.valueOf(value);
    }
    oi.put(fieldName, value);
  }

  /** Skip blank / malformed values so lookup copies cannot throw Invalid ID. */
  @TestVisible
  private static Id asCheckoutLookupId(Object value) {
    if (value == null) {
      return null;
    }
    if (value instanceof Id) {
      return (Id) value;
    }
    String raw = String.valueOf(value).trim();
    if (String.isBlank(raw)) {
      return null;
    }
    try {
      return Id.valueOf(raw);
    } catch (Exception e) {
      return null;
    }
  }

  private static Date resolveOrderItemShipDate(QuoteLineItem qli) {
    if (qli == null) {
      return null;
    }
    Map<String, Schema.SObjectField> qliFields = Schema.SObjectType.QuoteLineItem.fields.getMap();
    Map<String, Object> qliValues = qli.getPopulatedFieldsAsMap();
    for (String fieldName : QUOTE_LINE_SHIP_DATE_SOURCE_FIELDS) {
      if (
        !qliFields.containsKey(fieldName.toLowerCase()) ||
        !qliValues.containsKey(fieldName)
      ) {
        continue;
      }
      Date shipDate = (Date) qliValues.get(fieldName);
      if (shipDate != null) {
        return shipDate;
      }
    }
    // Portal/cart reads Expected_Ship_Date__c from quote request lines (formula roll-up).
    SObject qrLi = quoteRequestLineFromQuoteLineItem(qli);
    if (qrLi == null) {
      return null;
    }
    Map<String, Schema.SObjectField> qrLiFields = Schema.SObjectType.ABT_Quote_Request_Lineitem__c.fields.getMap();
    Map<String, Object> qrLiValues = qrLi.getPopulatedFieldsAsMap();
    for (
      String fieldName : new List<String>{
        'Expected_Ship_Date__c',
        'As_Early_As_Date__c'
      }
    ) {
      if (
        !qrLiFields.containsKey(fieldName.toLowerCase()) ||
        !qrLiValues.containsKey(fieldName)
      ) {
        continue;
      }
      Date shipDate = (Date) qrLiValues.get(fieldName);
      if (shipDate != null) {
        return shipDate;
      }
    }
    return null;
  }

  private static void copyQuoteRequestLineFallbackToOrderItem(
    OrderItem oi,
    QuoteLineItem qli,
    Map<String, Schema.SObjectField> oiFields
  ) {
    SObject qrLi = quoteRequestLineFromQuoteLineItem(qli);
    if (qrLi == null) {
      return;
    }
    Map<String, Schema.SObjectField> qrLiFields = Schema.SObjectType.ABT_Quote_Request_Lineitem__c.fields.getMap();
    if (
      oiFields.containsKey('vector__c') &&
      oi.get('Vector__c') == null &&
      qrLiFields.containsKey('vector__c')
    ) {
      putOrderItemFieldIfPresent(
        oi,
        oiFields,
        'Vector__c',
        qrLi.get('Vector__c')
      );
    }
    if (
      oiFields.containsKey('reflex_vector_opt_in__c') &&
      oi.get('Reflex_Vector_Opt_In__c') == null &&
      qrLiFields.containsKey('reflex_vector_opt_in__c')
    ) {
      putOrderItemFieldIfPresent(
        oi,
        oiFields,
        'Reflex_Vector_Opt_In__c',
        qrLi.get('Reflex_Vector_Opt_In__c')
      );
    }
    if (
      oiFields.containsKey('as_early_as_date__c') &&
      oi.get('As_Early_As_Date__c') == null &&
      qrLiFields.containsKey('as_early_as_date__c')
    ) {
      putOrderItemFieldIfPresent(
        oi,
        oiFields,
        'As_Early_As_Date__c',
        qrLi.get('As_Early_As_Date__c')
      );
    }
  }

  @TestVisible
  private static Decimal scaleUpPriceFromQuoteLineItem(QuoteLineItem qli) {
    if (qli == null) {
      return 0;
    }
    Map<String, Object> values = qli.getPopulatedFieldsAsMap();
    if (
      !values.containsKey('Scale_Up_Price__c') ||
      values.get('Scale_Up_Price__c') == null
    ) {
      return 0;
    }
    Decimal scaleUp = (Decimal) values.get('Scale_Up_Price__c');
    return scaleUp > 0 ? scaleUp : 0;
  }

  @TestVisible
  private static Decimal glycerolPriceFromQuoteLineItem(QuoteLineItem qli) {
    if (qli == null) {
      return 0;
    }
    Map<String, Object> values = qli.getPopulatedFieldsAsMap();
    if (
      !values.containsKey('Glycerol_Price__c') ||
      values.get('Glycerol_Price__c') == null
    ) {
      return 0;
    }
    Decimal glycerol = (Decimal) values.get('Glycerol_Price__c');
    return glycerol > 0 ? glycerol : 0;
  }

  @TestVisible
  private static Decimal quoteLineItemOrderUnitPrice(
    QuoteLineItem qli,
    Decimal fallbackUnitPrice
  ) {
    return quoteLineItemOrderUnitPrice(qli, fallbackUnitPrice, true, true);
  }

  @TestVisible
  private static Decimal quoteLineItemOrderUnitPrice(
    QuoteLineItem qli,
    Decimal fallbackUnitPrice,
    Boolean includeScaleUpField
  ) {
    return quoteLineItemOrderUnitPrice(
      qli,
      fallbackUnitPrice,
      includeScaleUpField,
      true
    );
  }

  /**
   * Order line UnitPrice is the quote line sales price (TotalPrice / Quantity).
   * Inner Scale_Up_Price__c / Glycerol_Price__c are not added — those duplicate
   * SC-001 / GS-001 children. A $0 fee child must not pick up a price-book fallback.
   */
  @TestVisible
  private static Decimal quoteLineItemOrderUnitPrice(
    QuoteLineItem qli,
    Decimal fallbackUnitPrice,
    Boolean includeScaleUpField,
    Boolean includeGlycerolField
  ) {
    Decimal qty = 1;
    if (qli != null) {
      Map<String, Object> populated = qli.getPopulatedFieldsAsMap();
      if (
        populated.containsKey('Quantity') &&
        qli.Quantity != null &&
        qli.Quantity > 0
      ) {
        qty = qli.Quantity;
      }
    }
    Decimal lineTotal = 0;
    if (qli != null) {
      if (qli.TotalPrice != null && qli.TotalPrice > 0) {
        lineTotal = qli.TotalPrice;
      } else if (qli.UnitPrice != null && qli.UnitPrice > 0) {
        lineTotal = qli.UnitPrice * qty;
      }
    }
    // Sales price on the quote line only. Inner Scale_Up_Price__c / Glycerol_Price__c
    // duplicate SC-001 / GS-001 children and must not be added here.
    if (
      (isScaleUpQuoteLineItem(qli) || isGlycerolStockQuoteLineItem(qli)) &&
      lineTotal == 0
    ) {
      return 0;
    }
    if (lineTotal == 0 && fallbackUnitPrice != null && fallbackUnitPrice > 0) {
      return fallbackUnitPrice;
    }
    return lineTotal / qty;
  }

  @TestVisible
  private static Boolean quoteLineItemHasPositiveAmount(QuoteLineItem qli) {
    if (qli == null) {
      return false;
    }
    if (qli.TotalPrice != null && qli.TotalPrice > 0) {
      return true;
    }
    return qli.UnitPrice != null && qli.UnitPrice > 0;
  }

  @TestVisible
  private static Boolean quoteLineItemsIncludeScaleUpChild(
    List<QuoteLineItem> quoteLineItems
  ) {
    return quoteLineItemsIncludePositiveFeeChild(quoteLineItems, true);
  }

  @TestVisible
  private static Boolean quoteLineItemsIncludeGlycerolChild(
    List<QuoteLineItem> quoteLineItems
  ) {
    return quoteLineItemsIncludePositiveFeeChild(quoteLineItems, false);
  }

  private static Boolean quoteLineItemsIncludePositiveFeeChild(
    List<QuoteLineItem> quoteLineItems,
    Boolean scaleUp
  ) {
    if (quoteLineItems == null || quoteLineItems.isEmpty()) {
      return false;
    }
    for (QuoteLineItem qli : quoteLineItems) {
      Boolean isFee = scaleUp
        ? isScaleUpQuoteLineItem(qli)
        : isGlycerolStockQuoteLineItem(qli);
      if (isFee && quoteLineItemHasPositiveAmount(qli)) {
        return true;
      }
    }
    return false;
  }

  @TestVisible
  private static void clearOrderItemScaleUpPriceField(OrderItem oi) {
    if (oi == null) {
      return;
    }
    Map<String, Schema.SObjectField> oiFields = Schema.SObjectType.OrderItem.fields.getMap();
    if (oiFields.containsKey('scale_up_price__c')) {
      oi.put('Scale_Up_Price__c', 0);
    }
  }

  @TestVisible
  private static void copyQuoteLineItemToOrderItem(
    OrderItem oi,
    QuoteLineItem qli,
    Id orderQuoteId
  ) {
    if (oi == null || qli == null) {
      return;
    }
    Map<String, Schema.SObjectField> qliFields = Schema.SObjectType.QuoteLineItem.fields.getMap();
    Map<String, Schema.SObjectField> oiFields = Schema.SObjectType.OrderItem.fields.getMap();
    Map<String, Object> qliValues = qli.getPopulatedFieldsAsMap();
    if (oiFields.containsKey('salesforce_quote_line_id__c')) {
      oi.put('Salesforce_Quote_Line_ID__c', (String) qli.Id);
    }
    // QuoteLineItemId must reference a line on the Order's Quote. Multi-quote cart
    // checkout creates one Order tied to the primary quote only.
    if (
      oiFields.containsKey('quotelineitemid') &&
      (orderQuoteId == null ||
      qli.QuoteId == orderQuoteId)
    ) {
      oi.QuoteLineItemId = qli.Id;
    }
    for (String fieldName : QUOTE_LINE_TO_ORDER_ITEM_COPY_FIELDS) {
      if (
        !qliFields.containsKey(fieldName.toLowerCase()) ||
        !oiFields.containsKey(fieldName.toLowerCase()) ||
        !qliValues.containsKey(fieldName)
      ) {
        continue;
      }
      try {
        putOrderItemFieldIfPresent(
          oi,
          oiFields,
          fieldName,
          qliValues.get(fieldName)
        );
      } catch (Exception ex) {
        throw checkoutAura(
          'Failed copying field ' + fieldName + ': ' + ex.getMessage()
        );
      }
    }
    copyQuoteRequestLineFallbackToOrderItem(oi, qli, oiFields);
    applyQuoteLineSequenceFieldsToOrderItem(oi, qli);
    overlaySequenceSourceOfTruthOnOrderItem(oi, qli, oiFields);
    Date shipDate = resolveOrderItemShipDate(qli);
    putOrderItemFieldIfPresent(oi, oiFields, 'Expected_Ship_Date__c', shipDate);
    putOrderItemFieldIfPresent(
      oi,
      oiFields,
      'Original_Promise_Date__c',
      shipDate
    );
    putOrderItemFieldIfPresent(oi, oiFields, 'Order_Date__c', Date.today());
  }

  @TestVisible
  private static void enrichOrderItemSequenceNames(List<OrderItem> items) {
    if (items == null || items.isEmpty()) {
      return;
    }
    for (OrderItem oi : items) {
      Map<String, Object> oiFields = oi.getPopulatedFieldsAsMap();
      if (
        oiFields.get('Related_Sequence__c') != null ||
        oiFields.containsKey('Related_Sequence__r')
      ) {
        continue;
      }
      if (!oiFields.containsKey('QuoteLineItem')) {
        continue;
      }
      applyQuoteLineSequenceFieldsToOrderItem(
        oi,
        (QuoteLineItem) oiFields.get('QuoteLineItem')
      );
    }
  }

  private static void applyQuoteLineSequenceFieldsToOrderItem(
    OrderItem oi,
    QuoteLineItem qli
  ) {
    if (oi == null || qli == null) {
      return;
    }
    Map<String, Object> qliFields = qli.getPopulatedFieldsAsMap();
    if (
      oi.Related_Sequence__c == null &&
      qliFields.get('Related_Sequence__c') != null
    ) {
      oi.Related_Sequence__c = (Id) qliFields.get('Related_Sequence__c');
    }
    if (qliFields.containsKey('Related_Sequence__r')) {
      oi.Related_Sequence__r = (Sequence__c) qliFields.get(
        'Related_Sequence__r'
      );
    }
  }

  /** Sequence__c wins over stale Quote Line Item copies at portal checkout. */
  private static void overlaySequenceSourceOfTruthOnOrderItem(
    OrderItem oi,
    QuoteLineItem qli,
    Map<String, Schema.SObjectField> oiFields
  ) {
    if (oi == null || qli == null || oiFields == null) {
      return;
    }
    putOrderItemFieldIfPresent(
      oi,
      oiFields,
      'Sequence_Classification__c',
      sequenceClassificationFromQuoteLineItem(qli)
    );
    putOrderItemFieldIfPresent(
      oi,
      oiFields,
      'Sequence_Length__c',
      sequenceLengthFromQuoteLineItem(qli)
    );
    putOrderItemFieldIfPresent(
      oi,
      oiFields,
      'Sequence_Name__c',
      sequenceNameFromQuoteLineItem(qli)
    );
    putOrderItemFieldIfPresent(
      oi,
      oiFields,
      'Complexity__c',
      relatedSequenceField(qli, 'Complexity__c')
    );
    putOrderItemFieldIfPresent(
      oi,
      oiFields,
      'Complexity_Assessment__c',
      relatedSequenceField(qli, 'Complexity_Assessment__c')
    );
    Object vectorId = relatedSequenceField(qli, 'Vector__c');
    if (vectorId != null) {
      putOrderItemFieldIfPresent(oi, oiFields, 'Vector__c', vectorId);
    }
    putOrderItemFieldIfPresent(
      oi,
      oiFields,
      'Product_SKU__c',
      productSkuFromQuoteLineItem(qli)
    );
  }

  /**
   * Order products for portal order detail. Hides fee-addon SKUs (Scale Up / Glycerol)
   * from the sequence table so the customer only sees DNA lines.
   */
  @AuraEnabled(cacheable=true)
  public static List<OrderItem> getOrderItemRelatedList(Id recordId) {
    try {
      return preparePortalOrderItems(queryPortalOrderItems(recordId));
    } catch (Exception e) {
      System.debug(
        LoggingLevel.WARN,
        'getOrderItemRelatedList fallback for order ' +
          recordId +
          ': ' +
          e.getMessage()
      );
      try {
        List<OrderItem> items = [
          SELECT
            Id,
            Related_Sequence__c,
            Related_Sequence__r.Sequence_Name__c,
            Related_Sequence__r.Sequence__c,
            Related_Sequence__r.Sequence_Length__c,
            Related_Sequence__r.Sequence_Classification__c,
            Related_Sequence__r.Feasibility_Classifier__c,
            Related_Sequence__r.Feasibility_Explained__c,
            Related_Sequence__r.Feasibility_Explained_1__c,
            Related_Sequence__r.Feasibility_Explained_2__c,
            Related_Sequence__r.Feasibility_Explained_3__c,
            Related_Sequence__r.Complexity__c,
            Sequence_Name_RS__c,
            Sequence_Classification_RS__c,
            Feasibility_RS__c,
            Complexity_RS__c,
            Product2Id,
            Product2.Id,
            Product2.Name,
            Product2.StockKeepingUnit,
            Product_SKU__c,
            Product_Code__c,
            Vector_Name__c,
            Scale_Up__c,
            Scale_Up__r.Name,
            Scale_Up_Price__c,
            Glycerol_Price__c,
            Confirmed_Ship_Date__c,
            Expected_Ship_Date__c,
            As_Early_As_Date__c,
            Original_Promise_Date__c,
            UnitPrice,
            Tracking_Number__c,
            TotalPrice,
            Quantity,
            Tranche__c,
            Status__c,
            QuoteLineItemId,
            Order.OrderNumber,
            Order.QuoteId,
            Order.Quote.QuoteNumber,
            Order.Ansa_Quote_Number__c,
            QuoteLineItem.Related_Sequence__c,
            QuoteLineItem.Related_Sequence__r.Sequence_Name__c,
            QuoteLineItem.Related_Sequence__r.Sequence__c,
            QuoteLineItem.Related_Sequence__r.Sequence_Length__c,
            QuoteLineItem.Related_Sequence__r.Sequence_Classification__c,
            QuoteLineItem.Related_Sequence__r.Feasibility_Classifier__c,
            QuoteLineItem.Related_Sequence__r.Feasibility_Explained__c,
            QuoteLineItem.Related_Sequence__r.Feasibility_Explained_1__c,
            QuoteLineItem.Related_Sequence__r.Feasibility_Explained_2__c,
            QuoteLineItem.Related_Sequence__r.Feasibility_Explained_3__c,
            QuoteLineItem.Related_Sequence__r.Complexity__c
          FROM OrderItem
          WHERE OrderId = :recordId
          ORDER BY CreatedDate ASC
        ];
        return preparePortalOrderItems(items);
      } catch (Exception fallbackEx) {
        System.debug(
          LoggingLevel.ERROR,
          'getOrderItemRelatedList failed for order ' +
            recordId +
            ': ' +
            fallbackEx.getMessage()
        );
        return new List<OrderItem>();
      }
    }
  }

  private static List<OrderItem> filterVisiblePortalOrderItems(
    List<OrderItem> items
  ) {
    List<OrderItem> visible = new List<OrderItem>();
    if (items == null) {
      return visible;
    }
    for (OrderItem oi : items) {
      if (!isPortalFeeAddonOrderItem(oi)) {
        visible.add(oi);
      }
    }
    return visible;
  }

  private static List<OrderItem> preparePortalOrderItems(
    List<OrderItem> items
  ) {
    enrichOrderItemSequenceNames(items);
    return filterVisiblePortalOrderItems(items);
  }

  /**
   * Glycerol fee per OrderItem (sequence name → price) for the order-detail
   * add-on column. Empty map if the order has no glycerol lines.
   */
  @AuraEnabled(cacheable=true)
  public static Map<String, Decimal> getOrderItemGlycerolAddons(Id recordId) {
    Map<String, Decimal> result = new Map<String, Decimal>();
    if (recordId == null) {
      return result;
    }
    try {
      List<OrderItem> items = queryPortalOrderItems(recordId);
      enrichOrderItemSequenceNames(items);
      List<OrderItem> visible = filterVisiblePortalOrderItems(items);
      Map<Id, Decimal> addons = computeGlycerolAddonByOrderItemId(
        items,
        visible
      );
      for (Id itemId : addons.keySet()) {
        result.put(String.valueOf(itemId), addons.get(itemId));
      }
    } catch (Exception e) {
      System.debug(
        LoggingLevel.WARN,
        'getOrderItemGlycerolAddons failed for order ' +
          recordId +
          ': ' +
          e.getMessage()
      );
    }
    return result;
  }

  @TestVisible
  private static Decimal orderItemLineAmount(OrderItem oi) {
    if (oi == null) {
      return 0;
    }
    if (oi.TotalPrice != null) {
      return oi.TotalPrice;
    }
    if (oi.UnitPrice != null && oi.Quantity != null) {
      return oi.UnitPrice * oi.Quantity;
    }
    if (oi.UnitPrice != null) {
      return oi.UnitPrice;
    }
    return 0;
  }

  private static Decimal orderItemParentScaleUpPrice(OrderItem oi) {
    return orderItemParentFeeAmount(oi, 'Scale_Up_Price__c');
  }

  private static Decimal orderItemParentGlycerolPrice(OrderItem oi) {
    return orderItemParentFeeAmount(oi, 'Glycerol_Price__c');
  }

  private static Decimal orderItemParentFeeAmount(
    OrderItem oi,
    String fieldName
  ) {
    if (oi == null) {
      return 0;
    }
    Map<String, Object> values = oi.getPopulatedFieldsAsMap();
    if (values.containsKey(fieldName)) {
      Decimal amount = (Decimal) values.get(fieldName);
      return amount != null && amount > 0 ? amount : 0;
    }
    return populatedPositiveCurrency(oi.QuoteLineItem, fieldName);
  }

  private static Decimal populatedPositiveCurrency(
    SObject rec,
    String fieldName
  ) {
    if (rec == null || String.isBlank(fieldName)) {
      return 0;
    }
    Map<String, Object> values = rec.getPopulatedFieldsAsMap();
    if (!values.containsKey(fieldName) || values.get(fieldName) == null) {
      return 0;
    }
    Decimal amount = (Decimal) values.get(fieldName);
    return amount > 0 ? amount : 0;
  }

  private static Decimal quoteLineDnaAmountForOrderItem(OrderItem oi) {
    if (oi == null || oi.QuoteLineItem == null) {
      return null;
    }
    QuoteLineItem qli = oi.QuoteLineItem;
    if (qli.TotalPrice != null && qli.TotalPrice > 0) {
      return qli.TotalPrice;
    }
    if (qli.UnitPrice != null && qli.UnitPrice > 0) {
      Decimal qty = (qli.Quantity != null &&
        qli.Quantity > 0)
        ? qli.Quantity
        : 1;
      return qli.UnitPrice * qty;
    }
    return null;
  }

  private static Boolean orderItemAlreadyIncludesParentFee(
    Decimal orderAmount,
    Decimal dnaSource,
    Decimal parentFee,
    Decimal pricedChildTotal
  ) {
    if (parentFee == null || parentFee <= 0) {
      return false;
    }
    Decimal lineAmount = orderAmount != null ? orderAmount : 0;
    if (dnaSource != null) {
      return lineAmount + 0.01 >= dnaSource + parentFee;
    }
    // Without the quote-line DNA amount, DNA ($375) is almost always larger
    // than glycerol ($30). Only treat a large parent fee as already baked.
    return pricedChildTotal <= 0 &&
      lineAmount >= parentFee &&
      parentFee * 2 >= lineAmount;
  }

  @TestVisible
  private static String sequenceNameFromOrderItem(OrderItem oi) {
    if (oi == null) {
      return null;
    }
    Map<String, Object> fields = oi.getPopulatedFieldsAsMap();
    SObject relatedSequence = (SObject) fields.get('Related_Sequence__r');
    if (relatedSequence != null) {
      String name = (String) relatedSequence.get('Sequence_Name__c');
      if (String.isNotBlank(name)) {
        return name;
      }
    }
    // Only touch QuoteLineItem when it was queried — otherwise Apex throws SObjectException.
    if (fields.containsKey('QuoteLineItem')) {
      String name = sequenceNameFromQuoteLineItem(
        (QuoteLineItem) fields.get('QuoteLineItem')
      );
      if (String.isNotBlank(name)) {
        return name;
      }
    }
    if (fields.containsKey('Sequence_Name__c')) {
      String name = (String) fields.get('Sequence_Name__c');
      if (String.isNotBlank(name)) {
        return name;
      }
    }
    if (fields.containsKey('Sequence_Name_RS__c')) {
      String name = (String) fields.get('Sequence_Name_RS__c');
      if (String.isNotBlank(name)) {
        return name;
      }
    }
    return null;
  }

  @TestVisible
  private static String orderItemSequenceKey(OrderItem oi) {
    String name = sequenceNameFromOrderItem(oi);
    return String.isBlank(name) ? null : name.trim().toLowerCase();
  }

  @TestVisible
  private static Id resolveOrderItemQuoteLineItemId(OrderItem oi) {
    if (oi == null) {
      return null;
    }
    if (oi.QuoteLineItemId != null) {
      return oi.QuoteLineItemId;
    }
    Map<String, Schema.SObjectField> oiFields = Schema.SObjectType.OrderItem.fields.getMap();
    if (!oiFields.containsKey('salesforce_quote_line_id__c')) {
      return null;
    }
    String rawLineId = (String) oi.get('Salesforce_Quote_Line_ID__c');
    if (String.isBlank(rawLineId)) {
      return null;
    }
    try {
      return Id.valueOf(rawLineId.trim());
    } catch (Exception e) {
      return null;
    }
  }

  /**
   * Quote-page math for an order: visible DNA line amounts plus parent Scale Up /
   * Glycerol fields (or fee children when those parent fields are zero).
   */
  @TestVisible
  private static Decimal portalOrderProductSubtotal(Id orderId) {
    if (orderId == null) {
      return 0;
    }
    try {
      List<OrderItem> items = queryPortalOrderItems(orderId);
      enrichOrderItemSequenceNames(items);
      List<OrderItem> visible = filterVisiblePortalOrderItems(items);
      return portalOrderProductSubtotal(items, visible);
    } catch (Exception e) {
      System.debug(
        LoggingLevel.WARN,
        'portalOrderProductSubtotal failed for order ' +
          orderId +
          ': ' +
          e.getMessage()
      );
      return 0;
    }
  }

  @TestVisible
  private static Decimal portalOrderProductSubtotal(
    List<OrderItem> allItems,
    List<OrderItem> visibleItems
  ) {
    if (visibleItems == null || visibleItems.isEmpty()) {
      return 0;
    }
    Map<Id, Decimal> addons = computeGlycerolAddonByOrderItemId(
      allItems,
      visibleItems
    );
    Decimal productSubtotal = 0;
    for (OrderItem visible : visibleItems) {
      productSubtotal += orderItemLineAmount(visible);
      if (addons.containsKey(visible.Id)) {
        productSubtotal += addons.get(visible.Id);
      }
    }
    return productSubtotal;
  }

  @TestVisible
  private static Map<Id, Decimal> computeGlycerolAddonByOrderItemId(
    List<OrderItem> allItems,
    List<OrderItem> visibleItems
  ) {
    Map<Id, Decimal> glycerolAddonByOrderItemId = new Map<Id, Decimal>();
    if (allItems == null || visibleItems == null || visibleItems.isEmpty()) {
      return glycerolAddonByOrderItemId;
    }

    Map<String, Schema.SObjectField> oiFields = Schema.SObjectType.OrderItem.fields.getMap();
    Boolean hasParentSequence = oiFields.containsKey('parent_sequence__c');

    Map<Id, Decimal> glycerolByParentOrderItemId = new Map<Id, Decimal>();
    Map<Id, Decimal> glycerolByParentQuoteLineId = new Map<Id, Decimal>();
    Map<String, Decimal> glycerolBySequenceKey = new Map<String, Decimal>();
    Decimal unlinkedFeeTotal = 0;

    for (OrderItem oi : allItems) {
      // Roll hidden Scale Up + Glycerol fee lines onto the parent sequence total.
      if (!isPortalFeeAddonOrderItem(oi)) {
        continue;
      }
      Decimal feeAmount = orderItemLineAmount(oi);
      if (feeAmount <= 0) {
        continue;
      }

      Boolean linked = false;
      if (hasParentSequence && oi.get('Parent_Sequence__c') != null) {
        Id parentOrderItemId = (Id) oi.get('Parent_Sequence__c');
        glycerolByParentOrderItemId.put(
          parentOrderItemId,
          (glycerolByParentOrderItemId.containsKey(parentOrderItemId)
            ? glycerolByParentOrderItemId.get(parentOrderItemId)
            : 0) + feeAmount
        );
        linked = true;
      }

      if (
        oi.QuoteLineItem != null &&
        oi.QuoteLineItem.get('Parent_Line_Item__c') != null
      ) {
        Id parentQuoteLineId = (Id) oi.QuoteLineItem.get('Parent_Line_Item__c');
        glycerolByParentQuoteLineId.put(
          parentQuoteLineId,
          (glycerolByParentQuoteLineId.containsKey(parentQuoteLineId)
            ? glycerolByParentQuoteLineId.get(parentQuoteLineId)
            : 0) + feeAmount
        );
        linked = true;
      }

      String sequenceKey = orderItemSequenceKey(oi);
      if (String.isNotBlank(sequenceKey)) {
        glycerolBySequenceKey.put(
          sequenceKey,
          (glycerolBySequenceKey.containsKey(sequenceKey)
            ? glycerolBySequenceKey.get(sequenceKey)
            : 0) + feeAmount
        );
        linked = true;
      }

      // Prod Scale Up Glycerol child lines often have blank Sequence_Name and no Parent_Line_Item.
      if (!linked) {
        unlinkedFeeTotal += feeAmount;
      }
    }

    for (OrderItem visible : visibleItems) {
      Decimal feeAddon = 0;
      if (glycerolByParentOrderItemId.containsKey(visible.Id)) {
        feeAddon = glycerolByParentOrderItemId.get(visible.Id);
      }
      if (feeAddon <= 0) {
        Id quoteLineId = resolveOrderItemQuoteLineItemId(visible);
        if (
          quoteLineId != null &&
          glycerolByParentQuoteLineId.containsKey(quoteLineId)
        ) {
          feeAddon = glycerolByParentQuoteLineId.get(quoteLineId);
        }
      }
      if (feeAddon <= 0) {
        String sequenceKey = orderItemSequenceKey(visible);
        if (
          String.isNotBlank(sequenceKey) &&
          glycerolBySequenceKey.containsKey(sequenceKey)
        ) {
          feeAddon = glycerolBySequenceKey.get(sequenceKey);
        }
      }
      if (feeAddon > 0) {
        glycerolAddonByOrderItemId.put(visible.Id, feeAddon);
      }
    }

    // Attach orphan fee lines (e.g. GS-001 with blank name / no parent) to the only visible sequence.
    if (unlinkedFeeTotal > 0 && visibleItems.size() == 1) {
      Id soleVisibleId = visibleItems[0].Id;
      Decimal existing = glycerolAddonByOrderItemId.containsKey(soleVisibleId)
        ? glycerolAddonByOrderItemId.get(soleVisibleId)
        : 0;
      glycerolAddonByOrderItemId.put(
        soleVisibleId,
        existing + unlinkedFeeTotal
      );
    }

    return glycerolAddonByOrderItemId;
  }

  private static List<OrderItem> queryPortalOrderItems(Id orderId) {
    Map<String, Schema.SObjectField> oiFields = Schema.SObjectType.OrderItem.fields.getMap();
    Map<String, Schema.SObjectField> qliFields = Schema.SObjectType.QuoteLineItem.fields.getMap();

    String query =
      'SELECT Id, ' +
      portalOrderItemSequenceFields(oiFields) +
      'Product2Id, Product2.Id, Product2.Name, Product2.StockKeepingUnit,' +
      ' Vector_Name__c, Scale_Up__c, Scale_Up__r.Name, Scale_Up_Price__c,' +
      ' Confirmed_Ship_Date__c, Expected_Ship_Date__c,' +
      ' As_Early_As_Date__c, Original_Promise_Date__c,' +
      ' UnitPrice, Tracking_Number__c, TotalPrice, Quantity, Tranche__c, Status__c,' +
      ' QuoteLineItemId, Order.OrderNumber, Order.QuoteId, Order.Quote.QuoteNumber,' +
      ' Order.Ansa_Quote_Number__c, ' +
      portalOrderItemQuoteLineSequenceFields(qliFields);

    if (oiFields.containsKey('glycerol_price__c')) {
      query += ', Glycerol_Price__c';
    }
    if (oiFields.containsKey('salesforce_quote_line_id__c')) {
      query += ', Salesforce_Quote_Line_ID__c';
    }
    if (oiFields.containsKey('parent_sequence__c')) {
      query += ', Parent_Sequence__c';
    }
    if (oiFields.containsKey('product_sku__c')) {
      query += ', Product_SKU__c';
    }
    if (oiFields.containsKey('product_code__c')) {
      query += ', Product_Code__c';
    }

    query +=
      ' FROM OrderItem WHERE OrderId = :orderId' + ' ORDER BY CreatedDate ASC';

    return Database.query(query);
  }

  /**
   * Saved cards for this Contact. cacheable for first paint; use Fresh after adding a card.
   */
  @AuraEnabled(cacheable=true)
  public static List<ABT_Payment_Method__c> getPaymentMethodsByContact(
    Id contactId
  ) {
    return queryPaymentMethodsByContact(contactId);
  }

  /**
   * Same card list, uncached, after adding a card from the wallet.
   */
  @AuraEnabled
  public static List<ABT_Payment_Method__c> getPaymentMethodsByContactFresh(
    Id contactId
  ) {
    return queryPaymentMethodsByContact(contactId);
  }

  private static List<ABT_Payment_Method__c> queryPaymentMethodsByContact(
    Id contactId
  ) {
    try {
      if (contactId == null) {
        return new List<ABT_Payment_Method__c>();
      }
      return [
        SELECT
          Id,
          ABT_Card_Number__c,
          ABT_Card_Last_4_Digit__c,
          ABT_Card_Holder_Name__c,
          ABT_Card_Brand__c,
          CreatedDate
        FROM ABT_Payment_Method__c
        WHERE ABT_Contact__c = :contactId
        ORDER BY CreatedDate DESC
      ];
    } catch (Exception e) {
      throw new AuraHandledException(
        'Error fetching payment methods: ' + e.getMessage()
      );
    }
  }

  /**
   * Soft-remove a saved card from the portal wallet. Does not delete the payment
   * method in Stripe — CX/finance still have the record.
   */
  @AuraEnabled
  public static void deletePaymentMethod(Id paymentMethodId) {
    if (paymentMethodId == null) {
      throw new AuraHandledException('Payment method Id is required.');
    }

    try {
      User currentUser = [
        SELECT ContactId
        FROM User
        WHERE Id = :UserInfo.getUserId()
        LIMIT 1
      ];
      if (currentUser.ContactId == null) {
        throw new AuraHandledException(
          'You are not authorized to delete this payment method.'
        );
      }

      ABT_Payment_Method__c paymentMethod = [
        SELECT Id, ABT_Contact__c, ABT_Stripe_Payment_Method_Id__c
        FROM ABT_Payment_Method__c
        WHERE Id = :paymentMethodId
        LIMIT 1
      ];
      if (paymentMethod.ABT_Contact__c != currentUser.ContactId) {
        throw new AuraHandledException(
          'You are not authorized to delete this payment method.'
        );
      }

      if (String.isNotBlank(paymentMethod.ABT_Stripe_Payment_Method_Id__c)) {
        try {
          Map<String, Object> flowInputs = new Map<String, Object>{
            'paymentMethodId' => paymentMethodId
          };
          Flow.Interview flowInterview = Flow.Interview.createInterview(
            'ABT_Detach_Payment_Method',
            flowInputs
          );
          flowInterview.start();

          List<ABT_Payment_Method__c> remaining = [
            SELECT Id
            FROM ABT_Payment_Method__c
            WHERE Id = :paymentMethodId
            LIMIT 1
          ];
          if (remaining.isEmpty()) {
            return;
          }
        } catch (Exception flowError) {
          System.debug(
            LoggingLevel.WARN,
            'Stripe detach flow failed; deleting Salesforce payment method. ' +
            flowError.getMessage()
          );
        }
      }

      delete paymentMethod;
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      throw new AuraHandledException(
        'Error deleting payment method: ' + e.getMessage()
      );
    }
  }

  /**
   * Default CPA Id for checkout (billing or shipping). cacheable for first paint.
   */
  @AuraEnabled(cacheable=true)
  public static String getDefaultAddressId(Id accountId, String addressType) {
    return queryDefaultAddressId(accountId, addressType);
  }

  /**
   * Uncached default after the address form saves, so checkout sees the new default.
   */
  @AuraEnabled
  public static String getDefaultAddressIdFresh(
    Id accountId,
    String addressType
  ) {
    return queryDefaultAddressId(accountId, addressType);
  }

  private static String queryDefaultAddressId(
    Id accountId,
    String addressType
  ) {
    if (accountId == null) {
      return null;
    }
    try {
      List<String> addressTypes = resolveContactPointAddressTypes(addressType);
      List<ContactPointAddress> defaults = [
        SELECT Id
        FROM ContactPointAddress
        WHERE
          ParentId = :accountId
          AND AddressType IN :addressTypes
          AND IsDefault = TRUE
        ORDER BY LastModifiedDate DESC
        LIMIT 1
      ];
      return defaults.isEmpty() ? null : defaults[0].Id;
    } catch (Exception e) {
      return null;
    }
  }

  /**
   * Invoice status + Stripe payment link for the portal pay screen.
   */
  @AuraEnabled(cacheable=true)
  public static ABT_Invoice__c getInvoiceById(Id recordId) {
    return [
      SELECT Id, ABT_Status__c, ABT_Stripe_Payment_Link__c
      FROM ABT_Invoice__c
      WHERE Id = :recordId
      LIMIT 1
    ];
  }

  /**
   * Attach a PO PDF to the Quote/Order from checkout. Strips the data-URL header
   * if the LWC sent base64 with a mime prefix.
   */
  @AuraEnabled
  public static String uploadPODocument(
    String base64Data,
    String fileName,
    String contentType,
    Id parentId
  ) {
    try {
      // Remove header from base64 data if present
      if (base64Data.contains(',')) {
        base64Data = base64Data.substringAfter(',');
      }

      // Create ContentVersion
      ContentVersion cv = new ContentVersion();
      cv.VersionData = EncodingUtil.base64Decode(base64Data);
      cv.Title = fileName;
      cv.PathOnClient = fileName;
      cv.IsMajorVersion = true;

      insert cv;

      // Get the ContentDocumentId from the ContentVersion record
      ContentVersion cvInserted = [
        SELECT ContentDocumentId
        FROM ContentVersion
        WHERE Id = :cv.Id
        LIMIT 1
      ];

      // Create ContentDocumentLink record to link the file to the parent record
      ContentDocumentLink cdl = new ContentDocumentLink();
      cdl.ContentDocumentId = cvInserted.ContentDocumentId;
      cdl.LinkedEntityId = parentId;
      cdl.ShareType = 'V'; // V = Viewer, C = Collaborator, I = Inferred
      cdl.Visibility = 'AllUsers';

      insert cdl;

      // // Update the Quote Request with a reference to this PO document
      // if (parentId.getSObjectType().getDescribe().getName() == 'ABT_Quote_Request__c') {
      //     ABT_Quote_Request__c quoteRequest = new ABT_Quote_Request__c(
      //         Id = parentId,
      //         ABT_PO_Document_Id__c = cvInserted.ContentDocumentId
      //     );
      //     update quoteRequest;
      // }

      return cvInserted.ContentDocumentId;
    } catch (Exception e) {
      throw new AuraHandledException('Error uploading file: ' + e.getMessage());
    }
  }

  /**
   * Quote-request page Apply. Validates the code and leaves Promo_Code__c for submit.
   */
  @AuraEnabled
  public static Map<String, Object> applyPromoCodeToQuoteRequest(
    Id quoteRequestId,
    String promoCode
  ) {
    List<Id> quoteRequestIds = quoteRequestId == null
      ? new List<Id>()
      : new List<Id>{ quoteRequestId };
    return applyPromoCodeToQuoteRequests(quoteRequestIds, promoCode, false);
  }

  /**
   * Existing checkout promo for quote requests already discounted in Salesforce.
   */
  @AuraEnabled
  public static Map<String, Object> getCheckoutPromoState(
    List<Id> quoteRequestIds
  ) {
    Map<String, Object> result = new Map<String, Object>();
    result.put('hasPromo', false);
    if (quoteRequestIds == null || quoteRequestIds.isEmpty()) {
      return result;
    }

    List<ABT_Quote_Request__c> quoteRequests = [
      SELECT
        Id,
        Promo_Code__c,
        Promo_Code__r.Name,
        Promo_Code__r.Promo_Code__c,
        Promo_Code__r.Discount_Percentage__c,
        ABT_Quote__r.Discount__c,
        ABT_Quote__r.Discount_Amount__c,
        ABT_Quote__r.Subtotal
      FROM ABT_Quote_Request__c
      WHERE Id IN :quoteRequestIds
    ];

    Decimal originalSubtotal = 0;
    Decimal discountAmount = 0;
    Decimal discountPercentage = null;
    Id promoCodeId = null;
    String promoCode = null;
    Boolean hasPromo = false;

    for (ABT_Quote_Request__c quoteRequest : quoteRequests) {
      if (quoteRequest.ABT_Quote__r != null) {
        if (quoteRequest.ABT_Quote__r.Subtotal != null) {
          originalSubtotal += quoteRequest.ABT_Quote__r.Subtotal;
        }
        if (quoteRequest.ABT_Quote__r.Discount_Amount__c != null) {
          discountAmount += quoteRequest.ABT_Quote__r.Discount_Amount__c;
        }
        if (
          quoteRequest.ABT_Quote__r.Discount__c != null &&
          quoteRequest.ABT_Quote__r.Discount__c > 0
        ) {
          discountPercentage = quoteRequest.ABT_Quote__r.Discount__c;
          hasPromo = true;
        }
      }
      if (quoteRequest.Promo_Code__c != null) {
        hasPromo = true;
        if (promoCodeId == null) {
          promoCodeId = quoteRequest.Promo_Code__c;
          promoCode = String.isNotBlank(
              quoteRequest.Promo_Code__r.Promo_Code__c
            )
            ? quoteRequest.Promo_Code__r.Promo_Code__c
            : quoteRequest.Promo_Code__r.Name;
          if (discountPercentage == null) {
            discountPercentage = quoteRequest.Promo_Code__r.Discount_Percentage__c;
          }
        }
      }
    }

    result.put('hasPromo', hasPromo);
    result.put('promoCodeId', promoCodeId);
    result.put('promoCode', promoCode);
    result.put('discountPercentage', discountPercentage);
    result.put('discountAmount', discountAmount);
    result.put('originalSubtotal', originalSubtotal);
    return result;
  }

  /**
   * Checkout Apply previews the discount and does not write Promo_Code__c.
   * Place Order writes it, and a multi-quote cart writes the first quote only.
   * commitToQuote true writes immediately. Checkout does not use that path.
   */
  @AuraEnabled
  public static Map<String, Object> applyPromoCodeToQuoteRequests(
    List<Id> quoteRequestIds,
    String promoCode,
    Boolean commitToQuote
  ) {
    Map<String, Object> result = new Map<String, Object>();

    try {
      if (
        quoteRequestIds == null ||
        quoteRequestIds.isEmpty() ||
        String.isBlank(promoCode)
      ) {
        result.put('success', false);
        result.put('message', 'Quote Request ID and Promo Code are required');
        return result;
      }

      Promo_Code__c validPromoCode = findPromoCodeRecord(promoCode);
      if (validPromoCode == null) {
        result.put('success', false);
        result.put('message', 'Invalid or expired promo code');
        return result;
      }

      String eligibilityMessage = promoApplyEligibilityMessage(validPromoCode);
      if (eligibilityMessage != null) {
        result.put('success', false);
        result.put('message', eligibilityMessage);
        return result;
      }

      List<ABT_Quote_Request__c> quoteRequests = [
        SELECT Id, ABT_Quote__c, ABT_Total_Price__c, ABT_Quote__r.Subtotal
        FROM ABT_Quote_Request__c
        WHERE Id IN :quoteRequestIds
      ];
      if (quoteRequests.isEmpty()) {
        result.put('success', false);
        result.put('message', 'Quote Request not found');
        return result;
      }

      Map<String, Object> preview = previewCheckoutPromoDiscount(
        validPromoCode,
        quoteRequests
      );
      result.put('success', true);
      result.put('alreadyApplied', false);
      result.put('message', 'Promo code applied successfully');
      result.put('discountPercentage', preview.get('discountPercentage'));
      if (preview.get('discountAmount') != null) {
        result.put('discountAmount', preview.get('discountAmount'));
      }
      result.put('quoteDiscounts', preview.get('quoteDiscounts'));
      result.put('promoCodeId', validPromoCode.Id);
      result.put('promoCode', validPromoCode.Promo_Code__c);
      if (commitToQuote == true) {
        persistCheckoutPromoToQuoteRequests(quoteRequestIds, promoCode);
      }
    } catch (Exception e) {
      System.debug('Error applying promo code: ' + e.getMessage());
      result.put('success', false);
      result.put('message', toFriendlyPromoApplyMessage(e));
    }

    return result;
  }

  @TestVisible
  private static void persistCheckoutPromoToQuoteRequests(
    List<Id> quoteRequestIds,
    String promoCode
  ) {
    if (
      quoteRequestIds == null ||
      quoteRequestIds.isEmpty() ||
      String.isBlank(promoCode)
    ) {
      return;
    }

    Promo_Code__c validPromoCode = findPromoCodeRecord(promoCode);
    if (validPromoCode == null) {
      throw checkoutAura('Invalid or expired promo code');
    }
    String eligibilityMessage = promoApplyEligibilityMessage(validPromoCode);
    if (eligibilityMessage != null) {
      throw checkoutAura(eligibilityMessage);
    }

    List<ABT_Quote_Request__c> quoteRequests = [
      SELECT Id, Promo_Code__c
      FROM ABT_Quote_Request__c
      WHERE Id IN :quoteRequestIds
    ];
    if (quoteRequests.isEmpty()) {
      throw checkoutAura('Quote Request not found');
    }

    List<ABT_Quote_Request__c> quoteRequestsToUpdate = new List<ABT_Quote_Request__c>();
    for (ABT_Quote_Request__c quoteRequest : quoteRequests) {
      if (quoteRequest.Promo_Code__c != validPromoCode.Id) {
        quoteRequest.Promo_Code__c = validPromoCode.Id;
        quoteRequestsToUpdate.add(quoteRequest);
      }
    }
    if (!quoteRequestsToUpdate.isEmpty()) {
      update quoteRequestsToUpdate;
    }
  }

  /**
   * Cart order is the checkout order. One quote uses that quote.
   * More than one quote uses the first quote only.
   */
  @TestVisible
  private static List<Id> checkoutPromoQuoteIds(List<Id> quoteIdsInCartOrder) {
    if (quoteIdsInCartOrder == null || quoteIdsInCartOrder.isEmpty()) {
      return new List<Id>();
    }
    if (quoteIdsInCartOrder.size() == 1) {
      return quoteIdsInCartOrder;
    }
    return new List<Id>{ quoteIdsInCartOrder[0] };
  }

  @TestVisible
  private static void persistCheckoutPromoToQuotes(
    List<Id> quoteIds,
    String promoCode
  ) {
    if (quoteIds == null || quoteIds.isEmpty() || String.isBlank(promoCode)) {
      return;
    }
    List<Id> quoteRequestIds = new List<Id>();
    for (ABT_Quote_Request__c quoteRequest : [
      SELECT Id
      FROM ABT_Quote_Request__c
      WHERE ABT_Quote__c IN :quoteIds
    ]) {
      quoteRequestIds.add(quoteRequest.Id);
    }
    persistCheckoutPromoToQuoteRequests(quoteRequestIds, promoCode);
  }

  /**
   * Clear Promo_Code__c on the QR and linked Quote.
   */
  @AuraEnabled
  public static Map<String, Object> removePromoCodeFromQuoteRequest(
    Id quoteRequestId
  ) {
    Map<String, Object> result = new Map<String, Object>();

    try {
      // Validate input parameters
      if (quoteRequestId == null) {
        result.put('success', false);
        result.put('message', 'Quote Request ID is required');
        return result;
      }

      // Get the quote request record
      List<ABT_Quote_Request__c> quoteRequests = [
        SELECT Id, ABT_Quote__c, Promo_Code__c
        FROM ABT_Quote_Request__c
        WHERE Id = :quoteRequestId
        LIMIT 1
      ];

      if (quoteRequests.isEmpty()) {
        result.put('success', false);
        result.put('message', 'Quote Request not found');
        return result;
      }

      ABT_Quote_Request__c quoteRequest = quoteRequests[0];

      // Remove the promo code from the quote request
      quoteRequest.Promo_Code__c = null;
      update quoteRequest;

      // Return success response
      result.put('success', true);
      result.put('message', 'Promo code removed successfully');
    } catch (Exception e) {
      System.debug('Error removing promo code: ' + e.getMessage());
      result.put('success', false);
      result.put('message', 'Error removing promo code: ' + e.getMessage());
    }

    return result;
  }

  /**
   * Catalog + account vectors (and the Contact's default) for the vector picker.
   * Images/GenBank come from S3 via fields on Vector__c, not a callout here.
   */
  @AuraEnabled(cacheable=true)
  public static Map<String, Object> getVectorLibraryData(
    Id currentUserAccountId
  ) {
    Map<String, Object> result = new Map<String, Object>();

    try {
      // Get catalog vectors (Type__c = 'Catalog', Active__c = true)
      List<Vector__c> catalogVectors = [
        SELECT
          Id,
          Name,
          Application__c,
          Antibiotic_Resistance__c,
          Copy_Number__c,
          CreatedDate,
          Active__c,
          Type__c,
          Image__c,
          Download_Genbank__c,
          eCommerce_Description__c,
          Preferred__c,
          Reflex_Applicable__c
        FROM Vector__c
        WHERE Type__c = 'Catalog' AND Active__c = TRUE
        ORDER BY Preferred__c DESC, Name ASC
      ];

      // Get internal vectors (Type__c = 'Internal', Active__c = true) - needed for XL products
      List<Vector__c> internalVectors = [
        SELECT
          Id,
          Name,
          Application__c,
          Antibiotic_Resistance__c,
          Copy_Number__c,
          CreatedDate,
          Active__c,
          Type__c,
          Image__c,
          Download_Genbank__c,
          eCommerce_Description__c,
          Preferred__c,
          Reflex_Applicable__c
        FROM Vector__c
        WHERE Type__c = 'Internal' AND Active__c = TRUE
        ORDER BY Preferred__c DESC, Name ASC
      ];

      // Get custom and internal vectors for the current user based on Vector Access
      List<Vector__c> customVectors = new List<Vector__c>();
      try {
        User currentUser = [
          SELECT ContactId
          FROM User
          WHERE Id = :UserInfo.getUserId()
          LIMIT 1
        ];
        if (currentUser.ContactId != null) {
          // Get vector IDs from Vector_Access__c for this contact
          Set<Id> accessibleVectorIds = new Set<Id>();
          for (Vector_Access__c va : [
            SELECT Vector__c
            FROM Vector_Access__c
            WHERE User__c = :currentUser.ContactId
          ]) {
            accessibleVectorIds.add(va.Vector__c);
          }

          // Query custom and internal vectors that the user has access to.
          // Download_Genbank__c is intentionally omitted: those links are
          // not shown on the custom tab and returning them is a security risk.
          if (!accessibleVectorIds.isEmpty()) {
            customVectors = [
              SELECT
                Id,
                Name,
                Application__c,
                Antibiotic_Resistance__c,
                Copy_Number__c,
                CreatedDate,
                Active__c,
                Type__c,
                Image__c,
                eCommerce_Description__c,
                Created_By_Name__c,
                Preferred__c,
                Reflex_Applicable__c
              FROM Vector__c
              WHERE
                Type__c IN ('Custom', 'Internal')
                AND Id IN :accessibleVectorIds
              ORDER BY Preferred__c DESC, Name ASC
            ];
          }
        }
      } catch (Exception e) {
        System.debug(
          'Error fetching custom/internal vectors with access control: ' +
          e.getMessage()
        );
      }

      // Get user's default vector
      String defaultVectorId = null;
      try {
        User currentUser = [
          SELECT ContactId
          FROM User
          WHERE Id = :UserInfo.getUserId()
          LIMIT 1
        ];
        System.debug('Current user ContactId: ' + currentUser.ContactId);
        if (currentUser.ContactId != null) {
          Contact userContact = [
            SELECT Default_Vector__c
            FROM Contact
            WHERE Id = :currentUser.ContactId
            LIMIT 1
          ];
          defaultVectorId = userContact.Default_Vector__c;
          System.debug('User default vector ID: ' + defaultVectorId);
        }
      } catch (Exception e) {
        System.debug('Error getting default vector: ' + e.getMessage());
      }

      result.put('catalogVectors', catalogVectors);
      result.put('customVectors', customVectors);
      result.put('internalVectors', internalVectors);
      result.put('defaultVectorId', defaultVectorId);
      result.put('success', true);
    } catch (Exception e) {
      System.debug('Error fetching vector library data: ' + e.getMessage());
      result.put('success', false);
      result.put('error', e.getMessage());
      result.put('catalogVectors', new List<Vector__c>());
      result.put('customVectors', new List<Vector__c>());
      result.put('internalVectors', new List<Vector__c>());
    }

    return result;
  }

  /**
   * Scale up options and glycerol default for the portal new-quote flow.
   * Scale Up is available to all customers; product Scale_Up_Enabled__c still
   * controls whether a given product shows the Scale Up UI.
   */
  @AuraEnabled(cacheable=true)
  public static Map<String, Object> getScaleUpLibraryData(Id accountId) {
    Map<String, Object> result = new Map<String, Object>();
    Boolean defaultGlycerol = false;
    List<Map<String, String>> options = new List<Map<String, String>>();

    try {
      if (accountId != null) {
        List<Account> accounts = [
          SELECT Default_Glycerol__c
          FROM Account
          WHERE Id = :accountId
          LIMIT 1
        ];
        if (!accounts.isEmpty()) {
          defaultGlycerol = accounts[0].Default_Glycerol__c == true;
        }
      }

      for (Scale_Up__c scaleUp : [
        SELECT Id, Name
        FROM Scale_Up__c
        ORDER BY Name ASC
      ]) {
        options.add(
          new Map<String, String>{
            'label' => scaleUp.Name,
            'value' => scaleUp.Id
          }
        );
      }

      result.put('scaleUpEnabled', true);
      result.put('scaleUpOptions', options);
      result.put('defaultGlycerol', defaultGlycerol);
      result.put('success', true);
    } catch (Exception e) {
      System.debug('Error fetching scale up library data: ' + e.getMessage());
      result.put('scaleUpEnabled', true);
      result.put('scaleUpOptions', new List<Map<String, String>>());
      result.put('defaultGlycerol', false);
      result.put('success', false);
      result.put('error', e.getMessage());
    }

    return result;
  }

  /**
   * Remember this Vector as the Contact's default for new lines. Returns
   * success/error for the LWC toast.
   */
  @AuraEnabled
  public static Map<String, Object> setDefaultVector(Id vectorId) {
    Map<String, Object> result = new Map<String, Object>();

    try {
      // Get current user's contact ID
      User currentUser = [
        SELECT ContactId
        FROM User
        WHERE Id = :UserInfo.getUserId()
        LIMIT 1
      ];

      if (currentUser.ContactId == null) {
        result.put('success', false);
        result.put('error', 'No contact associated with current user');
        return result;
      }

      // Update the contact's default vector
      Contact contactToUpdate = new Contact(
        Id = currentUser.ContactId,
        Default_Vector__c = vectorId
      );

      update contactToUpdate;

      result.put('success', true);
      result.put('message', 'Default vector updated successfully');
    } catch (Exception e) {
      System.debug('Error setting default vector: ' + e.getMessage());
      result.put('success', false);
      result.put('error', e.getMessage());
    }

    return result;
  }

  /**
   * Change vector on one line. Drops the QR from cart if it was already in there
   * so they re-price before checkout. Delegates Sequence DML to SequenceSyncService.
   */
  @AuraEnabled
  public static Map<String, Object> updateQuoteLineItemVector(
    Id lineItemId,
    Id vectorId
  ) {
    Map<String, Object> result = new Map<String, Object>();

    try {
      result = ABT_SequenceSyncService.buildPortalVectorUpdateResult(
        lineItemId,
        vectorId
      );
      if (result.get('success') == true) {
        result.put(
          'removedFromCart',
          clearQuoteRequestFromCartForLineItem(lineItemId)
        );
      }
    } catch (Exception e) {
      System.debug('Error updating line item vector: ' + e.getMessage());
      result.put('success', false);
      result.put('error', e.getMessage());
    }

    return result;
  }

  /**
   * Apply one vector to many lines. Same cart-clear as the single-line path,
   * done once so we don't lock the QR with parallel Apex calls.
   */
  @AuraEnabled
  public static Map<String, Object> bulkUpdateQuoteLineItemVectors(
    List<Id> lineItemIds,
    Id vectorId
  ) {
    Map<String, Object> result = new Map<String, Object>();

    try {
      result = ABT_SequenceSyncService.buildPortalBulkVectorUpdateResult(
        lineItemIds,
        vectorId
      );
      if (
        result.get('success') == true &&
        lineItemIds != null &&
        !lineItemIds.isEmpty()
      ) {
        result.put(
          'removedFromCart',
          clearQuoteRequestFromCartForLineItem(lineItemIds[0])
        );
      }
    } catch (Exception e) {
      System.debug('Error bulk updating line item vectors: ' + e.getMessage());
      result.put('success', false);
      result.put('error', e.getMessage());
    }

    return result;
  }

  private static Map<String, Object> applyGlycerolStockChange(
    Id lineItemId,
    Boolean glycerolStock,
    Boolean clearCart
  ) {
    Boolean stockValue = glycerolStock == true;
    Map<String, Object> batchResult = applyBulkGlycerolBatch(
      new Map<Id, Boolean>{ lineItemId => stockValue },
      new List<Id>{ lineItemId }
    );

    Map<String, Object> result = new Map<String, Object>();
    Boolean mutated = batchResult.get('anyMutation') == true;
    List<Object> linePayload = (List<Object>) batchResult.get('lines');
    Map<String, Object> lineResult = !linePayload.isEmpty()
      ? (Map<String, Object>) linePayload[0]
      : new Map<String, Object>{
          'glycerolStock' => stockValue,
          'glycerolPrice' => null
        };

    result.put('mutated', mutated);
    result.put('glycerolStock', lineResult.get('glycerolStock'));
    result.put('glycerolPrice', lineResult.get('glycerolPrice'));
    result.put(
      'removedFromCart',
      mutated && clearCart
        ? clearQuoteRequestFromCartForLineItem(lineItemId)
        : false
    );
    return result;
  }

  /**
   * Glycerol stock checkbox on a QRLI. Recalc pricing via SequenceSync. Drops
   * the QR from cart if it was already in there.
   */
  @AuraEnabled
  public static Map<String, Object> updateQuoteRequestLineItemGlycerol(
    Id lineItemId,
    Boolean glycerolStock
  ) {
    Map<String, Object> result = new Map<String, Object>();

    try {
      if (lineItemId == null) {
        result.put('success', false);
        result.put('error', 'Line item ID is required');
        return result;
      }

      Map<String, Object> applied = applyGlycerolStockChange(
        lineItemId,
        glycerolStock,
        true
      );
      result.put('success', true);
      result.put('glycerolStock', applied.get('glycerolStock'));
      result.put('glycerolPrice', applied.get('glycerolPrice'));
      result.put('removedFromCart', applied.get('removedFromCart'));
    } catch (Exception e) {
      System.debug('Error updating line item glycerol: ' + e.getMessage());
      result.put('success', false);
      result.put('error', e.getMessage());
      result.put(
        'retryable',
        e.getMessage() != null &&
        (e.getMessage().contains('UNABLE_TO_LOCK_ROW') ||
        e.getMessage().contains('Too many SOQL queries'))
      );
    }

    return result;
  }

  /**
   * Bulk-safe Glycerol update. One transaction updates all QRLs + linked QLIs
   * and clears cart once — avoids UNABLE_TO_LOCK_ROW from parallel single-row Apex calls.
   */
  @TestVisible
  private static Map<String, Object> applyBulkGlycerolBatch(
    Map<Id, Boolean> desiredById,
    List<Id> lineOrder
  ) {
    Boolean anyMutation = false;
    List<Map<String, Object>> lines = new List<Map<String, Object>>();

    if (desiredById == null || desiredById.isEmpty()) {
      return new Map<String, Object>{
        'anyMutation' => false,
        'lines' => lines
      };
    }

    List<ABT_Quote_Request_Lineitem__c> items = [
      SELECT
        Id,
        Glycerol_Stock__c,
        Glycerol_Price__c,
        ABT_Quote_Line_Item__c,
        ABT_Quote_Line_Item__r.Glycerol_Stock__c
      FROM ABT_Quote_Request_Lineitem__c
      WHERE Id IN :desiredById.keySet()
    ];

    List<ABT_Quote_Request_Lineitem__c> qrlToUpdate = new List<ABT_Quote_Request_Lineitem__c>();
    List<QuoteLineItem> qliSetTrue = new List<QuoteLineItem>();
    List<QuoteLineItem> qliSetFalse = new List<QuoteLineItem>();
    Set<Id> qliToggleIds = new Set<Id>();

    for (ABT_Quote_Request_Lineitem__c lineItem : items) {
      Boolean stockValue = desiredById.get(lineItem.Id) == true;
      Boolean qrlNeedsUpdate = lineItem.Glycerol_Stock__c != stockValue;
      Id quoteLineItemId = lineItem.ABT_Quote_Line_Item__c;
      Boolean qliStock =
        quoteLineItemId != null &&
        lineItem.ABT_Quote_Line_Item__r.Glycerol_Stock__c == true;
      Boolean qliNeedsUpdate =
        quoteLineItemId != null &&
        qliStock != stockValue;
      Boolean glycerolPriceMissing =
        lineItem.Glycerol_Price__c == null ||
        lineItem.Glycerol_Price__c == 0;
      Boolean needsQliStockFlowRetrigger =
        stockValue == true &&
        quoteLineItemId != null &&
        qliStock &&
        glycerolPriceMissing;

      if (!qrlNeedsUpdate && !qliNeedsUpdate && !needsQliStockFlowRetrigger) {
        continue;
      }

      anyMutation = true;
      if (qrlNeedsUpdate) {
        lineItem.Glycerol_Stock__c = stockValue;
        qrlToUpdate.add(lineItem);
      }

      if (quoteLineItemId != null) {
        if (stockValue == true) {
          if (!qliStock) {
            qliSetTrue.add(
              new QuoteLineItem(Id = quoteLineItemId, Glycerol_Stock__c = true)
            );
          } else if (qrlNeedsUpdate || needsQliStockFlowRetrigger) {
            qliToggleIds.add(quoteLineItemId);
          }
        } else if (qliStock) {
          qliSetFalse.add(
            new QuoteLineItem(Id = quoteLineItemId, Glycerol_Stock__c = false)
          );
        }
      }
    }

    if (!qrlToUpdate.isEmpty()) {
      update qrlToUpdate;
    }
    if (!qliSetTrue.isEmpty()) {
      update qliSetTrue;
    }
    if (!qliSetFalse.isEmpty()) {
      update qliSetFalse;
    }
    if (!qliToggleIds.isEmpty()) {
      List<QuoteLineItem> togglesOff = new List<QuoteLineItem>();
      for (Id quoteLineItemId : qliToggleIds) {
        togglesOff.add(
          new QuoteLineItem(Id = quoteLineItemId, Glycerol_Stock__c = false)
        );
      }
      update togglesOff;
      List<QuoteLineItem> togglesOn = new List<QuoteLineItem>();
      for (Id quoteLineItemId : qliToggleIds) {
        togglesOn.add(
          new QuoteLineItem(Id = quoteLineItemId, Glycerol_Stock__c = true)
        );
      }
      update togglesOn;
    }

    List<ABT_Quote_Request_Lineitem__c> refreshed = [
      SELECT Id, Glycerol_Stock__c, Glycerol_Price__c
      FROM ABT_Quote_Request_Lineitem__c
      WHERE Id IN :desiredById.keySet()
    ];
    Map<Id, ABT_Quote_Request_Lineitem__c> refreshedById = new Map<Id, ABT_Quote_Request_Lineitem__c>();
    for (ABT_Quote_Request_Lineitem__c row : refreshed) {
      refreshedById.put(row.Id, row);
    }

    for (Id lineItemId : lineOrder) {
      if (lineItemId == null || !desiredById.containsKey(lineItemId)) {
        continue;
      }

      ABT_Quote_Request_Lineitem__c row = refreshedById.get(lineItemId);
      lines.add(
        new Map<String, Object>{
          'id' => lineItemId,
          'glycerolStock' => row != null
            ? row.Glycerol_Stock__c == true
            : desiredById.get(lineItemId) == true,
          'glycerolPrice' => row != null ? row.Glycerol_Price__c : null
        }
      );
    }

    return new Map<String, Object>{
      'anyMutation' => anyMutation,
      'lines' => lines
    };
  }

  @AuraEnabled
  public static Map<String, Object> bulkUpdateQuoteRequestLineItemGlycerol(
    List<Id> lineItemIds,
    List<Boolean> glycerolStockFlags
  ) {
    Map<String, Object> result = new Map<String, Object>();

    try {
      if (lineItemIds == null || lineItemIds.isEmpty()) {
        result.put('success', false);
        result.put('error', 'At least one line item ID is required');
        return result;
      }
      if (
        glycerolStockFlags == null ||
        glycerolStockFlags.size() != lineItemIds.size()
      ) {
        result.put('success', false);
        result.put('error', 'glycerolStockFlags must match lineItemIds size');
        return result;
      }

      Map<Id, Boolean> desiredById = new Map<Id, Boolean>();
      for (Integer i = 0; i < lineItemIds.size(); i++) {
        Id lineItemId = lineItemIds[i];
        if (lineItemId == null) {
          result.put('success', false);
          result.put('error', 'Line item ID is required');
          return result;
        }
        desiredById.put(lineItemId, glycerolStockFlags[i] == true);
      }

      Map<String, Object> batchOutcome = applyBulkGlycerolBatch(
        desiredById,
        lineItemIds
      );
      Boolean anyMutation = batchOutcome.get('anyMutation') == true;

      result.put('success', true);
      result.put('lines', batchOutcome.get('lines'));
      result.put(
        'removedFromCart',
        anyMutation
          ? clearQuoteRequestFromCartForLineItem(lineItemIds[0])
          : false
      );
    } catch (Exception e) {
      System.debug('Error bulk updating line item glycerol: ' + e.getMessage());
      result.put('success', false);
      result.put('error', e.getMessage());
      result.put(
        'retryable',
        e.getMessage() != null &&
        (e.getMessage().contains('UNABLE_TO_LOCK_ROW') ||
        e.getMessage().contains('Too many SOQL queries'))
      );
    }

    return result;
  }

  @AuraEnabled
  public static Map<String, Object> updateQuoteRequestLineItemPotentiallyToxic(
    Id lineItemId,
    Boolean potentiallyToxic
  ) {
    if (lineItemId == null) {
      Map<String, Object> result = new Map<String, Object>();
      result.put('success', false);
      result.put('error', 'Line item ID is required');
      return result;
    }
    Map<String, Object> result = bulkUpdateQuoteRequestLineItemPotentiallyToxic(
      new List<Id>{ lineItemId },
      new List<Boolean>{ potentiallyToxic == true }
    );
    if (result.get('success') == true) {
      Boolean resolved = potentiallyToxic == true;
      Object linesObj = result.get('lines');
      if (linesObj instanceof List<Object>) {
        List<Object> lines = (List<Object>) linesObj;
        if (!lines.isEmpty() && lines[0] instanceof Map<String, Object>) {
          Object toxic = ((Map<String, Object>) lines[0])
            .get('potentiallyToxic');
          resolved = toxic == true;
        }
      }
      result.put('potentiallyToxic', resolved);
    }
    return result;
  }

  /**
   * Shared bulk checkbox sync for QRLI + linked QLI with a single cart clear.
   */
  @TestVisible
  private static Map<String, Object> bulkUpdateQuoteRequestLineItemCheckbox(
    List<Id> lineItemIds,
    List<Boolean> flagValues,
    String flagsMismatchError,
    String qrlFieldName,
    String qliFieldName,
    String lineResponseKey,
    String debugContext
  ) {
    Map<String, Object> result = new Map<String, Object>();

    try {
      if (lineItemIds == null || lineItemIds.isEmpty()) {
        result.put('success', false);
        result.put('error', 'At least one line item ID is required');
        return result;
      }
      if (flagValues == null || flagValues.size() != lineItemIds.size()) {
        result.put('success', false);
        result.put('error', flagsMismatchError);
        return result;
      }

      Map<Id, Boolean> desiredById = new Map<Id, Boolean>();
      for (Integer i = 0; i < lineItemIds.size(); i++) {
        Id lineItemId = lineItemIds[i];
        if (lineItemId == null) {
          result.put('success', false);
          result.put('error', 'Line item ID is required');
          return result;
        }
        desiredById.put(lineItemId, flagValues[i] == true);
      }

      List<ABT_Quote_Request_Lineitem__c> items = [
        SELECT
          Id,
          Potentially_Toxic__c,
          Reflex_Vector_Opt_In__c,
          ABT_Quote_Line_Item__c
        FROM ABT_Quote_Request_Lineitem__c
        WHERE Id IN :desiredById.keySet()
      ];

      List<ABT_Quote_Request_Lineitem__c> qrlToUpdate = new List<ABT_Quote_Request_Lineitem__c>();
      List<QuoteLineItem> qliToUpdate = new List<QuoteLineItem>();
      for (ABT_Quote_Request_Lineitem__c item : items) {
        Boolean flagValue = desiredById.get(item.Id) == true;
        if ((Boolean) item.get(qrlFieldName) == flagValue) {
          continue;
        }
        item.put(qrlFieldName, flagValue);
        qrlToUpdate.add(item);
        if (item.ABT_Quote_Line_Item__c != null) {
          QuoteLineItem qli = new QuoteLineItem(
            Id = item.ABT_Quote_Line_Item__c
          );
          qli.put(qliFieldName, flagValue);
          qliToUpdate.add(qli);
        }
      }

      if (!qrlToUpdate.isEmpty()) {
        update qrlToUpdate;
      }
      if (!qliToUpdate.isEmpty()) {
        update qliToUpdate;
      }

      List<ABT_Quote_Request_Lineitem__c> refreshed = [
        SELECT Id, Potentially_Toxic__c, Reflex_Vector_Opt_In__c
        FROM ABT_Quote_Request_Lineitem__c
        WHERE Id IN :desiredById.keySet()
      ];
      Map<Id, Boolean> refreshedById = new Map<Id, Boolean>();
      for (ABT_Quote_Request_Lineitem__c row : refreshed) {
        refreshedById.put(row.Id, (Boolean) row.get(qrlFieldName) == true);
      }

      List<Map<String, Object>> lines = new List<Map<String, Object>>();
      for (Id lineItemId : lineItemIds) {
        lines.add(
          new Map<String, Object>{
            'id' => lineItemId,
            lineResponseKey => refreshedById.containsKey(lineItemId)
              ? refreshedById.get(lineItemId)
              : desiredById.get(lineItemId) == true
          }
        );
      }

      result.put('success', true);
      result.put('lines', lines);
      result.put(
        'removedFromCart',
        !qrlToUpdate.isEmpty()
          ? clearQuoteRequestFromCartForLineItem(lineItemIds[0])
          : false
      );
    } catch (Exception e) {
      System.debug(
        'Error bulk updating line item ' + debugContext + ': ' + e.getMessage()
      );
      result.put('success', false);
      result.put('error', e.getMessage());
      result.put(
        'retryable',
        e.getMessage() != null &&
        (e.getMessage().contains('UNABLE_TO_LOCK_ROW') ||
        e.getMessage().contains('Too many SOQL queries'))
      );
    }

    return result;
  }

  /**
   * Bulk-safe Potentially Toxic update. One transaction updates all QRLs + linked QLIs
   * and clears cart once — avoids UNABLE_TO_LOCK_ROW from parallel single-row Apex calls
   * (e.g. Step 3 Next with many sequences).
   */
  @AuraEnabled
  public static Map<String, Object> bulkUpdateQuoteRequestLineItemPotentiallyToxic(
    List<Id> lineItemIds,
    List<Boolean> potentiallyToxicFlags
  ) {
    return bulkUpdateQuoteRequestLineItemCheckbox(
      lineItemIds,
      potentiallyToxicFlags,
      'potentiallyToxicFlags must match lineItemIds size',
      'Potentially_Toxic__c',
      'Potentially_Toxic__c',
      'potentiallyToxic',
      'potentially toxic'
    );
  }

  @AuraEnabled
  public static Map<String, Object> updateQuoteRequestLineItemReflexVectorOptIn(
    Id lineItemId,
    Boolean reflexVectorOptIn
  ) {
    if (lineItemId == null) {
      Map<String, Object> result = new Map<String, Object>();
      result.put('success', false);
      result.put('error', 'Line item ID is required');
      return result;
    }
    Map<String, Object> result = bulkUpdateQuoteRequestLineItemReflexVectorOptIn(
      new List<Id>{ lineItemId },
      new List<Boolean>{ reflexVectorOptIn == true }
    );
    if (result.get('success') == true) {
      Boolean resolved = reflexVectorOptIn == true;
      Object linesObj = result.get('lines');
      if (linesObj instanceof List<Object>) {
        List<Object> lines = (List<Object>) linesObj;
        if (!lines.isEmpty() && lines[0] instanceof Map<String, Object>) {
          Object optIn = ((Map<String, Object>) lines[0])
            .get('reflexVectorOptIn');
          resolved = optIn == true;
        }
      }
      result.put('reflexVectorOptIn', resolved);
    }
    return result;
  }

  /**
   * Bulk-safe Reflex Vector opt-in update. One transaction updates all QRLs + linked QLIs
   * and clears cart once — avoids UNABLE_TO_LOCK_ROW from parallel single-row Apex calls.
   */
  @AuraEnabled
  public static Map<String, Object> bulkUpdateQuoteRequestLineItemReflexVectorOptIn(
    List<Id> lineItemIds,
    List<Boolean> reflexVectorOptInFlags
  ) {
    return bulkUpdateQuoteRequestLineItemCheckbox(
      lineItemIds,
      reflexVectorOptInFlags,
      'reflexVectorOptInFlags must match lineItemIds size',
      'Reflex_Vector_Opt_In__c',
      'Reflex_Vector_Opt_In__c',
      'reflexVectorOptIn',
      'reflex vector opt-in'
    );
  }

  /** SKU for the Outsourced Scale Up product used for portal pricing. */
  @TestVisible
  private static final String SCALE_UP_PRODUCT_SKU = 'SC-001';
  private static final String SCALE_UP_PRODUCT_SKU_LEGACY = 'CS-200';
  private static final String GLYCEROL_STOCK_PRODUCT_SKU = 'GS-001';

  /** SC-001 / GS-001 TotalPrice keyed by parent Quote Line Item Id. */
  private static Map<Id, Map<String, Decimal>> feeChildSalesByParentId(
    Set<Id> parentIds
  ) {
    Map<Id, Map<String, Decimal>> byParent = new Map<Id, Map<String, Decimal>>();
    if (parentIds == null || parentIds.isEmpty()) {
      return byParent;
    }
    Map<String, Schema.SObjectField> qliFields = Schema.SObjectType.QuoteLineItem.fields.getMap();
    List<String> fields = new List<String>{
      'Parent_Line_Item__c',
      'TotalPrice',
      'UnitPrice',
      'Quantity',
      'Product2.StockKeepingUnit'
    };
    if (qliFields.containsKey('product_sku__c')) {
      fields.add('Product_SKU__c');
    }
    String soql =
      'SELECT ' +
      String.join(fields, ', ') +
      ' FROM QuoteLineItem WHERE Parent_Line_Item__c IN :parentIds';
    Set<String> scaleSkus = new Set<String>{
      SCALE_UP_PRODUCT_SKU,
      SCALE_UP_PRODUCT_SKU_LEGACY
    };
    for (QuoteLineItem child : Database.query(soql)) {
      if (child.Parent_Line_Item__c == null) {
        continue;
      }
      Decimal amount = child.TotalPrice;
      if (amount == null || amount <= 0) {
        Decimal unit = child.UnitPrice != null ? child.UnitPrice : 0;
        Decimal qty = child.Quantity != null ? child.Quantity : 1;
        amount = unit * qty;
      }
      if (amount == null || amount <= 0) {
        continue;
      }
      String sku = '';
      if (qliFields.containsKey('product_sku__c')) {
        Object lineSku = child.get('Product_SKU__c');
        if (lineSku != null) {
          sku = String.valueOf(lineSku).trim().toUpperCase();
        }
      }
      if (String.isBlank(sku) && child.Product2 != null) {
        sku = child.Product2.StockKeepingUnit != null
          ? child.Product2.StockKeepingUnit.trim().toUpperCase()
          : '';
      }
      if (!byParent.containsKey(child.Parent_Line_Item__c)) {
        byParent.put(
          child.Parent_Line_Item__c,
          new Map<String, Decimal>{ 'scaleUp' => 0, 'glycerol' => 0 }
        );
      }
      Map<String, Decimal> bucket = byParent.get(child.Parent_Line_Item__c);
      if (scaleSkus.contains(sku)) {
        bucket.put('scaleUp', bucket.get('scaleUp') + amount);
      } else if (GLYCEROL_STOCK_PRODUCT_SKU.equals(sku)) {
        bucket.put('glycerol', bucket.get('glycerol') + amount);
      }
    }
    return byParent;
  }

  /**
   * Persists the Scale Up configuration captured in the portal config panel.
   * Writable config fields live on the Quote Request Line Item; Mass / Price / Lead Time
   * are written on the linked Quote Line Item (the Quote_Line_Item_Scale_Up flow is not
   * relied on here — it is Draft in partial and its empty-touch trigger is unreliable for
   * cross-object formula IsChanged criteria).
   */
  @AuraEnabled
  public static Map<String, Object> updateQuoteRequestLineItemScaleUp(
    List<Id> lineItemIds,
    Boolean selected,
    String quantity,
    Boolean glycerolStock,
    String buffer,
    Boolean endotoxinFree,
    Boolean animalFree,
    String normalization
  ) {
    Map<String, Object> result = new Map<String, Object>();

    try {
      if (lineItemIds == null || lineItemIds.isEmpty()) {
        result.put('success', false);
        result.put('error', 'At least one line item ID is required');
        return result;
      }

      Boolean sel = selected == true;
      Decimal qtyNumber = scaleUpQuantityToDecimal(quantity);
      String normalizationValue = scaleUpNormalizationToApiValue(normalization);

      List<ABT_Quote_Request_Lineitem__c> items = [
        SELECT Id, ABT_Quote_Line_Item__c, Glycerol_Stock__c
        FROM ABT_Quote_Request_Lineitem__c
        WHERE Id IN :lineItemIds
      ];

      Set<Id> quoteLineItemIds = new Set<Id>();
      for (ABT_Quote_Request_Lineitem__c item : items) {
        item.Scale_Up_Selected__c = sel;
        item.Scale_Up_Quantity__c = sel ? quantity : null;
        item.Scale_Up_Glycerol_Stock__c = sel && glycerolStock == true;
        item.Scale_Up_Buffer__c = sel ? buffer : null;
        item.Scale_Up_Endotoxin_Free__c = sel && endotoxinFree == true;
        item.Scale_Up_Animal_Free__c = sel && animalFree == true;
        item.Scale_Up_Normalization__c = sel ? normalizationValue : null;
        // Scale Up owns glycerol via Scale_Up_Glycerol_Stock__c; clear the
        // standard Glycerol Stock column (matches Quote_Line_Item_Scale_Up flow).
        if (sel) {
          item.Glycerol_Stock__c = false;
        }
        if (item.ABT_Quote_Line_Item__c != null) {
          quoteLineItemIds.add(item.ABT_Quote_Line_Item__c);
        }
      }

      update items;

      if (!quoteLineItemIds.isEmpty()) {
        applyScaleUpFieldsToQuoteLineItems(
          quoteLineItemIds,
          sel,
          quantity,
          qtyNumber,
          glycerolStock == true,
          endotoxinFree == true,
          animalFree == true
        );
      }

      Map<Id, Map<String, Decimal>> childSales = feeChildSalesByParentId(
        quoteLineItemIds
      );

      List<ABT_Quote_Request_Lineitem__c> refreshed = [
        SELECT
          Id,
          Scale_Up_Selected__c,
          Scale_Up_Quantity__c,
          Scale_Up_Glycerol_Stock__c,
          Scale_Up_Buffer__c,
          Scale_Up_Endotoxin_Free__c,
          Scale_Up_Animal_Free__c,
          Scale_Up_Normalization__c,
          Scale_Up_Lead_Time__c,
          Glycerol_Stock__c,
          Glycerol_Price__c,
          ABT_Quote_Line_Item__c,
          ABT_Quote_Line_Item__r.Scale_Up_Mass__c,
          ABT_Quote_Line_Item__r.Scale_Up_Price__c,
          ABT_Quote_Line_Item__r.Scale_Up_Lead_Time__c
        FROM ABT_Quote_Request_Lineitem__c
        WHERE Id IN :lineItemIds
      ];

      List<Map<String, Object>> lines = new List<Map<String, Object>>();
      for (ABT_Quote_Request_Lineitem__c r : refreshed) {
        String mass = r.ABT_Quote_Line_Item__r != null
          ? r.ABT_Quote_Line_Item__r.Scale_Up_Mass__c
          : null;
        Decimal price = r.ABT_Quote_Line_Item__r != null
          ? r.ABT_Quote_Line_Item__r.Scale_Up_Price__c
          : null;
        Decimal glycerolPrice = r.Glycerol_Price__c;
        if (
          r.ABT_Quote_Line_Item__c != null &&
          childSales.containsKey(r.ABT_Quote_Line_Item__c)
        ) {
          Map<String, Decimal> fees = childSales.get(r.ABT_Quote_Line_Item__c);
          if (fees.get('scaleUp') > 0) {
            price = fees.get('scaleUp');
          }
          if (fees.get('glycerol') > 0) {
            glycerolPrice = fees.get('glycerol');
          }
        }
        String leadTime = r.ABT_Quote_Line_Item__r != null &&
          String.isNotBlank(r.ABT_Quote_Line_Item__r.Scale_Up_Lead_Time__c)
          ? r.ABT_Quote_Line_Item__r.Scale_Up_Lead_Time__c
          : r.Scale_Up_Lead_Time__c;
        lines.add(
          new Map<String, Object>{
            'id' => r.Id,
            'scaleUpSelected' => r.Scale_Up_Selected__c,
            'scaleUpQuantity' => r.Scale_Up_Quantity__c,
            'scaleUpGlycerolStock' => r.Scale_Up_Glycerol_Stock__c,
            'scaleUpBuffer' => r.Scale_Up_Buffer__c,
            'scaleUpEndotoxinFree' => r.Scale_Up_Endotoxin_Free__c,
            'scaleUpAnimalFree' => r.Scale_Up_Animal_Free__c,
            'scaleUpNormalization' => r.Scale_Up_Normalization__c,
            'scaleUpMass' => mass,
            'scaleUpPrice' => price,
            'scaleUpLeadTime' => leadTime,
            'glycerolStock' => r.Glycerol_Stock__c,
            'glycerolPrice' => glycerolPrice
          }
        );
      }

      result.put('success', true);
      result.put('lines', lines);
      result.put(
        'removedFromCart',
        clearQuoteRequestFromCartForLineItem(lineItemIds[0])
      );
    } catch (Exception e) {
      System.debug('Error updating line item scale up: ' + e.getMessage());
      result.put('success', false);
      result.put('error', e.getMessage());
      result.put(
        'retryable',
        e.getMessage() != null &&
        (e.getMessage().contains('UNABLE_TO_LOCK_ROW') ||
        e.getMessage().contains('Too many SOQL queries'))
      );
    }

    return result;
  }

  /**
   * Applies Scale Up mass/price/glycerol fields on linked quote line items,
   * and deletes SC-001/CS-200 child lines when clearing.
   */
  @TestVisible
  private static void applyScaleUpFieldsToQuoteLineItems(
    Set<Id> quoteLineItemIds,
    Boolean selected,
    String quantity,
    Decimal qtyNumber,
    Boolean glycerolStock,
    Boolean endotoxinFree,
    Boolean animalFree
  ) {
    if (quoteLineItemIds == null || quoteLineItemIds.isEmpty()) {
      return;
    }

    Boolean sel = selected == true;
    Map<Id, QuoteLineItem> qliById = new Map<Id, QuoteLineItem>(
      [
        SELECT
          Id,
          QuoteId,
          Quote.Pricebook2Id,
          Vector__r.Copy_Number__c,
          Scale_Up_Mass__c,
          Scale_Up_Price__c,
          Scale_Up_Lead_Time__c,
          Glycerol_Stock__c,
          Glycerol_Price__c
        FROM QuoteLineItem
        WHERE Id IN :quoteLineItemIds
      ]
    );

    Set<Id> pricebookIds = new Set<Id>();
    for (QuoteLineItem qli : qliById.values()) {
      if (qli.Quote != null && qli.Quote.Pricebook2Id != null) {
        pricebookIds.add(qli.Quote.Pricebook2Id);
      }
    }

    Map<Id, Decimal> unitPriceByPricebookId = new Map<Id, Decimal>();
    Map<Id, Decimal> glycerolPriceByPricebookId = new Map<Id, Decimal>();
    Set<String> scaleUpSkus = new Set<String>{
      SCALE_UP_PRODUCT_SKU,
      SCALE_UP_PRODUCT_SKU_LEGACY
    };
    if (!pricebookIds.isEmpty()) {
      if (sel) {
        for (PricebookEntry pbe : [
          SELECT Pricebook2Id, UnitPrice, Product2.StockKeepingUnit
          FROM PricebookEntry
          WHERE
            Pricebook2Id IN :pricebookIds
            AND IsActive = TRUE
            AND Product2.StockKeepingUnit IN :scaleUpSkus
        ]) {
          // Prefer SC-001 over legacy CS-200 when both exist.
          String sku = pbe.Product2 != null
            ? pbe.Product2.StockKeepingUnit
            : null;
          if (
            !unitPriceByPricebookId.containsKey(pbe.Pricebook2Id) ||
            SCALE_UP_PRODUCT_SKU.equals(sku)
          ) {
            unitPriceByPricebookId.put(pbe.Pricebook2Id, pbe.UnitPrice);
          }
        }
      }
      Boolean needsGlycerolPriceLookup = sel && glycerolStock == true;
      if (needsGlycerolPriceLookup) {
        Decimal standardGlycerolPrice = null;
        for (PricebookEntry pbe : [
          SELECT Pricebook2Id, Pricebook2.IsStandard, UnitPrice
          FROM PricebookEntry
          WHERE
            IsActive = TRUE
            AND Product2.StockKeepingUnit = :GLYCEROL_STOCK_PRODUCT_SKU
            AND (Pricebook2Id IN :pricebookIds
            OR Pricebook2.IsStandard = TRUE)
        ]) {
          if (pricebookIds.contains(pbe.Pricebook2Id)) {
            glycerolPriceByPricebookId.put(pbe.Pricebook2Id, pbe.UnitPrice);
          }
          if (
            pbe.Pricebook2 != null &&
            pbe.Pricebook2.IsStandard == true &&
            pbe.UnitPrice != null &&
            pbe.UnitPrice > 0
          ) {
            standardGlycerolPrice = pbe.UnitPrice;
          }
        }
        // Internal books can list GS-001 at $0. Do not stamp that onto the parent
        // fee field the quote page reads — use the standard $30 list price.
        if (standardGlycerolPrice != null) {
          for (Id pricebookId : pricebookIds) {
            Decimal quotedGlycerol = glycerolPriceByPricebookId.get(
              pricebookId
            );
            if (quotedGlycerol == null || quotedGlycerol <= 0) {
              glycerolPriceByPricebookId.put(
                pricebookId,
                standardGlycerolPrice
              );
            }
          }
        }
      }
    }

    Map<Id, Decimal> glycerolChildPriceByParentId = new Map<Id, Decimal>();
    if (sel && glycerolStock == true) {
      for (QuoteLineItem child : [
        SELECT
          Parent_Line_Item__c,
          UnitPrice,
          TotalPrice,
          Product_SKU__c,
          Product_Code__c,
          Product2.Name,
          Product2.StockKeepingUnit
        FROM QuoteLineItem
        WHERE Parent_Line_Item__c IN :quoteLineItemIds
      ]) {
        if (!isGlycerolStockQuoteLineItem(child)) {
          continue;
        }
        Decimal childPrice = child.UnitPrice != null &&
          child.UnitPrice > 0
          ? child.UnitPrice
          : child.TotalPrice;
        if (
          childPrice != null &&
          childPrice > 0 &&
          !glycerolChildPriceByParentId.containsKey(child.Parent_Line_Item__c)
        ) {
          glycerolChildPriceByParentId.put(
            child.Parent_Line_Item__c,
            childPrice
          );
        }
      }
    }

    List<QuoteLineItem> qlisToUpdate = new List<QuoteLineItem>();
    for (QuoteLineItem qli : qliById.values()) {
      Boolean applyScaleUpGlycerol = sel && glycerolStock == true;
      if (!sel) {
        qli.Scale_Up_Mass__c = null;
        qli.Scale_Up_Price__c = 0;
        qli.Scale_Up_Lead_Time__c = null;
        // Clear leftover Scale Up glycerol fee when standard Glycerol Stock is off.
        if (qli.Glycerol_Stock__c != true) {
          qli.Glycerol_Price__c = 0;
        }
      } else {
        String copyNumber = qli.Vector__r != null
          ? String.valueOf(qli.Vector__r.Copy_Number__c)
          : null;
        qli.Scale_Up_Mass__c = scaleUpMassForCopyNumber(copyNumber, quantity);
        Decimal unitPrice = (qli.Quote != null &&
          qli.Quote.Pricebook2Id != null)
          ? unitPriceByPricebookId.get(qli.Quote.Pricebook2Id)
          : null;
        qli.Scale_Up_Price__c = (unitPrice != null &&
          qtyNumber != null)
          ? (unitPrice * qtyNumber)
          : 0;
        qli.Scale_Up_Lead_Time__c = '7 Calendar Days';
        qli.Glycerol_Stock__c = false;
        if (applyScaleUpGlycerol) {
          Decimal glycerolUnit = (qli.Quote != null &&
            qli.Quote.Pricebook2Id != null)
            ? glycerolPriceByPricebookId.get(qli.Quote.Pricebook2Id)
            : null;
          qli.Glycerol_Price__c = scaleUpGlycerolFeeForParent(
            glycerolChildPriceByParentId.get(qli.Id),
            glycerolUnit,
            qli.Glycerol_Price__c
          );
        } else {
          qli.Glycerol_Price__c = 0;
        }
      }
      qlisToUpdate.add(qli);
    }
    if (!qlisToUpdate.isEmpty()) {
      update qlisToUpdate;
    }

    // Remove SC-001/CS-200 Scale Up fee children and any GS-001 Glycerol children created
    // for Scale Up Glycerol (standard Glycerol on other parents is untouched).
    if (!sel || !glycerolStock) {
      Set<String> feeChildSkus = new Set<String>{
        SCALE_UP_PRODUCT_SKU,
        SCALE_UP_PRODUCT_SKU_LEGACY,
        GLYCEROL_STOCK_PRODUCT_SKU
      };
      if (sel) {
        // Still selected but Scale Up Glycerol off — only remove glycerol fee children.
        feeChildSkus = new Set<String>{ GLYCEROL_STOCK_PRODUCT_SKU };
      }
      List<QuoteLineItem> feeChildren = [
        SELECT Id
        FROM QuoteLineItem
        WHERE
          Parent_Line_Item__c IN :quoteLineItemIds
          AND (Product2.StockKeepingUnit IN :feeChildSkus
          OR Product_SKU__c IN :feeChildSkus)
      ];
      // Empty list is a no-op; keeps coverage of the cleanup path.
      delete feeChildren;
    }
  }

  /**
   * Parent Glycerol_Price__c is what the quote page adds into Add'l Fees.
   * Prefer the GS-001 child sales price so Internal $0 list prices cannot
   * replace the $30 glycerol fee. Do not change the child line itself.
   */
  @TestVisible
  private static Decimal scaleUpGlycerolFeeForParent(
    Decimal childUnitPrice,
    Decimal pricebookUnitPrice,
    Decimal existingParentPrice
  ) {
    if (childUnitPrice != null && childUnitPrice > 0) {
      return childUnitPrice;
    }
    if (pricebookUnitPrice != null && pricebookUnitPrice > 0) {
      return pricebookUnitPrice;
    }
    if (existingParentPrice != null && existingParentPrice > 0) {
      return existingParentPrice;
    }
    return 0;
  }

  @TestVisible
  private static Decimal scaleUpQuantityToDecimal(String quantity) {
    if (String.isBlank(quantity)) {
      return null;
    }
    try {
      return Decimal.valueOf(quantity.trim());
    } catch (Exception e) {
      return null;
    }
  }

  /**
   * Maps portal Normalization UI values to Scale_Up_Normalization__c picklist API values.
   * "NA" / "None" / blank are stored as null; the portal still displays None.
   */
  @TestVisible
  private static String scaleUpNormalizationToApiValue(String normalization) {
    if (String.isBlank(normalization)) {
      return null;
    }
    String value = normalization.trim();
    if (value.equalsIgnoreCase('NA') || value.equalsIgnoreCase('None')) {
      return null;
    }
    return value;
  }

  /** Mirrors Quote_Line_Item_Scale_Up mass matrix (High/Inducible/Medium vs Low). */
  @TestVisible
  private static String scaleUpMassForCopyNumber(
    String copyNumber,
    String quantity
  ) {
    String qty = quantity != null ? quantity.trim() : '';
    if (String.isBlank(qty)) {
      return null;
    }
    String copy = copyNumber != null ? copyNumber.trim() : '';
    Boolean highCopy =
      copy == 'High' ||
      copy == 'Inducible' ||
      copy == 'Medium';
    Boolean lowCopy = copy == 'Low';
    if (highCopy) {
      if (qty == '1')
        return '500 µg';
      if (qty == '2')
        return '1 mg';
      if (qty == '3')
        return '1.5 mg';
      if (qty == '4')
        return '2 mg';
      if (qty == '5')
        return '2.5 mg';
    } else if (lowCopy) {
      if (qty == '1')
        return '100 µg';
      if (qty == '2')
        return '200 µg';
      if (qty == '3')
        return '300 µg';
      if (qty == '4')
        return '400 µg';
      if (qty == '5')
        return '500 µg';
    }
    return null;
  }

  /**
   * Lines with vector + scale-up fields for the quote-detail grid. Used when
   * the wizard needs the full row after a scale-up matrix change.
   */
  @AuraEnabled(cacheable=true)
  public static List<ABT_Quote_Request_Lineitem__c> getQuoteLineItemsWithVectors(
    Id quoteRequestId
  ) {
    try {
      if (quoteRequestId == null) {
        return new List<ABT_Quote_Request_Lineitem__c>();
      }

      return [
        SELECT
          Id,
          Name,
          ABT_Product_Name__c,
          ABT_Product__r.StockKeepingUnit,
          ABT_Sales_Price__c,
          ABT_Quantity__c,
          ABT_Total_Price__c,
          Potentially_Toxic__c,
          Reflex_Vector_Opt_In__c,
          ABT_Quote_Request__c,
          ABT_Quote_Line_Item__c,
          Tranche__c,
          ABT_Quote_Line_Item__r.Vector__c,
          ABT_Quote_Line_Item__r.Vector__r.Name,
          ABT_Quote_Line_Item__r.Vector__r.Type__c,
          ABT_Quote_Line_Item__r.Vector__r.Active__c,
          ABT_Quote_Line_Item__r.End_Customer_List_Price__c,
          ABT_Quote_Line_Item__r.Tranche__c,
          As_Early_As_Date__c,
          Expected_Ship_Date__c,
          ABT_Quote_Line_Item__r.Scale_Up_Mass__c,
          ABT_Quote_Line_Item__r.Scale_Up_Price__c,
          ABT_Quote_Line_Item__r.Scale_Up_Lead_Time__c,
          ABT_Quote_Line_Item__r.Vector__r.Copy_Number__c,
          Scale_Up_Selected__c,
          Scale_Up_Quantity__c,
          Scale_Up_Glycerol_Stock__c,
          Scale_Up_Buffer__c,
          Scale_Up_Endotoxin_Free__c,
          Scale_Up_Animal_Free__c,
          Scale_Up_Normalization__c,
          Scale_Up_Lead_Time__c,
          Glycerol_Stock__c,
          Glycerol_Price__c,
          Total_Combined_Price__c,
          Related_Sequence__c,
          Related_Sequence__r.Sequence_Name__c,
          Related_Sequence__r.Sequence__c,
          Related_Sequence__r.Sequence_Length__c,
          Related_Sequence__r.Sequence_Classification__c,
          Related_Sequence__r.Feasibility_Classifier__c,
          Related_Sequence__r.Feasibility_Explained__c,
          Related_Sequence__r.Feasibility_Explained_1__c,
          Related_Sequence__r.Feasibility_Explained_2__c,
          Related_Sequence__r.Feasibility_Explained_3__c,
          Related_Sequence__r.Complexity__c,
          Related_Sequence__r.Complexity_Assessment__c,
          Related_Sequence__r.Sequence_Error__c,
          Related_Sequence__r.Sequence_Flag__c,
          Related_Sequence__r.Recommend_Not_High_Copy_Num_Vector__c,
          Related_Sequence__r.Vector__c,
          Related_Sequence__r.Vector_name__c,
          Related_Sequence__r.Vector__r.Name,
          Related_Sequence__r.Vector__r.Type__c,
          Related_Sequence__r.Vector__r.Active__c
        FROM ABT_Quote_Request_Lineitem__c
        WHERE ABT_Quote_Request__c = :quoteRequestId
        ORDER BY CreatedDate ASC
      ];
    } catch (Exception e) {
      System.debug('Error fetching line items with vectors: ' + e.getMessage());
      return new List<ABT_Quote_Request_Lineitem__c>();
    }
  }

  /**
   * Quote Line Item sales prices for a quote request (DNA + SC-001 + GS-001).
   * Portal quote page / new quote use these instead of inner Scale_Up_Price /
   * Glycerol_Price on the DNA line.
   */
  @AuraEnabled(cacheable=true)
  public static List<QuoteLineItem> getQuoteRequestSalesLineItems(
    Id quoteRequestId
  ) {
    try {
      if (quoteRequestId == null) {
        return new List<QuoteLineItem>();
      }
      List<ABT_Quote_Request__c> requests = [
        SELECT Id, ABT_Quote__c
        FROM ABT_Quote_Request__c
        WHERE Id = :quoteRequestId
        LIMIT 1
      ];
      if (requests.isEmpty() || requests[0].ABT_Quote__c == null) {
        return new List<QuoteLineItem>();
      }
      Id quoteId = requests[0].ABT_Quote__c;
      Map<String, Schema.SObjectField> qliFields = Schema.SObjectType.QuoteLineItem.fields.getMap();
      List<String> fields = new List<String>{
        'Id',
        'QuoteId',
        'Quantity',
        'UnitPrice',
        'TotalPrice',
        'Product2.Name',
        'Product2.StockKeepingUnit'
      };
      for (
        String fieldName : new List<String>{
          'Was_Deleted__c',
          'Parent_Line_Item__c',
          'Quote_Request_Line_item__c',
          'Product_SKU__c',
          'Product_Code__c',
          'Sequence_Name__c',
          'Customer_ID__c'
        }
      ) {
        if (qliFields.containsKey(fieldName.toLowerCase())) {
          fields.add(fieldName);
        }
      }
      String soql =
        'SELECT ' +
        String.join(fields, ', ') +
        ' FROM QuoteLineItem WHERE QuoteId = :quoteId';
      List<QuoteLineItem> visible = new List<QuoteLineItem>();
      for (QuoteLineItem qli : Database.query(soql)) {
        if (quoteLineItemIsActive(qli)) {
          visible.add(qli);
        }
      }
      return visible;
    } catch (Exception e) {
      System.debug('Error fetching quote sales line items: ' + e.getMessage());
      return new List<QuoteLineItem>();
    }
  }

  /**
   * Kick the sample-maps flow so the portal can poll for the S3 zip. Always
   * retriggers because those links expire.
   */
  @AuraEnabled
  public static Map<String, Object> triggerGenerateQuoteSampleMapsFlow(
    Id quoteRequestId
  ) {
    Map<String, Object> result = new Map<String, Object>();

    try {
      if (quoteRequestId == null) {
        result.put('success', false);
        result.put('message', 'Quote Request ID is required');
        return result;
      }

      // Get the Quote ID from the Quote Request
      ABT_Quote_Request__c quoteRequest = [
        SELECT Id, ABT_Quote__c
        FROM ABT_Quote_Request__c
        WHERE Id = :quoteRequestId
        LIMIT 1
      ];

      if (quoteRequest.ABT_Quote__c == null) {
        result.put('success', false);
        result.put('message', 'No Quote found for this Quote Request');
        return result;
      }

      // Always trigger the flow to generate fresh S3 links (since they expire)
      Map<String, Object> flowInputs = new Map<String, Object>();
      flowInputs.put('recordId', quoteRequest.ABT_Quote__c);

      // Invoke the autolaunched flow
      Flow.Interview.Generate_Quote_Sample_Maps_Autolaunched flowInterview = new Flow.Interview.Generate_Quote_Sample_Maps_Autolaunched(
        flowInputs
      );

      flowInterview.start();

      // The flow publishes a Platform Event which triggers async processing
      // So we return success immediately and let the user know the files are being generated
      result.put('success', true);
      result.put(
        'message',
        'Genbank files are being generated. Please wait a moment and then check back.'
      );
      result.put('quoteId', quoteRequest.ABT_Quote__c);
      result.put('processing', true);
    } catch (Exception e) {
      System.debug(
        'Error triggering Generate_Quote_Sample_Maps flow: ' + e.getMessage()
      );
      System.debug('Stack trace: ' + e.getStackTraceString());
      result.put('success', false);
      result.put(
        'message',
        'Error generating Genbank files: ' + e.getMessage()
      );
    }

    return result;
  }

  @AuraEnabled
  public static Map<String, Object> checkGenbankLinkStatus(Id quoteRequestId) {
    Map<String, Object> result = new Map<String, Object>();

    try {
      if (quoteRequestId == null) {
        result.put('success', false);
        result.put('message', 'Quote Request ID is required');
        return result;
      }

      // Get the Quote ID and Collateral Link from the Quote Request
      ABT_Quote_Request__c quoteRequest = [
        SELECT Id, ABT_Quote__c, ABT_Quote__r.Collateral_Link__c
        FROM ABT_Quote_Request__c
        WHERE Id = :quoteRequestId
        LIMIT 1
      ];

      if (quoteRequest.ABT_Quote__c == null) {
        result.put('success', false);
        result.put('message', 'No Quote found for this Quote Request');
        result.put('ready', false);
        return result;
      }

      // Check if Collateral_Link__c is populated
      if (
        quoteRequest.ABT_Quote__r.Collateral_Link__c != null &&
        quoteRequest.ABT_Quote__r.Collateral_Link__c != ''
      ) {
        result.put('success', true);
        result.put('ready', true);
        result.put('downloadUrl', quoteRequest.ABT_Quote__r.Collateral_Link__c);
        result.put('message', 'Genbank files are ready for download');
      } else {
        result.put('success', true);
        result.put('ready', false);
        result.put('message', 'Genbank files are still being generated');
      }
    } catch (Exception e) {
      System.debug('Error checking Genbank link status: ' + e.getMessage());
      result.put('success', false);
      result.put('ready', false);
      result.put('message', 'Error checking status: ' + e.getMessage());
    }

    return result;
  }

  // ==================== Order Collateral Download Methods ====================

  @AuraEnabled
  public static Map<String, Object> triggerOrderCollateralFlow(Id orderId) {
    Map<String, Object> result = new Map<String, Object>();

    try {
      if (orderId == null) {
        result.put('success', false);
        result.put('message', 'Order ID is required');
        return result;
      }

      // Trigger the Retrieve_Customer_Collateral_Link flow
      Map<String, Object> flowInputs = new Map<String, Object>();
      flowInputs.put('recordId', orderId); // Flow expects 'recordId' (same as the Salesforce button)

      Flow.Interview flowInterview = Flow.Interview.createInterview(
        'Retrieve_Customer_Collateral_Link_New',
        flowInputs
      );
      flowInterview.start();

      result.put('success', true);
      result.put('message', 'Order files are being generated. Please wait...');
      result.put('orderId', orderId);
      result.put('processing', true);
    } catch (Exception e) {
      System.debug(
        'Error triggering Order Collateral generation: ' + e.getMessage()
      );
      System.debug('Stack trace: ' + e.getStackTraceString());

      // Send error notification to customer service
      try {
        sendCollateralErrorNotification(
          orderId,
          'All Order Files',
          e.getMessage()
        );
      } catch (Exception emailEx) {
        System.debug(
          'Failed to send error notification email: ' + emailEx.getMessage()
        );
      }

      result.put('success', false);
      result.put('message', 'Error generating order files: ' + e.getMessage());
    }

    return result;
  }

  @AuraEnabled
  public static Map<String, Object> checkOrderCollateralLinkStatus(
    Id orderId,
    String fileSuffix,
    String fileExtension
  ) {
    Map<String, Object> result = new Map<String, Object>();

    try {
      if (orderId == null) {
        result.put('success', false);
        result.put('message', 'Order ID is required');
        return result;
      }

      // Get the Order record to retrieve NetSuite Order Number
      Order orderRecord = [
        SELECT Id, NetSuite_Order_Number__c
        FROM Order
        WHERE Id = :orderId
        LIMIT 1
      ];

      // Expected file name: <NetSuite Order Number>[suffix] with specified extension
      String expectedFileName = orderRecord.NetSuite_Order_Number__c;
      if (String.isNotBlank(fileSuffix)) {
        expectedFileName += fileSuffix;
      }

      // Default to zip if no extension specified
      String expectedExtension = String.isNotBlank(fileExtension)
        ? fileExtension
        : 'zip';

      // Check for ContentDocumentLink records related to this Order
      List<ContentDocumentLink> fileLinks = [
        SELECT
          Id,
          ContentDocumentId,
          ContentDocument.Title,
          ContentDocument.FileExtension,
          ContentDocument.LatestPublishedVersion.VersionDataUrl
        FROM ContentDocumentLink
        WHERE
          LinkedEntityId = :orderId
          AND ContentDocument.Title = :expectedFileName
          AND ContentDocument.FileExtension = :expectedExtension
        ORDER BY ContentDocument.CreatedDate DESC
        LIMIT 1
      ];

      if (!fileLinks.isEmpty()) {
        // File exists - return download URL
        result.put('success', true);
        result.put('ready', true);
        result.put(
          'downloadUrl',
          fileLinks[0].ContentDocument.LatestPublishedVersion.VersionDataUrl
        );
        result.put('message', 'Order files are ready for download');
        result.put('fileName', expectedFileName);
      } else {
        // File doesn't exist yet
        result.put('success', true);
        result.put('ready', false);
        result.put('message', 'Order files are still being generated');
        result.put('fileName', expectedFileName);
      }
    } catch (Exception e) {
      System.debug('Error checking Order file status: ' + e.getMessage());

      // Send error notification to customer service
      try {
        String filePrefix = String.isNotBlank(fileSuffix)
          ? fileSuffix
          : fileExtension;
        sendCollateralErrorNotification(orderId, filePrefix, e.getMessage());
      } catch (Exception emailEx) {
        System.debug(
          'Failed to send error notification email: ' + emailEx.getMessage()
        );
      }

      result.put('success', false);
      result.put('ready', false);
      result.put('message', 'Error checking status: ' + e.getMessage());
    }

    return result;
  }

  @AuraEnabled
  public static Map<String, Object> notifyCollateralDownloadFailure(
    Id orderId,
    String fileType,
    String errorMessage
  ) {
    Map<String, Object> result = new Map<String, Object>();

    try {
      if (orderId == null) {
        result.put('success', false);
        result.put('message', 'Order ID is required');
        return result;
      }

      String safeFileType = String.isNotBlank(fileType)
        ? fileType
        : 'Order files';
      String safeErrorMessage = String.isNotBlank(errorMessage)
        ? errorMessage
        : 'Polling timed out while waiting for collateral file generation';

      sendCollateralErrorNotification(orderId, safeFileType, safeErrorMessage);

      result.put('success', true);
      result.put('message', 'Failure notification email sent');
    } catch (Exception e) {
      System.debug(
        'Error sending collateral failure notification: ' + e.getMessage()
      );
      result.put('success', false);
      result.put(
        'message',
        'Error sending failure notification: ' + e.getMessage()
      );
    }

    return result;
  }

  // ==================== Individual Sequence Flow Trigger Methods ====================

  @AuraEnabled
  public static Map<String, Object> triggerIndividualCoAFlow(Id orderItemId) {
    Map<String, Object> result = new Map<String, Object>();

    try {
      if (orderItemId == null) {
        result.put('success', false);
        result.put('message', 'Order Item ID is required');
        return result;
      }

      // Trigger the Download_Individual_CoA flow
      Map<String, Object> flowInputs = new Map<String, Object>();
      flowInputs.put('recordId', orderItemId); // Flow expects OrderItem ID as recordId

      Flow.Interview flowInterview = Flow.Interview.createInterview(
        'Download_Individual_CoA',
        flowInputs
      );
      flowInterview.start();

      result.put('success', true);
      result.put(
        'message',
        'Individual CoA file is being generated. Please wait...'
      );
      result.put('orderItemId', orderItemId);
      result.put('processing', true);
    } catch (Exception e) {
      System.debug(
        'Error triggering Individual CoA generation: ' + e.getMessage()
      );
      System.debug('Stack trace: ' + e.getStackTraceString());

      // Send error notification to customer service
      try {
        sendCollateralErrorNotification(
          orderItemId,
          'Individual CoA',
          e.getMessage()
        );
      } catch (Exception emailEx) {
        System.debug(
          'Failed to send error notification email: ' + emailEx.getMessage()
        );
      }

      result.put('success', false);
      result.put(
        'message',
        'Error triggering CoA generation: ' + e.getMessage()
      );
    }

    return result;
  }

  @AuraEnabled
  public static Map<String, Object> triggerIndividualGenbankFlow(
    Id orderItemId
  ) {
    Map<String, Object> result = new Map<String, Object>();

    try {
      if (orderItemId == null) {
        result.put('success', false);
        result.put('message', 'Order Item ID is required');
        return result;
      }

      // Trigger the Download_Individual_Genbank flow
      Map<String, Object> flowInputs = new Map<String, Object>();
      flowInputs.put('recordId', orderItemId); // Flow expects OrderItem ID as recordId

      Flow.Interview flowInterview = Flow.Interview.createInterview(
        'Download_Individual_Genbank',
        flowInputs
      );
      flowInterview.start();

      result.put('success', true);
      result.put(
        'message',
        'Individual Genbank file is being generated. Please wait...'
      );
      result.put('orderItemId', orderItemId);
      result.put('processing', true);
    } catch (Exception e) {
      System.debug(
        'Error triggering Individual Genbank generation: ' + e.getMessage()
      );
      System.debug('Stack trace: ' + e.getStackTraceString());

      // Send error notification to customer service
      try {
        sendCollateralErrorNotification(
          orderItemId,
          'Individual Genbank',
          e.getMessage()
        );
      } catch (Exception emailEx) {
        System.debug(
          'Failed to send error notification email: ' + emailEx.getMessage()
        );
      }

      result.put('success', false);
      result.put(
        'message',
        'Error triggering Genbank generation: ' + e.getMessage()
      );
    }

    return result;
  }

  @AuraEnabled
  public static Map<String, Object> triggerIndividualFASTAFlow(Id orderItemId) {
    Map<String, Object> result = new Map<String, Object>();

    try {
      if (orderItemId == null) {
        result.put('success', false);
        result.put('message', 'Order Item ID is required');
        return result;
      }

      // Trigger the Download_Individual_FASTA flow
      Map<String, Object> flowInputs = new Map<String, Object>();
      flowInputs.put('recordId', orderItemId); // Flow expects OrderItem ID as recordId

      Flow.Interview flowInterview = Flow.Interview.createInterview(
        'Download_Individual_FASTA',
        flowInputs
      );
      flowInterview.start();

      result.put('success', true);
      result.put(
        'message',
        'Individual FASTA file is being generated. Please wait...'
      );
      result.put('orderItemId', orderItemId);
      result.put('processing', true);
    } catch (Exception e) {
      System.debug(
        'Error triggering Individual FASTA generation: ' + e.getMessage()
      );
      System.debug('Stack trace: ' + e.getStackTraceString());

      // Send error notification to customer service
      try {
        sendCollateralErrorNotification(
          orderItemId,
          'Individual FASTA',
          e.getMessage()
        );
      } catch (Exception emailEx) {
        System.debug(
          'Failed to send error notification email: ' + emailEx.getMessage()
        );
      }

      result.put('success', false);
      result.put(
        'message',
        'Error triggering FASTA generation: ' + e.getMessage()
      );
    }

    return result;
  }

  @AuraEnabled
  public static Map<String, Object> checkIndividualFileStatus(
    Id orderItemId,
    String fileType
  ) {
    Map<String, Object> result = new Map<String, Object>();

    try {
      if (orderItemId == null || String.isBlank(fileType)) {
        result.put('success', false);
        result.put('message', 'Order Item ID and File Type are required');
        return result;
      }

      // Get the OrderItem to retrieve the sequence name and Order ID
      OrderItem orderItem = [
        SELECT Id, Sequence_Name__c, OrderId, Order.Id
        FROM OrderItem
        WHERE Id = :orderItemId
        LIMIT 1
      ];

      // Expected file name pattern: ContentDocument.Title = <Sequence Name>, FileExtension = <extension>
      // Convert spaces to underscores for filename (e.g., "Sequence 1" becomes "Sequence_1")
      String expectedFileName = orderItem.Sequence_Name__c;
      if (String.isNotBlank(expectedFileName)) {
        expectedFileName = expectedFileName.replace(' ', '_');
      }
      String expectedExtension;

      if (fileType == 'CoAs (PDF)') {
        expectedExtension = 'pdf';
      } else if (fileType == 'Genbank Files') {
        expectedExtension = 'gb';
      } else if (fileType == 'FASTA Files') {
        expectedExtension = 'fasta';
      } else {
        result.put('success', false);
        result.put(
          'message',
          'Unsupported file type for individual download: ' + fileType
        );
        return result;
      }

      // Check for ContentDocumentLink records related to this Order
      List<ContentDocumentLink> fileLinks = [
        SELECT
          Id,
          ContentDocumentId,
          ContentDocument.Title,
          ContentDocument.FileExtension,
          ContentDocument.LatestPublishedVersion.VersionDataUrl
        FROM ContentDocumentLink
        WHERE
          LinkedEntityId = :orderItem.OrderId
          AND ContentDocument.Title = :expectedFileName
          AND ContentDocument.FileExtension = :expectedExtension
        ORDER BY ContentDocument.CreatedDate DESC
        LIMIT 1
      ];

      if (!fileLinks.isEmpty()) {
        // File exists - return download URL
        result.put('success', true);
        result.put('ready', true);
        result.put(
          'downloadUrl',
          fileLinks[0].ContentDocument.LatestPublishedVersion.VersionDataUrl
        );
        result.put('message', 'Individual file is ready for download');
        result.put('fileName', expectedFileName);
      } else {
        // File doesn't exist yet
        result.put('success', true);
        result.put('ready', false);
        result.put('message', 'Individual file is still being generated');
        result.put('fileName', expectedFileName);
      }
    } catch (Exception e) {
      System.debug('Error checking individual file status: ' + e.getMessage());
      result.put('success', false);
      result.put('ready', false);
      result.put('message', 'Error checking status: ' + e.getMessage());
    }

    return result;
  }

  // ==================== Bulk Flow Trigger Methods (renamed) ====================

  @AuraEnabled
  public static Map<String, Object> triggerCoAFlow(
    Id orderId,
    List<String> sequenceIds
  ) {
    Map<String, Object> result = new Map<String, Object>();

    try {
      if (orderId == null) {
        result.put('success', false);
        result.put('message', 'Order ID is required');
        return result;
      }

      // Get the Order record to retrieve NetSuite Order Number
      Order orderRecord = [
        SELECT Id, NetSuite_Order_Number__c
        FROM Order
        WHERE Id = :orderId
        LIMIT 1
      ];

      // Trigger the Download_All_CoAs flow
      Map<String, Object> flowInputs = new Map<String, Object>();
      flowInputs.put('recordId', orderId); // Flow expects 'recordId' input variable

      Flow.Interview flowInterview = Flow.Interview.createInterview(
        'Download_All_CoAs',
        flowInputs
      );
      flowInterview.start();

      result.put('success', true);
      result.put('message', 'CoA files are being generated. Please wait...');
      result.put('orderId', orderId);
      result.put('processing', true);
    } catch (Exception e) {
      System.debug('Error triggering CoA flow: ' + e.getMessage());
      System.debug('Stack trace: ' + e.getStackTraceString());

      // Send error notification to customer service
      try {
        sendCollateralErrorNotification(orderId, 'All CoAs', e.getMessage());
      } catch (Exception emailEx) {
        System.debug(
          'Failed to send error notification email: ' + emailEx.getMessage()
        );
      }

      result.put('success', false);
      result.put('message', 'Error generating CoA files: ' + e.getMessage());
    }

    return result;
  }

  @AuraEnabled
  public static Map<String, Object> triggerFASTAFlow(
    Id orderId,
    List<String> sequenceIds
  ) {
    Map<String, Object> result = new Map<String, Object>();

    try {
      if (orderId == null) {
        result.put('success', false);
        result.put('message', 'Order ID is required');
        return result;
      }

      // Get the Order record to retrieve NetSuite Order Number
      Order orderRecord = [
        SELECT Id, NetSuite_Order_Number__c
        FROM Order
        WHERE Id = :orderId
        LIMIT 1
      ];

      // Trigger the Download_All_FASTAs flow
      Map<String, Object> flowInputs = new Map<String, Object>();
      flowInputs.put('recordId', orderId); // Flow expects 'recordId' input variable

      Flow.Interview flowInterview = Flow.Interview.createInterview(
        'Download_All_FASTAs',
        flowInputs
      );
      flowInterview.start();

      result.put('success', true);
      result.put('message', 'FASTA files are being generated. Please wait...');
      result.put('orderId', orderId);
      result.put('processing', true);
    } catch (Exception e) {
      System.debug('Error triggering FASTA flow: ' + e.getMessage());
      System.debug('Stack trace: ' + e.getStackTraceString());

      // Send error notification to customer service
      try {
        sendCollateralErrorNotification(orderId, 'All FASTAs', e.getMessage());
      } catch (Exception emailEx) {
        System.debug(
          'Failed to send error notification email: ' + emailEx.getMessage()
        );
      }

      result.put('success', false);
      result.put('message', 'Error generating FASTA files: ' + e.getMessage());
    }

    return result;
  }

  @AuraEnabled
  public static Map<String, Object> triggerGenbankFlow(
    Id orderId,
    List<String> sequenceIds
  ) {
    Map<String, Object> result = new Map<String, Object>();

    try {
      if (orderId == null) {
        result.put('success', false);
        result.put('message', 'Order ID is required');
        return result;
      }

      // Get the Order record to retrieve NetSuite Order Number
      Order orderRecord = [
        SELECT Id, NetSuite_Order_Number__c
        FROM Order
        WHERE Id = :orderId
        LIMIT 1
      ];

      // Trigger the Download_All_Genbanks flow
      Map<String, Object> flowInputs = new Map<String, Object>();
      flowInputs.put('recordId', orderId); // Flow expects 'recordId' input variable

      Flow.Interview flowInterview = Flow.Interview.createInterview(
        'Download_All_Genbanks',
        flowInputs
      );
      flowInterview.start();

      result.put('success', true);
      result.put(
        'message',
        'Genbank files are being generated. Please wait...'
      );
      result.put('orderId', orderId);
      result.put('processing', true);
    } catch (Exception e) {
      System.debug('Error triggering Genbank flow: ' + e.getMessage());
      System.debug('Stack trace: ' + e.getStackTraceString());

      // Send error notification to customer service
      try {
        sendCollateralErrorNotification(
          orderId,
          'All Genbanks',
          e.getMessage()
        );
      } catch (Exception emailEx) {
        System.debug(
          'Failed to send error notification email: ' + emailEx.getMessage()
        );
      }

      result.put('success', false);
      result.put(
        'message',
        'Error generating Genbank files: ' + e.getMessage()
      );
    }

    return result;
  }

  @AuraEnabled
  public static Map<String, Object> triggerPlateMapsFlow(
    Id orderId,
    List<String> sequenceIds
  ) {
    Map<String, Object> result = new Map<String, Object>();

    try {
      if (orderId == null) {
        result.put('success', false);
        result.put('message', 'Order ID is required');
        return result;
      }

      // Get the Order record to retrieve NetSuite Order Number
      Order orderRecord = [
        SELECT Id, NetSuite_Order_Number__c
        FROM Order
        WHERE Id = :orderId
        LIMIT 1
      ];

      // Trigger the Download_Plate_Maps flow
      Map<String, Object> flowInputs = new Map<String, Object>();
      flowInputs.put('recordId', orderId); // Flow expects 'recordId' input variable

      Flow.Interview flowInterview = Flow.Interview.createInterview(
        'Download_Plate_Maps',
        flowInputs
      );
      flowInterview.start();

      result.put('success', true);
      result.put('message', 'Plate Maps are being generated. Please wait...');
      result.put('orderId', orderId);
      result.put('processing', true);
    } catch (Exception e) {
      System.debug('Error triggering Plate Maps flow: ' + e.getMessage());
      System.debug('Stack trace: ' + e.getStackTraceString());

      // Send error notification to customer service
      try {
        sendCollateralErrorNotification(orderId, 'Plate Maps', e.getMessage());
      } catch (Exception emailEx) {
        System.debug(
          'Failed to send error notification email: ' + emailEx.getMessage()
        );
      }

      result.put('success', false);
      result.put('message', 'Error generating Plate Maps: ' + e.getMessage());
    }

    return result;
  }

  @AuraEnabled
  public static Map<String, Object> triggerTabularCoAFlow(
    Id orderId,
    List<String> sequenceIds
  ) {
    Map<String, Object> result = new Map<String, Object>();

    try {
      if (orderId == null) {
        result.put('success', false);
        result.put('message', 'Order ID is required');
        return result;
      }

      // Get the Order record to retrieve NetSuite Order Number
      Order orderRecord = [
        SELECT Id, NetSuite_Order_Number__c
        FROM Order
        WHERE Id = :orderId
        LIMIT 1
      ];

      // Trigger the Download_Tabular_CoA flow
      Map<String, Object> flowInputs = new Map<String, Object>();
      flowInputs.put('recordId', orderId); // Flow expects 'recordId' input variable

      Flow.Interview flowInterview = Flow.Interview.createInterview(
        'Download_Tabular_CoA',
        flowInputs
      );
      flowInterview.start();

      result.put('success', true);
      result.put('message', 'Tabular CoA is being generated. Please wait...');
      result.put('orderId', orderId);
      result.put('processing', true);
    } catch (Exception e) {
      System.debug('Error triggering Tabular CoA flow: ' + e.getMessage());
      System.debug('Stack trace: ' + e.getStackTraceString());

      // Send error notification to customer service
      try {
        sendCollateralErrorNotification(orderId, 'Tabular CoA', e.getMessage());
      } catch (Exception emailEx) {
        System.debug(
          'Failed to send error notification email: ' + emailEx.getMessage()
        );
      }

      result.put('success', false);
      result.put('message', 'Error generating Tabular CoA: ' + e.getMessage());
    }

    return result;
  }

  // ==================== Helper Methods ====================

  /**
   * Sends an error notification email to customer service when collateral download fails
   * @param recordId The Order ID or OrderItem ID
   * @param fileType The type of file being requested (e.g., 'CoA', 'FASTA', 'Genbank', 'All Files')
   * @param errorMessage The error message details
   */
  @TestVisible
  private static void sendCollateralErrorNotification(
    Id recordId,
    String fileType,
    String errorMessage
  ) {
    try {
      if (recordId == null) {
        return;
      }

      User currentUser = [
        SELECT Id, Email, Name, ContactId, AccountId, Contact.AccountId
        FROM User
        WHERE Id = :UserInfo.getUserId()
        LIMIT 1
      ];

      String netsuiteOrderNumber;
      String orderNumber;
      Id orderId;
      Id orderAccountId;
      String additionalInfo = '';

      String objectType = recordId.getSObjectType().getDescribe().getName();

      if (objectType == 'Order') {
        Order orderRecord = [
          SELECT Id, NetSuite_Order_Number__c, OrderNumber, AccountId
          FROM Order
          WHERE Id = :recordId
          LIMIT 1
        ];
        netsuiteOrderNumber = orderRecord.NetSuite_Order_Number__c;
        orderNumber = orderRecord.OrderNumber;
        orderId = orderRecord.Id;
        orderAccountId = orderRecord.AccountId;
      } else if (objectType == 'OrderItem') {
        OrderItem orderItemRecord = [
          SELECT
            Id,
            OrderId,
            Order.NetSuite_Order_Number__c,
            Order.OrderNumber,
            Order.AccountId,
            Product2.Name,
            Sequence_Name__c
          FROM OrderItem
          WHERE Id = :recordId
          LIMIT 1
        ];
        netsuiteOrderNumber = orderItemRecord.Order.NetSuite_Order_Number__c;
        orderNumber = orderItemRecord.Order.OrderNumber;
        orderId = orderItemRecord.OrderId;
        orderAccountId = orderItemRecord.Order.AccountId;
        additionalInfo =
          '\nProduct: ' +
          (orderItemRecord.Product2.Name != null
            ? orderItemRecord.Product2.Name
            : 'N/A');
        if (String.isNotBlank(orderItemRecord.Sequence_Name__c)) {
          additionalInfo +=
            '\nSequence Name: ' + orderItemRecord.Sequence_Name__c;
        }
        additionalInfo += '\nOrder Item ID: ' + recordId;
      } else {
        return;
      }

      String fileDescription = String.isNotBlank(fileType) ? fileType : 'files';
      String subject =
        'Order Collateral Download Error - Order ' + netsuiteOrderNumber;

      String emailBody = 'Dear Customer Service Team,\n\n';
      emailBody +=
        'The following user: ' +
        currentUser.Email +
        ', tried to download the ' +
        fileDescription +
        ' from Order ' +
        netsuiteOrderNumber +
        ' but encountered an error.\n\n';
      emailBody += 'Please get the file from IFX and send it to them.\n\n';
      emailBody += 'Thanks,\n';
      emailBody += 'Commercial Operations Team\n\n';
      emailBody += '---\n';
      emailBody += 'Additional Details:\n';
      emailBody += 'User Name: ' + currentUser.Name + '\n';
      emailBody += 'Order ID: ' + orderId + '\n';
      emailBody += 'Order Number: ' + orderNumber + '\n';
      emailBody += 'NetSuite Order Number: ' + netsuiteOrderNumber + '\n';
      emailBody += 'Error Details: ' + errorMessage;
      emailBody += additionalInfo;

      createCollateralDownloadFailureCase(
        orderId,
        orderAccountId,
        currentUser,
        subject,
        emailBody
      );

      Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
      email.setToAddresses(new List<String>{ 'customerservice@ansabio.com' });
      email.setSubject(subject);
      email.setPlainTextBody(emailBody);
      Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });

      System.debug(
        'Error notification email sent to customer service for: ' + recordId
      );
    } catch (Exception e) {
      System.debug(
        'Failed to send error notification email: ' + e.getMessage()
      );
      System.debug('Stack trace: ' + e.getStackTraceString());
    }
  }

  private static void createCollateralDownloadFailureCase(
    Id orderId,
    Id orderAccountId,
    User currentUser,
    String subject,
    String description
  ) {
    if (orderId == null) {
      return;
    }

    try {
      Datetime recentCutoff = Datetime.now().addMinutes(-10);
      List<Case> existingCases = [
        SELECT Id
        FROM Case
        WHERE
          Related_Order__c = :orderId
          AND Subject = :subject
          AND CreatedDate >= :recentCutoff
        LIMIT 1
      ];
      if (!existingCases.isEmpty()) {
        return;
      }

      Case newCase = new Case();
      newCase.Subject = subject;
      newCase.Description = description;
      newCase.Origin = 'Community Portal';
      newCase.Status = 'New';
      newCase.Type = 'Question';
      newCase.Priority = 'Medium';
      newCase.AccountId = orderAccountId;
      newCase.Related_Order__c = orderId;
      newCase.Category__c = 'Portal_&_Account';
      newCase.Application__c = 'Collateral';
      newCase.Issue__c = 'Missing file';

      Map<String, Schema.RecordTypeInfo> recordTypes = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName();
      if (
        recordTypes.containsKey('General_Support_Inquiry') &&
        recordTypes.get('General_Support_Inquiry').isAvailable()
      ) {
        newCase.RecordTypeId = recordTypes.get('General_Support_Inquiry')
          .getRecordTypeId();
      }

      Id contactId = currentUser != null ? currentUser.ContactId : null;
      Id contactAccountId = currentUser != null
        ? currentUser.Contact?.AccountId
        : null;
      if (
        contactId != null &&
        (orderAccountId == null ||
        contactAccountId == orderAccountId)
      ) {
        newCase.ContactId = contactId;
      }

      List<Group> cxQueue = [
        SELECT Id
        FROM Group
        WHERE Type = 'Queue' AND DeveloperName = 'Customer_Experience'
        LIMIT 1
      ];
      if (!cxQueue.isEmpty()) {
        newCase.OwnerId = cxQueue[0].Id;
      }

      Database.DMLOptions dmlOptions = new Database.DMLOptions();
      dmlOptions.assignmentRuleHeader.useDefaultRule = false;
      newCase.setOptions(dmlOptions);

      insert newCase;
    } catch (Exception e) {
      System.debug(
        'Failed to create collateral download failure Case: ' + e.getMessage()
      );
      System.debug('Stack trace: ' + e.getStackTraceString());
    }
  }

  @AuraEnabled
  public static void deleteContactPointAddress(Id addressId) {
    try {
      ContactPointAddress addr = [
        SELECT Id
        FROM ContactPointAddress
        WHERE Id = :addressId
        LIMIT 1
      ];
      delete addr;
    } catch (Exception e) {
      throw new AuraHandledException(
        'Error deleting address: ' + e.getMessage()
      );
    }
  }

  // Order Now journey

  //   @AuraEnabled(cacheable=true)
  // public static List<ABT_Quote_Request__c> getQuoteRequestsByAccount(Id accountId) {
  //     if (accountId == null) {
  //         throw new AuraHandledException('accountId cannot be null');
  //     }
  //     return [
  //         SELECT
  //             Id,
  //             ABT_Customer_Project_Name__c,
  //             ABT_Product_Name__c,
  //             ABT_Stage__c,
  //             Vector__c,
  //             Vector__r.Name,
  //             Vector__r.Type__c,
  //             Vector__r.Active__c,
  //             CreatedDate
  //         FROM ABT_Quote_Request__c
  //         WHERE ABT_Account__c = :accountId
  //           AND ABT_Customer_Project_Name__c != null
  //         ORDER BY CreatedDate DESC
  //     ];
  // }

  /**
   * Active Project__c records for the new-quote combobox.
   * Shopper = My Projects (records they own). Buyer = Account Projects
   * (owned by them or linked to a quote request on their account).
   */
  @AuraEnabled(cacheable=true)
  public static List<Project__c> getQuoteRequestsByAccount() {
    User currentUser = [
      SELECT Id, AccountId, Profile.Name
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];
    Boolean isB2BBuyer =
      currentUser.Profile.Name ==
      ABT_Portal_PermissionService.PROFILE_B2B_BUYER &&
      currentUser.AccountId != null;

    if (isB2BBuyer) {
      Id accountId = currentUser.AccountId;
      Id currentUserId = currentUser.Id;
      Set<Id> accountProjectIds = new Set<Id>();
      for (ABT_Quote_Request__c qr : [
        SELECT Project__c
        FROM ABT_Quote_Request__c
        WHERE ABT_Account__c = :accountId AND Project__c != NULL
      ]) {
        accountProjectIds.add(qr.Project__c);
      }
      if (accountProjectIds.isEmpty()) {
        return [
          SELECT Id, Name
          FROM Project__c
          WHERE Active__c = TRUE AND OwnerId = :currentUserId
          ORDER BY Name ASC
        ];
      }
      return [
        SELECT Id, Name
        FROM Project__c
        WHERE
          Active__c = TRUE
          AND (OwnerId = :currentUserId
          OR Id IN :accountProjectIds)
        ORDER BY Name ASC
      ];
    }

    Id currentUserId = currentUser.Id;
    return [
      SELECT Id, Name
      FROM Project__c
      WHERE Active__c = TRUE AND OwnerId = :currentUserId
      ORDER BY Name ASC
    ];
  }

  /** Create the Quote Request (and Project__c if they typed a new name). Returns the portal display #. */
  @AuraEnabled
  public static CreateQuoteRequestResult createQuoteRequest(
    Id accountId,
    Id productId,
    String projectName,
    String vectorId,
    Boolean isGlycerol
  ) {
    try {
      Id projectId;

      // 1. Handle Project Logic
      // The LWC combobox passes a Project__c record ID when an existing project is selected,
      // or a plain text name when the user types a new project name.
      String resolvedProjectName = projectName;
      if (String.isNotBlank(projectName)) {
        try {
          // If projectName is a valid Salesforce ID, it's an existing project
          Id directId = Id.valueOf(projectName);
          projectId = directId;
          List<Project__c> prj = [
            SELECT Name
            FROM Project__c
            WHERE Id = :directId
            LIMIT 1
          ];
          if (!prj.isEmpty())
            resolvedProjectName = prj[0].Name;
        } catch (Exception idEx) {
          // Not an ID — treat as a free-text project name: find or create
          List<Project__c> existingPrjs = [
            SELECT Id
            FROM Project__c
            WHERE Name = :projectName
            LIMIT 1
          ];
          if (existingPrjs.isEmpty()) {
            Project__c newPrj = new Project__c(
              Name = projectName,
              Active__c = true
            );
            insert newPrj;
            projectId = newPrj.Id;
          } else {
            projectId = existingPrjs[0].Id;
          }
        }
      }

      // 2. Create Quote Request
      ABT_Quote_Request__c qr = new ABT_Quote_Request__c();
      qr.ABT_Account__c = accountId;
      qr.ABT_Product__c = productId;
      qr.ABT_Customer_Project_Name__c = resolvedProjectName;
      qr.Project__c = projectId;
      qr.Accept_Partial_Shipment__c = defaultAcceptPartialShipmentForAccount(
        accountId
      );

      // Fixed logic: Use String.isNotBlank and check for 'none' string
      if (String.isNotBlank(vectorId) && vectorId != 'none') {
        qr.Vector__c = vectorId;
      }

      // Set glycerol field if it exists on the object
      // qr.Is_Glycerol__c = isGlycerol;

      insert qr;

      ABT_Quote_Request__c inserted = [
        SELECT Id, Name, Ansa_Quote_Number__c, Quote_Number__c
        FROM ABT_Quote_Request__c
        WHERE Id = :qr.Id
        LIMIT 1
      ];
      CreateQuoteRequestResult result = new CreateQuoteRequestResult();
      result.quoteRequestId = inserted.Id;
      result.displayQuoteNumber = resolveQuoteRequestDisplayNumber(inserted);
      return result;
    } catch (Exception e) {
      throw new AuraHandledException(
        'Error creating quote request: ' + e.getMessage()
      );
    }
  }

  /** Unchecked unless Account.Always_Accept_Partial__c is true. */
  @TestVisible
  private static Boolean defaultAcceptPartialShipmentForAccount(Id accountId) {
    if (accountId == null) {
      return false;
    }
    List<Account> accounts = [
      SELECT Always_Accept_Partial__c
      FROM Account
      WHERE Id = :accountId
      LIMIT 1
    ];
    return !accounts.isEmpty() && accounts[0].Always_Accept_Partial__c == true;
  }

  private static String resolveQuoteRequestDisplayNumber(
    ABT_Quote_Request__c qr
  ) {
    if (qr == null) {
      return '';
    }
    if (String.isNotBlank(qr.Ansa_Quote_Number__c)) {
      return qr.Ansa_Quote_Number__c.trim();
    }
    if (String.isNotBlank(qr.Quote_Number__c)) {
      return qr.Quote_Number__c.trim();
    }
    return qr.Name != null ? qr.Name.trim() : '';
  }

  /**
   * Removes the quote request from the active cart when a cart quote is edited so stale
   * pricing/options are not checked out.
   */
  @TestVisible
  private static Boolean clearQuoteRequestFromCart(Id quoteRequestId) {
    if (quoteRequestId == null) {
      return false;
    }

    try {
      return removeQuoteRequestFromCommerceCart(quoteRequestId);
    } catch (Exception e) {
      return false;
    }
  }

  @TestVisible
  private static Boolean clearQuoteRequestFromCartForLineItem(Id lineItemId) {
    if (lineItemId == null) {
      return false;
    }

    List<ABT_Quote_Request_Lineitem__c> lineItems = [
      SELECT ABT_Quote_Request__c
      FROM ABT_Quote_Request_Lineitem__c
      WHERE Id = :lineItemId
      LIMIT 1
    ];
    if (lineItems.isEmpty() || lineItems[0].ABT_Quote_Request__c == null) {
      return false;
    }

    return clearQuoteRequestFromCart(lineItems[0].ABT_Quote_Request__c);
  }

  /** LWC wrapper around ABT_Cart_Service.remove. */
  @AuraEnabled
  public static Boolean removeQuoteRequestFromCart(Id quoteRequestId) {
    try {
      return clearQuoteRequestFromCart(quoteRequestId);
    } catch (Exception e) {
      throw new AuraHandledException(
        'Error removing quote from cart: ' + e.getMessage()
      );
    }
  }

  /**
   * Maps portal stage labels (Draft / Quoted / Ordered) to valid Quote.Status picklist values.
   * ABT_Stage__c on the quote request is derived from Quote.Status via formula.
   */
  @TestVisible
  private static String mapPortalStageToQuoteStatus(String stage) {
    if (String.isBlank(stage)) {
      return stage;
    }
    String normalized = stage.trim();
    if (normalized.equalsIgnoreCase('Quoted')) {
      return 'Presented';
    }
    if (normalized.equalsIgnoreCase('Draft')) {
      return 'Draft';
    }
    if (normalized.equalsIgnoreCase('Ordered')) {
      return 'Ordered';
    }
    return normalized;
  }

  /** Tubes vs plate packaging on the Quote Request. */
  @AuraEnabled
  public static void updateQuoteRequestPackaging(
    Id quoteRequestId,
    String packagingType
  ) {
    try {
      if (quoteRequestId == null) {
        throw new AuraHandledException('Quote Request ID is required');
      }
      String picklistValue = resolvePackagingPicklistValue(packagingType);
      if (String.isBlank(picklistValue)) {
        return;
      }
      update new ABT_Quote_Request__c(
        Id = quoteRequestId,
        Request_Packaging__c = picklistValue
      );
    } catch (Exception e) {
      throw new AuraHandledException(
        'Error updating quote request packaging: ' + e.getMessage()
      );
    }
  }

  /** Draft / Quoted / Ordered on the QR — maps to Quote.Status under the hood. */
  @AuraEnabled
  public static void updateQuoteRequestStage(Id quoteRequestId, String stage) {
    try {
      ABT_Quote_Request__c qr = [
        SELECT Id, ABT_Quote__c
        FROM ABT_Quote_Request__c
        WHERE Id = :quoteRequestId
        LIMIT 1
      ];
      String normalizedStage = String.isBlank(stage) ? '' : stage.trim();
      if (qr.ABT_Quote__c != null) {
        String quoteStatus = mapPortalStageToQuoteStatus(stage);
        update new Quote(Id = qr.ABT_Quote__c, Status = quoteStatus);
      }
    } catch (Exception e) {
      throw new AuraHandledException(
        'Error updating quote stage: ' + e.getMessage()
      );
    }
  }

  /** Add one sequence line (QRLI + Sequence__c) from the wizard. */
  @AuraEnabled
  public static ABT_Quote_Request_Lineitem__c createQuoteRequestLineItem(
    Id quoteRequestId,
    String sequenceName,
    String sequence,
    Id vectorId,
    Boolean potentiallyToxic,
    Boolean glycerolStock,
    Boolean reflexVectorOptIn
  ) {
    try {
      ABT_SequenceSyncService.LineWithSequenceInput input = new ABT_SequenceSyncService.LineWithSequenceInput();
      input.quoteRequestId = quoteRequestId;
      input.sequenceName = sequenceName;
      input.sequence = sequence;
      input.vectorId = vectorId;
      input.potentiallyToxic = potentiallyToxic;
      input.glycerolStock = glycerolStock;
      input.reflexVectorOptIn = reflexVectorOptIn;

      ABT_Quote_Request_Lineitem__c createdLineItem = ABT_SequenceSyncService.createPortalQuoteRequestLineItem(
        input
      );
      if (createdLineItem != null) {
        clearQuoteRequestFromCart(quoteRequestId);
        return createdLineItem;
      }
      System.debug(LoggingLevel.WARN, 'createQuoteRequestLineItem soft-failed');
      return null;
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'createQuoteRequestLineItem exception: ' + e.getMessage()
      );
      return null;
    }
  }

  /** Bulk add sequences (CSV / multi-paste). */
  @AuraEnabled
  public static List<ABT_Quote_Request_Lineitem__c> createQuoteRequestLineItems(
    Id quoteRequestId,
    List<String> sequenceNames,
    List<String> sequences,
    List<Id> vectorIds,
    List<Boolean> potentiallyToxicFlags,
    List<Boolean> glycerolStockFlags,
    List<Boolean> reflexVectorOptInFlags
  ) {
    List<ABT_Quote_Request_Lineitem__c> orderedResults = new List<ABT_Quote_Request_Lineitem__c>();
    try {
      List<ABT_SequenceSyncService.LineWithSequenceInput> inputs = ABT_SequenceSyncService.buildLineWithSequenceInputs(
        quoteRequestId,
        sequenceNames,
        sequences,
        vectorIds,
        potentiallyToxicFlags,
        glycerolStockFlags,
        reflexVectorOptInFlags
      );
      if (inputs.isEmpty()) {
        return orderedResults;
      }

      orderedResults = ABT_SequenceSyncService.createPortalQuoteRequestLineItems(
        inputs
      );
      for (ABT_Quote_Request_Lineitem__c row : orderedResults) {
        if (row != null) {
          clearQuoteRequestFromCart(quoteRequestId);
          break;
        }
      }
      return orderedResults;
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'createQuoteRequestLineItems exception: ' + e.getMessage()
      );
      return orderedResults;
    }
  }

  /**
   * Re-queries a quote request line item after the pricing Flow has had time to run.
   * Called by the LWC polling loop until ABT_Total_Price__c is populated.
   */
  @AuraEnabled
  public static Map<String, Object> updateSequenceForLineItem(
    Id lineItemId,
    String sequenceName,
    String sequence,
    Id vectorId
  ) {
    Map<String, Object> result = new Map<String, Object>();
    try {
      result = ABT_SequenceSyncService.buildPortalSequenceUpdateResult(
        lineItemId,
        sequenceName,
        sequence,
        vectorId
      );
      if (result.get('success') == true) {
        result.put(
          'removedFromCart',
          clearQuoteRequestFromCartForLineItem(lineItemId)
        );
      }
    } catch (Exception e) {
      result.put('success', false);
      result.put('error', e.getMessage());
    }
    return result;
  }

  @AuraEnabled
  public static ABT_Quote_Request_Lineitem__c getLineItemPricing(
    Id lineItemId
  ) {
    try {
      List<ABT_Quote_Request_Lineitem__c> results = [
        SELECT
          Id,
          ABT_Total_Price__c,
          Total_Combined_Price__c,
          Scale_Up_Selected__c,
          Scale_Up_Quantity__c,
          Scale_Up_Glycerol_Stock__c,
          Scale_Up_Buffer__c,
          Scale_Up_Endotoxin_Free__c,
          Scale_Up_Animal_Free__c,
          Scale_Up_Normalization__c,
          Scale_Up_Lead_Time__c,
          Glycerol_Stock__c,
          Glycerol_Price__c,
          Potentially_Toxic__c,
          Reflex_Vector_Opt_In__c,
          Tranche__c,
          ABT_Quote_Line_Item__c,
          As_Early_As_Date__c,
          Expected_Ship_Date__c,
          ABT_Quote_Line_Item__r.OSC_Guaranteed__c,
          ABT_Quote_Line_Item__r.Tranche__c,
          ABT_Quote_Line_Item__r.Scale_Up_Mass__c,
          ABT_Quote_Line_Item__r.Scale_Up_Price__c,
          ABT_Quote_Line_Item__r.Scale_Up_Lead_Time__c,
          ABT_Quote_Line_Item__r.End_Customer_List_Price__c,
          Related_Sequence__c,
          Related_Sequence__r.Sequence_Name__c,
          Related_Sequence__r.Sequence__c,
          Related_Sequence__r.Sequence_Length__c,
          Related_Sequence__r.Sequence_Classification__c,
          Related_Sequence__r.Feasibility_Classifier__c,
          Related_Sequence__r.Feasibility_Explained__c,
          Related_Sequence__r.Feasibility_Explained_1__c,
          Related_Sequence__r.Feasibility_Explained_2__c,
          Related_Sequence__r.Feasibility_Explained_3__c,
          Related_Sequence__r.Complexity__c,
          Related_Sequence__r.Complexity_Assessment__c,
          Related_Sequence__r.Complexity_Score__c,
          Related_Sequence__r.Sequence_Error__c,
          Related_Sequence__r.Sequence_Flag__c,
          Related_Sequence__r.Recommend_Not_High_Copy_Num_Vector__c,
          Related_Sequence__r.Vector__c,
          Related_Sequence__r.Vector_name__c,
          Related_Sequence__r.Vector__r.Name
        FROM ABT_Quote_Request_Lineitem__c
        WHERE Id = :lineItemId
        LIMIT 1
      ];
      return results.isEmpty() ? null : results[0];
    } catch (Exception e) {
      return null;
    }
  }

  private static final String NETSUITE_ORDER_PENDING = 'Pending';

  /** Portal display for Ansa Order Number — NetSuite when assigned, otherwise "Pending". */
  public static String resolvePortalOrderDisplayNumber(
    String orderNumber,
    String netSuiteOrderNumber
  ) {
    String ns = String.isBlank(netSuiteOrderNumber)
      ? ''
      : netSuiteOrderNumber.trim();
    if (!String.isBlank(ns) && !NETSUITE_ORDER_PENDING.equalsIgnoreCase(ns)) {
      return ns;
    }
    return NETSUITE_ORDER_PENDING;
  }

  /** Prefer quote-request project title over Order.Customer_Project_Name__c (may include Opportunity name). */
  public static String resolvePortalOrderProjectName(
    Id quoteId,
    String customerProjectNameOnOrder,
    SObject projectRel
  ) {
    if (quoteId != null) {
      Map<Id, String> titleByQuoteId = loadProjectTitleByQuoteId(
        new Set<Id>{ quoteId }
      );
      if (titleByQuoteId.containsKey(quoteId)) {
        return titleByQuoteId.get(quoteId);
      }
    }
    if (
      projectRel != null && String.isNotBlank((String) projectRel.get('Name'))
    ) {
      return ((String) projectRel.get('Name')).trim();
    }
    if (String.isBlank(customerProjectNameOnOrder)) {
      return null;
    }
    String raw = customerProjectNameOnOrder.trim();
    try {
      Id projectId = Id.valueOf(raw);
      List<Project__c> projects = [
        SELECT Name
        FROM Project__c
        WHERE Id = :projectId
        LIMIT 1
      ];
      return projects.isEmpty() ? raw : projects[0].Name;
    } catch (Exception e) {
      return raw;
    }
  }

  @TestVisible
  private static String mapPortalPaymentMethod(String raw) {
    if (String.isBlank(raw)) {
      return 'Purchase Order';
    }
    String lower = raw.toLowerCase();
    if (lower.contains('credit')) {
      return 'Credit Card';
    }
    if (lower.contains('bpo') || lower.contains('blanket')) {
      return 'Purchase Order';
    }
    if (lower.contains('purchase') || lower == 'purchase_order') {
      return 'Purchase Order';
    }
    return raw;
  }

  @TestVisible
  private static Boolean isPortalCreditCardPaymentMethod(String paymentMethod) {
    if (String.isBlank(paymentMethod)) {
      return false;
    }
    return paymentMethod.toLowerCase().contains('credit');
  }

  private static Id getCurrentUserContactId() {
    User currentUser = [
      SELECT ContactId
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];
    return currentUser.ContactId;
  }

  @TestVisible
  private static String resolveCheckoutStripePaymentMethodId(
    String paymentMethod,
    Id contactId,
    String paymentMethodRecordId
  ) {
    if (
      !isPortalCreditCardPaymentMethod(paymentMethod) ||
      String.isBlank(paymentMethodRecordId)
    ) {
      return null;
    }

    Id paymentMethodId;
    try {
      paymentMethodId = Id.valueOf(paymentMethodRecordId);
    } catch (Exception e) {
      throw checkoutAura('Selected payment method was not found.');
    }
    List<ABT_Payment_Method__c> rows = [
      SELECT ABT_Stripe_Payment_Method_Id__c, ABT_Contact__c
      FROM ABT_Payment_Method__c
      WHERE Id = :paymentMethodId
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      throw new AuraHandledException('Selected payment method was not found.');
    }
    if (contactId != null && rows[0].ABT_Contact__c != contactId) {
      throw new AuraHandledException(
        'You are not authorized to use this payment method.'
      );
    }
    if (String.isBlank(rows[0].ABT_Stripe_Payment_Method_Id__c)) {
      throw new AuraHandledException(
        'The selected payment method is not linked to Stripe.'
      );
    }
    return rows[0].ABT_Stripe_Payment_Method_Id__c;
  }

  @TestVisible
  private static void validatePortalCreditCardCheckout(
    String paymentMethod,
    String paymentMethodRecordId
  ) {
    if (!isPortalCreditCardPaymentMethod(paymentMethod)) {
      return;
    }
    if (String.isBlank(paymentMethodRecordId)) {
      throw new AuraHandledException(
        'Please select a credit card to continue.'
      );
    }
  }
  @TestVisible
  private static Boolean isPortalBpoPaymentMethod(String paymentMethod) {
    if (String.isBlank(paymentMethod)) {
      return false;
    }
    String lower = paymentMethod.toLowerCase();
    return lower.contains('bpo') || lower.contains('blanket');
  }

  @TestVisible
  private static Id resolveCheckoutBlanketPurchaseOrderId(
    String paymentMethod,
    Id accountId,
    String bpoId,
    String poNumber
  ) {
    if (!isPortalBpoPaymentMethod(paymentMethod) || accountId == null) {
      return null;
    }
    if (String.isNotBlank(bpoId)) {
      try {
        return Id.valueOf(bpoId);
      } catch (Exception e) {
        return null;
      }
    }
    BpoLookupResult lookup = getActiveBpoForAccount(accountId, poNumber);
    return lookup != null ? lookup.id : null;
  }

  @TestVisible
  private static String resolveCheckoutPoNumber(
    String paymentMethod,
    String poNumber,
    Id blanketPurchaseOrderId
  ) {
    if (
      blanketPurchaseOrderId != null && isPortalBpoPaymentMethod(paymentMethod)
    ) {
      List<Blanket_Purchase_Orders__c> rows = [
        SELECT PO_Number__c
        FROM Blanket_Purchase_Orders__c
        WHERE Id = :blanketPurchaseOrderId
        LIMIT 1
      ];
      if (!rows.isEmpty() && String.isNotBlank(rows[0].PO_Number__c)) {
        return rows[0].PO_Number__c;
      }
    }
    return poNumber;
  }

  @TestVisible
  private static String mapPortalShipMethod(String raw) {
    if (String.isBlank(raw)) {
      return null;
    }
    String lower = raw.toLowerCase();
    if (lower.contains('priority') && lower.contains('overnight')) {
      return 'FedEx Priority Overnight® One Rate';
    }
    if (lower.contains('2 day') || lower.contains('2day')) {
      return 'FedEx 2Day® One Rate';
    }
    if (lower.contains('international')) {
      return 'FedEx International Priority®';
    }
    if (lower.contains('saver')) {
      return 'FedEx Express Saver One Rate';
    }
    if (lower.contains('standard') && lower.contains('overnight')) {
      return 'FedEx Standard Overnight®';
    }
    return null;
  }

  private static void copyContactPointAddressToOrderBilling(
    Order ord,
    ContactPointAddress cpa
  ) {
    if (cpa == null) {
      return;
    }
    String street = cpa.Street;
    String city = cpa.City;
    String state = cpa.State;
    String postal = cpa.PostalCode;
    String country = cpa.Country;
    if (cpa.Address != null) {
      if (String.isBlank(street)) {
        street = cpa.Address.getStreet();
      }
      if (String.isBlank(city)) {
        city = cpa.Address.getCity();
      }
      if (String.isBlank(state)) {
        state = cpa.Address.getState();
      }
      if (String.isBlank(postal)) {
        postal = cpa.Address.getPostalCode();
      }
      if (String.isBlank(country)) {
        country = cpa.Address.getCountry();
      }
    }
    ord.BillingStreet = street;
    ord.BillingCity = city;
    ord.BillingState = state;
    ord.BillingPostalCode = postal;
    ord.BillingCountry = country;
  }

  private static void copyContactPointAddressToOrderShipping(
    Order ord,
    ContactPointAddress cpa
  ) {
    if (cpa == null) {
      return;
    }
    String street = cpa.Street;
    String city = cpa.City;
    String state = cpa.State;
    String postal = cpa.PostalCode;
    String country = cpa.Country;
    if (cpa.Address != null) {
      if (String.isBlank(street)) {
        street = cpa.Address.getStreet();
      }
      if (String.isBlank(city)) {
        city = cpa.Address.getCity();
      }
      if (String.isBlank(state)) {
        state = cpa.Address.getState();
      }
      if (String.isBlank(postal)) {
        postal = cpa.Address.getPostalCode();
      }
      if (String.isBlank(country)) {
        country = cpa.Address.getCountry();
      }
    }
    ord.ShippingStreet = street;
    ord.ShippingCity = city;
    ord.ShippingState = state;
    ord.ShippingPostalCode = postal;
    ord.ShippingCountry = country;
  }

  /** Active default for Order.Requested_Packaging__c (restricted picklist). */
  private static String defaultActiveOrderPackaging() {
    return 'Microcentrifuge Tube';
  }

  private static Boolean isActiveOrderPackagingValue(String apiValue) {
    if (String.isBlank(apiValue)) {
      return false;
    }
    for (
      Schema.PicklistEntry entry : Order.Requested_Packaging__c.getDescribe()
        .getPicklistValues()
    ) {
      if (entry.isActive() && entry.getValue() == apiValue) {
        return true;
      }
    }
    return false;
  }

  /** Accept picklist API values directly; map legacy portal codes when needed. */
  private static String resolvePackagingPicklistValue(String raw) {
    if (String.isBlank(raw)) {
      return null;
    }
    if (isActiveOrderPackagingValue(raw)) {
      return raw;
    }
    String mapped = mapPortalPackaging(raw);
    if (isActiveOrderPackagingValue(mapped)) {
      return mapped;
    }
    return defaultActiveOrderPackaging();
  }

  /** Map portal packaging codes to active Requested_Packaging__c API values. */
  private static String mapPortalPackaging(String raw) {
    if (String.isBlank(raw)) {
      return null;
    }
    String lower = raw.toLowerCase();
    if (lower.contains('axygen')) {
      return 'Axygen 96';
    }
    if (lower.contains('plate') || lower.contains('armadillo')) {
      return 'Axygen 96';
    }
    if (
      lower.contains('corteva') ||
      lower.contains('matrix') ||
      lower.contains('tube') ||
      lower.contains('standard') ||
      lower.contains('premium')
    ) {
      return 'Microcentrifuge Tube';
    }
    return null;
  }

  /**
   * Normalize quote packaging before Status = Ordered so Order - Create From Quote
   * does not copy inactive picklist values (e.g. Corteva Matrix Tube) onto Order.
   */
  private static void sanitizeCartQuotePackaging(List<Id> quoteIds) {
    if (quoteIds == null || quoteIds.isEmpty()) {
      return;
    }
    Map<String, Schema.SObjectField> quoteFieldMap = Schema.SObjectType.Quote.fields.getMap();
    if (!quoteFieldMap.containsKey('request_packaging__c')) {
      return;
    }

    List<Quote> quotes = [
      SELECT Id, Request_Packaging__c
      FROM Quote
      WHERE Id IN :quoteIds
    ];
    List<Quote> updates = new List<Quote>();
    for (Quote q : quotes) {
      if (String.isBlank(q.Request_Packaging__c)) {
        continue;
      }
      String resolved = resolvePackagingPicklistValue(q.Request_Packaging__c);
      if (resolved != q.Request_Packaging__c) {
        updates.add(new Quote(Id = q.Id, Request_Packaging__c = resolved));
      }
    }
    if (!updates.isEmpty()) {
      update updates;
    }
  }

  private static void putOrderFieldIfPresent(
    Order ord,
    Map<String, Schema.SObjectField> orderFieldMap,
    String fieldName,
    Object value
  ) {
    if (value == null || !orderFieldMap.containsKey(fieldName.toLowerCase())) {
      return;
    }
    ord.put(fieldName, value);
  }

  private static void cleanupPortalCartDuplicateOrders(
    Id cartOrderId,
    Id primaryQuoteId,
    List<Id> cartQuoteIds
  ) {
    if (
      cartOrderId == null ||
      cartQuoteIds == null ||
      cartQuoteIds.size() < 2
    ) {
      return;
    }

    Set<Id> secondaryQuoteIds = new Set<Id>(cartQuoteIds);
    secondaryQuoteIds.remove(primaryQuoteId);
    if (secondaryQuoteIds.isEmpty()) {
      return;
    }

    // Quote-ordered automation creates one Order per QuoteId. Cart checkout consolidates
    // every quote onto cartOrderId, so any other order tied to a secondary quote is stray.
    List<Order> strayOrders = [
      SELECT Id
      FROM Order
      WHERE QuoteId IN :secondaryQuoteIds AND Id != :cartOrderId
    ];
    if (strayOrders.isEmpty()) {
      return;
    }

    Set<Id> strayOrderIds = new Map<Id, Order>(strayOrders).keySet();
    List<OrderItem> strayItems = [
      SELECT Id
      FROM OrderItem
      WHERE OrderId IN :strayOrderIds
    ];
    if (!strayItems.isEmpty()) {
      delete strayItems;
    }
    delete strayOrders;
  }

  @AuraEnabled(cacheable=true)
  public static Map<String, String> getQuoteDisplayNumbersForOrder(Id orderId) {
    Map<String, String> quoteNumberByOrderItemId = new Map<String, String>();
    if (orderId == null) {
      return quoteNumberByOrderItemId;
    }

    Map<String, Schema.SObjectField> oiFields = Schema.SObjectType.OrderItem.fields.getMap();
    Boolean hasSalesforceQuoteLineId = oiFields.containsKey(
      'salesforce_quote_line_id__c'
    );

    String oiQuery = 'SELECT Id, QuoteLineItemId';
    if (hasSalesforceQuoteLineId) {
      oiQuery += ', Salesforce_Quote_Line_ID__c';
    }
    oiQuery +=
      ', QuoteLineItem.Quote.Ansa_Quote_Number__c, QuoteLineItem.Quote.QuoteNumber' +
      ' FROM OrderItem WHERE OrderId = :orderId';

    List<OrderItem> items = Database.query(oiQuery);
    Set<Id> quoteLineItemIds = new Set<Id>();

    for (OrderItem item : items) {
      if (item.QuoteLineItemId != null) {
        quoteLineItemIds.add(item.QuoteLineItemId);
      } else if (hasSalesforceQuoteLineId) {
        String rawLineId = (String) item.get('Salesforce_Quote_Line_ID__c');
        if (String.isNotBlank(rawLineId)) {
          try {
            quoteLineItemIds.add(Id.valueOf(rawLineId.trim()));
          } catch (Exception e) {
            // Ignore malformed line id values.
          }
        }
      }
    }

    Map<Id, QuoteLineItem> quoteLineItemsById = quoteLineItemIds.isEmpty()
      ? new Map<Id, QuoteLineItem>()
      : new Map<Id, QuoteLineItem>(
          [
            SELECT Id, Quote.Ansa_Quote_Number__c, Quote.QuoteNumber
            FROM QuoteLineItem
            WHERE Id IN :quoteLineItemIds
          ]
        );

    for (OrderItem item : items) {
      String displayNumber = resolveQuoteDisplayNumber(
        item,
        quoteLineItemsById,
        hasSalesforceQuoteLineId
      );
      if (String.isNotBlank(displayNumber)) {
        quoteNumberByOrderItemId.put(item.Id, displayNumber);
      }
    }

    return quoteNumberByOrderItemId;
  }

  private static String resolveQuoteDisplayNumber(
    OrderItem item,
    Map<Id, QuoteLineItem> quoteLineItemsById,
    Boolean hasSalesforceQuoteLineId
  ) {
    if (item.QuoteLineItem != null) {
      if (String.isNotBlank(item.QuoteLineItem.Quote.Ansa_Quote_Number__c)) {
        return item.QuoteLineItem.Quote.Ansa_Quote_Number__c;
      }
      if (String.isNotBlank(item.QuoteLineItem.Quote.QuoteNumber)) {
        return item.QuoteLineItem.Quote.QuoteNumber;
      }
    }

    Id lineItemId = item.QuoteLineItemId;
    if (lineItemId == null && hasSalesforceQuoteLineId) {
      String rawLineId = (String) item.get('Salesforce_Quote_Line_ID__c');
      if (String.isNotBlank(rawLineId)) {
        try {
          lineItemId = Id.valueOf(rawLineId.trim());
        } catch (Exception e) {
          return null;
        }
      }
    }

    if (lineItemId == null || !quoteLineItemsById.containsKey(lineItemId)) {
      return null;
    }

    QuoteLineItem lineItem = quoteLineItemsById.get(lineItemId);
    if (String.isNotBlank(lineItem.Quote.Ansa_Quote_Number__c)) {
      return lineItem.Quote.Ansa_Quote_Number__c;
    }
    return lineItem.Quote.QuoteNumber;
  }

  private static Id resolvePromoCodeLookupId(String promoCode) {
    Promo_Code__c match = findPromoCodeRecord(promoCode);
    if (match == null || promoApplyEligibilityMessage(match) != null) {
      return null;
    }
    return match.Id;
  }

  /**
   * Dollar discount checkout should show on Apply. Does not write the promo.
   * Free Sequence and Discount Percent follow the Quote Request - Promo Code flow.
   * A blank Discount Type stays a flat percent, which is how existing codes behave.
   */
  @TestVisible
  private static Map<String, Object> previewCheckoutPromoDiscount(
    Promo_Code__c promo,
    List<ABT_Quote_Request__c> quoteRequests
  ) {
    Map<String, Object> preview = new Map<String, Object>();
    List<Map<String, Object>> quoteDiscounts = new List<Map<String, Object>>();
    preview.put('quoteDiscounts', quoteDiscounts);
    if (promo == null || quoteRequests == null || quoteRequests.isEmpty()) {
      return preview;
    }

    Boolean freeSequence = promo.Discount_Type__c == PROMO_TYPE_FREE_SEQUENCE;
    Boolean discountPercent =
      promo.Discount_Type__c == PROMO_TYPE_DISCOUNT_PERCENT;
    if (!freeSequence) {
      preview.put('discountPercentage', promo.Discount_Percentage__c);
    }

    Set<Id> quoteIds = new Set<Id>();
    for (ABT_Quote_Request__c quoteRequest : quoteRequests) {
      if (quoteRequest.ABT_Quote__c != null) {
        quoteIds.add(quoteRequest.ABT_Quote__c);
      }
    }

    Map<Id, List<QuoteLineItem>> linesByQuote = new Map<Id, List<QuoteLineItem>>();
    if (!quoteIds.isEmpty()) {
      for (QuoteLineItem lineItem : [
        SELECT
          Id,
          QuoteId,
          UnitPrice,
          Quantity,
          TotalPrice,
          Total_Combined_Price__c,
          Was_Deleted__c,
          Sequence_Classification_RS__c,
          Product_Family__c,
          Parent_Line_Item__c
        FROM QuoteLineItem
        WHERE QuoteId IN :quoteIds
      ]) {
        if (!linesByQuote.containsKey(lineItem.QuoteId)) {
          linesByQuote.put(lineItem.QuoteId, new List<QuoteLineItem>());
        }
        linesByQuote.get(lineItem.QuoteId).add(lineItem);
      }
    }

    Decimal totalDiscount = 0;
    Boolean pricedAQuote = false;
    for (ABT_Quote_Request__c quoteRequest : quoteRequests) {
      List<QuoteLineItem> lines = quoteRequest.ABT_Quote__c == null
        ? new List<QuoteLineItem>()
        : linesByQuote.get(quoteRequest.ABT_Quote__c);
      if (lines == null) {
        lines = new List<QuoteLineItem>();
      }
      Decimal quoteDiscount = freeSequence
        ? freeSequenceDiscount(promo, lines)
        : percentPromoDiscount(promo, quoteRequest, lines, discountPercent);
      if (quoteDiscount == null) {
        continue;
      }
      quoteDiscount = quoteDiscount.setScale(2, RoundingMode.HALF_UP);
      pricedAQuote = true;
      totalDiscount += quoteDiscount;
      quoteDiscounts.add(
        new Map<String, Object>{
          'quoteRequestId' => quoteRequest.Id,
          'discountAmount' => quoteDiscount
        }
      );
    }
    if (pricedAQuote) {
      preview.put(
        'discountAmount',
        totalDiscount.setScale(2, RoundingMode.HALF_UP)
      );
    }
    return preview;
  }

  @TestVisible
  private static Decimal percentPromoDiscount(
    Promo_Code__c promo,
    ABT_Quote_Request__c quoteRequest,
    List<QuoteLineItem> lines,
    Boolean applyDollarCap
  ) {
    Decimal base = 0;
    for (QuoteLineItem lineItem : lines) {
      if (lineItem.Was_Deleted__c == true) {
        continue;
      }
      base += promoLineSalesAmount(lineItem);
    }
    if (
      base <= 0 &&
      quoteRequest.ABT_Total_Price__c != null &&
      quoteRequest.ABT_Total_Price__c > 0
    ) {
      base = quoteRequest.ABT_Total_Price__c;
    } else if (
      base <= 0 &&
      quoteRequest.ABT_Quote__r != null &&
      quoteRequest.ABT_Quote__r.Subtotal != null &&
      quoteRequest.ABT_Quote__r.Subtotal > 0
    ) {
      base = quoteRequest.ABT_Quote__r.Subtotal;
    }
    if (base <= 0) {
      return null;
    }
    Decimal percent = promo.Discount_Percentage__c == null
      ? 0
      : promo.Discount_Percentage__c;
    Decimal dollars = (base * percent / 100).setScale(2, RoundingMode.HALF_UP);
    Decimal limitAmount = promo.Discount_Dollar_Limit__c;
    if (
      applyDollarCap &&
      limitAmount != null &&
      limitAmount > 0 &&
      dollars > limitAmount
    ) {
      return limitAmount;
    }
    return dollars;
  }

  @TestVisible
  private static Decimal freeSequenceDiscount(
    Promo_Code__c promo,
    List<QuoteLineItem> lines
  ) {
    List<QuoteLineItem> candidates = new List<QuoteLineItem>();
    for (QuoteLineItem lineItem : lines) {
      if (isPromoSequenceCandidate(lineItem)) {
        candidates.add(lineItem);
      }
    }
    if (candidates.isEmpty()) {
      return 0;
    }

    Decimal limitAmount = promo.Discount_Dollar_Limit__c;
    Boolean hasLimit = limitAmount != null && limitAmount > 0;
    if (!hasLimit) {
      return zeroedSequenceDiscount(mostExpensivePromoLine(candidates), lines);
    }

    List<QuoteLineItem> underLimit = new List<QuoteLineItem>();
    for (QuoteLineItem lineItem : candidates) {
      if (
        lineItem.Total_Combined_Price__c != null &&
        lineItem.Total_Combined_Price__c <= limitAmount
      ) {
        underLimit.add(lineItem);
      }
    }
    if (!underLimit.isEmpty()) {
      return zeroedSequenceDiscount(mostExpensivePromoLine(underLimit), lines);
    }

    QuoteLineItem chosen = mostExpensivePromoLine(candidates);
    Decimal unitPrice = chosen.UnitPrice == null ? 0 : chosen.UnitPrice;
    Decimal quantity = chosen.Quantity == null ||
      chosen.Quantity == 0
      ? 1
      : chosen.Quantity;
    Decimal reduction = limitAmount > unitPrice ? unitPrice : limitAmount;
    if (reduction < 0) {
      reduction = 0;
    }
    return reduction * quantity;
  }

  private static Decimal zeroedSequenceDiscount(
    QuoteLineItem chosen,
    List<QuoteLineItem> lines
  ) {
    Decimal amount = promoLineSalesAmount(chosen);
    for (QuoteLineItem lineItem : lines) {
      if (
        lineItem.Id != chosen.Id &&
        lineItem.Parent_Line_Item__c == chosen.Id &&
        lineItem.Was_Deleted__c != true
      ) {
        amount += promoLineSalesAmount(lineItem);
      }
    }
    return amount;
  }

  private static Boolean isPromoSequenceCandidate(QuoteLineItem lineItem) {
    if (lineItem == null || lineItem.Was_Deleted__c == true) {
      return false;
    }
    if (lineItem.Sequence_Classification_RS__c == 'Not Currently Possible') {
      return false;
    }
    return lineItem.Product_Family__c != 'Services';
  }

  private static QuoteLineItem mostExpensivePromoLine(
    List<QuoteLineItem> lines
  ) {
    QuoteLineItem best;
    for (QuoteLineItem lineItem : lines) {
      if (best == null || promoUnitPrice(lineItem) > promoUnitPrice(best)) {
        best = lineItem;
      }
    }
    return best;
  }

  private static Decimal promoUnitPrice(QuoteLineItem lineItem) {
    return lineItem.UnitPrice == null ? 0 : lineItem.UnitPrice;
  }

  private static Decimal promoLineSalesAmount(QuoteLineItem lineItem) {
    if (lineItem == null || lineItem.Was_Deleted__c == true) {
      return 0;
    }
    if (lineItem.TotalPrice != null && lineItem.TotalPrice > 0) {
      return lineItem.TotalPrice;
    }
    Decimal unitPrice = lineItem.UnitPrice == null ? 0 : lineItem.UnitPrice;
    Decimal quantity = lineItem.Quantity == null ||
      lineItem.Quantity == 0
      ? 1
      : lineItem.Quantity;
    return unitPrice > 0 ? unitPrice * quantity : 0;
  }

  /**
   * Resolve a typed checkout/quote promo by Salesforce Id, Name, or customer-facing Promo_Code__c (ANSA-…).
   */
  private static Promo_Code__c findPromoCodeRecord(String promoCode) {
    if (String.isBlank(promoCode)) {
      return null;
    }

    String code = promoCode.trim();
    List<Promo_Code__c> matches;
    try {
      Id promoId = Id.valueOf(code);
      matches = [
        SELECT
          Id,
          Name,
          Discount_Percentage__c,
          Discount_Type__c,
          Discount_Dollar_Limit__c,
          Status__c,
          Valid_To__c,
          Promo_Code__c,
          Related_Contact__c
        FROM Promo_Code__c
        WHERE Id = :promoId OR Name = :code OR Promo_Code__c = :code
        LIMIT 1
      ];
    } catch (Exception e) {
      matches = [
        SELECT
          Id,
          Name,
          Discount_Percentage__c,
          Discount_Type__c,
          Discount_Dollar_Limit__c,
          Status__c,
          Valid_To__c,
          Promo_Code__c,
          Related_Contact__c
        FROM Promo_Code__c
        WHERE Name = :code OR Promo_Code__c = :code
        LIMIT 1
      ];
    }
    return matches.isEmpty() ? null : matches[0];
  }

  private static final String PROMO_TYPE_FREE_SEQUENCE = 'Free Sequence';
  private static final String PROMO_TYPE_DISCOUNT_PERCENT = 'Discount Percent';
  private static final String VOLUME_PROMO_NAME = 'VOLUME10';
  private static final String PROMO_NOT_FOR_ACCOUNT = 'This promo code isn\'t valid for your account. If you need help, contact customerservice@ansabio.com.';
  private static final String PROMO_APPLY_FAILED = 'Unable to apply this promo code. Please try again or contact customerservice@ansabio.com.';

  private static String promoApplyEligibilityMessage(Promo_Code__c promo) {
    if (promo == null) {
      return 'Invalid or expired promo code';
    }
    if (promo.Name == VOLUME_PROMO_NAME) {
      return null;
    }
    if (
      promo.Status__c == 'Expired' ||
      (promo.Valid_To__c != null &&
      promo.Valid_To__c < Date.today())
    ) {
      return 'This promo code has expired.';
    }
    if (promo.Status__c == 'Ordered') {
      return 'This promo code has already been used.';
    }
    Id userContactId = currentUserContactId();
    if (userContactId != null && promo.Related_Contact__c != userContactId) {
      return PROMO_NOT_FOR_ACCOUNT;
    }
    return null;
  }

  private static Id currentUserContactId() {
    List<User> users = [
      SELECT ContactId
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];
    return users.isEmpty() ? null : users[0].ContactId;
  }

  private static String toFriendlyPromoApplyMessage(Exception e) {
    String raw = e == null ? '' : String.valueOf(e.getMessage());
    if (String.isBlank(raw)) {
      return PROMO_APPLY_FAILED;
    }
    if (raw.contains('FIELD_FILTER_VALIDATION_EXCEPTION')) {
      return PROMO_NOT_FOR_ACCOUNT;
    }
    String lower = raw.toLowerCase();
    if (
      lower.contains('update failed') ||
      lower.contains('exception on row') ||
      lower.contains('first error:')
    ) {
      return PROMO_APPLY_FAILED;
    }
    return raw;
  }

  private static void applyContactPointAddressesToOrder(
    Order ord,
    String billingAddressId,
    String shippingAddressId
  ) {
    Set<Id> addrIds = new Set<Id>();
    Id billingId = null;
    Id shippingId = null;
    try {
      if (String.isNotBlank(billingAddressId)) {
        billingId = Id.valueOf(billingAddressId);
        addrIds.add(billingId);
      }
    } catch (Exception e) {
    }
    try {
      if (String.isNotBlank(shippingAddressId)) {
        shippingId = Id.valueOf(shippingAddressId);
        addrIds.add(shippingId);
      }
    } catch (Exception e) {
    }

    if (addrIds.isEmpty()) {
      return;
    }

    Map<Id, ContactPointAddress> byId = new Map<Id, ContactPointAddress>(
      [
        SELECT Id, Street, City, State, PostalCode, Country, Address
        FROM ContactPointAddress
        WHERE Id IN :addrIds
      ]
    );

    if (billingId != null && byId.containsKey(billingId)) {
      copyContactPointAddressToOrderBilling(ord, byId.get(billingId));
    }
    if (shippingId != null && byId.containsKey(shippingId)) {
      copyContactPointAddressToOrderShipping(ord, byId.get(shippingId));
    }
  }

  /**
   * Contact.Invoice_Email__c is Text and can hold spaces (e.g. "AP.NJ. Invoice@azenta.com").
   * Order.Invoice_Email__c is Email and rejects those values, which failed portal checkout.
   */
  @TestVisible
  private static String sanitizeCheckoutInvoiceEmail(String raw) {
    if (String.isBlank(raw)) {
      return null;
    }
    String cleaned = raw.trim().replaceAll('\\s+', '');
    if (String.isBlank(cleaned)) {
      return null;
    }
    Integer atIndex = cleaned.indexOf('@');
    if (atIndex <= 0 || atIndex == cleaned.length() - 1) {
      return null;
    }
    String domain = cleaned.substring(atIndex + 1);
    if (!domain.contains('.')) {
      return null;
    }
    return cleaned;
  }

  @TestVisible
  private static String resolveCheckoutInvoiceEmail(Id contactId) {
    if (contactId == null) {
      return null;
    }
    List<Contact> contacts = [
      SELECT Invoice_Email__c
      FROM Contact
      WHERE Id = :contactId
      LIMIT 1
    ];
    if (contacts.isEmpty() || String.isBlank(contacts[0].Invoice_Email__c)) {
      return null;
    }
    return sanitizeCheckoutInvoiceEmail(contacts[0].Invoice_Email__c);
  }

  @TestVisible
  private static void applyPortalCheckoutFields(
    Order ord,
    String projectName,
    String shippingMethod,
    Boolean isExpedite,
    String packagingType,
    String poNumber,
    String billingAddressId,
    String shippingAddressId,
    String paymentMethod,
    String notes,
    String promoCode,
    Boolean isTaxExempt,
    Boolean isPartialShipment,
    Id blanketPurchaseOrderId,
    String stripePaymentMethodId
  ) {
    Map<String, Schema.SObjectField> orderFieldMap = Schema.SObjectType.Order.fields.getMap();
    final Decimal DEFAULT_SHIPPING_FEE = 60.00;

    putOrderFieldIfPresent(
      ord,
      orderFieldMap,
      'Customer_Project_Name__c',
      projectName
    );
    putOrderFieldIfPresent(
      ord,
      orderFieldMap,
      'Purchase_Order_Number__c',
      poNumber
    );
    putOrderFieldIfPresent(
      ord,
      orderFieldMap,
      'Blanket_Purchase_Order__c',
      blanketPurchaseOrderId
    );
    putOrderFieldIfPresent(
      ord,
      orderFieldMap,
      'ABT_Stripe_Payment_Method_Id__c',
      stripePaymentMethodId
    );
    putOrderFieldIfPresent(
      ord,
      orderFieldMap,
      'Ship_Method__c',
      mapPortalShipMethod(shippingMethod)
    );
    putOrderFieldIfPresent(
      ord,
      orderFieldMap,
      'Payment_Method__c',
      mapPortalPaymentMethod(paymentMethod)
    );
    putOrderFieldIfPresent(
      ord,
      orderFieldMap,
      'Customer_Notes_New__c',
      String.isNotBlank(notes) ? notes.trim() : null
    );
    putOrderFieldIfPresent(
      ord,
      orderFieldMap,
      'Promo_Code__c',
      resolvePromoCodeLookupId(promoCode)
    );
    putOrderFieldIfPresent(ord, orderFieldMap, 'Is_Expedite__c', isExpedite);
    putOrderFieldIfPresent(
      ord,
      orderFieldMap,
      'Requested_Packaging__c',
      resolvePackagingPicklistValue(packagingType)
    );
    putOrderFieldIfPresent(
      ord,
      orderFieldMap,
      'Accept_Partial_Shipment__c',
      isPartialShipment == true
    );
    putOrderFieldIfPresent(
      ord,
      orderFieldMap,
      'Tax_Exempt__c',
      isTaxExempt == true
    );
    putOrderFieldIfPresent(
      ord,
      orderFieldMap,
      'Shipping_charges__c',
      DEFAULT_SHIPPING_FEE
    );

    applyContactPointAddressesToOrder(ord, billingAddressId, shippingAddressId);
  }

  @TestVisible
  private static Decimal discountDollarsFromPercent(
    Decimal discountedSubtotal,
    Decimal percent
  ) {
    if (
      discountedSubtotal == null ||
      discountedSubtotal <= 0 ||
      percent == null ||
      percent <= 0 ||
      percent >= 100
    ) {
      return 0;
    }
    Decimal original = discountedSubtotal / (1 - (percent / 100));
    return (original - discountedSubtotal).setScale(2);
  }

  @TestVisible
  private static Decimal resolveOrderDiscountAmount(
    List<Quote> quotes,
    Decimal discountedSubtotal
  ) {
    Decimal rolledUp = 0;
    Decimal percent = null;
    if (quotes != null) {
      for (Quote q : quotes) {
        if (q == null) {
          continue;
        }
        if (q.Discount_Amount__c != null && q.Discount_Amount__c > 0) {
          rolledUp += q.Discount_Amount__c;
        }
        Decimal quotePercent = q.Discount__c;
        if (quotePercent != null && quotePercent > 0) {
          percent = percent == null ? quotePercent : percent;
        }
      }
    }
    if (rolledUp > 0) {
      return rolledUp.setScale(2);
    }
    return discountDollarsFromPercent(discountedSubtotal, percent);
  }

  private static Decimal resolveStoredOrQuoteDiscount(
    Order o,
    Decimal lineSubtotal
  ) {
    if (o != null && o.Discount__c != null && o.Discount__c > 0) {
      return o.Discount__c;
    }
    List<Quote> quotes = (o != null &&
      o.Quote != null)
      ? new List<Quote>{ o.Quote }
      : new List<Quote>();
    Decimal fromQuote = resolveOrderDiscountAmount(quotes, lineSubtotal);
    if (fromQuote != null && fromQuote > 0) {
      return fromQuote;
    }
    Decimal promoPercent = (o != null &&
      o.Promo_Code__r != null)
      ? o.Promo_Code__r.Discount_Percentage__c
      : null;
    return discountDollarsFromPercent(lineSubtotal, promoPercent);
  }

  @TestVisible
  private static void stampOrderDiscountFromQuotes(
    Id orderId,
    List<Quote> quotes
  ) {
    if (orderId == null) {
      return;
    }
    Decimal discountedSubtotal = 0;
    for (OrderItem oi : [
      SELECT UnitPrice, Quantity
      FROM OrderItem
      WHERE OrderId = :orderId
    ]) {
      Decimal qty = oi.Quantity == null ? 1 : oi.Quantity;
      Decimal price = oi.UnitPrice == null ? 0 : oi.UnitPrice;
      discountedSubtotal += price * qty;
    }
    Decimal amount = resolveOrderDiscountAmount(quotes, discountedSubtotal);
    if (amount == null || amount <= 0) {
      return;
    }
    Map<String, Schema.SObjectField> orderFieldMap = Schema.SObjectType.Order.fields.getMap();
    Order ord = new Order(Id = orderId);
    putOrderFieldIfPresent(ord, orderFieldMap, 'Discount__c', amount);
    update ord;
  }

  /**
   * Copies Quote.X3rd_Party_Shipping_Account__c onto Order.Third_Party_Shipping_Account__c
   * and forces Shipping_charges__c to $0 when a third-party account is present.
   * Prefers the primary quote (first in list), then any other non-blank quote value.
   */
  @TestVisible
  private static Boolean applyThirdPartyShippingFromQuotes(
    Order ord,
    List<Quote> quotes
  ) {
    if (ord == null || quotes == null || quotes.isEmpty()) {
      return false;
    }
    String thirdPartyAccount = null;
    for (Quote q : quotes) {
      if (q != null && String.isNotBlank(q.X3rd_Party_Shipping_Account__c)) {
        thirdPartyAccount = q.X3rd_Party_Shipping_Account__c.trim();
        break;
      }
    }
    if (String.isBlank(thirdPartyAccount)) {
      return false;
    }
    Map<String, Schema.SObjectField> orderFieldMap = Schema.SObjectType.Order.fields.getMap();
    putOrderFieldIfPresent(
      ord,
      orderFieldMap,
      'Third_Party_Shipping_Account__c',
      thirdPartyAccount
    );
    putOrderFieldIfPresent(ord, orderFieldMap, 'Shipping_charges__c', 0);
    return true;
  }

  @TestVisible
  private static void persistOrderAddressesAfterInsert(
    Id orderId,
    String billingAddressId,
    String shippingAddressId
  ) {
    if (orderId == null) {
      return;
    }
    if (String.isBlank(billingAddressId) && String.isBlank(shippingAddressId)) {
      return;
    }
    Order upd = new Order(Id = orderId);
    applyContactPointAddressesToOrder(upd, billingAddressId, shippingAddressId);
    update upd;
  }

  @TestVisible
  private static String resolveCartProjectName(
    List<Quote> quotes,
    List<Id> quoteIds
  ) {
    Set<String> names = new Set<String>();
    Map<Id, String> titleByQuoteId = loadProjectTitleByQuoteId(
      new Set<Id>(quoteIds)
    );
    for (Id qId : quoteIds) {
      if (titleByQuoteId.containsKey(qId)) {
        names.add(titleByQuoteId.get(qId));
      }
    }
    return names.isEmpty() ? null : String.join(new List<String>(names), ', ');
  }

  @TestVisible
  private static String resolveQuoteIncoTerms(Id quoteId) {
    if (quoteId == null) {
      return 'FCA';
    }
    List<Quote> rows = [
      SELECT Incoterms__c
      FROM Quote
      WHERE Id = :quoteId
      LIMIT 1
    ];
    if (!rows.isEmpty() && String.isNotBlank(rows[0].Incoterms__c)) {
      return rows[0].Incoterms__c;
    }
    return 'FCA';
  }

  @TestVisible
  private static String resolveSingleQuoteProjectName(
    Quote quote,
    Id quoteRequestId
  ) {
    if (quoteRequestId != null) {
      List<ABT_Quote_Request__c> reqs = [
        SELECT ABT_Customer_Project_Name__c, Project__r.Name
        FROM ABT_Quote_Request__c
        WHERE Id = :quoteRequestId
        LIMIT 1
      ];
      if (!reqs.isEmpty()) {
        String title = projectTitleFromQuoteRequest(reqs[0]);
        if (String.isNotBlank(title)) {
          return title;
        }
      }
    }
    if (quote != null && quote.Id != null) {
      Map<Id, String> titleByQuoteId = loadProjectTitleByQuoteId(
        new Set<Id>{ quote.Id }
      );
      if (titleByQuoteId.containsKey(quote.Id)) {
        return titleByQuoteId.get(quote.Id);
      }
    }
    return null;
  }

  /**
   * Place a single Order from ALL quotes in the cart (multi-quote checkout).
   * Launches the cart checkout flow, which creates one Order from all quotes
   * in the active cart and returns the created Order Id.
   */
  @AuraEnabled
  public static String placeOrderForCart(
    String quoteIdsJson,
    String shippingMethod,
    Boolean isExpedite,
    String packagingType,
    String poNumber,
    String billingAddressId,
    String shippingAddressId,
    String paymentMethod,
    String notes,
    String promoCode,
    Boolean isTaxExempt,
    Boolean isPartialShipment,
    String bpoId,
    String paymentMethodRecordId
  ) {
    List<String> quoteIds = String.isBlank(quoteIdsJson)
      ? new List<String>()
      : (List<String>) JSON.deserialize(quoteIdsJson, List<String>.class);
    if (quoteIds.isEmpty()) {
      throw checkoutAura('No quotes provided for checkout.');
    }

    Id currentContactId = getCurrentUserContactId();
    if (currentContactId == null) {
      throw checkoutAura(
        'You do not have permission to checkout these quotes.'
      );
    }

    Id currentAccountId = null;
    List<User> users = [
      SELECT AccountId, Contact.AccountId
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];
    if (!users.isEmpty()) {
      currentAccountId = users[0].AccountId;
      if (currentAccountId == null && users[0].Contact != null) {
        currentAccountId = users[0].Contact.AccountId;
      }
    }

    Id cartId = null;
    List<WebCart> carts = [
      SELECT Id
      FROM WebCart
      WHERE
        OwnerId = :UserInfo.getUserId()
        AND AccountId = :currentAccountId
        AND Status IN ('Active', 'Checkout')
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
    if (!carts.isEmpty()) {
      cartId = carts[0].Id;
    }

    Map<String, Object> flowInputs = new Map<String, Object>{
      'cartId' => toFlowStringId(cartId),
      'quoteIds' => quoteIds,
      'accountId' => toFlowStringId(currentAccountId),
      'contactId' => toFlowStringId(currentContactId),
      'billingAddressId' => billingAddressId,
      'shippingAddressId' => shippingAddressId,
      'shippingMethod' => shippingMethod,
      'isExpedite' => isExpedite,
      'packagingType' => packagingType,
      'paymentMethod' => paymentMethod,
      'poNumber' => poNumber,
      'bpoId' => bpoId,
      'paymentMethodRecordId' => paymentMethodRecordId,
      'promoCode' => promoCode,
      'isTaxExempt' => isTaxExempt,
      'isPartialShipment' => isPartialShipment,
      'notes' => notes
    };

    try {
      Flow.Interview flowInterview = Flow.Interview.createInterview(
        'Order_Create_From_Cart',
        flowInputs
      );
      flowInterview.start();
      Object createdOrderId = flowInterview.getVariableValue('createdOrderId');
      Object checkoutErrorMessage = flowInterview.getVariableValue(
        'checkoutErrorMessage'
      );
      if (
        checkoutErrorMessage != null &&
        String.isNotBlank(String.valueOf(checkoutErrorMessage))
      ) {
        if (isInvalidCheckoutIdError(String.valueOf(checkoutErrorMessage))) {
          return executeCartCheckout(
            quoteIdsJson,
            shippingMethod,
            isExpedite,
            packagingType,
            poNumber,
            billingAddressId,
            shippingAddressId,
            paymentMethod,
            notes,
            promoCode,
            isTaxExempt,
            isPartialShipment,
            bpoId,
            paymentMethodRecordId
          );
        }
        throw checkoutUnexpected(
          String.valueOf(checkoutErrorMessage),
          toQuoteIds(quoteIds)
        );
      }
      if (
        createdOrderId == null || String.isBlank(String.valueOf(createdOrderId))
      ) {
        throw checkoutUnexpected(
          'Cart checkout flow did not return an order id.',
          toQuoteIds(quoteIds)
        );
      }
      return String.valueOf(createdOrderId);
    } catch (AuraHandledException e) {
      if (!isInvalidCheckoutIdError(checkoutExceptionMessage(e))) {
        throw checkoutUnexpected(e, toQuoteIds(quoteIds));
      }
    } catch (Exception e) {
      // Blank Flow String -> Id invocable used to abort here with "Invalid ID"
      // before executeCartCheckout ran. Retry directly when that happens.
      if (!isInvalidCheckoutIdError(checkoutExceptionMessage(e))) {
        throw checkoutUnexpected(e, toQuoteIds(quoteIds));
      }
    }
    return executeCartCheckout(
      quoteIdsJson,
      shippingMethod,
      isExpedite,
      packagingType,
      poNumber,
      billingAddressId,
      shippingAddressId,
      paymentMethod,
      notes,
      promoCode,
      isTaxExempt,
      isPartialShipment,
      bpoId,
      paymentMethodRecordId
    );
  }

  @TestVisible
  private static String toFlowStringId(Id value) {
    return value == null ? null : String.valueOf(value);
  }

  /** Shared by placeOrderForCart and the Flow invocable. Creates the Order from selected cart quotes. */
  public static String executeCartCheckout(
    String quoteIdsJson,
    String shippingMethod,
    Boolean isExpedite,
    String packagingType,
    String poNumber,
    String billingAddressId,
    String shippingAddressId,
    String paymentMethod,
    String notes,
    String promoCode,
    Boolean isTaxExempt,
    Boolean isPartialShipment,
    String bpoId,
    String paymentMethodRecordId
  ) {
    List<String> rawIds = String.isBlank(quoteIdsJson)
      ? new List<String>()
      : (List<String>) JSON.deserialize(quoteIdsJson, List<String>.class);
    if (rawIds.isEmpty()) {
      throw checkoutAura('No quotes provided for checkout.');
    }
    List<Id> requestedOrder = new List<Id>();
    for (String s : rawIds) {
      if (String.isBlank(s)) {
        continue;
      }
      try {
        requestedOrder.add(Id.valueOf(s));
      } catch (Exception e) {
        throw checkoutAura(
          'One or more selected quotes are no longer in the active cart. Please refresh /my-cart and try again.'
        );
      }
    }

    List<Id> quoteIds = ABT_Cart_Service.getOrderedPortalCommerceCartQuoteIds(
      requestedOrder
    );
    if (quoteIds.size() != new Set<Id>(requestedOrder).size()) {
      throw checkoutAura(
        'One or more selected quotes are no longer in the active cart. Please refresh /my-cart and try again.'
      );
    }
    if (quoteIds.isEmpty()) {
      throw checkoutAura(
        'Your active cart is empty. Please return to /my-cart and try again.'
      );
    }

    List<Quote> quotes = [
      SELECT
        Id,
        Status,
        ContactId,
        OpportunityId,
        Pricebook2Id,
        ShippingHandling,
        X3rd_Party_Shipping_Account__c,
        Discount__c,
        Discount_Amount__c,
        Opportunity.Name,
        Opportunity.AccountId,
        Opportunity.ContactId
      FROM Quote
      WHERE Id IN :quoteIds
    ];
    if (quotes.isEmpty()) {
      throw checkoutAura('No valid quotes found for checkout.');
    }
    if (quotes.size() != quoteIds.size()) {
      throw checkoutAura(
        'One or more cart quotes are no longer available for checkout. Please refresh /my-cart and try again.'
      );
    }

    Map<Id, Quote> quotesById = new Map<Id, Quote>();
    for (Quote q : quotes) {
      quotesById.put(q.Id, q);
    }
    // Preserve cart order: first id in quoteIdsJson is the primary quote on the Order.
    Quote primary = null;
    Set<Id> verifiedQuoteIds = new Set<Id>();
    List<Quote> quotesInCartOrder = new List<Quote>();
    for (Id qId : quoteIds) {
      if (quotesById.containsKey(qId)) {
        Quote candidate = quotesById.get(qId);
        if (primary == null) {
          primary = candidate;
        }
        verifiedQuoteIds.add(candidate.Id);
        quotesInCartOrder.add(candidate);
      }
    }
    if (primary == null) {
      primary = quotes[0];
      quotesInCartOrder = quotes;
    }
    if (verifiedQuoteIds.size() != quoteIds.size()) {
      throw checkoutAura(
        'One or more cart quotes are missing from the checkout set. Please refresh /my-cart and try again.'
      );
    }

    List<User> users = [
      SELECT ContactId
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];
    Id currentContactId = users.isEmpty() ? null : users[0].ContactId;
    if (currentContactId == null) {
      throw checkoutAura(
        'You do not have permission to checkout these quotes.'
      );
    }
    for (Quote q : quotes) {
      Boolean isOwner =
        currentContactId == q.ContactId ||
        currentContactId == q.Opportunity.ContactId;
      if (!isOwner) {
        throw checkoutAura(
          'You do not have permission to checkout these quotes.'
        );
      }
    }

    final Decimal DEFAULT_SHIPPING_FEE = 60.00;
    final Decimal DEFAULT_PACKAGING_FEE = 55.00;

    Savepoint sp = Database.setSavepoint();
    try {
      persistCheckoutPromoToQuotes(checkoutPromoQuoteIds(quoteIds), promoCode);
      quotes = [
        SELECT
          Id,
          Status,
          ContactId,
          OpportunityId,
          Pricebook2Id,
          ShippingHandling,
          X3rd_Party_Shipping_Account__c,
          Discount__c,
          Discount_Amount__c,
          Opportunity.Name,
          Opportunity.AccountId,
          Opportunity.ContactId
        FROM Quote
        WHERE Id IN :quoteIds
      ];
      quotesById = new Map<Id, Quote>(quotes);
      quotesInCartOrder = new List<Quote>();
      primary = null;
      for (Id qId : quoteIds) {
        if (quotesById.containsKey(qId)) {
          Quote refreshed = quotesById.get(qId);
          if (primary == null) {
            primary = refreshed;
          }
          quotesInCartOrder.add(refreshed);
        }
      }
      if (primary == null && !quotes.isEmpty()) {
        primary = quotes[0];
        quotesInCartOrder = quotes;
      }

      String cartProjectName = resolveCartProjectName(quotes, quoteIds);
      Id accountId = primary.Opportunity.AccountId;
      Id contactId = getCurrentUserContactId();
      validatePortalCreditCardCheckout(paymentMethod, paymentMethodRecordId);
      Id blanketPurchaseOrderId = resolveCheckoutBlanketPurchaseOrderId(
        paymentMethod,
        accountId,
        bpoId,
        poNumber
      );
      String resolvedPoNumber = resolveCheckoutPoNumber(
        paymentMethod,
        poNumber,
        blanketPurchaseOrderId
      );
      String stripePaymentMethodId = resolveCheckoutStripePaymentMethodId(
        paymentMethod,
        contactId,
        paymentMethodRecordId
      );
      Decimal maxCartShippingAmount = 0;
      for (Quote q : quotes) {
        Decimal quoteShipping = q.ShippingHandling != null
          ? q.ShippingHandling
          : 0;
        if (quoteShipping > maxCartShippingAmount) {
          maxCartShippingAmount = quoteShipping;
        }
      }

      Order newOrder = new Order(
        AccountId = accountId,
        OpportunityId = primary.OpportunityId,
        QuoteId = primary.Id,
        Pricebook2Id = primary.Pricebook2Id,
        EffectiveDate = Date.today(),
        Status = 'Draft'
      );

      applyPortalCheckoutFields(
        newOrder,
        cartProjectName,
        shippingMethod,
        isExpedite,
        packagingType,
        resolvedPoNumber,
        billingAddressId,
        shippingAddressId,
        paymentMethod,
        notes,
        promoCode,
        isTaxExempt,
        isPartialShipment,
        blanketPurchaseOrderId,
        stripePaymentMethodId
      );
      Boolean hasThirdPartyShipping = applyThirdPartyShippingFromQuotes(
        newOrder,
        quotesInCartOrder
      );
      // Prefer Contact invoice email from checkout; flow only fills from Account when blank.
      putOrderFieldIfPresent(
        newOrder,
        Schema.SObjectType.Order.fields.getMap(),
        'Invoice_Email__c',
        resolveCheckoutInvoiceEmail(contactId)
      );
      if (
        !hasThirdPartyShipping &&
        quoteIds.size() > 1 &&
        maxCartShippingAmount > 0
      ) {
        Map<String, Schema.SObjectField> orderFieldMap = Schema.SObjectType.Order.fields.getMap();
        putOrderFieldIfPresent(
          newOrder,
          orderFieldMap,
          'Shipping_charges__c',
          maxCartShippingAmount
        );
      }
      insert newOrder;
      persistOrderAddressesAfterInsert(
        newOrder.Id,
        billingAddressId,
        shippingAddressId
      );

      // ── Build OrderItems ─────────────────────────────────────────────────
      // Primary path: standard QuoteLineItems (Ansa staff has priced the quote).
      // Fallback path: ABT_Quote_Request_Lineitem__c (quote not yet priced in detail).
      List<QuoteLineItem> allQlis = Database.query(
        'SELECT ' +
          quoteLineItemPortalSelectClause() +
          ', Quote.Ansa_Quote_Number__c, Quote.QuoteNumber ' +
          'FROM QuoteLineItem WHERE QuoteId IN :quoteIds'
      );

      if (
        !findQuoteIdsWithOnlyNonOrderableLines(
            allQlis,
            quoteIds,
            accountId
          )
          .isEmpty()
      ) {
        throw checkoutAura(CHECKOUT_CART_NO_ORDERABLE_LINES_MESSAGE);
      }

      Set<Id> quotesWithAnyQlis = new Set<Id>();
      for (QuoteLineItem qli : allQlis) {
        if (qli != null && qli.QuoteId != null) {
          quotesWithAnyQlis.add(qli.QuoteId);
        }
      }
      allQlis = filterOrderableQuoteLineItems(allQlis, accountId);

      // Quotes that have NO standard QLIs → need fallback
      Set<Id> quotesWithoutQlis = new Set<Id>();
      for (Id qId : quoteIds) {
        if (!quotesWithAnyQlis.contains(qId))
          quotesWithoutQlis.add(qId);
      }

      List<OrderItem> items = new List<OrderItem>();

      // Pre-fetch PricebookEntry prices so we can fill in 0-priced QLIs
      Set<Id> pbeIds = new Set<Id>();
      for (QuoteLineItem qli : allQlis) {
        if (qli.PricebookEntryId != null)
          pbeIds.add(qli.PricebookEntryId);
      }
      Map<Id, Decimal> priceByPbeId = new Map<Id, Decimal>();
      if (!pbeIds.isEmpty()) {
        for (PricebookEntry pbe : [
          SELECT Id, UnitPrice
          FROM PricebookEntry
          WHERE Id IN :pbeIds
        ]) {
          priceByPbeId.put(pbe.Id, pbe.UnitPrice);
        }
      }

      // Add items from standard QLIs
      Boolean includeScaleUpField = !quoteLineItemsIncludeScaleUpChild(allQlis);
      Boolean includeGlycerolField = !quoteLineItemsIncludeGlycerolChild(
        allQlis
      );
      for (QuoteLineItem qli : allQlis) {
        Decimal fallback = priceByPbeId.containsKey(qli.PricebookEntryId)
          ? priceByPbeId.get(qli.PricebookEntryId)
          : 0;
        Decimal price = quoteLineItemOrderUnitPrice(
          qli,
          fallback,
          includeScaleUpField,
          includeGlycerolField
        );
        OrderItem oi = new OrderItem(
          OrderId = newOrder.Id,
          Product2Id = qli.Product2Id,
          Quantity = qli.Quantity,
          UnitPrice = price,
          PricebookEntryId = qli.PricebookEntryId,
          Description = qli.Description
        );
        copyQuoteLineItemToOrderItem(oi, qli, primary.Id);
        // SC-001 children already carry the fee — avoid baking Scale_Up_Price on parent.
        if (!includeScaleUpField) {
          clearOrderItemScaleUpPriceField(oi);
        }
        items.add(oi);
      }

      // Fallback: use ABT_Quote_Request_Lineitem__c for quotes without standard QLIs
      if (!quotesWithoutQlis.isEmpty()) {
        List<ABT_Quote_Request__c> linkedRequests = [
          SELECT Id, ABT_Quote__c, ABT_Product__c
          FROM ABT_Quote_Request__c
          WHERE ABT_Quote__c IN :quotesWithoutQlis
        ];

        if (!linkedRequests.isEmpty()) {
          Set<Id> reqIds = new Set<Id>();
          Map<Id, Id> productByReqId = new Map<Id, Id>();
          for (ABT_Quote_Request__c req : linkedRequests) {
            reqIds.add(req.Id);
            productByReqId.put(req.Id, req.ABT_Product__c);
          }

          Id pricebookId = primary.Pricebook2Id;
          if (pricebookId == null) {
            List<Pricebook2> stdPbs = [
              SELECT Id
              FROM Pricebook2
              WHERE IsStandard = TRUE AND IsActive = TRUE
              LIMIT 1
            ];
            if (!stdPbs.isEmpty())
              pricebookId = stdPbs[0].Id;
          }

          Set<Id> productIds = new Set<Id>(productByReqId.values());
          productIds.remove(null);

          Map<Id, PricebookEntry> pbeByProduct = new Map<Id, PricebookEntry>();
          if (pricebookId != null && !productIds.isEmpty()) {
            for (PricebookEntry pbe : [
              SELECT Id, Product2Id, UnitPrice
              FROM PricebookEntry
              WHERE
                Pricebook2Id = :pricebookId
                AND Product2Id IN :productIds
                AND IsActive = TRUE
            ]) {
              pbeByProduct.put(pbe.Product2Id, pbe);
            }
          }

          if (!pbeByProduct.isEmpty()) {
            if (newOrder.Pricebook2Id == null) {
              newOrder.Pricebook2Id = pricebookId;
              update newOrder;
            }

            Map<String, Schema.SObjectField> oiFields = Schema.SObjectType.OrderItem.fields.getMap();
            Boolean hasRelatedSequence = oiFields.containsKey(
              'related_sequence__c'
            );

            List<ABT_Quote_Request_Lineitem__c> reqLines = [
              SELECT
                Id,
                ABT_Quote_Request__c,
                Related_Sequence__c,
                Related_Sequence__r.Sequence_Name__c,
                Related_Sequence__r.Sequence__c
              FROM ABT_Quote_Request_Lineitem__c
              WHERE ABT_Quote_Request__c IN :reqIds
              ORDER BY CreatedDate ASC
            ];

            for (ABT_Quote_Request_Lineitem__c rl : reqLines) {
              Id productId = productByReqId.get(rl.ABT_Quote_Request__c);
              if (productId == null || !pbeByProduct.containsKey(productId))
                continue;
              PricebookEntry pbe = pbeByProduct.get(productId);
              OrderItem oi = new OrderItem(
                OrderId = newOrder.Id,
                Product2Id = productId,
                PricebookEntryId = pbe.Id,
                Quantity = 1,
                UnitPrice = pbe.UnitPrice
              );
              if (hasRelatedSequence && rl.Related_Sequence__c != null) {
                oi.put('Related_Sequence__c', rl.Related_Sequence__c);
              }
              items.add(oi);
            }
          }
        }
      }

      Boolean hasOrderItems = !items.isEmpty();
      if (!hasOrderItems) {
        throw checkoutAura(CHECKOUT_NO_ORDERABLE_LINES_MESSAGE);
      }
      insert items;

      stampOrderDiscountFromQuotes(newOrder.Id, quotesInCartOrder);

      updateQuotesAfterCartCheckout(quoteIds, newOrder.Id);

      // Quote-ordered automation copies Request_Packaging__c to Order; inactive values fail DML.
      sanitizeCartQuotePackaging(quoteIds);

      List<ABT_Quote_Request__c> quoteRequestsToReset = [
        SELECT Id, ABT_Order_Placed__c
        FROM ABT_Quote_Request__c
        WHERE ABT_Quote__c IN :quoteIds
      ];
      if (!quoteRequestsToReset.isEmpty()) {
        for (ABT_Quote_Request__c qr : quoteRequestsToReset) {
          qr.ABT_Order_Placed__c = true;
        }
        update quoteRequestsToReset;
      }

      try {
        ABT_Cart_Service.clearCheckedOutCartItems(new Set<Id>(quoteIds));
      } catch (AuraHandledException e) {
        // Keep checkout success even if the cart has already been cleared in another session.
      }

      // Must run after quote + quote-request updates. Quote-ordered automation and
      // ABT_Sync_Quote_Request_with_Quote can create per-quote orders for secondary quotes.
      cleanupPortalCartDuplicateOrders(newOrder.Id, primary.Id, quoteIds);

      return newOrder.Id;
    } catch (AuraHandledException ahe) {
      Database.rollback(sp);
      throw checkoutUnexpected(ahe, quoteIds);
    } catch (Exception e) {
      Database.rollback(sp);
      throw checkoutUnexpected(e, quoteIds);
    }
  }

  @TestVisible
  private static void updateQuotesAfterCartCheckout(
    List<Id> quoteIds,
    Id orderId
  ) {
    if (quoteIds == null || quoteIds.isEmpty() || orderId == null) {
      return;
    }

    Map<String, Schema.SObjectField> quoteFieldMap = Schema.SObjectType.Quote.fields.getMap();
    List<Quote> quotesToUpdate = new List<Quote>();
    for (Id qId : quoteIds) {
      Quote quoteUpdate = new Quote(Id = qId, Status = 'Ordered');
      if (quoteFieldMap.containsKey('Order__c')) {
        quoteUpdate.put('Order__c', orderId);
      }
      quotesToUpdate.add(quoteUpdate);
    }
    if (!quotesToUpdate.isEmpty()) {
      update quotesToUpdate;
    }
  }

  /** Single-quote checkout (older path). Cart checkout uses placeOrderForCart. */
  @AuraEnabled
  public static String placeOrder(
    String quoteId,
    String shippingMethod,
    Boolean isExpedite,
    String packagingType,
    String poNumber,
    String billingAddressId,
    String shippingAddressId,
    String paymentMethod,
    String notes,
    String promoCode,
    String sequencesJson,
    Boolean isTaxExempt,
    Boolean isPartialShipment,
    String bpoId,
    String paymentMethodRecordId
  ) {
    // Constants
    final String QUOTE_STATUS_DRAFT = 'Draft';
    final String QUOTE_STATUS_PRESENTED = 'Entered';
    final String ORDER_STATUS_DRAFT = 'Draft';
    final Decimal DEFAULT_SHIPPING_FEE = 60.00;
    final Decimal DEFAULT_PACKAGING_FEE = 55.00;
    final String DEFAULT_INCO_TERMS = 'FCA';

    if (String.isBlank(quoteId)) {
      throw checkoutAura('Quote Id is required.');
    }

    // Resolve the ID — callers may pass an ABT_Quote_Request__c ID instead of a Quote ID.
    // If the direct Quote lookup misses, fall back to the request's linked Quote.
    Id resolvedQuoteId = quoteId;
    Id quoteRequestId = null; // track the ABT_Quote_Request__c Id for line-item fallback

    List<Quote> quotes = [
      SELECT
        Id,
        Status,
        ContactId,
        OpportunityId,
        Pricebook2Id,
        ShippingHandling,
        X3rd_Party_Shipping_Account__c,
        Discount__c,
        Discount_Amount__c,
        Opportunity.Name,
        Opportunity.AccountId,
        Opportunity.ContactId
      FROM Quote
      WHERE Id = :resolvedQuoteId
      LIMIT 1
    ];
    if (quotes.isEmpty()) {
      List<ABT_Quote_Request__c> qrs = [
        SELECT Id, ABT_Quote__c
        FROM ABT_Quote_Request__c
        WHERE Id = :quoteId
        LIMIT 1
      ];
      if (!qrs.isEmpty() && qrs[0].ABT_Quote__c != null) {
        quoteRequestId = qrs[0].Id;
        resolvedQuoteId = qrs[0].ABT_Quote__c;
        quotes = [
          SELECT
            Id,
            Status,
            ContactId,
            OpportunityId,
            Pricebook2Id,
            ShippingHandling,
            X3rd_Party_Shipping_Account__c,
            Discount__c,
            Discount_Amount__c,
            Opportunity.Name,
            Opportunity.AccountId,
            Opportunity.ContactId
          FROM Quote
          WHERE Id = :resolvedQuoteId
          LIMIT 1
        ];
      }
    } else {
      // quoteId was already a Quote ID — find the request that points back to it
      List<ABT_Quote_Request__c> linkedReqs = [
        SELECT Id
        FROM ABT_Quote_Request__c
        WHERE ABT_Quote__c = :resolvedQuoteId
        LIMIT 1
      ];
      if (!linkedReqs.isEmpty())
        quoteRequestId = linkedReqs[0].Id;
    }

    Savepoint sp = Database.setSavepoint();
    try {
      if (quotes.isEmpty()) {
        throw checkoutAura(
          'No quote is ready for checkout yet. If you just submitted a quote request, ' +
          'please wait for Ansa\'s team to process it before checking out.'
        );
      }
      Quote quote = quotes[0];
      assertQuotesNotAlreadyOrdered(new Set<Id>{ quote.Id });

      // 2. Ownership check (also list-based to be safe)
      List<User> users = [
        SELECT ContactId
        FROM User
        WHERE Id = :UserInfo.getUserId()
        LIMIT 1
      ];
      Id currentContactId = users.isEmpty() ? null : users[0].ContactId;

      Boolean isOwner =
        currentContactId != null &&
        (currentContactId == quote.ContactId ||
        currentContactId == quote.Opportunity.ContactId);
      if (!isOwner) {
        throw checkoutAura(
          'You do not have permission to checkout this quote.'
        );
      }
      // if (quote.Status != 'Ordered' && quote.Status != 'Rejected') {
      //     throw new AuraHandledException('Only OPEN quotes can be checked out.' + quote.Status);
      // }

      // 4. Build Order
      Order newOrder = new Order(
        AccountId = quote.Opportunity.AccountId,
        OpportunityId = quote.OpportunityId,
        QuoteId = quote.Id,
        Pricebook2Id = quote.Pricebook2Id,
        EffectiveDate = Date.today(),
        Status = ORDER_STATUS_DRAFT
      );

      String projectName = resolveSingleQuoteProjectName(quote, quoteRequestId);
      Id accountId = quote.Opportunity.AccountId;
      Id contactId = getCurrentUserContactId();
      validatePortalCreditCardCheckout(paymentMethod, paymentMethodRecordId);
      Id blanketPurchaseOrderId = resolveCheckoutBlanketPurchaseOrderId(
        paymentMethod,
        accountId,
        bpoId,
        poNumber
      );
      String resolvedPoNumber = resolveCheckoutPoNumber(
        paymentMethod,
        poNumber,
        blanketPurchaseOrderId
      );
      String stripePaymentMethodId = resolveCheckoutStripePaymentMethodId(
        paymentMethod,
        contactId,
        paymentMethodRecordId
      );

      applyPortalCheckoutFields(
        newOrder,
        projectName,
        shippingMethod,
        isExpedite,
        packagingType,
        resolvedPoNumber,
        billingAddressId,
        shippingAddressId,
        paymentMethod,
        notes,
        promoCode,
        isTaxExempt,
        isPartialShipment,
        blanketPurchaseOrderId,
        stripePaymentMethodId
      );
      applyThirdPartyShippingFromQuotes(newOrder, quotes);
      // Prefer Contact invoice email from checkout; flow only fills from Account when blank.
      putOrderFieldIfPresent(
        newOrder,
        Schema.SObjectType.Order.fields.getMap(),
        'Invoice_Email__c',
        resolveCheckoutInvoiceEmail(contactId)
      );

      insert newOrder;
      persistOrderAddressesAfterInsert(
        newOrder.Id,
        billingAddressId,
        shippingAddressId
      );

      if (quoteRequestId != null) {
        persistCheckoutPromoToQuoteRequests(
          new List<Id>{ quoteRequestId },
          promoCode
        );
      } else {
        persistCheckoutPromoToQuotes(new List<Id>{ quote.Id }, promoCode);
      }
      quotes = [
        SELECT
          Id,
          Status,
          ContactId,
          OpportunityId,
          Pricebook2Id,
          ShippingHandling,
          X3rd_Party_Shipping_Account__c,
          Discount__c,
          Discount_Amount__c,
          Opportunity.Name,
          Opportunity.AccountId,
          Opportunity.ContactId
        FROM Quote
        WHERE Id = :resolvedQuoteId
        LIMIT 1
      ];
      quote = quotes[0];

      // 5. Copy Quote Line Items → Order Items.
      // Primary path: Ansa staff has priced the request and added QuoteLineItems.
      // Fallback path: copy raw sequences from ABT_Quote_Request_Lineitem__c so the
      //   customer can see their sequences in the order even before Ansa prices them.
      List<QuoteLineItem> allQuoteLineItems = Database.query(
        'SELECT ' +
          quoteLineItemPortalSelectClause() +
          ' FROM QuoteLineItem WHERE QuoteId = :resolvedQuoteId'
      );
      Boolean quoteHasPricedLines = !allQuoteLineItems.isEmpty();
      if (
        !findQuoteIdsWithOnlyNonOrderableLines(
            allQuoteLineItems,
            new List<Id>{ resolvedQuoteId },
            accountId
          )
          .isEmpty()
      ) {
        throw checkoutAura(CHECKOUT_NO_ORDERABLE_LINES_MESSAGE);
      }

      List<QuoteLineItem> quoteLineItems = filterOrderableQuoteLineItems(
        allQuoteLineItems,
        accountId
      );

      Boolean hasOrderItems = false;

      if (!quoteLineItems.isEmpty()) {
        // Pre-fetch PricebookEntry prices to fill in any 0-priced QLIs
        Set<Id> qliPbeIds = new Set<Id>();
        for (QuoteLineItem qli : quoteLineItems) {
          if (qli.PricebookEntryId != null)
            qliPbeIds.add(qli.PricebookEntryId);
        }
        Map<Id, Decimal> qliPriceByPbeId = new Map<Id, Decimal>();
        if (!qliPbeIds.isEmpty()) {
          for (PricebookEntry pbe : [
            SELECT Id, UnitPrice
            FROM PricebookEntry
            WHERE Id IN :qliPbeIds
          ]) {
            qliPriceByPbeId.put(pbe.Id, pbe.UnitPrice);
          }
        }
        List<OrderItem> orderItems = new List<OrderItem>();
        Boolean includeScaleUpField = !quoteLineItemsIncludeScaleUpChild(
          quoteLineItems
        );
        Boolean includeGlycerolField = !quoteLineItemsIncludeGlycerolChild(
          quoteLineItems
        );
        for (QuoteLineItem qli : quoteLineItems) {
          Decimal fallback = qliPriceByPbeId.containsKey(qli.PricebookEntryId)
            ? qliPriceByPbeId.get(qli.PricebookEntryId)
            : 0;
          Decimal price = quoteLineItemOrderUnitPrice(
            qli,
            fallback,
            includeScaleUpField,
            includeGlycerolField
          );
          OrderItem oi = new OrderItem(
            OrderId = newOrder.Id,
            Product2Id = qli.Product2Id,
            Quantity = qli.Quantity,
            UnitPrice = price,
            PricebookEntryId = qli.PricebookEntryId,
            Description = qli.Description
          );
          copyQuoteLineItemToOrderItem(oi, qli, quote.Id);
          if (!includeScaleUpField) {
            clearOrderItemScaleUpPriceField(oi);
          }
          orderItems.add(oi);
        }
        insert orderItems;
        hasOrderItems = true;
      } else if (quoteHasPricedLines) {
        throw checkoutAura(CHECKOUT_NO_ORDERABLE_LINES_MESSAGE);
      } else if (quoteRequestId != null) {
        // Fallback: build OrderItems from ABT_Quote_Request_Lineitem__c
        List<ABT_Quote_Request_Lineitem__c> reqLines = [
          SELECT
            Id,
            Related_Sequence__c,
            Related_Sequence__r.Sequence_Name__c,
            Related_Sequence__r.Sequence__c,
            ABT_Quote_Request__r.ABT_Product__c
          FROM ABT_Quote_Request_Lineitem__c
          WHERE ABT_Quote_Request__c = :quoteRequestId
          ORDER BY CreatedDate ASC
        ];

        if (!reqLines.isEmpty()) {
          Id productId = reqLines[0].ABT_Quote_Request__r.ABT_Product__c;

          // Resolve pricebook — use Quote's pricebook or fall back to Standard
          Id pricebookId = quote.Pricebook2Id;
          if (pricebookId == null) {
            List<Pricebook2> stdPbs = [
              SELECT Id
              FROM Pricebook2
              WHERE IsStandard = TRUE AND IsActive = TRUE
              LIMIT 1
            ];
            if (!stdPbs.isEmpty())
              pricebookId = stdPbs[0].Id;
          }

          List<PricebookEntry> pbeList = new List<PricebookEntry>();
          if (pricebookId != null && productId != null) {
            pbeList = [
              SELECT Id, UnitPrice
              FROM PricebookEntry
              WHERE
                Pricebook2Id = :pricebookId
                AND Product2Id = :productId
                AND IsActive = TRUE
              LIMIT 1
            ];
          }

          if (!pbeList.isEmpty()) {
            // Ensure the Order has the right pricebook set
            if (newOrder.Pricebook2Id == null) {
              newOrder.Pricebook2Id = pricebookId;
              update newOrder;
            }

            Map<String, Schema.SObjectField> oiFields = Schema.SObjectType.OrderItem.fields.getMap();
            Boolean hasRelatedSequence = oiFields.containsKey(
              'related_sequence__c'
            );

            List<OrderItem> fallbackItems = new List<OrderItem>();
            for (ABT_Quote_Request_Lineitem__c rl : reqLines) {
              OrderItem oi = new OrderItem(
                OrderId = newOrder.Id,
                Product2Id = productId,
                PricebookEntryId = pbeList[0].Id,
                Quantity = 1,
                UnitPrice = pbeList[0].UnitPrice
              );
              if (hasRelatedSequence && rl.Related_Sequence__c != null) {
                oi.put('Related_Sequence__c', rl.Related_Sequence__c);
              }
              fallbackItems.add(oi);
            }
            List<Database.SaveResult> insertResults = Database.insert(
              fallbackItems,
              false
            );
            for (Database.SaveResult sr : insertResults) {
              if (sr.isSuccess()) {
                hasOrderItems = true;
              }
            }
          }
        }
      }

      // Last-resort fallback: sequences were stored only in the browser (e.g. pricebook
      // validation prevented ABT_Quote_Request_Lineitem__c from being saved).
      // The LWC passes them as sequencesJson so we can still attach them to the order.
      if (!hasOrderItems && String.isNotBlank(sequencesJson)) {
        // Need product and pricebook from the quote request
        Id fbProductId = null;
        Id fbPricebookId = quote.Pricebook2Id;

        if (quoteRequestId != null) {
          List<ABT_Quote_Request__c> reqForProd = [
            SELECT ABT_Product__c
            FROM ABT_Quote_Request__c
            WHERE Id = :quoteRequestId
            LIMIT 1
          ];
          if (!reqForProd.isEmpty())
            fbProductId = reqForProd[0].ABT_Product__c;
        }

        if (fbPricebookId == null) {
          List<Pricebook2> stdPbs = [
            SELECT Id
            FROM Pricebook2
            WHERE IsStandard = TRUE AND IsActive = TRUE
            LIMIT 1
          ];
          if (!stdPbs.isEmpty())
            fbPricebookId = stdPbs[0].Id;
        }

        List<PricebookEntry> fbPbe = new List<PricebookEntry>();
        if (fbPricebookId != null && fbProductId != null) {
          fbPbe = [
            SELECT Id, UnitPrice
            FROM PricebookEntry
            WHERE
              Pricebook2Id = :fbPricebookId
              AND Product2Id = :fbProductId
              AND IsActive = TRUE
            LIMIT 1
          ];
        }

        if (!fbPbe.isEmpty()) {
          if (newOrder.Pricebook2Id == null) {
            newOrder.Pricebook2Id = fbPricebookId;
            update newOrder;
          }

          Map<String, Schema.SObjectField> oiFields = Schema.SObjectType.OrderItem.fields.getMap();
          Boolean hasSeqName = oiFields.containsKey('sequence_name__c');
          Boolean hasSeq = oiFields.containsKey('sequence__c');

          List<Object> parsedSeqs = (List<Object>) JSON.deserializeUntyped(
            sequencesJson
          );
          List<OrderItem> jsonItems = new List<OrderItem>();
          for (Object s : parsedSeqs) {
            Map<String, Object> seq = (Map<String, Object>) s;
            OrderItem oi = new OrderItem(
              OrderId = newOrder.Id,
              Product2Id = fbProductId,
              PricebookEntryId = fbPbe[0].Id,
              Quantity = 1,
              UnitPrice = fbPbe[0].UnitPrice
            );
            if (hasSeqName)
              oi.put('Sequence_Name__c', (String) seq.get('name'));
            if (hasSeq)
              oi.put('Sequence__c', (String) seq.get('sequence'));
            jsonItems.add(oi);
          }
          if (!jsonItems.isEmpty()) {
            List<Database.SaveResult> srs = Database.insert(jsonItems, false);
            for (Database.SaveResult sr : srs) {
              if (sr.isSuccess())
                hasOrderItems = true;
            }
          }
        }
      }

      if (!hasOrderItems && quoteHasPricedLines) {
        throw checkoutAura(CHECKOUT_NO_ORDERABLE_LINES_MESSAGE);
      }

      stampOrderDiscountFromQuotes(newOrder.Id, quotes);

      return newOrder.Id;
    } catch (AuraHandledException ahe) {
      Database.rollback(sp);
      throw checkoutUnexpected(
        ahe,
        resolvedQuoteId == null ? null : new List<Id>{ resolvedQuoteId }
      );
    } catch (Exception e) {
      Database.rollback(sp);
      System.debug(
        LoggingLevel.ERROR,
        'placeOrder failed: ' + e.getMessage() + '\n' + e.getStackTraceString()
      );
      throw checkoutUnexpected(
        e,
        resolvedQuoteId == null ? null : new List<Id>{ resolvedQuoteId }
      );
    }
  }
  /**
   * OPTIONAL: Helper method to get Order details after creation
   * Can be used by Order detail page
   */
  @AuraEnabled(cacheable=true)
  public static Order getOrderDetails(String orderId) {
    try {
      return [
        SELECT
          Id,
          OrderNumber,
          Status,
          TotalAmount,
          CreatedDate,
          AccountId,
          Account.Name,
          QuoteId,
          Quote.QuoteNumber,
          OpportunityId,
          Opportunity.Name,
          Customer_Project_Name__c,
          Invoice_Status__c,
          //Is_Expedite__c, Shipping_Method__c, Packaging_Type__c, PO_Number__c, Notes__c
          Payment_Method__c,
          Promo_Code__c,
          (
            SELECT
              Id,
              Product2.Name,
              Quantity,
              UnitPrice,
              TotalPrice, //Sequence_Name__c
              Sequence__c,
              Sequence_Length__c
            //Group__c, Scale__c, Purification__c
            FROM OrderItems
          )
        FROM Order
        WHERE Id = :orderId
        LIMIT 1
      ];
    } catch (Exception e) {
      throw new AuraHandledException(
        'Unable to fetch order details: ' + e.getMessage()
      );
    }
  }

  @AuraEnabled(cacheable=true)
  public static List<Order> getOrdersByAccount(Id accountId) {
    if (accountId == null) {
      throw new AuraHandledException('accountId cannot be null');
    }
    return [
      SELECT
        Id,
        OrderNumber,
        Status,
        EffectiveDate,
        QuoteId,
        (SELECT Id, Product2.Name FROM OrderItems)
      FROM Order
      WHERE AccountId = :accountId
      ORDER BY CreatedDate DESC
      LIMIT 200
    ];
  }

  /**
   * Get pending ABT_Quote_Request__c records for the user's account that have not yet
   * been processed into a standard Quote by Ansa staff (ABT_Quote__c == null).
   * These appear in the cart as "Pending Review" rows — the customer can see them
   * but cannot check out until Ansa creates a priced Quote.
   */
  @AuraEnabled
  public static List<ABT_Quote_Request__c> getPendingQuoteRequests(
    String userId
  ) {
    try {
      User currentUser = [
        SELECT AccountId
        FROM User
        WHERE Id = :userId
        LIMIT 1
      ];
      Id accountId = currentUser.AccountId;

      if (accountId != null) {
        List<ABT_Quote_Request__c> byAccount = [
          SELECT
            Id,
            Name,
            ABT_Customer_Project_Name__c,
            ABT_Product_Name__c,
            ABT_Stage__c,
            ABT_Total_Price__c,
            CreatedDate,
            (SELECT Id FROM Quote_Request_Lineitems__r)
          FROM ABT_Quote_Request__c
          WHERE ABT_Account__c = :accountId AND ABT_Quote__c = NULL
          ORDER BY CreatedDate DESC
        ];
        if (!byAccount.isEmpty()) {
          return byAccount;
        }
      }

      return [
        SELECT
          Id,
          Name,
          ABT_Customer_Project_Name__c,
          ABT_Product_Name__c,
          ABT_Stage__c,
          ABT_Total_Price__c,
          CreatedDate
        FROM ABT_Quote_Request__c
        WHERE CreatedById = :userId AND ABT_Quote__c = NULL
        ORDER BY CreatedDate DESC
      ];
    } catch (Exception e) {
      System.debug('Error in getPendingQuoteRequests: ' + e.getMessage());
      throw new AuraHandledException(
        'Unable to fetch pending requests: ' + e.getMessage()
      );
    }
  }

  @AuraEnabled(cacheable=true)
  public static List<Quote> getPortalCommerceCart(String userId) {
    return ABT_Cart_Service.getPortalCommerceCart(userId);
  }

  @AuraEnabled(cacheable=true)
  public static List<Quote> getDraftQuotes(String userId) {
    return getPortalCommerceCart(userId);
  }

  @AuraEnabled
  public static void addQuoteRequestToCommerceCart(Id quoteRequestId) {
    ABT_Cart_Service.addQuoteRequestToCommerceCart(quoteRequestId);
  }

  @AuraEnabled
  public static Boolean removeQuoteRequestFromCommerceCart(Id quoteRequestId) {
    return ABT_Cart_Service.removeQuoteRequestFromCommerceCart(quoteRequestId);
  }

  @AuraEnabled
  public static Boolean syncLegacyPortalCommerceCart() {
    return ABT_Cart_Service.syncLegacyPortalCommerceCart();
  }

  /**
   * Persist cart-wide shipping method on each draft Quote (and linked Quote Request when present)
   * so org automation can recalculate Quote.ShippingHandling.
   */
  @AuraEnabled
  public static void updateCartShippingMethod(
    List<Id> quoteIds,
    String shippingMethodValue
  ) {
    try {
      if (quoteIds == null || quoteIds.isEmpty()) {
        return;
      }
      if (String.isBlank(shippingMethodValue)) {
        throw new AuraHandledException('Shipping method is required.');
      }

      Set<Id> requestedIds = new Set<Id>(quoteIds);
      if (requestedIds.isEmpty()) {
        return;
      }

      User currentUser = [
        SELECT ContactId
        FROM User
        WHERE Id = :UserInfo.getUserId()
        LIMIT 1
      ];
      if (currentUser.ContactId == null) {
        throw new AuraHandledException(
          'You must be logged in as a contact user to update shipping.'
        );
      }

      List<Quote> quotes = [
        SELECT Id, ContactId, OpportunityId, Opportunity.ContactId
        FROM Quote
        WHERE Id IN :requestedIds
      ];

      if (quotes.size() != requestedIds.size()) {
        throw new AuraHandledException('One or more quotes were not found.');
      }

      for (Quote q : quotes) {
        Id oppContactId = (q.Opportunity != null)
          ? q.Opportunity.ContactId
          : null;
        Boolean isOwner =
          (q.ContactId == currentUser.ContactId) ||
          (oppContactId == currentUser.ContactId);
        if (!isOwner) {
          throw new AuraHandledException(
            'You do not have permission to update shipping for these quotes.'
          );
        }
      }

      Map<String, Schema.SObjectField> quoteFieldMap = Schema.SObjectType.Quote.fields.getMap();
      Map<String, Schema.SObjectField> qrFieldMap = Schema.SObjectType.ABT_Quote_Request__c.fields.getMap();

      Boolean quoteHasShippingField = quoteFieldMap.containsKey(
        'abt_shipping_method__c'
      );
      Boolean qrHasShippingField = qrFieldMap.containsKey(
        'abt_shipping_method__c'
      );

      if (quoteHasShippingField) {
        List<Quote> quoteUpdates = new List<Quote>();
        for (Id qId : requestedIds) {
          Quote qu = new Quote(Id = qId);
          qu.put('ABT_Shipping_Method__c', shippingMethodValue);
          quoteUpdates.add(qu);
        }
        update quoteUpdates;
      }

      if (qrHasShippingField) {
        try {
          List<ABT_Quote_Request__c> qrs = [
            SELECT Id
            FROM ABT_Quote_Request__c
            WHERE ABT_Quote__c IN :requestedIds
          ];
          if (!qrs.isEmpty()) {
            for (ABT_Quote_Request__c qr : qrs) {
              qr.put('ABT_Shipping_Method__c', shippingMethodValue);
            }
            update qrs;
          }
        } catch (Exception qrUpdateError) {
          System.debug(
            LoggingLevel.WARN,
            'Quote request shipping sync skipped: ' + qrUpdateError.getMessage()
          );
        }
      }
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      System.debug('Error in updateCartShippingMethod: ' + e.getMessage());
      throw new AuraHandledException(
        'Unable to update shipping method: ' + e.getMessage()
      );
    }
  }

  @AuraEnabled(cacheable=true)
  public static List<ABT_Quote_Request__c> getQuoteRequestIdsByQuoteIds(
    List<Id> quoteIds
  ) {
    if (quoteIds == null || quoteIds.isEmpty())
      return new List<ABT_Quote_Request__c>();
    return [
      SELECT
        Id,
        ABT_Quote__c,
        ABT_Shipping_Method__c,
        ABT_Product_Name__c,
        ABT_Product__r.Name,
        ABT_Customer_Project_Name__c,
        Total_Quote_Request_Line_Items__c,
        Shipping_Destination__c,
        As_Early_As_Date__c,
        Promo_Code__c,
        Promo_Code__r.Name,
        Promo_Code__r.Promo_Code__c,
        Promo_Code__r.Discount_Percentage__c,
        (
          SELECT
            Id,
            Expected_Ship_Date__c,
            Tranche__c,
            ABT_Total_Price__c,
            Total_Combined_Price__c,
            Scale_Up_Price__c,
            Glycerol_Price__c
          FROM Quote_Request_Lineitems__r
        )
      FROM ABT_Quote_Request__c
      WHERE ABT_Quote__c IN :quoteIds
    ];
  }

  /**
   * Update quote status
   * @param quoteId - ID of the quote
   * @param newStatus - New status value
   */
  @AuraEnabled
  public static void updateQuoteStatus(String quoteId, String newStatus) {
    try {
      Quote quote = [
        SELECT Id, Status, ContactId, OpportunityId, Opportunity.ContactId
        FROM Quote
        WHERE Id = :quoteId
        LIMIT 1
      ];

      // Security check
      User currentUser = [
        SELECT ContactId
        FROM User
        WHERE Id = :UserInfo.getUserId()
        LIMIT 1
      ];

      Boolean isOwner =
        (quote.ContactId == currentUser.ContactId) ||
        (quote.Opportunity.ContactId == currentUser.ContactId);

      if (!isOwner) {
        throw new AuraHandledException(
          'You do not have permission to update this quote.'
        );
      }

      quote.Status = newStatus;
      update quote;
    } catch (Exception e) {
      System.debug('Error in updateQuoteStatus: ' + e.getMessage());
      throw new AuraHandledException(
        'Unable to update quote status: ' + e.getMessage()
      );
    }
  }

  /**
   * OPTIONAL: Get rejected quotes for history view
   * @param userId - Current user ID
   * @return List of rejected Quote records
   */
  @AuraEnabled(cacheable=true)
  public static List<Quote> getRejectedQuotes(String userId) {
    try {
      User currentUser = [
        SELECT ContactId
        FROM User
        WHERE Id = :userId
        LIMIT 1
      ];

      if (currentUser.ContactId == null) {
        return new List<Quote>();
      }

      List<Quote> rejectedQuotes = [
        SELECT
          Id,
          QuoteNumber,
          Name,
          Status,
          Account.Name,
          Opportunity.Name,
          TotalPrice,
          GrandTotal,
          CreatedDate,
          LastModifiedDate
        FROM Quote
        WHERE
          (ContactId = :currentUser.ContactId
          OR Opportunity.ContactId = :currentUser.ContactId)
          AND Status = 'Rejected'
        ORDER BY LastModifiedDate DESC
        LIMIT 100
      ];

      return rejectedQuotes;
    } catch (Exception e) {
      System.debug('Error in getRejectedQuotes: ' + e.getMessage());
      throw new AuraHandledException(
        'Unable to fetch rejected quotes: ' + e.getMessage()
      );
    }
  }

  /**
   * Helper method to get contact ID for user
   * (If you need this separately)
   */
  @AuraEnabled(cacheable=true)
  public static String getUserContactId(String userId) {
    try {
      User u = [SELECT ContactId FROM User WHERE Id = :userId LIMIT 1];
      return u.ContactId;
    } catch (Exception e) {
      throw new AuraHandledException(
        'Unable to get contact ID: ' + e.getMessage()
      );
    }
  }

  @TestVisible
  private static Boolean skipCartEmailFlowForTests = false;

  /**
   * Sends the portal cart to a recipient (Sales Rep or Procurement) from the
   * cart email actions. Portal users cannot reliably call Messaging.sendEmail
   * directly, so Apex validates/builds the payload and delegates the actual send
   * to the Cart_Portal_Email_Send autolaunched flow.
   */
  @AuraEnabled
  public static void sendCartEmail(
    String toAddress,
    String subject,
    String message,
    String cartHtml
  ) {
    List<String> recipients = parseCartEmailRecipients(toAddress);
    String finalSubject = String.isNotBlank(subject)
      ? subject.trim()
      : 'Your Ansa Biotechnologies Cart';

    User currentUser = [
      SELECT Id, Name, Email
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];

    String emailBody = buildCartEmailBody(currentUser, message, cartHtml);

    if (Test.isRunningTest() && skipCartEmailFlowForTests) {
      return;
    }

    try {
      Flow.Interview flowInterview = Flow.Interview.createInterview(
        'Cart_Portal_Email_Send',
        new Map<String, Object>{
          'toAddress' => recipients,
          'emailSubject' => finalSubject,
          'emailBody' => emailBody
        }
      );
      flowInterview.start();
    } catch (Exception e) {
      System.debug('Failed to send cart email via flow: ' + e.getMessage());
      throw new AuraHandledException('Unable to send email: ' + e.getMessage());
    }
  }

  @TestVisible
  private static List<String> parseCartEmailRecipients(String toAddress) {
    if (String.isBlank(toAddress)) {
      throw new AuraHandledException('A recipient email address is required.');
    }

    List<String> recipients = new List<String>();
    for (String raw : toAddress.split('[,;]')) {
      String cleaned = raw == null ? '' : raw.trim();
      if (String.isNotBlank(cleaned)) {
        recipients.add(cleaned);
      }
    }
    if (recipients.isEmpty()) {
      throw new AuraHandledException('A recipient email address is required.');
    }
    return recipients;
  }

  @TestVisible
  private static String buildCartEmailBody(
    User currentUser,
    String message,
    String cartHtml
  ) {
    String safeMessage = String.isNotBlank(message)
      ? message.trim().escapeHtml4().replace('\n', '<br/>')
      : '';
    String cartMarkup = sanitizeCartEmailHtml(cartHtml);

    String innerContent = '';
    if (String.isNotBlank(safeMessage)) {
      innerContent += '<p>' + safeMessage + '</p>';
    }
    innerContent +=
      '<p>Please find the cart details below' +
      (currentUser != null && String.isNotBlank(currentUser.Name)
        ? ', shared by ' + currentUser.Name.escapeHtml4()
        : '') +
      '.</p>';
    innerContent += '<hr style="border:none;border-top:1px solid #e1e1e2;margin:16px 0;"/>';
    innerContent += cartMarkup;

    return wrapAnsaEmailShell(innerContent);
  }

  @TestVisible
  private static String wrapAnsaEmailShell(String innerContent) {
    return '<html><body style="background:white;color:black;">' +
      '<table border="0" cellpadding="0" cellspacing="0" width="100%" height="100%" role="presentation" style="border-collapse:collapse;border-spacing:0;vertical-align:top;height:100%!important;width:100%!important;min-width:100%;box-sizing:border-box;text-align:center;background-color:#e9eaec;font-weight:normal;padding:0;margin:0;Margin:0;font-size:16px;line-height:24px;color:#2a2b2d;font-family:-apple-system,BlinkMacSystemFont,avenir next,avenir,segoe ui,helvetica neue,helvetica,Cantarell,Ubuntu,roboto,noto,arial,sans-serif">' +
      '<tbody><tr style="padding:0;vertical-align:top">' +
      '<td style="word-wrap:break-word;border-collapse:collapse!important;vertical-align:top;font-weight:normal;padding:0;margin:0;Margin:0;font-size:16px;color:#2a2b2d;font-family:-apple-system,BlinkMacSystemFont,avenir next,avenir,segoe ui,helvetica neue,helvetica,Cantarell,Ubuntu,roboto,noto,arial,sans-serif;line-height:24px"></td>' +
      '<td align="center" valign="top" width="700" style="word-wrap:break-word;border-collapse:collapse!important;vertical-align:top;font-weight:normal;padding:0;margin:0;Margin:0;font-size:16px;color:#2a2b2d;font-family:-apple-system,BlinkMacSystemFont,avenir next,avenir,segoe ui,helvetica neue,helvetica,Cantarell,Ubuntu,roboto,noto,arial,sans-serif;padding-top:80px;padding-bottom:80px;line-height:24px">' +
      '<div width="100%" dir="ltr" style="max-width:700px">' +
      '<table border="0" cellpadding="0" cellspacing="0" width="100%" role="presentation" style="border-collapse:collapse;border-spacing:0;padding:0;vertical-align:top;margin:0 auto 0 auto;Margin:0 auto 0 auto">' +
      '<tbody><tr style="padding:0;vertical-align:top">' +
      '<td bgcolor="#ffffff" style="word-wrap:break-word;border-collapse:collapse!important;vertical-align:top;font-weight:normal;padding:0;margin:0;Margin:0;font-size:16px;color:#2a2b2d;font-family:-apple-system,BlinkMacSystemFont,avenir next,avenir,segoe ui,helvetica neue,helvetica,Cantarell,Ubuntu,roboto,noto,arial,sans-serif;border-radius:12px;background-color:#ffffff;line-height:24px">' +
      '<table border="0" cellpadding="0" cellspacing="0" width="100%" role="presentation" style="border-collapse:collapse;border-spacing:0;padding:0;vertical-align:top">' +
      '<tbody>' +
      '<tr style="padding:0;vertical-align:top">' +
      '<td valign="middle" style="word-wrap:break-word;border-collapse:collapse!important;vertical-align:top;font-weight:normal;margin:0;Margin:0;font-size:16px;color:#2a2b2d;font-family:-apple-system,BlinkMacSystemFont,avenir next,avenir,segoe ui,helvetica neue,helvetica,Cantarell,Ubuntu,roboto,noto,arial,sans-serif;line-height:1;padding:40px 50px 40px 50px;border-bottom:1px solid #e1e1e2">' +
      '<div style="max-width:350px;display:inline-block;vertical-align:middle;width:80%">' +
      '<img src="https://ansabio.com/wp-content/uploads/2024/11/ANSA-BIO-Logo-Horizontal-Dark.png" alt="Ansa Biotechnologies" style="outline:none;text-decoration:none;width:auto;max-width:100%;clear:both;display:inline-block!important;vertical-align:middle;max-height:180px" />' +
      '</div></td></tr>' +
      '<tr style="padding:0;vertical-align:top">' +
      '<td valign="top" style="word-wrap:break-word;border-collapse:collapse!important;vertical-align:top;font-weight:normal;margin:0;Margin:0;font-size:16px;color:#2a2b2d;font-family:-apple-system,BlinkMacSystemFont,avenir next,avenir,segoe ui,helvetica neue,helvetica,Cantarell,Ubuntu,roboto,noto,arial,sans-serif;padding:35px 50px 25px 50px;line-height:24px">' +
      '<table border="0" cellpadding="0" cellspacing="0" width="100%" role="presentation" style="border-collapse:collapse;border-spacing:0;padding:0;vertical-align:top">' +
      '<tbody><tr style="padding:0;vertical-align:top">' +
      '<td colspan="2" style="word-wrap:break-word;border-collapse:collapse!important;vertical-align:top;font-weight:normal;padding:0;margin:0;Margin:0;font-size:16px;color:#2a2b2d;font-family:-apple-system,BlinkMacSystemFont,avenir next,avenir,segoe ui,helvetica neue,helvetica,Cantarell,Ubuntu,roboto,noto,arial,sans-serif;padding-top:15px;padding-bottom:25px;line-height:24px;text-align:left">' +
      innerContent +
      '</td></tr></tbody></table>' +
      '</td></tr>' +
      '<tr style="padding:0;vertical-align:top">' +
      '<td valign="top" style="word-wrap:break-word;border-collapse:collapse!important;vertical-align:top;font-weight:normal;margin:0;Margin:0;font-family:-apple-system,BlinkMacSystemFont,avenir next,avenir,segoe ui,helvetica neue,helvetica,Cantarell,Ubuntu,roboto,noto,arial,sans-serif;font-size:14px;padding:30px 50px 30px 50px;border-top:1px solid #e1e1e2;color:#959596;line-height:24px;text-align:left">' +
      'Sent from <a href="https://ansabio.com" style="font-weight:normal;padding:0;margin:0;Margin:0;line-height:24px;font-family:-apple-system,BlinkMacSystemFont,avenir next,avenir,segoe ui,helvetica neue,helvetica,Cantarell,Ubuntu,roboto,noto,arial,sans-serif;text-decoration:underline;color:#959596" target="_blank">Ansa Biotechnologies</a>' +
      '</td></tr>' +
      '</tbody></table>' +
      '</td></tr></tbody></table>' +
      '</div></td><td></td></tr></tbody></table>' +
      '</body></html>';
  }

  @TestVisible
  private static String sanitizeCartEmailHtml(String cartHtml) {
    if (String.isBlank(cartHtml)) {
      return '';
    }

    String sanitized = cartHtml;
    sanitized = sanitized.replaceAll('\\s+lwc-[A-Za-z0-9_-]+(="[^"]*")?', '');
    sanitized = sanitized.replaceAll('\\s+data-[A-Za-z0-9_-]+(="[^"]*")?', '');
    sanitized = sanitized.replaceAll('\\s+aria-hidden="[^"]*"', '');
    sanitized = sanitized.replaceAll('\\s+src="/[^"]*"', '');
    // Remove the inner Ansa logo/icon; the branded shell already provides the header logo.
    sanitized = sanitized.replaceAll('(?is)<img[^>]*>', '');
    // Drop the outer wrapper border/padding so the cart blends into the branded card.
    // The wrapper is uniquely identified by "width: 90%"; matching any color format
    // (e.g. #ddd or rgb(221, 221, 221)) leaves the inner table/cell borders intact.
    sanitized = sanitized.replaceAll(
      '(?is)(width:\\s*90%[^"]*?)border:\\s*1px\\s+solid\\s+[^;"]+;',
      '$1'
    );
    sanitized = sanitized.replaceAll(
      '(?is)(width:\\s*90%[^"]*?)padding:\\s*10px;',
      '$1padding: 0;'
    );
    // Make the cart full-width and remove auto-centering so it aligns with the message text.
    sanitized = sanitized.replace('width: 90%;', 'width: 100%;')
      .replace('margin: 0 auto;', 'margin: 0;');
    return sanitized;
  }
}
