/**
 * @description Trigger on Course_Faculty__c to automatically create Payment_Information__c records
 * @author System
 * @date 2026-04-22
 */
trigger CourseFacultyTrigger on Course_Faculty__c (after insert) {
    if (Trigger.isAfter && Trigger.isInsert) {
        CourseFacultyTriggerHandler.handleAfterInsert(Trigger.new);
    }
}