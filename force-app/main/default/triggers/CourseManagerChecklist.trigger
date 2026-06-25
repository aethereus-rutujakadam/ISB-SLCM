trigger CourseManagerChecklist on course_managers__c (before insert, before update, after insert) {
    if (Trigger.isBefore) {
        if (Trigger.isInsert || Trigger.isUpdate) {
            CourseManagerDuplicateValidationHandler.validateNoDuplicates(Trigger.new, Trigger.oldMap);
        }
    }
    
    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            CourseManagerChecklistHandler.handleAfterInsert(Trigger.new);
        }
    }
}