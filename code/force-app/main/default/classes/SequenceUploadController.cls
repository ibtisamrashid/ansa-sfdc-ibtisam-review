/** Creates Sequence__c rows from files that the Sequence Hub parsed in the browser. */
public with sharing class SequenceUploadController {
  private static final Integer MAX_ROWS = 100;
  private static final Integer MAX_BASES_PER_SEQUENCE = 50000;
  private static final Integer MAX_TOTAL_BASES = 1000000;
  private static final Integer MAX_NAME_LENGTH = 255;

  // Portal users cannot create Sequence__c directly. The rows are validated
  // and tied to the user's own account before this writes them.
  private without sharing class SequenceWriter {
    private void insertRows(List<Sequence__c> rows) {
      insert rows;
    }
  }

  @TestVisible
  private static Id testAccountId;

  @AuraEnabled
  public static Map<String, Object> uploadSequences(
    List<String> names,
    List<String> sequences
  ) {
    if (
      names == null ||
      sequences == null ||
      names.size() != sequences.size() ||
      sequences.isEmpty()
    ) {
      throw new AuraHandledException('Upload at least one valid sequence.');
    }
    if (sequences.size() > MAX_ROWS) {
      throw new AuraHandledException(
        'Maximum ' + MAX_ROWS + ' sequences per upload.'
      );
    }
    Id accountId = getUserAccountId();
    Integer totalBases = 0;
    List<Sequence__c> rows = new List<Sequence__c>();
    for (Integer i = 0; i < sequences.size(); i++) {
      String dna = sequences[i] == null
        ? ''
        : sequences[i].replaceAll('\\s+', '').toUpperCase();
      if (String.isBlank(dna))
        throw new AuraHandledException('Sequence ' + (i + 1) + ' is empty.');
      if (String.isNotBlank(dna.replaceAll('[ACGTN]', '')))
        throw new AuraHandledException(
          'Sequence ' +
            (i + 1) +
            ' must contain DNA bases only (A, C, G, T, N).'
        );
      if (dna.length() > MAX_BASES_PER_SEQUENCE)
        throw new AuraHandledException(
          'Sequence ' + (i + 1) + ' is longer than 50,000 bases.'
        );
      totalBases += dna.length();
      if (totalBases > MAX_TOTAL_BASES)
        throw new AuraHandledException(
          'This upload is too large. Split it into smaller files.'
        );
      String name = String.isBlank(names[i])
        ? 'Sequence_' + (i + 1)
        : names[i].trim();
      if (name.length() > MAX_NAME_LENGTH)
        name = name.substring(0, MAX_NAME_LENGTH);
      rows.add(
        new Sequence__c(
          Sequence_Name__c = name,
          Sequence__c = dna,
          Sequence_Length__c = dna.length(),
          Sequence_Account__c = accountId
        )
      );
    }
    try {
      new SequenceWriter().insertRows(rows);
    } catch (DmlException e) {
      throw new AuraHandledException(
        'The sequences could not be saved: ' + e.getDmlMessage(0)
      );
    }
    SequenceHubFeasibility.enqueue(new Map<Id, Sequence__c>(rows).keySet());
    return new Map<String, Object>{ 'created' => rows.size() };
  }

  // Uploads always land on the signed-in user's own account, so the
  // account-based sharing set shows them to the rest of that account.
  private static Id getUserAccountId() {
    if (Test.isRunningTest() && testAccountId != null)
      return testAccountId;
    List<User> users = [
      SELECT Contact.AccountId
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];
    Id accountId = users.isEmpty() || users[0].Contact == null
      ? null
      : users[0].Contact.AccountId;
    if (accountId == null) {
      throw new AuraHandledException(
        'Your user is not linked to an account, so sequences cannot be uploaded.'
      );
    }
    return accountId;
  }
}
