trigger CourseOfferingParticipantTrigger on CourseOfferingParticipant (
    before insert, before update, after insert
) {
    if (Trigger.isBefore && (Trigger.isInsert || Trigger.isUpdate)) {
        CourseOfferingParticipantHandler.preventDuplicateParticipants(
            Trigger.new,
            Trigger.oldMap
        );
        CourseOfferingParticipantHandler.markPendingOnChanges(
            Trigger.new,
            Trigger.oldMap,
            Trigger.isInsert
        );
    }
    
    if (Trigger.isAfter && Trigger.isInsert) {
        CourseOfferingParticipantHandler.handleCourseChecklistCreation(Trigger.newMap);
    }
}