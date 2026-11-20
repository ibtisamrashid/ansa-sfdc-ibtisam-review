@IsTest
private class CodonControllerTest {
  @TestSetup
  static void createOrganism() {
    insert new Target_Organism__c(
      Name = 'Controller test organism',
      Common_Hosts__c = 'Controller test host',
      Slug__c = 'controller-test',
      Models_Accepted__c = 'trias',
      Model__c = 'Trias',
      Active__c = true
    );
  }

  @IsTest
  static void delegatesOrganismCatalog() {
    Test.startTest();
    Map<String, Object> result = CodonController.getOrganisms();
    Test.stopTest();

    List<Object> groups = (List<Object>) result.get('groups');
    System.assertEquals(1, groups.size());
    System.assertEquals(
      'Common Hosts',
      ((Map<String, Object>) groups[0]).get('label')
    );
  }

  @IsTest
  static void delegatesSubmissionAndStatusValidation() {
    Boolean submitRejected = false;
    try {
      CodonController.submitJob(
        null,
        new List<String>{ 'sequence' },
        new List<String>{ 'M*' },
        'trias',
        'controller-test',
        '',
        '',
        true,
        true,
        null,
        null
      );
    } catch (AuraHandledException e) {
      submitRejected = true;
    }
    System.assert(submitRejected);

    Boolean statusRejected = false;
    try {
      CodonController.getJobStatus('bad/job/id');
    } catch (AuraHandledException e) {
      statusRejected = true;
    }
    System.assert(statusRejected);
  }

  @IsTest
  static void ignoresIncompleteSequenceLinks() {
    Test.startTest();
    CodonController.linkAminoAcidSequence(null, null);
    Test.stopTest();
    System.assert(true, 'Null links are intentionally ignored.');
  }
}
