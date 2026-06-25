trigger EnrollmentSessionTrigger on Enrollment_Session__c (after insert, after update) {
    if (Trigger.isAfter) {
        if (Trigger.isInsert || Trigger.isUpdate) {
           EnrollmentSessionHandler.handleAfterInsertUpdate(Trigger.new, Trigger.oldMap);
        }
    }
}