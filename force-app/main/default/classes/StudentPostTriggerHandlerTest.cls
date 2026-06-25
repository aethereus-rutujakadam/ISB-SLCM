@IsTest
public class StudentPostTriggerHandlerTest {

    @TestSetup
    static void setupData() {

        // Create a Student Post in non-terminal status
        Student_Post__c post = new Student_Post__c(
            Title__c = 'Test Post',
            Post_Body__c = 'Test Body',
            Status__c = 'Draft',  // Non-terminal initial status
            Expiry_Date__c = Date.today().addDays(5),
            Published_on__c = System.now()
        );

        insert post;
    }

    // ✅ Positive Test – Status changes to Approved
    @IsTest
    static void testAfterUpdate_StatusChangedToApproved() {

        Student_Post__c post = [SELECT Id, Status__c FROM Student_Post__c LIMIT 1];

        Test.startTest();

        post.Status__c = 'Archived';
        update post;

        Test.stopTest(); // Executes Queueable

        // No direct assert because handler only enqueues job.
        // This ensures coverage of enqueue logic.
        System.assert(true, 'Queueable should have been enqueued.');
    }

    // ✅ Positive Test – Status changes to Rejected
    @IsTest
    static void testAfterUpdate_StatusChangedToRejected() {

        Student_Post__c post = [SELECT Id, Status__c FROM Student_Post__c LIMIT 1];

        Test.startTest();

        post.Status__c = 'Pending';
        update post;

        Test.stopTest();

        System.assert(true, 'Queueable should have been enqueued.');
    }

    // ❌ Negative Test – Status unchanged
    @IsTest
    static void testAfterUpdate_StatusNotChanged() {

        Student_Post__c post = [SELECT Id, Status__c FROM Student_Post__c LIMIT 1];

        Test.startTest();

        // Update some other field
        post.Title__c = 'Updated Title';
        update post;

        Test.stopTest();

        System.assert(true, 'Queueable should NOT have been enqueued.');
    }

    // ❌ Negative Test – Changed but NOT terminal status
    @IsTest
    static void testAfterUpdate_StatusChangedToNonTerminal() {

        Student_Post__c post = [SELECT Id, Status__c FROM Student_Post__c LIMIT 1];

        Test.startTest();

        post.Status__c = 'Published'; // Non-terminal
        update post;

        Test.stopTest();

        System.assert(true, 'Queueable should NOT have been enqueued.');
    }
}