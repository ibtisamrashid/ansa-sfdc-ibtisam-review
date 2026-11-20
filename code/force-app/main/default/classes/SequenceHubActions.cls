/** Narrow, account-scoped mutations for Sequence Hub. Browser inputs never choose an account. */
public without sharing class SequenceHubActions {
  @TestVisible
  private static Id testAccountId;

  public static Id currentAccountId() {
    if (Test.isRunningTest() && testAccountId != null)
      return testAccountId;
    User caller = [
      SELECT Contact.AccountId
      FROM User
      WHERE Id = :UserInfo.getUserId()
    ];
    if (caller.Contact == null || caller.Contact.AccountId == null)
      throw new AuraHandledException(
        'Sign in with an account-linked portal user.'
      );
    return caller.Contact.AccountId;
  }

  public static Sequence__c accessibleSequence(Id sequenceId) {
    Id accountId = currentAccountId();
    List<Sequence__c> records = [
      SELECT
        Id,
        Sequence_Name__c,
        Sequence__c,
        Vector__c,
        Sequence_Account__c,
        Quote_Line_Item__c,
        Order_Product__c
      FROM Sequence__c
      WHERE Id = :sequenceId
      WITH USER_MODE
      LIMIT 1
    ];
    if (records.isEmpty() || records[0].Sequence_Account__c != accountId)
      throw new AuraHandledException(
        'This sequence is unavailable for your account.'
      );
    return records[0];
  }

  @AuraEnabled
  public static Map<String, Object> getQuoteOptions() {
    Id accountId = currentAccountId();
    List<Map<String, Object>> quotes = new List<Map<String, Object>>();
    for (ABT_Quote_Request__c request : [
      SELECT
        Id,
        Name,
        ABT_Customer_Project_Name__c,
        ABT_Product__r.Name,
        ABT_Product__r.Vector_Enabled__c,
        ABT_Quote__r.Status
      FROM ABT_Quote_Request__c
      WHERE
        ABT_Account__c = :accountId
        AND ABT_Product__c != NULL
        AND ABT_Quote__c != NULL
        AND ABT_Quote__r.Status NOT IN ('Ordered', 'Rejected')
      ORDER BY CreatedDate DESC
      LIMIT 100
    ])
      quotes.add(
        new Map<String, Object>{
          'value' => request.Id,
          'label' => request.Name +
          ' - ' +
          request.ABT_Customer_Project_Name__c +
          ' (' +
          request.ABT_Product__r.Name +
          ')',
          'requiresVector' => request.ABT_Product__r.Vector_Enabled__c
        }
      );
    List<Map<String, Object>> vectors = new List<Map<String, Object>>();
    Set<Id> seen = new Set<Id>();
    Map<String, Object> library = ABT_Portal_Controller.getVectorLibraryData(
      accountId
    );
    for (
      String groupName : new List<String>{
        'catalogVectors',
        'customVectors',
        'internalVectors'
      }
    ) {
      List<Vector__c> groupRows = (List<Vector__c>) library.get(groupName);
      if (groupRows == null)
        continue;
      for (Vector__c vector : groupRows) {
        if (vector.Active__c != true || seen.contains(vector.Id))
          continue;
        seen.add(vector.Id);
        vectors.add(
          new Map<String, Object>{
            'value' => vector.Id,
            'label' => vector.Name
          }
        );
      }
    }
    return new Map<String, Object>{ 'quotes' => quotes, 'vectors' => vectors };
  }

  @AuraEnabled
  public static Map<String, Object> addToQuote(
    List<Id> sequenceIds,
    Id quoteRequestId,
    Id vectorId
  ) {
    if (sequenceIds == null || sequenceIds.isEmpty() || sequenceIds.size() > 25)
      throw new AuraHandledException('Select between 1 and 25 sequences.');
    Set<Id> ids = new Set<Id>(sequenceIds);
    if (ids.size() != sequenceIds.size() || ids.contains(null))
      throw new AuraHandledException('Select each sequence only once.');
    Id accountId = currentAccountId();
    List<Sequence__c> originals = [
      SELECT Id, Sequence_Name__c, Sequence__c, Sequence_Account__c, Vector__c
      FROM Sequence__c
      WHERE Id IN :ids
      WITH USER_MODE
    ];
    if (originals.size() != ids.size())
      throw new AuraHandledException(
        'One or more selected sequences are unavailable.'
      );
    for (Sequence__c original : originals) {
      if (
        original.Sequence_Account__c != accountId ||
        String.isBlank(original.Sequence__c)
      )
        throw new AuraHandledException(
          'Every selected sequence must belong to your account and contain DNA.'
        );
    }
    // Read annotation metadata only after record visibility and account checks above.
    Map<Id, Sequence__c> annotationsById = new Map<Id, Sequence__c>(
      [
        SELECT
          Id,
          Manual_Annotations__c,
          Plannotate_Features__c,
          Plannotate_Sequence_Hash__c,
          Plannotate_Status__c
        FROM Sequence__c
        WHERE Id IN :ids
      ]
    );
    List<ABT_Quote_Request__c> requests = [
      SELECT
        Id,
        ABT_Account__c,
        ABT_Quote__c,
        ABT_Quote__r.Status,
        ABT_Product__r.Vector_Enabled__c
      FROM ABT_Quote_Request__c
      WHERE
        Id = :quoteRequestId
        AND ABT_Account__c = :accountId
        AND ABT_Product__c != NULL
      LIMIT 1
      FOR UPDATE
    ];
    if (
      requests.isEmpty() ||
      requests[0].ABT_Quote__c == null ||
      new Set<String>{ 'Ordered', 'Rejected' }
        .contains(requests[0].ABT_Quote__r.Status)
    )
      throw new AuraHandledException('Choose an open quote for your account.');
    Map<String, Object> options = getQuoteOptions();
    Set<Id> allowedVectors = new Set<Id>();
    for (
      Map<String, Object> vector : (List<Map<String, Object>>) options.get(
        'vectors'
      )
    )
      allowedVectors.add((Id) vector.get('value'));
    if (vectorId != null && !allowedVectors.contains(vectorId))
      throw new AuraHandledException(
        'Choose a vector available to your account.'
      );
    if (
      requests[0].ABT_Product__r.Vector_Enabled__c == true &&
      vectorId == null
    )
      throw new AuraHandledException('This quote product requires a vector.');
    List<String> names = new List<String>();
    List<String> dna = new List<String>();
    List<Id> vectors = new List<Id>();
    for (Sequence__c original : originals) {
      names.add(original.Sequence_Name__c);
      dna.add(original.Sequence__c);
      vectors.add(vectorId);
    }
    Savepoint beforeAdd = Database.setSavepoint();
    try {
      List<ABT_Quote_Request_Lineitem__c> added = ABT_PortalSequenceCreate.createQuoteRequestLineItemsDeferredKick(
        quoteRequestId,
        names,
        dna,
        vectors,
        null,
        null,
        null
      );
      Set<Id> copies = new Set<Id>();
      if (added.size() != originals.size())
        throw new AuraHandledException(
          'The quote did not accept all selected sequences.'
        );
      List<Sequence__c> copiedAnnotations = new List<Sequence__c>();
      for (Integer index = 0; index < added.size(); index++) {
        ABT_Quote_Request_Lineitem__c line = added[index];
        if (line == null || line.Related_Sequence__c == null)
          throw new AuraHandledException(
            'A selected sequence could not be added. Nothing was added.'
          );
        copies.add(line.Related_Sequence__c);
        Sequence__c original = annotationsById.get(originals[index].Id);
        copiedAnnotations.add(
          new Sequence__c(
            Id = line.Related_Sequence__c,
            Manual_Annotations__c = original.Manual_Annotations__c,
            Plannotate_Features__c = original.Plannotate_Features__c,
            Plannotate_Sequence_Hash__c = original.Plannotate_Sequence_Hash__c,
            Plannotate_Status__c = original.Plannotate_Status__c == 'Complete'
              ? 'Complete'
              : null
          )
        );
      }
      update copiedAnnotations;
      SequenceHubFeasibility.enqueue(copies);
      return new Map<String, Object>{
        'quoteRequestId' => quoteRequestId,
        'added' => added.size()
      };
    } catch (Exception e) {
      Database.rollback(beforeAdd);
      throw new AuraHandledException(
        'No sequences were added: ' + e.getMessage()
      );
    }
  }

  @AuraEnabled
  public static List<Object> saveAnnotations(
    Id sequenceId,
    String annotationsJson
  ) {
    Sequence__c sequence = accessibleSequence(sequenceId);
    List<Object> features = validateFeatures(
      annotationsJson,
      sequence.Sequence__c == null ? 0 : sequence.Sequence__c.length()
    );
    update new Sequence__c(
      Id = sequenceId,
      Manual_Annotations__c = JSON.serialize(features)
    );
    return features;
  }

  public static List<Object> validateFeatures(
    String annotationsJson,
    Integer length
  ) {
    if (annotationsJson == null || annotationsJson.length() > 32000)
      throw new AuraHandledException(
        'Annotation data is missing or too large.'
      );
    List<Object> features;
    try {
      features = (List<Object>) JSON.deserializeUntyped(annotationsJson);
    } catch (Exception e) {
      throw new AuraHandledException('Annotations must be a list of features.');
    }
    if (features == null || features.size() > 200)
      throw new AuraHandledException('Save at most 200 annotation features.');
    List<Object> clean = new List<Object>();
    for (Object item : features) {
      try {
        Map<String, Object> feature = (Map<String, Object>) item;
        String label = (String) feature.get('label');
        Integer start = Integer.valueOf(String.valueOf(feature.get('start')));
        Integer finish = Integer.valueOf(String.valueOf(feature.get('end')));
        String strand = String.valueOf(feature.get('strand'));
        if (
          String.isBlank(label) ||
          label.length() > 80 ||
          start < 1 ||
          finish < start ||
          finish > length ||
          !new Set<String>{ '1', '-1' }.contains(strand)
        )
          throw new IllegalArgumentException();
        clean.add(
          new Map<String, Object>{
            'label' => label.trim(),
            'start' => start,
            'end' => finish,
            'strand' => strand
          }
        );
      } catch (Exception e) {
        throw new AuraHandledException(
          'Each feature needs a name (up to 80 characters), a valid 1-based start/end within the DNA, and strand 1 or -1.'
        );
      }
    }
    return clean;
  }

  private static Sequence__c lockedAnnotations(Id sequenceId) {
    Sequence__c accessible = accessibleSequence(sequenceId);
    Sequence__c stored = [
      SELECT
        Sequence__c,
        Sequence_Account__c,
        Manual_Annotations__c,
        Plannotate_Features__c
      FROM Sequence__c
      WHERE Id = :sequenceId
      FOR UPDATE
    ];
    if (stored.Sequence_Account__c != accessible.Sequence_Account__c)
      throw new AuraHandledException(
        'The sequence account changed. Refresh and try again.'
      );
    return stored;
  }

  private static List<Object> storedFeatures(String json, Integer length) {
    return validateFeatures(String.isBlank(json) ? '[]' : json, length);
  }

  @AuraEnabled
  public static void appendManualAnnotations(
    Id sequenceId,
    String annotationsJson
  ) {
    Sequence__c stored = lockedAnnotations(sequenceId);
    Integer length = stored.Sequence__c == null
      ? 0
      : stored.Sequence__c.length();
    List<Object> features = storedFeatures(
      stored.Manual_Annotations__c,
      length
    );
    Set<String> seen = new Set<String>();
    for (Object feature : features)
      seen.add(JSON.serialize(feature));
    for (Object feature : validateFeatures(annotationsJson, length)) {
      String key = JSON.serialize(feature);
      if (seen.add(key))
        features.add(feature);
    }
    features = validateFeatures(JSON.serialize(features), length);
    update new Sequence__c(
      Id = sequenceId,
      Manual_Annotations__c = JSON.serialize(features)
    );
  }

  @AuraEnabled
  public static void removeManualFeature(
    Id sequenceId,
    Integer featureIndex,
    String featureJson
  ) {
    removeSavedFeature(
      sequenceId,
      featureIndex,
      featureJson,
      'Manual_Annotations__c'
    );
  }

  @AuraEnabled
  public static void removePlannotateFeature(
    Id sequenceId,
    Integer featureIndex,
    String featureJson
  ) {
    removeSavedFeature(
      sequenceId,
      featureIndex,
      featureJson,
      'Plannotate_Features__c'
    );
  }

  private static void removeSavedFeature(
    Id sequenceId,
    Integer featureIndex,
    String featureJson,
    String fieldName
  ) {
    Sequence__c stored = lockedAnnotations(sequenceId);
    Integer length = stored.Sequence__c == null
      ? 0
      : stored.Sequence__c.length();
    List<Object> features = storedFeatures(
      (String) stored.get(fieldName),
      length
    );
    List<Object> expected = validateFeatures('[' + featureJson + ']', length);
    if (
      featureIndex == null ||
      featureIndex < 0 ||
      featureIndex >= features.size() ||
      expected.size() != 1 ||
      JSON.serialize(features[featureIndex]) != JSON.serialize(expected[0])
    ) {
      throw new AuraHandledException(
        'The annotation changed. Refresh the sequence and try again.'
      );
    }
    features.remove(featureIndex);
    Sequence__c patch = new Sequence__c(Id = sequenceId);
    patch.put(fieldName, JSON.serialize(features));
    update patch;
  }

  @AuraEnabled
  public static void renameSequence(Id sequenceId, String name) {
    accessibleSequence(sequenceId);
    if (String.isBlank(name) || name.trim().length() > 255)
      throw new AuraHandledException(
        'Enter a sequence name of 1 to 255 characters.'
      );
    update new Sequence__c(Id = sequenceId, Sequence_Name__c = name.trim());
  }

  @AuraEnabled
  public static void requestFeasibility(Id sequenceId) {
    Sequence__c sequence = accessibleSequence(sequenceId);
    if (String.isBlank(sequence.Sequence__c))
      throw new AuraHandledException('Add DNA before requesting feasibility.');
    if (sequence.Order_Product__c != null)
      throw new AuraHandledException('Ordered sequences cannot be changed.');
    if (sequence.Quote_Line_Item__c != null) {
      List<QuoteLineItem> linked = [
        SELECT Quote.Status
        FROM QuoteLineItem
        WHERE Id = :sequence.Quote_Line_Item__c
        LIMIT 1
      ];
      if (
        !linked.isEmpty() &&
        new Set<String>{ 'Ordered', 'Rejected' }
          .contains(linked[0].Quote.Status)
      )
        throw new AuraHandledException(
          'Sequences on closed quotes cannot be changed.'
        );
    }
    update new Sequence__c(
      Id = sequenceId,
      Sequence_Classification__c = 'Pending',
      Feasibility_Classifier__c = 'Pending'
    );
    SequenceHubFeasibility.enqueue(new Set<Id>{ sequenceId });
  }

  @AuraEnabled
  public static void saveVector(Id sequenceId, Id vectorId) {
    Sequence__c sequence = accessibleSequence(sequenceId);
    if (sequence.Order_Product__c != null)
      throw new AuraHandledException('Ordered sequences cannot be changed.');
    if (sequence.Quote_Line_Item__c != null) {
      QuoteLineItem line = [
        SELECT Quote.Status, Product2.Vector_Enabled__c
        FROM QuoteLineItem
        WHERE Id = :sequence.Quote_Line_Item__c
      ];
      if (new Set<String>{ 'Ordered', 'Rejected' }.contains(line.Quote.Status))
        throw new AuraHandledException(
          'Sequences on closed quotes cannot be changed.'
        );
      if (line.Product2.Vector_Enabled__c == true && vectorId == null)
        throw new AuraHandledException(
          'This sequence product requires a vector.'
        );
    }
    if (vectorId != null) {
      Boolean available = false;
      for (
        Map<String, Object> vector : (List<Map<String, Object>>) getQuoteOptions()
          .get('vectors')
      )
        if ((Id) vector.get('value') == vectorId)
          available = true;
      if (!available)
        throw new AuraHandledException(
          'Choose an active vector available to your account.'
        );
    }
    update new Sequence__c(
      Id = sequence.Id,
      Vector__c = vectorId,
      Sequence_Classification__c = 'Pending',
      Feasibility_Classifier__c = 'Pending'
    );
    SequenceHubFeasibility.enqueue(new Set<Id>{ sequence.Id });
  }
}
