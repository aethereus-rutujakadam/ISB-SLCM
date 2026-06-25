@isTest
public class AAFeedbackSummaryControllerTest {

    // Helper method to create feedback records
    private static List<Feedback__c> createFeedbackRecords(Id aaProfileId) {
        Id recordTypeId = [SELECT Id FROM RecordType WHERE SObjectType = 'Feedback__c' AND DeveloperName = 'Academic_Associate' LIMIT 1].Id;
        
        List<Feedback__c> feedbackList = new List<Feedback__c>();
        
        feedbackList.add(new Feedback__c(
            Academic_Associate__c = aaProfileId,
            RecordTypeId = recordTypeId,
            Overall_Rating__c = '5',
            Comments__c = 'Great job!',
            Status__c = 'Published'
        ));
        
        feedbackList.add(new Feedback__c(
            Academic_Associate__c = aaProfileId,
            RecordTypeId = recordTypeId,
            Overall_Rating__c = '4',
            Comments__c = 'Good work.',
            Status__c = 'Published'
        ));
        
        feedbackList.add(new Feedback__c(
            Academic_Associate__c = aaProfileId,
            RecordTypeId = recordTypeId,
            Overall_Rating__c = '3',
            Comments__c = 'Needs improvement',
            Status__c = 'Published'
        ));

        insert feedbackList;
        return feedbackList;
    }

    @isTest
    static void testGetFeedbackSummary() {
        // Create User
        String uniqueStr = String.valueOf(Datetime.now().getTime()) + String.valueOf(Math.random());
        User u = TestDataFactory.testUser('testusr', 'testuser' + uniqueStr + '@example.com');
        
        // Create AA Contact
        Contact aaContact = TestDataFactory.testAAContact(u);
        
        // Create Academic Term
        AcademicTerm term = TestDataFactory.testAcademicTerm();
        
        // Create AA Profile
        AA_Profile__c profile = TestDataFactory.testAAProfile(term.Id, aaContact.Id);
        
        // Fix potential null Academic_Term__c issue
        if (profile.Academic_Term__c == null) {
            profile.Academic_Term__c = term.Id;
            update profile;
        }

        // Create Feedback Records
        createFeedbackRecords(profile.Id);
        
        Test.startTest();
        List<Map<String, Object>> summary = AAFeedbackSummaryController.getFeedbackSummary(profile.Id, 30);
        Test.stopTest();
        
        System.assertNotEquals(null, summary, 'Summary should not be null');
        System.assert(!summary.isEmpty(), 'Summary should not be empty');
        
        Map<String, Object> associateFeedback = null;
        for (Map<String, Object> item : summary) {
            if (item.get('source') == 'Academic_Associate') {
                associateFeedback = item;
                break;
            }
        }
        
        System.assertNotEquals(null, associateFeedback, 'Should have feedback for Academic_Associate source');
        System.assertEquals(3, associateFeedback.get('count'), 'Should have 3 feedback records');
        
        // Average of 5, 4, 3 is 4.00
        Decimal avg = (Decimal)associateFeedback.get('avgRating');
        System.assertEquals(4.00, avg, 'Average rating should be 4.00');
    }

    @isTest
    static void testGetFeedbackDetails() {
        // Create User
        String uniqueStr = String.valueOf(Datetime.now().getTime()) + String.valueOf(Math.random());
        User u = TestDataFactory.testUser('testusr', 'testuser' + uniqueStr + '@example.com');
        
        // Create AA Contact
        Contact aaContact = TestDataFactory.testAAContact(u);
        
        // Create Academic Term
        AcademicTerm term = TestDataFactory.testAcademicTerm();
        
        // Create AA Profile
        AA_Profile__c profile = TestDataFactory.testAAProfile(term.Id, aaContact.Id);
        
        // Fix potential null Academic_Term__c issue
        if (profile.Academic_Term__c == null) {
            profile.Academic_Term__c = term.Id;
            update profile;
        }

        // Create Feedback Records
        createFeedbackRecords(profile.Id);
        
        Test.startTest();
        List<AAFeedbackSummaryController.FeedbackDetailWrapper> details = AAFeedbackSummaryController.getFeedbackDetails(profile.Id, 'Academic_Associate');
        Test.stopTest();
        
        System.assertNotEquals(null, details, 'Details should not be null');
        System.assertEquals(3, details.size(), 'Should return 3 detail records');
        
        AAFeedbackSummaryController.FeedbackDetailWrapper firstItem = details[0];
        System.assertNotEquals(null, firstItem.Id, 'Id should be populated');
        System.assertNotEquals(null, firstItem.RecordUrl, 'RecordUrl should be populated');
        System.assert(firstItem.RecordUrl.contains(firstItem.Id), 'RecordUrl should contain the Id');
    }
    
    @isTest
    static void testGetFeedbackSummaryNoData() {
        // Create User
        String uniqueStr = String.valueOf(Datetime.now().getTime()) + String.valueOf(Math.random());
        User u = TestDataFactory.testUser('testusr', 'testuser' + uniqueStr + '@example.com');
        
        // Create AA Contact
        Contact aaContact = TestDataFactory.testAAContact(u);
        
        // Create Academic Term
        AcademicTerm term = TestDataFactory.testAcademicTerm();
        
        // Create AA Profile without feedback
        AA_Profile__c newProfile = TestDataFactory.testAAProfile(term.Id, aaContact.Id);
        
        Test.startTest();
        List<Map<String, Object>> summary = AAFeedbackSummaryController.getFeedbackSummary(newProfile.Id, 30);
        Test.stopTest();
        
        System.assertNotEquals(null, summary, 'Summary should not be null');
        System.assert(summary.isEmpty(), 'Summary should be empty for new profile');
    }
    
    @isTest
    static void testGetFeedbackDetailsNoData() {
        // Create User
        String uniqueStr = String.valueOf(Datetime.now().getTime()) + String.valueOf(Math.random());
        User u = TestDataFactory.testUser('testusr', 'testuser' + uniqueStr + '@example.com');
        
        // Create AA Contact
        Contact aaContact = TestDataFactory.testAAContact(u);
        
        // Create Academic Term
        AcademicTerm term = TestDataFactory.testAcademicTerm();
        
        // Create AA Profile without feedback
        AA_Profile__c newProfile = TestDataFactory.testAAProfile(term.Id, aaContact.Id);
        
        Test.startTest();
        List<AAFeedbackSummaryController.FeedbackDetailWrapper> details = AAFeedbackSummaryController.getFeedbackDetails(newProfile.Id, 'Academic_Associate');
        Test.stopTest();
        
        System.assertNotEquals(null, details, 'Details should not be null');
        System.assert(details.isEmpty(), 'Details should be empty for new profile');
    }
}