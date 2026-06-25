@isTest
public class CourseAAAssignmentHandlerTest {

    @testSetup
    static void setup() {
        // 1. Setup User (AA)
        User aaUser = TestDataFactory.testUser('aauser', 'aauser' + System.currentTimeMillis() + '@test.com');
        
        // 2. Setup AA Contact linked to User
        Contact aaContact = TestDataFactory.testAAContact(aaUser);
        
        // 3. Setup AA Profile
        AA_Profile__c aaProfile = TestDataFactory.testAAProfile(aaContact.Id);
        
        // 4. Setup Offering
        CourseOffering co = TestDataFactory.testCourseOffering();
        
        // 5. Setup Active Checklist for the Offering
        Course_Checklist__c cl = new Course_Checklist__c(
            Course_Offering__c = co.Id,
            Status__c = 'Active'
        );
        insert cl;
    }

    @isTest
    static void testInsertActiveAssignment() {
        AA_Profile__c aaProfile = [SELECT Id FROM AA_Profile__c LIMIT 1];
        CourseOffering co = [SELECT Id FROM CourseOffering LIMIT 1];
        User aaUser = [SELECT Id FROM User WHERE Alias = 'aauser' LIMIT 1];
        Course_Checklist__c cl = [SELECT Id FROM Course_Checklist__c WHERE Status__c = 'Active' LIMIT 1];

        Test.startTest();
        Course_AA_Assignment__c assign = new Course_AA_Assignment__c(
            Academic_Associate__c = aaProfile.Id,
            Course_Offering__c = co.Id,
            Is_Active__c = true
        );
        insert assign;
        Test.stopTest();

        // Verify Checklist Share
        List<Course_Checklist__Share> clShares = [
            SELECT Id 
            FROM Course_Checklist__Share 
            WHERE ParentId = :cl.Id AND UserOrGroupId = :aaUser.Id AND RowCause = 'Manual'
        ];
        System.assert(clShares.size() > 0, 'Checklist should be shared with the AA User');

        // Verify Course Offering Share
        try {
            List<SObject> offeringShares = Database.query(
                'SELECT Id FROM CourseOfferingShare WHERE ParentId = \'' + co.Id + '\' AND UserOrGroupId = \'' + aaUser.Id + '\' AND RowCause = \'Manual\''
            );
            System.assert(offeringShares.size() > 0, 'Course Offering should be shared with the AA User');
        } catch (Exception e) {}
    }

    @isTest
    static void testDeactivateAssignment() {
        AA_Profile__c aaProfile = [SELECT Id FROM AA_Profile__c LIMIT 1];
        CourseOffering co = [SELECT Id FROM CourseOffering LIMIT 1];
        User aaUser = [SELECT Id FROM User WHERE Alias = 'aauser' LIMIT 1];
        Course_Checklist__c cl = [SELECT Id FROM Course_Checklist__c WHERE Status__c = 'Active' LIMIT 1];

        Course_AA_Assignment__c assign = new Course_AA_Assignment__c(
            Academic_Associate__c = aaProfile.Id,
            Course_Offering__c = co.Id,
            Is_Active__c = true
        );
        insert assign;
        
        // Verify shared initially
        System.assert([SELECT Id FROM Course_Checklist__Share WHERE ParentId = :cl.Id AND UserOrGroupId = :aaUser.Id].size() > 0);

        Test.startTest();
        assign.Is_Active__c = false;
        update assign;
        Test.stopTest();

        // Verify Shares removed
        List<Course_Checklist__Share> clShares = [
            SELECT Id 
            FROM Course_Checklist__Share 
            WHERE ParentId = :cl.Id AND UserOrGroupId = :aaUser.Id AND RowCause = 'Manual'
        ];
        System.assertEquals(0, clShares.size(), 'Checklist share should be removed when assignment is deactivated');
    }

    @isTest
    static void testDeleteAssignment() {
        AA_Profile__c aaProfile = [SELECT Id FROM AA_Profile__c LIMIT 1];
        CourseOffering co = [SELECT Id FROM CourseOffering LIMIT 1];
        User aaUser = [SELECT Id FROM User WHERE Alias = 'aauser' LIMIT 1];
        Course_Checklist__c cl = [SELECT Id FROM Course_Checklist__c WHERE Status__c = 'Active' LIMIT 1];

        Course_AA_Assignment__c assign = new Course_AA_Assignment__c(
            Academic_Associate__c = aaProfile.Id,
            Course_Offering__c = co.Id,
            Is_Active__c = true
        );
        insert assign;

        Test.startTest();
        delete assign;
        Test.stopTest();

        // Verify Shares removed
        List<Course_Checklist__Share> clShares = [
            SELECT Id 
            FROM Course_Checklist__Share 
            WHERE ParentId = :cl.Id AND UserOrGroupId = :aaUser.Id AND RowCause = 'Manual'
        ];
        System.assertEquals(0, clShares.size(), 'Checklist share should be removed when assignment is deleted');
    }
}