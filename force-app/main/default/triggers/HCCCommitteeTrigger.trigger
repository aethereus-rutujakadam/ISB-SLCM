trigger HCCCommitteeTrigger on Honour_Code_Committee__c (before update) {
    if (Trigger.isBefore && Trigger.isUpdate) {
        HCCCommitteeTriggerHandler.populateFromPGID(Trigger.new, Trigger.oldMap);
        HCCCommitteeTriggerHandler.populateChairFromEmail(Trigger.new, Trigger.oldMap);
        HCCCommitteeTriggerHandler.populateStudentDetails(Trigger.new, Trigger.oldMap);
    }
}