/**
 * Portal B2B cart: WebCart / CartItem against Quote Requests.
 * without sharing so community users can still hit store + cart DML.
 * After checkout we close the cart and keep CartItems so CX can see what went out.
 */
public without sharing class ABT_Cart_Service {
  private static final String CART_CREATE_ERROR = 'Unable to create a commerce cart for this portal user.';
  private static final String CART_ITEM_CREATE_ERROR = 'Unable to add this quote to the commerce cart.';

  @TestVisible
  private static List<Id> testCartQuoteIdsOverride;

  @TestVisible
  private static Id testPortalWebStoreIdOverride;

  @TestVisible
  private static Boolean testSimulateCommerceDml = false;

  @TestVisible
  private static WebCart testSimulatedWebCart;

  @TestVisible
  private static List<Id> testSimulatedCartQuoteIds = new List<Id>();

  @TestVisible
  private static Id testSimulatedCartDeliveryGroupId;

  private static final String DEFAULT_DELIVERY_GROUP_NAME = 'Default Delivery';
  private static final String DEFAULT_CART_ITEM_NAME = 'Portal Cart Item';

  private static Map<String, Schema.SObjectField> getCartItemFieldMap() {
    return Schema.SObjectType.CartItem.fields.getMap();
  }

  private static Boolean cartItemHasField(String fieldApiName) {
    return String.isNotBlank(fieldApiName) &&
      getCartItemFieldMap().containsKey(fieldApiName);
  }

  private static Boolean cartDeliveryGroupHasField(String fieldApiName) {
    return String.isNotBlank(fieldApiName) &&
      Schema.SObjectType.CartDeliveryGroup.fields.getMap()
        .containsKey(fieldApiName);
  }

  private static Boolean commerceFieldWritable(
    Schema.DescribeFieldResult fieldDescribe,
    Boolean isInsert
  ) {
    if (fieldDescribe == null) {
      return false;
    }
    return isInsert
      ? fieldDescribe.isCreateable()
      : fieldDescribe.isUpdateable();
  }

  private static Boolean usingSimulatedCommerceCart() {
    return Test.isRunningTest() && testSimulateCommerceDml;
  }

  private static Boolean usingLegacyTestOverride() {
    return Test.isRunningTest() &&
      testCartQuoteIdsOverride != null &&
      !usingSimulatedCommerceCart();
  }

  private static void trackSimulatedCartQuote(Id quoteId) {
    if (quoteId == null || testSimulatedCartQuoteIds.contains(quoteId)) {
      return;
    }
    testSimulatedCartQuoteIds.add(quoteId);
  }

  private static void untrackSimulatedCartQuote(Id quoteId) {
    if (quoteId == null) {
      return;
    }
    List<Id> remaining = new List<Id>();
    for (Id cartQuoteId : testSimulatedCartQuoteIds) {
      if (cartQuoteId != quoteId) {
        remaining.add(cartQuoteId);
      }
    }
    testSimulatedCartQuoteIds = remaining;
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

  private static Id getCurrentUserAccountId() {
    User currentUser = [
      SELECT AccountId, ContactId, Contact.AccountId
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];
    if (currentUser.AccountId != null) {
      return currentUser.AccountId;
    }
    return currentUser.Contact != null ? currentUser.Contact.AccountId : null;
  }

  private static String buildPortalCartName(Id accountId) {
    String accountName = null;
    if (accountId != null) {
      List<Account> accounts = [
        SELECT Name
        FROM Account
        WHERE Id = :accountId
        LIMIT 1
      ];
      if (!accounts.isEmpty()) {
        accountName = accounts[0].Name;
      }
    }

    String userName = null;
    List<User> users = [
      SELECT Name
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];
    if (!users.isEmpty()) {
      userName = users[0].Name;
    }

    List<String> parts = new List<String>();
    if (String.isNotBlank(accountName)) {
      parts.add(accountName.trim());
    }
    if (String.isNotBlank(userName)) {
      parts.add(userName.trim());
    }
    parts.add('Portal Cart');

    String cartName = String.join(parts, ' - ');
    return String.isNotBlank(cartName) ? cartName.left(255) : 'Portal Cart';
  }

  private static Id resolvePortalWebStoreId() {
    if (Test.isRunningTest() && testPortalWebStoreIdOverride != null) {
      return testPortalWebStoreIdOverride;
    }

    Id networkId = null;
    try {
      networkId = Network.getNetworkId();
    } catch (Exception e) {
      networkId = null;
    }

    if (networkId == null) {
      throw new AuraHandledException(
        'This portal site is not running in an Experience Cloud network, so no commerce web store can be resolved.'
      );
    }

    List<SObject> linkedStores = Database.query(
      'SELECT WebStoreId FROM WebStoreNetwork WHERE NetworkId = :networkId LIMIT 1'
    );
    if (linkedStores.isEmpty() || linkedStores[0].get('WebStoreId') == null) {
      throw new AuraHandledException(
        'No commerce web store is linked to the current portal site.'
      );
    }

    return (Id) linkedStores[0].get('WebStoreId');
  }

  private static WebCart createPortalWebCart(Id accountId, Id webStoreId) {
    String cartName = buildPortalCartName(accountId);
    if (usingSimulatedCommerceCart()) {
      testSimulatedWebCart = new WebCart(
        Name = cartName,
        OwnerId = UserInfo.getUserId(),
        AccountId = accountId,
        WebStoreId = webStoreId,
        Status = 'Active',
        Type = 'Cart'
      );
      return testSimulatedWebCart;
    }

    WebCart cart = new WebCart(
      Name = cartName,
      OwnerId = UserInfo.getUserId(),
      AccountId = accountId,
      WebStoreId = webStoreId,
      Status = 'Active',
      Type = 'Cart'
    );

    Database.SaveResult saveResult = Database.insert(cart, false);
    if (!saveResult.isSuccess()) {
      Database.Error err = saveResult.getErrors()[0];
      throw new AuraHandledException(
        CART_CREATE_ERROR + ' ' + err.getMessage()
      );
    }

    cart.Id = saveResult.getId();
    return cart;
  }

  private static WebCart getPortalWebCart(Boolean createIfMissing) {
    if (usingSimulatedCommerceCart() && testSimulatedWebCart != null) {
      String simulatedStatus = testSimulatedWebCart.Status;
      if (simulatedStatus == 'Active' || simulatedStatus == 'Checkout') {
        return testSimulatedWebCart;
      }
      if (!createIfMissing) {
        return null;
      }
      // Closed/historical simulated carts stay available for investigation assertions,
      // but shopping needs a fresh Active cart.
      Id accountId = testSimulatedWebCart.AccountId;
      Id webStoreId = testSimulatedWebCart.WebStoreId != null
        ? testSimulatedWebCart.WebStoreId
        : resolvePortalWebStoreId();
      testSimulatedCartQuoteIds = new List<Id>();
      testSimulatedCartDeliveryGroupId = null;
      return createPortalWebCart(accountId, webStoreId);
    }

    Id accountId = getCurrentUserAccountId();
    if (accountId == null) {
      if (usingSimulatedCommerceCart()) {
        if (!createIfMissing) {
          return null;
        }
        return createPortalWebCart(null, resolvePortalWebStoreId());
      }
      if (!createIfMissing) {
        return null;
      }
      throw new AuraHandledException(
        'You must be logged in as an account user to use the cart.'
      );
    }

    Id webStoreId = resolvePortalWebStoreId();

    if (!usingSimulatedCommerceCart()) {
      List<WebCart> carts = [
        SELECT Id, Name, OwnerId, AccountId, WebStoreId, Status, Type
        FROM WebCart
        WHERE
          OwnerId = :UserInfo.getUserId()
          AND AccountId = :accountId
          AND WebStoreId = :webStoreId
          AND Status IN ('Active', 'Checkout')
        ORDER BY CreatedDate DESC
        LIMIT 1
      ];
      if (!carts.isEmpty()) {
        return carts[0];
      }
    }

    if (!createIfMissing) {
      return null;
    }

    return createPortalWebCart(accountId, webStoreId);
  }

  private static WebCart getOrCreatePortalWebCart() {
    return getPortalWebCart(true);
  }

  private static Map<Id, Id> loadPortalCartItemIdByQuoteId(
    Id cartId,
    Set<Id> quoteIds
  ) {
    Map<Id, Id> result = new Map<Id, Id>();
    if (quoteIds == null || quoteIds.isEmpty()) {
      return result;
    }

    if (usingSimulatedCommerceCart()) {
      for (Id quoteId : quoteIds) {
        if (testSimulatedCartQuoteIds.contains(quoteId)) {
          result.put(quoteId, quoteId);
        }
      }
      return result;
    }

    if (cartId == null) {
      return result;
    }

    for (
      SObject row : Database.query(
        'SELECT Id, ABT_Quote__c FROM CartItem WHERE CartId = :cartId AND ABT_Quote__c IN :quoteIds'
      )
    ) {
      Id quoteId = (Id) row.get('ABT_Quote__c');
      if (quoteId != null && !result.containsKey(quoteId)) {
        result.put(quoteId, (Id) row.get('Id'));
      }
    }

    return result;
  }

  private static List<SObject> loadPortalCartItems(Id cartId) {
    if (usingSimulatedCommerceCart()) {
      List<SObject> rows = new List<SObject>();
      for (Id quoteId : testSimulatedCartQuoteIds) {
        rows.add(new Quote(Id = quoteId));
      }
      return rows;
    }

    if (cartId == null) {
      return new List<SObject>();
    }

    String query = 'SELECT Id, CartId, CreatedDate, Quantity';
    if (cartItemHasField('Product2Id')) {
      query += ', Product2Id';
    }
    if (cartItemHasField('PricebookEntryId')) {
      query += ', PricebookEntryId';
    }
    query +=
      ', ABT_Quote__c, ABT_Quote_Request__c ' +
      'FROM CartItem WHERE CartId = :cartId ORDER BY CreatedDate ASC';
    return Database.query(query);
  }

  private static String resolveQuoteLineItemFieldApiName(
    List<String> candidates
  ) {
    Map<String, Schema.SObjectField> qliFields = Schema.SObjectType.QuoteLineItem.fields.getMap();
    if (candidates == null) {
      return null;
    }
    for (String candidate : candidates) {
      if (String.isBlank(candidate)) {
        continue;
      }
      for (String fieldApiName : qliFields.keySet()) {
        if (fieldApiName != null && fieldApiName.equalsIgnoreCase(candidate)) {
          return fieldApiName;
        }
      }
    }
    return null;
  }

  private static List<QuoteLineItem> loadActiveQuoteLineItems(Id quoteId) {
    if (quoteId == null) {
      return new List<QuoteLineItem>();
    }

    String quoteLineQuery =
      'SELECT Id, QuoteId, Product2Id, Product2.Name, Product2.StockKeepingUnit, ' +
      'PricebookEntryId, Quantity, UnitPrice, ' +
      'TotalPrice, Subtotal, ListPrice, Description';
    String sequenceNameField = resolveQuoteLineItemFieldApiName(
      new List<String>{
        'Sequence_Name__c',
        'ABT_Sequence_Name__c',
        'Customer_ID__c'
      }
    );
    if (sequenceNameField != null) {
      quoteLineQuery += ', ' + sequenceNameField;
    }
    String wasDeletedField = resolveQuoteLineItemFieldApiName(
      new List<String>{ 'Was_Deleted__c' }
    );
    if (wasDeletedField != null) {
      quoteLineQuery += ', ' + wasDeletedField;
    }
    Map<String, Schema.SObjectField> qliFields = Schema.SObjectType.QuoteLineItem.fields.getMap();
    if (qliFields.containsKey('scale_up_price__c')) {
      quoteLineQuery += ', Scale_Up_Price__c';
    }
    if (qliFields.containsKey('glycerol_price__c')) {
      quoteLineQuery += ', Glycerol_Price__c';
    }
    if (qliFields.containsKey('related_sequence__c')) {
      quoteLineQuery +=
        ', ' + ABT_SequenceSyncService.PORTAL_LINE_ITEM_SEQUENCE_SUBQUERY;
    }
    quoteLineQuery += ' FROM QuoteLineItem WHERE QuoteId = :quoteId';
    if (wasDeletedField != null) {
      quoteLineQuery +=
        ' AND (' +
        wasDeletedField +
        ' = false OR ' +
        wasDeletedField +
        ' = null)';
    }
    quoteLineQuery += ' ORDER BY CreatedDate ASC';

    List<SObject> rows = Database.query(quoteLineQuery);
    List<QuoteLineItem> result = new List<QuoteLineItem>();
    for (SObject row : rows) {
      result.add((QuoteLineItem) row);
    }
    return result;
  }

  private static List<ABT_Quote_Request_Lineitem__c> loadQuoteRequestLines(
    Id quoteRequestId
  ) {
    if (quoteRequestId == null) {
      return new List<ABT_Quote_Request_Lineitem__c>();
    }

    return [
      SELECT
        Id,
        ABT_Sequence_Name__c,
        ABT_Sequence__c,
        Related_Sequence__c,
        Related_Sequence__r.Sequence_Name__c,
        ABT_Total_Price__c,
        Total_Combined_Price__c,
        Scale_Up_Price__c,
        Glycerol_Price__c
      FROM ABT_Quote_Request_Lineitem__c
      WHERE ABT_Quote_Request__c = :quoteRequestId
      ORDER BY CreatedDate ASC
    ];
  }

  private static Id resolvePortalCartProductId(
    ABT_Quote_Request__c quoteRequest,
    Quote quote
  ) {
    if (quoteRequest != null && quoteRequest.ABT_Product__c != null) {
      return quoteRequest.ABT_Product__c;
    }

    List<QuoteLineItem> qlis = [
      SELECT Product2Id
      FROM QuoteLineItem
      WHERE QuoteId = :quote.Id
      ORDER BY CreatedDate ASC
      LIMIT 1
    ];
    return qlis.isEmpty() ? null : qlis[0].Product2Id;
  }

  private static Id resolvePortalCartPricebookEntryId(
    Quote quote,
    Id productId
  ) {
    List<QuoteLineItem> qlis = [
      SELECT PricebookEntryId
      FROM QuoteLineItem
      WHERE QuoteId = :quote.Id
      ORDER BY CreatedDate ASC
      LIMIT 1
    ];
    if (!qlis.isEmpty() && qlis[0].PricebookEntryId != null) {
      return qlis[0].PricebookEntryId;
    }

    Id pricebookId = quote.Pricebook2Id;
    if (pricebookId == null) {
      List<Pricebook2> stdPbs = [
        SELECT Id
        FROM Pricebook2
        WHERE IsStandard = TRUE AND IsActive = TRUE
        LIMIT 1
      ];
      if (!stdPbs.isEmpty()) {
        pricebookId = stdPbs[0].Id;
      }
    }
    if (pricebookId == null || productId == null) {
      return null;
    }

    List<PricebookEntry> entries = [
      SELECT Id
      FROM PricebookEntry
      WHERE
        Pricebook2Id = :pricebookId
        AND Product2Id = :productId
        AND IsActive = TRUE
      LIMIT 1
    ];
    return entries.isEmpty() ? null : entries[0].Id;
  }

  private static Id resolveWebStorePricebookId(Id webStoreId) {
    if (webStoreId == null) {
      return null;
    }

    List<WebStore> stores = [
      SELECT SortByPricebookId
      FROM WebStore
      WHERE Id = :webStoreId
      LIMIT 1
    ];
    if (!stores.isEmpty() && stores[0].SortByPricebookId != null) {
      return stores[0].SortByPricebookId;
    }

    try {
      List<SObject> linkedPricebooks = Database.query(
        'SELECT Pricebook2Id FROM WebStorePricebook WHERE WebStoreId = :webStoreId AND IsActive = true LIMIT 1'
      );
      if (!linkedPricebooks.isEmpty()) {
        return (Id) linkedPricebooks[0].get('Pricebook2Id');
      }
    } catch (Exception e) {
      System.debug(
        LoggingLevel.WARN,
        'Unable to resolve WebStorePricebook: ' + e.getMessage()
      );
    }

    return null;
  }

  private static Id resolveCommercePricebookEntryId(
    Id webStoreId,
    Id productId,
    Id fallbackPricebookEntryId
  ) {
    if (webStoreId == null || productId == null) {
      return fallbackPricebookEntryId;
    }

    Id storePricebookId = resolveWebStorePricebookId(webStoreId);
    if (storePricebookId == null) {
      return fallbackPricebookEntryId;
    }

    List<PricebookEntry> entries = [
      SELECT Id
      FROM PricebookEntry
      WHERE
        Pricebook2Id = :storePricebookId
        AND Product2Id = :productId
        AND IsActive = TRUE
      LIMIT 1
    ];
    return entries.isEmpty() ? fallbackPricebookEntryId : entries[0].Id;
  }

  private static Id resolvePortalCartPricebookEntryForCart(
    WebCart cart,
    Quote quote,
    Id productId
  ) {
    Id pricebookEntryId = resolvePortalCartPricebookEntryId(quote, productId);
    if (cart == null) {
      return pricebookEntryId;
    }
    return resolveCommercePricebookEntryId(
      cart.WebStoreId,
      productId,
      pricebookEntryId
    );
  }

  private static QuoteLineItem loadPrimaryQuoteLineItem(Id quoteId) {
    List<QuoteLineItem> items = loadActiveQuoteLineItems(quoteId);
    return items.isEmpty() ? null : items[0];
  }

  private static String loadQuoteRequestSequenceName(Id quoteRequestId) {
    if (quoteRequestId == null) {
      return null;
    }

    List<ABT_Quote_Request_Lineitem__c> requestLines = [
      SELECT Related_Sequence__r.Sequence_Name__c
      FROM ABT_Quote_Request_Lineitem__c
      WHERE ABT_Quote_Request__c = :quoteRequestId
      ORDER BY CreatedDate ASC
      LIMIT 1
    ];
    if (requestLines.isEmpty()) {
      return null;
    }
    ABT_Quote_Request_Lineitem__c requestLine = requestLines[0];
    if (requestLine.Related_Sequence__r != null) {
      return requestLine.Related_Sequence__r.Sequence_Name__c;
    }
    return null;
  }

  private static String readQuoteLineItemSequenceName(QuoteLineItem lineItem) {
    if (lineItem == null) {
      return null;
    }

    if (
      lineItem.Related_Sequence__r != null &&
      String.isNotBlank(lineItem.Related_Sequence__r.Sequence_Name__c)
    ) {
      return lineItem.Related_Sequence__r.Sequence_Name__c;
    }

    return null;
  }

  private static String resolvePortalCartItemName(
    Id productId,
    Id quoteId,
    Id quoteRequestId
  ) {
    QuoteLineItem primaryQli = loadPrimaryQuoteLineItem(quoteId);
    String quoteLineSequenceName = readQuoteLineItemSequenceName(primaryQli);
    if (String.isNotBlank(quoteLineSequenceName)) {
      return quoteLineSequenceName.left(255);
    }

    String requestSequenceName = loadQuoteRequestSequenceName(quoteRequestId);
    if (String.isNotBlank(requestSequenceName)) {
      return requestSequenceName.left(255);
    }

    if (productId != null) {
      List<Product2> products = [
        SELECT Name
        FROM Product2
        WHERE Id = :productId
        LIMIT 1
      ];
      if (!products.isEmpty() && String.isNotBlank(products[0].Name)) {
        return products[0].Name.left(255);
      }
    }

    if (quoteId != null) {
      List<Quote> quotes = [
        SELECT Name, QuoteNumber
        FROM Quote
        WHERE Id = :quoteId
        LIMIT 1
      ];
      if (!quotes.isEmpty()) {
        if (String.isNotBlank(quotes[0].Name)) {
          return quotes[0].Name.left(255);
        }
        if (String.isNotBlank(quotes[0].QuoteNumber)) {
          return quotes[0].QuoteNumber.left(255);
        }
      }
    }

    return DEFAULT_CART_ITEM_NAME;
  }

  private static String resolvePortalCartQuoteItemName(
    ABT_Quote_Request__c quoteRequest,
    Quote quote
  ) {
    if (
      quoteRequest != null &&
      String.isNotBlank(quoteRequest.Ansa_Quote_Number__c)
    ) {
      return quoteRequest.Ansa_Quote_Number__c.left(255);
    }
    if (
      quoteRequest != null &&
      String.isNotBlank(quoteRequest.ABT_Customer_Project_Name__c)
    ) {
      return quoteRequest.ABT_Customer_Project_Name__c.left(255);
    }
    if (quote != null) {
      String ansaQuoteNumber = (String) quote.get('Ansa_Quote_Number__c');
      if (String.isNotBlank(ansaQuoteNumber)) {
        return ansaQuoteNumber.left(255);
      }
      String customerProjectName = (String) quote.get(
        'Customer_Project_Name__c'
      );
      if (String.isNotBlank(customerProjectName)) {
        return customerProjectName.left(255);
      }
      if (String.isNotBlank(quote.QuoteNumber)) {
        return quote.QuoteNumber.left(255);
      }
      if (String.isNotBlank(quote.Name)) {
        return quote.Name.left(255);
      }
    }
    return resolvePortalCartItemName(
      quoteRequest != null ? quoteRequest.ABT_Product__c : null,
      quote != null ? quote.Id : null,
      quoteRequest != null ? quoteRequest.Id : null
    );
  }

  private static void populateDeliveryGroupRecipient(
    CartDeliveryGroup deliveryGroup
  ) {
    if (!cartDeliveryGroupHasField('DeliverToName')) {
      return;
    }

    String recipientName = 'Portal Customer';
    Id contactId = getCurrentUserContactId();
    if (contactId != null) {
      Contact con = [
        SELECT Name, FirstName, LastName
        FROM Contact
        WHERE Id = :contactId
        LIMIT 1
      ];
      if (String.isNotBlank(con.Name)) {
        recipientName = con.Name;
      }
      if (
        cartDeliveryGroupHasField('DeliverToFirstName') &&
        String.isNotBlank(con.FirstName)
      ) {
        deliveryGroup.put('DeliverToFirstName', con.FirstName);
      }
      if (
        cartDeliveryGroupHasField('DeliverToLastName') &&
        String.isNotBlank(con.LastName)
      ) {
        deliveryGroup.put('DeliverToLastName', con.LastName);
      }
    }

    deliveryGroup.put('DeliverToName', recipientName);
    if (cartDeliveryGroupHasField('DeliverToCountry')) {
      deliveryGroup.put('DeliverToCountry', 'United States');
    }
    if (cartDeliveryGroupHasField('DeliverToCity')) {
      deliveryGroup.put('DeliverToCity', 'Emeryville');
    }
    if (cartDeliveryGroupHasField('DeliverToState')) {
      deliveryGroup.put('DeliverToState', 'California');
    }
    if (cartDeliveryGroupHasField('DeliverToPostalCode')) {
      deliveryGroup.put('DeliverToPostalCode', '94608');
    }
    if (cartDeliveryGroupHasField('DeliverToStreet')) {
      deliveryGroup.put('DeliverToStreet', '123 Main Street');
    }
  }

  private static Id createDefaultCartDeliveryGroup(Id cartId) {
    CartDeliveryGroup deliveryGroup = new CartDeliveryGroup(
      CartId = cartId,
      Name = DEFAULT_DELIVERY_GROUP_NAME
    );
    if (cartDeliveryGroupHasField('IsDefault')) {
      deliveryGroup.put('IsDefault', true);
    }
    populateDeliveryGroupRecipient(deliveryGroup);

    Database.SaveResult saveResult = Database.insert(deliveryGroup, false);
    if (!saveResult.isSuccess()) {
      Database.Error err = saveResult.getErrors()[0];
      System.debug(
        LoggingLevel.WARN,
        'Unable to create a delivery group for the commerce cart: ' +
        err.getMessage()
      );
      return null;
    }

    return saveResult.getId();
  }

  private static Id getOrCreateDefaultCartDeliveryGroup(Id cartId) {
    if (cartId == null) {
      return null;
    }

    if (usingSimulatedCommerceCart()) {
      if (testSimulatedCartDeliveryGroupId == null) {
        testSimulatedCartDeliveryGroupId = cartId;
      }
      return testSimulatedCartDeliveryGroupId;
    }

    List<CartDeliveryGroup> groups = [
      SELECT Id
      FROM CartDeliveryGroup
      WHERE CartId = :cartId
      ORDER BY CreatedDate ASC
      LIMIT 1
    ];
    if (!groups.isEmpty()) {
      return groups[0].Id;
    }

    return createDefaultCartDeliveryGroup(cartId);
  }

  private static void applyPortalCartItemPricing(
    CartItem cartItem,
    Id pricebookEntryId,
    Decimal unitPrice,
    Decimal totalPrice,
    Decimal subtotal,
    Decimal listPrice
  ) {
    if (cartItemHasField('ListPrice') && listPrice != null) {
      cartItem.put('ListPrice', listPrice);
    }
    if (cartItemHasField('SalesPrice') && unitPrice != null) {
      cartItem.put('SalesPrice', unitPrice);
    }
    if (
      cartItemHasField('TotalPrice') &&
      (totalPrice != null ||
      unitPrice != null)
    ) {
      cartItem.put('TotalPrice', totalPrice != null ? totalPrice : unitPrice);
    }
    if (
      cartItemHasField('TotalLineAmount') &&
      (subtotal != null ||
      totalPrice != null ||
      unitPrice != null)
    ) {
      cartItem.put(
        'TotalLineAmount',
        subtotal != null
          ? subtotal
          : (totalPrice != null ? totalPrice : unitPrice)
      );
    }

    if (
      (cartItemHasField('SalesPrice') && cartItem.get('SalesPrice') != null) ||
      (cartItemHasField('TotalPrice') && cartItem.get('TotalPrice') != null)
    ) {
      return;
    }

    if (pricebookEntryId == null) {
      return;
    }

    List<PricebookEntry> entries = [
      SELECT UnitPrice
      FROM PricebookEntry
      WHERE Id = :pricebookEntryId
      LIMIT 1
    ];
    if (entries.isEmpty() || entries[0].UnitPrice == null) {
      return;
    }

    Decimal fallbackUnitPrice = entries[0].UnitPrice;
    if (cartItemHasField('ListPrice')) {
      cartItem.put('ListPrice', fallbackUnitPrice);
    }
    if (cartItemHasField('SalesPrice')) {
      cartItem.put('SalesPrice', fallbackUnitPrice);
    }
    if (cartItemHasField('TotalPrice')) {
      cartItem.put('TotalPrice', fallbackUnitPrice);
    }
    if (cartItemHasField('TotalLineAmount')) {
      cartItem.put('TotalLineAmount', fallbackUnitPrice);
    }
  }

  private static CartItem createPortalCartItem(
    WebCart cart,
    Id quoteRequestId,
    Id quoteId,
    Id productId,
    Id pricebookEntryId,
    String itemName,
    Decimal quantity,
    Decimal unitPrice,
    Decimal totalPrice,
    Decimal subtotal,
    Decimal listPrice,
    Id quoteLineItemId
  ) {
    if (usingSimulatedCommerceCart() && !testExecuteFullCartItemLogic) {
      trackSimulatedCartQuote(quoteId);
      return new CartItem(
        CartId = cart != null ? cart.Id : null,
        Quantity = 1,
        Type = 'Product'
      );
    }

    CartItem cartItem = new CartItem(
      CartId = cart != null ? cart.Id : null,
      Quantity = quantity != null && quantity > 0 ? quantity : 1,
      Type = 'Product'
    );
    if (cartItemHasField('Name')) {
      cartItem.Name = String.isNotBlank(itemName)
        ? itemName.left(255)
        : resolvePortalCartItemName(productId, quoteId, quoteRequestId);
    }
    Id deliveryGroupId = getOrCreateDefaultCartDeliveryGroup(cart.Id);
    if (deliveryGroupId != null && cartItemHasField('CartDeliveryGroupId')) {
      cartItem.CartDeliveryGroupId = deliveryGroupId;
    }
    if (productId != null && cartItemHasField('Product2Id')) {
      cartItem.Product2Id = productId;
    }
    if (pricebookEntryId != null && cartItemHasField('PricebookEntryId')) {
      cartItem.put('PricebookEntryId', pricebookEntryId);
    }
    if (quoteLineItemId != null && cartItemHasField('QuoteLineItemId')) {
      cartItem.put('QuoteLineItemId', quoteLineItemId);
    }
    applyPortalCartItemPricing(
      cartItem,
      pricebookEntryId,
      unitPrice,
      totalPrice,
      subtotal,
      listPrice
    );
    cartItem.put('ABT_Quote_Request__c', quoteRequestId);
    cartItem.put('ABT_Quote__c', quoteId);

    // Coverage/deploy hook: exercise field population without requiring real B2B cart DML.
    if (usingSimulatedCommerceCart() && testExecuteFullCartItemLogic) {
      trackSimulatedCartQuote(quoteId);
      return cartItem;
    }

    Database.SaveResult saveResult = Database.insert(cartItem, false);
    if (!saveResult.isSuccess()) {
      Database.Error err = saveResult.getErrors()[0];
      throw new AuraHandledException(
        CART_ITEM_CREATE_ERROR + ' ' + err.getMessage()
      );
    }

    cartItem.Id = saveResult.getId();
    return cartItem;
  }

  private static CartItem createPortalCartItem(
    WebCart cart,
    Id quoteRequestId,
    Id quoteId,
    Id productId,
    Id pricebookEntryId
  ) {
    return createPortalCartItem(
      cart,
      quoteRequestId,
      quoteId,
      productId,
      pricebookEntryId,
      null,
      1,
      null,
      null,
      null,
      null,
      null
    );
  }

  private static void syncPortalCartShippingDetails(WebCart cart, Quote quote) {
    return;
  }

  private static void recreatePortalCartItemsForQuote(
    WebCart cart,
    ABT_Quote_Request__c quoteRequest,
    Quote quote
  ) {
    if (usingSimulatedCommerceCart() && !testExecuteFullCartItemLogic) {
      trackSimulatedCartQuote(quote != null ? quote.Id : null);
      return;
    }
    if (cart == null || quote == null || quote.Id == null) {
      return;
    }

    Id cartId = cart.Id;
    Id quoteId = quote.Id;
    if (cartId != null) {
      List<SObject> existingRows = Database.query(
        'SELECT Id FROM CartItem WHERE CartId = :cartId AND ABT_Quote__c = :quoteId'
      );
      if (!existingRows.isEmpty()) {
        delete existingRows;
      }
    }

    List<QuoteLineItem> quoteLineItems = loadActiveQuoteLineItems(quote.Id);
    List<ABT_Quote_Request_Lineitem__c> requestLines = loadQuoteRequestLines(
      quoteRequest != null ? quoteRequest.Id : null
    );
    Decimal productSubtotal = quoteProductSubtotal(
      quote,
      quoteLineItems,
      requestLines
    );
    if (!quoteLineItems.isEmpty()) {
      QuoteLineItem primaryQli = quoteLineItems[0];
      Decimal quantity = quoteLineItems.size();
      if (
        quantity == 1 &&
        primaryQli.Quantity != null &&
        primaryQli.Quantity > 0
      ) {
        quantity = primaryQli.Quantity;
      }
      Id cartPricebookEntryId = resolvePortalCartPricebookEntryForCart(
        cart,
        quote,
        primaryQli.Product2Id
      );
      if (cartPricebookEntryId == null) {
        cartPricebookEntryId = primaryQli.PricebookEntryId;
      }
      createPortalCartItem(
        cart,
        quoteRequest != null ? quoteRequest.Id : null,
        quote.Id,
        primaryQli.Product2Id,
        cartPricebookEntryId,
        resolvePortalCartQuoteItemName(quoteRequest, quote),
        quantity,
        primaryQli.UnitPrice,
        productSubtotal,
        productSubtotal,
        primaryQli.ListPrice,
        primaryQli.Id
      );
      syncPortalCartShippingDetails(cart, quote);
      return;
    }

    if (!requestLines.isEmpty()) {
      Id productId = resolvePortalCartProductId(quoteRequest, quote);
      Id pricebookEntryId = resolvePortalCartPricebookEntryForCart(
        cart,
        quote,
        productId
      );
      createPortalCartItem(
        cart,
        quoteRequest != null ? quoteRequest.Id : null,
        quote.Id,
        productId,
        pricebookEntryId,
        resolvePortalCartQuoteItemName(quoteRequest, quote),
        requestLines.size(),
        null,
        productSubtotal,
        productSubtotal,
        null,
        null
      );
      syncPortalCartShippingDetails(cart, quote);
      return;
    }

    Id productId = resolvePortalCartProductId(quoteRequest, quote);
    Id pricebookEntryId = resolvePortalCartPricebookEntryId(quote, productId);
    createPortalCartItem(
      cart,
      quoteRequest != null ? quoteRequest.Id : null,
      quote.Id,
      productId,
      pricebookEntryId,
      resolvePortalCartQuoteItemName(quoteRequest, quote),
      1,
      null,
      productSubtotal,
      productSubtotal,
      null,
      null
    );
    syncPortalCartShippingDetails(cart, quote);
  }

  /**
   * Cart / checkout product total is the sum of Quote Line Item sales prices
   * (DNA + SC-001 + GS-001). Inner Scale_Up_Price__c / Glycerol_Price__c on the
   * DNA line are ignored so they are not added on top of those children.
   */
  @TestVisible
  private static Decimal quoteProductSubtotal(
    Quote quote,
    List<QuoteLineItem> quoteLineItems
  ) {
    return quoteProductSubtotal(quote, quoteLineItems, null);
  }

  @TestVisible
  private static Decimal quoteProductSubtotal(
    Quote quote,
    List<QuoteLineItem> quoteLineItems,
    List<ABT_Quote_Request_Lineitem__c> requestLines
  ) {
    // requestLines kept for callers; inner QRLI Scale Up / Glycerol are not sales prices.
    return quoteLineProductSubtotal(quote, quoteLineItems);
  }

  private static Decimal quoteLineProductSubtotal(
    Quote quote,
    List<QuoteLineItem> quoteLineItems
  ) {
    if (quoteLineItems == null || quoteLineItems.isEmpty()) {
      if (quote != null && quote.TotalPrice != null) {
        return quote.TotalPrice;
      }
      return (quote != null && quote.Subtotal != null) ? quote.Subtotal : 0;
    }

    Decimal total = 0;
    for (QuoteLineItem qli : quoteLineItems) {
      total += quoteLineItemAmount(qli);
    }
    return total;
  }

  private static Decimal quoteLineItemAmount(QuoteLineItem qli) {
    if (qli == null) {
      return 0;
    }
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
    return 0;
  }

  @TestVisible
  private static Boolean isGlycerolStockProductLine(QuoteLineItem qli) {
    if (qli == null) {
      return false;
    }
    String sku = null;
    String name = null;
    if (qli.Product2 != null) {
      sku = qli.Product2.StockKeepingUnit;
      name = qli.Product2.Name;
    }
    if (String.isNotBlank(sku)) {
      String normalized = sku.trim().toUpperCase();
      if (
        normalized == 'GS-001' ||
        normalized == 'GS-096' ||
        normalized.startsWith('GS-001')
      ) {
        return true;
      }
    }
    if (String.isNotBlank(name) && name.toLowerCase().contains('glycerol')) {
      return true;
    }
    return false;
  }

  @TestVisible
  private static Boolean isScaleUpProductLine(QuoteLineItem qli) {
    if (qli == null) {
      return false;
    }
    String sku = null;
    String name = null;
    if (qli.Product2 != null) {
      sku = qli.Product2.StockKeepingUnit;
      name = qli.Product2.Name;
    }
    if (String.isNotBlank(sku)) {
      String normalized = sku.trim().toUpperCase();
      if (normalized == 'SC-001' || normalized == 'CS-200') {
        return true;
      }
    }
    return String.isNotBlank(name) && name.toLowerCase().contains('scale up');
  }

  private static List<ABT_Quote_Request__c> loadLegacyFlaggedQuoteRequests(
    Id currentContactId
  ) {
    if (currentContactId == null) {
      return new List<ABT_Quote_Request__c>();
    }

    return [
      SELECT
        Id,
        ABT_Quote__c,
        ABT_Product__c,
        ABT_Customer_Project_Name__c,
        Ansa_Quote_Number__c
      FROM ABT_Quote_Request__c
      WHERE
        ABT_Added_to_Cart__c = TRUE
        AND ABT_Quote__c != NULL
        AND (ABT_Quote__r.ContactId = :currentContactId
        OR ABT_Quote__r.Opportunity.ContactId = :currentContactId)
    ];
  }

  private static void ensureLegacyCartItemsBackfilled(
    WebCart cart,
    List<ABT_Quote_Request__c> legacyRows
  ) {
    if (cart == null || legacyRows == null || legacyRows.isEmpty()) {
      return;
    }

    Set<Id> quoteIds = new Set<Id>();
    for (ABT_Quote_Request__c row : legacyRows) {
      quoteIds.add(row.ABT_Quote__c);
    }

    Map<Id, Quote> quotesById = new Map<Id, Quote>(
      [
        SELECT
          Id,
          Name,
          QuoteNumber,
          Ansa_Quote_Number__c,
          Customer_Project_Name__c,
          Pricebook2Id,
          ShippingHandling,
          ABT_Shipping_Method__c,
          Subtotal,
          TotalPrice
        FROM Quote
        WHERE Id IN :quoteIds
      ]
    );

    for (ABT_Quote_Request__c row : legacyRows) {
      if (!quotesById.containsKey(row.ABT_Quote__c)) {
        continue;
      }

      try {
        Quote quote = quotesById.get(row.ABT_Quote__c);
        recreatePortalCartItemsForQuote(cart, row, quote);
      } catch (Exception e) {
        System.debug(
          LoggingLevel.WARN,
          'Unable to backfill legacy cart item for quote request ' +
            row.Id +
            ': ' +
            e.getMessage()
        );
      }
    }
  }

  private static List<Quote> queryPortalQuotesByIds(
    Id currentContactId,
    List<Id> orderedQuoteIds
  ) {
    if (
      currentContactId == null ||
      orderedQuoteIds == null ||
      orderedQuoteIds.isEmpty()
    ) {
      return new List<Quote>();
    }

    Set<Id> requestedIds = new Set<Id>(orderedQuoteIds);

    String quoteQuery =
      'SELECT Id, QuoteNumber, Ansa_Quote_Number__c, Name, Status, AccountId, Account.Name, ' +
      'OpportunityId, Opportunity.Name, Opportunity.AccountId, Opportunity.ContactId, ContactId, ' +
      'Subtotal, TotalPrice, GrandTotal, ShippingHandling, ABT_Shipping_Method__c, Description, ' +
      'CreatedDate, LastModifiedDate';

    Map<String, Schema.SObjectField> quoteFields = Schema.SObjectType.Quote.fields.getMap();
    if (quoteFields.containsKey('Customer_Project_Name__c')) {
      quoteQuery += ', Customer_Project_Name__c';
    }
    if (quoteFields.containsKey('Product_Type__c')) {
      quoteQuery += ', Product_Type__c';
    }
    if (quoteFields.containsKey('Discount__c')) {
      quoteQuery += ', Discount__c';
    }
    if (quoteFields.containsKey('Discount_Amount__c')) {
      quoteQuery += ', Discount_Amount__c';
    }

    quoteQuery +=
      ', (SELECT Id, Product2Id, Product2.Name, Product2.StockKeepingUnit, Quantity, UnitPrice, ' +
      'TotalPrice, Subtotal, Description, ListPrice ';

    Map<String, Schema.SObjectField> qliFields = Schema.SObjectType.QuoteLineItem.fields.getMap();
    if (qliFields.containsKey('Sequence_Name__c')) {
      quoteQuery += ', Sequence_Name__c';
    }
    if (qliFields.containsKey('Sequence__c')) {
      quoteQuery += ', Sequence__c';
    }
    if (qliFields.containsKey('Sequence_Length__c')) {
      quoteQuery += ', Sequence_Length__c';
    }
    if (qliFields.containsKey('GC_Content__c')) {
      quoteQuery += ', GC_Content__c';
    }
    if (qliFields.containsKey('Tranche__c')) {
      quoteQuery += ', Tranche__c';
    }
    if (qliFields.containsKey('Scale__c')) {
      quoteQuery += ', Scale__c';
    }
    if (qliFields.containsKey('Purification__c')) {
      quoteQuery += ', Purification__c';
    }
    if (qliFields.containsKey('was_deleted__c')) {
      quoteQuery += ', Was_Deleted__c';
    }
    if (qliFields.containsKey('related_sequence__c')) {
      quoteQuery +=
        ', ' + ABT_SequenceSyncService.PORTAL_LINE_ITEM_SEQUENCE_SUBQUERY;
    }
    if (qliFields.containsKey('scale_up_price__c')) {
      quoteQuery += ', Scale_Up_Price__c';
    }
    if (qliFields.containsKey('glycerol_price__c')) {
      quoteQuery += ', Glycerol_Price__c';
    }
    if (qliFields.containsKey('scale_up__c')) {
      quoteQuery += ', Scale_Up__c';
    }

    quoteQuery += ' FROM QuoteLineItems';
    if (qliFields.containsKey('was_deleted__c')) {
      quoteQuery += ' WHERE (Was_Deleted__c = false OR Was_Deleted__c = null)';
    }
    quoteQuery +=
      ' ORDER BY CreatedDate ASC) ' +
      'FROM Quote ' +
      'WHERE (ContactId = :currentContactId OR Opportunity.ContactId = :currentContactId) ' +
      'AND Status IN (\'Presented\', \'Approved\') ' +
      'AND Id IN :requestedIds ' +
      'AND Id NOT IN (SELECT QuoteId FROM Order WHERE QuoteId != null)';

    List<Quote> rawQuotes = Database.query(quoteQuery);
    Map<Id, Quote> byId = new Map<Id, Quote>(rawQuotes);
    List<Quote> ordered = new List<Quote>();
    for (Id quoteId : orderedQuoteIds) {
      if (byId.containsKey(quoteId)) {
        ordered.add(byId.get(quoteId));
      }
    }
    return ordered;
  }

  private static List<Id> mergePreferredQuoteOrder(
    List<Id> preferredOrder,
    List<Id> sourceOrder,
    Boolean includeRemainder
  ) {
    List<Id> ordered = new List<Id>();
    Set<Id> seen = new Set<Id>();

    if (preferredOrder != null) {
      for (Id quoteId : preferredOrder) {
        if (
          quoteId != null &&
          sourceOrder != null &&
          sourceOrder.contains(quoteId) &&
          !seen.contains(quoteId)
        ) {
          ordered.add(quoteId);
          seen.add(quoteId);
        }
      }
    }

    if (includeRemainder && sourceOrder != null) {
      for (Id quoteId : sourceOrder) {
        if (quoteId != null && !seen.contains(quoteId)) {
          ordered.add(quoteId);
          seen.add(quoteId);
        }
      }
    }

    return ordered;
  }

  /**
   * Quote Ids currently on the portal WebCart. preferredOrder wins when the LWC
   * already knows the display order; otherwise we use CartItem CreatedDate order.
   */
  public static List<Id> getOrderedPortalCommerceCartQuoteIds(
    List<Id> preferredOrder
  ) {
    if (usingLegacyTestOverride()) {
      return mergePreferredQuoteOrder(
        preferredOrder,
        new List<Id>(testCartQuoteIdsOverride),
        preferredOrder == null || preferredOrder.isEmpty()
      );
    }

    WebCart cart = getPortalWebCart(false);

    List<Id> sourceOrder = new List<Id>();
    Set<Id> seen = new Set<Id>();
    if (cart != null) {
      Id cartKey = cart.Id;
      for (SObject row : loadPortalCartItems(cartKey)) {
        Id quoteId;
        if (row.getSObjectType() == Quote.SObjectType) {
          quoteId = row.Id;
        } else {
          quoteId = (Id) row.get('ABT_Quote__c');
        }
        if (quoteId != null && !seen.contains(quoteId)) {
          sourceOrder.add(quoteId);
          seen.add(quoteId);
        }
      }
    }

    return mergePreferredQuoteOrder(
      preferredOrder,
      sourceOrder,
      preferredOrder == null || preferredOrder.isEmpty()
    );
  }

  /**
   * Backfill CartItems from the old ABT_Added_to_Cart__c flag (pre-WebCart portal).
   * Returns true if anything was added so the LWC can refresh.
   */
  public static Boolean syncLegacyPortalCommerceCart() {
    if (usingLegacyTestOverride()) {
      List<Id> before = new List<Id>(testCartQuoteIdsOverride);
      List<Id> merged = getOrderedPortalCommerceCartQuoteIds(null);
      testCartQuoteIdsOverride = merged;
      return before.size() != merged.size();
    }

    Id currentContactId = getCurrentUserContactId();
    List<ABT_Quote_Request__c> legacyRows = loadLegacyFlaggedQuoteRequests(
      currentContactId
    );
    if (legacyRows.isEmpty()) {
      return false;
    }

    WebCart cart = getOrCreatePortalWebCart();
    Set<Id> quoteIds = new Set<Id>();
    for (ABT_Quote_Request__c row : legacyRows) {
      quoteIds.add(row.ABT_Quote__c);
    }
    Integer beforeCount = loadPortalCartItemIdByQuoteId(cart.Id, quoteIds)
      .size();
    ensureLegacyCartItemsBackfilled(cart, legacyRows);
    Integer afterCount = loadPortalCartItemIdByQuoteId(cart.Id, quoteIds)
      .size();
    return afterCount > beforeCount;
  }

  /**
   * Quotes currently sitting on this user's Active WebCart, as Quote records
   * the cart LWC can render.
   */
  public static List<Quote> getPortalCommerceCart(String userId) {
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

      List<Id> quoteIds = getOrderedPortalCommerceCartQuoteIds(null);
      return queryPortalQuotesByIds(currentUser.ContactId, quoteIds);
    } catch (Exception e) {
      throw new AuraHandledException(
        'Unable to fetch commerce cart: ' + e.getMessage()
      );
    }
  }

  /**
   * Add the QR's Quote as a CartItem. Owner check is against Contact / Opp Contact.
   * Sets Quote to Presented if it wasn't already (so CX sees it as in-cart).
   */
  public static void addQuoteRequestToCommerceCart(Id quoteRequestId) {
    try {
      if (quoteRequestId == null) {
        throw new AuraHandledException('Quote Request ID is required.');
      }

      ABT_Quote_Request__c quoteRequest = [
        SELECT
          Id,
          ABT_Quote__c,
          ABT_Product__c,
          ABT_Added_to_Cart__c,
          Ansa_Quote_Number__c,
          ABT_Customer_Project_Name__c
        FROM ABT_Quote_Request__c
        WHERE Id = :quoteRequestId
        LIMIT 1
      ];

      if (quoteRequest.ABT_Quote__c == null) {
        throw new AuraHandledException(
          'No quote is ready for checkout yet. If you just submitted a quote request, please wait for Ansa\'s team to process it before checking out.'
        );
      }

      Quote quote = [
        SELECT
          Id,
          Name,
          QuoteNumber,
          Ansa_Quote_Number__c,
          Customer_Project_Name__c,
          Status,
          ContactId,
          Pricebook2Id,
          Opportunity.ContactId,
          ShippingHandling,
          ABT_Shipping_Method__c,
          Subtotal,
          TotalPrice
        FROM Quote
        WHERE Id = :quoteRequest.ABT_Quote__c
        LIMIT 1
      ];

      if (!usingLegacyTestOverride() && !usingSimulatedCommerceCart()) {
        Id currentContactId = getCurrentUserContactId();
        Id opportunityContactId = quote.Opportunity != null
          ? quote.Opportunity.ContactId
          : null;
        Boolean isOwner =
          currentContactId != null &&
          (currentContactId == quote.ContactId ||
          currentContactId == opportunityContactId);
        if (!isOwner) {
          throw new AuraHandledException(
            'You do not have permission to add this quote to the cart.'
          );
        }
      }

      Boolean alreadyInCart = false;
      if (usingLegacyTestOverride()) {
        alreadyInCart = testCartQuoteIdsOverride.contains(quote.Id);
      } else if (usingSimulatedCommerceCart()) {
        alreadyInCart = testSimulatedCartQuoteIds.contains(quote.Id);
      } else {
        WebCart existingCart = getPortalWebCart(false);
        if (existingCart != null) {
          alreadyInCart = !loadPortalCartItemIdByQuoteId(
              existingCart.Id,
              new Set<Id>{ quote.Id }
            )
            .isEmpty();
        }
      }

      if (usingLegacyTestOverride()) {
        if (!testCartQuoteIdsOverride.contains(quote.Id)) {
          testCartQuoteIdsOverride.add(quote.Id);
        }
      } else {
        WebCart cart = getOrCreatePortalWebCart();
        recreatePortalCartItemsForQuote(cart, quoteRequest, quote);
      }

      List<SObject> updates = new List<SObject>();
      if (quoteRequest.ABT_Added_to_Cart__c != true) {
        updates.add(
          new ABT_Quote_Request__c(
            Id = quoteRequest.Id,
            ABT_Added_to_Cart__c = true
          )
        );
      }
      if (
        !alreadyInCart &&
        quote.Status != 'Presented' &&
        quote.Status != 'Approved' &&
        quote.Status != 'Ordered'
      ) {
        updates.add(new Quote(Id = quote.Id, Status = 'Presented'));
      }
      if (!updates.isEmpty()) {
        update updates;
      }
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      throw new AuraHandledException(
        'Unable to add quote to cart: ' + e.getMessage()
      );
    }
  }

  /**
   * Drop the CartItem and clear ABT_Added_to_Cart__c. Returns false if the QR
   * wasn't found (LWC treats that as already gone).
   */
  public static Boolean removeQuoteRequestFromCommerceCart(Id quoteRequestId) {
    try {
      if (quoteRequestId == null) {
        return false;
      }

      List<ABT_Quote_Request__c> requests = [
        SELECT Id, ABT_Quote__c, ABT_Added_to_Cart__c
        FROM ABT_Quote_Request__c
        WHERE Id = :quoteRequestId
        LIMIT 1
      ];
      if (requests.isEmpty()) {
        return false;
      }

      ABT_Quote_Request__c request = requests[0];
      if (usingLegacyTestOverride()) {
        if (request.ABT_Quote__c != null) {
          List<Id> remaining = new List<Id>();
          for (Id quoteId : testCartQuoteIdsOverride) {
            if (quoteId != request.ABT_Quote__c) {
              remaining.add(quoteId);
            }
          }
          testCartQuoteIdsOverride = remaining;
        }
      } else {
        if (usingSimulatedCommerceCart() && request.ABT_Quote__c != null) {
          untrackSimulatedCartQuote(request.ABT_Quote__c);
        } else {
          List<SObject> cartRows = new List<SObject>();
          WebCart cart = getPortalWebCart(false);
          if (cart != null) {
            Id cartId = cart.Id;
            cartRows = Database.query(
              'SELECT Id FROM CartItem WHERE CartId = :cartId AND ABT_Quote_Request__c = :quoteRequestId'
            );
            if (cartRows.isEmpty() && request.ABT_Quote__c != null) {
              Id requestQuoteId = request.ABT_Quote__c;
              cartRows = Database.query(
                'SELECT Id FROM CartItem WHERE CartId = :cartId AND ABT_Quote__c = :requestQuoteId'
              );
            }
          }

          if (!cartRows.isEmpty()) {
            delete cartRows;
          }
        }
      }

      if (request.ABT_Added_to_Cart__c == true) {
        update new ABT_Quote_Request__c(
          Id = request.Id,
          ABT_Added_to_Cart__c = false
        );
      }
      return request.ABT_Quote__c != null;
    } catch (Exception e) {
      throw new AuraHandledException(
        'Unable to remove quote from cart: ' + e.getMessage()
      );
    }
  }

  /**
   * After portal checkout: keep CartItems for investigation, mark the cart Closed,
   * and link it to the created Order so CX can audit what checked out.
   * A new Active cart is created lazily on the next getOrCreatePortalWebCart call.
   */
  public static void clearCheckedOutCartItems(Set<Id> quoteIds) {
    clearCheckedOutCartItems(quoteIds, null);
  }

  /**
   * After portal checkout: close the cart and keep CartItems for CX. Stamps Order__c
   * when we already have the Id so the closed cart is auditable.
   */
  public static void clearCheckedOutCartItems(Set<Id> quoteIds, Id orderId) {
    if (quoteIds == null || quoteIds.isEmpty()) {
      return;
    }

    if (usingLegacyTestOverride()) {
      List<Id> remaining = new List<Id>();
      for (Id cartQuoteId : testCartQuoteIdsOverride) {
        if (!quoteIds.contains(cartQuoteId)) {
          remaining.add(cartQuoteId);
        }
      }
      testCartQuoteIdsOverride = remaining;
      return;
    }

    if (usingSimulatedCommerceCart()) {
      for (Id quoteId : quoteIds) {
        untrackSimulatedCartQuote(quoteId);
      }
      if (testSimulatedWebCart != null) {
        testSimulatedWebCart.Status = 'Closed';
        if (orderId != null) {
          testSimulatedWebCart.put('Order__c', orderId);
        }
      }
      return;
    }

    WebCart cart = getPortalWebCart(false);
    if (cart == null) {
      return;
    }

    Id linkedOrderId = orderId != null
      ? orderId
      : resolveOrderIdForQuotes(quoteIds);
    closeCartForInvestigation(cart.Id, linkedOrderId);
  }

  /**
   * When quotes are ordered outside portal checkout, close any Active/Checkout carts
   * that still contain those quotes. Keep CartItems for investigation; do not delete them.
   */
  public static void clearCartItemsForQuotes(Set<Id> quoteIds) {
    if (quoteIds == null || quoteIds.isEmpty()) {
      return;
    }

    if (usingLegacyTestOverride()) {
      List<Id> remaining = new List<Id>();
      for (Id cartQuoteId : testCartQuoteIdsOverride) {
        if (!quoteIds.contains(cartQuoteId)) {
          remaining.add(cartQuoteId);
        }
      }
      testCartQuoteIdsOverride = remaining;
      return;
    }

    if (usingSimulatedCommerceCart()) {
      for (Id quoteId : quoteIds) {
        untrackSimulatedCartQuote(quoteId);
      }
      if (testSimulatedWebCart != null) {
        testSimulatedWebCart.Status = 'Closed';
      }
      return;
    }

    List<SObject> cartItems = Database.query(
      'SELECT Id, CartId FROM CartItem WHERE ABT_Quote__c IN :quoteIds AND CartId != null'
    );
    if (cartItems.isEmpty()) {
      return;
    }

    Set<Id> cartIds = new Set<Id>();
    for (SObject cartItem : cartItems) {
      Id cartId = (Id) cartItem.get('CartId');
      if (cartId != null) {
        cartIds.add(cartId);
      }
    }

    List<WebCart> openCarts = [
      SELECT Id
      FROM WebCart
      WHERE Id IN :cartIds AND Status IN ('Active', 'Checkout')
    ];
    if (openCarts.isEmpty()) {
      return;
    }

    Id linkedOrderId = resolveOrderIdForQuotes(quoteIds);
    for (WebCart openCart : openCarts) {
      closeCartForInvestigation(openCart.Id, linkedOrderId);
    }
  }

  private static void closeCartForInvestigation(Id cartId, Id orderId) {
    if (cartId == null) {
      return;
    }

    WebCart cartUpdate = new WebCart(Id = cartId, Status = 'Closed');
    if (
      orderId != null &&
      Schema.sObjectType.WebCart.fields.getMap().containsKey('order__c')
    ) {
      cartUpdate.put('Order__c', orderId);
    }
    update cartUpdate;
  }

  private static Id resolveOrderIdForQuotes(Set<Id> quoteIds) {
    if (quoteIds == null || quoteIds.isEmpty()) {
      return null;
    }
    if (!Schema.sObjectType.Quote.fields.getMap().containsKey('order__c')) {
      return null;
    }

    List<Quote> quotes = Database.query(
      'SELECT Order__c FROM Quote WHERE Id IN :quoteIds AND Order__c != null LIMIT 1'
    );
    if (quotes.isEmpty()) {
      return null;
    }
    return (Id) quotes[0].get('Order__c');
  }

  /**
   * Shipping is stored on Quote now. Left as a no-op so older Flow/Apex callers
   * still compile after the field move.
   */
  public static void syncPortalCartShippingForQuotes(Set<Id> quoteIds) {
    return;
  }

  /** When true, simulated cart mode still executes full recreate/create item logic. */
  @TestVisible
  private static Boolean testExecuteFullCartItemLogic = false;

  @TestVisible
  private static void resetSimulatedCommerceCartState() {
    testSimulateCommerceDml = false;
    testExecuteFullCartItemLogic = false;
    testSimulatedWebCart = null;
    testSimulatedCartQuoteIds = new List<Id>();
    testSimulatedCartDeliveryGroupId = null;
  }

  @TestVisible
  private static List<Quote> testQueryPortalQuotesByIds(
    Id contactId,
    List<Id> quoteIds
  ) {
    return queryPortalQuotesByIds(contactId, quoteIds);
  }

  @TestVisible
  private static void testRunLegacyBackfill(
    WebCart cart,
    List<ABT_Quote_Request__c> legacyRows
  ) {
    ensureLegacyCartItemsBackfilled(cart, legacyRows);
  }

  @TestVisible
  private static Id testResolvePortalCartProductId(
    ABT_Quote_Request__c quoteRequest,
    Quote quote
  ) {
    return resolvePortalCartProductId(quoteRequest, quote);
  }

  @TestVisible
  private static Id testResolvePortalCartPricebookEntryId(
    Quote quote,
    Id productId
  ) {
    return resolvePortalCartPricebookEntryId(quote, productId);
  }

  @TestVisible
  private static Id testResolveCommercePricebookEntryId(
    Id webStoreId,
    Id productId,
    Id fallbackPricebookEntryId
  ) {
    return resolveCommercePricebookEntryId(
      webStoreId,
      productId,
      fallbackPricebookEntryId
    );
  }

  @TestVisible
  private static Id testResolvePortalCartPricebookEntryForCart(
    WebCart cart,
    Quote quote,
    Id productId
  ) {
    return resolvePortalCartPricebookEntryForCart(cart, quote, productId);
  }

  @TestVisible
  private static QuoteLineItem testLoadPrimaryQuoteLineItem(Id quoteId) {
    return loadPrimaryQuoteLineItem(quoteId);
  }

  @TestVisible
  private static String testReadQuoteLineItemSequenceName(
    QuoteLineItem lineItem
  ) {
    return readQuoteLineItemSequenceName(lineItem);
  }

  @TestVisible
  private static WebCart testGetPortalWebCart(Boolean createIfMissing) {
    return getPortalWebCart(createIfMissing);
  }

  @TestVisible
  private static List<Id> testMergePreferredQuoteOrder(
    List<Id> preferredOrder,
    List<Id> sourceOrder,
    Boolean includeRemainder
  ) {
    return mergePreferredQuoteOrder(
      preferredOrder,
      sourceOrder,
      includeRemainder
    );
  }

  @TestVisible
  private static Id testResolvePortalWebStoreId() {
    return resolvePortalWebStoreId();
  }

  @TestVisible
  private static Boolean testCartItemHasField(String fieldApiName) {
    return cartItemHasField(fieldApiName);
  }

  @TestVisible
  private static Id testGetCurrentUserAccountId() {
    return getCurrentUserAccountId();
  }

  @TestVisible
  private static void testTrackSimulatedCartQuote(Id quoteId) {
    trackSimulatedCartQuote(quoteId);
  }

  @TestVisible
  private static void testUntrackSimulatedCartQuote(Id quoteId) {
    untrackSimulatedCartQuote(quoteId);
  }

  @TestVisible
  private static Map<Id, Id> testLoadPortalCartItemIdByQuoteId(
    Id cartId,
    Set<Id> quoteIds
  ) {
    return loadPortalCartItemIdByQuoteId(cartId, quoteIds);
  }

  @TestVisible
  private static List<SObject> testLoadPortalCartItems(Id cartId) {
    return loadPortalCartItems(cartId);
  }

  @TestVisible
  private static List<ABT_Quote_Request__c> testLoadLegacyFlaggedQuoteRequests(
    Id contactId
  ) {
    return loadLegacyFlaggedQuoteRequests(contactId);
  }

  @TestVisible
  private static WebCart testCreatePortalWebCart(Id accountId, Id webStoreId) {
    return createPortalWebCart(accountId, webStoreId);
  }

  @TestVisible
  private static CartItem testCreatePortalCartItem(
    WebCart cart,
    Id quoteRequestId,
    Id quoteId,
    Id productId,
    Id pricebookEntryId
  ) {
    return createPortalCartItem(
      cart,
      quoteRequestId,
      quoteId,
      productId,
      pricebookEntryId
    );
  }

  @TestVisible
  private static void testRecreatePortalCartItemsForQuote(
    WebCart cart,
    ABT_Quote_Request__c quoteRequest,
    Quote quote
  ) {
    recreatePortalCartItemsForQuote(cart, quoteRequest, quote);
  }

  @TestVisible
  private static Id testGetOrCreateDefaultCartDeliveryGroup(Id cartId) {
    return getOrCreateDefaultCartDeliveryGroup(cartId);
  }

  @TestVisible
  private static String testResolvePortalCartItemName(
    Id productId,
    Id quoteId,
    Id quoteRequestId
  ) {
    return resolvePortalCartItemName(productId, quoteId, quoteRequestId);
  }

  @TestVisible
  private static String testResolvePortalCartQuoteItemName(
    ABT_Quote_Request__c quoteRequest,
    Quote quote
  ) {
    return resolvePortalCartQuoteItemName(quoteRequest, quote);
  }

  @TestVisible
  private static String testBuildPortalCartName(Id accountId) {
    return buildPortalCartName(accountId);
  }

  @TestVisible
  private static void testApplyPortalCartItemPricing(
    CartItem cartItem,
    Id pricebookEntryId,
    Id quoteId
  ) {
    QuoteLineItem qli = loadPrimaryQuoteLineItem(quoteId);
    applyPortalCartItemPricing(
      cartItem,
      pricebookEntryId,
      qli != null ? qli.UnitPrice : null,
      qli != null ? qli.TotalPrice : null,
      qli != null ? qli.Subtotal : null,
      qli != null ? qli.ListPrice : null
    );
  }

  @TestVisible
  private static void testCloseCartForInvestigation(Id cartId, Id orderId) {
    closeCartForInvestigation(cartId, orderId);
  }

  @TestVisible
  private static Id testResolveOrderIdForQuotes(Set<Id> quoteIds) {
    return resolveOrderIdForQuotes(quoteIds);
  }

  @TestVisible
  private static void testPopulateDeliveryGroupRecipient(
    CartDeliveryGroup deliveryGroup
  ) {
    populateDeliveryGroupRecipient(deliveryGroup);
  }

  @TestVisible
  private static Boolean testCartDeliveryGroupHasField(String fieldApiName) {
    return cartDeliveryGroupHasField(fieldApiName);
  }
}
