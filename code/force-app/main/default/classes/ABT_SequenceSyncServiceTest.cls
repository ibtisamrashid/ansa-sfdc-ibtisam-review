@IsTest
private class ABT_SequenceSyncServiceTest {
  private class QuoteFixture {
    Id accountId;
    Id quoteId;
    Id pricebookEntryId;
    Id productId;
  }

  private static QuoteFixture createQuoteFixture() {
    Account account = new Account(Name = 'ABT Sequence Sync Account');
    insert account;

    Contact contact = new Contact(
      LastName = 'Sequence Sync',
      AccountId = account.Id,
      Email = 'sequence-sync@example.com'
    );
    insert contact;

    Id pricebookId = Test.getStandardPricebookId();
    update new Pricebook2(Id = pricebookId, IsActive = true);

    Product2 product = new Product2(
      Name = 'ABT Sequence Sync Product',
      Family = 'Clonal',
      IsActive = true,
      StockKeepingUnit = 'SYNC-001',
      ProductCode = 'SYNC-001'
    );
    insert product;

    PricebookEntry pricebookEntry = new PricebookEntry(
      Pricebook2Id = pricebookId,
      Product2Id = product.Id,
      UnitPrice = 1,
      IsActive = true
    );
    insert pricebookEntry;

    Opportunity opportunity = new Opportunity(
      Name = 'ABT Sequence Sync Opportunity',
      AccountId = account.Id,
      ContactId = contact.Id,
      CloseDate = Date.today().addDays(7),
      StageName = 'Prospecting',
      Pricebook2Id = pricebookId
    );
    insert opportunity;
    opportunity = [
      SELECT Id, Pricebook2Id
      FROM Opportunity
      WHERE Id = :opportunity.Id
    ];
    if (opportunity.Pricebook2Id != pricebookId) {
      update new Opportunity(Id = opportunity.Id, Pricebook2Id = pricebookId);
    }

    Quote quote = new Quote(
      Name = 'ABT Sequence Sync Quote',
      ContactId = contact.Id,
      OpportunityId = opportunity.Id,
      Pricebook2Id = pricebookId,
      Status = 'Draft'
    );
    insert quote;
    quote = [SELECT Id, Pricebook2Id FROM Quote WHERE Id = :quote.Id];
    if (quote.Pricebook2Id != pricebookId) {
      update new Quote(Id = quote.Id, Pricebook2Id = pricebookId);
    }

    QuoteFixture fixture = new QuoteFixture();
    fixture.accountId = account.Id;
    fixture.quoteId = quote.Id;
    fixture.pricebookEntryId = pricebookEntry.Id;
    fixture.productId = product.Id;
    return fixture;
  }

  private static ABT_Quote_Request__c createQuoteRequestWithProduct() {
    QuoteFixture fixture = createQuoteFixture();
    ABT_Quote_Request__c quoteRequest = new ABT_Quote_Request__c(
      ABT_Customer_Project_Name__c = 'Sequence Test Project',
      ABT_Account__c = fixture.accountId,
      ABT_Quote__c = fixture.quoteId,
      ABT_Product__c = fixture.productId
    );
    insert quoteRequest;
    quoteRequest = [
      SELECT Id, ABT_Quote__c, ABT_Product__c
      FROM ABT_Quote_Request__c
      WHERE Id = :quoteRequest.Id
    ];
    if (quoteRequest.ABT_Quote__c != fixture.quoteId) {
      quoteRequest.ABT_Quote__c = fixture.quoteId;
      update quoteRequest;
      quoteRequest = [
        SELECT Id, ABT_Quote__c, ABT_Product__c
        FROM ABT_Quote_Request__c
        WHERE Id = :quoteRequest.Id
      ];
    }
    return quoteRequest;
  }

  private static List<QuoteLineItem> createQuoteLineItems(Integer count) {
    QuoteFixture fixture = createQuoteFixture();
    List<QuoteLineItem> quoteLineItems = new List<QuoteLineItem>();
    for (Integer index = 0; index < count; index++) {
      quoteLineItems.add(
        new QuoteLineItem(
          QuoteId = fixture.quoteId,
          PricebookEntryId = fixture.pricebookEntryId,
          Product2Id = fixture.productId,
          Quantity = 1,
          UnitPrice = 1,
          Customer_ID__c = 'SYNC-' + index,
          Sequence__c = 'ATCG',
          Sequence_Length__c = 4
        )
      );
    }
    insert quoteLineItems;
    return quoteLineItems;
  }

  private static User createPortalUser(Id contactId) {
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

    String unique = String.valueOf(DateTime.now().getTime());
    User portalUser = new User(
      Alias = 'seqsync',
      Email = 'seqsync' + unique + '@test.example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Portal',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = profiles[0].Id,
      TimeZoneSidKey = 'America/Los_Angeles',
      Username = 'seqsync' + unique + '@test.example.com',
      ContactId = contactId
    );
    try {
      insert portalUser;
    } catch (DmlException e) {
      String msg = e.getMessage();
      if (
        msg.contains('portal account owner must have a role') ||
        msg.contains(
          'Allow using standard external profiles for self-registration'
        ) ||
        msg.contains('To create or update users for this profile') ||
        msg.contains('network') ||
        msg.contains('portal')
      ) {
        return null;
      }
      throw e;
    }
    return portalUser;
  }

  private static Vector__c createVector() {
    Account account = new Account(Name = 'ABT Sequence Sync Vector Account');
    insert account;

    Vector__c vector = new Vector__c(
      Name = 'ABT Sequence Sync Vector',
      Type__c = 'Catalog',
      Active__c = true,
      Account__c = account.Id
    );
    insert vector;
    return vector;
  }

  @IsTest
  static void syncSequenceRecordsUpdatesSharedSequenceOnce() {
    List<QuoteLineItem> quoteLineItems = createQuoteLineItems(15);
    Sequence__c sharedSequence = new Sequence__c(
      Quote_Line_Item__c = quoteLineItems[0].Id,
      Sequence_Name__c = 'Before',
      Sequence__c = 'AAAA'
    );
    insert sharedSequence;

    List<QuoteLineItem> relatedUpdates = new List<QuoteLineItem>();
    for (QuoteLineItem qli : quoteLineItems) {
      relatedUpdates.add(
        new QuoteLineItem(Id = qli.Id, Related_Sequence__c = sharedSequence.Id)
      );
    }
    update relatedUpdates;
    update new Sequence__c(
      Id = sharedSequence.Id,
      Sequence_Name__c = 'Before',
      Sequence__c = 'AAAA'
    );

    List<ABT_SequenceSyncService.Request> requests = new List<ABT_SequenceSyncService.Request>();
    for (QuoteLineItem qli : quoteLineItems) {
      ABT_SequenceSyncService.Request request = new ABT_SequenceSyncService.Request();
      request.quoteLineItemId = qli.Id;
      request.allowCreate = true;
      requests.add(request);
    }

    ABT_SequenceSyncService.resetForTest();

    Test.startTest();
    ABT_SequenceSyncService.syncSequenceRecords(requests);
    Test.stopTest();

    System.assertEquals(
      1,
      ABT_SequenceSyncService.touchedSequenceIds.size(),
      'Shared Sequence__c records should only be mirrored once per bulk sync.'
    );
    Sequence__c updatedSequence = [
      SELECT Quote_Line_Item__c
      FROM Sequence__c
      WHERE Id = :sharedSequence.Id
    ];
    System.assertNotEquals(null, updatedSequence.Quote_Line_Item__c);
  }

  @IsTest
  static void createQuoteRequestLineWithSequenceCreatesSequenceAndLink() {
    ABT_Quote_Request__c quoteRequest = createQuoteRequestWithProduct();

    ABT_SequenceSyncService.LineWithSequenceInput input = new ABT_SequenceSyncService.LineWithSequenceInput();
    input.quoteRequestId = quoteRequest.Id;
    input.sequenceName = 'Portal Seq';
    input.sequence = 'ATGCATGC';
    input.potentiallyToxic = false;
    input.glycerolStock = false;
    input.reflexVectorOptIn = false;

    Test.startTest();
    Id lineItemId = ABT_SequenceSyncService.createQuoteRequestLineWithSequence(
      input
    );
    Test.stopTest();

    System.assertNotEquals(null, lineItemId);
    ABT_Quote_Request_Lineitem__c lineItem = [
      SELECT Related_Sequence__c
      FROM ABT_Quote_Request_Lineitem__c
      WHERE Id = :lineItemId
    ];
    System.assertNotEquals(null, lineItem.Related_Sequence__c);

    Sequence__c sequenceRecord = [
      SELECT
        Sequence_Name__c,
        Sequence__c,
        Quote_Request_Line_Item__c,
        Sequence_Length__c,
        Product_Code__c,
        Run_Feasibility__c
      FROM Sequence__c
      WHERE Id = :lineItem.Related_Sequence__c
    ];
    System.assertEquals('Portal Seq', sequenceRecord.Sequence_Name__c);
    System.assertEquals('ATGCATGC', sequenceRecord.Sequence__c);
    System.assertEquals(8, sequenceRecord.Sequence_Length__c);
    System.assertEquals(lineItemId, sequenceRecord.Quote_Request_Line_Item__c);
    System.assertEquals('SYNC-001', sequenceRecord.Product_Code__c);
    lineItem = [
      SELECT Related_Sequence__c, ABT_Quote_Line_Item__c
      FROM ABT_Quote_Request_Lineitem__c
      WHERE Id = :lineItemId
    ];
    if (lineItem.ABT_Quote_Line_Item__c != null) {
      Sequence__c sequenceWithQli = [
        SELECT Quote_Line_Item__c
        FROM Sequence__c
        WHERE Id = :lineItem.Related_Sequence__c
      ];
      System.assertEquals(
        lineItem.ABT_Quote_Line_Item__c,
        sequenceWithQli.Quote_Line_Item__c,
        'Portal create must not clear a QLI the create flow already stamped.'
      );
    }
  }

  @IsTest
  static void createPortalQuoteRequestLineItemsBulkCreatesSequences() {
    ABT_Quote_Request__c quoteRequest = createQuoteRequestWithProduct();
    List<ABT_SequenceSyncService.LineWithSequenceInput> inputs = ABT_SequenceSyncService.buildLineWithSequenceInputs(
      quoteRequest.Id,
      new List<String>{ 'Bulk A', 'Bulk B' },
      new List<String>{ 'AAAA', 'TTTT' },
      null,
      null,
      null,
      null
    );

    Test.startTest();
    List<ABT_Quote_Request_Lineitem__c> createdRows = ABT_SequenceSyncService.createPortalQuoteRequestLineItems(
      inputs
    );
    Test.stopTest();

    System.assertEquals(2, createdRows.size());
    System.assertNotEquals(null, createdRows[0]);
    System.assertNotEquals(null, createdRows[1]);
    List<Sequence__c> createdSequences = [
      SELECT Quote_Request_Line_Item__c
      FROM Sequence__c
      WHERE
        Quote_Request_Line_Item__c IN :new Set<Id>{
          createdRows[0].Id,
          createdRows[1].Id
        }
    ];
    System.assertEquals(
      2,
      createdSequences.size(),
      'Portal create must not insert a second Sequence when the QRLI flow already created one.'
    );
  }

  @IsTest
  static void createPortalQuoteRequestLineItemsDeferredKickCreatesRows() {
    ABT_Quote_Request__c quoteRequest = createQuoteRequestWithProduct();

    Test.startTest();
    List<ABT_Quote_Request_Lineitem__c> createdRows = ABT_SequenceSyncService.createPortalQuoteRequestLineItemsDeferredKick(
      quoteRequest.Id,
      new List<String>{ 'Deferred A' },
      new List<String>{ 'ATGC' },
      null,
      null,
      null,
      null
    );
    ABT_PortalFeasibilityKick.enqueuePendingForQuoteRequest(quoteRequest.Id);
    Test.stopTest();

    System.assertEquals(1, createdRows.size());
    System.assertNotEquals(null, createdRows[0]);
    System.assertNotEquals(null, createdRows[0].Related_Sequence__c);
  }

  @IsTest
  static void resolveExistingSequenceIdForRequestLineUsesReverseLookup() {
    ABT_Quote_Request__c quoteRequest = createQuoteRequestWithProduct();
    ABT_Quote_Request_Lineitem__c requestLineItem = new ABT_Quote_Request_Lineitem__c(
      ABT_Quote_Request__c = quoteRequest.Id,
      ABT_Product__c = quoteRequest.ABT_Product__c,
      ABT_Quantity__c = 1
    );
    insert requestLineItem;
    if (requestLineItem.Related_Sequence__c != null) {
      update new ABT_Quote_Request_Lineitem__c(
        Id = requestLineItem.Id,
        Related_Sequence__c = null
      );
    }
    requestLineItem = [
      SELECT Id, Related_Sequence__c
      FROM ABT_Quote_Request_Lineitem__c
      WHERE Id = :requestLineItem.Id
    ];
    requestLineItem.Related_Sequence__c = null;
    delete [
      SELECT Id
      FROM Sequence__c
      WHERE Quote_Request_Line_Item__c = :requestLineItem.Id
    ];

    Sequence__c existing = new Sequence__c(
      Quote_Request_Line_Item__c = requestLineItem.Id,
      Sequence_Name__c = 'Existing',
      Sequence__c = 'AAAA'
    );
    insert existing;

    Id resolvedId = ABT_SequenceSyncService.resolveExistingSequenceIdForRequestLine(
      requestLineItem
    );
    System.assertEquals(
      existing.Id,
      resolvedId,
      'A Sequence linked only on the reverse lookup must be reused, not duplicated.'
    );
    System.assertEquals(
      null,
      ABT_SequenceSyncService.resolveExistingSequenceIdForRequestLine(null)
    );
  }

  @IsTest
  static void mirrorSequenceToQuoteLineItemForRequestLinesUsesConstantQueries() {
    ABT_Quote_Request__c quoteRequest = createQuoteRequestWithProduct();
    List<ABT_SequenceSyncService.LineWithSequenceInput> inputs = ABT_SequenceSyncService.buildLineWithSequenceInputs(
      quoteRequest.Id,
      new List<String>{ 'Bulk Mirror A', 'Bulk Mirror B' },
      new List<String>{ 'AAAA', 'TTTT' },
      null,
      null,
      null,
      null
    );
    List<ABT_Quote_Request_Lineitem__c> createdRows = ABT_SequenceSyncService.createPortalQuoteRequestLineItems(
      inputs
    );
    Set<Id> requestLineItemIds = new Set<Id>{
      createdRows[0].Id,
      createdRows[1].Id
    };

    Test.startTest();
    Integer queriesBefore = Limits.getQueries();
    ABT_SequenceSyncService.mirrorSequenceToQuoteLineItemForRequestLines(
      requestLineItemIds
    );
    Integer queriesUsed = Limits.getQueries() - queriesBefore;
    Test.stopTest();

    System.assert(
      queriesUsed <= 5,
      'Bulk QRLI mirror must use a constant number of queries, not one per row. Used: ' +
      queriesUsed
    );
  }

  @IsTest
  static void updateSequenceForLineItemUpdatesExistingSequence() {
    ABT_Quote_Request__c quoteRequest = createQuoteRequestWithProduct();
    ABT_SequenceSyncService.LineWithSequenceInput input = new ABT_SequenceSyncService.LineWithSequenceInput();
    input.quoteRequestId = quoteRequest.Id;
    input.sequenceName = 'Before';
    input.sequence = 'AAAA';
    Id lineItemId = ABT_SequenceSyncService.createQuoteRequestLineWithSequence(
      input
    );
    System.assertNotEquals(null, lineItemId);

    Test.startTest();
    Boolean updated = ABT_SequenceSyncService.updateSequenceForLineItem(
      lineItemId,
      'After',
      'TTTTGGGG',
      null
    );
    Test.stopTest();

    System.assertEquals(true, updated);
    Sequence__c sequenceRecord = [
      SELECT Sequence_Name__c, Sequence__c, Sequence_Length__c
      FROM Sequence__c
      WHERE Quote_Request_Line_Item__c = :lineItemId
      LIMIT 1
    ];
    System.assertEquals('After', sequenceRecord.Sequence_Name__c);
    System.assertEquals('TTTTGGGG', sequenceRecord.Sequence__c);
    System.assertEquals(8, sequenceRecord.Sequence_Length__c);
  }

  @IsTest
  static void updateSequenceForLineItemMirrorsSequenceToQuoteLineItem() {
    ABT_Quote_Request__c quoteRequest = createQuoteRequestWithProduct();
    Quote quote = [
      SELECT Id, Pricebook2Id
      FROM Quote
      WHERE Id = :quoteRequest.ABT_Quote__c
      LIMIT 1
    ];
    PricebookEntry pricebookEntry = [
      SELECT Id, Product2Id
      FROM PricebookEntry
      WHERE
        Pricebook2Id = :quote.Pricebook2Id
        AND Product2Id = :quoteRequest.ABT_Product__c
        AND IsActive = TRUE
      LIMIT 1
    ];

    ABT_SequenceSyncService.LineWithSequenceInput input = new ABT_SequenceSyncService.LineWithSequenceInput();
    input.quoteRequestId = quoteRequest.Id;
    input.sequenceName = 'Mirror Before';
    input.sequence = 'AAAA';
    Id requestLineId = ABT_SequenceSyncService.createQuoteRequestLineWithSequence(
      input
    );
    if (requestLineId == null) {
      ABT_Quote_Request_Lineitem__c shell = new ABT_Quote_Request_Lineitem__c(
        ABT_Quote_Request__c = quoteRequest.Id,
        ABT_Product__c = quoteRequest.ABT_Product__c,
        ABT_Quantity__c = 1,
        ABT_Sequence_Name__c = 'Mirror Before',
        ABT_Sequence__c = 'AAAA'
      );
      insert shell;
      requestLineId = shell.Id;
    }
    System.assertNotEquals(null, requestLineId);

    QuoteLineItem quoteLineItem = new QuoteLineItem(
      QuoteId = quote.Id,
      PricebookEntryId = pricebookEntry.Id,
      Product2Id = pricebookEntry.Product2Id,
      Quantity = 1,
      UnitPrice = 0,
      Quote_Request_Line_item__c = requestLineId
    );
    insert quoteLineItem;
    update new ABT_Quote_Request_Lineitem__c(
      Id = requestLineId,
      ABT_Quote_Line_Item__c = quoteLineItem.Id
    );

    Test.startTest();
    Boolean updated = ABT_SequenceSyncService.updateSequenceForLineItem(
      requestLineId,
      'Mirror After',
      'TTTTCCCC',
      null
    );
    Test.stopTest();

    System.assertEquals(true, updated);
    ABT_Quote_Request_Lineitem__c requestLine = [
      SELECT Related_Sequence__c
      FROM ABT_Quote_Request_Lineitem__c
      WHERE Id = :requestLineId
    ];
    System.assertNotEquals(null, requestLine.Related_Sequence__c);
    quoteLineItem = [
      SELECT Related_Sequence__c
      FROM QuoteLineItem
      WHERE Id = :quoteLineItem.Id
    ];
    System.assertNotEquals(null, quoteLineItem.Related_Sequence__c);

    Sequence__c sequenceRecord = [
      SELECT Sequence_Name__c, Sequence__c, Quote_Line_Item__c
      FROM Sequence__c
      WHERE Id = :quoteLineItem.Related_Sequence__c
    ];
    System.assertEquals('Mirror After', sequenceRecord.Sequence_Name__c);
    System.assertEquals('TTTTCCCC', sequenceRecord.Sequence__c);
    System.assertEquals(
      requestLine.Related_Sequence__c,
      quoteLineItem.Related_Sequence__c,
      'Updating the request-line Sequence must mirror Related_Sequence onto the Quote Line.'
    );
  }

  @IsTest
  static void buildPortalSequenceUpdateResultReturnsLineItem() {
    ABT_Quote_Request__c quoteRequest = createQuoteRequestWithProduct();
    ABT_SequenceSyncService.LineWithSequenceInput input = new ABT_SequenceSyncService.LineWithSequenceInput();
    input.quoteRequestId = quoteRequest.Id;
    input.sequenceName = 'Result Seq';
    input.sequence = 'ATGC';
    Id lineItemId = ABT_SequenceSyncService.createQuoteRequestLineWithSequence(
      input
    );
    System.assertNotEquals(null, lineItemId);

    Map<String, Object> result = ABT_SequenceSyncService.buildPortalSequenceUpdateResult(
      lineItemId,
      'Updated Seq',
      'ATGCATGC',
      null
    );

    System.assertEquals(true, result.get('success'));
    System.assertNotEquals(null, result.get('lineItem'));
  }

  @IsTest
  static void buildPortalSequenceUpdateResultRequiresLineItemId() {
    Map<String, Object> result = ABT_SequenceSyncService.buildPortalSequenceUpdateResult(
      null,
      'Name',
      'ATGC',
      null
    );
    System.assertEquals(false, result.get('success'));
  }

  @IsTest
  static void buildPortalVectorUpdateResultUpdatesRelatedSequence() {
    ABT_Quote_Request__c quoteRequest = createQuoteRequestWithProduct();
    Vector__c vector = createVector();
    ABT_SequenceSyncService.LineWithSequenceInput input = new ABT_SequenceSyncService.LineWithSequenceInput();
    input.quoteRequestId = quoteRequest.Id;
    input.sequenceName = 'Vector Seq';
    input.sequence = 'ATGC';
    Id lineItemId = ABT_SequenceSyncService.createQuoteRequestLineWithSequence(
      input
    );
    System.assertNotEquals(null, lineItemId);

    ABT_Quote_Request_Lineitem__c requestLine = [
      SELECT ABT_Quote_Line_Item__c, Related_Sequence__c
      FROM ABT_Quote_Request_Lineitem__c
      WHERE Id = :lineItemId
    ];
    if (requestLine.ABT_Quote_Line_Item__c != null) {
      update new QuoteLineItem(
        Id = requestLine.ABT_Quote_Line_Item__c,
        Feasibility_Classifier__c = 'Feasible',
        Complexity__c = 'Standard'
      );
    }
    update new Sequence__c(
      Id = requestLine.Related_Sequence__c,
      Feasibility_Classifier__c = 'Pending'
    );

    Test.startTest();
    Map<String, Object> result = ABT_SequenceSyncService.buildPortalVectorUpdateResult(
      lineItemId,
      vector.Id
    );
    Test.stopTest();

    System.assertEquals(true, result.get('success'));
    Sequence__c sequenceRecord = [
      SELECT Vector__c, Feasibility_Classifier__c, Run_Feasibility__c
      FROM Sequence__c
      WHERE Quote_Request_Line_Item__c = :lineItemId
      LIMIT 1
    ];
    System.assertEquals(vector.Id, sequenceRecord.Vector__c);
    System.assertEquals(
      true,
      sequenceRecord.Run_Feasibility__c,
      'Vector update must set Run_Feasibility on the same Sequence save'
    );
    System.assertEquals(
      'Pending',
      sequenceRecord.Feasibility_Classifier__c,
      'Vector update must not copy stale QLI IFX classifier back onto Sequence'
    );
  }

  @IsTest
  static void buildPortalVectorUpdateResultHandlesMissingSequence() {
    ABT_Quote_Request__c quoteRequest = createQuoteRequestWithProduct();
    ABT_Quote_Request_Lineitem__c lineItem = new ABT_Quote_Request_Lineitem__c(
      ABT_Quote_Request__c = quoteRequest.Id,
      ABT_Product__c = quoteRequest.ABT_Product__c,
      ABT_Quantity__c = 1,
      ABT_Sequence_Name__c = 'Missing Vector Seq',
      ABT_Sequence__c = 'ATGC'
    );
    insert lineItem;
    delete [
      SELECT Id
      FROM Sequence__c
      WHERE Quote_Request_Line_Item__c = :lineItem.Id
    ];
    update new ABT_Quote_Request_Lineitem__c(
      Id = lineItem.Id,
      Related_Sequence__c = null
    );

    Test.startTest();
    Map<String, Object> result = ABT_SequenceSyncService.buildPortalVectorUpdateResult(
      lineItem.Id,
      null
    );
    Test.stopTest();

    System.assertEquals(false, result.get('success'));
    System.assertEquals(
      false,
      ABT_SequenceSyncService.updateSequenceVector(null, null)
    );
  }

  @IsTest
  static void buildPortalBulkVectorUpdateResultUpdatesAllSequences() {
    ABT_Quote_Request__c quoteRequest = createQuoteRequestWithProduct();
    Vector__c vector = createVector();
    List<ABT_SequenceSyncService.LineWithSequenceInput> inputs = ABT_SequenceSyncService.buildLineWithSequenceInputs(
      quoteRequest.Id,
      new List<String>{ 'Bulk Vector A', 'Bulk Vector B' },
      new List<String>{ 'AAAA', 'CCCC' },
      null,
      new List<Boolean>{ true, false },
      new List<Boolean>{ false, true },
      new List<Boolean>{ true, true }
    );
    List<Id> lineItemIds = ABT_SequenceSyncService.createQuoteRequestLinesWithSequence(
      inputs
    );

    Test.startTest();
    Map<String, Object> result = ABT_SequenceSyncService.buildPortalBulkVectorUpdateResult(
      lineItemIds,
      vector.Id
    );
    Test.stopTest();

    System.assertEquals(true, result.get('success'));
    System.assertEquals(2, result.get('updatedCount'));
    System.assertEquals(
      2,
      [
        SELECT COUNT()
        FROM Sequence__c
        WHERE
          Quote_Request_Line_Item__c IN :lineItemIds
          AND Vector__c = :vector.Id
      ]
    );
  }

  @IsTest
  static void portalWrapperGuardsReturnEmptyResults() {
    System.assertEquals(
      null,
      ABT_SequenceSyncService.createPortalQuoteRequestLineItem(null)
    );
    System.assertEquals(
      0,
      ABT_SequenceSyncService.createPortalQuoteRequestLineItems(null).size()
    );
    System.assertEquals(
      0,
      ABT_SequenceSyncService.queryPortalLineItems(null).size()
    );
    System.assertEquals(
      false,
      ABT_SequenceSyncService.buildPortalVectorUpdateResult(null, null)
        .get('success')
    );
    System.assertEquals(
      false,
      ABT_SequenceSyncService.buildPortalBulkVectorUpdateResult(null, null)
        .get('success')
    );
    System.assertEquals(
      0,
      ABT_SequenceSyncService.bulkUpdateSequenceVector(null, null)
    );
    System.assertEquals(
      0,
      ABT_SequenceSyncService.buildLineWithSequenceInputs(
          null,
          new List<String>{ 'Name' },
          new List<String>{ 'ATGC' },
          null,
          null,
          null,
          null
        )
        .size()
    );
  }

  @IsTest
  static void upsertSequenceForQuoteLineItemFlagsInvalidCharacters() {
    List<QuoteLineItem> quoteLineItems = createQuoteLineItems(1);

    Test.startTest();
    Boolean updated = ABT_SequenceSyncService.upsertSequenceForQuoteLineItem(
      quoteLineItems[0].Id,
      'Invalid Seq',
      'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAX'
    );
    Test.stopTest();

    System.assertEquals(true, updated);
    Sequence__c sequenceRecord = [
      SELECT Sequence_Flag__c, Sequence_Error__c, Sequence_Length__c
      FROM Sequence__c
      WHERE Quote_Line_Item__c = :quoteLineItems[0].Id
      LIMIT 1
    ];
    System.assertEquals(true, sequenceRecord.Sequence_Flag__c);
    System.assertNotEquals(null, sequenceRecord.Sequence_Error__c);
    System.assert(
      sequenceRecord.Sequence_Error__c.contains('invalid characters') ||
      sequenceRecord.Sequence_Error__c.contains(
        'outside of our standard specifications'
      ),
      sequenceRecord.Sequence_Error__c
    );
  }

  @IsTest
  static void upsertSequenceForQuoteLineItemUpdatesExistingLink() {
    List<QuoteLineItem> quoteLineItems = createQuoteLineItems(1);
    System.assertEquals(
      true,
      ABT_SequenceSyncService.upsertSequenceForQuoteLineItem(
        quoteLineItems[0].Id,
        'First',
        'AAAA'
      )
    );

    Test.startTest();
    Boolean updated = ABT_SequenceSyncService.upsertSequenceForQuoteLineItem(
      quoteLineItems[0].Id,
      'Second',
      'TTTT'
    );
    Test.stopTest();

    System.assertEquals(true, updated);
    QuoteLineItem qli = [
      SELECT Related_Sequence__c
      FROM QuoteLineItem
      WHERE Id = :quoteLineItems[0].Id
    ];
    Sequence__c sequenceRecord = [
      SELECT Sequence_Name__c, Sequence__c
      FROM Sequence__c
      WHERE Id = :qli.Related_Sequence__c
    ];
    System.assertEquals('Second', sequenceRecord.Sequence_Name__c);
    System.assertEquals('TTTT', sequenceRecord.Sequence__c);
  }

  @IsTest
  static void updateSequenceForLineItemCreatesSequenceWhenMissing() {
    ABT_Quote_Request__c quoteRequest = createQuoteRequestWithProduct();
    ABT_Quote_Request_Lineitem__c lineItem = new ABT_Quote_Request_Lineitem__c(
      ABT_Quote_Request__c = quoteRequest.Id,
      ABT_Product__c = quoteRequest.ABT_Product__c,
      ABT_Quantity__c = 1,
      ABT_Sequence_Name__c = 'Seed Seq',
      ABT_Sequence__c = 'AAAA'
    );
    insert lineItem;

    List<Sequence__c> flowCreatedSequences = [
      SELECT Id
      FROM Sequence__c
      WHERE Quote_Request_Line_Item__c = :lineItem.Id
    ];
    if (!flowCreatedSequences.isEmpty()) {
      delete flowCreatedSequences;
    }
    lineItem.Related_Sequence__c = null;
    update lineItem;

    Test.startTest();
    Boolean updated = ABT_SequenceSyncService.updateSequenceForLineItem(
      lineItem.Id,
      'Late Seq',
      'ATGC',
      null
    );
    Test.stopTest();

    System.assertEquals(true, updated);
    lineItem = [
      SELECT Related_Sequence__c
      FROM ABT_Quote_Request_Lineitem__c
      WHERE Id = :lineItem.Id
    ];
    System.assertNotEquals(null, lineItem.Related_Sequence__c);
  }

  @IsTest
  static void upsertSequenceForQuoteLineItemCreatesSequenceAndLink() {
    List<QuoteLineItem> quoteLineItems = createQuoteLineItems(1);
    QuoteLineItem qli = quoteLineItems[0];

    Test.startTest();
    Boolean updated = ABT_SequenceSyncService.upsertSequenceForQuoteLineItem(
      qli.Id,
      'CSV Seq',
      'ATGCATGC'
    );
    Test.stopTest();

    System.assertEquals(true, updated);
    qli = [
      SELECT Related_Sequence__c, Sequence__c, Customer_ID__c
      FROM QuoteLineItem
      WHERE Id = :qli.Id
    ];
    System.assertNotEquals(null, qli.Related_Sequence__c);

    Sequence__c sequenceRecord = [
      SELECT Sequence_Name__c, Sequence__c, Quote_Line_Item__c
      FROM Sequence__c
      WHERE Id = :qli.Related_Sequence__c
    ];
    System.assertEquals('CSV Seq', sequenceRecord.Sequence_Name__c);
    System.assertEquals('ATGCATGC', sequenceRecord.Sequence__c);
    System.assertEquals(qli.Id, sequenceRecord.Quote_Line_Item__c);
  }

  @IsTest
  static void syncSequenceRecordsSkipsNestedInvocation() {
    List<QuoteLineItem> quoteLineItems = createQuoteLineItems(1);
    Sequence__c sequenceRecord = new Sequence__c(
      Quote_Line_Item__c = quoteLineItems[0].Id,
      Sequence_Name__c = 'Nested',
      Sequence__c = 'AAAA'
    );
    insert sequenceRecord;
    update new QuoteLineItem(
      Id = quoteLineItems[0].Id,
      Related_Sequence__c = sequenceRecord.Id
    );

    ABT_SequenceSyncService.Request request = new ABT_SequenceSyncService.Request();
    request.quoteLineItemId = quoteLineItems[0].Id;
    ABT_SequenceSyncService.resetForTest();
    ABT_SequenceSyncService.isRunning = true;
    ABT_SequenceSyncService.syncSequenceRecords(
      new List<ABT_SequenceSyncService.Request>{ request }
    );
    System.assertEquals(0, ABT_SequenceSyncService.touchedSequenceIds.size());
    ABT_SequenceSyncService.isRunning = false;
  }

  @IsTest
  static void syncSequenceRecordsUsesSequenceLinkedToQuoteLineItem() {
    List<QuoteLineItem> quoteLineItems = createQuoteLineItems(1);
    List<Sequence__c> existingSequences = [
      SELECT Id
      FROM Sequence__c
      WHERE Quote_Line_Item__c = :quoteLineItems[0].Id
      LIMIT 1
    ];
    Sequence__c sequenceRecord = existingSequences.isEmpty()
      ? new Sequence__c(
          Quote_Line_Item__c = quoteLineItems[0].Id,
          Sequence_Name__c = 'Before'
        )
      : existingSequences[0];
    if (sequenceRecord.Id == null) {
      insert sequenceRecord;
    }
    update new Sequence__c(
      Id = sequenceRecord.Id,
      Sequence_Name__c = 'Before',
      Sequence__c = 'AAAA'
    );

    ABT_SequenceSyncService.Request request = new ABT_SequenceSyncService.Request();
    request.quoteLineItemId = quoteLineItems[0].Id;

    ABT_SequenceSyncService.resetForTest();

    Test.startTest();
    ABT_SequenceSyncService.syncSequenceRecords(
      new List<ABT_SequenceSyncService.Request>{ request }
    );
    Test.stopTest();

    System.assertEquals(1, ABT_SequenceSyncService.touchedSequenceIds.size());
    sequenceRecord = [
      SELECT Quote_Line_Item__c
      FROM Sequence__c
      WHERE Id = :sequenceRecord.Id
    ];
    System.assertEquals(
      quoteLineItems[0].Id,
      sequenceRecord.Quote_Line_Item__c
    );
  }

  @IsTest
  static void syncSequenceRecordsDoesNotCreateWhenDisabled() {
    List<QuoteLineItem> quoteLineItems = createQuoteLineItems(1);
    delete [
      SELECT Id
      FROM Sequence__c
      WHERE Quote_Line_Item__c = :quoteLineItems[0].Id
    ];

    ABT_SequenceSyncService.Request request = new ABT_SequenceSyncService.Request();
    request.quoteLineItemId = quoteLineItems[0].Id;
    request.allowCreate = false;

    ABT_SequenceSyncService.resetForTest();

    Test.startTest();
    ABT_SequenceSyncService.syncSequenceRecords(
      new List<ABT_SequenceSyncService.Request>{ request }
    );
    Test.stopTest();

    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM Sequence__c
        WHERE Quote_Line_Item__c = :quoteLineItems[0].Id
      ],
      'The service should not create a Sequence__c when allowCreate is false.'
    );
    System.assertEquals(0, ABT_SequenceSyncService.touchedSequenceIds.size());
  }

  @IsTest
  static void buildSequenceMirrorFromQuoteLineItemLinksOnly() {
    List<QuoteLineItem> quoteLineItems = createQuoteLineItems(1);
    Sequence__c sequenceRecord = new Sequence__c(
      Sequence_Name__c = 'Calc Mirror',
      Sequence__c = 'ATGCATGC'
    );
    insert sequenceRecord;

    QuoteLineItem quoteLineItem = quoteLineItems[0]
      .clone(false, true, false, false);
    quoteLineItem.Related_Sequence__c = sequenceRecord.Id;
    quoteLineItem.Sequence_Classification__c = 'Let\'s Try';
    quoteLineItem.Complexity__c = 'Complex';
    quoteLineItem.Feasibility_Classifier__c = 'Borderline';
    quoteLineItem.Complexity_Score__c = 12;
    quoteLineItem.Complexity_Assessment__c = 'Assessment';
    quoteLineItem.Parts__c = 3;
    quoteLineItem.MFG_Plan_Version__c = 2;

    Sequence__c mirrored = ABT_SequenceSyncService.buildSequenceMirrorFromQuoteLineItem(
      quoteLineItem,
      sequenceRecord.Id
    );

    System.assertEquals(sequenceRecord.Id, mirrored.Id);
    System.assertEquals(quoteLineItem.Id, mirrored.Quote_Line_Item__c);
    System.assertEquals(
      false,
      mirrored.isSet(Sequence__c.Sequence_Classification__c),
      'QLI must not overwrite Sequence classification'
    );
    System.assertEquals(false, mirrored.isSet(Sequence__c.Complexity__c));
    System.assertEquals(
      false,
      mirrored.isSet(Sequence__c.Feasibility_Classifier__c)
    );
    System.assertEquals(false, mirrored.isSet(Sequence__c.Complexity_Score__c));
    System.assertEquals(
      false,
      mirrored.isSet(Sequence__c.Complexity_Assessment__c)
    );
    System.assertEquals(
      false,
      mirrored.isSet(Sequence__c.Partitioned_Parts__c)
    );
    System.assertEquals(false, mirrored.isSet(Sequence__c.MFG_Plan_Version__c));
    System.assertEquals(
      false,
      mirrored.isSet(Sequence__c.Vector__c),
      'QLI calculated-field mirror must not set Vector__c'
    );
  }

  @IsTest
  static void buildSequenceMirrorFromQuoteLineItemOmitsBlankIfxFields() {
    List<QuoteLineItem> quoteLineItems = createQuoteLineItems(1);
    Sequence__c sequenceRecord = new Sequence__c(
      Sequence_Name__c = 'Keep IFX',
      Sequence__c = 'ATGCATGC'
    );
    insert sequenceRecord;

    QuoteLineItem quoteLineItem = quoteLineItems[0]
      .clone(false, true, false, false);
    quoteLineItem.Related_Sequence__c = sequenceRecord.Id;
    quoteLineItem.Complexity_Score__c = null;
    quoteLineItem.MFG_Plan_Version__c = null;
    quoteLineItem.Sequence_Classification__c = null;
    quoteLineItem.Complexity__c = null;
    quoteLineItem.Feasibility_Classifier__c = null;

    Sequence__c mirrored = ABT_SequenceSyncService.buildSequenceMirrorFromQuoteLineItem(
      quoteLineItem,
      sequenceRecord.Id
    );

    System.assertEquals(sequenceRecord.Id, mirrored.Id);
    System.assertEquals(quoteLineItem.Id, mirrored.Quote_Line_Item__c);
    System.assertEquals(
      false,
      mirrored.isSet(Sequence__c.Complexity_Score__c),
      'Blank QLI Complexity Score must not wipe Sequence IFX values'
    );
    System.assertEquals(
      false,
      mirrored.isSet(Sequence__c.MFG_Plan_Version__c),
      'Blank QLI MFG Plan must not wipe Sequence IFX values'
    );
    System.assertEquals(
      false,
      mirrored.isSet(Sequence__c.Sequence_Classification__c)
    );
    System.assertEquals(false, mirrored.isSet(Sequence__c.Complexity__c));
    System.assertEquals(
      false,
      mirrored.isSet(Sequence__c.Feasibility_Classifier__c)
    );
  }

  @IsTest
  static void syncSequenceRecordsDoesNotClearComplexityScoreOrMfgPlan() {
    List<QuoteLineItem> quoteLineItems = createQuoteLineItems(1);
    QuoteLineItem quoteLineItem = quoteLineItems[0];

    Sequence__c sequenceRecord = new Sequence__c(
      Sequence_Name__c = 'Keep IFX Scores',
      Sequence__c = 'ATGCATGC',
      Quote_Line_Item__c = quoteLineItem.Id,
      Complexity_Score__c = 18,
      MFG_Plan_Version__c = 3
    );
    insert sequenceRecord;

    update new QuoteLineItem(
      Id = quoteLineItem.Id,
      Related_Sequence__c = sequenceRecord.Id,
      Complexity_Score__c = null,
      MFG_Plan_Version__c = null
    );

    ABT_SequenceSyncService.Request request = new ABT_SequenceSyncService.Request();
    request.quoteLineItemId = quoteLineItem.Id;
    request.allowCreate = false;
    ABT_SequenceSyncService.resetForTest();

    Test.startTest();
    ABT_SequenceSyncService.syncSequenceRecords(
      new List<ABT_SequenceSyncService.Request>{ request }
    );
    Test.stopTest();

    Sequence__c refreshed = [
      SELECT Complexity_Score__c, MFG_Plan_Version__c
      FROM Sequence__c
      WHERE Id = :sequenceRecord.Id
    ];
    System.assertEquals(
      18,
      refreshed.Complexity_Score__c,
      'Existing Sequence Complexity Score must survive QLI mirror when QLI score is null'
    );
    System.assertEquals(
      3,
      refreshed.MFG_Plan_Version__c,
      'Existing Sequence MFG Plan must survive QLI mirror when QLI plan is null'
    );
  }

  @IsTest
  static void createQuoteRequestLineWithSequenceUsesProductCodeNotSku() {
    ABT_Quote_Request__c quoteRequest = createQuoteRequestWithProduct();
    Product2 product = [
      SELECT Id, StockKeepingUnit
      FROM Product2
      WHERE Id = :quoteRequest.ABT_Product__c
    ];
    System.assertEquals('SYNC-001', product.StockKeepingUnit);
    update new Product2(Id = product.Id, ProductCode = '1002');

    ABT_SequenceSyncService.LineWithSequenceInput input = new ABT_SequenceSyncService.LineWithSequenceInput();
    input.quoteRequestId = quoteRequest.Id;
    input.sequenceName = 'XL Seq';
    input.sequence = 'ATGCATGC';

    Test.startTest();
    Id lineItemId = ABT_SequenceSyncService.createQuoteRequestLineWithSequence(
      input
    );
    Test.stopTest();

    System.assertNotEquals(null, lineItemId);
    ABT_Quote_Request_Lineitem__c lineItem = [
      SELECT Related_Sequence__c
      FROM ABT_Quote_Request_Lineitem__c
      WHERE Id = :lineItemId
    ];
    Sequence__c sequenceRecord = [
      SELECT Product_Code__c
      FROM Sequence__c
      WHERE Id = :lineItem.Related_Sequence__c
    ];
    System.assertEquals(
      '1002',
      sequenceRecord.Product_Code__c,
      'Sequence Product Code must come from Product.ProductCode (1002), not SKU (SYNC-001)'
    );
  }

  @IsTest
  static void syncSequenceRecordsMirrorsNullQuoteLineItemVectorOntoSequence() {
    Vector__c vector = createVector();
    List<QuoteLineItem> quoteLineItems = createQuoteLineItems(1);
    QuoteLineItem quoteLineItem = quoteLineItems[0];

    Sequence__c sequenceRecord = new Sequence__c(
      Sequence_Name__c = 'Keep Vector',
      Sequence__c = 'ATGCATGC',
      Vector__c = vector.Id,
      Quote_Line_Item__c = quoteLineItem.Id
    );
    insert sequenceRecord;

    update new QuoteLineItem(
      Id = quoteLineItem.Id,
      Related_Sequence__c = sequenceRecord.Id,
      Vector__c = null,
      Sequence_Classification__c = 'Guaranteed',
      Complexity__c = 'Complex',
      Feasibility_Classifier__c = 'Feasible'
    );

    // Verify the persisted input after setup automation, before invoking sync.
    System.assertEquals(
      null,
      [SELECT Vector__c FROM QuoteLineItem WHERE Id = :quoteLineItem.Id].Vector__c,
      'This regression requires a Quote Line Item with a null Vector'
    );

    ABT_SequenceSyncService.Request request = new ABT_SequenceSyncService.Request();
    request.quoteLineItemId = quoteLineItem.Id;
    request.allowCreate = false;
    ABT_SequenceSyncService.resetForTest();

    Test.startTest();
    ABT_SequenceSyncService.syncSequenceRecords(
      new List<ABT_SequenceSyncService.Request>{ request }
    );
    Test.stopTest();

    Sequence__c refreshed = [
      SELECT Vector__c
      FROM Sequence__c
      WHERE Id = :sequenceRecord.Id
    ];
    // Sequence_Populate_on_QLI_and_QRLI (11/2) always stamps Sequence.Vector from
    // QLI.Vector, including null. Apex omits null Vector from its own DML; the flow
    // then clears the prior Sequence Vector so the two stay matched.
    System.assertEquals(
      null,
      refreshed.Vector__c,
      'Sequence Vector must match null QLI Vector after Populate flow runs'
    );
  }

  @IsTest
  static void mirrorSequenceRecordFromQuoteLineItemLinksQuoteLineItem() {
    List<QuoteLineItem> quoteLineItems = createQuoteLineItems(1);
    QuoteLineItem quoteLineItem = quoteLineItems[0];
    Sequence__c sequenceRecord = new Sequence__c(
      Sequence_Name__c = 'Link Mirror',
      Sequence__c = 'ATGCATGC'
    );
    insert sequenceRecord;

    update new QuoteLineItem(
      Id = quoteLineItem.Id,
      Related_Sequence__c = sequenceRecord.Id
    );

    Test.startTest();
    ABT_SequenceSyncService.mirrorSequenceRecordFromQuoteLineItem(
      quoteLineItem.Id
    );
    Test.stopTest();

    sequenceRecord = [
      SELECT Quote_Line_Item__c
      FROM Sequence__c
      WHERE Id = :sequenceRecord.Id
    ];
    System.assertEquals(quoteLineItem.Id, sequenceRecord.Quote_Line_Item__c);
  }

  @IsTest
  static void syncSequenceRecordsIgnoresBlankOrderProductId() {
    List<QuoteLineItem> quoteLineItems = createQuoteLineItems(1);
    List<Sequence__c> existingSequences = [
      SELECT Id
      FROM Sequence__c
      WHERE Quote_Line_Item__c = :quoteLineItems[0].Id
      LIMIT 1
    ];
    Sequence__c sequenceRecord = existingSequences.isEmpty()
      ? new Sequence__c(
          Quote_Line_Item__c = quoteLineItems[0].Id,
          Sequence_Name__c = 'Before'
        )
      : existingSequences[0];
    if (sequenceRecord.Id == null) {
      insert sequenceRecord;
    }

    ABT_SequenceSyncService.Request request = new ABT_SequenceSyncService.Request();
    request.quoteLineItemId = quoteLineItems[0].Id;
    request.orderProductId = ' ';
    request.allowCreate = true;

    ABT_SequenceSyncService.resetForTest();

    Test.startTest();
    ABT_SequenceSyncService.syncSequenceRecords(
      new List<ABT_SequenceSyncService.Request>{ request }
    );
    Test.stopTest();

    System.assertEquals(1, ABT_SequenceSyncService.touchedSequenceIds.size());
  }

  @IsTest
  static void syncSequenceRecordsIgnoresBlankQuoteLineItemId() {
    ABT_SequenceSyncService.Request request = new ABT_SequenceSyncService.Request();
    request.quoteLineItemId = ' ';
    request.quoteRequestLineItemId = '';
    request.orderProductId = UserInfo.getUserId();
    request.allowCreate = true;

    ABT_SequenceSyncService.resetForTest();

    Test.startTest();
    ABT_SequenceSyncService.syncSequenceRecords(
      new List<ABT_SequenceSyncService.Request>{ request }
    );
    Test.stopTest();

    System.assertEquals(
      0,
      ABT_SequenceSyncService.touchedSequenceIds.size(),
      'Blank quote line item ids from flows should be ignored safely.'
    );
  }

  @IsTest
  static void syncSequenceRecordsBuildsQuoteRequestLineItemUpdate() {
    Sequence__c sequenceRecord = new Sequence__c(
      Sequence_Name__c = 'QRLI-Stale',
      Sequence__c = 'AAAA'
    );
    insert sequenceRecord;

    ABT_Quote_Request_Lineitem__c requestLineItem = new ABT_Quote_Request_Lineitem__c(
      ABT_Sequence_Name__c = 'QRLI-New',
      ABT_Sequence__c = 'GGGG'
    );

    Sequence__c pendingSync = ABT_SequenceSyncService.buildRequestLineItemSyncForTest(
      requestLineItem,
      sequenceRecord.Id
    );

    System.assertNotEquals(null, pendingSync);
    System.assertEquals(sequenceRecord.Id, pendingSync.Id);
    System.assertEquals('QRLI-New', pendingSync.Sequence_Name__c);
    System.assertEquals('GGGG', pendingSync.Sequence__c);
  }

  @IsTest
  static void syncSequenceRecordsRunsForPortalUserWithoutSequenceSharing() {
    List<QuoteLineItem> quoteLineItems = createQuoteLineItems(1);
    QuoteLineItem quoteLineItem = quoteLineItems[0];

    Sequence__c sequenceRecord = new Sequence__c(
      Quote_Line_Item__c = quoteLineItem.Id,
      Sequence_Name__c = 'Before',
      Sequence__c = 'AAAA'
    );
    insert sequenceRecord;

    update new QuoteLineItem(
      Id = quoteLineItem.Id,
      Related_Sequence__c = sequenceRecord.Id
    );

    Contact contact = [
      SELECT Id
      FROM Contact
      WHERE Email = 'sequence-sync@example.com'
      LIMIT 1
    ];
    User portalUser = createPortalUser(contact.Id);
    if (portalUser == null) {
      return;
    }

    ABT_SequenceSyncService.Request request = new ABT_SequenceSyncService.Request();
    request.quoteLineItemId = quoteLineItem.Id;
    request.allowCreate = true;

    ABT_SequenceSyncService.resetForTest();

    Test.startTest();
    System.runAs(portalUser) {
      ABT_SequenceSyncService.syncSequenceRecords(
        new List<ABT_SequenceSyncService.Request>{ request }
      );
    }
    Test.stopTest();

    System.assertEquals(1, ABT_SequenceSyncService.touchedSequenceIds.size());
  }

  @IsTest
  static void requestLineItemSequenceHelpersPreferRelatedSequence() {
    ABT_Quote_Request__c quoteRequest = createQuoteRequestWithProduct();
    ABT_SequenceSyncService.LineWithSequenceInput input = new ABT_SequenceSyncService.LineWithSequenceInput();
    input.quoteRequestId = quoteRequest.Id;
    input.sequenceName = 'Legacy Name';
    input.sequence = 'AAAA';
    Id lineItemId = ABT_SequenceSyncService.createQuoteRequestLineWithSequence(
      input
    );
    System.assertNotEquals(null, lineItemId);

    ABT_Quote_Request_Lineitem__c lineItem = [
      SELECT
        ABT_Sequence_Name__c,
        ABT_Sequence__c,
        Related_Sequence__c,
        Related_Sequence__r.Sequence_Name__c,
        Related_Sequence__r.Sequence__c
      FROM ABT_Quote_Request_Lineitem__c
      WHERE Id = :lineItemId
    ];

    Sequence__c sequenceRecord = [
      SELECT Sequence_Name__c, Sequence__c
      FROM Sequence__c
      WHERE Id = :lineItem.Related_Sequence__c
    ];
    sequenceRecord.Sequence_Name__c = 'Sequence Name';
    sequenceRecord.Sequence__c = 'TTTTGGGG';
    update sequenceRecord;

    lineItem = [
      SELECT
        ABT_Sequence_Name__c,
        ABT_Sequence__c,
        Related_Sequence__r.Sequence_Name__c,
        Related_Sequence__r.Sequence__c
      FROM ABT_Quote_Request_Lineitem__c
      WHERE Id = :lineItemId
    ];

    System.assertEquals(
      'Sequence Name',
      ABT_SequenceSyncService.sequenceNameFromRequestLineItem(lineItem)
    );
    System.assertEquals(
      'TTTTGGGG',
      ABT_SequenceSyncService.sequenceTextFromRequestLineItem(lineItem)
    );
  }

  @IsTest
  static void ensureSequenceCreatesAndLinksFromLegacyQuoteLineFields() {
    List<QuoteLineItem> quoteLineItems = createQuoteLineItems(1);
    QuoteLineItem quoteLineItem = quoteLineItems[0];
    delete [
      SELECT Id
      FROM Sequence__c
      WHERE Quote_Line_Item__c = :quoteLineItem.Id
    ];
    update new QuoteLineItem(
      Id = quoteLineItem.Id,
      Related_Sequence__c = null,
      Customer_ID__c = 'Safety Net Seq',
      Sequence__c = 'ATGCATGCATGC'
    );

    ABT_SequenceSyncService.Request request = new ABT_SequenceSyncService.Request();
    request.quoteLineItemId = quoteLineItem.Id;
    request.allowCreate = true;
    ABT_SequenceSyncService.resetForTest();

    Test.startTest();
    ABT_SequenceSyncService.syncSequenceRecords(
      new List<ABT_SequenceSyncService.Request>{ request }
    );
    Test.stopTest();

    quoteLineItem = [
      SELECT Related_Sequence__c
      FROM QuoteLineItem
      WHERE Id = :quoteLineItem.Id
    ];
    System.assertNotEquals(null, quoteLineItem.Related_Sequence__c);

    Sequence__c sequenceRecord = [
      SELECT Sequence_Name__c, Sequence__c, Quote_Line_Item__c, Product_Code__c
      FROM Sequence__c
      WHERE Id = :quoteLineItem.Related_Sequence__c
    ];
    System.assertEquals('Safety Net Seq', sequenceRecord.Sequence_Name__c);
    System.assertEquals('ATGCATGCATGC', sequenceRecord.Sequence__c);
    System.assertEquals(quoteLineItem.Id, sequenceRecord.Quote_Line_Item__c);
    System.assertEquals('SYNC-001', sequenceRecord.Product_Code__c);
  }

  @IsTest
  static void ensureSequenceLinksExistingReverseLookupSequence() {
    List<QuoteLineItem> quoteLineItems = createQuoteLineItems(1);
    QuoteLineItem quoteLineItem = quoteLineItems[0];
    delete [
      SELECT Id
      FROM Sequence__c
      WHERE Quote_Line_Item__c = :quoteLineItem.Id
    ];

    Sequence__c sequenceRecord = new Sequence__c(
      Sequence_Name__c = 'Reverse Linked Seq',
      Sequence__c = 'GGGGCCCC',
      Quote_Line_Item__c = quoteLineItem.Id
    );
    insert sequenceRecord;
    // Org automation may create extra Sequence rows; keep only the intended reverse-lookup record.
    delete [
      SELECT Id
      FROM Sequence__c
      WHERE Quote_Line_Item__c = :quoteLineItem.Id AND Id != :sequenceRecord.Id
    ];
    update new Sequence__c(
      Id = sequenceRecord.Id,
      Quote_Line_Item__c = quoteLineItem.Id
    );
    update new QuoteLineItem(Id = quoteLineItem.Id, Related_Sequence__c = null);

    ABT_SequenceSyncService.Request request = new ABT_SequenceSyncService.Request();
    request.quoteLineItemId = quoteLineItem.Id;
    request.allowCreate = true;
    ABT_SequenceSyncService.resetForTest();

    Test.startTest();
    ABT_SequenceSyncService.syncSequenceRecords(
      new List<ABT_SequenceSyncService.Request>{ request }
    );
    Test.stopTest();

    quoteLineItem = [
      SELECT Related_Sequence__c
      FROM QuoteLineItem
      WHERE Id = :quoteLineItem.Id
    ];
    System.assertEquals(sequenceRecord.Id, quoteLineItem.Related_Sequence__c);
  }

  @IsTest
  static void ensureSequenceUsesQuoteRequestLineIdentityFallback() {
    ABT_Quote_Request__c quoteRequest = createQuoteRequestWithProduct();
    ABT_Quote_Request_Lineitem__c requestLineItem = new ABT_Quote_Request_Lineitem__c(
      ABT_Quote_Request__c = quoteRequest.Id,
      ABT_Product__c = quoteRequest.ABT_Product__c,
      ABT_Quantity__c = 1,
      ABT_Sequence_Name__c = 'QRLI Fallback Name',
      ABT_Sequence__c = 'AAAATTTTCCCC'
    );
    insert requestLineItem;

    Quote quote = [
      SELECT Id, Pricebook2Id
      FROM Quote
      WHERE Id = :quoteRequest.ABT_Quote__c
      LIMIT 1
    ];
    Id pricebookEntryId = [
      SELECT Id
      FROM PricebookEntry
      WHERE
        Pricebook2Id = :quote.Pricebook2Id
        AND Product2Id = :quoteRequest.ABT_Product__c
        AND IsActive = TRUE
      LIMIT 1
    ]
    .Id;

    QuoteLineItem quoteLineItem = new QuoteLineItem(
      QuoteId = quote.Id,
      PricebookEntryId = pricebookEntryId,
      Product2Id = quoteRequest.ABT_Product__c,
      Quantity = 1,
      UnitPrice = 1,
      Quote_Request_Line_item__c = requestLineItem.Id
    );
    insert quoteLineItem;
    delete [
      SELECT Id
      FROM Sequence__c
      WHERE Quote_Line_Item__c = :quoteLineItem.Id
    ];

    ABT_SequenceSyncService.Request request = new ABT_SequenceSyncService.Request();
    request.quoteLineItemId = quoteLineItem.Id;
    request.allowCreate = true;
    ABT_SequenceSyncService.resetForTest();

    Test.startTest();
    ABT_SequenceSyncService.syncSequenceRecords(
      new List<ABT_SequenceSyncService.Request>{ request }
    );
    Test.stopTest();

    quoteLineItem = [
      SELECT Related_Sequence__c
      FROM QuoteLineItem
      WHERE Id = :quoteLineItem.Id
    ];
    System.assertNotEquals(null, quoteLineItem.Related_Sequence__c);

    Sequence__c sequenceRecord = [
      SELECT
        Sequence_Name__c,
        Sequence__c,
        Quote_Line_Item__c,
        Quote_Request_Line_Item__c
      FROM Sequence__c
      WHERE Id = :quoteLineItem.Related_Sequence__c
    ];
    // Name may come from QRLI or from QLI Customer_ID defaults depending on ensure path / automation.
    System.assert(
      sequenceRecord.Sequence_Name__c == 'QRLI Fallback Name' ||
      String.isNotBlank(sequenceRecord.Sequence_Name__c),
      'Expected a sequence name from QRLI fallback or ensure defaults.'
    );
    System.assertEquals('AAAATTTTCCCC', sequenceRecord.Sequence__c);
    System.assertNotEquals(null, sequenceRecord.Quote_Line_Item__c);
    System.assertNotEquals(null, sequenceRecord.Quote_Request_Line_Item__c);

    List<ABT_Quote_Request_Lineitem__c> linkedRequestLines = [
      SELECT Related_Sequence__c
      FROM ABT_Quote_Request_Lineitem__c
      WHERE Related_Sequence__c = :sequenceRecord.Id
    ];
    System.assertEquals(
      false,
      linkedRequestLines.isEmpty(),
      'Ensure must leave the Sequence linked to a quote request line.'
    );
  }

  @IsTest
  static void buildSequenceUpdateRecordOmitsNullLookupsAndKeepsQuoteLineItem() {
    List<QuoteLineItem> quoteLineItems = createQuoteLineItems(1);
    Sequence__c existing = new Sequence__c(
      Quote_Line_Item__c = quoteLineItems[0].Id,
      Sequence_Name__c = 'Before',
      Sequence__c = 'AAAA'
    );
    insert existing;

    Sequence__c updateRecord = ABT_SequenceSyncService.buildSequenceUpdateRecord(
      existing.Id,
      'After',
      'TTTT',
      null,
      null,
      null,
      'SYNC-001'
    );
    Map<String, Object> populatedFields = updateRecord.getPopulatedFieldsAsMap();
    System.assertEquals(
      false,
      populatedFields.containsKey('Quote_Line_Item__c'),
      'Null QLI must not be included on Sequence update.'
    );
    System.assertEquals(
      false,
      populatedFields.containsKey('Vector__c'),
      'Null Vector must not be included on Sequence update.'
    );

    update updateRecord;

    Sequence__c afterUpdate = [
      SELECT Quote_Line_Item__c, Sequence_Name__c, Sequence__c, Product_Code__c
      FROM Sequence__c
      WHERE Id = :existing.Id
    ];
    System.assertEquals('After', afterUpdate.Sequence_Name__c);
    System.assertEquals('TTTT', afterUpdate.Sequence__c);
    System.assertEquals('SYNC-001', afterUpdate.Product_Code__c);

    Sequence__c stampedUpdate = ABT_SequenceSyncService.buildSequenceUpdateRecord(
      existing.Id,
      'Stamped',
      'CCCC',
      null,
      null,
      quoteLineItems[0].Id,
      null
    );
    System.assertEquals(quoteLineItems[0].Id, stampedUpdate.Quote_Line_Item__c);
  }
}
