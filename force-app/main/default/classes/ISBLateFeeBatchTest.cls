@isTest
public class ISBLateFeeBatchTest {
    
    @TestSetup
    static void setupTestData() {
        // Create Test Data using Factory
        Contact student = TestDataFactory.testContact();
        Program prog = TestDataFactory.testProgram();
        ProgramEnrollment pe = TestDataFactory.testProgramEnrollment(student, prog, 'PGID001');
        
        // Create Installment #1 - Should charge flat 10000 late fee
        ISB_Installment__c inst1 = TestDataFactory.testInstallment(
            student.Id, 
            prog.Id, 
            pe.Id, 
            100000,  // Total Amount
            100000,  // Pending Amount
            1        // Installment Number
        );
        
        // Create Installment #2 - Should charge 1.5% of pending
        ISB_Installment__c inst2 = new ISB_Installment__c(
            Contact__c = student.Id,
            Program__c = prog.Id,
            Program_Enrollment__c = pe.Id,
            Installment_Number__c = '2',
            Pending_Amount__c = 80000,
            Due_Date__c = System.today().addDays(-5), // Overdue by 5 days
            Late_Fee_Added__c = false
        );
        insert inst2;
        
        // Create Fee for Installment #1 - Overdue (Regular Due Date)
        ISB_Fee__c fee1 = new ISB_Fee__c(
            ISB_Installment__c = inst1.Id,
            Contact__c = student.Id,
            Customer__c = student.Id,
            Program_Enrollment__c = pe.Id,
            Fee_Type__c = 'Installment 1',
            Total_amount__c = 100000,
            Pending_Amount__c = 100000,
            Due_Date__c = System.today().addDays(-10), // Overdue by 10 days
            Extended_Due_Date__c = null,
            Late_Fee_Added__c = false,
            Fee_Amount__c = 100000
        );
        
        // Create Fee for Installment #2 - Overdue (Extended Due Date)
        ISB_Fee__c fee2 = new ISB_Fee__c(
            ISB_Installment__c = inst2.Id,
            Contact__c = student.Id,
            Customer__c = student.Id,
            Program_Enrollment__c = pe.Id,
            Fee_Type__c = 'Installment 2',
            Total_amount__c = 80000,
            Pending_Amount__c = 80000,
            Due_Date__c = System.today().addDays(-20),
            Extended_Due_Date__c = System.today().addDays(-3), // Extended but still overdue
            Late_Fee_Added__c = false,
            Fee_Amount__c = 80000

        );
        
        // Create Fee that should NOT trigger late fee (Not overdue)
        ISB_Fee__c fee3 = new ISB_Fee__c(
            ISB_Installment__c = inst2.Id,
            Contact__c = student.Id,
            Customer__c = student.Id,
            Program_Enrollment__c = pe.Id,
            Fee_Type__c = 'Installment 3',
            Total_amount__c = 50000,
            Pending_Amount__c = 50000,
            Due_Date__c = System.today().addDays(5), // Future due date
            Extended_Due_Date__c = null,
            Late_Fee_Added__c = false,
            Fee_Amount__c = 50000
        );
        
        insert new List<ISB_Fee__c>{ fee1, fee2, fee3 };
    }
    
    @isTest
    static void testBatchExecution_Installment1() {
        // Query the Installment #1 fee
        ISB_Fee__c fee = [
            SELECT Id, Pending_Amount__c, Total_amount__c, Late_Fee_Added__c,
                   ISB_Installment__c, ISB_Installment__r.Installment_Number__c
            FROM ISB_Fee__c 
            WHERE Fee_Type__c = 'Installment 1'
            LIMIT 1
        ];
        
        Decimal originalPending = fee.Pending_Amount__c;
        Decimal originalTotal = fee.Total_amount__c;
        Decimal expectedLateFee = 10000; // Flat fee for Installment #1
        
        Test.startTest();
        
        // Execute Batch
        ISBLateFeeBatch batch = new ISBLateFeeBatch();
        Database.executeBatch(batch, 200);
        
        Test.stopTest();
        
        // Verify Late Fee Breakage Record Created
        List<ISB_Student_Fee_Breakage__c> breakages = [
            SELECT Id, Fee_Type__c, Amount__c, Pending_Amount__c, 
                   Paid_Amount__c, ISB_Installment__c
            FROM ISB_Student_Fee_Breakage__c
            WHERE ISB_Installment__c = :fee.ISB_Installment__c
            AND Fee_Type__c = 'Late Fee'
        ];
        
        System.assertEquals(1, breakages.size(), 
            'Should create 1 late fee breakage for Installment #1');
        System.assertEquals(expectedLateFee, breakages[0].Amount__c, 
            'Late fee should be 10000 for Installment #1');
        System.assertEquals(expectedLateFee, breakages[0].Pending_Amount__c, 
            'Breakage pending amount should equal late fee');
        System.assertEquals(0, breakages[0].Paid_Amount__c, 
            'Breakage paid amount should be 0');
        
        // Verify Fee Record Updated
        ISB_Fee__c updatedFee = [
            SELECT Id, Late_Fee_Added__c, Pending_Amount__c, Total_amount__c
            FROM ISB_Fee__c
            WHERE Id = :fee.Id
        ];
                
        // Verify Installment Record Updated
        ISB_Installment__c updatedInst = [
            SELECT Id, Late_Fee_Added__c, Pending_Amount__c
            FROM ISB_Installment__c
            WHERE Id = :fee.ISB_Installment__c
        ];
        
        System.assertEquals(true, updatedInst.Late_Fee_Added__c, 
            'Installment Late_Fee_Added__c should be true');
        // Installment pending should include late fee
        System.assert(updatedInst.Pending_Amount__c >= expectedLateFee, 
            'Installment pending should include late fee');
    }
    
    @isTest
    static void testBatchExecution_OtherInstallments() {
        // Query the Installment #2 fee
        ISB_Fee__c fee = [
            SELECT Id, Pending_Amount__c, Total_amount__c, Late_Fee_Added__c,
                   ISB_Installment__c, ISB_Installment__r.Installment_Number__c
            FROM ISB_Fee__c 
            WHERE Fee_Type__c = 'Installment 2'
            LIMIT 1
        ];
        
        Decimal originalPending = fee.Pending_Amount__c;
        Decimal originalTotal = fee.Total_amount__c;
        Decimal expectedLateFee = (originalPending * 1.5) / 100; // 1.5% of pending
        
        Test.startTest();
        
        // Execute Batch
        ISBLateFeeBatch batch = new ISBLateFeeBatch();
        Database.executeBatch(batch, 200);
        
        Test.stopTest();
        
        // Verify Late Fee Breakage Record Created
        List<ISB_Student_Fee_Breakage__c> breakages = [
            SELECT Id, Fee_Type__c, Amount__c, Pending_Amount__c, ISB_Installment__c
            FROM ISB_Student_Fee_Breakage__c
            WHERE ISB_Installment__c = :fee.ISB_Installment__c
            AND Fee_Type__c = 'Late Fee'
        ];
        
        System.assertEquals(1, breakages.size(), 
            'Should create 1 late fee breakage for Installment #2');
        
        // Verify Fee Record Updated
        ISB_Fee__c updatedFee = [
            SELECT Id, Late_Fee_Added__c, Pending_Amount__c, Total_amount__c
            FROM ISB_Fee__c
            WHERE Id = :fee.Id
        ];
        
        // Verify Installment Record Updated
        ISB_Installment__c updatedInst = [
            SELECT Id, Late_Fee_Added__c, Pending_Amount__c
            FROM ISB_Installment__c
            WHERE Id = :fee.ISB_Installment__c
        ];
        
        System.assertEquals(true, updatedInst.Late_Fee_Added__c, 
            'Installment Late_Fee_Added__c should be true');
    }
    
    @isTest
    static void testBatchExecution_NoOverdueFees() {
        // Delete overdue fees, keep only future-dated fee
        delete [SELECT Id FROM ISB_Fee__c WHERE Fee_Type__c IN ('Installment 1', 'Installment 2')];
        
        Test.startTest();
        
        // Execute Batch
        ISBLateFeeBatch batch = new ISBLateFeeBatch();
        Database.executeBatch(batch, 200);
        
        Test.stopTest();
        
        // Verify no late fee breakages created
        List<ISB_Student_Fee_Breakage__c> breakages = [
            SELECT Id FROM ISB_Student_Fee_Breakage__c
            WHERE Fee_Type__c = 'Late Fee'
        ];
        
        System.assertEquals(0, breakages.size(), 
            'Should not create late fee breakages for non-overdue fees');
        
        // Verify batch completed successfully
        List<AsyncApexJob> jobs = [
            SELECT Id, Status, NumberOfErrors
            FROM AsyncApexJob
            WHERE ApexClass.Name = 'ISBLateFeeBatch'
            AND JobType = 'BatchApex'
        ];
        
        System.assertEquals(1, jobs.size(), 'Batch job should be created');
        System.assertEquals('Completed', jobs[0].Status, 
            'Batch should complete successfully even with no records');
        System.assertEquals(0, jobs[0].NumberOfErrors, 'No errors should occur');
    }
    
    @isTest
    static void testBatchExecution_ExtendedDueDateLogic() {
        // Query the fee with extended due date
        ISB_Fee__c fee = [
            SELECT Id, Due_Date__c, Extended_Due_Date__c, Pending_Amount__c
            FROM ISB_Fee__c 
            WHERE Fee_Type__c = 'Installment 2'
            LIMIT 1
        ];
        
        Test.startTest();
        
        // Execute Batch
        ISBLateFeeBatch batch = new ISBLateFeeBatch();
        Database.executeBatch(batch, 200);
        
        Test.stopTest();
        
        // Verify late fee applied based on extended due date
        ISB_Fee__c updatedFee = [
            SELECT Id, Late_Fee_Added__c
            FROM ISB_Fee__c
            WHERE Id = :fee.Id
        ];
        
    }
    
    @isTest
    static void testBatchExecution_MultipleFeesPerInstallment() {
        // Get installment #2
        ISB_Installment__c inst = [
            SELECT Id, Pending_Amount__c, Total_Amount_calc__c
            FROM ISB_Installment__c
            WHERE Installment_Number__c = '2'
            LIMIT 1
        ];
        
        Contact student = [SELECT Id FROM Contact LIMIT 1];
        ProgramEnrollment pe = [SELECT Id FROM ProgramEnrollment LIMIT 1];
        
        Decimal originalInstPending = inst.Pending_Amount__c;
        
        // Create additional overdue fee for same installment
        ISB_Fee__c additionalFee = new ISB_Fee__c(
            ISB_Installment__c = inst.Id,
            Contact__c = student.Id,
            Customer__c = student.Id,
            Program_Enrollment__c = pe.Id,
            Fee_Type__c = 'Installment 2',
            Total_amount__c = 20000,
            Pending_Amount__c = 20000,
            Due_Date__c = System.today().addDays(-5),
            Extended_Due_Date__c = null,
            Late_Fee_Added__c = false,
            Fee_Amount__c = 20000

        );
        insert additionalFee;
        
        Decimal expectedLateFee1 = (80000 * 1.5) / 100; // Original fee
        Decimal expectedLateFee2 = (20000 * 1.5) / 100; // Additional fee
        Decimal totalExpectedLateFee = expectedLateFee1 + expectedLateFee2;
        
        Test.startTest();
        
        // Execute Batch
        ISBLateFeeBatch batch = new ISBLateFeeBatch();
        Database.executeBatch(batch, 200);
        
        Test.stopTest();
        
        // Verify 2 late fee breakages created for same installment
        List<ISB_Student_Fee_Breakage__c> breakages = [
            SELECT Id, Amount__c
            FROM ISB_Student_Fee_Breakage__c
            WHERE ISB_Installment__c = :inst.Id
            AND Fee_Type__c = 'Late Fee'
        ];
        
        System.assertEquals(2, breakages.size(), 
            'Should create 2 late fee breakages for 2 overdue fees');
        
        // Verify installment pending increased by total of both late fees
        ISB_Installment__c updatedInst = [
            SELECT Id, Pending_Amount__c
            FROM ISB_Installment__c
            WHERE Id = :inst.Id
        ];
        
        System.assertEquals(originalInstPending + totalExpectedLateFee, 
            updatedInst.Pending_Amount__c, 
            'Installment should accumulate both late fees');
    }
    
    @isTest
    static void testScheduledExecution() {
        Test.startTest();
        
        // Schedule the batch
        String cronExp = '0 0 2 * * ?'; // 2 AM daily
        String jobId = System.schedule(
            'ISB Late Fee Batch Test',
            cronExp,
            new ISBLateFeeBatch()
        );
        
        Test.stopTest();
        
        // Verify scheduled job created
        CronTrigger ct = [
            SELECT Id, CronExpression, State
            FROM CronTrigger 
            WHERE Id = :jobId
        ];
        
        System.assertNotEquals(null, ct, 'Scheduled job should be created');
        System.assertEquals(cronExp, ct.CronExpression, 
            'Cron expression should match');
    }
    
    @isTest
    static void testBatchExecution_VerifyAsyncJob() {
        Test.startTest();
        
        // Execute Batch
        ISBLateFeeBatch batch = new ISBLateFeeBatch();
        Database.executeBatch(batch, 200);
        
        Test.stopTest();
        
        // Verify batch job completed successfully
        List<AsyncApexJob> jobs = [
            SELECT Id, Status, NumberOfErrors, TotalJobItems, JobItemsProcessed
            FROM AsyncApexJob
            WHERE ApexClass.Name = 'ISBLateFeeBatch'
            AND JobType = 'BatchApex'
        ];
        
        System.assertEquals(1, jobs.size(), 'Batch job should be created');
        System.assertEquals('Completed', jobs[0].Status, 
            'Batch should complete successfully');
        System.assertEquals(0, jobs[0].NumberOfErrors, 
            'No errors should occur');
        System.assert(jobs[0].JobItemsProcessed > 0, 
            'Should process at least one batch');
    }
}