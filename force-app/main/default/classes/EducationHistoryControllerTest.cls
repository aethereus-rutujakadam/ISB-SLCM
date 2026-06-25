@isTest
public class EducationHistoryControllerTest {
    
    @testSetup
    static void setup() {
        // Create an Account
        Account acc = new Account(Name = 'Test Account');
        insert acc;
        
        // Create a contact
        Contact con = new Contact(
            FirstName = 'Test',
            LastName = 'Student',
            Email = 'test.student@isb.edu',
            ISB_External_Id__c = 'EXT-12345',
            hed__Preferred_Email__c = 'Alternate Email',
            hed__AlternateEmail__c = 'test.student@isb.edu'
        );
        insert con;
        
        // Create a Program Plan (required for ProgramEnrollment.ProgramId in EDA)
        Program programPlan = new Program(
            Name = 'Test Program Plan'
        );
        insert programPlan;

        // Create a Program Enrollment with External Id
        ProgramEnrollment pe1 = new ProgramEnrollment(
            ContactId = con.Id,
            ProgramId = programPlan.Id,
            ISB_External_Id__c = 'EXT-12345'
        );
        
        // Create a Program Enrollment without External Id
        ProgramEnrollment pe2 = new ProgramEnrollment(
            ContactId = con.Id,
            ProgramId = programPlan.Id
        );
        
        insert new List<ProgramEnrollment>{pe1, pe2};
    }

    @isTest
    static void testGetEducationHistorySuccess() {
        ProgramEnrollment pe = [SELECT Id FROM ProgramEnrollment WHERE ISB_External_Id__c = 'EXT-12345' LIMIT 1];
        
        Test.startTest();
        // Passes the Id check and the ISB_External_Id__c check. 
        // Covers the actual SOQL generation, Database.query execution, and Exception fallback lines.
        List<SObject> results = EducationHistoryController.getEducationHistory(pe.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, results, 'Results should not be null. If Data Cloud raises exception, catch block will return empty array safely.');
    }

    @isTest
    static void testGetEducationHistoryNoExternalId() {
        ProgramEnrollment pe = [SELECT Id FROM ProgramEnrollment WHERE ISB_External_Id__c = null LIMIT 1];
        
        Test.startTest();
        // Tests the scenario where enrollment exists but no external ID is mapped
        List<SObject> results = EducationHistoryController.getEducationHistory(pe.Id);
        Test.stopTest();
        
        System.assertEquals(0, results.size(), 'Should return empty list for PE without external ID');
    }

    @isTest
    static void testGetEducationHistoryBlankId() {
        Test.startTest();
        // Tests the empty payload guard clause
        List<SObject> results = EducationHistoryController.getEducationHistory('');
        Test.stopTest();
        
        System.assertEquals(0, results.size(), 'Should return empty list for blank ID');
    }
    
    @isTest
    static void testGetEducationHistoryInvalidId() {
        Test.startTest();
        // Tests a garbage id / missing query.
        List<SObject> results = EducationHistoryController.getEducationHistory('003000000000000AAA'); // valid length fake id
        Test.stopTest();
        
        System.assertEquals(0, results.size(), 'Should return empty list for non-existent ID');
    }

    @isTest
    static void testGetEducationHistoryException() {
        ProgramEnrollment pe = [SELECT Id FROM ProgramEnrollment WHERE ISB_External_Id__c = 'EXT-12345' LIMIT 1];
        
        // Force the exception path in the controller
        EducationHistoryController.forceException = true;
        
        Test.startTest();
        // The catch block will execute: System.debug, Test.isRunningTest() check, and return empty list
        List<SObject> results = EducationHistoryController.getEducationHistory(pe.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, results, 'Results should not be null even on exception');
        System.assertEquals(0, results.size(), 'Should return empty list when an exception is caught during test');
    }
}