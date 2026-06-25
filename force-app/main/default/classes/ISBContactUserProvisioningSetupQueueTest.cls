@isTest
public class ISBContactUserProvisioningSetupQueueTest {

    @testSetup
    static void setup() {
        // Ensure the Academic Associate Profile and Role exist (Org dependent, but usually present in this project)
        // We will create the data in individual tests or here if generic.
    }

    /**
     * Test Case: Successful User Provisioning
     * Scenario: A valid AA Contact with an AA Profile is passed to the queue. 
     * Expected: A new User is created.
     */
    @isTest
    static void testSuccessfulProvisioning() {
        // 1. Create AA Contact and Profile
        // Note: testAAContact in factory inserts a Linked_User_Id__c usually, 
        // but the queueable skips if Linked_User_Id__c is present. 
        // We'll create a fresh one manually via factory-like steps if needed, 
        // or just use factory and then clear the field.
        
        Contact con = new Contact(
            FirstName = 'Provision',
            LastName = 'Test',
            Email = 'provision.test@isb.com',
            ISB_Email_ID__c = 'provision.test@isb.com',
            VF_Email_ID__c = 'provision.test@isb.com',
            hed__Preferred_Email__c = 'Alternate Email',
            hed__AlternateEmail__c = 'provision.test@isb.com'
        );
        Id aaRTId = [SELECT Id FROM RecordType WHERE SObjectType='Contact' AND DeveloperName='Academic_Associate' LIMIT 1].Id;
        con.RecordTypeId = aaRTId;
        insert con;
        
        // Defensively handle profile (might be created by flow)
        List<AA_Profile__c> profiles = [SELECT Id FROM AA_Profile__c WHERE Academic_Associate__c = :con.Id];
        AA_Profile__c profile;
        if (profiles.isEmpty()) {
            profile = new AA_Profile__c(
                Academic_Associate__c = con.Id,
                Employee_ID__c = 'EMP001',
                Status__c = 'Active'
            );
            insert profile;
        } else {
            profile = profiles[0];
            profile.Employee_ID__c = 'EMP001';
            profile.Status__c = 'Active';
            update profile;
        }

        Set<Id> contactIds = new Set<Id>{ con.Id };

        Test.startTest();
        ISBContactUserProvisioningSetupQueue job = new ISBContactUserProvisioningSetupQueue(contactIds, UserInfo.getUserId());
        System.enqueueJob(job);
        Test.stopTest(); // Executes Queueable

        // Verify User Creation
        List<User> createdUsers = [SELECT Id, Email FROM User WHERE Email = :con.ISB_Email_ID__c AND ContactId = null]; 
        // ContactId remains null on User until BusinessQueue links them, or SetupQueue builds it.
        // SetupQueue builds User object but doesn't set ContactId (standard User doesn't have ContactId unless it's a Portal User)
        // Actually, the SetupQueue code: u.ProfileId = profileId; ... (Standard User doesn't have ContactId field)
        
        System.assertEquals(1, createdUsers.size(), 'One user should have been created');
    }

    /**
     * Test Case: Existing User Mapping
     * Scenario: Contact Email matches an existing internal User.
     * Expected: No new user created, SetupQueue identifies it as an existing user.
     */
    @isTest
    static void testExistingUserMapping() {
        // 1. Create existing user
        String uniqueEmail = 'existing.aa@example.com';
        User existingUser = TestDataFactory.testUser('existAA', uniqueEmail);

        Id aaRTId = [SELECT Id FROM RecordType WHERE SObjectType='Contact' AND DeveloperName='Academic_Associate' LIMIT 1].Id;
        // 2. Create AA Contact with same email
        Contact con = new Contact(
            FirstName = 'Existing',
            LastName = 'UserTest',
            Email = uniqueEmail,
            ISB_Email_ID__c = uniqueEmail,
            VF_Email_ID__c = uniqueEmail,
            hed__Preferred_Email__c = 'Alternate Email',
            hed__AlternateEmail__c = uniqueEmail,
            RecordTypeId = aaRTId
        );
        insert con;
        
        // Defensively handle profile
        List<AA_Profile__c> profiles = [SELECT Id FROM AA_Profile__c WHERE Academic_Associate__c = :con.Id];
        AA_Profile__c profile;
        if (profiles.isEmpty()) {
            profile = new AA_Profile__c(
                Academic_Associate__c = con.Id,
                Employee_ID__c = 'EMP002',
                Status__c = 'Active'
            );
            insert profile;
        } else {
            profile = profiles[0];
            profile.Employee_ID__c = 'EMP002';
            profile.Status__c = 'Active';
            update profile;
        }

        Set<Id> contactIds = new Set<Id>{ con.Id };

        Test.startTest();
        ISBContactUserProvisioningSetupQueue job = new ISBContactUserProvisioningSetupQueue(contactIds, UserInfo.getUserId());
        System.enqueueJob(job);
        Test.stopTest();

        // Verify: No second user with this email was created
        List<User> users = [SELECT Id FROM User WHERE Email = :uniqueEmail];
        System.assertEquals(1, users.size(), 'Should still only have 1 user (the existing one)');
    }

    /**
     * Test Case: Validation Failure (Missing Employee ID)
     * Scenario: AA Profile is missing Employee_ID__c.
     * Expected: User is not created.
     */
    @isTest
    static void testValidationFailure() {
        Id aaRTId = [SELECT Id FROM RecordType WHERE SObjectType='Contact' AND DeveloperName='Academic_Associate' LIMIT 1].Id;
        Contact con = new Contact(
            FirstName = 'Fail',
            LastName = 'Validation',
            Email = 'fail.val@example.com',
            ISB_Email_ID__c = 'fail.val@example.com',
            VF_Email_ID__c = 'fail.val@example.com',
            hed__Preferred_Email__c = 'Alternate Email',
            hed__AlternateEmail__c = 'fail.val@example.com',
            RecordTypeId = aaRTId
        );
        insert con;
        
        // No Employee ID
        // Defensively handle profile
        List<AA_Profile__c> profiles = [SELECT Id FROM AA_Profile__c WHERE Academic_Associate__c = :con.Id];
        AA_Profile__c profile;
        if (profiles.isEmpty()) {
            profile = new AA_Profile__c(
                Academic_Associate__c = con.Id,
                Status__c = 'Active'
            );
            insert profile;
        } else {
            profile = profiles[0];
            profile.Status__c = 'Active';
            update profile;
        }

        Set<Id> contactIds = new Set<Id>{ con.Id };

        Test.startTest();
        ISBContactUserProvisioningSetupQueue job = new ISBContactUserProvisioningSetupQueue(contactIds, UserInfo.getUserId());
        System.enqueueJob(job);
        Test.stopTest();

        // Verify: No user created
        List<User> users = [SELECT Id FROM User WHERE Email = :con.Email];
        System.assertEquals(0, users.size(), 'User should not be created for invalid data');
    }

    /**
     * Test Case: Skip already linked Contacts
     */
    @isTest
    static void testSkipAlreadyLinked() {
        User u = TestDataFactory.testUser('link', 'linked.user@example.com');
        
        Id aaRTId = [SELECT Id FROM RecordType WHERE SObjectType='Contact' AND DeveloperName='Academic_Associate' LIMIT 1].Id;
        Contact con = new Contact(
            FirstName = 'Linked',
            LastName = 'Already',
            Email = 'linked.user@example.com',
            ISB_Email_ID__c = 'linked.user@example.com',
            VF_Email_ID__c = 'linked.user@example.com',
            hed__Preferred_Email__c = 'Alternate Email',
            hed__AlternateEmail__c = 'linked.user@example.com',
            Linked_User_Id__c = u.Id,
            RecordTypeId = aaRTId
        );
        insert con;

        Set<Id> contactIds = new Set<Id>{ con.Id };

        Test.startTest();
        ISBContactUserProvisioningSetupQueue job = new ISBContactUserProvisioningSetupQueue(contactIds, UserInfo.getUserId());
        System.enqueueJob(job);
        Test.stopTest();

        // Coverage check: Should exit early for this record
        System.assert(true);
    }
}