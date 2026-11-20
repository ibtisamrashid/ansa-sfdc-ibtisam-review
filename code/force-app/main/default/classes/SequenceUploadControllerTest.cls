@IsTest
private class SequenceUploadControllerTest {
  @IsTest
  static void createsSequencesOnTheUsersAccount() {
    Account a = new Account(Name = 'Upload Test Account');
    insert a;
    SequenceUploadController.testAccountId = a.Id;

    Test.startTest();
    Map<String, Object> result = SequenceUploadController.uploadSequences(
      new List<String>{ 'UP_1', '' },
      new List<String>{ 'atgc tagc', 'GGGNNN' }
    );
    Test.stopTest();

    System.assertEquals(2, result.get('created'));
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM AsyncApexJob
        WHERE ApexClass.Name = 'ABT_PortalFeasibilityKick'
      ],
      'Uploads must request the existing external feasibility process after commit'
    );
    Map<String, Sequence__c> byName = new Map<String, Sequence__c>();
    for (Sequence__c s : [
      SELECT
        Sequence_Name__c,
        Sequence__c,
        Sequence_Length__c,
        Sequence_Account__c
      FROM Sequence__c
      WHERE Sequence_Account__c = :a.Id
    ]) {
      byName.put(s.Sequence_Name__c, s);
    }
    System.assertEquals(2, byName.size());
    System.assertEquals('ATGCTAGC', byName.get('UP_1').Sequence__c);
    System.assertEquals(8, byName.get('UP_1').Sequence_Length__c);
    System.assert(byName.containsKey('Sequence_2'));
  }

  @IsTest
  static void rejectsNonDnaCharacters() {
    Account a = new Account(Name = 'Upload Test Account');
    insert a;
    SequenceUploadController.testAccountId = a.Id;
    Boolean thrown = false;
    try {
      SequenceUploadController.uploadSequences(
        new List<String>{ 'BAD' },
        new List<String>{ 'ATGCXYZ' }
      );
    } catch (AuraHandledException e) {
      thrown = true;
    }
    System.assert(thrown, 'Non-DNA characters should be rejected.');
    System.assertEquals(0, [SELECT COUNT() FROM Sequence__c]);
  }

  @IsTest
  static void rejectsUsersWithoutAnAccount() {
    Boolean thrown = false;
    try {
      SequenceUploadController.uploadSequences(
        new List<String>{ 'NOACCT' },
        new List<String>{ 'ATGC' }
      );
    } catch (AuraHandledException e) {
      thrown = true;
    }
    System.assert(thrown, 'A user with no account should be rejected.');
  }
  private static void assertRejected(
    List<String> names,
    List<String> sequences
  ) {
    Boolean rejected = false;
    try {
      SequenceUploadController.uploadSequences(names, sequences);
    } catch (AuraHandledException e) {
      rejected = true;
    }
    System.assert(rejected, 'Invalid upload must fail');
    System.assertEquals(
      0,
      [SELECT COUNT() FROM Sequence__c],
      'Validation must save no rows'
    );
  }

  @IsTest
  static void rejectsInvalidBatchesWithoutSavingValidRows() {
    Account account = new Account(Name = 'Hub validation account');
    insert account;
    SequenceUploadController.testAccountId = account.Id;
    assertRejected(null, null);
    assertRejected(new List<String>(), new List<String>());
    assertRejected(
      new List<String>{ 'One' },
      new List<String>{ 'ACGT', 'GGCC' }
    );
    assertRejected(
      new List<String>{ 'Good', 'Bad' },
      new List<String>{ 'ACGT', 'AC-GT' }
    );
    assertRejected(new List<String>{ 'Empty' }, new List<String>{ '   ' });
    List<String> names = new List<String>();
    List<String> sequences = new List<String>();
    for (Integer i = 0; i < 101; i++) {
      names.add('Row ' + i);
      sequences.add('ACGT');
    }
    assertRejected(names, sequences);
    String tooLong = 'A'.repeat(50001);
    assertRejected(new List<String>{ 'Too long' }, new List<String>{ tooLong });
    names.clear();
    sequences.clear();
    for (Integer i = 0; i < 21; i++) {
      names.add('Large ' + i);
      sequences.add('A'.repeat(50000));
    }
    assertRejected(names, sequences);
  }
}
