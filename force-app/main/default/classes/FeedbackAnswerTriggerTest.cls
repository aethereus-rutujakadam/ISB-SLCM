/**
 * @description Test class for FeedbackAnswerTrigger and FeedbackAnswerTriggerHandler
 * @author ISB Team
 * @date 2025
 */
@IsTest
public class FeedbackAnswerTriggerTest {

    @TestSetup
    static void setupData() {
        // Create Feedback Template
        Feedback_Template__c template = new Feedback_Template__c(
            Name = 'Test Template',
            Active__c = true
        );
        insert template;

        // Create Feedback Template Question
        Feedback_Template_Question__c question = new Feedback_Template_Question__c(
            Feedback_Template__c = template.Id,
            Question_Text__c = 'What is your favorite color?',
            Question_Type_c__c = 'Text',
            Order__c = 1
        );
        insert question;

        // Create Feedback
        Feedback__c feedback = new Feedback__c(
            Name = 'Test Feedback',
            Status__c = 'Published'
        );
        insert feedback;
    }

    @IsTest
    static void testQuestionUpdate() {
        Feedback__c feedback = [SELECT Id FROM Feedback__c LIMIT 1];
        Feedback_Template_Question__c question = [SELECT Id, Question_Text__c FROM Feedback_Template_Question__c LIMIT 1];

        // Create Feedback Answer
        Feedback_Answer__c answer = new Feedback_Answer__c(
            Feedback__c = feedback.Id,
            Feedback_Template_Question__c = question.Id,
            Answer_Text__c = 'Blue'
        );

        Test.startTest();
        insert answer;
        Test.stopTest();

        // Verify Question__c is updated
        Feedback_Answer__c updatedAnswer = [SELECT Id, Question__c FROM Feedback_Answer__c WHERE Id = :answer.Id];
        System.assertEquals(question.Question_Text__c, updatedAnswer.Question__c, 'Question__c should be updated from Template Question');
    }

    @IsTest
    static void testQuestionUpdateBulk() {
        Feedback__c feedback = [SELECT Id FROM Feedback__c LIMIT 1];
        Feedback_Template_Question__c question = [SELECT Id, Question_Text__c FROM Feedback_Template_Question__c LIMIT 1];

        List<Feedback_Answer__c> answers = new List<Feedback_Answer__c>();
        for (Integer i = 0; i < 10; i++) {
            answers.add(new Feedback_Answer__c(
                Feedback__c = feedback.Id,
                Feedback_Template_Question__c = question.Id,
                Answer_Text__c = 'Answer ' + i
            ));
        }

        Test.startTest();
        insert answers;
        Test.stopTest();

        // Verify Question__c is updated for all
        List<Feedback_Answer__c> updatedAnswers = [SELECT Id, Question__c FROM Feedback_Answer__c WHERE Feedback__c = :feedback.Id];
        for (Feedback_Answer__c ans : updatedAnswers) {
            System.assertEquals(question.Question_Text__c, ans.Question__c, 'Question__c should be updated for all answers');
        }
    }
}