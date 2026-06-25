@IsTest
public class ISBInstallmentMissedBatchTest {

    @TestSetup
    static void setupData() {
        // 1. Setup foundation data using Factory
        Program prog = TestDataFactory.testProgram();
        Contact con = TestDataFactory.testContact();
        
        // 2. Create Program Enrollment (Linking to the Program to fix ProgramId error)
        ProgramEnrollment pe = new ProgramEnrollment(
            ContactId = con.Id,
            ProgramId = prog.Id, // <--- This fixes the REQUIRED_FIELD_MISSING error
            Status = 'Registered' 
        );
        insert pe;

        // 3. Create Installments (Linking to Program to satisfy Installment requirements)
        ISB_Installment__c inst1 = new ISB_Installment__c(
            Contact__c = con.Id,
            Program__c = prog.Id, // Linking to Program
            Program_Enrollment__c = pe.Id,
            Installment_Number__c = '1',
            Pending_Amount__c = 50000,
            Due_Date__c = System.today().addDays(-5),
            Late_Fee_Added__c = false
        );

        ISB_Installment__c inst2 = new ISB_Installment__c(
            Contact__c = con.Id,
            Program__c = prog.Id, // Linking to Program
            Program_Enrollment__c = pe.Id,
            Installment_Number__c = '2',
            Pending_Amount__c = 20000,
            Due_Date__c = System.today().addDays(-10),
            Late_Fee_Added__c = false
        );

        insert new List<ISB_Installment__c>{ inst1, inst2 };
    }

    @IsTest
    static void testBatchExecution() {
        Test.startTest();
        Database.executeBatch(new ISBInstallmentMissedBatch(), 50);
        Test.stopTest();

        // Verify Student Fee Breakage records were created
        List<ISB_Student_Fee_Breakage__c> brks = [SELECT Id FROM ISB_Student_Fee_Breakage__c];
        System.assertEquals(2, brks.size(), 'Two breakage records should have been created for the late fees.');

        // Verify Installments were flagged
        for (ISB_Installment__c inst : [SELECT Late_Fee_Added__c FROM ISB_Installment__c]) {
            System.assertEquals(true, inst.Late_Fee_Added__c, 'Late fee flag should be true.');
        }

        // Verify Program Enrollment status change
        ProgramEnrollment pe = [SELECT Status, Sub_Status__c FROM ProgramEnrollment LIMIT 1];
        System.assertEquals('On Hold', pe.Status, 'Status should be updated to On Hold.');
        System.assertEquals('Fee payment', pe.Sub_Status__c, 'Sub-status should be set to Fee payment.');
    }

    @IsTest
    static void testScheduler() {
        Test.startTest();
        String jobId = System.schedule(
            'Missed Installment Batch Test',
            '0 0 0 * * ?',
            new ISBInstallmentMissedBatch()
        );
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Job should be successfully scheduled.');
    }
}