@IsTest
private class SequenceHubControllerTest {
  @TestSetup
  static void setup() {
    insert new List<Sequence__c>{
      new Sequence__c(
        Sequence_Name__c = 'Hub alpha',
        Sequence__c = 'ACGT',
        Sequence_Length__c = 4,
        Feasibility_Classifier__c = 'Feasible',
        Complexity__c = 'Standard'
      ),
      new Sequence__c(
        Sequence_Name__c = 'Hub beta',
        Sequence__c = 'GGCC',
        Sequence_Length__c = 4,
        Feasibility_Classifier__c = 'Pending',
        Complexity__c = 'Complex'
      ),
      new Sequence__c(
        Sequence_Name__c = 'Motif alpha',
        Sequence__c = 'CCAAGT\nCCGGTT',
        Sequence_Length__c = 12,
        Complexity__c = 'Standard'
      ),
      new Sequence__c(
        Sequence_Name__c = 'Motif beta',
        Sequence__c = 'TTAAGTCCGGAA',
        Sequence_Length__c = 12,
        Complexity__c = 'Complex'
      )
    };
  }

  @IsTest
  static void searchesDnaSubstringsWithFiltersAndPaging() {
    List<Map<String, Object>> first = SequenceHubController.getSequences(
      'aagtccgg',
      null,
      null,
      null,
      null,
      null,
      1,
      0
    );
    List<Map<String, Object>> second = SequenceHubController.getSequences(
      'AAGTCCGG',
      null,
      null,
      null,
      null,
      null,
      1,
      1
    );
    System.assertEquals(1, first.size());
    System.assertEquals(1, second.size());
    System.assertNotEquals(first[0].get('id'), second[0].get('id'));
    List<Map<String, Object>> filtered = SequenceHubController.getSequences(
      'AAGTCCGG',
      null,
      null,
      'Standard',
      null,
      null,
      25,
      0
    );
    System.assertEquals(1, filtered.size());
    System.assertEquals('Motif alpha', filtered[0].get('sequenceName'));
    System.assertEquals(
      0,
      SequenceHubController.getSequences(
          'AAGTCCGA',
          null,
          null,
          null,
          null,
          null,
          25,
          0
        )
        .size()
    );
  }

  @IsTest
  static void filtersAndPagesAccessibleSequences() {
    List<Map<String, Object>> rows = SequenceHubController.getSequences(
      'Hub',
      null,
      null,
      null,
      null,
      null,
      1,
      0
    );
    System.assertEquals(1, rows.size());
    List<Map<String, Object>> nextPage = SequenceHubController.getSequences(
      'Hub',
      null,
      null,
      null,
      null,
      null,
      1,
      1
    );
    System.assertEquals(1, nextPage.size());
    System.assertNotEquals(rows[0].get('id'), nextPage[0].get('id'));
    Sequence__c alpha = [
      SELECT Owner.Name, Feasibility_Classifier__c, Complexity__c
      FROM Sequence__c
      WHERE Sequence_Name__c = 'Hub alpha'
    ];
    rows = SequenceHubController.getSequences(
      'alpha',
      alpha.Owner.Name,
      alpha.Feasibility_Classifier__c,
      alpha.Complexity__c,
      Date.today(),
      Date.today(),
      25,
      0
    );
    System.assertEquals(1, rows.size());
    System.assertEquals('Hub alpha', rows[0].get('sequenceName'));
    System.assertEquals('Designed', rows[0].get('status'));
    System.assertEquals(
      0,
      SequenceHubController.getSequences(
          null,
          null,
          null,
          null,
          Date.today().addDays(1),
          null,
          null,
          null
        )
        .size()
    );
    System.assertEquals(
      0,
      SequenceHubController.getSequences(
          null,
          null,
          null,
          null,
          null,
          Date.today().addDays(-1),
          null,
          null
        )
        .size()
    );
    System.assertEquals(
      0,
      SequenceHubController.getSequences(
          '\' OR Name != \'\'',
          null,
          null,
          null,
          null,
          null,
          25,
          0
        )
        .size()
    );
  }

  @IsTest
  static void detailReturnsDnaAndLinkedProteinSettings() {
    Sequence__c sequence = [
      SELECT Id
      FROM Sequence__c
      WHERE Sequence_Name__c = 'Hub alpha'
    ];
    sequence.Product_SKU__c = '1002';
    update sequence;
    insert new Amino_Acid__c(
      Related_Sequence__c = sequence.Id,
      Amino_Acid_Sequence__c = 'MK*',
      Model__c = 'Trias',
      Flanking_Sequence_5__c = 'ACGT'
    );
    Map<String, Object> detail = SequenceHubController.getSequence(sequence.Id);
    System.assertEquals('ACGT', detail.get('sequence'));
    System.assertEquals('MK*', detail.get('aminoAcidSequence'));
    System.assertEquals(
      'trias',
      ((Map<String, Object>) detail.get('optimizationSettings')).get('modelKey')
    );
    System.assertEquals(true, detail.get('optimizationAvailable'));
    System.assertEquals(false, detail.get('requiresProtein'));
    System.assertEquals(null, detail.get('optimizationUnavailableReason'));
  }

  @IsTest
  static void detailRejectsMissingSequence() {
    Boolean rejected = false;
    try {
      SequenceHubController.getSequence(null);
    } catch (AuraHandledException e) {
      rejected = true;
    }
    System.assert(rejected);
    Sequence__c sequence = [SELECT Id FROM Sequence__c LIMIT 1];
    delete sequence;
    rejected = false;
    try {
      SequenceHubController.getSequence(sequence.Id);
    } catch (AuraHandledException e) {
      rejected = true;
    }
    System.assert(rejected);
  }

  @IsTest
  static void sharingHandlerPreservesExplicitAccountsInBulk() {
    Account account = new Account(Name = 'Hub account');
    insert account;
    List<Sequence__c> sequences = new List<Sequence__c>();
    for (Integer i = 0; i < 200; i++)
      sequences.add(
        new Sequence__c(
          Sequence_Account__c = Math.mod(i, 2) == 0 ? account.Id : null
        )
      );
    Integer queriesBefore = Limits.getQueries();
    SequenceAccountSharingHandler.populateAccount(sequences);
    System.assertEquals(queriesBefore, Limits.getQueries());
    for (Integer i = 0; i < 200; i++)
      System.assertEquals(
        Math.mod(i, 2) == 0 ? account.Id : null,
        sequences[i].Sequence_Account__c
      );
  }
  @IsTest
  static void sharingHandlerResolvesRequestQuoteAndOrderAccounts() {
    Account account = new Account(Name = 'Linked hub account');
    insert account;
    Contact contact = new Contact(
      LastName = 'Hub buyer',
      AccountId = account.Id,
      Email = 'hub-test@example.com'
    );
    insert contact;
    Id pricebookId = Test.getStandardPricebookId();
    update new Pricebook2(Id = pricebookId, IsActive = true);
    Product2 product = new Product2(
      Name = 'Hub product',
      IsActive = true,
      Family = 'Clonal',
      StockKeepingUnit = 'HUB-TEST'
    );
    insert product;
    PricebookEntry entry = new PricebookEntry(
      Pricebook2Id = pricebookId,
      Product2Id = product.Id,
      UnitPrice = 1,
      IsActive = true
    );
    insert entry;
    Opportunity opportunity = new Opportunity(
      Name = 'Hub opportunity',
      AccountId = account.Id,
      ContactId = contact.Id,
      CloseDate = Date.today().addDays(7),
      StageName = 'Prospecting',
      Pricebook2Id = pricebookId
    );
    insert opportunity;
    update new Opportunity(Id = opportunity.Id, Pricebook2Id = pricebookId);
    Quote quote = new Quote(
      Name = 'Hub quote',
      ContactId = contact.Id,
      OpportunityId = opportunity.Id,
      Pricebook2Id = pricebookId,
      Status = 'Draft'
    );
    insert quote;
    update new Quote(Id = quote.Id, Pricebook2Id = pricebookId);
    QuoteLineItem quoteItem = new QuoteLineItem(
      QuoteId = quote.Id,
      PricebookEntryId = entry.Id,
      Product2Id = product.Id,
      Quantity = 1,
      UnitPrice = 1
    );
    insert quoteItem;
    Order orderRecord = new Order(
      AccountId = account.Id,
      EffectiveDate = Date.today(),
      Status = 'Draft',
      Pricebook2Id = pricebookId
    );
    insert orderRecord;
    OrderItem orderItem = new OrderItem(
      OrderId = orderRecord.Id,
      PricebookEntryId = entry.Id,
      Quantity = 1,
      UnitPrice = 1
    );
    insert orderItem;
    ABT_Quote_Request__c request = new ABT_Quote_Request__c(
      ABT_Account__c = account.Id,
      ABT_Product__c = product.Id,
      ABT_Customer_Project_Name__c = 'Hub sharing',
      ABT_Quote__c = quote.Id
    );
    insert request;
    update new ABT_Quote_Request__c(Id = request.Id, ABT_Quote__c = quote.Id);
    ABT_Quote_Request_Lineitem__c requestItem = new ABT_Quote_Request_Lineitem__c(
      ABT_Quote_Request__c = request.Id,
      ABT_Product__c = product.Id,
      ABT_Quantity__c = 1
    );
    insert requestItem;
    update new Opportunity(Id = opportunity.Id, AccountId = account.Id);
    update new Quote(Id = quote.Id, OpportunityId = opportunity.Id);
    update new ABT_Quote_Request__c(
      Id = request.Id,
      ABT_Account__c = account.Id
    );
    update new Order(Id = orderRecord.Id, AccountId = account.Id);
    List<Sequence__c> sequences = new List<Sequence__c>{
      new Sequence__c(Quote_Request_Line_Item__c = requestItem.Id),
      new Sequence__c(Quote_Line_Item__c = quoteItem.Id),
      new Sequence__c(Order_Product__c = orderItem.Id)
    };
    Test.startTest();
    SequenceAccountSharingHandler.populateAccount(sequences);
    Test.stopTest();
    for (Sequence__c sequence : sequences)
      System.assertEquals(
        account.Id,
        sequence.Sequence_Account__c,
        'Source: ' + JSON.serialize(sequence)
      );
    Sequence__c existing = [
      SELECT
        Id,
        Sequence_Account__c,
        Quote_Request_Line_Item__c,
        Quote_Line_Item__c,
        Order_Product__c
      FROM Sequence__c
      WHERE Sequence_Name__c = 'Hub alpha'
    ];
    Account previousAccount = new Account(Name = 'Previous hub account');
    insert previousAccount;
    existing.Sequence_Account__c = previousAccount.Id;
    update existing;
    update new Sequence__c(Id = existing.Id, Quote_Line_Item__c = quoteItem.Id);
    System.assertEquals(
      account.Id,
      [SELECT Sequence_Account__c FROM Sequence__c WHERE Id = :existing.Id]
      .Sequence_Account__c,
      'Moving a sequence must replace its old account sharing'
    );
    Sequence__c detached = new Sequence__c(
      Id = existing.Id,
      Sequence_Account__c = account.Id
    );
    SequenceAccountSharingHandler.populateAccount(
      new List<Sequence__c>{ detached },
      new Map<Id, Sequence__c>{
        existing.Id => new Sequence__c(
          Id = existing.Id,
          Quote_Line_Item__c = quoteItem.Id,
          Sequence_Account__c = account.Id
        )
      }
    );
    System.assertEquals(
      null,
      detached.Sequence_Account__c,
      'Removing all source links must clear derived sharing'
    );
  }
}
