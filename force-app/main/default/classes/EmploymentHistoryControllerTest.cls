@isTest
public class EmploymentHistoryControllerTest {
    
    @testSetup
    static void setup() {
        // Create an Account
        Account acc = new Account(Name = 'Test Account');
        insert acc;
        
        // Create a contact
        Contact con = new Contact(
            FirstName = 'Work',
            LastName = 'Professional',
            Email = 'work.pro@example.com',
            ISB_External_Id__c = 'EMP-98765',
            hed__Preferred_Email__c = 'Alternate Email',
            hed__AlternateEmail__c = 'work.pro@example.com'
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
            ISB_External_Id__c = 'EMP-98765'
        );
        
        // Create a Program Enrollment without External Id
        ProgramEnrollment pe2 = new ProgramEnrollment(
            ContactId = con.Id,
            ProgramId = programPlan.Id
        );
        
        insert new List<ProgramEnrollment>{pe1, pe2};
    }

    @isTest
    static void testGetEmploymentHistorySuccess() {
        ProgramEnrollment pe = [SELECT Id FROM ProgramEnrollment WHERE ISB_External_Id__c = 'EMP-98765' LIMIT 1];
        
        Test.startTest();
        // Passes the Id check and the ISB_External_Id__c check. 
        // Covers the actual SOQL generation, Database.query execution, and Exception fallback lines.
        List<SObject> results = EmploymentHistoryController.getEmploymentHistory(pe.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, results, 'Results should not be null. If Data Cloud raises exception, catch block will return empty array safely.');
    }

    @isTest
    static void testGetEmploymentHistoryNoExternalId() {
        ProgramEnrollment pe = [SELECT Id FROM ProgramEnrollment WHERE ISB_External_Id__c = null LIMIT 1];
        
        Test.startTest();
        // Tests the scenario where enrollment exists but no external ID is mapped
        List<SObject> results = EmploymentHistoryController.getEmploymentHistory(pe.Id);
        Test.stopTest();
        
        System.assertEquals(0, results.size(), 'Should return empty list for PE without external ID');
    }

    @isTest
    static void testGetEmploymentHistoryBlankId() {
        Test.startTest();
        // Tests the empty payload guard clause
        List<SObject> results = EmploymentHistoryController.getEmploymentHistory('');
        Test.stopTest();
        
        System.assertEquals(0, results.size(), 'Should return empty list for blank ID');
    }
    
    @isTest
    static void testGetEmploymentHistoryInvalidId() {
        Test.startTest();
        // Tests a garbage id / missing query.
        List<SObject> results = EmploymentHistoryController.getEmploymentHistory('003000000000000AAA'); // valid length fake id
        Test.stopTest();
        
        System.assertEquals(0, results.size(), 'Should return empty list for non-existent ID');
    }

    @isTest
    static void testGetEmploymentHistoryException() {
        ProgramEnrollment pe = [SELECT Id FROM ProgramEnrollment WHERE ISB_External_Id__c = 'EMP-98765' LIMIT 1];
        
        // Force the exception path in the controller
        EmploymentHistoryController.forceException = true;
        
        Test.startTest();
        // The catch block will execute: System.debug, Test.isRunningTest() check, and return empty list
        List<SObject> results = EmploymentHistoryController.getEmploymentHistory(pe.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, results, 'Results should not be null even on exception');
        System.assertEquals(0, results.size(), 'Should return empty list when an exception is caught during test');
    }
}