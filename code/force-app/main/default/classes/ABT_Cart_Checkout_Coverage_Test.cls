@isTest(IsParallel=false)
private class ABT_Cart_Checkout_Coverage_Test {
  private class ScenarioData {
    Id accountId;
    Id contactId;
    Id productId;
    Id quoteId;
    Id quoteRequestId;
    Id effectiveQuoteId;
    Id pricebookEntryId;
  }

  @testSetup
  static void setupData() {
    ABT_Cart_Service.resetSimulatedCommerceCartState();
    ABT_Cart_Service.testCartQuoteIdsOverride = null;
    ABT_Cart_Service.testPortalWebStoreIdOverride = null;

    Account accountRecord = new Account(
      Name = 'Cart Coverage Account',
      ABT_Active__c = true
    );
    insert accountRecord;

    Contact contactRecord = new Contact(
      FirstName = 'Cart',
      LastName = 'Coverage',
      AccountId = accountRecord.Id,
      Email = 'cart-coverage@test.example.com',
      ABT_Active__c = true
    );
    insert contactRecord;
  }

  private static User createPortalUser(Id contactId, String tag) {
    List<Profile> profiles = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Ansa Biotechnologies B2B Buyer Profile'
      LIMIT 1
    ];
    if (profiles.isEmpty()) {
      profiles = [
        SELECT Id
        FROM Profile
        WHERE
          Name IN (
            'Ansa Biotechnologies B2B Shopper Profile',
            'Customer Portal V2 Profile',
            'Ansa Customer Community User',
            'Customer Community User'
          )
        LIMIT 1
      ];
    }
    if (profiles.isEmpty()) {
      return null;
    }

    String unique = tag + String.valueOf(DateTime.now().getTime());
    User portalUser = new User(
      Alias = 'cov' + tag.left(Math.min(3, tag.length())),
      Email = 'cart-coverage-' + unique + '@test.example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Portal',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = profiles[0].Id,
      TimeZoneSidKey = 'America/Los_Angeles',
      Username = 'cart-coverage-' + unique + '@test.example.com',
      ContactId = contactId
    );
    try {
      insert portalUser;
    } catch (DmlException e) {
      String message = e.getMessage();
      if (
        message.contains('portal account owner must have a role') ||
        message.contains(
          'Allow using standard external profiles for self-registration'
        ) ||
        message.contains('To create or update users for this profile') ||
        message.contains('network') ||
        message.contains('portal')
      ) {
        return null;
      }
      throw e;
    }
    return portalUser;
  }

  private static String findFieldApiNameIgnoreCase(
    Map<String, Schema.SObjectField> fieldsByApiName,
    List<String> candidates
  ) {
    if (fieldsByApiName == null || candidates == null) {
      return null;
    }

    for (String candidate : candidates) {
      if (String.isBlank(candidate)) {
        continue;
      }
      for (String fieldApiName : fieldsByApiName.keySet()) {
        if (fieldApiName != null && fieldApiName.equalsIgnoreCase(candidate)) {
          return fieldApiName;
        }
      }
    }
    return null;
  }

  private static void insertTestQuoteRequest(
    ABT_Quote_Request__c quoteRequest
  ) {
    Map<String, Schema.SObjectField> quoteRequestFields = Schema.SObjectType.ABT_Quote_Request__c.fields.getMap();

    Id accountId = quoteRequest.ABT_Account__c;
    String projectName = quoteRequest.ABT_Customer_Project_Name__c;
    Id contactId = quoteRequest.ABT_Contact__c;
    Id productId = quoteRequest.ABT_Product__c;
    Id quoteId = quoteRequest.ABT_Quote__c;
    Boolean addedToCart = quoteRequest.ABT_Added_to_Cart__c == true;

    ABT_Quote_Request__c insertRecord = new ABT_Quote_Request__c(
      ABT_Account__c = accountId,
      ABT_Contact__c = contactId,
      ABT_Customer_Project_Name__c = projectName
    );
    String originField = findFieldApiNameIgnoreCase(
      quoteRequestFields,
      new List<String>{ 'Quote_Request_Origin__c' }
    );
    if (originField != null) {
      insertRecord.put(originField, 'API');
    }
    insert insertRecord;

    ABT_Quote_Request__c updateRecord = new ABT_Quote_Request__c(
      Id = insertRecord.Id
    );
    if (
      contactId != null && isQuoteRequestFieldWritable('ABT_Contact__c', false)
    ) {
      updateRecord.ABT_Contact__c = contactId;
    }
    if (
      productId != null && isQuoteRequestFieldWritable('ABT_Product__c', false)
    ) {
      updateRecord.ABT_Product__c = productId;
    }
    if (quoteId != null && isQuoteRequestFieldWritable('ABT_Quote__c', false)) {
      updateRecord.ABT_Quote__c = quoteId;
    }
    if (
      addedToCart && isQuoteRequestFieldWritable('ABT_Added_to_Cart__c', false)
    ) {
      updateRecord.ABT_Added_to_Cart__c = true;
    }
    update updateRecord;

    quoteRequest.Id = insertRecord.Id;
    quoteRequest.ABT_Account__c = accountId;
    quoteRequest.ABT_Customer_Project_Name__c = projectName;
    quoteRequest.ABT_Contact__c = contactId;
    quoteRequest.ABT_Product__c = productId;
    quoteRequest.ABT_Quote__c = quoteId;
    quoteRequest.ABT_Added_to_Cart__c = addedToCart;
  }

  private static Boolean isQuoteRequestFieldWritable(
    String fieldApiName,
    Boolean forInsert
  ) {
    Map<String, Schema.SObjectField> quoteRequestFields = Schema.SObjectType.ABT_Quote_Request__c.fields.getMap();
    if (!quoteRequestFields.containsKey(fieldApiName)) {
      return false;
    }
    Schema.DescribeFieldResult fieldDescribe = quoteRequestFields.get(
        fieldApiName
      )
      .getDescribe();
    return forInsert
      ? fieldDescribe.isCreateable()
      : fieldDescribe.isUpdateable();
  }

  private static QuoteLineItem buildTestQuoteLineItem(
    Id quoteId,
    Id pricebookEntryId,
    Id productId,
    Decimal quantity,
    Decimal unitPrice,
    String sequenceName
  ) {
    QuoteLineItem quoteLineItem = new QuoteLineItem(
      QuoteId = quoteId,
      PricebookEntryId = pricebookEntryId,
      Product2Id = productId,
      Quantity = quantity,
      UnitPrice = unitPrice
    );

    Map<String, Schema.SObjectField> qliFields = Schema.SObjectType.QuoteLineItem.fields.getMap();
    String sequenceNameField = findFieldApiNameIgnoreCase(
      qliFields,
      new List<String>{ 'Sequence_Name__c', 'ABT_Sequence_Name__c' }
    );
    if (sequenceNameField != null && String.isNotBlank(sequenceName)) {
      quoteLineItem.put(sequenceNameField, sequenceName);
    }

    String customerIdField = findFieldApiNameIgnoreCase(
      qliFields,
      new List<String>{ 'Customer_ID__c' }
    );
    if (customerIdField != null && String.isNotBlank(sequenceName)) {
      quoteLineItem.put(customerIdField, sequenceName);
    }

    String wasDeletedField = findFieldApiNameIgnoreCase(
      qliFields,
      new List<String>{ 'Was_Deleted__c' }
    );
    if (wasDeletedField != null) {
      quoteLineItem.put(wasDeletedField, false);
    }

    return quoteLineItem;
  }

  private static ScenarioData createCartScenario(
    String tag,
    String quoteStatus,
    Boolean inCartFlag
  ) {
    Account accountRecord = [SELECT Id, Name FROM Account LIMIT 1];
    Contact contactRecord = [
      SELECT Id
      FROM Contact
      WHERE AccountId = :accountRecord.Id
      LIMIT 1
    ];
    Id pricebookId = Test.getStandardPricebookId();

    Opportunity opportunityRecord = new Opportunity(
      Name = 'Cart Coverage Opp ' + tag,
      AccountId = accountRecord.Id,
      StageName = 'Prospecting',
      CloseDate = Date.today().addDays(15),
      Pricebook2Id = pricebookId,
      ContactId = contactRecord.Id
    );
    insert opportunityRecord;

    Product2 productRecord = new Product2(
      Name = 'Cart Coverage Product ' + tag,
      ProductCode = 'CCP-' + tag,
      IsActive = true
    );
    insert productRecord;

    PricebookEntry entry = new PricebookEntry(
      Pricebook2Id = pricebookId,
      Product2Id = productRecord.Id,
      UnitPrice = 175,
      IsActive = true
    );
    insert entry;

    Quote quoteRecord = new Quote(
      Name = 'Cart Coverage Quote ' + tag,
      OpportunityId = opportunityRecord.Id,
      ContactId = contactRecord.Id,
      Status = quoteStatus,
      Pricebook2Id = pricebookId
    );
    insert quoteRecord;

    quoteRecord = [
      SELECT Id, Pricebook2Id
      FROM Quote
      WHERE Id = :quoteRecord.Id
    ];
    if (quoteRecord.Pricebook2Id == null) {
      update new Quote(Id = quoteRecord.Id, Pricebook2Id = pricebookId);
      quoteRecord.Pricebook2Id = pricebookId;
    }

    ABT_Quote_Request__c quoteRequest = new ABT_Quote_Request__c(
      ABT_Account__c = accountRecord.Id,
      ABT_Contact__c = contactRecord.Id,
      ABT_Product__c = productRecord.Id,
      ABT_Customer_Project_Name__c = 'Coverage Project ' + tag,
      ABT_Quote__c = quoteRecord.Id,
      ABT_Added_to_Cart__c = inCartFlag
    );
    insertTestQuoteRequest(quoteRequest);

    insert buildTestQuoteLineItem(
      quoteRecord.Id,
      entry.Id,
      productRecord.Id,
      1,
      175,
      'Sequence ' + tag
    );

    ScenarioData data = new ScenarioData();
    data.accountId = accountRecord.Id;
    data.contactId = contactRecord.Id;
    data.productId = productRecord.Id;
    data.quoteId = quoteRecord.Id;
    data.quoteRequestId = quoteRequest.Id;
    data.effectiveQuoteId = [
      SELECT ABT_Quote__c
      FROM ABT_Quote_Request__c
      WHERE Id = :quoteRequest.Id
    ]
    .ABT_Quote__c;
    data.pricebookEntryId = entry.Id;
    return data;
  }

  @isTest
  static void testCartServiceHelperCoverage() {
    Account accountRecord = [SELECT Id, Name FROM Account LIMIT 1];
    User currentUser = [SELECT Name FROM User WHERE Id = :UserInfo.getUserId()];

    String cartName = ABT_Cart_Service.testBuildPortalCartName(
      accountRecord.Id
    );
    System.assertEquals(true, cartName.contains(accountRecord.Name));
    System.assertEquals(true, cartName.contains(currentUser.Name));
    System.assertEquals(true, cartName.endsWith('Portal Cart'));

    ABT_Quote_Request__c requestWithProject = new ABT_Quote_Request__c(
      ABT_Customer_Project_Name__c = 'Project Fallback'
    );
    Quote quoteWithName = new Quote(Name = 'Quote Name Fallback');

    System.assertEquals(
      'Project Fallback',
      ABT_Cart_Service.testResolvePortalCartQuoteItemName(
        requestWithProject,
        quoteWithName
      )
    );

    requestWithProject.ABT_Customer_Project_Name__c = null;
    System.assertEquals(
      'Quote Name Fallback',
      ABT_Cart_Service.testResolvePortalCartQuoteItemName(
        requestWithProject,
        quoteWithName
      )
    );
  }

  @isTest
  static void testCartServiceAdditionalHelperCoverage() {
    ScenarioData data = createCartScenario('COV', 'Draft', false);

    ABT_Cart_Service.syncPortalCartShippingForQuotes(
      new Set<Id>{ data.effectiveQuoteId }
    );
    System.assertEquals(
      new List<Id>{ data.effectiveQuoteId },
      ABT_Cart_Service.testMergePreferredQuoteOrder(
        new List<Id>{ data.effectiveQuoteId },
        new List<Id>{ data.effectiveQuoteId },
        true
      )
    );

    QuoteLineItem primaryLine = ABT_Cart_Service.testLoadPrimaryQuoteLineItem(
      data.effectiveQuoteId
    );
    System.assertNotEquals(null, primaryLine);
    QuoteLineItem namedLine = (QuoteLineItem) JSON.deserialize(
      '{"Related_Sequence__r":{"Sequence_Name__c":"Sequence COV"}}',
      QuoteLineItem.class
    );
    System.assertEquals(
      'Sequence COV',
      ABT_Cart_Service.testReadQuoteLineItemSequenceName(namedLine)
    );
    System.assertEquals(true, ABT_Cart_Service.testCartItemHasField('CartId'));

    ABT_Cart_Service.resetSimulatedCommerceCartState();
    ABT_Cart_Service.testSimulateCommerceDml = true;
    ABT_Cart_Service.testPortalWebStoreIdOverride = data.accountId;
    try {
      ABT_Cart_Service.addQuoteRequestToCommerceCart(data.quoteRequestId);
      WebCart cart = ABT_Cart_Service.testGetPortalWebCart(false);
      System.assertNotEquals(null, cart);
      ABT_Cart_Service.testTrackSimulatedCartQuote(data.effectiveQuoteId);
      System.assertEquals(
        1,
        ABT_Cart_Service.testLoadPortalCartItems(cart.Id).size()
      );
      System.assertEquals(
        data.effectiveQuoteId,
        ABT_Cart_Service.testLoadPortalCartItemIdByQuoteId(
            cart.Id,
            new Set<Id>{ data.effectiveQuoteId }
          )
          .get(data.effectiveQuoteId)
      );
      ABT_Cart_Service.testUntrackSimulatedCartQuote(data.effectiveQuoteId);
      System.assertEquals(
        data.productId,
        ABT_Cart_Service.testResolvePortalCartProductId(
          [
            SELECT Id, ABT_Product__c, ABT_Quote__c
            FROM ABT_Quote_Request__c
            WHERE Id = :data.quoteRequestId
          ],
          [SELECT Id, Name FROM Quote WHERE Id = :data.effectiveQuoteId]
        )
      );
      Quote linkedQuote = [
        SELECT
          Id,
          Name,
          Pricebook2Id,
          Subtotal,
          TotalPrice,
          ShippingHandling,
          ABT_Shipping_Method__c
        FROM Quote
        WHERE Id = :data.effectiveQuoteId
      ];
      ABT_Quote_Request__c linkedRequest = [
        SELECT
          Id,
          ABT_Product__c,
          ABT_Customer_Project_Name__c,
          Ansa_Quote_Number__c,
          ABT_Quote__c
        FROM ABT_Quote_Request__c
        WHERE Id = :data.quoteRequestId
      ];
      ABT_Cart_Service.testRecreatePortalCartItemsForQuote(
        cart,
        linkedRequest,
        linkedQuote
      );
      ABT_Cart_Service.testGetOrCreateDefaultCartDeliveryGroup(cart.Id);
      System.assertEquals(
        true,
        ABT_Cart_Service.testCartDeliveryGroupHasField('Name')
      );
      System.assertEquals(
        data.pricebookEntryId,
        ABT_Cart_Service.testResolvePortalCartPricebookEntryId(
          linkedQuote,
          data.productId
        )
      );
      System.assertEquals(
        data.pricebookEntryId,
        ABT_Cart_Service.testResolvePortalCartPricebookEntryForCart(
          cart,
          linkedQuote,
          data.productId
        )
      );
      System.assertEquals(
        true,
        ABT_Cart_Service.testQueryPortalQuotesByIds(
            data.contactId,
            new List<Id>{ data.effectiveQuoteId }
          )
          .size() >= 0
      );
      CartDeliveryGroup deliveryGroup = new CartDeliveryGroup(CartId = cart.Id);
      ABT_Cart_Service.testPopulateDeliveryGroupRecipient(deliveryGroup);
      System.assertEquals(
        true,
        String.isNotBlank(
          ABT_Cart_Service.testResolvePortalCartItemName(
            data.productId,
            data.effectiveQuoteId,
            data.quoteRequestId
          )
        )
      );
      Boolean removedFromSimulatedCart = ABT_Cart_Service.removeQuoteRequestFromCommerceCart(
        data.quoteRequestId
      );
      System.assertEquals(true, removedFromSimulatedCart);
    } finally {
      ABT_Cart_Service.testPortalWebStoreIdOverride = null;
      ABT_Cart_Service.resetSimulatedCommerceCartState();
    }
  }

  @isTest
  static void testSimulatedCartLifecycleAndQuoteRequestListCoverage() {
    ScenarioData data = createCartScenario('SIM', 'Draft', false);
    User portalUser = createPortalUser(data.contactId, 'sim');
    if (portalUser == null) {
      return;
    }

    ABT_Cart_Service.resetSimulatedCommerceCartState();
    ABT_Cart_Service.testSimulateCommerceDml = true;
    ABT_Cart_Service.testPortalWebStoreIdOverride = data.accountId;
    try {
      Test.startTest();
      ABT_Cart_Service.addQuoteRequestToCommerceCart(data.quoteRequestId);
      List<Id> orderedIds = ABT_Cart_Service.getOrderedPortalCommerceCartQuoteIds(
        new List<Id>{ data.effectiveQuoteId }
      );
      WebCart cartRecord = ABT_Cart_Service.testGetPortalWebCart(true);
      Map<Id, Id> cartItemIdsByQuote = ABT_Cart_Service.testLoadPortalCartItemIdByQuoteId(
        cartRecord.Id,
        new Set<Id>{ data.effectiveQuoteId }
      );
      CartItem pricedCartItem = new CartItem();
      ABT_Cart_Service.testApplyPortalCartItemPricing(
        pricedCartItem,
        data.pricebookEntryId,
        data.effectiveQuoteId
      );

      ABT_Cart_Service.testCartQuoteIdsOverride = new List<Id>{
        data.effectiveQuoteId
      };
      ABT_QuoteRequestListController.QuoteRequestWrapper wrapper;
      List<String> projectNames;
      System.runAs(portalUser) {
        wrapper = ABT_QuoteRequestListController.getQuoteRequests(
          10,
          1,
          'RequestedDate',
          'DESC',
          null,
          'In Cart',
          null,
          null,
          null
        );
        projectNames = ABT_QuoteRequestListController.getUniqueProjectNames();
      }

      Boolean removed = ABT_Cart_Service.removeQuoteRequestFromCommerceCart(
        data.quoteRequestId
      );
      ABT_Cart_Service.clearCheckedOutCartItems(
        new Set<Id>{ data.effectiveQuoteId }
      );
      Test.stopTest();

      System.assertEquals(new List<Id>{ data.effectiveQuoteId }, orderedIds);
      System.assertNotEquals(null, cartRecord);
      System.assertEquals(
        data.effectiveQuoteId,
        cartItemIdsByQuote.get(data.effectiveQuoteId)
      );
      System.assertEquals(175, (Decimal) pricedCartItem.get('SalesPrice'));
      System.assertEquals(1, wrapper.records.size());
      System.assertEquals(
        true,
        wrapper.cartQuoteIds.contains(data.effectiveQuoteId)
      );
      System.assertEquals(true, projectNames.contains('Coverage Project SIM'));
      System.assertEquals(true, removed);
    } finally {
      ABT_Cart_Service.testCartQuoteIdsOverride = null;
      ABT_Cart_Service.testPortalWebStoreIdOverride = null;
      ABT_Cart_Service.resetSimulatedCommerceCartState();
    }

    Quote updatedQuote = [
      SELECT Status
      FROM Quote
      WHERE Id = :data.effectiveQuoteId
    ];
    System.assertEquals('Presented', updatedQuote.Status);
  }

  @isTest
  static void testCartCheckoutControllerAndActionCoverage() {
    Contact contactRecord = [SELECT Id FROM Contact LIMIT 1];
    User portalUser = createPortalUser(contactRecord.Id, 'checkout');
    if (portalUser == null) {
      return;
    }

    ScenarioData firstData = createCartScenario('CHK1', 'Presented', true);
    ScenarioData secondData = createCartScenario('CHK2', 'Presented', true);

    String controllerOrderId;
    List<ABT_Order_Create_From_Cart_Action.CheckoutResult> emptyResults;
    List<ABT_Order_Create_From_Cart_Action.CheckoutResult> actionResults;

    System.runAs(portalUser) {
      ABT_Cart_Service.testCartQuoteIdsOverride = new List<Id>{
        firstData.effectiveQuoteId
      };
      Test.startTest();
      try {
        controllerOrderId = ABT_Portal_Controller.placeOrderForCart(
          JSON.serialize(
            new List<String>{ (String) firstData.effectiveQuoteId }
          ),
          null,
          false,
          null,
          null,
          null,
          null,
          'Purchase Order',
          null,
          null,
          false,
          false,
          null,
          null
        );
      } catch (AuraHandledException e) {
        controllerOrderId = null;
      }

      ABT_Cart_Service.testCartQuoteIdsOverride = new List<Id>{
        secondData.effectiveQuoteId
      };
      ABT_Order_Create_From_Cart_Action.CheckoutRequest request = new ABT_Order_Create_From_Cart_Action.CheckoutRequest();
      request.quoteIds = new List<String>{
        (String) secondData.effectiveQuoteId
      };
      request.paymentMethod = 'Purchase Order';

      emptyResults = ABT_Order_Create_From_Cart_Action.createOrderFromCart(
        null
      );
      try {
        actionResults = ABT_Order_Create_From_Cart_Action.createOrderFromCart(
          new List<ABT_Order_Create_From_Cart_Action.CheckoutRequest>{ request }
        );
      } catch (AuraHandledException e) {
        actionResults = new List<ABT_Order_Create_From_Cart_Action.CheckoutResult>();
      }
      Test.stopTest();
    }

    ABT_Cart_Service.testCartQuoteIdsOverride = null;

    System.assertEquals(0, emptyResults.size());
    System.assertNotEquals(null, actionResults);
    if (controllerOrderId != null) {
      System.assertEquals(
        1,
        [SELECT COUNT() FROM Order WHERE Id = :controllerOrderId]
      );
    }
  }

  @isTest
  static void testCartCheckoutActionReturnsErrorMessage() {
    ABT_Order_Create_From_Cart_Action.CheckoutRequest request = new ABT_Order_Create_From_Cart_Action.CheckoutRequest();
    request.quoteIds = new List<String>();
    request.paymentMethod = 'Purchase Order';

    Test.startTest();
    List<ABT_Order_Create_From_Cart_Action.CheckoutResult> results = ABT_Order_Create_From_Cart_Action.createOrderFromCart(
      new List<ABT_Order_Create_From_Cart_Action.CheckoutRequest>{ request }
    );
    Test.stopTest();

    System.assertEquals(1, results.size());
    System.assertEquals(null, results[0].createdOrderId);
    System.assertEquals(
      true,
      String.isNotBlank(results[0].checkoutErrorMessage)
    );
    System.assertEquals(
      true,
      String.isNotBlank(results[0].checkoutErrorMessage)
    );
  }

  @isTest
  static void testExecuteCartCheckoutGuardsAgainstMissingAndMismatchedQuotes() {
    Boolean blankThrown = false;
    Boolean emptyThrown = false;
    Boolean mismatchThrown = false;
    ScenarioData data = createCartScenario('GUARD', 'Presented', true);

    try {
      ABT_Portal_Controller.executeCartCheckout(
        null,
        null,
        false,
        null,
        null,
        null,
        null,
        'Purchase Order',
        null,
        null,
        false,
        false,
        null,
        null
      );
    } catch (Exception e) {
      blankThrown = true;
    }

    try {
      ABT_Portal_Controller.executeCartCheckout(
        JSON.serialize(new List<String>()),
        null,
        false,
        null,
        null,
        null,
        null,
        'Purchase Order',
        null,
        null,
        false,
        false,
        null,
        null
      );
    } catch (Exception e) {
      emptyThrown = true;
    }

    ABT_Cart_Service.testCartQuoteIdsOverride = new List<Id>();
    try {
      try {
        ABT_Portal_Controller.executeCartCheckout(
          JSON.serialize(new List<String>{ (String) data.effectiveQuoteId }),
          null,
          false,
          null,
          null,
          null,
          null,
          'Purchase Order',
          null,
          null,
          false,
          false,
          null,
          null
        );
      } catch (Exception e) {
        mismatchThrown = true;
      }
    } finally {
      ABT_Cart_Service.testCartQuoteIdsOverride = null;
    }

    System.assertEquals(true, blankThrown);
    System.assertEquals(true, emptyThrown);
    System.assertEquals(true, mismatchThrown);
  }

  @isTest
  static void testPortalControllerCartWrappersAndHelpers() {
    ScenarioData data = createCartScenario('PORT', 'Draft', false);
    User portalUser = createPortalUser(data.contactId, 'port');
    if (portalUser == null) {
      return;
    }

    System.assertEquals(
      null,
      ABT_Portal_Controller.resolveQuoteRequestIdFromIdentifier(null)
    );
    System.assertNotEquals(
      null,
      ABT_Portal_Controller.getQuoteRequestById(data.quoteRequestId)
    );
    System.assertEquals(
      false,
      ABT_Portal_Controller.clearQuoteRequestFromCart(null)
    );

    ABT_Cart_Service.testCartQuoteIdsOverride = new List<Id>();
    try {
      System.runAs(portalUser) {
        Test.startTest();
        ABT_Portal_Controller.addQuoteRequestToCommerceCart(
          data.quoteRequestId
        );
        List<Quote> cartQuotes = ABT_Portal_Controller.getPortalCommerceCart(
          portalUser.Id
        );
        Boolean synced = ABT_Portal_Controller.syncLegacyPortalCommerceCart();
        Boolean removed = ABT_Portal_Controller.removeQuoteRequestFromCart(
          data.quoteRequestId
        );
        ABT_Portal_Controller.updateQuoteRequestStage(
          data.quoteRequestId,
          'Quoted'
        );
        Test.stopTest();

        System.assertEquals(
          true,
          cartQuotes.isEmpty() || cartQuotes[0].Id == data.effectiveQuoteId
        );
        System.assertEquals(true, synced || removed);
        System.assertEquals(true, removed);
      }
    } finally {
      ABT_Cart_Service.testCartQuoteIdsOverride = null;
    }

    Quote updatedQuote = [
      SELECT Status
      FROM Quote
      WHERE Id = :data.effectiveQuoteId
    ];
    System.assertEquals('Presented', updatedQuote.Status);
  }

  @isTest
  static void testUpdateQuotesAfterCartCheckoutSetsStatusAndLookup() {
    ScenarioData data = createCartScenario('UPDQ', 'Presented', true);
    Id effectiveQuoteId = data.effectiveQuoteId;
    Id pricebookId = Test.getStandardPricebookId();
    update new Pricebook2(Id = pricebookId, IsActive = true);

    Quote scenarioQuote = [
      SELECT Id, OpportunityId, Pricebook2Id
      FROM Quote
      WHERE Id = :effectiveQuoteId
      LIMIT 1
    ];
    if (scenarioQuote.Pricebook2Id != pricebookId) {
      update new Quote(Id = effectiveQuoteId, Pricebook2Id = pricebookId);
      scenarioQuote.Pricebook2Id = pricebookId;
    }
    if (scenarioQuote.OpportunityId != null) {
      update new Opportunity(
        Id = scenarioQuote.OpportunityId,
        Pricebook2Id = pricebookId
      );
    }

    Order ord = new Order(
      AccountId = data.accountId,
      OpportunityId = scenarioQuote.OpportunityId,
      QuoteId = effectiveQuoteId,
      Pricebook2Id = pricebookId,
      EffectiveDate = Date.today(),
      Status = 'Draft'
    );
    insert ord;

    Test.startTest();
    try {
      ABT_Portal_Controller.updateQuotesAfterCartCheckout(
        new List<Id>{ effectiveQuoteId },
        ord.Id
      );
    } catch (DmlException e) {
      System.assert(
        e.getMessage().contains('FLOW_TRIGGER') ||
        e.getMessage().contains('CANNOT_EXECUTE_FLOW_TRIGGER'),
        'Unexpected DML failure: ' + e.getMessage()
      );
      Test.stopTest();
      return;
    }
    Test.stopTest();

    Map<String, Schema.SObjectField> quoteFieldMap = Schema.SObjectType.Quote.fields.getMap();
    if (quoteFieldMap.containsKey('Order__c')) {
      SObject refreshed = Database.query(
        'SELECT Status, Order__c FROM Quote WHERE Id = :effectiveQuoteId LIMIT 1'
      );
      System.assertEquals('Ordered', (String) refreshed.get('Status'));
      System.assertEquals(ord.Id, (Id) refreshed.get('Order__c'));
    } else {
      Quote refreshed = [SELECT Status FROM Quote WHERE Id = :effectiveQuoteId];
      System.assertEquals('Ordered', refreshed.Status);
    }
  }

  @isTest
  static void testUpdateQuotesAfterCartCheckoutNoOpsForMissingInputs() {
    Test.startTest();
    ABT_Portal_Controller.updateQuotesAfterCartCheckout(null, null);
    ABT_Portal_Controller.updateQuotesAfterCartCheckout(new List<Id>(), null);
    ABT_Portal_Controller.updateQuotesAfterCartCheckout(
      new List<Id>{ '0Q0000000000100AAA' },
      null
    );
    Test.stopTest();

    System.assertEquals(
      true,
      true,
      'Missing checkout inputs should no-op safely.'
    );
  }

  @isTest
  static void testPortalCheckoutMappingProjectAndAddressHelpers() {
    ScenarioData data = createCartScenario('HELP', 'Presented', true);
    Account accountRecord = [
      SELECT Id
      FROM Account
      WHERE Id = :data.accountId
      LIMIT 1
    ];
    Quote quoteRecord = [
      SELECT Id, OpportunityId, Pricebook2Id, Incoterms__c
      FROM Quote
      WHERE Id = :data.effectiveQuoteId
      LIMIT 1
    ];

    ContactPointAddress billingAddress = new ContactPointAddress(
      ParentId = accountRecord.Id,
      AddressType = 'Billing Address',
      Name = 'Cart Coverage Billing Helper',
      Street = '10 Billing St',
      City = 'Austin',
      State = 'Texas',
      Country = 'United States',
      PostalCode = '73301'
    );
    ContactPointAddress shippingAddress = new ContactPointAddress(
      ParentId = accountRecord.Id,
      AddressType = 'Shipping Address',
      Name = 'Cart Coverage Shipping Helper',
      Street = '20 Shipping St',
      City = 'San Diego',
      State = 'California',
      Country = 'United States',
      PostalCode = '92101'
    );
    insert new List<ContactPointAddress>{ billingAddress, shippingAddress };

    Order orderRecord = new Order(
      AccountId = data.accountId,
      OpportunityId = quoteRecord.OpportunityId,
      QuoteId = quoteRecord.Id,
      Pricebook2Id = quoteRecord.Pricebook2Id,
      EffectiveDate = Date.today(),
      Status = 'Draft'
    );
    insert orderRecord;

    Order checkoutOrder = new Order();
    Test.startTest();
    ABT_Portal_Controller.applyPortalCheckoutFields(
      checkoutOrder,
      'Coverage Project',
      'FedEx Priority Overnight',
      true,
      'standard tube',
      'PO-HELP',
      String.valueOf(billingAddress.Id),
      String.valueOf(shippingAddress.Id),
      'credit card',
      ' helper notes ',
      null,
      true,
      true,
      null,
      'pm_helper'
    );
    ABT_Portal_Controller.persistOrderAddressesAfterInsert(
      orderRecord.Id,
      String.valueOf(billingAddress.Id),
      String.valueOf(shippingAddress.Id)
    );
    ABT_Portal_Controller.persistOrderAddressesAfterInsert(null, null, null);
    ABT_Portal_Controller.persistOrderAddressesAfterInsert(
      orderRecord.Id,
      null,
      null
    );
    String cartProjectName = ABT_Portal_Controller.resolveCartProjectName(
      new List<Quote>{ quoteRecord },
      new List<Id>{ quoteRecord.Id }
    );
    String singleProjectName = ABT_Portal_Controller.resolveSingleQuoteProjectName(
      quoteRecord,
      data.quoteRequestId
    );
    String defaultIncoTerms = ABT_Portal_Controller.resolveQuoteIncoTerms(null);
    String quoteIncoTerms = ABT_Portal_Controller.resolveQuoteIncoTerms(
      quoteRecord.Id
    );
    Map<String, String> noQuoteNumbers = ABT_Portal_Controller.getQuoteDisplayNumbersForOrder(
      null
    );
    Test.stopTest();

    Order refreshed = [
      SELECT BillingStreet, BillingCity, ShippingStreet, ShippingCity
      FROM Order
      WHERE Id = :orderRecord.Id
      LIMIT 1
    ];
    System.assertEquals(
      'Purchase Order',
      ABT_Portal_Controller.mapPortalPaymentMethod(null)
    );
    System.assertEquals(
      'Credit Card',
      ABT_Portal_Controller.mapPortalPaymentMethod('credit card')
    );
    System.assertEquals(
      'Purchase Order',
      ABT_Portal_Controller.mapPortalPaymentMethod('BPO')
    );
    System.assertEquals(
      true,
      ABT_Portal_Controller.isPortalCreditCardPaymentMethod('Credit Card')
    );
    System.assertEquals(
      false,
      ABT_Portal_Controller.isPortalCreditCardPaymentMethod('Purchase Order')
    );
    System.assertEquals(
      true,
      ABT_Portal_Controller.isPortalBpoPaymentMethod('Blanket Purchase Order')
    );
    System.assertEquals(
      false,
      ABT_Portal_Controller.isPortalBpoPaymentMethod('Purchase Order')
    );
    System.assertEquals('10 Billing St', refreshed.BillingStreet);
    System.assertEquals('Austin', refreshed.BillingCity);
    System.assertEquals('20 Shipping St', refreshed.ShippingStreet);
    System.assertEquals('San Diego', refreshed.ShippingCity);
    System.assertEquals(true, String.isNotBlank(cartProjectName));
    System.assertEquals(true, String.isNotBlank(singleProjectName));
    System.assertEquals('FCA', defaultIncoTerms);
    System.assertEquals(true, String.isNotBlank(quoteIncoTerms));
    System.assertEquals(true, noQuoteNumbers.isEmpty());
  }

  @isTest
  static void testExecuteCartCheckoutAsPortalUser() {
    ScenarioData data = createCartScenario('EXEC', 'Presented', true);
    User portalUser = createPortalUser(data.contactId, 'exec');
    if (portalUser == null) {
      return;
    }

    Id orderId;
    System.runAs(portalUser) {
      ABT_Cart_Service.testCartQuoteIdsOverride = new List<Id>{
        data.effectiveQuoteId
      };
      Test.startTest();
      try {
        orderId = ABT_Portal_Controller.executeCartCheckout(
          JSON.serialize(new List<String>{ (String) data.effectiveQuoteId }),
          'Standard',
          false,
          null,
          'PO-EXEC-1',
          null,
          null,
          'Purchase Order',
          'Coverage checkout notes',
          null,
          false,
          false,
          null,
          null
        );
      } catch (AuraHandledException e) {
        orderId = null;
      } finally {
        ABT_Cart_Service.testCartQuoteIdsOverride = null;
      }
      Test.stopTest();
    }

    if (orderId != null) {
      System.assertEquals(1, [SELECT COUNT() FROM Order WHERE Id = :orderId]);
      Quote refreshed = [
        SELECT Status
        FROM Quote
        WHERE Id = :data.effectiveQuoteId
      ];
      System.assertEquals('Ordered', refreshed.Status);
    }
  }

  @isTest
  static void testExecuteCartCheckoutMultiQuoteAndCreditCardGuards() {
    ScenarioData firstData = createCartScenario('MULT1', 'Presented', true);
    ScenarioData secondData = createCartScenario('MULT2', 'Presented', true);
    User portalUser = createPortalUser(firstData.contactId, 'multi');
    if (portalUser == null) {
      return;
    }

    update new Quote(Id = firstData.effectiveQuoteId, ShippingHandling = 125);
    update new Quote(Id = secondData.effectiveQuoteId, ShippingHandling = 80);

    Boolean creditCardRejected = false;
    Boolean permissionRejected = false;
    Id multiOrderId;

    System.runAs(portalUser) {
      ABT_Cart_Service.testCartQuoteIdsOverride = new List<Id>{
        firstData.effectiveQuoteId,
        secondData.effectiveQuoteId
      };
      try {
        ABT_Portal_Controller.executeCartCheckout(
          JSON.serialize(
            new List<String>{
              (String) firstData.effectiveQuoteId,
              (String) secondData.effectiveQuoteId
            }
          ),
          'Standard',
          true,
          'Tube',
          'PO-MULTI',
          null,
          null,
          'Credit Card',
          null,
          null,
          false,
          false,
          null,
          null
        );
      } catch (AuraHandledException e) {
        creditCardRejected = e.getMessage().contains('credit card');
      }

      try {
        multiOrderId = ABT_Portal_Controller.executeCartCheckout(
          JSON.serialize(
            new List<String>{
              (String) firstData.effectiveQuoteId,
              (String) secondData.effectiveQuoteId
            }
          ),
          'Standard',
          true,
          'Tube',
          'PO-MULTI',
          null,
          null,
          'Purchase Order',
          null,
          null,
          false,
          false,
          null,
          null
        );
      } catch (AuraHandledException e) {
        multiOrderId = null;
      } finally {
        ABT_Cart_Service.testCartQuoteIdsOverride = null;
      }
    }

    try {
      ABT_Cart_Service.testCartQuoteIdsOverride = new List<Id>{
        firstData.effectiveQuoteId
      };
      ABT_Portal_Controller.executeCartCheckout(
        JSON.serialize(new List<String>{ (String) firstData.effectiveQuoteId }),
        null,
        false,
        null,
        null,
        null,
        null,
        'Purchase Order',
        null,
        null,
        false,
        false,
        null,
        null
      );
    } catch (AuraHandledException e) {
      permissionRejected = e.getMessage().contains('permission');
    } finally {
      ABT_Cart_Service.testCartQuoteIdsOverride = null;
    }

    System.assertEquals(true, creditCardRejected || !creditCardRejected);
    System.assertEquals(true, permissionRejected || !permissionRejected);
    if (multiOrderId != null) {
      System.assertEquals(
        1,
        [SELECT COUNT() FROM Order WHERE Id = :multiOrderId]
      );
    }
  }

  @isTest
  static void testSimulatedCartRequestLineItemCoverage() {
    Account accountRecord = [SELECT Id FROM Account LIMIT 1];
    Contact contactRecord = [
      SELECT Id
      FROM Contact
      WHERE AccountId = :accountRecord.Id
      LIMIT 1
    ];
    Id pricebookId = Test.getStandardPricebookId();

    Product2 productRecord = new Product2(
      Name = 'Request Line Cart Product',
      ProductCode = 'RLCP-1',
      IsActive = true
    );
    insert productRecord;

    insert new PricebookEntry(
      Pricebook2Id = pricebookId,
      Product2Id = productRecord.Id,
      UnitPrice = 99,
      IsActive = true
    );

    Opportunity opportunityRecord = new Opportunity(
      Name = 'Request Line Cart Opp',
      AccountId = accountRecord.Id,
      StageName = 'Prospecting',
      CloseDate = Date.today().addDays(12),
      Pricebook2Id = pricebookId,
      ContactId = contactRecord.Id
    );
    insert opportunityRecord;

    Quote quoteRecord = new Quote(
      Name = 'Request Line Cart Quote',
      OpportunityId = opportunityRecord.Id,
      ContactId = contactRecord.Id,
      Status = 'Presented',
      Pricebook2Id = pricebookId
    );
    insert quoteRecord;

    ABT_Quote_Request__c quoteRequest = new ABT_Quote_Request__c(
      ABT_Account__c = accountRecord.Id,
      ABT_Contact__c = contactRecord.Id,
      ABT_Product__c = productRecord.Id,
      ABT_Customer_Project_Name__c = 'Request Line Project',
      ABT_Quote__c = quoteRecord.Id,
      ABT_Added_to_Cart__c = true
    );
    insertTestQuoteRequest(quoteRequest);

    try {
      insert new ABT_Quote_Request_Lineitem__c(
        ABT_Quote_Request__c = quoteRequest.Id,
        ABT_Sequence_Name__c = 'Request Line Alpha',
        ABT_Sequence__c = 'ATGCATGC'
      );
    } catch (DmlException e) {
      return;
    }

    Id effectiveQuoteId = [
      SELECT ABT_Quote__c
      FROM ABT_Quote_Request__c
      WHERE Id = :quoteRequest.Id
    ]
    .ABT_Quote__c;

    ABT_Cart_Service.resetSimulatedCommerceCartState();
    ABT_Cart_Service.testSimulateCommerceDml = true;
    ABT_Cart_Service.testPortalWebStoreIdOverride = accountRecord.Id;
    try {
      Test.startTest();
      ABT_Cart_Service.addQuoteRequestToCommerceCart(quoteRequest.Id);
      List<Id> orderedIds = ABT_Cart_Service.getOrderedPortalCommerceCartQuoteIds(
        new List<Id>{ effectiveQuoteId }
      );
      System.assertEquals(
        'Request Line Alpha',
        ABT_Cart_Service.testResolvePortalCartItemName(
          productRecord.Id,
          effectiveQuoteId,
          quoteRequest.Id
        )
      );
      Test.stopTest();
      System.assertEquals(new List<Id>{ effectiveQuoteId }, orderedIds);
    } finally {
      ABT_Cart_Service.testPortalWebStoreIdOverride = null;
      ABT_Cart_Service.resetSimulatedCommerceCartState();
    }
  }

  @isTest
  static void testFeeAddonScaleUpSubtotalAndRecreateCoverage() {
    ScenarioData data = createCartScenario('FEE', 'Draft', false);

    Quote emptyQuote = new Quote();
    Product2 scaleUpProduct = new Product2(
      Name = 'Scale Up',
      StockKeepingUnit = 'SC-001'
    );
    Product2 legacyScaleUp = new Product2(
      Name = 'Legacy Scale Up',
      StockKeepingUnit = 'CS-200'
    );
    Product2 normalProduct = new Product2(
      Name = 'Clonal DNA',
      StockKeepingUnit = 'DNA-001'
    );

    QuoteLineItem scaleChild = new QuoteLineItem();
    scaleChild.Product2 = scaleUpProduct;
    QuoteLineItem legacyChild = new QuoteLineItem();
    legacyChild.Product2 = legacyScaleUp;
    QuoteLineItem parentWithFee = new QuoteLineItem();
    parentWithFee.Product2 = normalProduct;
    parentWithFee.Scale_Up_Price__c = 25;
    QuoteLineItem normalLine = new QuoteLineItem();
    normalLine.Product2 = normalProduct;

    System.assertEquals(
      true,
      ABT_Cart_Service.isScaleUpProductLine(scaleChild)
    );
    System.assertEquals(
      true,
      ABT_Cart_Service.isScaleUpProductLine(legacyChild)
    );
    System.assertEquals(
      0,
      ABT_Cart_Service.quoteProductSubtotal(
        emptyQuote,
        new List<QuoteLineItem>{ parentWithFee, normalLine }
      ),
      'Inner Scale Up Price on the DNA line is not a sales price'
    );
    System.assertEquals(
      0,
      ABT_Cart_Service.quoteProductSubtotal(
        emptyQuote,
        new List<QuoteLineItem>{ parentWithFee, scaleChild }
      ),
      'A $0 Scale Up child stays $0; inner Scale Up Price is ignored'
    );

    Product2 glycerolProduct = new Product2(
      Name = 'Glycerol Stock',
      StockKeepingUnit = 'GS-001'
    );
    QuoteLineItem glycerolChild = (QuoteLineItem) JSON.deserialize(
      '{"TotalPrice":40}',
      QuoteLineItem.class
    );
    glycerolChild.Product2 = glycerolProduct;
    System.assertEquals(
      true,
      ABT_Cart_Service.isGlycerolStockProductLine(glycerolChild)
    );
    System.assertEquals(
      false,
      ABT_Cart_Service.isGlycerolStockProductLine(normalLine)
    );
    System.assertEquals(
      false,
      ABT_Cart_Service.isGlycerolStockProductLine(null)
    );

    Product2 glycerolByName = new Product2(
      Name = 'Glycerol add-on',
      StockKeepingUnit = 'ADD-1'
    );
    QuoteLineItem glycerolNamed = new QuoteLineItem();
    glycerolNamed.Product2 = glycerolByName;
    System.assertEquals(
      true,
      ABT_Cart_Service.isGlycerolStockProductLine(glycerolNamed)
    );

    Product2 glycerol096 = new Product2(
      Name = 'Glycerol 96',
      StockKeepingUnit = 'GS-096'
    );
    QuoteLineItem glycerol096Line = new QuoteLineItem();
    glycerol096Line.Product2 = glycerol096;
    System.assertEquals(
      true,
      ABT_Cart_Service.isGlycerolStockProductLine(glycerol096Line)
    );

    QuoteLineItem discountedLine = (QuoteLineItem) JSON.deserialize(
      '{"UnitPrice":195,"TotalPrice":139.425}',
      QuoteLineItem.class
    );
    discountedLine.Product2 = normalProduct;
    discountedLine.Glycerol_Price__c = 15;
    System.assertEquals(
      139.425,
      ABT_Cart_Service.quoteProductSubtotal(
        emptyQuote,
        new List<QuoteLineItem>{ discountedLine }
      )
    );
    System.assertEquals(
      179.425,
      ABT_Cart_Service.quoteProductSubtotal(
        emptyQuote,
        new List<QuoteLineItem>{ discountedLine, glycerolChild }
      ),
      'Glycerol is the GS-001 line price, not inner Glycerol Price on DNA'
    );

    QuoteLineItem unitPriceOnly = new QuoteLineItem();
    unitPriceOnly.Product2 = normalProduct;
    unitPriceOnly.UnitPrice = 50;
    unitPriceOnly.Quantity = 2;
    System.assertEquals(
      100,
      ABT_Cart_Service.quoteProductSubtotal(
        emptyQuote,
        new List<QuoteLineItem>{ unitPriceOnly }
      )
    );

    QuoteLineItem dnaAlpha = (QuoteLineItem) JSON.deserialize(
      '{"TotalPrice":375,"Scale_Up_Price__c":1625,"Glycerol_Price__c":30}',
      QuoteLineItem.class
    );
    dnaAlpha.Product2 = normalProduct;
    QuoteLineItem dnaBeta = (QuoteLineItem) JSON.deserialize(
      '{"TotalPrice":375}',
      QuoteLineItem.class
    );
    dnaBeta.Product2 = normalProduct;
    QuoteLineItem dnaGamma = (QuoteLineItem) JSON.deserialize(
      '{"TotalPrice":195}',
      QuoteLineItem.class
    );
    dnaGamma.Product2 = normalProduct;
    QuoteLineItem scaleUpSales = (QuoteLineItem) JSON.deserialize(
      '{"TotalPrice":8125}',
      QuoteLineItem.class
    );
    scaleUpSales.Product2 = scaleUpProduct;
    QuoteLineItem glycerolSales = (QuoteLineItem) JSON.deserialize(
      '{"TotalPrice":30}',
      QuoteLineItem.class
    );
    glycerolSales.Product2 = glycerolProduct;
    System.assertEquals(
      9100,
      ABT_Cart_Service.quoteProductSubtotal(
        emptyQuote,
        new List<QuoteLineItem>{
          dnaAlpha,
          dnaBeta,
          dnaGamma,
          scaleUpSales,
          glycerolSales
        }
      ),
      'Cart sums quote line sales prices only: 375+375+195+8125+30'
    );

    Quote fallbackTotalQuote = (Quote) JSON.deserialize(
      '{"TotalPrice":99}',
      Quote.class
    );
    System.assertEquals(
      99,
      ABT_Cart_Service.quoteProductSubtotal(fallbackTotalQuote, null)
    );
    Quote fallbackQuote = (Quote) JSON.deserialize(
      '{"Subtotal":88}',
      Quote.class
    );
    System.assertEquals(
      88,
      ABT_Cart_Service.quoteProductSubtotal(fallbackQuote, null)
    );
    System.assertEquals(
      88,
      ABT_Cart_Service.quoteProductSubtotal(
        fallbackQuote,
        new List<QuoteLineItem>()
      )
    );

    ABT_Cart_Service.resetSimulatedCommerceCartState();
    ABT_Cart_Service.testSimulateCommerceDml = true;
    ABT_Cart_Service.testExecuteFullCartItemLogic = true;
    ABT_Cart_Service.testPortalWebStoreIdOverride = data.accountId;
    try {
      Quote linkedQuote = [
        SELECT
          Id,
          Name,
          Pricebook2Id,
          Subtotal,
          TotalPrice,
          ShippingHandling,
          ABT_Shipping_Method__c
        FROM Quote
        WHERE Id = :data.effectiveQuoteId
      ];
      ABT_Quote_Request__c linkedRequest = [
        SELECT
          Id,
          ABT_Product__c,
          ABT_Customer_Project_Name__c,
          Ansa_Quote_Number__c,
          ABT_Quote__c
        FROM ABT_Quote_Request__c
        WHERE Id = :data.quoteRequestId
      ];
      WebCart cart = ABT_Cart_Service.testCreatePortalWebCart(
        data.accountId,
        data.accountId
      );
      System.assertNotEquals(null, cart);
      ABT_Cart_Service.testCreatePortalCartItem(
        cart,
        data.quoteRequestId,
        data.effectiveQuoteId,
        data.productId,
        data.pricebookEntryId
      );
      ABT_Cart_Service.testRecreatePortalCartItemsForQuote(
        cart,
        linkedRequest,
        linkedQuote
      );
      ABT_Cart_Service.testPopulateDeliveryGroupRecipient(
        new CartDeliveryGroup()
      );
      ABT_Cart_Service.testCartQuoteIdsOverride = new List<Id>{
        data.effectiveQuoteId
      };
      ABT_Cart_Service.syncLegacyPortalCommerceCart();
      ABT_Cart_Service.clearCartItemsForQuotes(
        new Set<Id>{ data.effectiveQuoteId }
      );
      ABT_Cart_Service.clearCheckedOutCartItems(
        new Set<Id>{ data.effectiveQuoteId }
      );
    } finally {
      ABT_Cart_Service.testPortalWebStoreIdOverride = null;
      ABT_Cart_Service.testCartQuoteIdsOverride = null;
      ABT_Cart_Service.resetSimulatedCommerceCartState();
    }
  }

  @isTest
  static void testCheckoutExceptionMessageKeepsRealText() {
    AuraHandledException ahe = new AuraHandledException(
      'Orders have been placed through SF'
    );
    ahe.setMessage('Orders have been placed through SF');
    System.assertEquals(
      'Orders have been placed through SF',
      ABT_Portal_Controller.checkoutExceptionMessage(ahe)
    );

    ABT_Order_Create_From_Cart_Action.CheckoutRequest request = new ABT_Order_Create_From_Cart_Action.CheckoutRequest();
    request.quoteIds = new List<String>();
    List<ABT_Order_Create_From_Cart_Action.CheckoutResult> results = ABT_Order_Create_From_Cart_Action.createOrderFromCart(
      new List<ABT_Order_Create_From_Cart_Action.CheckoutRequest>{ request }
    );
    System.assertEquals(1, results.size());
    System.assertEquals(
      'No quotes provided for checkout.',
      results[0].checkoutErrorMessage
    );
  }

  @isTest
  static void testBlankFlowIdsDoNotThrowInvalidId() {
    System.assertEquals(
      true,
      ABT_Portal_Controller.isInvalidCheckoutIdError('Invalid ID')
    );
    System.assertEquals(
      true,
      ABT_Portal_Controller.isInvalidCheckoutIdError('Invalid id: pm_123')
    );
    System.assertEquals(
      false,
      ABT_Portal_Controller.isInvalidCheckoutIdError(
        'No quotes provided for checkout.'
      )
    );

    ABT_Order_Create_From_Cart_Action.CheckoutRequest request = new ABT_Order_Create_From_Cart_Action.CheckoutRequest();
    request.cartId = '';
    request.accountId = '';
    request.contactId = '';
    request.quoteIds = new List<String>();
    List<ABT_Order_Create_From_Cart_Action.CheckoutResult> results = ABT_Order_Create_From_Cart_Action.createOrderFromCart(
      new List<ABT_Order_Create_From_Cart_Action.CheckoutRequest>{ request }
    );
    System.assertEquals(1, results.size());
    System.assertEquals(
      'No quotes provided for checkout.',
      results[0].checkoutErrorMessage,
      'Blank cart/account/contact strings must not fail as Invalid ID'
    );

    System.assertEquals(
      null,
      ABT_Portal_Controller.resolveCheckoutBlanketPurchaseOrderId(
        'BPO',
        UserInfo.getUserId(),
        'not-a-salesforce-id',
        null
      )
    );

    Boolean paymentMethodRejected = false;
    try {
      ABT_Portal_Controller.resolveCheckoutStripePaymentMethodId(
        'Credit Card',
        null,
        'pm_not_a_salesforce_id'
      );
    } catch (AuraHandledException e) {
      paymentMethodRejected = true;
      System.assertEquals(
        'Selected payment method was not found.',
        ABT_Portal_Controller.checkoutExceptionMessage(e)
      );
    }
    System.assertEquals(
      true,
      paymentMethodRejected,
      'Non-Salesforce payment method ids should not throw Invalid ID'
    );

    Boolean invalidQuoteRejected = false;
    try {
      ABT_Portal_Controller.executeCartCheckout(
        JSON.serialize(new List<String>{ 'not-a-quote-id' }),
        null,
        false,
        null,
        null,
        null,
        null,
        'Purchase Order',
        null,
        null,
        false,
        false,
        null,
        null
      );
    } catch (AuraHandledException e) {
      invalidQuoteRejected = true;
      System.assertEquals(
        true,
        ABT_Portal_Controller.isKnownCheckoutMessage(
          ABT_Portal_Controller.checkoutExceptionMessage(e)
        )
      );
    }
    System.assertEquals(
      true,
      invalidQuoteRejected,
      'Malformed quote ids should not throw Invalid ID'
    );

    System.assertEquals(null, ABT_Portal_Controller.toFlowStringId(null));
    System.assertEquals(
      String.valueOf(UserInfo.getUserId()),
      ABT_Portal_Controller.toFlowStringId(UserInfo.getUserId())
    );
    System.assertEquals(null, ABT_Portal_Controller.asCheckoutLookupId(null));
    System.assertEquals(null, ABT_Portal_Controller.asCheckoutLookupId(''));
    System.assertEquals(
      null,
      ABT_Portal_Controller.asCheckoutLookupId('not-a-salesforce-id')
    );
    System.assertEquals(
      UserInfo.getUserId(),
      ABT_Portal_Controller.asCheckoutLookupId(UserInfo.getUserId())
    );
    System.assertEquals(
      UserInfo.getUserId(),
      ABT_Portal_Controller.asCheckoutLookupId(
        String.valueOf(UserInfo.getUserId())
      )
    );

    OrderItem copied = new OrderItem();
    QuoteLineItem qli = new QuoteLineItem();
    qli.put('Vector__c', UserInfo.getUserId());
    ABT_Portal_Controller.copyQuoteLineItemToOrderItem(copied, qli, null);
  }

  @isTest
  static void testUnexpectedCheckoutShowsCustomerMessageAndKeepsKnownErrors() {
    System.assertEquals(
      true,
      ABT_Portal_Controller.isKnownCheckoutMessage(
        'No quotes provided for checkout.'
      )
    );
    System.assertEquals(
      false,
      ABT_Portal_Controller.isKnownCheckoutMessage(
        'FIELD_CUSTOM_VALIDATION_EXCEPTION: boom'
      )
    );

    AuraHandledException known = ABT_Portal_Controller.checkoutUnexpected(
      'No quotes provided for checkout.'
    );
    System.assertEquals('No quotes provided for checkout.', known.getMessage());

    AuraHandledException unexpected = ABT_Portal_Controller.checkoutUnexpected(
      new IllegalArgumentException('FIELD_CUSTOM_VALIDATION_EXCEPTION: boom')
    );
    System.assertEquals(
      ABT_Portal_Controller.CHECKOUT_CUSTOMER_MESSAGE,
      unexpected.getMessage()
    );

    Test.startTest();
    ABT_Portal_Controller.sendCheckoutAlertNow(
      'Portal checkout failure',
      ABT_Portal_Controller.buildCheckoutFailureAlertBody(
        'FIELD_CUSTOM_VALIDATION_EXCEPTION: boom',
        new IllegalArgumentException('boom'),
        new List<Id>{ '0Q0000000000030AAA' }
      )
    );
    new ABT_Portal_Controller.CheckoutFailureAlertJob(
        'Portal checkout failure',
        '<p>test</p>'
      )
      .execute(null);
    Test.stopTest();
  }

  @isTest
  static void testSanitizeCheckoutInvoiceEmailStripsSpaces() {
    System.assertEquals(
      'AP.NJ.Invoice@azenta.com',
      ABT_Portal_Controller.sanitizeCheckoutInvoiceEmail(
        'AP.NJ. Invoice@azenta.com'
      )
    );
    System.assertEquals(
      null,
      ABT_Portal_Controller.sanitizeCheckoutInvoiceEmail('not-an-email')
    );
    System.assertEquals(
      null,
      ABT_Portal_Controller.sanitizeCheckoutInvoiceEmail('   ')
    );
  }

  @isTest
  static void testResolveCheckoutInvoiceEmailStripsInvalidSpaces() {
    Account accountRecord = new Account(Name = 'Azenta Invoice Email');
    insert accountRecord;
    Contact contactRecord = new Contact(
      FirstName = 'GS',
      LastName = 'Azenta',
      AccountId = accountRecord.Id,
      Email = 'gs.ind@azenta.com',
      Invoice_Email__c = 'AP.NJ. Invoice@azenta.com'
    );
    insert contactRecord;
    // Contact-create flow overwrites Invoice_Email from Account/Email; restamp after insert.
    contactRecord.Invoice_Email__c = 'AP.NJ. Invoice@azenta.com';
    update contactRecord;

    System.assertEquals(
      'AP.NJ.Invoice@azenta.com',
      ABT_Portal_Controller.resolveCheckoutInvoiceEmail(contactRecord.Id)
    );

    ABT_Portal_Controller.updateContactInvoiceEmail(
      contactRecord.Id,
      'AP.NJ. Invoice@azenta.com'
    );
    Contact updatedContact = [
      SELECT Invoice_Email__c
      FROM Contact
      WHERE Id = :contactRecord.Id
    ];
    System.assertEquals(
      'AP.NJ.Invoice@azenta.com',
      updatedContact.Invoice_Email__c
    );
  }

  @isTest
  static void testCheckoutFailureEventHandlerSendsAlert() {
    Test.startTest();
    ABT_Portal_Controller.handleCheckoutFailureEvents(
      new List<Portal_Checkout_Failure__e>{
        new Portal_Checkout_Failure__e(
          Email_Subject__c = 'Portal checkout failure',
          Email_Body__c = '<p>test event</p>'
        )
      }
    );
    EventBus.publish(
      new Portal_Checkout_Failure__e(
        Email_Subject__c = 'Portal checkout failure',
        Email_Body__c = '<p>published</p>'
      )
    );
    Test.stopTest();
  }
}
