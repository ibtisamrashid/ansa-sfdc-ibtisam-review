trigger SequenceAccountSharing on Sequence__c(before insert, before update) {
  SequenceAccountSharingHandler.populateAccount(Trigger.new, Trigger.oldMap);
  if (Trigger.isUpdate) {
    for (Sequence__c sequence : Trigger.new) {
      if (
        (sequence.Sequence__c != Trigger.oldMap.get(sequence.Id).Sequence__c ||
        sequence.Sequence_Account__c !=
        Trigger.oldMap.get(sequence.Id).Sequence_Account__c) &&
        (String.isNotBlank(sequence.Plannotate_Features__c) ||
        sequence.Plannotate_Job__c != null)
      ) {
        sequence.Plannotate_Features__c = null;
        sequence.Plannotate_Sequence_Hash__c = null;
        sequence.Plannotate_Job__c = null;
        sequence.Plannotate_Status__c = 'Outdated';
      }
    }
  }
}
