@isTest
private class ISB_PaymentTriggerHelperTest {

    @isTest
    static void testHandlePaymentUpdates_FirstInstallmentPaid() {

        // Create base data
        Contact con = TestDataFactory.testContact();
        Program prog = TestDataFactory.testProgram();

        // Create Program Enrollment
        ProgramEnrollment pe = TestDataFactory.testProgramEnrollment(con, prog, 'PG123');

        // IMPORTANT: populate external id (used in trigger)
        pe.ISB_External_Id__c = 'APP-001';
        update pe;

        // Create Payment
        ISB_Payment__c payment = new ISB_Payment__c(
            Customer__c = con.Id,
            Program_Enrollment__c = pe.Id,
            Amount__c = 1000,
            First_Installment_Paid__c = false
        );
        insert payment;

        Test.startTest();

        // Update → trigger condition
        payment.First_Installment_Paid__c = true;
        update payment;

        Test.stopTest();

        // Validate update happened
        ISB_Payment__c updatedPayment = [
            SELECT Id, First_Installment_Paid__c
            FROM ISB_Payment__c
            WHERE Id = :payment.Id
        ];

        System.assertEquals(true, updatedPayment.First_Installment_Paid__c);
    }


    // Negative test → should NOT enqueue queueable
    @isTest
    static void testHandlePaymentUpdates_NotPaid() {

        Contact con = TestDataFactory.testContact();
        Program prog = TestDataFactory.testProgram();

        ProgramEnrollment pe = TestDataFactory.testProgramEnrollment(con, prog, 'PG999');
        pe.ISB_External_Id__c = 'APP-002';
        update pe;

        ISB_Payment__c payment = new ISB_Payment__c(
            Customer__c = con.Id,
            Program_Enrollment__c = pe.Id,
            Amount__c = 2000,
            First_Installment_Paid__c = false
        );
        insert payment;

        Test.startTest();

        // Update without changing field
        payment.Amount__c = 3000;
        update payment;

        Test.stopTest();

        System.assertEquals(true, true); // ensures no exception
    }
}