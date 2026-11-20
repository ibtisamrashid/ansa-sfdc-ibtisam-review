/** Plannotate adapter. Credentials and URL paths are configured per org, never by the browser. */
public without sharing class SequenceHubAnnotation {
  @TestVisible
  private static Sequence_Hub_Settings__mdt testSettings;

  private static Sequence_Hub_Settings__mdt settings() {
    return Test.isRunningTest() && testSettings != null
      ? testSettings
      : Sequence_Hub_Settings__mdt.getInstance('Default');
  }

  @AuraEnabled
  public static Boolean isConfigured() {
    Sequence_Hub_Settings__mdt config = settings();
    return config != null &&
      String.isNotBlank(config.Annotation_Credential__c) &&
      Pattern.matches(
        '[A-Za-z][A-Za-z0-9_]*',
        config.Annotation_Credential__c
      ) &&
      String.isNotBlank(config.Annotation_Path__c) &&
      config.Annotation_Path__c.startsWith('/') &&
      !config.Annotation_Path__c.contains('://') &&
      !Pattern.matches('(?s).*[\r\n].*', config.Annotation_Path__c);
  }

  @AuraEnabled
  public static Id requestAnnotation(Id sequenceId) {
    Sequence__c sequence = SequenceHubActions.accessibleSequence(sequenceId);
    if (!isConfigured())
      throw new AuraHandledException(
        'The Plannotate service is not configured. Ask an administrator to configure it.'
      );
    if (String.isBlank(sequence.Sequence__c))
      throw new AuraHandledException('Add DNA before running Plannotate.');
    Sequence_Hub_Settings__mdt config = settings();
    Id jobId = System.enqueueJob(
      new AnnotationJob(
        sequence.Id,
        sequence.Sequence_Account__c,
        sequenceHash(sequence.Sequence__c),
        config.Annotation_Credential__c,
        config.Annotation_Path__c
      )
    );
    update new Sequence__c(
      Id = sequence.Id,
      Plannotate_Status__c = 'Queued',
      Plannotate_Job__c = String.valueOf(jobId)
    );
    return jobId;
  }

  public static String sequenceHash(String dna) {
    return EncodingUtil.convertToHex(
      Crypto.generateDigest(
        'SHA-256',
        Blob.valueOf(
          dna == null ? '' : dna.replaceAll('\\s+', '').toUpperCase()
        )
      )
    );
  }

  private static Boolean sameJob(String stored, Id running) {
    if (String.isBlank(stored))
      return false;
    try {
      return Id.valueOf(stored) == running;
    } catch (Exception e) {
      return false;
    }
  }

  private class AnnotationJob implements Queueable, Database.AllowsCallouts {
    private Id sequenceId;
    private Id accountId;
    private String hash;
    private String credential;
    private String path;
    private AnnotationJob(
      Id sequenceId,
      Id accountId,
      String hash,
      String credential,
      String path
    ) {
      this.sequenceId = sequenceId;
      this.accountId = accountId;
      this.hash = hash;
      this.credential = credential;
      this.path = path;
    }
    public void execute(QueueableContext context) {
      List<Sequence__c> records = [
        SELECT
          Id,
          Sequence__c,
          Sequence_Name__c,
          Sequence_Account__c,
          Plannotate_Job__c
        FROM Sequence__c
        WHERE Id = :sequenceId
        LIMIT 1
      ];
      if (
        records.isEmpty() ||
        records[0].Sequence_Account__c != accountId ||
        sequenceHash(records[0].Sequence__c) != hash ||
        !sameJob(records[0].Plannotate_Job__c, context.getJobId())
      )
        return;
      String resultJson;
      String status = 'Complete';
      try {
        HttpRequest request = new HttpRequest();
        request.setEndpoint('callout:' + credential + path);
        request.setMethod('POST');
        request.setTimeout(120000);
        request.setHeader('Content-Type', 'application/json');
        request.setBody(
          JSON.serialize(
            new Map<String, Object>{
              'sequence' => records[0].Sequence__c,
              'name' => records[0].Sequence_Name__c,
              'sequence_hash' => hash
            }
          )
        );
        HttpResponse response = new Http().send(request);
        if (response.getStatusCode() < 200 || response.getStatusCode() >= 300)
          throw new CalloutException('Annotation request failed.');
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
          response.getBody()
        );
        if (
          body.get('sequence_hash') != null &&
          body.get('sequence_hash') != hash
        )
          throw new CalloutException(
            'Annotation response does not match the requested DNA.'
          );
        resultJson = JSON.serialize(
          SequenceHubActions.validateFeatures(
            JSON.serialize(body.get('features')),
            records[0].Sequence__c.length()
          )
        );
      } catch (Exception e) {
        status = 'Failed';
      }
      // A result must never attach to edited DNA or overwrite a newer annotation request/import.
      List<Sequence__c> current = [
        SELECT Id, Sequence__c, Sequence_Account__c, Plannotate_Job__c
        FROM Sequence__c
        WHERE Id = :sequenceId
        LIMIT 1
        FOR UPDATE
      ];
      if (
        current.isEmpty() ||
        current[0].Sequence_Account__c != accountId ||
        sequenceHash(current[0].Sequence__c) != hash ||
        !sameJob(current[0].Plannotate_Job__c, context.getJobId())
      )
        return;
      Sequence__c updateRecord = new Sequence__c(
        Id = sequenceId,
        Plannotate_Status__c = status,
        Plannotate_Job__c = null
      );
      if (status == 'Complete') {
        updateRecord.Plannotate_Features__c = resultJson;
        updateRecord.Plannotate_Sequence_Hash__c = hash;
      }
      update updateRecord;
    }
  }
}
