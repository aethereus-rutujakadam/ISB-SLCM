trigger CourseOfferingTrigger on CourseOffering (after update) {
    // Delegate to handler for bulk processing
    if (Trigger.isAfter) {
        if (Trigger.isUpdate) {
            CourseOfferingTriggerHandler.handleAfter(Trigger.new);
        }
    }
}