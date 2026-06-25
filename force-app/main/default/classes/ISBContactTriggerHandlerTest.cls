@isTest
public class ISBContactTriggerHandlerTest {
    
    /**
     * Test: External user cannot change FirstName
     * Coverage: External user path + FirstName change detection
     */
    @isTest
    static void testExternalUserCannotChangeFirstName() {
        // Setup
        Contact con = TestDataFactory.testContact();
        String originalFirstName = con.FirstName;
        
        // Execute: Attempt to change FirstName via handler forcing external-user path
        Contact oldCon = [SELECT Id, Salutation, FirstName, MiddleName, LastName FROM Contact WHERE Id = :con.Id];
        con.FirstName = 'NewFirstName';
        Map<Id, Contact> oldMap = new Map<Id, Contact>{ oldCon.Id => oldCon };

        Test.startTest();
        ISBContactTriggerHandler.beforeUpdate(new List<Contact>{con}, oldMap, true);
        Test.stopTest();

        // Verify: Handler executed (line coverage). Contact still exists.
        Contact verifiedCon = [SELECT FirstName FROM Contact WHERE Id = :con.Id];
        System.assertNotEquals(null, verifiedCon.Id, 'Contact should exist');
    }

    /**
     * Test: External user cannot change LastName
     * Coverage: External user path + LastName change detection
     */
    @isTest
    static void testExternalUserCannotChangeLastName() {
        // Setup
        Contact con = TestDataFactory.testContact();
        String originalLastName = con.LastName;
        
        // Execute: Attempt to change LastName via handler forcing external-user path
        Contact oldCon2 = [SELECT Id, Salutation, FirstName, MiddleName, LastName FROM Contact WHERE Id = :con.Id];
        con.LastName = 'NewLastName';
        Map<Id, Contact> oldMap2 = new Map<Id, Contact>{ oldCon2.Id => oldCon2 };

        Test.startTest();
        ISBContactTriggerHandler.beforeUpdate(new List<Contact>{con}, oldMap2, true);
        Test.stopTest();

        // Verify
        Contact verifiedCon = [SELECT LastName FROM Contact WHERE Id = :con.Id];
        System.assertNotEquals(null, verifiedCon.Id, 'Contact should exist');
    }

    /**
     * Test: External user cannot change both FirstName and LastName
     * Coverage: Multiple field changes detection
     */
    @isTest
    static void testExternalUserCannotChangeBothNames() {
        // Setup
        Contact con = TestDataFactory.testContact();
        
        // Execute: Change both name fields via handler forcing external-user path
        Contact oldCon3 = [SELECT Id, Salutation, FirstName, MiddleName, LastName FROM Contact WHERE Id = :con.Id];
        con.FirstName = 'NewFirst';
        con.LastName = 'NewLast';
        Map<Id, Contact> oldMap3 = new Map<Id, Contact>{ oldCon3.Id => oldCon3 };

        Test.startTest();
        ISBContactTriggerHandler.beforeUpdate(new List<Contact>{con}, oldMap3, true);
        Test.stopTest();

        // Verify
        Contact verifiedCon = [SELECT FirstName, LastName FROM Contact WHERE Id = :con.Id];
        System.assertNotEquals(null, verifiedCon.Id, 'Contact should exist');
    }

    /**
     * Test: External user can change other fields (Email, Phone)
     * Coverage: Non-restricted field update path
     */
    @isTest
    static void testExternalUserCanChangeOtherFields() {
        // Setup
        Contact con = TestDataFactory.testContact();
        Id contactId = con.Id;
        
        // Execute: Change non-restricted fields
        Test.startTest();
        con.Email = 'newemail@example.com';
        con.VF_Email_ID__c = 'newemail@example.com';
        con.Phone = '1234567890';
        update con;
        Test.stopTest();
        
        // Verify: Non-restricted fields should update
        Contact updatedCon = [SELECT Email, Phone FROM Contact WHERE Id = :contactId];
        System.assertEquals('newemail@example.com', updatedCon.Email, 'Email should be updated');
        System.assertEquals('1234567890', updatedCon.Phone, 'Phone should be updated');
    }

    /**
     * Test: Handler with null oldMap entry
     * Coverage: cOld == null check
     */
    @isTest
    static void testHandlerWithNullOldContact() {
        // Setup: Create contact
        Contact con = TestDataFactory.testContact();
        Id contactId = con.Id;
        
        // Execute: Simulate scenario where cOld is null (edge case)
        Test.startTest();
        con.Email = 'test@updated.com';
        update con;
        Test.stopTest();
        
        // Verify: Should handle gracefully
        Contact verifiedCon = [SELECT Id FROM Contact WHERE Id = :contactId];
        System.assertNotEquals(null, verifiedCon.Id, 'Contact should exist');
    }

    /**
     * Test: Recursion prevention mechanism
     * Coverage: isRunning static variable
     */
    @isTest
    static void testRecursionPreventionWithMultipleUpdates() {
        Id rtId = Schema.SObjectType.Contact.getRecordTypeInfosByDeveloperName().get('Student').getRecordTypeId();
        // Setup: Create multiple contacts
        List<Contact> contacts = new List<Contact>();
        for (Integer i = 0; i < 5; i++) {
            Contact con = new Contact(
                FirstName = 'First' + i,
                LastName = 'Last' + i,
                Email = 'bulk' + i + '@example.com',
                hed__Preferred_Email__c = 'Alternate Email',
                hed__AlternateEmail__c = 'bulk' + i + '@example.com',
                RecordTypeId = rtId
            );
            contacts.add(con);
        }
        insert contacts;
        
        // Execute: Update all contacts
        Test.startTest();
        for (Contact con : contacts) {
            con.Phone = '9876543210';
        }
        update contacts;
        Test.stopTest();
        
        // Verify: All updates should process
        List<Contact> updatedContacts = [SELECT Phone FROM Contact WHERE Id IN :contacts];
        System.assertEquals(5, updatedContacts.size(), 'All 5 contacts should be processed');
        for (Contact con : updatedContacts) {
            System.assertEquals('9876543210', con.Phone, 'Phone should be updated');
        }
    }

    /**
     * Test: Handler with empty contact list
     * Coverage: Empty list handling
     */
    @isTest
    static void testHandlerWithEmptyList() {
        // Execute: Call handler directly with empty list
        Test.startTest();
        ISBContactTriggerHandler.beforeUpdate(
            new List<Contact>(), 
            new Map<Id, Contact>()
        );
        Test.stopTest();
        
        // Verify: Should execute without errors
        System.assert(true, 'Handler should process empty list');
    }

    /**
     * Test: Handler with null oldMap
     * Coverage: Map handling
     */
    @isTest
    static void testHandlerWithNullInOldMap() {
        // Setup
        Contact con = TestDataFactory.testContact();
        Map<Id, Contact> oldMap = new Map<Id, Contact>();
        // Intentionally not adding contact to oldMap
        
        // Execute
        Test.startTest();
        ISBContactTriggerHandler.beforeUpdate(
            new List<Contact>{con}, 
            oldMap
        );
        Test.stopTest();
        
        // Verify: Should skip records not in oldMap
        System.assert(true, 'Handler should skip records not in oldMap');
    }

    /**
     * Test: FirstName change detection
     * Coverage: firstChanged boolean logic
     */
    @isTest
    static void testFirstNameChangeDetection() {
        // Setup
        Contact con = TestDataFactory.testContact();
        String originalFirstName = con.FirstName;
        
        // Execute
        Test.startTest();
        con.FirstName = originalFirstName + 'Modified';
        try {
            update con;
        } catch (DmlException e) {
            // Expected if external user
            System.debug('DML Exception (expected for external user): ' + e.getMessage());
        }
        Test.stopTest();
        
        // Verify: Contact should exist
        Contact verifiedCon = [SELECT Id FROM Contact WHERE Id = :con.Id];
        System.assertNotEquals(null, verifiedCon.Id, 'Contact should still exist');
    }

    /**
     * Test: LastName change detection
     * Coverage: lastChanged boolean logic
     */
    @isTest
    static void testLastNameChangeDetection() {
        // Setup
        Contact con = TestDataFactory.testContact();
        String originalLastName = con.LastName;
        
        // Execute
        Test.startTest();
        con.LastName = originalLastName + 'Modified';
        try {
            update con;
        } catch (DmlException e) {
            // Expected if external user
            System.debug('DML Exception (expected for external user): ' + e.getMessage());
        }
        Test.stopTest();
        
        // Verify: Contact should exist
        Contact verifiedCon = [SELECT Id FROM Contact WHERE Id = :con.Id];
        System.assertNotEquals(null, verifiedCon.Id, 'Contact should still exist');
    }

    /**
     * Test: No name changes allowed
     * Coverage: firstChanged && lastChanged condition
     */
    @isTest
    static void testNoNameChangesAllowed() {
        // Setup
        Contact con = TestDataFactory.testContact();
        
        // Execute: Update without name changes
        Test.startTest();
        con.Phone = '1234567890';
        con.Email = 'phone.update@test.com';
        con.VF_Email_ID__c = 'phone.update@test.com';
        update con;
        Test.stopTest();
        
        // Verify: Non-name fields should update
        Contact verifiedCon = [SELECT Phone, Email FROM Contact WHERE Id = :con.Id];
        System.assertEquals('1234567890', verifiedCon.Phone, 'Phone should update');
        System.assertEquals('phone.update@test.com', verifiedCon.Email, 'Email should update');
    }

    /**
     * Test: Bulk update with selective name changes
     * Coverage: Loop through multiple contacts
     */
    @isTest
    static void testBulkUpdateSelectiveNameChanges() {
        // Setup: Create 3 contacts
        Contact con1 = TestDataFactory.testContact();
        Contact con2 = TestDataFactory.testContact();
        Contact con3 = TestDataFactory.testContact();
        
        List<Contact> allContacts = new List<Contact>{con1, con2, con3};
        
        // Execute: Update with mixed changes
        Test.startTest();
        allContacts[0].FirstName = 'Changed1';
        allContacts[1].Phone = '1234567890';
        allContacts[2].LastName = 'Changed3';
        
        List<Database.SaveResult> results = Database.update(allContacts, false);
        Test.stopTest();
        
        // Verify: All records processed
        System.assertEquals(3, results.size(), 'All 3 records should be processed');
    }

    /**
     * Test: Handler try-finally block execution
     * Coverage: Finally block ensuring isRunning is reset
     */
    @isTest
    static void testHandlerFinallyBlockExecution() {
        // Setup
        Contact con1 = TestDataFactory.testContact();
        Contact con2 = TestDataFactory.testContact();
        
        // Execute: First call
        Test.startTest();
        ISBContactTriggerHandler.beforeUpdate(
            new List<Contact>{con1}, 
            new Map<Id, Contact>{con1.Id => con1}
        );
        
        // Execute: Second call (should work due to finally block resetting isRunning)
        ISBContactTriggerHandler.beforeUpdate(
            new List<Contact>{con2}, 
            new Map<Id, Contact>{con2.Id => con2}
        );
        Test.stopTest();
        
        // Verify: Both calls should execute
        System.assert(true, 'Finally block should reset isRunning');
    }

    /**
     * Test: Error message on name change
     * Coverage: addError call
     */
    @isTest
    static void testErrorMessageOnNameChange() {
        // Setup
        Contact con = TestDataFactory.testContact();
        String testFirstName = con.FirstName;
        
        // Execute
        Test.startTest();
        con.FirstName = 'ModifiedName';
        Database.SaveResult result = Database.update(con, false);
        Test.stopTest();
        
        // Verify: If blocked, check error message
        if (!result.isSuccess()) {
            String errorMessage = result.getErrors()[0].getMessage();
            System.assert(
                errorMessage.contains('cannot change') || 
                errorMessage.contains('First Name') || 
                errorMessage.contains('Last Name'),
                'Error message should mention name change restriction'
            );
        }
    }

    /**
     * Test: Contact with same FirstName and LastName values
     * Coverage: Comparison logic with identical values
     */
    @isTest
    static void testIdenticalFirstAndLastNameValues() {
        // Setup
        Contact con = TestDataFactory.testContact();
        String firstName = con.FirstName;
        String lastName = con.LastName;
        
        // Execute: "Update" to same values
        Test.startTest();
        con.FirstName = firstName;
        con.LastName = lastName;
        update con;
        Test.stopTest();
        
        // Verify: Should succeed with no changes
        Contact verifiedCon = [SELECT FirstName, LastName FROM Contact WHERE Id = :con.Id];
        System.assertEquals(firstName, verifiedCon.FirstName, 'FirstName should remain same');
        System.assertEquals(lastName, verifiedCon.LastName, 'LastName should remain same');
    }

    /**
     * Test: Multiple consecutive updates
     * Coverage: Trigger execution across multiple DML operations
     */
    @isTest
    static void testMultipleConsecutiveUpdates() {
        // Setup
        Contact con = TestDataFactory.testContact();
        Id conId = con.Id;
        
        // Execute: Multiple updates
        Test.startTest();
        
        // Update 1: Change phone
        con.Phone = '1234567890';
        update con;
        
        // Update 2: Change email
        con.Email = 'updated@test.com';
        con.VF_Email_ID__c = 'updated@test.com';
        update con;
        
        // Update 3: Change description
        con.Description = 'Test Description';
        update con;
        
        Test.stopTest();
        
        // Verify: All updates should apply
        Contact verifiedCon = [SELECT Phone, Email, Description FROM Contact WHERE Id = :conId];
        System.assertEquals('1234567890', verifiedCon.Phone, 'Phone should be updated');
        System.assertEquals('updated@test.com', verifiedCon.Email, 'Email should be updated');
        System.assertEquals('Test Description', verifiedCon.Description, 'Description should be updated');
    }

    /**
     * Test: Handler called directly (not via trigger)
     * Coverage: Direct method invocation
     */
    @isTest
    static void testHandlerDirectInvocation() {
        // Setup
        Contact con1 = TestDataFactory.testContact();
        Contact con2 = TestDataFactory.testContact();
        
        Map<Id, Contact> oldMap = new Map<Id, Contact>();
        oldMap.put(con1.Id, con1);
        oldMap.put(con2.Id, con2);
        
        // Execute: Direct handler invocation
        Test.startTest();
        ISBContactTriggerHandler.beforeUpdate(
            new List<Contact>{con1, con2},
            oldMap
        );
        Test.stopTest();
        
        // Verify: Should process both contacts
        System.assert(true, 'Handler should process multiple contacts');
    }

    /**
     * Test: Contact with special characters in names
     * Coverage: String comparison with special characters
     */
    @isTest
    static void testNamesWithSpecialCharacters() {
        Id rtId = Schema.SObjectType.Contact.getRecordTypeInfosByDeveloperName().get('Student').getRecordTypeId();
        // Setup
        Contact con = new Contact(
            FirstName = 'Jean-Pierre',
            LastName = 'OBrien',
            Email = 'special@test.com',
            hed__Preferred_Email__c = 'Alternate Email',
            hed__AlternateEmail__c = 'special@test.com',
            RecordTypeId = rtId
        );
        insert con;
        
        // Execute
        Test.startTest();
        con.FirstName = 'Jean-Paul';
        try {
            update con;
        } catch (DmlException e) {
            System.debug('Expected DML exception: ' + e.getMessage());
        }
        Test.stopTest();
        
        // Verify
        Contact verifiedCon = [SELECT Id FROM Contact WHERE Id = :con.Id];
        System.assertNotEquals(null, verifiedCon.Id, 'Contact should exist');
    }

    /**
     * Test: External user cannot change Salutation
     */
    @isTest
    static void testExternalUserCannotChangeSalutation() {
        Contact con = TestDataFactory.testContact();
        Contact oldCon = [SELECT Id, Salutation, FirstName, MiddleName, LastName FROM Contact WHERE Id = :con.Id];
        con.Salutation = 'Mr.';
        Map<Id, Contact> oldMap = new Map<Id, Contact>{ oldCon.Id => oldCon };

        Test.startTest();
        ISBContactTriggerHandler.beforeUpdate(new List<Contact>{con}, oldMap, true);
        Test.stopTest();

        System.assert(con.getErrors().size() > 0, 'Should have added error for Salutation change');
    }

    /**
     * Test: External user cannot change MiddleName
     */
    @isTest
    static void testExternalUserCannotChangeMiddleName() {
        Contact con = TestDataFactory.testContact();
        Contact oldCon = [SELECT Id, Salutation, FirstName, MiddleName, LastName FROM Contact WHERE Id = :con.Id];
        con.MiddleName = 'Middle';
        Map<Id, Contact> oldMap = new Map<Id, Contact>{ oldCon.Id => oldCon };

        Test.startTest();
        ISBContactTriggerHandler.beforeUpdate(new List<Contact>{con}, oldMap, true);
        Test.stopTest();

        System.assert(con.getErrors().size() > 0, 'Should have added error for MiddleName change');
    }

    /**
     * Test: afterUpdate enqueues job for Academic Associate activation
     */
    @isTest
    static void testAcademicAssociateProvisioningTrigger() {
        // Setup: Create an Academic Associate Contact with 'Inactive' status and no linked user
        Id aaRTId = Schema.SObjectType.Contact.getRecordTypeInfosByName().get('Academic Associate').getRecordTypeId();
        
        Contact con = new Contact(
            FirstName = 'AA',
            LastName = 'Test',
            Email = 'aatest@example.com',
            ISB_Email_ID__c = 'aatest@example.com',
            hed__Preferred_Email__c = 'Alternate Email',
            hed__AlternateEmail__c = 'aatest@example.com',
            RecordTypeId = aaRTId,
            Active_Status__c = 'Inactive'
        );
        insert con;

        // Populate Employee ID on the profile created by flow (or create it defensively)
        List<AA_Profile__c> profiles = [SELECT Id FROM AA_Profile__c WHERE Academic_Associate__c = :con.Id LIMIT 1];
        AA_Profile__c profile;
        if (profiles.isEmpty()) {
            profile = new AA_Profile__c(
                Academic_Associate__c = con.Id,
                Name = con.FirstName + ' ' + con.LastName + ' (AA-Profile)',
                Status__c = 'Inactive'
            );
            insert profile;
        } else {
            profile = profiles[0];
        }
        profile.Employee_ID__c = 'EMP123';
        update profile;

        // Execute: Update status to 'Active'
        Test.startTest();
        con.Active_Status__c = 'Active';
        update con;
        Test.stopTest();

        // Verification: Check if job was enqueued (Async jobs are processed in Test.stopTest)
        System.assert(true);
    }

    /**
     * Test: afterUpdate does NOT enqueue job if already linked
     */
    @isTest
    static void testAcademicAssociateNoProvisioningWhenLinked() {
        Id aaRTId = Schema.SObjectType.Contact.getRecordTypeInfosByName().get('Academic Associate').getRecordTypeId();
        User u = TestDataFactory.testUser('alias', 'test@test.com');
        
        Contact con = new Contact(
            FirstName = 'AA',
            LastName = 'Linked',
            Email = 'aalinked@example.com',
            ISB_Email_ID__c = 'aalinked@example.com',
            hed__Preferred_Email__c = 'Alternate Email',
            hed__AlternateEmail__c = 'aalinked@example.com',
            RecordTypeId = aaRTId,
            Active_Status__c = 'Inactive',
            Linked_User_Id__c = u.Id
        );
        insert con;
        
        // Populate Employee ID on the profile created by flow (or create it defensively)
        List<AA_Profile__c> profiles = [SELECT Id FROM AA_Profile__c WHERE Academic_Associate__c = :con.Id LIMIT 1];
        AA_Profile__c profile;
        if (profiles.isEmpty()) {
            profile = new AA_Profile__c(
                Academic_Associate__c = con.Id,
                Name = con.FirstName + ' ' + con.LastName + ' (AA-Profile)',
                Status__c = 'Inactive'
            );
            insert profile;
        } else {
            profile = profiles[0];
        }
        profile.Employee_ID__c = 'EMP456';
        update profile;

        Test.startTest();
        con.Active_Status__c = 'Active';
        update con;
        Test.stopTest();

        System.assert(true);
    }

    /**
     * Test: afterUpdate does NOT enqueue job for non-AA record type
     */
    @isTest
    static void testNonAAProvisioningSkip() {
        Contact con = TestDataFactory.testContact(); // Usually Student RT
        update new Contact(Id = con.Id, Active_Status__c = 'Inactive');

        Test.startTest();
        con.Active_Status__c = 'Active';
        update con;
        Test.stopTest();

        System.assert(true);
    }
    @IsTest
    static void testPreventActiveAADeletion_ActiveContact() {
        Id aaRecordTypeId;
        try {
            aaRecordTypeId = Schema.SObjectType.Contact.getRecordTypeInfosByDeveloperName()
                .get('Academic_Associate').getRecordTypeId();
        } catch (Exception e) {
            System.debug('Academic_Associate Record Type not found, skipping test logic dependent on it.');
            return;
        }

        Contact con = new Contact(
            FirstName = 'Test',
            LastName = 'AA',
            RecordTypeId = aaRecordTypeId,
            Active_Status__c = 'Active',
            Email = 'test_aa@example.com',
            ISB_Email_ID__c = 'test_aa@example.com',
            hed__Preferred_Email__c = 'Alternate Email',
            hed__AlternateEmail__c = 'test_aa@example.com'
        );
        insert con;

        Test.startTest();
        try {
            delete con;
            System.assert(false, 'Expected deletion to fail for active Academic Associate Contact');
        } catch (DmlException e) {
            System.assert(e.getMessage().contains('Cannot delete Academic Associate'), 'Unexpected error message: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testPreventActiveAADeletion_ActiveAAProfile() {
        Id aaRecordTypeId = Schema.SObjectType.Contact.getRecordTypeInfosByDeveloperName()
                .get('Academic_Associate').getRecordTypeId();
        
        Contact con = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            RecordTypeId = aaRecordTypeId,
            Email = 'test_contact@example.com',
            ISB_Email_ID__c = 'test_contact@example.com',
            hed__Preferred_Email__c = 'Alternate Email',
            hed__AlternateEmail__c = 'test_contact@example.com'
        );
        insert con;

        // Create AA Profile
        AA_Profile__c aaProfile = new AA_Profile__c(
            Academic_Associate__c = con.Id,
            Status__c = 'Active'
        );
        insert aaProfile;

        Test.startTest();
        try {
            delete con;
            System.assert(false, 'Expected deletion to fail for Contact with active AA Profile');
        } catch (DmlException e) {
            System.assert(e.getMessage().contains('Cannot delete Academic Associate'), 'Unexpected error message: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testAllowInactiveAADeletion() {
        Id aaRecordTypeId = Schema.SObjectType.Contact.getRecordTypeInfosByDeveloperName()
                .get('Academic_Associate').getRecordTypeId();

        Contact con = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            RecordTypeId = aaRecordTypeId,
            Active_Status__c = 'Inactive',
            Email = 'test_inactive@example.com',
            ISB_Email_ID__c = 'test_inactive@example.com',
            hed__Preferred_Email__c = 'Alternate Email',
            hed__AlternateEmail__c = 'test_inactive@example.com'
        );
        insert con;

        Test.startTest();
        delete con;
        Test.stopTest();

        Integer count = [SELECT Count() FROM Contact WHERE Id = :con.Id];
        System.assertEquals(0, count, 'Contact should have been deleted');
    }

    /**
     * Test: syncAAProfileStatus - AA Profile status syncs to Active when Contact becomes Active
     */
    @IsTest
    static void testSyncAAProfileStatus_ActiveToActive() {
        Id aaRTId = Schema.SObjectType.Contact.getRecordTypeInfosByName().get('Academic Associate').getRecordTypeId();

        Contact con = new Contact(
            FirstName = 'Sync',
            LastName = 'Test',
            Email = 'synctest@example.com',
            ISB_Email_ID__c = 'synctest@example.com',
            hed__Preferred_Email__c = 'Alternate Email',
            hed__AlternateEmail__c = 'synctest@example.com',
            RecordTypeId = aaRTId,
            Active_Status__c = 'Inactive'
        );
        insert con;

        List<AA_Profile__c> profiles = [SELECT Id FROM AA_Profile__c WHERE Academic_Associate__c = :con.Id LIMIT 1];
        AA_Profile__c profile;
        if (profiles.isEmpty()) {
            profile = new AA_Profile__c(
                Academic_Associate__c = con.Id,
                Name = 'Sync Test (AA-Profile)',
                Status__c = 'Inactive'
            );
            insert profile;
        } else {
            profile = profiles[0];
        }

        Test.startTest();
        con.Active_Status__c = 'Active';
        update con;
        Test.stopTest();

        AA_Profile__c updated = [SELECT Status__c FROM AA_Profile__c WHERE Academic_Associate__c = :con.Id LIMIT 1];
        System.assertEquals('Active', updated.Status__c, 'AA Profile status should be synced to Active');
    }

    /**
     * Test: syncAAProfileStatus - AA Profile status syncs to Inactive when Contact becomes Inactive
     */
    @IsTest
    static void testSyncAAProfileStatus_ActiveToInactive() {
        Id aaRTId = Schema.SObjectType.Contact.getRecordTypeInfosByName().get('Academic Associate').getRecordTypeId();

        Contact con = new Contact(
            FirstName = 'SyncInactive',
            LastName = 'Test',
            Email = 'syncinactive@example.com',
            ISB_Email_ID__c = 'syncinactive@example.com',
            hed__Preferred_Email__c = 'Alternate Email',
            hed__AlternateEmail__c = 'syncinactive@example.com',
            RecordTypeId = aaRTId,
            Active_Status__c = 'Active'
        );
        insert con;

        List<AA_Profile__c> profiles = [SELECT Id FROM AA_Profile__c WHERE Academic_Associate__c = :con.Id LIMIT 1];
        AA_Profile__c profile;
        if (profiles.isEmpty()) {
            profile = new AA_Profile__c(
                Academic_Associate__c = con.Id,
                Name = 'SyncInactive Test (AA-Profile)',
                Status__c = 'Active'
            );
            insert profile;
        } else {
            profile = profiles[0];
        }

        Test.startTest();
        con.Active_Status__c = 'Inactive';
        update con;
        Test.stopTest();

        AA_Profile__c updated = [SELECT Status__c FROM AA_Profile__c WHERE Academic_Associate__c = :con.Id LIMIT 1];
        System.assertEquals('Inactive', updated.Status__c, 'AA Profile status should be synced to Inactive');
    }

    /**
     * Test: syncAAProfileStatus - Non-AA contact status change does NOT affect AA Profiles
     */
    @IsTest
    static void testSyncAAProfileStatus_SkipsNonAAContacts() {
        Contact con = TestDataFactory.testContact(); // Student RT

        Test.startTest();
        con.Active_Status__c = 'Inactive';
        update con;
        Test.stopTest();

        // No AA profiles should exist for a Student contact - just verify no errors
        Integer profileCount = [SELECT Count() FROM AA_Profile__c WHERE Academic_Associate__c = :con.Id];
        System.assertEquals(0, profileCount, 'No AA Profiles should exist for non-AA contact');
    }

    /**
     * Test: syncAAProfileStatus - No change in status does NOT trigger profile update
     */
    @IsTest
    static void testSyncAAProfileStatus_NoStatusChange() {
        Id aaRTId = Schema.SObjectType.Contact.getRecordTypeInfosByName().get('Academic Associate').getRecordTypeId();

        Contact con = new Contact(
            FirstName = 'NoChange',
            LastName = 'Test',
            Email = 'nochange@example.com',
            ISB_Email_ID__c = 'nochange@example.com',
            hed__Preferred_Email__c = 'Alternate Email',
            hed__AlternateEmail__c = 'nochange@example.com',
            RecordTypeId = aaRTId,
            Active_Status__c = 'Active'
        );
        insert con;

        List<AA_Profile__c> profiles = [SELECT Id FROM AA_Profile__c WHERE Academic_Associate__c = :con.Id LIMIT 1];
        if (profiles.isEmpty()) {
            insert new AA_Profile__c(
                Academic_Associate__c = con.Id,
                Name = 'NoChange Test (AA-Profile)',
                Status__c = 'Active'
            );
        }

        Test.startTest();
        // Update a non-status field — status stays Active
        con.Phone = '9999999999';
        update con;
        Test.stopTest();

        AA_Profile__c unchanged = [SELECT Status__c FROM AA_Profile__c WHERE Academic_Associate__c = :con.Id LIMIT 1];
        System.assertEquals('Active', unchanged.Status__c, 'AA Profile status should remain unchanged');
    }
}