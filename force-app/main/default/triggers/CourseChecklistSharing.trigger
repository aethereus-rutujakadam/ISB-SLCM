trigger CourseChecklistSharing on Course_Checklist__c (after insert, after update) {
    CourseChecklistSharingHandler.handleChecklistAfterUpdate(Trigger.new, Trigger.oldMap);
}