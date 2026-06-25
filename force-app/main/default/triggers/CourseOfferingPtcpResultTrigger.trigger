trigger CourseOfferingPtcpResultTrigger on CourseOfferingPtcpResult (after insert, after update, after delete, after undelete) {
    if (Trigger.isAfter) {
        if (Trigger.isInsert || Trigger.isUpdate || Trigger.isUndelete) {
            CourseOfferingPtcpResultHandler.handleAfter(Trigger.new, Trigger.oldMap);
        } else if (Trigger.isDelete) {
            CourseOfferingPtcpResultHandler.handleAfter(Trigger.old, null);
        }
    }
}