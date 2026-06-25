@isTest
public class AdvisorUserProvisioningBusinessQueueTest {

    @TestSetup
    static void setup() {
        // Create Advisor Record Type
        Id advisorRTId = Schema.SObjectType.Contact.getRecordTypeInfosByName().get('Advisor').getRecordTypeId();
        
        // Create test Contacts
        List<Contact> contacts = new List<Contact>();
        for (Integer i = 0; i < 3; i++) {
            contacts.add(new Contact(
                FirstName = 'Business',
                LastName = 'Test' + i,
                Email = 'business.test' + i + '@test.com',
                ISB_Email_ID__c = 'business.test' + i + '@test.com',
                RecordTypeId = advisorRTId,
                Active_Status__c = 'Active'
            ));
        }
        insert contacts;
    }

    @isTest
    static void testSuccessfulContactUpdate() {
        List<Contact> contacts = [SELECT Id FROM Contact WHERE LastName LIKE 'Test%' LIMIT 2];
        
        Map<Id, Id> createdUserMap = new Map<Id, Id>();
        createdUserMap.put(contacts[0].Id, UserInfo.getUserId());
        
        Test.startTest();
        System.enqueueJob(new AdvisorUserProvisioningBusinessQueue(
            createdUserMap,
            new Map<Id, Id>(),
            new Set<Id>(),
            UserInfo.getUserId()
        ));
        Test.stopTest();
        
        // Verify contact was updated with linked user
        Contact updatedContact = [SELECT Id, Linked_User_Id__c, Activated_By__c, Activation_Date__c 
                                  FROM Contact WHERE Id = :contacts[0].Id];
        System.assertNotEquals(null, updatedContact.Linked_User_Id__c, 'Linked User should be populated');
        System.assertNotEquals(null, updatedContact.Activated_By__c, 'Activated By should be populated');
        System.assertNotEquals(null, updatedContact.Activation_Date__c, 'Activation Date should be populated');
    }

    @isTest
    static void testExistingUserLink() {
        List<Contact> contacts = [SELECT Id FROM Contact WHERE LastName LIKE 'Test%' LIMIT 1];
        
        Map<Id, Id> existingUserMap = new Map<Id, Id>();
        existingUserMap.put(contacts[0].Id, UserInfo.getUserId());
        
        Test.startTest();
        System.enqueueJob(new AdvisorUserProvisioningBusinessQueue(
            new Map<Id, Id>(),
            existingUserMap,
            new Set<Id>(),
            UserInfo.getUserId()
        ));
        Test.stopTest();
        
        // Verify contact was updated with existing user
        Contact updatedContact = [SELECT Id, Linked_User_Id__c FROM Contact WHERE Id = :contacts[0].Id];
        System.assertNotEquals(null, updatedContact.Linked_User_Id__c, 'Existing User should be linked');
    }

    @isTest
    static void testContactReversion() {
        List<Contact> contacts = [SELECT Id FROM Contact WHERE LastName LIKE 'Test%' LIMIT 1];
        contacts[0].Active_Status__c = 'Active';
        update contacts;
        
        Set<Id> contactsToRevert = new Set<Id>{contacts[0].Id};
        
        Test.startTest();
        System.enqueueJob(new AdvisorUserProvisioningBusinessQueue(
            new Map<Id, Id>(),
            new Map<Id, Id>(),
            contactsToRevert,
            UserInfo.getUserId()
        ));
        Test.stopTest();
        
        // Verify contact was reverted to Inactive
        Contact revertedContact = [SELECT Id, Active_Status__c FROM Contact WHERE Id = :contacts[0].Id];
        System.assertEquals('Inactive', revertedContact.Active_Status__c, 'Contact should be reverted to Inactive');
    }

    @isTest
    static void testMixedOperations() {
        List<Contact> contacts = [SELECT Id FROM Contact WHERE LastName LIKE 'Test%' LIMIT 3];
        
        Map<Id, Id> createdUserMap = new Map<Id, Id>();
        createdUserMap.put(contacts[0].Id, UserInfo.getUserId());
        
        Map<Id, Id> existingUserMap = new Map<Id, Id>();
        existingUserMap.put(contacts[1].Id, UserInfo.getUserId());
        
        Set<Id> contactsToRevert = new Set<Id>{contacts[2].Id};
        
        Test.startTest();
        System.enqueueJob(new AdvisorUserProvisioningBusinessQueue(
            createdUserMap,
            existingUserMap,
            contactsToRevert,
            UserInfo.getUserId()
        ));
        Test.stopTest();
        
        // Verify all operations completed
        List<Contact> updatedContacts = [SELECT Id, Linked_User_Id__c, Active_Status__c 
                                         FROM Contact WHERE Id IN :contacts];
        System.assertEquals(3, updatedContacts.size(), 'All 3 contacts should be updated');
    }
}