/** Read-only portal data access for the Sequence Hub. */
public with sharing class SequenceHubController {
  @AuraEnabled
  public static List<Map<String, Object>> getSequences(
    String searchTerm,
    String ownerName,
    String feasibility,
    String complexity,
    Date createdAfter,
    Date createdBefore,
    Integer pageSize,
    Integer offsetRows
  ) {
    Integer safePageSize = pageSize == null
      ? 25
      : Math.max(1, Math.min(pageSize, 100));
    Integer safeOffset = offsetRows == null
      ? 0
      : Math.max(0, Math.min(offsetRows, 2000));
    List<String> filters = new List<String>();
    Map<String, Object> binds = new Map<String, Object>{
      'safePageSize' => safePageSize,
      'safeOffset' => safeOffset
    };
    if (String.isNotBlank(searchTerm)) {
      filters.add(
        '(Name LIKE :searchPattern OR Sequence_Name__c LIKE :searchPattern)'
      );
      binds.put('searchPattern', '%' + searchTerm.trim() + '%');
    }
    if (String.isNotBlank(ownerName)) {
      filters.add('Owner.Name LIKE :ownerPattern');
      binds.put('ownerPattern', '%' + ownerName.trim() + '%');
    }
    if (String.isNotBlank(feasibility)) {
      filters.add('Feasibility_Classifier__c = :feasibilityFilter');
      binds.put('feasibilityFilter', feasibility);
    }
    if (String.isNotBlank(complexity)) {
      filters.add('Complexity__c = :complexityFilter');
      binds.put('complexityFilter', complexity);
    }
    if (createdAfter != null) {
      filters.add('CreatedDate >= :createdAfterDateTime');
      binds.put(
        'createdAfterDateTime',
        Datetime.newInstance(createdAfter, Time.newInstance(0, 0, 0, 0))
      );
    }
    if (createdBefore != null) {
      filters.add('CreatedDate < :createdBeforeDateTime');
      binds.put(
        'createdBeforeDateTime',
        Datetime.newInstance(
          createdBefore.addDays(1),
          Time.newInstance(0, 0, 0, 0)
        )
      );
    }

    String queryText =
      'SELECT Id, Name, Sequence_Name__c, Sequence_Length__c, ' +
      'Feasibility_Classifier__c, Complexity__c, Complexity_Score__c, ' +
      'Owner.Name, CreatedDate, Vector__c, Vector__r.Name FROM Sequence__c';
    List<Sequence__c> records;
    if (
      String.isNotBlank(searchTerm) &&
      Pattern.matches('(?i)[ACGTN]+', searchTerm.trim())
    ) {
      List<Id> matchedIds = findBaseMatches(
        searchTerm.trim().toUpperCase(),
        ownerName,
        feasibility,
        complexity,
        createdAfter,
        createdBefore,
        safePageSize,
        safeOffset
      );
      if (matchedIds.isEmpty())
        return new List<Map<String, Object>>();
      Map<Id, Sequence__c> byId = new Map<Id, Sequence__c>(
        (List<Sequence__c>) Database.queryWithBinds(
          queryText + ' WHERE Id IN :matchedIds',
          new Map<String, Object>{ 'matchedIds' => matchedIds },
          AccessLevel.USER_MODE
        )
      );
      records = new List<Sequence__c>();
      for (Id matchedId : matchedIds)
        records.add(byId.get(matchedId));
    } else {
      if (!filters.isEmpty())
        queryText += ' WHERE ' + String.join(filters, ' AND ');
      queryText += ' ORDER BY CreatedDate DESC, Id DESC LIMIT :safePageSize OFFSET :safeOffset';
      records = (List<Sequence__c>) Database.queryWithBinds(
        queryText,
        binds,
        AccessLevel.USER_MODE
      );
    }

    List<Map<String, Object>> output = new List<Map<String, Object>>();
    Map<Id, Sequence__c> extras = loadListExtras(records);
    for (Sequence__c record : records)
      output.add(withListExtras(toRow(record), extras.get(record.Id)));
    return output;
  }

  // Sequence__c is a long text area, so SOQL cannot apply LIKE to its DNA.
  // Stream visible records in order and keep only the IDs for the requested page.
  private static List<Id> findBaseMatches(
    String bases,
    String ownerName,
    String feasibility,
    String complexity,
    Date createdAfter,
    Date createdBefore,
    Integer pageSize,
    Integer offsetRows
  ) {
    List<Id> matches = new List<Id>();
    Integer skipped = 0;
    String ownerTerm = String.isBlank(ownerName)
      ? null
      : ownerName.trim().toLowerCase();
    Datetime afterStart = createdAfter == null
      ? null
      : Datetime.newInstance(createdAfter, Time.newInstance(0, 0, 0, 0));
    Datetime beforeEnd = createdBefore == null
      ? null
      : Datetime.newInstance(
          createdBefore.addDays(1),
          Time.newInstance(0, 0, 0, 0)
        );
    for (Sequence__c candidate : [
      SELECT
        Id,
        Name,
        Sequence_Name__c,
        Sequence__c,
        Owner.Name,
        Feasibility_Classifier__c,
        Complexity__c,
        CreatedDate
      FROM Sequence__c
      WITH USER_MODE
      ORDER BY CreatedDate DESC, Id DESC
    ]) {
      if (
        (ownerTerm != null &&
        (candidate.Owner == null ||
        !candidate.Owner.Name.toLowerCase().contains(ownerTerm))) ||
        (String.isNotBlank(feasibility) &&
        candidate.Feasibility_Classifier__c != feasibility) ||
        (String.isNotBlank(complexity) &&
        candidate.Complexity__c != complexity) ||
        (afterStart != null &&
        candidate.CreatedDate < afterStart) ||
        (beforeEnd != null &&
        candidate.CreatedDate >= beforeEnd)
      )
        continue;
      if (
        !(candidate.Name != null &&
        candidate.Name.toUpperCase().contains(bases)) &&
        !(candidate.Sequence_Name__c != null &&
        candidate.Sequence_Name__c.toUpperCase().contains(bases)) &&
        !(candidate.Sequence__c != null &&
        candidate.Sequence__c.replaceAll('\\s+', '')
          .toUpperCase()
          .contains(bases))
      )
        continue;
      if (skipped < offsetRows) {
        skipped++;
        continue;
      }
      matches.add(candidate.Id);
      if (matches.size() == pageSize)
        break;
    }
    return matches;
  }

  @AuraEnabled
  public static Map<String, Object> getSequence(Id sequenceId) {
    if (sequenceId == null)
      throw new AuraHandledException('Select a sequence to view.');
    List<Sequence__c> records = [
      SELECT
        Id,
        Name,
        Sequence_Name__c,
        Sequence__c,
        Sequence_Length__c,
        Feasibility_Classifier__c,
        Feasibility_Explained__c,
        Sequence_Error__c,
        Complexity__c,
        Complexity_Score__c,
        Owner.Name,
        CreatedDate,
        Vector__c,
        Vector__r.Name,
        Quote_Line_Item__c,
        Product_SKU__c,
        (
          SELECT
            Id,
            Amino_Acid_Sequence__c,
            Model__c,
            Flanking_Sequence_5__c,
            Flanking_Sequence_3__c,
            Target_Organism__r.Slug__c
          FROM Amino_Acids__r
          ORDER BY CreatedDate DESC
          LIMIT 1
        )
      FROM Sequence__c
      WHERE Id = :sequenceId
      WITH USER_MODE
      LIMIT 1
    ];
    if (records.isEmpty())
      throw new AuraHandledException('This sequence is unavailable.');
    Map<String, Object> output = toRow(records[0]);
    withListExtras(output, loadListExtras(records).get(records[0].Id));
    output.put('sequence', records[0].Sequence__c);
    output.put('feasibilityExplained', records[0].Feasibility_Explained__c);
    output.put('sequenceError', records[0].Sequence_Error__c);
    output.put('quoteLineItemId', records[0].Quote_Line_Item__c);
    List<Amino_Acid__c> aminoAcids = records[0].Amino_Acids__r;
    Boolean hasLinkedProtein =
      !aminoAcids.isEmpty() &&
      String.isNotBlank(aminoAcids[0].Amino_Acid_Sequence__c);
    if (!aminoAcids.isEmpty()) {
      Amino_Acid__c aminoAcid = aminoAcids[0];
      output.put('aminoAcidId', aminoAcid.Id);
      output.put('aminoAcidSequence', aminoAcid.Amino_Acid_Sequence__c);
      output.put(
        'optimizationSettings',
        new Map<String, Object>{
          'modelKey' => modelKey(aminoAcid.Model__c),
          'organismSlug' => aminoAcid.Target_Organism__r == null
            ? null
            : aminoAcid.Target_Organism__r.Slug__c,
          'flank5' => aminoAcid.Flanking_Sequence_5__c,
          'flank3' => aminoAcid.Flanking_Sequence_3__c
        }
      );
    }
    String quoteStatus = getQuoteStatus(records[0].Quote_Line_Item__c);
    Boolean isClonal = new Set<String>{ '1002', '6001', '6003' }
      .contains(records[0].Product_SKU__c);
    Boolean isStandalone =
      records[0].Quote_Line_Item__c == null &&
      output.get('status') != 'Ordered';
    Boolean supportedProduct =
      isClonal || (isStandalone && String.isBlank(records[0].Product_SKU__c));
    Boolean isClosedQuote =
      quoteStatus == 'Ordered' ||
      quoteStatus == 'Rejected' ||
      output.get('status') == 'Ordered';
    output.put('optimizationAvailable', supportedProduct && !isClosedQuote);
    output.put('requiresProtein', !hasLinkedProtein);
    output.put(
      'optimizationUnavailableReason',
      !supportedProduct
        ? 'Optimization is available for Clonal DNA, XL Clonal DNA, and standalone library sequences.'
        : isClosedQuote
            ? 'This sequence is linked to a closed quote or order.'
            : null
    );
    return output;
  }

  /**
   * The Sequence was already loaded in USER_MODE. Read only the related Quote
   * status needed for the re-optimization guard, without granting portal users
   * general QuoteLineItem object access.
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

  private static String modelKey(String modelValue) {
    if (String.isBlank(modelValue))
      return null;
    return modelValue.toLowerCase().replaceAll('[^a-z0-9]', '');
  }

  // Status, order date and account name are read separately in system mode,
  // so portal users do not need access to the order or account objects.
  private static Map<Id, Sequence__c> loadListExtras(
    List<Sequence__c> records
  ) {
    if (records.isEmpty())
      return new Map<Id, Sequence__c>();
    return new Map<Id, Sequence__c>(
      [
        SELECT
          Id,
          Sequence_Account__r.Name,
          Order_Product__c,
          Order_Product__r.CreatedDate,
          Quote_Line_Item__c,
          Manual_Annotations__c,
          Plannotate_Features__c,
          Plannotate_Sequence_Hash__c,
          Plannotate_Status__c
        FROM Sequence__c
        WHERE Id IN :records
        WITH SYSTEM_MODE
      ]
    );
  }

  private static Map<String, Object> withListExtras(
    Map<String, Object> row,
    Sequence__c extra
  ) {
    if (extra == null)
      return row;
    List<Object> manual = readFeatures(extra.Manual_Annotations__c);
    List<Object> automatic = readFeatures(extra.Plannotate_Features__c);
    row.put('manualFeatures', manual);
    row.put('plannotateFeatures', automatic);
    row.put('annotations', featureLabels(manual));
    row.put('plannotate', featureLabels(automatic));
    row.put('plannotateStatus', extra.Plannotate_Status__c);
    row.put('plannotateSequenceHash', extra.Plannotate_Sequence_Hash__c);
    String status = extra.Order_Product__c != null
      ? 'Ordered'
      : extra.Quote_Line_Item__c != null ? 'Quoted' : 'Designed';
    row.put('status', status);
    if (extra.Order_Product__r != null)
      row.put('orderedDate', extra.Order_Product__r.CreatedDate);
    String ownerName = (String) row.get('ownerName');
    if (isPlaceholderName(ownerName) && extra.Sequence_Account__r != null)
      row.put('ownerName', extra.Sequence_Account__r.Name);
    return row;
  }

  private static List<Object> readFeatures(String value) {
    if (String.isBlank(value))
      return new List<Object>();
    try {
      return (List<Object>) JSON.deserializeUntyped(value);
    } catch (Exception e) {
      return new List<Object>();
    }
  }

  private static List<String> featureLabels(List<Object> features) {
    Set<String> labels = new Set<String>();
    for (Object item : features) {
      Map<String, Object> feature = (Map<String, Object>) item;
      if (feature.get('label') != null)
        labels.add(String.valueOf(feature.get('label')));
    }
    return new List<String>(labels);
  }

  private static Boolean isPlaceholderName(String name) {
    return String.isNotBlank(name) && Pattern.matches('User[0-9]{8,}', name);
  }

  private static Map<String, Object> toRow(Sequence__c row) {
    return new Map<String, Object>{
      'id' => row.Id,
      'sequenceNumber' => row.Name,
      'sequenceName' => row.Sequence_Name__c,
      'length' => row.Sequence_Length__c,
      'feasibility' => row.Feasibility_Classifier__c,
      'complexity' => row.Complexity__c,
      'complexityScore' => row.Complexity_Score__c,
      'ownerName' => row.Owner.Name,
      'createdDate' => row.CreatedDate,
      'vectorId' => row.Vector__c,
      'vectorName' => row.Vector__r == null ? null : row.Vector__r.Name
    };
  }
}
