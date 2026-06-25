@isTest
public class CourseChecklistSharingHandlerTest {

    @IsTest
    static void testChecklistActivation() {
        // 1. Setup User (AA)
        User aaUser = TestDataFactory.testUser('aauser', 'aauser' + System.currentTimeMillis() + '@test.com');
        
        // 2. Setup AA Contact linked to User
        Contact aaContact = TestDataFactory.testAAContact(aaUser);
        
        // 3. Setup Offering
        CourseOffering co = TestDataFactory.testCourseOffering();
        
        // 4. Setup AA Profile
        AA_Profile__c aaProfile = TestDataFactory.testAAProfile(aaContact.Id);
        
        // 5. Setup Course AA Assignment
        TestDataFactory.testCourseAAAssignment(aaContact.Id, co.Id, aaProfile.Id);
        
        // 6. Setup Checklist (status Draft)
        Course_Checklist__c cl = new Course_Checklist__c(
            Course_Offering__c = co.Id,
            Status__c = 'Draft'
        );
        insert cl;
        
        // 7. Setup Checklist Items (status Not Started)
        Course_Checklist_Item__c item = new Course_Checklist_Item__c(
            Course_Checklist__c = cl.Id,
            Status__c = 'Not Started'
        );
        insert item;
        
        // 8. Activate Checklist
        Test.startTest();
        cl.Status__c = 'Active';
        update cl;
        Test.stopTest();
        
        // 9. Verify Item status updated
        Course_Checklist_Item__c updatedItem = [SELECT Status__c FROM Course_Checklist_Item__c WHERE Id = :item.Id];
        System.assertEquals('In Progress', updatedItem.Status__c, 'Item status should be updated to In Progress');
        
        // 10. Verify Shares created for AA User
        List<Course_Checklist__Share> clShares = [
            SELECT Id, UserOrGroupId, AccessLevel 
            FROM Course_Checklist__Share 
            WHERE ParentId = :cl.Id AND UserOrGroupId = :aaUser.Id
        ];
        System.assert(clShares.size() > 0, 'Course Checklist share should be created for the AA User');
        
        // Verify Course Offering Shares if applicable (Manual sharing might not be enabled for standard objects in all orgs)
        // Check if CourseOfferingShare exists (standard object sharing)
        try {
            List<SObject> offeringShares = Database.query(
                'SELECT Id FROM CourseOfferingShare WHERE ParentId = \'' + co.Id + '\' AND UserOrGroupId = \'' + aaUser.Id + '\''
            );
            System.assert(offeringShares.size() > 0, 'Course Offering share should be created for the AA User');
        } catch (Exception e) {
            System.debug('Could not query CourseOfferingShare: ' + e.getMessage());
        }
    }

    @IsTest
    static void testInsertAsActive() {
        // Setup User (AA)
        User aaUser = TestDataFactory.testUser('aauser2', 'aauser2' + System.currentTimeMillis() + '@test.com');
        Contact aaContact = TestDataFactory.testAAContact(aaUser);
        CourseOffering co = TestDataFactory.testCourseOffering();
        AA_Profile__c aaProfile = TestDataFactory.testAAProfile(aaContact.Id);
        TestDataFactory.testCourseAAAssignment(aaContact.Id, co.Id, aaProfile.Id);

        // Insert as Active
        Test.startTest();
        Course_Checklist__c cl = new Course_Checklist__c(
            Course_Offering__c = co.Id,
            Status__c = 'Active'
        );
        insert cl;
        Test.stopTest();

        List<Course_Checklist__Share> clShares = [
            SELECT Id FROM Course_Checklist__Share 
            WHERE ParentId = :cl.Id AND UserOrGroupId = :aaUser.Id
        ];
        System.assert(clShares.size() > 0, 'Checklist should be shared even if inserted as Active');
    }
}