/** Direct client for the optimizer's cookie-authenticated FastAPI API. */
public without sharing class CodonService {
  @TestVisible
  private static Set<String> testAllowedSkus;
  private static final String NAMED_CREDENTIAL = 'callout:Codon_Optimizer';
  private static final Integer MAX_SEQUENCES = 96;
  private static final Integer MAX_PROTEIN_LENGTH = 2045;
  private static final Integer MAX_FLANK_LENGTH = 5000;
  private static final Integer SESSION_TTL_SECONDS = 39600; // Optimizer cookie lasts 12 hours.

  public static Map<String, Object> getOrganisms() {
    List<Object> organismsOut = new List<Object>();
    for (Target_Organism__c organism : [
      SELECT Common_Hosts__c, Models_Accepted__c, Slug__c
      FROM Target_Organism__c
      WHERE Active__c = TRUE AND Slug__c != NULL
      ORDER BY Common_Hosts__c
    ]) {
      List<String> models = new List<String>();
      if (String.isNotBlank(organism.Models_Accepted__c)) {
        for (String acceptedModel : organism.Models_Accepted__c.split(';')) {
          String modelKey = toModelKey(acceptedModel);
          if (String.isNotBlank(modelKey) && !models.contains(modelKey))
            models.add(modelKey);
        }
      }
      String defaultModel = models.size() == 1 ? models[0] : null;
      organismsOut.add(
        new Map<String, Object>{
          'slug' => organism.Slug__c,
          'name' => organism.Common_Hosts__c,
          'models' => models,
          'default_model' => defaultModel
        }
      );
    }
    return new Map<String, Object>{
      'groups' => new List<Object>{
        new Map<String, Object>{
          'label' => 'Common Hosts',
          'organisms' => organismsOut
        }
      }
    };
  }

  public static Map<String, Object> submitJob(
    Id quoteRequestId,
    List<String> names,
    List<String> sequences,
    String modelKey,
    String organismSlug,
    String flank5,
    String flank3,
    Boolean includeStop,
    Boolean deterministic,
    List<String> enzymes,
    List<String> customSites
  ) {
    validateClonalQuote(quoteRequestId);
    return submitJobInternal(
      null,
      null,
      names,
      sequences,
      modelKey,
      organismSlug,
      flank5,
      flank3,
      includeStop,
      deterministic,
      enzymes,
      customSites
    );
  }

  public static Map<String, Object> submitSequenceJob(
    Id sequenceId,
    Id aminoAcidId,
    List<String> names,
    List<String> sequences,
    String modelKey,
    String organismSlug,
    String flank5,
    String flank3,
    Boolean includeStop,
    Boolean deterministic,
    List<String> enzymes,
    List<String> customSites
  ) {
    validateSequenceForOptimization(sequenceId, aminoAcidId);
    if (sequences == null || sequences.size() != 1) {
      throw new AuraHandledException(
        'Sequence Hub optimization accepts one sequence at a time.'
      );
    }
    return submitJobInternal(
      sequenceId,
      aminoAcidId,
      names,
      sequences,
      modelKey,
      organismSlug,
      flank5,
      flank3,
      includeStop,
      deterministic,
      enzymes,
      customSites
    );
  }

  private static Map<String, Object> submitJobInternal(
    Id sequenceId,
    Id existingAminoAcidId,
    List<String> names,
    List<String> sequences,
    String modelKey,
    String organismSlug,
    String flank5,
    String flank3,
    Boolean includeStop,
    Boolean deterministic,
    List<String> enzymes,
    List<String> customSites
  ) {
    if (
      names == null ||
      sequences == null ||
      names.size() != sequences.size() ||
      sequences.isEmpty()
    ) {
      throw new AuraHandledException(
        'Upload at least one valid amino acid sequence.'
      );
    }
    if (sequences.size() > MAX_SEQUENCES)
      throw new AuraHandledException('Maximum 96 sequences per upload.');
    if (String.isBlank(organismSlug) || String.isBlank(modelKey)) {
      throw new AuraHandledException('Select a target organism and model.');
    }
    Target_Organism__c organism = getActiveOrganism(organismSlug);
    if (
      organism == null ||
      !acceptedModelKeys(organism.Models_Accepted__c)
        .contains(toModelKey(modelKey))
    ) {
      throw new AuraHandledException(
        'The selected model is not available for this target organism.'
      );
    }
    validateFlank(flank5, '5\'');
    validateFlank(flank3, '3\'');

    String fasta = '';
    List<Object> rowMap = new List<Object>();
    for (Integer i = 0; i < sequences.size(); i++) {
      String sequence = sequences[i] == null
        ? ''
        : sequences[i].replaceAll('\\s+', '').toUpperCase();
      if (String.isBlank(sequence))
        throw new AuraHandledException('Sequence ' + (i + 1) + ' is empty.');
      if (!Pattern.matches('[ACDEFGHIKLMNPQRSTVWY*]+', sequence))
        throw new AuraHandledException(
          'Sequence ' + (i + 1) + ' contains unsupported amino acid characters.'
        );
      if (sequence.length() > MAX_PROTEIN_LENGTH) {
        throw new AuraHandledException(
          'Sequence ' +
            (i + 1) +
            ' exceeds the optimizer limit of 2,045 amino acids.'
        );
      }
      String tempId = 'row-' + i;
      String rowName = String.isBlank(names[i])
        ? 'Sequence_' + (i + 1)
        : names[i];
      fasta += '>' + tempId + '\r\n' + sequence + '\r\n';
      rowMap.add(new Map<String, Object>{ 'id' => tempId, 'name' => rowName });
    }

    Map<String, Object> payload = new Map<String, Object>{
      'model_key' => modelKey,
      'organism_slug' => organismSlug,
      'flanks' => new Map<String, Object>{
        'five_prime' => blankIfNull(flank5),
        'three_prime' => blankIfNull(flank3)
      },
      'include_stop_codon' => includeStop != false,
      'input_type' => 'protein',
      'forbidden_sites' => new Map<String, Object>{
        'enzymes' => enzymes == null ? new List<String>() : enzymes,
        'custom' => customSites == null ? new List<String>() : customSites
      },
      'params' => new Map<String, Object>{
        'deterministic' => deterministic != false
      }
    };
    String boundary =
      '----CodonBoundary' +
      EncodingUtil.convertToHex(Crypto.generateAesKey(128));
    String body = multipartBody(boundary, fasta, JSON.serialize(payload));
    HttpResponse response = send(
      'POST',
      '/api/jobs',
      Blob.valueOf(body),
      'multipart/form-data; boundary=' + boundary,
      true
    );
    Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(
      response.getBody()
    );
    String jobId = (String) responseBody.get('job_id');
    if (String.isBlank(jobId))
      throw new AuraHandledException(
        'The optimizer did not return a job ID. Please try again.'
      );

    List<Amino_Acid__c> aminoAcidRows = new List<Amino_Acid__c>();
    for (Integer i = 0; i < sequences.size(); i++) {
      String normalizedSequence = sequences[i]
        .replaceAll('\\s+', '')
        .toUpperCase();
      String modelValue = toModelValue(modelKey);
      Amino_Acid__c aminoAcidRow = new Amino_Acid__c(
        Amino_Acid_Sequence__c = normalizedSequence,
        Model__c = modelValue,
        Flanking_Sequence_5__c = blankIfNull(flank5),
        Flanking_Sequence_3__c = blankIfNull(flank3),
        Target_Organism__c = organism.Id,
        Related_Sequence__c = sequenceId,
        Optimized_Sequence__c = null,
        Amino_Acid_Error__c = null
      );
      if (sequenceId != null && existingAminoAcidId != null)
        aminoAcidRow.Id = existingAminoAcidId;
      aminoAcidRows.add(aminoAcidRow);
    }
    upsert aminoAcidRows;

    // Keep original display names associated with FASTA headers across polling transactions.
    for (Integer i = 0; i < rowMap.size(); i++) {
      ((Map<String, Object>) rowMap[i]).put('aminoAcidId', aminoAcidRows[i].Id);
      if (sequenceId != null) {
        ((Map<String, Object>) rowMap[i]).put('sequenceId', sequenceId);
        ((Map<String, Object>) rowMap[i]).put('ownerId', UserInfo.getUserId());
      }
    }
    Codon_Optimizer_State__c jobState = new Codon_Optimizer_State__c(
      Key__c = 'JOB:' + jobId,
      Value__c = JSON.serialize(rowMap)
    );
    upsert jobState Key__c;
    Map<String, Object> report = (Map<String, Object>) responseBody.get(
      'parse_report'
    );
    Integer accepted = sequences.size();
    if (report != null && report.containsKey('accepted'))
      accepted = asInteger(report.get('accepted'));
    return new Map<String, Object>{
      'jobId' => jobId,
      'status' => 'queued',
      'accepted' => accepted
    };
  }

  private static void validateSequenceForOptimization(
    Id sequenceId,
    Id aminoAcidId
  ) {
    if (sequenceId == null)
      throw new AuraHandledException('Select a sequence to optimize.');
    List<Sequence__c> records = [
      SELECT Id, Product_SKU__c, Quote_Line_Item__c, Order_Product__c
      FROM Sequence__c
      WHERE Id = :sequenceId
      WITH USER_MODE
      LIMIT 1
    ];
    if (records.isEmpty())
      throw new AuraHandledException('This sequence is unavailable.');
    Sequence__c sequenceRecord = records[0];
    Boolean isStandalone =
      sequenceRecord.Quote_Line_Item__c == null &&
      sequenceRecord.Order_Product__c == null;
    if (
      !(isStandalone && String.isBlank(sequenceRecord.Product_SKU__c)) &&
      !new Set<String>{ '1002', '6001', '6003' }
        .contains(sequenceRecord.Product_SKU__c)
    ) {
      throw new AuraHandledException(
        'Optimization is available for Clonal DNA and XL Clonal DNA only.'
      );
    }
    if (sequenceRecord.Order_Product__c != null)
      throw new AuraHandledException(
        'Ordered sequences cannot be re-optimized.'
      );
    String quoteStatus = getQuoteStatus(sequenceRecord.Quote_Line_Item__c);
    if (quoteStatus == 'Ordered' || quoteStatus == 'Rejected')
      throw new AuraHandledException(
        'This sequence cannot be re-optimized because its quote is closed.'
      );
    // The optimizer validates a user-supplied protein when no linked protein exists.
    if (aminoAcidId == null)
      return;
    List<Amino_Acid__c> aminoAcids = [
      SELECT Id, Related_Sequence__c, Amino_Acid_Sequence__c
      FROM Amino_Acid__c
      WHERE Id = :aminoAcidId
      WITH USER_MODE
      LIMIT 1
    ];
    if (aminoAcids.isEmpty() || aminoAcids[0].Related_Sequence__c != sequenceId)
      throw new AuraHandledException(
        'The amino acid record does not belong to this sequence.'
      );
    if (String.isBlank(aminoAcids[0].Amino_Acid_Sequence__c))
      throw new AuraHandledException(
        'This sequence has no linked amino acid protein to optimize.'
      );
  }

  /**
   * Called only after the caller's Sequence row has been verified in USER_MODE.
   * Reads just the related Quote status needed to enforce the optimizer guard.
   */
  private static String getQuoteStatus(Id quoteLineItemId) {
    if (quoteLineItemId == null)
      return null;
    List<QuoteLineItem> lineItems = [
      SELECT Quote.Status
      FROM QuoteLineItem
      WHERE Id = :quoteLineItemId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    return lineItems.isEmpty() || lineItems[0].Quote == null
      ? null
      : lineItems[0].Quote.Status;
  }

  private static Target_Organism__c getActiveOrganism(String slug) {
    List<Target_Organism__c> organisms = [
      SELECT Id, Models_Accepted__c
      FROM Target_Organism__c
      WHERE Slug__c = :slug AND Active__c = TRUE
      LIMIT 1
    ];
    return organisms.isEmpty() ? null : organisms[0];
  }

  private static Set<String> acceptedModelKeys(String acceptedModels) {
    Set<String> modelKeys = new Set<String>();
    if (String.isNotBlank(acceptedModels)) {
      for (String acceptedModel : acceptedModels.split(';')) {
        modelKeys.add(toModelKey(acceptedModel));
      }
    }
    return modelKeys;
  }

  private static String toModelKey(String modelValue) {
    if (String.isBlank(modelValue))
      return null;
    return modelValue.toLowerCase().replaceAll('[^a-z0-9]', '');
  }

  private static String toModelValue(String modelKey) {
    String normalized = toModelKey(modelKey);
    if (normalized == 'trias')
      return 'Trias';
    if (normalized == 'codontransformer')
      return 'Codon_Transformer';
    return modelKey;
  }

  private static void validateClonalQuote(Id quoteRequestId) {
    if (quoteRequestId == null) {
      throw new AuraHandledException(
        'A clonal DNA quote is required for amino acid optimization.'
      );
    }
    List<ABT_Quote_Request__c> quoteRequests = [
      SELECT ABT_Product__r.StockKeepingUnit
      FROM ABT_Quote_Request__c
      WHERE Id = :quoteRequestId
      LIMIT 1
    ];
    Set<String> allowedSkus = Test.isRunningTest() && testAllowedSkus != null
      ? testAllowedSkus
      : new Set<String>{ '1002', '6001', '6003' };
    if (
      quoteRequests.isEmpty() ||
      quoteRequests[0].ABT_Product__r == null ||
      !allowedSkus.contains(quoteRequests[0].ABT_Product__r.StockKeepingUnit)
    ) {
      throw new AuraHandledException(
        'Amino acid optimization is available for Clonal DNA and XL Clonal DNA only.'
      );
    }
  }

  public static Map<String, Object> getJobStatus(String jobId) {
    if (
      String.isBlank(jobId) || !Pattern.matches('[A-Za-z0-9_-]{1,80}', jobId)
    ) {
      throw new AuraHandledException('Invalid optimizer job ID.');
    }
    HttpResponse response = send(
      'GET',
      '/api/jobs/' +
        EncodingUtil.urlEncode(jobId, 'UTF-8') +
        '?include_results=true',
      null,
      null,
      true
    );
    Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(
      response.getBody()
    );
    Map<String, Object> result = new Map<String, Object>{
      'jobId' => jobId,
      'status' => data.get('status'),
      'stage' => data.get('stage'),
      'error' => data.get('error')
    };
    Map<String, Object> progress = (Map<String, Object>) data.get('progress');
    Map<String, Object> progressOut = new Map<String, Object>();
    if (progress != null) {
      progressOut.put('total', asInteger(progress.get('total')));
      progressOut.put('completed', asInteger(progress.get('completed')));
      progressOut.put('failed', asInteger(progress.get('failed')));
      progressOut.put(
        'queuePosition',
        asInteger(progress.get('queue_position'))
      );
      progressOut.put('etaSeconds', asInteger(progress.get('eta_seconds')));
    }
    result.put('progress', progressOut);

    Map<String, Map<String, Object>> jobRowsById = loadJobRows(jobId);
    Map<String, String> namesById = new Map<String, String>();
    for (String rowId : jobRowsById.keySet())
      namesById.put(rowId, (String) jobRowsById.get(rowId).get('name'));
    List<Object> resultRows = new List<Object>();
    List<Amino_Acid__c> aminoAcidUpdates = new List<Amino_Acid__c>();
    List<Object> rawResults = (List<Object>) data.get('results');
    if (rawResults != null)
      for (Object raw : rawResults) {
        Map<String, Object> row = (Map<String, Object>) raw;
        String rawName = (String) row.get('name');
        String returnedId = (String) row.get('record_id');
        String tempId = String.isNotBlank(returnedId)
          ? returnedId
          : rawName == null ? null : rawName.replaceFirst('^ERROR__', '');
        String displayName = namesById.containsKey(tempId)
          ? namesById.get(tempId)
          : rawName;
        List<String> rowWarnings = stringList(row.get('warnings'));
        Map<String, Object> jobRow = jobRowsById.get(tempId);
        Id aminoAcidId = jobRow == null ||
          jobRow.get('aminoAcidId') == null
          ? null
          : Id.valueOf(String.valueOf(jobRow.get('aminoAcidId')));
        String rowError = (String) row.get('error');
        String dna = (String) row.get('display_sequence');
        if (
          String.isBlank(rowError) &&
          row.get('fidelity') != null &&
          row.get('fidelity') != 'ok'
        ) {
          rowError =
            'Sequence verification failed (' +
            String.valueOf(row.get('fidelity')) +
            ').';
        }
        if (rowError != null && rowError.length() > 1000)
          rowError = rowError.substring(0, 1000);
        Id sequenceId = jobRow == null ||
          jobRow.get('sequenceId') == null
          ? null
          : Id.valueOf(String.valueOf(jobRow.get('sequenceId')));
        if (
          sequenceId != null &&
          String.valueOf(jobRow.get('ownerId')) != UserInfo.getUserId()
        ) {
          throw new AuraHandledException(
            'This optimizer job is not available to your user.'
          );
        }
        Boolean isDone = String.valueOf(data.get('status')) == 'done';
        Boolean saveAsCopy = sequenceId != null;
        // Hub jobs leave the original protein row alone on success and only
        // record an error on it. Other jobs keep the old behavior.
        if (
          aminoAcidId != null &&
          isDone &&
          (!saveAsCopy || String.isNotBlank(rowError))
        ) {
          aminoAcidUpdates.add(
            new Amino_Acid__c(
              Id = aminoAcidId,
              Optimized_Sequence__c = dna,
              Amino_Acid_Error__c = rowError
            )
          );
        }
        if (
          saveAsCopy &&
          isDone &&
          String.isBlank(rowError) &&
          String.isNotBlank(dna)
        ) {
          result.put(
            'optimizedSequenceId',
            createOptimizedCopy(jobId, sequenceId, aminoAcidId, dna)
          );
        }
        Map<String, Object> outputRow = new Map<String, Object>{
          'recordId' => tempId,
          'name' => displayName,
          'dna' => dna,
          'error' => rowError,
          'fidelity' => row.get('fidelity'),
          'warnings' => rowWarnings
        };
        if (aminoAcidId != null)
          outputRow.put('aminoAcidId', aminoAcidId);
        resultRows.add(outputRow);
      }
    if (!aminoAcidUpdates.isEmpty())
      update aminoAcidUpdates;
    result.put('results', resultRows);
    result.put('warnings', stringList(data.get('warnings')));
    return result;
  }

  /**
   * Hub optimization saves the result as a NEW Sequence__c and leaves the
   * original untouched. The copy keeps the original's account (so the
   * sharing set still applies), owner, vector and SKU, but not its quote
   * line item. Polling can call getJobStatus repeatedly, so the new record
   * Id is remembered under COPY:<jobId> to avoid duplicate copies.
   */
  private static Id createOptimizedCopy(
    String jobId,
    Id originalId,
    Id aminoAcidId,
    String dna
  ) {
    String copyKey = 'COPY:' + jobId;
    List<Codon_Optimizer_State__c> existing = [
      SELECT Value__c
      FROM Codon_Optimizer_State__c
      WHERE Key__c = :copyKey
      LIMIT 1
    ];
    if (!existing.isEmpty() && String.isNotBlank(existing[0].Value__c)) {
      return Id.valueOf(existing[0].Value__c);
    }
    // The original was checked in USER_MODE at job submission.
    Sequence__c original = [
      SELECT
        Sequence_Name__c,
        OwnerId,
        Sequence_Account__c,
        Vector__c,
        Product_SKU__c,
        Product_Code__c
      FROM Sequence__c
      WHERE Id = :originalId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    String baseName = String.isBlank(original.Sequence_Name__c)
      ? 'Sequence'
      : original.Sequence_Name__c;
    if (baseName.length() > 240)
      baseName = baseName.substring(0, 240);
    Sequence__c copy = new Sequence__c(
      OwnerId = original.OwnerId,
      Sequence_Name__c = baseName + '_optimized',
      Sequence__c = dna,
      Sequence_Length__c = dna.length(),
      Sequence_Account__c = original.Sequence_Account__c,
      Vector__c = original.Vector__c,
      Product_SKU__c = original.Product_SKU__c,
      Product_Code__c = original.Product_Code__c
    );
    try {
      insert copy;
      if (aminoAcidId != null) {
        Amino_Acid__c src = [
          SELECT
            Amino_Acid_Sequence__c,
            Model__c,
            Flanking_Sequence_5__c,
            Flanking_Sequence_3__c,
            Target_Organism__c
          FROM Amino_Acid__c
          WHERE Id = :aminoAcidId
          LIMIT 1
        ];
        insert new Amino_Acid__c(
          Amino_Acid_Sequence__c = src.Amino_Acid_Sequence__c,
          Model__c = src.Model__c,
          Flanking_Sequence_5__c = src.Flanking_Sequence_5__c,
          Flanking_Sequence_3__c = src.Flanking_Sequence_3__c,
          Target_Organism__c = src.Target_Organism__c,
          Related_Sequence__c = copy.Id,
          Optimized_Sequence__c = dna
        );
      }
    } catch (DmlException e) {
      throw new AuraHandledException(
        'The optimized copy could not be created: ' + e.getDmlMessage(0)
      );
    }
    Codon_Optimizer_State__c copyState = new Codon_Optimizer_State__c(
      Key__c = copyKey,
      Value__c = String.valueOf(copy.Id)
    );
    upsert copyState Key__c;
    SequenceHubFeasibility.enqueue(new Set<Id>{ copy.Id });
    return copy.Id;
  }

  private static Map<String, Map<String, Object>> loadJobRows(String jobId) {
    Map<String, Map<String, Object>> output = new Map<String, Map<String, Object>>();
    String stateKey = 'JOB:' + jobId;
    List<Codon_Optimizer_State__c> rows = [
      SELECT Value__c
      FROM Codon_Optimizer_State__c
      WHERE Key__c = :stateKey
      LIMIT 1
    ];
    if (!rows.isEmpty() && String.isNotBlank(rows[0].Value__c)) {
      for (
        Object entry : (List<Object>) JSON.deserializeUntyped(rows[0].Value__c)
      ) {
        Map<String, Object> row = (Map<String, Object>) entry;
        output.put((String) row.get('id'), row);
      }
    }
    return output;
  }

  public static void linkAminoAcidSequence(Id aminoAcidId, Id sequenceId) {
    if (aminoAcidId == null || sequenceId == null)
      return;
    update new Amino_Acid__c(
      Id = aminoAcidId,
      Related_Sequence__c = sequenceId
    );
  }

  private static HttpResponse send(
    String method,
    String path,
    Blob body,
    String contentType,
    Boolean retryUnauthorized
  ) {
    Codon_Optimizer_State__c state = readSession();
    Boolean authenticatedNow = false;
    String cookie = state != null &&
      state.Expires_At__c != null &&
      state.Expires_At__c > System.now()
      ? state.Value__c
      : null;
    if (String.isBlank(cookie)) {
      cookie = authenticate();
      authenticatedNow = true;
    }
    HttpResponse response = request(method, path, body, contentType, cookie);
    if (response.getStatusCode() == 401 && retryUnauthorized) {
      cookie = authenticate();
      authenticatedNow = true;
      response = request(method, path, body, contentType, cookie);
    }
    if (authenticatedNow)
      saveSession(cookie);
    Integer code = response.getStatusCode();
    if (code < 200 || code >= 300) {
      if (code == 401 || code == 403)
        throw new AuraHandledException(
          'Optimizer authentication failed. Contact support.'
        );
      if (code == 413)
        throw new AuraHandledException(
          'The upload is too large. Reduce the number or length of sequences.'
        );
      throw new AuraHandledException(
        'Optimizer request failed (' + code + '). Please try again.'
      );
    }
    return response;
  }

  private static HttpResponse request(
    String method,
    String path,
    Blob body,
    String contentType,
    String cookie
  ) {
    HttpRequest request = new HttpRequest();
    request.setEndpoint(NAMED_CREDENTIAL + path);
    request.setMethod(method);
    request.setTimeout(20000);
    request.setHeader('Accept', 'application/json');
    if (String.isNotBlank(cookie))
      request.setHeader('Cookie', cookie);
    if (body != null) {
      request.setHeader('Content-Type', contentType);
      request.setBodyAsBlob(body);
    }
    try {
      return new Http().send(request);
    } catch (CalloutException e) {
      throw new AuraHandledException(
        'The optimizer service is temporarily unavailable. Please try again.'
      );
    }
  }

  private static String authenticate() {
    HttpRequest request = new HttpRequest();
    request.setEndpoint(NAMED_CREDENTIAL + '/api/auth');
    request.setMethod('POST');
    request.setTimeout(20000);
    request.setHeader('Accept', 'application/json');
    request.setHeader('Content-Type', 'application/json');
    // The merge value is a Custom External Credential principal parameter populated in Setup.
    request.setBody(
      '{"password":"{!$Credential.Codon_Optimizer_Auth.AlphaPassword}"}'
    );
    HttpResponse response;
    try {
      response = new Http().send(request);
    } catch (CalloutException e) {
      throw new AuraHandledException(
        'The optimizer service is temporarily unavailable. Please try again.'
      );
    }
    if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
      throw new AuraHandledException(
        'Optimizer authentication failed. Check the External Credential password.'
      );
    }
    String setCookie = response.getHeader('Set-Cookie');
    if (String.isBlank(setCookie))
      throw new AuraHandledException(
        'Optimizer login did not return a session cookie.'
      );
    String cookie = setCookie.split(';')[0].trim();
    if (!cookie.startsWith('codon_alpha='))
      throw new AuraHandledException(
        'Optimizer login returned an unexpected session cookie.'
      );
    return cookie;
  }

  private static Codon_Optimizer_State__c readSession() {
    List<Codon_Optimizer_State__c> rows = [
      SELECT Id, Value__c, Expires_At__c
      FROM Codon_Optimizer_State__c
      WHERE Key__c = 'SESSION'
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0];
  }

  private static void saveSession(String cookie) {
    Codon_Optimizer_State__c sessionState = new Codon_Optimizer_State__c(
      Key__c = 'SESSION',
      Value__c = cookie,
      Expires_At__c = System.now().addSeconds(SESSION_TTL_SECONDS)
    );
    upsert sessionState Key__c;
  }

  private static String multipartBody(
    String boundary,
    String fasta,
    String payload
  ) {
    String crlf = '\r\n';
    return '--' +
      boundary +
      crlf +
      'Content-Disposition: form-data; name="payload"' +
      crlf +
      'Content-Type: text/plain; charset=UTF-8' +
      crlf +
      crlf +
      payload +
      crlf +
      '--' +
      boundary +
      crlf +
      'Content-Disposition: form-data; name="file"; filename="sequences.fasta"' +
      crlf +
      'Content-Type: text/plain; charset=UTF-8' +
      crlf +
      crlf +
      fasta +
      '--' +
      boundary +
      '--' +
      crlf;
  }

  private static List<String> stringList(Object values) {
    List<String> result = new List<String>();
    if (values != null)
      for (Object value : (List<Object>) values)
        result.add(String.valueOf(value));
    return result;
  }
  private static String blankIfNull(String value) {
    return value == null ? '' : value;
  }
  private static Integer asInteger(Object value) {
    return value == null ? null : Integer.valueOf(String.valueOf(value));
  }
  private static void validateFlank(String value, String label) {
    String flank = value == null ? '' : value;
    if (flank.length() > MAX_FLANK_LENGTH)
      throw new AuraHandledException(
        label + ' flank exceeds the optimizer limit of 5,000 nucleotides.'
      );
    if (!Pattern.matches('[ACGTacgt\\s]*', flank))
      throw new AuraHandledException(
        label + ' flank must contain DNA bases only (A, C, G, T).'
      );
  }
}
