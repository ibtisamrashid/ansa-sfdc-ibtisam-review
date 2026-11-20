@IsTest
private class SequenceHubOptimizationTest {
  private class OptimizerMock implements HttpCalloutMock {
    private Boolean fail;
    OptimizerMock(Boolean fail) {
      this.fail = fail;
    }
    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      response.setStatusCode(200);
      if (request.getEndpoint().endsWith('/api/auth')) {
        response.setHeader(
          'Set-Cookie',
          'codon_alpha=hub-test; Path=/; HttpOnly'
        );
        response.setBody('{"success":true}');
      } else if (request.getEndpoint().endsWith('/api/jobs')) {
        response.setStatusCode(202);
        response.setBody(
          '{"job_id":"standalone-job","parse_report":{"accepted":1}}'
        );
      } else {
        response.setBody(
          JSON.serialize(
            new Map<String, Object>{
              'status' => 'done',
              'results' => new List<Object>{
                new Map<String, Object>{
                  'name' => 'row-0',
                  'display_sequence' => fail ? null : 'ACGTATG',
                  'fidelity' => 'ok',
                  'error' => fail ? 'Optimization failed' : null
                }
              }
            }
          )
        );
      }
      return response;
    }
  }

  @TestSetup
  static void setup() {
    Account account = new Account(Name = 'Hub optimizer account');
    insert account;
    Sequence__c sequence = new Sequence__c(
      Sequence_Name__c = 'Original',
      Sequence__c = 'GGCC',
      Sequence_Length__c = 4,
      Sequence_Account__c = account.Id,
      Product_SKU__c = '1002'
    );
    insert sequence;
    Amino_Acid__c protein = new Amino_Acid__c(
      Related_Sequence__c = sequence.Id,
      Amino_Acid_Sequence__c = 'MK*',
      Model__c = 'Trias'
    );
    insert protein;
    insert new Codon_Optimizer_State__c(
      Key__c = 'JOB:hub-test',
      Value__c = JSON.serialize(
        new List<Object>{
          new Map<String, Object>{
            'id' => 'row-0',
            'name' => 'Original',
            'aminoAcidId' => protein.Id,
            'sequenceId' => sequence.Id,
            'ownerId' => UserInfo.getUserId()
          }
        }
      )
    );
  }

  @IsTest
  static void successfulJobCreatesCopyAndPreservesOriginal() {
    Test.setMock(HttpCalloutMock.class, new OptimizerMock(false));
    Test.startTest();
    Map<String, Object> result = CodonService.getJobStatus('hub-test');
    Test.stopTest();
    Id copyId = (Id) result.get('optimizedSequenceId');
    System.assertNotEquals(null, copyId);
    Sequence__c copy = [
      SELECT
        Sequence_Name__c,
        Sequence__c,
        Sequence_Account__c,
        Quote_Line_Item__c,
        OwnerId
      FROM Sequence__c
      WHERE Id = :copyId
    ];
    Sequence__c original = [
      SELECT Sequence__c, Sequence_Account__c, OwnerId
      FROM Sequence__c
      WHERE Sequence_Name__c = 'Original'
    ];
    System.assertEquals('GGCC', original.Sequence__c);
    System.assertEquals('ACGTATG', copy.Sequence__c);
    System.assertEquals('Original_optimized', copy.Sequence_Name__c);
    System.assertEquals(original.Sequence_Account__c, copy.Sequence_Account__c);
    System.assertEquals(original.OwnerId, copy.OwnerId);
    System.assertEquals(null, copy.Quote_Line_Item__c);
    System.assertEquals(
      'ACGTATG',
      [
        SELECT Optimized_Sequence__c
        FROM Amino_Acid__c
        WHERE Related_Sequence__c = :copyId
      ]
      .Optimized_Sequence__c
    );
    System.assertEquals(
      null,
      [
        SELECT Optimized_Sequence__c
        FROM Amino_Acid__c
        WHERE Related_Sequence__c = :original.Id
      ]
      .Optimized_Sequence__c
    );
  }

  @IsTest
  static void repeatedPollReturnsExistingCopy() {
    Sequence__c copy = new Sequence__c(
      Sequence_Name__c = 'Existing optimized copy',
      Sequence__c = 'ACGTATG'
    );
    insert copy;
    insert new Codon_Optimizer_State__c(
      Key__c = 'COPY:hub-test',
      Value__c = String.valueOf(copy.Id)
    );
    Test.setMock(HttpCalloutMock.class, new OptimizerMock(false));
    Test.startTest();
    Map<String, Object> result = CodonService.getJobStatus('hub-test');
    Test.stopTest();
    System.assertEquals(copy.Id, result.get('optimizedSequenceId'));
    System.assertEquals(2, [SELECT COUNT() FROM Sequence__c]);
  }

  @IsTest
  static void failedJobPreservesOriginalWithoutCreatingCopy() {
    Test.setMock(HttpCalloutMock.class, new OptimizerMock(true));
    Test.startTest();
    Map<String, Object> result = CodonService.getJobStatus('hub-test');
    Test.stopTest();
    System.assertEquals(null, result.get('optimizedSequenceId'));
    System.assertEquals(1, [SELECT COUNT() FROM Sequence__c]);
    System.assertEquals(
      'GGCC',
      [SELECT Sequence__c FROM Sequence__c LIMIT 1].Sequence__c
    );
    System.assertEquals(
      'Optimization failed',
      [SELECT Amino_Acid_Error__c FROM Amino_Acid__c LIMIT 1]
      .Amino_Acid_Error__c
    );
  }
  @IsTest
  static void hubEntryPointRejectsMissingSequence() {
    Boolean rejected = false;
    Test.startTest();
    try {
      CodonController.submitSequenceJob(
        null,
        null,
        new List<String>{ 'Hub sequence' },
        new List<String>{ 'MK*' },
        'trias',
        null,
        '',
        '',
        true,
        true,
        null,
        null
      );
    } catch (AuraHandledException e) {
      rejected = true;
    }
    Test.stopTest();
    System.assert(
      rejected,
      'The public Hub optimizer entry point must require an accessible sequence'
    );
  }
  @IsTest
  static void standaloneDnaAcceptsExplicitProteinWithoutAQuote() {
    Sequence__c original = [SELECT Id FROM Sequence__c LIMIT 1];
    insert new Target_Organism__c(
      Name = 'Standalone host',
      Common_Hosts__c = 'Standalone host',
      Slug__c = 'hub-standalone',
      Models_Accepted__c = 'trias',
      Model__c = 'Trias',
      Active__c = true
    );
    Test.setMock(HttpCalloutMock.class, new OptimizerMock(false));
    Test.startTest();
    Map<String, Object> result = CodonService.submitSequenceJob(
      original.Id,
      null,
      new List<String>{ 'Explicit protein' },
      new List<String>{ 'MKG*' },
      'trias',
      'hub-standalone',
      '',
      '',
      true,
      true,
      null,
      null
    );
    Test.stopTest();
    System.assertEquals('standalone-job', result.get('jobId'));
    System.assertEquals(
      'GGCC',
      [SELECT Sequence__c FROM Sequence__c WHERE Id = :original.Id].Sequence__c
    );
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM Amino_Acid__c
        WHERE
          Related_Sequence__c = :original.Id
          AND Model__c = 'Trias'
          AND Target_Organism__r.Slug__c = 'hub-standalone'
      ]
    );
  }
}
