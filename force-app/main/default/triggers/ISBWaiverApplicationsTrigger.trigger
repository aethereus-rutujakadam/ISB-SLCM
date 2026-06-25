trigger ISBWaiverApplicationsTrigger on ISBWaiverApplications__c (after insert, after update) {
    if (Trigger.isAfter) {
        if (Trigger.isInsert || Trigger.isUpdate) {
           // ISBWaiverHandler.applyWaiverToInstallments(Trigger.new);
        }
    }
}