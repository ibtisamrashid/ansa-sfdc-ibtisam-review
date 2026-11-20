@IsTest
private class CodonServiceTest {
  private class OptimizerMock implements HttpCalloutMock {
    Boolean retryFirstPoll = false;
    Boolean failAuthentication = false;
    Boolean failSequence = false;
    Integer authCalls = 0;
    Integer pollCalls = 0;
    String lastJobRequest;

    void reset() {
      retryFirstPoll = false;
      failAuthentication = false;
      failSequence = false;
      authCalls = 0;
      pollCalls = 0;
      lastJobRequest = null;
    }

    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      String endpoint = request.getEndpoint();
      if (endpoint.endsWith('/api/auth')) {
        authCalls++;
        if (failAuthentication) {
          response.setStatusCode(401);
          response.setBody('{"detail":"unauthorized"}');
          return response;
        }
        response.setStatusCode(200);
        response.setHeader(
          'Set-Cookie',
          'codon_alpha=test-cookie; Path=/; HttpOnly'
        );
        response.setBody('{"success":true}');
        return response;
      }
      if (endpoint.endsWith('/api/jobs') && request.getMethod() == 'POST') {
        lastJobRequest = request.getBody();
        response.setStatusCode(202);
        response.setBody(
          '{"job_id":"submit-job","parse_report":{"accepted":1}}'
        );
        return response;
      }
      if (endpoint.contains('/api/jobs/')) {
        pollCalls++;
        if (retryFirstPoll && pollCalls == 1) {
          response.setStatusCode(401);
          response.setBody('{"detail":"expired"}');
          return response;
        }
        response.setStatusCode(200);
        String rowError = failSequence
          ? 'Could not optimize this sequence.'
          : null;
        String dna = failSequence ? null : 'acgtATG';
        response.setBody(
          JSON.serialize(
            new Map<String, Object>{
              'status' => 'done',
              'stage' => 'complete',
              'progress' => new Map<String, Object>{
                'total' => 1,
                'completed' => 1,
                'failed' => failSequence ? 1 : 0
              },
              'results' => new List<Object>{
                new Map<String, Object>{
                  'name' => failSequence ? 'ERROR__row-0' : 'row-0',
                  'display_sequence' => dna,
                  'fidelity' => 'ok',
                  'error' => rowError,
                  'warnings' => new List<String>{ 'Restriction site checked' }
                }
              },
              'warnings' => new List<String>{
                'Site enforcement warning from optimizer'
              }
            }
          )
        );
        return response;
      }
      response.setStatusCode(404);
      response.setBody('{"detail":"not found"}');
      return response;
    }
  }

  @TestSetup
  static void createData() {
    Account account = new Account(Name = 'Codon Test Account');
    insert account;

    String uniqueSku =
      'CODON-TEST-' + EncodingUtil.convertToHex(Crypto.generateAesKey(128));
    Product2 product = new Product2(
      Name = 'Codon Optimizer Test Product',
      StockKeepingUnit = uniqueSku,
      IsActive = true
    );
    insert product;

    insert new ABT_Quote_Request__c(
      ABT_Account__c = account.Id,
      ABT_Product__c = product.Id,
      ABT_Customer_Project_Name__c = 'Codon service test'
    );

    insert new List<Target_Organism__c>{
      new Target_Organism__c(
        Name = 'Escherichia coli',
        Common_Hosts__c = 'E. coli general',
        Slug__c = 'ecoli-test',
        Models_Accepted__c = 'trias;codontransformer',
        Model__c = 'Trias',
        Active__c = true
      ),
      new Target_Organism__c(
        Name = 'Inactive organism',
        Common_Hosts__c = 'Inactive organism',
        Slug__c = 'inactive-test',
        Models_Accepted__c = 'trias',
        Model__c = 'Trias',
        Active__c = false
      ),
      new Target_Organism__c(
        Name = 'Single model organism',
        Common_Hosts__c = 'Single model host',
        Slug__c = 'single-test',
        Models_Accepted__c = 'codontransformer',
        Model__c = 'Codon_Transformer',
        Active__c = true
      )
    };

    Amino_Acid__c pollingRecord = new Amino_Acid__c(
      Amino_Acid_Sequence__c = 'M*',
      Model__c = 'Trias'
    );
    insert pollingRecord;
    insert new Codon_Optimizer_State__c(
      Key__c = 'JOB:poll-job',
      Value__c = JSON.serialize(
        new List<Object>{
          new Map<String, Object>{
            'id' => 'row-0',
            'name' => 'Polling sequence',
            'aminoAcidId' => pollingRecord.Id
          }
        }
      )
    );
    insert new Codon_Optimizer_State__c(
      Key__c = 'JOB:failed-job',
      Value__c = JSON.serialize(
        new List<Object>{
          new Map<String, Object>{
            'id' => 'row-0',
            'name' => 'Failed sequence',
            'aminoAcidId' => pollingRecord.Id
          }
        }
      )
    );
  }

  private static Id quoteRequestId() {
    ABT_Quote_Request__c request = [
      SELECT Id, ABT_Product__r.StockKeepingUnit
      FROM ABT_Quote_Request__c
      LIMIT 1
    ];
    CodonService.testAllowedSkus = new Set<String>{
      request.ABT_Product__r.StockKeepingUnit
    };
    return request.Id;
  }

  @IsTest
  static void getOrganismsReturnsOnlyActiveRecordsAndAcceptedModels() {
    Test.startTest();
    Map<String, Object> response = CodonService.getOrganisms();
    Test.stopTest();

    List<Object> groups = (List<Object>) response.get('groups');
    Map<String, Object> groupRow = (Map<String, Object>) groups[0];
    List<Object> organisms = (List<Object>) groupRow.get('organisms');
    System.assertEquals(2, organisms.size());
    Map<String, Object> ecoli;
    Map<String, Object> single;
    for (Object item : organisms) {
      Map<String, Object> organism = (Map<String, Object>) item;
      if (organism.get('slug') == 'ecoli-test')
        ecoli = organism;
      if (organism.get('slug') == 'single-test')
        single = organism;
    }
    System.assertNotEquals(null, ecoli);
    System.assertEquals(
      new List<String>{ 'trias', 'codontransformer' },
      (List<String>) ecoli.get('models')
    );
    System.assertEquals(null, ecoli.get('default_model'));
    System.assertEquals('codontransformer', single.get('default_model'));
  }

  @IsTest
  static void submitCreatesAminoAcidAndJobStateWithOrganismLink() {
    OptimizerMock mock = new OptimizerMock();
    mock.reset();
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    Map<String, Object> result = CodonService.submitJob(
      quoteRequestId(),
      new List<String>{ 'Submitted sequence' },
      new List<String>{ 'M K *' },
      'trias',
      'ecoli-test',
      'acgt',
      'ttaa',
      true,
      true,
      new List<String>{ 'BsaI' },
      new List<String>{ 'GGWCC' }
    );
    Test.stopTest();

    System.assertEquals('submit-job', result.get('jobId'));
    System.assertEquals(1, result.get('accepted'));
    System.assert(mock.lastJobRequest.contains('>row-0'));
    System.assert(mock.lastJobRequest.contains('"organism_slug":"ecoli-test"'));
    System.assert(mock.lastJobRequest.contains('"five_prime":"acgt"'));
    Amino_Acid__c created = [
      SELECT
        Amino_Acid_Sequence__c,
        Model__c,
        Target_Organism__c,
        Flanking_Sequence_5__c,
        Flanking_Sequence_3__c
      FROM Amino_Acid__c
      WHERE Target_Organism__c != NULL
      LIMIT 1
    ];
    System.assertEquals('MK*', created.Amino_Acid_Sequence__c);
    System.assertEquals('Trias', created.Model__c);
    System.assertEquals('acgt', created.Flanking_Sequence_5__c);
    System.assertEquals('ttaa', created.Flanking_Sequence_3__c);
    System.assertEquals(
      [SELECT Id FROM Target_Organism__c WHERE Slug__c = 'ecoli-test'].Id,
      created.Target_Organism__c
    );
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM Codon_Optimizer_State__c
        WHERE Key__c = 'JOB:submit-job'
      ]
    );
  }

  @IsTest
  static void submitRejectsUnknownOrganismAndUnsupportedModel() {
    Boolean unknownRejected = false;
    try {
      CodonService.submitJob(
        quoteRequestId(),
        new List<String>{ 'seq' },
        new List<String>{ 'M*' },
        'trias',
        'missing',
        '',
        '',
        true,
        true,
        null,
        null
      );
    } catch (AuraHandledException e) {
      unknownRejected = true;
    }
    System.assert(unknownRejected, 'Unknown organisms must be rejected.');

    Boolean modelRejected = false;
    try {
      CodonService.submitJob(
        quoteRequestId(),
        new List<String>{ 'seq' },
        new List<String>{ 'M*' },
        'trias',
        'single-test',
        '',
        '',
        true,
        true,
        null,
        null
      );
    } catch (AuraHandledException e) {
      modelRejected = true;
    }
    System.assert(
      modelRejected,
      'Models not accepted by the organism must be rejected.'
    );
  }

  @IsTest
  static void submitRejectsSequenceAndFlankLimits() {
    List<String> names = new List<String>();
    List<String> sequences = new List<String>();
    for (Integer i = 0; i < 97; i++) {
      names.add('seq-' + i);
      sequences.add('M*');
    }
    Boolean countRejected = false;
    try {
      CodonService.submitJob(
        quoteRequestId(),
        names,
        sequences,
        'trias',
        'ecoli-test',
        '',
        '',
        true,
        true,
        null,
        null
      );
    } catch (AuraHandledException e) {
      countRejected = true;
    }
    System.assert(countRejected, 'The 96-record cap must be enforced.');

    Boolean flankRejected = false;
    String longFlank = '';
    for (Integer i = 0; i < 5001; i++)
      longFlank += 'A';
    try {
      CodonService.submitJob(
        quoteRequestId(),
        new List<String>{ 'seq' },
        new List<String>{ 'M*' },
        'trias',
        'ecoli-test',
        longFlank,
        '',
        true,
        true,
        null,
        null
      );
    } catch (AuraHandledException e) {
      flankRejected = true;
    }
    System.assert(
      flankRejected,
      'Flanks over 5,000 nucleotides must be rejected.'
    );
  }

  @IsTest
  static void pollMapsSuccessfulResultAndUpdatesAminoAcid() {
    OptimizerMock mock = new OptimizerMock();
    mock.reset();
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    Map<String, Object> result = CodonService.getJobStatus('poll-job');
    Test.stopTest();

    List<Object> rows = (List<Object>) result.get('results');
    Map<String, Object> row = (Map<String, Object>) rows[0];
    System.assertEquals('Polling sequence', row.get('name'));
    System.assertEquals('acgtATG', row.get('dna'));
    System.assertEquals(
      'Site enforcement warning from optimizer',
      ((List<String>) result.get('warnings'))[0]
    );
    Amino_Acid__c updated = [
      SELECT Optimized_Sequence__c, Amino_Acid_Error__c
      FROM Amino_Acid__c
      LIMIT 1
    ];
    System.assertEquals('acgtATG', updated.Optimized_Sequence__c);
    System.assertEquals(null, updated.Amino_Acid_Error__c);
  }

  @IsTest
  static void pollRetriesOnceAfterUnauthorizedAndRetainsPerSequenceError() {
    OptimizerMock mock = new OptimizerMock();
    mock.reset();
    mock.retryFirstPoll = true;
    mock.failSequence = true;
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    Map<String, Object> result = CodonService.getJobStatus('failed-job');
    Test.stopTest();

    System.assertEquals(2, mock.authCalls);
    System.assertEquals(2, mock.pollCalls);
    Map<String, Object> row = (Map<String, Object>) ((List<Object>) result.get(
      'results'
    ))[0];
    System.assertEquals('Failed sequence', row.get('name'));
    System.assertEquals('Could not optimize this sequence.', row.get('error'));
    Amino_Acid__c updated = [
      SELECT Amino_Acid_Error__c
      FROM Amino_Acid__c
      LIMIT 1
    ];
    System.assertEquals(
      'Could not optimize this sequence.',
      updated.Amino_Acid_Error__c
    );
  }

  @IsTest
  static void rejectsInvalidJobIdsAndAuthenticationFailure() {
    Boolean invalidIdRejected = false;
    try {
      CodonService.getJobStatus('../bad');
    } catch (AuraHandledException e) {
      invalidIdRejected = true;
    }
    System.assert(invalidIdRejected);

    OptimizerMock mock = new OptimizerMock();
    mock.reset();
    mock.failAuthentication = true;
    Test.setMock(HttpCalloutMock.class, mock);
    Boolean authRejected = false;
    try {
      CodonService.getJobStatus('auth-failure');
    } catch (AuraHandledException e) {
      authRejected = true;
    }
    System.assert(authRejected);
  }
}
