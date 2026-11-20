@IsTest
private class SequenceHubActionsTest {
  @TestSetup
  static void setup() {
    Account account = new Account(Name = 'Hub action account');
    Account other = new Account(Name = 'Other action account');
    insert new List<Account>{ account, other };
    insert new List<Sequence__c>{
      new Sequence__c(
        Sequence_Name__c = 'Hub editable',
        Sequence__c = 'ACGTACGT',
        Sequence_Length__c = 8,
        Sequence_Account__c = account.Id
      ),
      new Sequence__c(
        Sequence_Name__c = 'Other hidden',
        Sequence__c = 'GGCC',
        Sequence_Length__c = 4,
        Sequence_Account__c = other.Id
      )
    };
  }
  private static Id accountId() {
    Id id = [SELECT Id FROM Account WHERE Name = 'Hub action account'].Id;
    SequenceHubActions.testAccountId = id;
    return id;
  }
  private static Id sequenceId() {
    return [SELECT Id FROM Sequence__c WHERE Sequence_Name__c = 'Hub editable']
    .Id;
  }

  @IsTest
  static void annotationsAndRenameRoundTripThroughHub() {
    accountId();
    Id id = sequenceId();
    SequenceHubActions.saveAnnotations(
      id,
      '[{"label":"GFP","start":1,"end":8,"strand":"1"}]'
    );
    SequenceHubActions.renameSequence(id, '  Renamed construct  ');
    Map<String, Object> detail = SequenceHubController.getSequence(id);
    System.assertEquals('Renamed construct', detail.get('sequenceName'));
    System.assertEquals(
      new List<String>{ 'GFP' },
      (List<String>) detail.get('annotations')
    );
    System.assertEquals(
      1,
      ((List<Object>) detail.get('manualFeatures')).size()
    );
    SequenceHubActions.saveAnnotations(id, '[]');
    System.assertEquals(
      0,
      ((List<Object>) SequenceHubController.getSequence(id)
          .get('manualFeatures'))
        .size()
    );
  }

  @IsTest
  static void removesOnlyTheMatchingPlannotateFeature() {
    accountId();
    Id id = sequenceId();
    String first = '{"label":"Promoter","start":1,"end":3,"strand":"1"}';
    String second = '{"label":"Terminator","start":4,"end":8,"strand":"-1"}';
    update new Sequence__c(
      Id = id,
      Plannotate_Features__c = '[' + first + ',' + second + ']'
    );
    SequenceHubActions.removePlannotateFeature(id, 0, first);
    Sequence__c remaining = [
      SELECT Sequence__c, Plannotate_Features__c
      FROM Sequence__c
      WHERE Id = :id
    ];
    List<Object> features = (List<Object>) JSON.deserializeUntyped(
      remaining.Plannotate_Features__c
    );
    System.assertEquals(1, features.size());
    System.assertEquals(
      'Terminator',
      ((Map<String, Object>) features[0]).get('label')
    );
    System.assertEquals('ACGTACGT', remaining.Sequence__c);
    Boolean rejected = false;
    try {
      SequenceHubActions.removePlannotateFeature(id, 0, first);
    } catch (AuraHandledException error) {
      rejected = true;
    }
    System.assert(
      rejected,
      'A stale feature selection must not remove another feature.'
    );
    rejected = false;
    Id otherId = [
      SELECT Id
      FROM Sequence__c
      WHERE Sequence_Name__c = 'Other hidden'
    ]
    .Id;
    try {
      SequenceHubActions.removePlannotateFeature(otherId, 0, second);
    } catch (AuraHandledException error) {
      rejected = true;
    }
    System.assert(rejected, 'Automatic annotations remain account-scoped.');
  }

  @IsTest
  static void manualAnnotationActionsPreserveConcurrentFeaturesAndSafeRetries() {
    accountId();
    Id id = sequenceId();
    String original = '{"label":"Original","start":1,"end":2,"strand":"1"}';
    String teammate = '{"label":"Teammate","start":3,"end":4,"strand":"1"}';
    String addition = '{"label":"New","start":5,"end":8,"strand":"1"}';
    update new Sequence__c(
      Id = id,
      Manual_Annotations__c = '[' + original + ',' + teammate + ']'
    );
    SequenceHubActions.appendManualAnnotations(id, '[' + addition + ']');
    SequenceHubActions.appendManualAnnotations(id, '[' + addition + ']');
    List<Object> features = (List<Object>) JSON.deserializeUntyped(
      [SELECT Manual_Annotations__c FROM Sequence__c WHERE Id = :id]
      .Manual_Annotations__c
    );
    System.assertEquals(
      3,
      features.size(),
      'Preserve a teammate addition and do not duplicate a retried append.'
    );
    SequenceHubActions.removeManualFeature(id, 0, original);
    features = (List<Object>) JSON.deserializeUntyped(
      [SELECT Manual_Annotations__c FROM Sequence__c WHERE Id = :id]
      .Manual_Annotations__c
    );
    System.assertEquals(2, features.size());
    System.assertEquals(
      'Teammate',
      ((Map<String, Object>) features[0]).get('label')
    );
    Boolean rejected = false;
    try {
      SequenceHubActions.removeManualFeature(id, 0, original);
    } catch (AuraHandledException error) {
      rejected = true;
    }
    System.assert(rejected, 'A stale chip must not remove the next feature.');
    Id otherId = [
      SELECT Id
      FROM Sequence__c
      WHERE Sequence_Name__c = 'Other hidden'
    ]
    .Id;
    rejected = false;
    try {
      SequenceHubActions.appendManualAnnotations(otherId, '[' + addition + ']');
    } catch (AuraHandledException error) {
      rejected = true;
    }
    System.assert(rejected, 'Bulk additions cannot modify another account.');
  }

  @IsTest
  static void rejectsOutOfRangeAndCrossAccountWrites() {
    accountId();
    Id id = sequenceId();
    Boolean rejected = false;
    try {
      SequenceHubActions.saveAnnotations(
        id,
        '[{"label":"Bad","start":1,"end":9,"strand":"1"}]'
      );
    } catch (AuraHandledException e) {
      rejected = true;
    }
    System.assert(rejected);
    Id otherId = [
      SELECT Id
      FROM Sequence__c
      WHERE Sequence_Name__c = 'Other hidden'
    ]
    .Id;
    rejected = false;
    try {
      SequenceHubActions.renameSequence(otherId, 'Unauthorized');
    } catch (AuraHandledException e) {
      rejected = true;
    }
    System.assert(
      rejected,
      'Account restriction applies even when the test administrator can read both records'
    );
    System.assertEquals(
      'Other hidden',
      [SELECT Sequence_Name__c FROM Sequence__c WHERE Id = :otherId]
      .Sequence_Name__c
    );
    rejected = false;
    try {
      SequenceHubActions.renameSequence(id, '   ');
    } catch (AuraHandledException e) {
      rejected = true;
    }
    System.assert(rejected);
    rejected = false;
    try {
      SequenceHubActions.addToQuote(new List<Id>{ id, id }, null, null);
    } catch (AuraHandledException e) {
      rejected = true;
    }
    System.assert(rejected);
  }

  @IsTest
  static void feasibilityUsesExistingAfterCommitProcess() {
    accountId();
    Id id = sequenceId();
    Test.startTest();
    SequenceHubActions.requestFeasibility(id);
    Test.stopTest();
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM AsyncApexJob
        WHERE ApexClass.Name = 'ABT_PortalFeasibilityKick'
      ]
    );
    System.assertEquals(
      'Pending',
      [SELECT Feasibility_Classifier__c FROM Sequence__c WHERE Id = :id]
      .Feasibility_Classifier__c
    );
  }

  private static ABT_Quote_Request__c createDestination(Id accountId) {
    Contact contact = new Contact(
      LastName = 'Hub quote buyer',
      AccountId = accountId,
      Email = 'hub-quote@example.com'
    );
    insert contact;
    Id pricebookId = Test.getStandardPricebookId();
    update new Pricebook2(Id = pricebookId, IsActive = true);
    Product2 product = new Product2(
      Name = 'Hub quote product',
      Family = 'Clonal',
      StockKeepingUnit = 'HUB-QUOTE-TEST',
      ProductCode = 'HUB-QUOTE-TEST',
      IsActive = true,
      Vector_Enabled__c = false
    );
    insert product;
    insert new PricebookEntry(
      Pricebook2Id = pricebookId,
      Product2Id = product.Id,
      UnitPrice = 1,
      IsActive = true
    );
    Opportunity opportunity = new Opportunity(
      Name = 'Hub quote opportunity',
      AccountId = accountId,
      ContactId = contact.Id,
      CloseDate = Date.today().addDays(7),
      StageName = 'Prospecting',
      Pricebook2Id = pricebookId
    );
    insert opportunity;
    update new Opportunity(
      Id = opportunity.Id,
      Pricebook2Id = pricebookId,
      AccountId = accountId
    );
    Quote quote = new Quote(
      Name = 'Hub destination',
      ContactId = contact.Id,
      OpportunityId = opportunity.Id,
      Pricebook2Id = pricebookId,
      Status = 'Draft'
    );
    insert quote;
    update new Quote(
      Id = quote.Id,
      Pricebook2Id = pricebookId,
      OpportunityId = opportunity.Id
    );
    ABT_Quote_Request__c request = new ABT_Quote_Request__c(
      ABT_Account__c = accountId,
      ABT_Product__c = product.Id,
      ABT_Contact__c = contact.Id,
      ABT_Customer_Project_Name__c = 'Hub quote test',
      ABT_Quote__c = quote.Id
    );
    insert request;
    update new ABT_Quote_Request__c(
      Id = request.Id,
      ABT_Quote__c = quote.Id,
      ABT_Account__c = accountId
    );
    return request;
  }

  @IsTest
  static void addsCopiesToAnOpenQuoteAndPreservesOriginal() {
    Id accountId = accountId();
    Id id = sequenceId();
    SequenceHubActions.saveAnnotations(
      id,
      '[{"label":"GFP","start":1,"end":4,"strand":"1"}]'
    );
    ABT_Quote_Request__c request = createDestination(accountId);
    Map<String, Object> options = SequenceHubActions.getQuoteOptions();
    System.assertEquals(
      1,
      ((List<Map<String, Object>>) options.get('quotes')).size()
    );
    Test.startTest();
    Map<String, Object> result = SequenceHubActions.addToQuote(
      new List<Id>{ id },
      request.Id,
      null
    );
    Test.stopTest();
    System.assertEquals(1, result.get('added'));
    Sequence__c original = [
      SELECT Sequence__c, Quote_Line_Item__c
      FROM Sequence__c
      WHERE Id = :id
    ];
    System.assertEquals('ACGTACGT', original.Sequence__c);
    System.assertEquals(null, original.Quote_Line_Item__c);
    List<Sequence__c> copies = [
      SELECT Id, Sequence__c
      FROM Sequence__c
      WHERE Quote_Request_Line_Item__r.ABT_Quote_Request__c = :request.Id
    ];
    System.assertEquals(1, copies.size());
    System.assertNotEquals(id, copies[0].Id);
    System.assertEquals('ACGTACGT', copies[0].Sequence__c);
    System.assertEquals(
      new List<String>{ 'GFP' },
      (List<String>) SequenceHubController.getSequence(copies[0].Id)
        .get('annotations')
    );
  }

  @IsTest
  static void rejectsAnotherAccountsDestination() {
    accountId();
    Id id = sequenceId();
    ABT_Quote_Request__c request = createDestination(
      [SELECT Id FROM Account WHERE Name = 'Other action account'].Id
    );
    Boolean rejected = false;
    try {
      SequenceHubActions.addToQuote(new List<Id>{ id }, request.Id, null);
    } catch (AuraHandledException e) {
      rejected = true;
    }
    System.assert(rejected);
    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM ABT_Quote_Request_Lineitem__c
        WHERE ABT_Quote_Request__c = :request.Id
      ]
    );
  }
  @IsTest
  static void rejectsClosedQuotesBeforeCreatingAnyLines() {
    Id accountId = accountId();
    Id id = sequenceId();
    ABT_Quote_Request__c request = createDestination(accountId);
    Id quoteId = [
      SELECT ABT_Quote__c
      FROM ABT_Quote_Request__c
      WHERE Id = :request.Id
    ]
    .ABT_Quote__c;
    update new Quote(Id = quoteId, Status = 'Rejected');
    Boolean rejected = false;
    try {
      SequenceHubActions.addToQuote(new List<Id>{ id }, request.Id, null);
    } catch (AuraHandledException e) {
      rejected = true;
    }
    System.assert(rejected);
    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM ABT_Quote_Request_Lineitem__c
        WHERE ABT_Quote_Request__c = :request.Id
      ]
    );
  }
  @IsTest
  static void vectorSelectionPreservesDnaAndRequestsFeasibility() {
    Id accountId = accountId();
    Id id = sequenceId();
    Vector__c vector = new Vector__c(
      Name = 'Hub catalog vector',
      Account__c = accountId,
      Type__c = 'Catalog',
      Active__c = true
    );
    insert vector;
    Test.startTest();
    SequenceHubActions.saveVector(id, vector.Id);
    Test.stopTest();
    Sequence__c sequence = [
      SELECT Vector__c, Sequence__c
      FROM Sequence__c
      WHERE Id = :id
    ];
    System.assertEquals(vector.Id, sequence.Vector__c);
    System.assertEquals('ACGTACGT', sequence.Sequence__c);
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM AsyncApexJob
        WHERE ApexClass.Name = 'ABT_PortalFeasibilityKick'
      ]
    );
  }
}
