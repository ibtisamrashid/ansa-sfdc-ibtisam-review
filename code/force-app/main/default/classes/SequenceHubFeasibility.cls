/** Reuse the portal's batched, after-commit feasibility request for library DNA. */
public without sharing class SequenceHubFeasibility {
  public static Id enqueue(Set<Id> sequenceIds) {
    if (sequenceIds == null || sequenceIds.isEmpty())
      return null;
    return System.enqueueJob(new ABT_PortalFeasibilityKick(sequenceIds));
  }
}
