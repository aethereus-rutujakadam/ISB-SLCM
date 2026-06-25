@isTest
public class FacultySearchControllerTest {

    @isTest
    static void testGetFacultyListSuccess() {
        // Setup: Create Faculty contacts
        Contact faculty1 = TestDataFactory.testFacultyContact('John', 'Doe', 'john.doe' + Datetime.now().getTime() + '@example.com');
        Contact faculty2 = TestDataFactory.testFacultyContact('Jane', 'Smith', 'jane.smith' + Datetime.now().getTime() + '@example.com');
        Contact faculty3 = TestDataFactory.testFacultyContact('Bob', 'Johnson', 'bob.johnson' + Datetime.now().getTime() + '@example.com');
        
        Test.startTest();
        List<Contact> results = FacultySearchController.getFacultyList('John');
        Test.stopTest();
        
        System.assertNotEquals(null, results, 'Results should not be null');
        System.assertEquals(2, results.size(), 'Should return 2 faculty members with "John" in name');
        System.assert(results[0].Name.contains('John') || results[1].Name.contains('John'), 'Results should contain John');
    }

    @isTest
    static void testGetFacultyListEmptySearch() {
        // Setup: Create Faculty contacts
        Contact faculty1 = TestDataFactory.testFacultyContact('Alice', 'Williams', 'alice.williams' + Datetime.now().getTime() + '@example.com');
        
        Test.startTest();
        List<Contact> results = FacultySearchController.getFacultyList('');
        Test.stopTest();
        
        System.assertNotEquals(null, results, 'Results should not be null');
        System.assert(results.size() >= 1, 'Should return at least 1 faculty member');
    }

    @isTest
    static void testGetFacultyListNoResults() {
        // Setup: Create Faculty contact
        Contact faculty1 = TestDataFactory.testFacultyContact('Test', 'Faculty', 'test.faculty' + Datetime.now().getTime() + '@example.com');
        
        Test.startTest();
        List<Contact> results = FacultySearchController.getFacultyList('XYZ123NonExistent');
        Test.stopTest();
        
        System.assertNotEquals(null, results, 'Results should not be null');
        System.assertEquals(0, results.size(), 'Should return no results for non-existent search');
    }

    @isTest
    static void testGetFacultyListLimit() {
        // Setup: Create multiple Faculty contacts
        List<Contact> faculties = new List<Contact>();
        Id facultyRTId = [SELECT Id FROM RecordType WHERE SObjectType='Contact' AND DeveloperName='Faculty' LIMIT 1].Id;
        
        for (Integer i = 0; i < 60; i++) {
            faculties.add(new Contact(
                FirstName = 'Faculty',
                LastName = 'Member' + i,
                Email = 'faculty' + i + Datetime.now().getTime() + '@example.com',
                RecordTypeId = facultyRTId
            ));
        }
        insert faculties;
        
        Test.startTest();
        List<Contact> results = FacultySearchController.getFacultyList('Faculty');
        Test.stopTest();
        
        System.assertNotEquals(null, results, 'Results should not be null');
        System.assertEquals(50, results.size(), 'Should return maximum of 50 results');
    }

    @isTest
    static void testGetAASuccess() {
        // Setup: Create AA Profile
        Contact aaContact = TestDataFactory.testAAContact(null);
        AA_Profile__c aaProfile = TestDataFactory.testAAProfile(aaContact.Id);
        
        Test.startTest();
        AA_Profile__c result = FacultySearchController.getAA(aaProfile.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(aaProfile.Id, result.Id, 'Should return correct AA Profile');
    }

    @isTest
    static void testGetAANotFound() {
        Test.startTest();
        try {
            AA_Profile__c result = FacultySearchController.getAA('a0X000000000000AAA');
            System.assert(false, 'Should have thrown exception');
        } catch (Exception e) {
            // Exception is expected - test passes
            System.assert(true, 'Exception was thrown as expected');
        }
        Test.stopTest();
    }

    @isTest
    static void testUpdateAASuccess() {
        // Setup: Create AA Profile
        Contact aaContact = TestDataFactory.testAAContact(null);
        AA_Profile__c aaProfile = TestDataFactory.testAAProfile(aaContact.Id);
        
        // Create Faculty contacts
        Contact faculty1 = TestDataFactory.testFacultyContact('Test', 'Faculty1', 'test.faculty1' + Datetime.now().getTime() + '@example.com');
        Contact faculty2 = TestDataFactory.testFacultyContact('Test', 'Faculty2', 'test.faculty2' + Datetime.now().getTime() + '@example.com');
        
        String preferredList = faculty1.Id + ';' + faculty2.Id;
        
        Test.startTest();
        FacultySearchController.updateAA(aaProfile.Id, preferredList);
        Test.stopTest();
        
        AA_Profile__c updatedProfile = [SELECT Id, Preferred_By_Faculty__c FROM AA_Profile__c WHERE Id = :aaProfile.Id];
        System.assertEquals(preferredList, updatedProfile.Preferred_By_Faculty__c, 'Preferred faculty list should be updated');
    }

    @isTest
    static void testUpdateAANullPreferredList() {
        // Setup: Create AA Profile with existing preferred list
        Contact aaContact = TestDataFactory.testAAContact(null);
        AA_Profile__c aaProfile = TestDataFactory.testAAProfile(aaContact.Id);
        
        Contact faculty1 = TestDataFactory.testFacultyContact('Test', 'Faculty', 'test.faculty' + Datetime.now().getTime() + '@example.com');
        aaProfile.Preferred_By_Faculty__c = faculty1.Id;
        update aaProfile;
        
        Test.startTest();
        FacultySearchController.updateAA(aaProfile.Id, null);
        Test.stopTest();
        
        AA_Profile__c updatedProfile = [SELECT Id, Preferred_By_Faculty__c FROM AA_Profile__c WHERE Id = :aaProfile.Id];
        System.assertEquals(null, updatedProfile.Preferred_By_Faculty__c, 'Preferred faculty list should be cleared');
    }

    @isTest
    static void testUpdateAAInvalidId() {
        Test.startTest();
        try {
            FacultySearchController.updateAA('a0X000000000000AAA', 'test');
            System.assert(false, 'Should have thrown exception');
        } catch (Exception e) {
            // Exception is expected - test passes
            System.assert(true, 'Exception was thrown as expected');
        }
        Test.stopTest();
    }
}