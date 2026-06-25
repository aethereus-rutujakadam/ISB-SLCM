/**
 * @description Trigger on Feedback_Answer__c
 * @author ISB Team
 * @date 2025
 */
trigger FeedbackAnswerTrigger on Feedback_Answer__c (before insert) {
    if (Trigger.isBefore && Trigger.isInsert) {
        FeedbackAnswerTriggerHandler.handleBeforeInsert(Trigger.new);
    }
}