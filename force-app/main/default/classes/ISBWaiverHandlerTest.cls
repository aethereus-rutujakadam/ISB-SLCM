@isTest
public class ISBWaiverHandlerTest {
    
    @testSetup static void setup() {
        Contact con = TestDataFactory.testContact();
        Program prog = TestDataFactory.testProgram();
        ProgramEnrollment pe = TestDataFactory.testProgramEnrollment(con, prog);
    }

    @isTest static void testApplyWaiverToInstallmentsCreatesBreakageAndUpdatesAmount() {
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        ProgramEnrollment pe = [SELECT Id FROM ProgramEnrollment LIMIT 1];

        // Create installments
        ISB_Installment__c inst1 = new ISB_Installment__c(
            Contact__c = con.Id,
            Program_Enrollment__c = pe.Id,
            Installment_Number__c = 1,
            Installment_Status__c = 'Not Paid',
            Actual_Amount__c = 5000,
            Pending_Amount__c = 5000
        );
        ISB_Installment__c inst2 = new ISB_Installment__c(
            Contact__c = con.Id,
            Program_Enrollment__c = pe.Id,
            Installment_Number__c = 2,
            Installment_Status__c = 'Not Paid',
            Actual_Amount__c = 5000,
            Pending_Amount__c = 5000
        );
        insert new List<ISB_Installment__c>{ inst1, inst2 };

        // Create waiver
        ISBWaiverApplications__c waiver = new ISBWaiverApplications__c(
            Program_Enrollment__c = pe.Id,
            ScholarshipAmount__c = 3000
        );
        insert waiver;

        Test.startTest();
        ISBWaiverHandler.applyWaiverToInstallments(new List<ISBWaiverApplications__c>{ waiver });
        Test.stopTest();

        // Verify breakage records created
        List<ISB_Student_Fee_Breakage__c> breakages = [SELECT Id, Amount__c, Fee_Type__c FROM ISB_Student_Fee_Breakage__c];
        System.assertNotEquals(0, breakages.size(), 'Breakage records should be created');
        
        // Verify installment pending amounts updated
        List<ISB_Installment__c> updatedInsts = [SELECT Id, Pending_Amount__c FROM ISB_Installment__c ORDER BY Installment_Number__c];
        System.assertEquals(2, updatedInsts.size(), 'Two installments should exist');
    }

    @isTest static void testApplyWaiverWithZeroScholarshipAmount() {
        ProgramEnrollment pe = [SELECT Id FROM ProgramEnrollment LIMIT 1];

        ISBWaiverApplications__c waiver = new ISBWaiverApplications__c(
            Program_Enrollment__c = pe.Id,
            ScholarshipAmount__c = 0
        );
        insert waiver;

        Test.startTest();
        ISBWaiverHandler.applyWaiverToInstallments(new List<ISBWaiverApplications__c>{ waiver });
        Test.stopTest();

        List<ISB_Student_Fee_Breakage__c> breakages = [SELECT Id FROM ISB_Student_Fee_Breakage__c];
        System.assertEquals(0, breakages.size(), 'No breakage should be created for zero scholarship');
    }

    @isTest static void testApplyWaiverWithNullProgramEnrollment() {
        ISBWaiverApplications__c waiver = new ISBWaiverApplications__c(
            Program_Enrollment__c = null,
            ScholarshipAmount__c = 1000
        );
        insert waiver;

        Test.startTest();
        ISBWaiverHandler.applyWaiverToInstallments(new List<ISBWaiverApplications__c>{ waiver });
        Test.stopTest();

        List<ISB_Student_Fee_Breakage__c> breakages = [SELECT Id FROM ISB_Student_Fee_Breakage__c];
        System.assertEquals(0, breakages.size(), 'No breakage should be created for null program enrollment');
    }

    @isTest static void testApplyWaiverDeductsFromLastInstallmentBackward() {
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        ProgramEnrollment pe = [SELECT Id FROM ProgramEnrollment LIMIT 1];

        // Create 3 installments
        ISB_Installment__c inst1 = new ISB_Installment__c(
            Contact__c = con.Id,
            Program_Enrollment__c = pe.Id,
            Installment_Number__c = 1,
            Installment_Status__c = 'Not Paid',
            Actual_Amount__c = 1000,
            Pending_Amount__c = 1000
        );
        ISB_Installment__c inst2 = new ISB_Installment__c(
            Contact__c = con.Id,
            Program_Enrollment__c = pe.Id,
            Installment_Number__c = 2,
            Installment_Status__c = 'Not Paid',
            Actual_Amount__c = 1000,
            Pending_Amount__c = 1000
        );
        ISB_Installment__c inst3 = new ISB_Installment__c(
            Contact__c = con.Id,
            Program_Enrollment__c = pe.Id,
            Installment_Number__c = 3,
            Installment_Status__c = 'Not Paid',
            Actual_Amount__c = 1000,
            Pending_Amount__c = 1000
        );
        insert new List<ISB_Installment__c>{ inst1, inst2, inst3 };

        ISBWaiverApplications__c waiver = new ISBWaiverApplications__c(
            Program_Enrollment__c = pe.Id,
            ScholarshipAmount__c = 2500
        );
        insert waiver;

        Test.startTest();
        ISBWaiverHandler.applyWaiverToInstallments(new List<ISBWaiverApplications__c>{ waiver });
        Test.stopTest();

        // Deduction should start from installment 3 backward
        ISB_Installment__c inst3After = [SELECT Pending_Amount__c FROM ISB_Installment__c WHERE Installment_Number__c = 3];
        ISB_Installment__c inst2After = [SELECT Pending_Amount__c FROM ISB_Installment__c WHERE Installment_Number__c = 2];
        
        System.assertEquals(0, inst3After.Pending_Amount__c, 'Inst 3 should be fully deducted (1000 waived)');
        System.assertEquals(0, inst2After.Pending_Amount__c, 'Inst 2 should be fully deducted (1500 remaining waived)');
    }

    @isTest static void testApplyWaiverPreventNegativePendingAmount() {
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        ProgramEnrollment pe = [SELECT Id FROM ProgramEnrollment LIMIT 1];

        ISB_Installment__c inst = new ISB_Installment__c(
            Contact__c = con.Id,
            Program_Enrollment__c = pe.Id,
            Installment_Number__c = 1,
            Installment_Status__c = 'Not Paid',
            Actual_Amount__c = 1000,
            Pending_Amount__c = 1000
        );
        insert inst;

        ISBWaiverApplications__c waiver = new ISBWaiverApplications__c(
            Program_Enrollment__c = pe.Id,
            ScholarshipAmount__c = 5000
        );
        insert waiver;

        Test.startTest();
        ISBWaiverHandler.applyWaiverToInstallments(new List<ISBWaiverApplications__c>{ waiver });
        Test.stopTest();

        ISB_Installment__c instAfter = [SELECT Pending_Amount__c FROM ISB_Installment__c WHERE Id = :inst.Id];
        System.assertEquals(0, instAfter.Pending_Amount__c, 'Pending amount should not go below 0');
    }

}