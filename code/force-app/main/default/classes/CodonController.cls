public with sharing class CodonController {
  @AuraEnabled
  public static Map<String, Object> getOrganisms() {
    return CodonService.getOrganisms();
  }

  @AuraEnabled
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
    return CodonService.submitJob(
      quoteRequestId,
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

  @AuraEnabled
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
    return CodonService.submitSequenceJob(
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

  @AuraEnabled
  public static Map<String, Object> getJobStatus(String jobId) {
    return CodonService.getJobStatus(jobId);
  }

  @AuraEnabled
  public static void linkAminoAcidSequence(Id aminoAcidId, Id sequenceId) {
    CodonService.linkAminoAcidSequence(aminoAcidId, sequenceId);
  }
}
