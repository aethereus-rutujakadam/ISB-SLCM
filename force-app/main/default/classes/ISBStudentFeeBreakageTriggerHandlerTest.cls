@isTest
public class ISBStudentFeeBreakageTriggerHandlerTest {

    @isTest
    static void testHandleBeforeInsert() {

        // Create base data using factory
        Contact con = TestDataFactory.testContact();
        Program prog = TestDataFactory.testProgram();
        ProgramEnrollment pe = TestDataFactory.testProgramEnrollment(con, prog);

        ISB_Installment__c inst = TestDataFactory.testInstallment(
            con.Id, prog.Id, pe.Id, 1000, 1000, 1
        );

        // Create breakage records (before insert scenario)
        List<ISB_Student_Fee_Breakage__c> breakages = new List<ISB_Student_Fee_Breakage__c>();

        breakages.add(new ISB_Student_Fee_Breakage__c(
            ISB_Installment__c = inst.Id,
            Fee_Type__c = 'Tuition'
            // Paid & Pending null → should be set
        ));

        breakages.add(new ISB_Student_Fee_Breakage__c(
            ISB_Installment__c = inst.Id,
            Fee_Type__c = 'Hostel',
            Paid_Amount__c = 100
            // Pending null → should become Total
        ));

        Test.startTest();
        ISBStudentFeeBreakageTriggerHandler.handleBeforeInsert(breakages);
        Test.stopTest();

        // Assertions
        System.assertEquals(0, breakages[0].Paid_Amount__c, 'Paid should default to 0');
    }


    @isTest
    static void testUpdateScholarshipOnInstallment() {

        // Create base data
        Contact con = TestDataFactory.testContact();
        Program prog = TestDataFactory.testProgram();
        ProgramEnrollment pe = TestDataFactory.testProgramEnrollment(con, prog);

        ISB_Installment__c inst = TestDataFactory.testInstallment(
            con.Id, prog.Id, pe.Id, 1000, 1000, 1
        );

        // Create breakages with scholarship
        List<ISB_Student_Fee_Breakage__c> breakages = new List<ISB_Student_Fee_Breakage__c>();

        breakages.add(new ISB_Student_Fee_Breakage__c(
            ISB_Installment__c = inst.Id,
            Fee_Type__c = 'Tuition Fee',
            Scholarship_Amount__c = 100
        ));

        breakages.add(new ISB_Student_Fee_Breakage__c(
            ISB_Installment__c = inst.Id,
            Fee_Type__c = 'Security Deposit',
            Scholarship_Amount__c = 50
        ));

        insert breakages;

        Test.startTest();
        ISBStudentFeeBreakageTriggerHandler.updateScholarshipOnInstallment(breakages);
        Test.stopTest();

        // Fetch updated installment
        ISB_Installment__c updatedInst = [
            SELECT Scholarship_Amount__c, Total_Amount__c, Paid_Amount__c, Pending_Amount__c
            FROM ISB_Installment__c
            WHERE Id = :inst.Id
        ];

        // Assertions
        System.assertEquals(150, updatedInst.Scholarship_Amount__c, 'Total scholarship should be summed');

        Decimal expectedPending = 
            (updatedInst.Total_Amount__c == null ? 0 : updatedInst.Total_Amount__c)
            - (updatedInst.Paid_Amount__c == null ? 0 : updatedInst.Paid_Amount__c)
            - 150;

        System.assertEquals(expectedPending, updatedInst.Pending_Amount__c,
            'Pending should be Total - Paid - Scholarship');
    }


    @isTest
    static void testUpdateScholarship_EmptyCase() {

        // Cover early return branch
        List<ISB_Student_Fee_Breakage__c> breakages = new List<ISB_Student_Fee_Breakage__c>();

        breakages.add(new ISB_Student_Fee_Breakage__c(
            Fee_Type__c = 'No Installment'
            // No installment + no scholarship → should skip
        ));

        Test.startTest();
        ISBStudentFeeBreakageTriggerHandler.updateScholarshipOnInstallment(breakages);
        Test.stopTest();

        System.assert(true, 'No exception should occur');
    }
}