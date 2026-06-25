/**
 * @description Handler for Feedback_Answer__c trigger
 * @author ISB Team
 * @date 2025
 */
public without sharing class FeedbackAnswerTriggerHandler {
    
    /**
     * @description Update Question__c with Question_Text__c from Feedback_Template_Question__c
     * @param newAnswers List of new Feedback_Answer__c records
     */
    public static void handleBeforeInsert(List<Feedback_Answer__c> newAnswers) {
        System.debug('FeedbackAnswerTriggerHandler.handleBeforeInsert: Processing ' + newAnswers.size() + ' records');
        Set<Id> questionIds = new Set<Id>();
        for (Feedback_Answer__c ans : newAnswers) {
            if (ans.Feedback_Template_Question__c != null) {
                questionIds.add(ans.Feedback_Template_Question__c);
            } else {
                System.debug('FeedbackAnswerTriggerHandler: Feedback_Template_Question__c is null for record');
            }
        }
        
        if (questionIds.isEmpty()) {
            System.debug('FeedbackAnswerTriggerHandler: No question IDs found to process');
            return;
        }
        
        System.debug('FeedbackAnswerTriggerHandler: Querying ' + questionIds.size() + ' questions');
        Map<Id, Feedback_Template_Question__c> questionsMap = new Map<Id, Feedback_Template_Question__c>([
            SELECT Id, Question_Text__c 
            FROM Feedback_Template_Question__c 
            WHERE Id IN :questionIds
        ]);
        System.debug('FeedbackAnswerTriggerHandler: Found ' + questionsMap.size() + ' questions in DB');
        
        for (Feedback_Answer__c ans : newAnswers) {
            if (ans.Feedback_Template_Question__c != null && questionsMap.containsKey(ans.Feedback_Template_Question__c)) {
                String qText = questionsMap.get(ans.Feedback_Template_Question__c).Question_Text__c;
                ans.Question__c = qText;
                System.debug('FeedbackAnswerTriggerHandler: Populated Question__c with: ' + (qText != null ? qText.left(50) : 'NULL'));
            } else if (ans.Feedback_Template_Question__c != null) {
                System.debug('FeedbackAnswerTriggerHandler: Question ID ' + ans.Feedback_Template_Question__c + ' not found in questionsMap');
            }
        }
    }
}