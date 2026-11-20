@isTest
private class ABT_LockSafeDml_Test {
  private class Fixture {
    Account accountRecord;
    Contact contactRecord;
    Id pricebookId;
    Opportunity opportunityRecord;
    Quote quoteRecord;
    Product2 product;
    PricebookEntry pbe;
    QuoteLineItem qli;
  }

  private static Fixture createFixture(Boolean withLine, String classifier) {
    Fixture fx = new Fixture();
    fx.accountRecord = new Account(Name = 'Lock Safe Acc');
    insert fx.accountRecord;

    fx.contactRecord = new Contact(
      LastName = 'Lock Safe',
      AccountId = fx.accountRecord.Id,
      Email = 'lock-safe@example.com'
    );
    insert fx.contactRecord;

    fx.pricebookId = Test.getStandardPricebookId();
    update new Pricebook2(Id = fx.pricebookId, IsActive = true);

    fx.opportunityRecord = new Opportunity(
      Name = 'Lock Safe Opp',
      AccountId = fx.accountRecord.Id,
      ContactId = fx.contactRecord.Id,
      StageName = 'Prospect',
      CloseDate = Date.today().addDays(14),
      Pricebook2Id = fx.pricebookId
    );
    insert fx.opportunityRecord;
    fx.opportunityRecord = [
      SELECT Id, Pricebook2Id
      FROM Opportunity
      WHERE Id = :fx.opportunityRecord.Id
    ];
    if (fx.opportunityRecord.Pricebook2Id != fx.pricebookId) {
      update new Opportunity(
        Id = fx.opportunityRecord.Id,
        Pricebook2Id = fx.pricebookId
      );
    }

    fx.quoteRecord = new Quote(
      Name = 'Lock Safe Quote',
      OpportunityId = fx.opportunityRecord.Id,
      ContactId = fx.contactRecord.Id,
      Status = 'Draft',
      Pricebook2Id = fx.pricebookId
    );
    insert fx.quoteRecord;
    fx.quoteRecord = [
      SELECT Id, Pricebook2Id
      FROM Quote
      WHERE Id = :fx.quoteRecord.Id
    ];
    if (fx.quoteRecord.Pricebook2Id != fx.pricebookId) {
      update new Quote(Id = fx.quoteRecord.Id, Pricebook2Id = fx.pricebookId);
      fx.quoteRecord = [
        SELECT Id, Pricebook2Id
        FROM Quote
        WHERE Id = :fx.quoteRecord.Id
      ];
    }

    if (!withLine) {
      return fx;
    }

    fx.product = new Product2(
      Name = 'Lock Safe Product',
      ProductCode = 'LS-1',
      IsActive = true,
      Family = 'Clonal',
      StockKeepingUnit = 'LS-1'
    );
    insert fx.product;

    fx.pbe = new PricebookEntry(
      Pricebook2Id = fx.quoteRecord.Pricebook2Id,
      Product2Id = fx.product.Id,
      UnitPrice = 10,
      IsActive = true
    );
    insert fx.pbe;

    fx.qli = new QuoteLineItem(
      QuoteId = fx.quoteRecord.Id,
      PricebookEntryId = fx.pbe.Id,
      Product2Id = fx.product.Id,
      Quantity = 1,
      UnitPrice = 10,
      Pending_Feasibility__c = true,
      Feasibility_Classifier__c = classifier
    );
    insert fx.qli;
    return fx;
  }

  private static void prepareQuoteForOrder(Fixture fx) {
    // The order Flow reads this checkbox from the quote's related request.
    ABT_Quote_Request__c request = new ABT_Quote_Request__c(
      ABT_Account__c = fx.accountRecord.Id,
      ABT_Customer_Project_Name__c = 'Lock Safe Project',
      Accept_Partial_Shipment__c = false
    );
    insert request;
    update new Quote(Id = fx.quoteRecord.Id, Quote_Request__c = request.Id);
  }

  private static Sequence__c insertSequence(
    Id quoteLineItemId,
    String classifier
  ) {
    Sequence__c sequenceRecord = new Sequence__c(
      Sequence_Name__c = 'Lock Safe Seq',
      Sequence__c = 'ATGCATGC',
      Quote_Line_Item__c = quoteLineItemId,
      Feasibility_Classifier__c = classifier,
      Complexity__c = 'Pending'.equals(classifier) ? 'Pending' : 'Standard',
      Sequence_Classification__c = 'Pending'.equals(classifier)
        ? 'Pending'
        : 'Guaranteed'
    );
    insert sequenceRecord;
    update new QuoteLineItem(
      Id = quoteLineItemId,
      Related_Sequence__c = sequenceRecord.Id
    );
    return sequenceRecord;
  }

  @isTest
  static void clearQuoteLinePendingFeasibility_updatesFields() {
    Fixture fx = createFixture(true, null);

    ABT_LockSafeQuoteLineUpdate.Request request = new ABT_LockSafeQuoteLineUpdate.Request();
    request.quoteLineItemId = fx.qli.Id;
    request.complexityScore = 1;
    request.feasibilityClassifier = 'Feasible';
    request.mfgPlanVersion = 1;
    request.parts = 1;

    Test.startTest();
    List<ABT_LockSafeQuoteLineUpdate.Result> results = ABT_LockSafeQuoteLineUpdate.clearPendingFeasibility(
      new List<ABT_LockSafeQuoteLineUpdate.Request>{ request }
    );
    Test.stopTest();

    System.assert(results[0].success);
    QuoteLineItem refreshed = [
      SELECT
        Pending_Feasibility__c,
        Feasibility_Classifier__c,
        Times_sent_to_Feasibility__c
      FROM QuoteLineItem
      WHERE Id = :fx.qli.Id
    ];
    System.assertEquals(false, refreshed.Pending_Feasibility__c);
    System.assertEquals('Feasible', refreshed.Feasibility_Classifier__c);
    System.assertEquals(0, refreshed.Times_sent_to_Feasibility__c);
  }

  @isTest
  static void completeIfReady_approvesQuoteAndSyncsOpp() {
    Fixture fx = createFixture(true, 'Feasible');
    insertSequence(fx.qli.Id, 'Feasible');
    update new QuoteLineItem(
      Id = fx.qli.Id,
      Pending_Feasibility__c = false,
      Feasibility_Classifier__c = 'Feasible'
    );

    Test.startTest();
    Boolean completed = ABT_LockSafeDml.completeFeasibilityIfReady(
      fx.quoteRecord.Id,
      fx.opportunityRecord.Id
    );
    Boolean again = ABT_LockSafeDml.completeFeasibilityIfReady(
      fx.quoteRecord.Id,
      fx.opportunityRecord.Id
    );
    System.assertEquals(
      false,
      ABT_LockSafeDml.completeFeasibilityIfReady(null, null)
    );
    Test.stopTest();

    System.assertEquals(true, completed);
    System.assertEquals(true, again);

    Quote quoteRefreshed = [
      SELECT Status
      FROM Quote
      WHERE Id = :fx.quoteRecord.Id
    ];
    System.assert(
      quoteRefreshed.Status == 'Approved' ||
        quoteRefreshed.Status == 'Presented',
      'Unexpected quote status: ' + quoteRefreshed.Status
    );

    Opportunity oppRefreshed = [
      SELECT StageName, SyncedQuoteId
      FROM Opportunity
      WHERE Id = :fx.opportunityRecord.Id
    ];
    System.assertEquals('Quote/Sample', oppRefreshed.StageName);
    System.assertEquals(fx.quoteRecord.Id, oppRefreshed.SyncedQuoteId);
  }

  @isTest
  static void completeIfReady_skipsWhenPendingOrOrdered() {
    Fixture fx = createFixture(true, 'Pending');
    insertSequence(fx.qli.Id, 'Pending');
    prepareQuoteForOrder(fx);

    Test.startTest();
    Boolean pending = ABT_LockSafeDml.completeFeasibilityIfReady(
      fx.quoteRecord.Id,
      fx.opportunityRecord.Id
    );

    update new Quote(Id = fx.quoteRecord.Id, Status = 'Ordered');
    Boolean ordered = ABT_LockSafeDml.completeFeasibilityIfReady(
      fx.quoteRecord.Id,
      fx.opportunityRecord.Id
    );
    Test.stopTest();

    System.assertEquals(false, pending);
    System.assertEquals(false, ordered);
  }

  @isTest
  static void completeIfReady_skipsWhenSequencePendingEvenIfQliFeasible() {
    Fixture fx = createFixture(true, 'Feasible');
    insertSequence(fx.qli.Id, 'Pending');
    update new QuoteLineItem(
      Id = fx.qli.Id,
      Pending_Feasibility__c = true,
      Feasibility_Classifier__c = 'Feasible'
    );

    Test.startTest();
    Boolean completed = ABT_LockSafeDml.completeFeasibilityIfReady(
      fx.quoteRecord.Id,
      fx.opportunityRecord.Id
    );
    Test.stopTest();

    System.assertEquals(
      false,
      completed,
      'QLI Feasible must not complete the quote while Sequence is Pending'
    );
    System.assertEquals(
      'Draft',
      [SELECT Status FROM Quote WHERE Id = :fx.quoteRecord.Id].Status
    );
  }

  @isTest
  static void guardPathsAndRetryHelpers() {
    System.assertEquals(
      true,
      ABT_LockSafeDml.isRetryableLockError(
        new DmlException(
          'UNABLE_TO_LOCK_ROW: unable to obtain exclusive access'
        )
      )
    );
    System.assertEquals(
      false,
      ABT_LockSafeDml.isRetryableLockError(
        new DmlException('FIELD_CUSTOM_VALIDATION')
      )
    );
    System.assertEquals(false, ABT_LockSafeDml.isRetryableLockError(null));

    System.assertEquals(
      0,
      ABT_LockSafeQuoteLineUpdate.clearPendingFeasibility(null).size()
    );

    List<ABT_LockSafeQuoteLineUpdate.Result> emptyQli = ABT_LockSafeQuoteLineUpdate.clearPendingFeasibility(
      new List<ABT_LockSafeQuoteLineUpdate.Request>{
        new ABT_LockSafeQuoteLineUpdate.Request()
      }
    );
    System.assertEquals(false, emptyQli[0].success);

    ABT_LockSafeDml.sleep(1);
    ABT_LockSafeDml.sleep(0);
    ABT_LockSafeDml.lockOpportunity(null);
  }

  @isTest
  static void setQuotePendingFeasibility_movesPresentedQuote() {
    Fixture fx = createFixture(false, null);
    try {
      update new Quote(Id = fx.quoteRecord.Id, Status = 'Presented');
    } catch (Exception e) {
      update new Quote(Id = fx.quoteRecord.Id, Status = 'Approved');
    }

    Test.startTest();
    Boolean moved = ABT_LockSafeDml.setQuotePendingFeasibility(
      fx.quoteRecord.Id
    );
    Boolean alreadyPending = ABT_LockSafeDml.setQuotePendingFeasibility(
      fx.quoteRecord.Id
    );
    Boolean skippedNull = ABT_LockSafeDml.setQuotePendingFeasibility(null);
    Test.stopTest();

    System.assertEquals(true, moved);
    System.assertEquals(true, alreadyPending);
    System.assertEquals(false, skippedNull);
    System.assertEquals(
      'Pending Feasibility',
      [SELECT Status FROM Quote WHERE Id = :fx.quoteRecord.Id].Status
    );
  }

  @isTest
  static void setQuotePendingFeasibility_skipsOrdered() {
    Fixture fx = createFixture(false, null);
    prepareQuoteForOrder(fx);
    update new Quote(Id = fx.quoteRecord.Id, Status = 'Ordered');

    Test.startTest();
    Boolean moved = ABT_LockSafeDml.setQuotePendingFeasibility(
      fx.quoteRecord.Id
    );
    ABT_LockSafeQuotePendingFeasibility.Request request = new ABT_LockSafeQuotePendingFeasibility.Request();
    request.quoteId = fx.quoteRecord.Id;
    List<ABT_LockSafeQuotePendingFeasibility.Result> results = ABT_LockSafeQuotePendingFeasibility.setPendingFeasibility(
      new List<ABT_LockSafeQuotePendingFeasibility.Request>{ request }
    );
    Test.stopTest();

    System.assertEquals(false, moved);
    System.assertEquals(false, results[0].success);
    System.assertEquals(
      0,
      ABT_LockSafeQuotePendingFeasibility.setPendingFeasibility(null).size()
    );
    System.assertEquals(
      'Ordered',
      [SELECT Status FROM Quote WHERE Id = :fx.quoteRecord.Id].Status
    );
  }

  @isTest
  static void insertAndUpdateWithRetry_noopsAndInserts() {
    Fixture fx = createFixture(true, null);

    Test.startTest();
    ABT_LockSafeDml.insertWithRetry((SObject) null);
    ABT_LockSafeDml.insertWithRetry(new List<SObject>());
    ABT_LockSafeDml.updateWithRetry((SObject) null);
    ABT_LockSafeDml.updateWithRetry(new List<SObject>());
    ABT_LockSafeDml.insertWithRetry(
      new QuoteLineItem(
        QuoteId = fx.quoteRecord.Id,
        PricebookEntryId = fx.pbe.Id,
        Product2Id = fx.product.Id,
        Quantity = 1,
        UnitPrice = 12,
        Product_SKU__c = 'GS-001'
      )
    );
    Test.stopTest();

    System.assertEquals(
      2,
      [
        SELECT COUNT()
        FROM QuoteLineItem
        WHERE QuoteId = :fx.quoteRecord.Id
      ]
    );
  }

  @isTest
  static void createGlycerolLine_insertsChildAndStampsParentPrice() {
    Fixture fx = createFixture(true, null);

    Product2 glycerolProduct = new Product2(
      Name = 'Glycerol Stock - Tubes',
      ProductCode = 'GS-LOCKSAFE-TEST',
      IsActive = true,
      Family = 'Services',
      StockKeepingUnit = 'GS-LOCKSAFE-TEST'
    );
    insert glycerolProduct;
    PricebookEntry glycerolPbe = new PricebookEntry(
      Pricebook2Id = fx.quoteRecord.Pricebook2Id,
      Product2Id = glycerolProduct.Id,
      UnitPrice = 30,
      IsActive = true
    );
    insert glycerolPbe;

    ABT_LockSafeGlycerolLineCreate.Request request = new ABT_LockSafeGlycerolLineCreate.Request();
    request.quoteId = fx.quoteRecord.Id;
    request.parentLineItemId = fx.qli.Id;
    request.pricebookEntryId = glycerolPbe.Id;
    request.product2Id = glycerolProduct.Id;
    request.productCode = 'GS-001';
    request.productSku = 'GS-001';
    request.unitPrice = 30;
    request.ansaListPrice = 30;
    request.quantity = 1;

    Test.startTest();
    List<ABT_LockSafeGlycerolLineCreate.Result> results = ABT_LockSafeGlycerolLineCreate.createLines(
      new List<ABT_LockSafeGlycerolLineCreate.Request>{ request }
    );
    List<ABT_LockSafeGlycerolLineCreate.Result> again = ABT_LockSafeGlycerolLineCreate.createLines(
      new List<ABT_LockSafeGlycerolLineCreate.Request>{ request }
    );
    Test.stopTest();

    System.assertEquals(true, results[0].success);
    System.assertNotEquals(null, results[0].quoteLineItemId);
    System.assertEquals(30, results[0].unitPrice);
    System.assertEquals(true, again[0].success);
    System.assertEquals(results[0].quoteLineItemId, again[0].quoteLineItemId);

    QuoteLineItem child = [
      SELECT
        Parent_Line_Item__c,
        UnitPrice,
        Product_SKU__c,
        Product_Code__c,
        Product2.Name,
        Product2.StockKeepingUnit
      FROM QuoteLineItem
      WHERE Id = :results[0].quoteLineItemId
    ];
    System.assertEquals(fx.qli.Id, child.Parent_Line_Item__c);
    System.assert(
      child.Product2 != null &&
        child.Product2.Name != null &&
        child.Product2.Name.toLowerCase().contains('glycerol stock'),
      child.Product2 != null ? child.Product2.Name : 'null product'
    );
    System.assertEquals(30, child.UnitPrice);

    System.assertEquals(
      30,
      [
        SELECT Glycerol_Price__c
        FROM QuoteLineItem
        WHERE Id = :fx.qli.Id
      ]
      .Glycerol_Price__c
    );
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM QuoteLineItem
        WHERE Parent_Line_Item__c = :fx.qli.Id
      ]
    );
  }

  @isTest
  static void createGlycerolLine_requiresIds() {
    System.assertEquals(
      0,
      ABT_LockSafeGlycerolLineCreate.createLines(null).size()
    );

    List<ABT_LockSafeGlycerolLineCreate.Result> results = ABT_LockSafeGlycerolLineCreate.createLines(
      new List<ABT_LockSafeGlycerolLineCreate.Request>{
        new ABT_LockSafeGlycerolLineCreate.Request()
      }
    );
    System.assertEquals(false, results[0].success);
    System.assert(
      results[0].errorMessage.contains('required'),
      results[0].errorMessage
    );
  }
}
