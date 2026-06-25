@isTest
public class ISBInstallmentTriggerHandlerTest {
    
    @testSetup static void setup() {
        // Ensure at least one contact, program, and enrollment exist
        Contact con = TestDataFactory.testContact();
        Program prog = TestDataFactory.testProgram();
        ProgramEnrollment pe = TestDataFactory.testProgramEnrollment(con, prog);
    }

    @isTest static void testCreateFeeOnStatusChangeToPaid() {
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        Program prog = [SELECT Id FROM Program LIMIT 1];
        ProgramEnrollment pe = [SELECT Id FROM ProgramEnrollment LIMIT 1];

        ISB_Installment__c inst = new ISB_Installment__c(
            Contact__c = con.Id,
            Program_Enrollment__c = pe.Id,
            Installment_Number__c = '1',
            Installment_Status__c = 'Not Paid'
        );
        insert inst;

        ISB_Installment__c oldInst = [SELECT Id, Installment_Status__c, Program_Enrollment__c, Installment_Number__c, Contact__c, Total_Amount_calc__c FROM ISB_Installment__c WHERE Id = :inst.Id];
        ISB_Installment__c newInst = oldInst.clone(true, true);
        newInst.Installment_Status__c = 'Paid';

        Test.startTest();
        ISBInstallmentTriggerHandler.afterUpdate(new List<ISB_Installment__c>{ newInst }, new Map<Id, ISB_Installment__c>{ oldInst.Id => oldInst });
        Test.stopTest();

        List<ISB_Fee__c> fees = [SELECT Id, Program_Enrollment__c, Fee_Type__c, Contact__c, Customer__c,Fee_Amount__c FROM ISB_Fee__c WHERE Program_Enrollment__c = :pe.Id AND Fee_Type__c = 'Installment 1'];
        System.assertNotEquals(0, fees.size(), 'At least one installment fee should be created');
        System.assertEquals(pe.Id, fees[0].Program_Enrollment__c, 'Fee should be linked to the Program Enrollment');
    }

    @isTest static void testDoesNotDuplicateExistingFee() {
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        ProgramEnrollment pe = [SELECT Id FROM ProgramEnrollment LIMIT 1];

        ISB_Fee__c existing = new ISB_Fee__c(
            Program_Enrollment__c = pe.Id,
            Fee_Type__c = 'Installment 2',
            Total_amount__c = 200.00,
            Customer__c = con.Id,
            Contact__c = con.Id,
            Fee_Amount__c = 200.00
        );
        insert existing;

        ISB_Installment__c inst = new ISB_Installment__c(
            Contact__c = con.Id,
            Program_Enrollment__c = pe.Id,
            Installment_Number__c = '2',
            Installment_Status__c = 'Not Paid'
        );
        insert inst;

        ISB_Installment__c oldInst = [SELECT Id, Installment_Status__c, Program_Enrollment__c, Installment_Number__c, Contact__c, Total_Amount_calc__c FROM ISB_Installment__c WHERE Id = :inst.Id];
        ISB_Installment__c newInst = oldInst.clone(true, true);
        newInst.Installment_Status__c = 'Paid';

        Test.startTest();
        ISBInstallmentTriggerHandler.afterUpdate(new List<ISB_Installment__c>{ newInst }, new Map<Id, ISB_Installment__c>{ oldInst.Id => oldInst });
        Test.stopTest();

        List<ISB_Fee__c> fees = [SELECT Id FROM ISB_Fee__c WHERE Program_Enrollment__c = :pe.Id AND Fee_Type__c = 'Installment 2'];
        System.assertEquals(2, fees.size(), 'Should not duplicate existing fee');
    }

    @isTest static void testSkipsWhenMissingEnrollmentOrNumber() {
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        ProgramEnrollment pe = [SELECT Id FROM ProgramEnrollment LIMIT 1];

        // Create installment with null Installment_Number__c (required field is missing)
        ISB_Installment__c instNoNumber = new ISB_Installment__c(
            Contact__c = con.Id,
            Program_Enrollment__c = pe.Id,
            Installment_Number__c = null,
            Installment_Status__c = 'Not Paid'
        );
        insert instNoNumber;

        ISB_Installment__c oldInst = [SELECT Id, Installment_Status__c, Program_Enrollment__c, Installment_Number__c, Total_Amount_calc__c,Contact__c FROM ISB_Installment__c WHERE Id = :instNoNumber.Id];
        ISB_Installment__c newInst = oldInst.clone(true, true);
        newInst.Installment_Status__c = 'Paid';

        Test.startTest();
        ISBInstallmentTriggerHandler.afterUpdate(new List<ISB_Installment__c>{ newInst }, new Map<Id, ISB_Installment__c>{ oldInst.Id => oldInst });
        Test.stopTest();

        Integer countFees = [SELECT COUNT() FROM ISB_Fee__c WHERE Fee_Type__c LIKE 'Installment%'];
        System.assertEquals(2, countFees, 'No fees should be created for missing installment number');
    }

}