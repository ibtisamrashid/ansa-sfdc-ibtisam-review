@IsTest
private class SequenceHubAnnotationTest {
  @TestSetup
  static void setup() {
    Account account = new Account(Name = 'Hub annotation account');
    insert account;
    insert new Sequence__c(
      Sequence_Name__c = 'Annotated DNA',
      Sequence__c = 'ACGTACGT',
      Sequence_Length__c = 8,
      Sequence_Account__c = account.Id
    );
  }
  private static Id initialize() {
    SequenceHubActions.testAccountId = [SELECT Id FROM Account LIMIT 1].Id;
    return [SELECT Id FROM Sequence__c LIMIT 1].Id;
  }
  private class AnnotationMock implements HttpCalloutMock {
    private Integer code;
    private String body;
    AnnotationMock(Integer code, String body) {
      this.code = code;
      this.body = body;
    }
    public HttpResponse respond(HttpRequest request) {
      System.assertEquals('POST', request.getMethod());
      System.assertEquals(
        'callout:TestPlannotate/annotate',
        request.getEndpoint()
      );
      Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(
        request.getBody()
      );
      System.assertEquals('ACGTACGT', payload.get('sequence'));
      HttpResponse response = new HttpResponse();
      response.setStatusCode(code);
      response.setBody(body);
      return response;
    }
  }
  private static void configure() {
    SequenceHubAnnotation.testSettings = new Sequence_Hub_Settings__mdt(
      Annotation_Credential__c = 'TestPlannotate',
      Annotation_Path__c = '/annotate'
    );
  }
  @IsTest
  static void asyncAnnotationPersistsValidatedFeatures() {
    Id id = initialize();
    configure();
    Test.setMock(
      HttpCalloutMock.class,
      new AnnotationMock(
        200,
        '{"features":[{"label":"GFP","start":1,"end":8,"strand":"1"}]}'
      )
    );
    Test.startTest();
    Id jobId = SequenceHubAnnotation.requestAnnotation(id);
    System.assertNotEquals(null, jobId);
    Test.stopTest();
    System.assertEquals(
      'Complete',
      SequenceHubController.getSequence(id).get('plannotateStatus')
    );
  }
  @IsTest
  static void serviceFailureRetainsPreviousResults() {
    Id id = initialize();
    configure();
    update new Sequence__c(
      Id = id,
      Plannotate_Features__c = '[{"label":"Existing","start":1,"end":4,"strand":"1"}]',
      Plannotate_Status__c = 'Complete'
    );
    Test.setMock(HttpCalloutMock.class, new AnnotationMock(503, '{}'));
    Test.startTest();
    SequenceHubAnnotation.requestAnnotation(id);
    Test.stopTest();
    Map<String, Object> detail = SequenceHubController.getSequence(id);
    System.assertEquals('Failed', detail.get('plannotateStatus'));
    System.assertEquals(
      new List<String>{ 'Existing' },
      (List<String>) detail.get('plannotate')
    );
  }
  @IsTest
  static void changedDnaDiscardsQueuedResults() {
    Id id = initialize();
    configure();
    Test.setMock(
      HttpCalloutMock.class,
      new AnnotationMock(200, '{"features":[]}')
    );
    Test.startTest();
    SequenceHubAnnotation.requestAnnotation(id);
    update new Sequence__c(Id = id, Sequence__c = 'GGCCAATT');
    Test.stopTest();
    System.assertEquals(
      'Outdated',
      SequenceHubController.getSequence(id).get('plannotateStatus')
    );
    System.assertEquals(
      0,
      ((List<Object>) SequenceHubController.getSequence(id)
          .get('plannotateFeatures'))
        .size()
    );
  }
  @IsTest
  static void invalidServiceCoordinatesAreNotSaved() {
    Id id = initialize();
    configure();
    Test.setMock(
      HttpCalloutMock.class,
      new AnnotationMock(
        200,
        '{"features":[{"label":"Invalid","start":0,"end":99,"strand":"1"}]}'
      )
    );
    Test.startTest();
    SequenceHubAnnotation.requestAnnotation(id);
    Test.stopTest();
    System.assertEquals(
      'Failed',
      SequenceHubController.getSequence(id).get('plannotateStatus')
    );
  }
  @IsTest
  static void missingConfigurationDoesNotQueueAJob() {
    Id id = initialize();
    SequenceHubAnnotation.testSettings = new Sequence_Hub_Settings__mdt();
    System.assertEquals(false, SequenceHubAnnotation.isConfigured());
    Boolean rejected = false;
    try {
      SequenceHubAnnotation.requestAnnotation(id);
    } catch (AuraHandledException e) {
      rejected = true;
    }
    System.assert(rejected);
    System.assertEquals(0, Limits.getQueueableJobs());
  }
}
