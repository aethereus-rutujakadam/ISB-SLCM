@isTest
public class ISBContactUserProvBizQueueTest {

    @isTest
    static void testBusinessQueueLogic() {
        Id aaRTId = [SELECT Id FROM RecordType WHERE SObjectType='Contact' AND DeveloperName='Academic_Associate' LIMIT 1].Id;
        // 1. Setup Test Data
        // A. Contact for New User Linking
        Contact conNew = new Contact(
            FirstName = 'New',
            LastName = 'LinkTest',
            Email = 'newlink@example.com',
            VF_Email_ID__c = 'newlink@example.com',
            hed__Preferred_Email__c = 'Alternate Email',
            hed__AlternateEmail__c = 'newlink@example.com',
            RecordTypeId = aaRTId
        );
        insert conNew;
        User uNew = TestDataFactory.testUser('newU', 'newlink@example.com');

        // B. Contact for Existing User Linking
        Contact conExist = new Contact(
            FirstName = 'Exist',
            LastName = 'LinkTest',
            Email = 'existlink@example.com',
            VF_Email_ID__c = 'existlink@example.com',
            hed__Preferred_Email__c = 'Alternate Email',
            hed__AlternateEmail__c = 'existlink@example.com',
            RecordTypeId = aaRTId
        );
        insert conExist;
        User uExist = TestDataFactory.testUser('existU', 'existlink@example.com');

        // C. Contact for Reversion (Simulate Failure)
        Contact conRevert = new Contact(
            FirstName = 'Revert',
            LastName = 'Test',
            Email = 'revert@example.com',
            VF_Email_ID__c = 'revert@example.com',
            hed__Preferred_Email__c = 'Alternate Email',
            hed__AlternateEmail__c = 'revert@example.com',
            Active_Status__c = 'Active',
            RecordTypeId = aaRTId
        );
        insert conRevert;

        // 2. Prepare Maps for Queueable
        Map<Id, Id> createdUserIdByContactId = new Map<Id, Id>{ conNew.Id => uNew.Id };
        Map<Id, Id> existingUserIdByContactId = new Map<Id, Id>{ conExist.Id => uExist.Id };
        Set<Id> contactsToRevert = new Set<Id>{ conRevert.Id };
        Id managerId = UserInfo.getUserId();

        // 3. Execute Queueable
        Test.startTest();
        ISBContactUserProvisioningBusinessQueue job = new ISBContactUserProvisioningBusinessQueue(
            createdUserIdByContactId,
            existingUserIdByContactId,
            contactsToRevert,
            managerId
        );
        System.enqueueJob(job);
        Test.stopTest();

        // 4. Verify Results
        Contact verifiedNew = [SELECT Linked_User_Id__c, Activated_By__c, Activation_Date__c FROM Contact WHERE Id = :conNew.Id];
        System.assertEquals(uNew.Id, (Id)verifiedNew.Linked_User_Id__c, 'Contact should be linked to the newly created user');
        System.assertEquals(managerId, verifiedNew.Activated_By__c, 'Activated_By should be set');
        System.assertNotEquals(null, verifiedNew.Activation_Date__c, 'Activation_Date should be set');

        Contact verifiedExist = [SELECT Linked_User_Id__c FROM Contact WHERE Id = :conExist.Id];
        System.assertEquals(uExist.Id, (Id)verifiedExist.Linked_User_Id__c, 'Contact should be linked to the existing user');

        Contact verifiedRevert = [SELECT Active_Status__c FROM Contact WHERE Id = :conRevert.Id];
        System.assertEquals('Inactive', verifiedRevert.Active_Status__c, 'Contact status should have been reverted to Inactive');
    }
}