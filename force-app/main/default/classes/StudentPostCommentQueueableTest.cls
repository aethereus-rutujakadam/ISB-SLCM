@isTest
private class StudentPostCommentQueueableTest {

    @isTest
    static void testQueueableWithValidPostAndApproval() {

        Student_Post__c post = new Student_Post__c(
            Title__c = 'Test Post',
            Post_Body__c = 'Test Body'
        );
        insert post;

        // Create mock ProcessInstance via JSON
        String mockJson = '[{' +
            '"attributes":{"type":"ProcessInstance"},' +
            '"Id":"04g000000000000AAA",' +
            '"TargetObjectId":"' + post.Id + '",' +
            '"Steps":{' +
                '"totalSize":1,' +
                '"done":true,' +
                '"records":[{' +
                    '"attributes":{"type":"ProcessInstanceStep"},' +
                    '"Id":"04h000000000000AAA",' +
                    '"Comments":"Mocked Approval Comment"' +
                '}]' +
            '}' +
        '}]';

        List<ProcessInstance> mockedInstances =
            (List<ProcessInstance>) JSON.deserialize(mockJson, List<ProcessInstance>.class);

        // Inject into class
        StudentPostCommentQueueable.testInstances = mockedInstances;

        Test.startTest();
        System.enqueueJob(new StudentPostCommentQueueable(
            new Set<Id>{post.Id}
        ));
        Test.stopTest();

        Student_Post__c updatedPost =
            [SELECT Reviewer_s_Comments__c FROM Student_Post__c WHERE Id = :post.Id];

        System.assertEquals(
            'Mocked Approval Comment',
            updatedPost.Reviewer_s_Comments__c
        );
    }
}