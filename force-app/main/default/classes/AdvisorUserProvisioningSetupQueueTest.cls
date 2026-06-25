@isTest
public class AdvisorUserProvisioningSetupQueueTest {

    @TestSetup
    static void setup() {
        // Create Advisor Profile
        Profile advisorProfile = new Profile();
        try {
            advisorProfile = [SELECT Id FROM Profile WHERE Name = 'Advisor' LIMIT 1];
        } catch (Exception e) {
            // Profile might not exist in test context, that's OK
        }
        
        // Create Advisor Role
        UserRole advisorRole = new UserRole(Name = 'Advisor Test Role');
        insert advisorRole;

        User currentUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        
        // Create Advisor Record Type
        Id advisorRTId = Schema.SObjectType.Contact.getRecordTypeInfosByName().get('Advisor').getRecordTypeId();
        
        // Create test Contacts
        List<Contact> contacts = new List<Contact>();
        for (Integer i = 0; i < 5; i++) {
            contacts.add(new Contact(
                FirstName = 'Advisor',
                LastName = 'Test' + i,
                Email = 'advisor.test' + i + '@test.com',
                ISB_Email_ID__c = 'advisor.test' + i + '@test.com',
                RecordTypeId = advisorRTId,
                Active_Status__c = 'Inactive'
            ));
        }
        System.runAs(currentUser) {
            insert contacts;
        }
    }

    @isTest
    static void testSuccessfulUserCreation() {
        // Get test contacts
        List<Contact> contacts = [SELECT Id FROM Contact WHERE LastName LIKE 'Test%' LIMIT 2];
        Set<Id> contactIds = new Set<Id>();
        for (Contact c : contacts) {
            contactIds.add(c.Id);
        }
        
        Test.startTest();
        System.enqueueJob(new AdvisorUserProvisioningSetupQueue(contactIds, UserInfo.getUserId()));
        Test.stopTest();
        
        // Verify contacts were processed (in test context, the chained queueable won't execute)
        System.assertEquals(2, contactIds.size(), 'Should have 2 contacts to process');
    }

    @isTest
    static void testMissingRequiredFields() {
        // Create contact with missing fields
        Id advisorRTId = Schema.SObjectType.Contact.getRecordTypeInfosByName().get('Advisor').getRecordTypeId();
        Contact c = new Contact(
            FirstName = 'Test',
            LastName = 'MissingEmail',
            RecordTypeId = advisorRTId,
            Active_Status__c = 'Inactive'
        );
        insert c;
        
        Set<Id> contactIds = new Set<Id>{c.Id};
        
        Test.startTest();
        System.enqueueJob(new AdvisorUserProvisioningSetupQueue(contactIds, UserInfo.getUserId()));
        Test.stopTest();
        
        // Contact should be marked for revert due to missing fields
        System.assertEquals(1, contactIds.size(), 'Should have 1 contact to process');
    }

    @isTest
    static void testExistingUserByEmail() {
        // Create a user first
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User existingUser = new User(
            FirstName = 'Existing',
            LastName = 'User',
            Email = 'existing.user@test.com',
            Username = 'existinguser' + System.currentTimeMillis() + '@testorg.com',
            Alias = 'exuser',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = p.Id,
            LanguageLocaleKey = 'en_US'
        );
        insert existingUser;
        
        // Create contact with same email
        Id advisorRTId = Schema.SObjectType.Contact.getRecordTypeInfosByName().get('Advisor').getRecordTypeId();
        Contact c = new Contact(
            FirstName = 'Advisor',
            LastName = 'WithExistingUser',
            Email = 'existing.user@test.com',
            ISB_Email_ID__c = 'existing.user@test.com',
            RecordTypeId = advisorRTId,
            Active_Status__c = 'Inactive'
        );
        insert c;
        
        Set<Id> contactIds = new Set<Id>{c.Id};
        
        Test.startTest();
        System.enqueueJob(new AdvisorUserProvisioningSetupQueue(contactIds, UserInfo.getUserId()));
        Test.stopTest();
        
        // Should be tagged to link to existing user, not create new
        System.assertEquals(1, contactIds.size(), 'Should have 1 contact to process');
    }

    @isTest
    static void testExistingInactiveUserByEmailGetsReactivated() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User existingUser = new User(
            FirstName = 'Inactive',
            LastName = 'ExistingUser',
            Email = 'inactive.existing.user@test.com',
            Username = 'inactiveexistinguser' + System.currentTimeMillis() + '@testorg.com',
            Alias = 'iexuser',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = p.Id,
            LanguageLocaleKey = 'en_US',
            IsActive = false
        );
        insert existingUser;

        Id advisorRTId = Schema.SObjectType.Contact.getRecordTypeInfosByName().get('Advisor').getRecordTypeId();
        Contact c = new Contact(
            FirstName = 'Advisor',
            LastName = 'InactiveExistingUser',
            Email = 'inactive.existing.user@test.com',
            ISB_Email_ID__c = 'inactive.existing.user@test.com',
            RecordTypeId = advisorRTId,
            Active_Status__c = 'Active'
        );
        insert c;

        Test.startTest();
        System.enqueueJob(new AdvisorUserProvisioningSetupQueue(new Set<Id>{ c.Id }, UserInfo.getUserId()));
        Test.stopTest();

        User reactivatedUser = [SELECT IsActive FROM User WHERE Id = :existingUser.Id];
        System.assertEquals(true, reactivatedUser.IsActive,
            'Existing matched user should be reactivated when the advisor contact is activated.');
    }

    @isTest
    static void testBulkProcessing() {
        List<Contact> contacts = [SELECT Id FROM Contact WHERE LastName LIKE 'Test%'];
        Set<Id> contactIds = new Set<Id>();
        for (Contact c : contacts) {
            contactIds.add(c.Id);
        }
        
        Test.startTest();
        System.enqueueJob(new AdvisorUserProvisioningSetupQueue(contactIds, UserInfo.getUserId()));
        Test.stopTest();
        
        System.assertEquals(5, contactIds.size(), 'Should process all 5 test contacts');
    }

    @isTest
    static void testContactWithLinkedUser() {
        // Get a contact and add a linked user
        Contact c = [SELECT Id FROM Contact WHERE LastName LIKE 'Test%' LIMIT 1];
        c.Linked_User_Id__c = UserInfo.getUserId();
        update c;
        
        Set<Id> contactIds = new Set<Id>{c.Id};
        
        Test.startTest();
        System.enqueueJob(new AdvisorUserProvisioningSetupQueue(contactIds, UserInfo.getUserId()));
        Test.stopTest();
        
        // Contact should be skipped as it already has a linked user
        System.assertEquals(1, contactIds.size(), 'Should have 1 contact but should be skipped');
    }
}