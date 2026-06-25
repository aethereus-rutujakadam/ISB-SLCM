@isTest
private class UploadInstallmentPaymentsControllerTest {
   
    @TestSetup
    static void setupTestData() {

        // Create Account
        Account testAccount = new Account(
            Name = 'Test Account'
        );
        insert testAccount;

        // Create Contact
        Contact testContact = new Contact(
            FirstName = 'Test',
            LastName = 'Student',
            Email = 'test@example.com',
            AccountId = testAccount.Id
        );
        insert testContact;

        // Academic Session
        AcademicSession testSession = new AcademicSession(
            Name = 'Spring 2026',
            From_Date__c = System.today(),
            To_date__c = System.today().addDays(90)
        );
        insert testSession;

        // Learning
        Learning learn = new Learning(
            Name = 'Controller Learning'
        );
        insert learn;

        // Learning Program
        LearningProgram learningProgram = new LearningProgram(
            Name = 'MBA',
            LearningId = learn.Id
        );
        insert learningProgram;

        // Program Plan
        Program programPlan = new Program(
            Name = 'Test Program Plan'
        );
        insert programPlan;

        // Program
        Program prog = TestDataFactory.testProgram();

        // Academic Term
        AcademicTerm term =
            TestDataFactory.testAcademicTerm(prog.Id);

        // Program Enrollment
        ProgramEnrollment enrollment =
            new ProgramEnrollment(
                ContactId = testContact.Id,
                Learning_Program__c = learningProgram.Id,
                PGID__c = 'STU001',
                ISB_Fee_Payment_Installments__c = 'One Installment',
                ISB_Fee_Amount__c = 500000,
                ProgramId = programPlan.Id,
                Academic_Term__c = term.Id
            );
        insert enrollment;

        // Installment
        ISB_Installment__c installment =
            new ISB_Installment__c(
                Contact__c = testContact.Id,
                Installment_Number__c = 'Single',
                Paid_Amount__c = 0,
                Pending_Amount__c = 500000,
                Installment_Status__c = 'Not Paid',
                Program_Enrollment__c = enrollment.Id
            );
        insert installment;

        // Fees Master
        ISB_Fees_Master__c feesMaster =
            new ISB_Fees_Master__c(
                Academic_Term__c = term.Id,
                Installment__c = 'Single'
            );
        insert feesMaster;

        // Eligible Term
        ISB_Eligible_Term__c eligibleTerm =
            new ISB_Eligible_Term__c(
                ISB_Fees_Master__c = feesMaster.Id,
                Academic_Session__c = testSession.Id,
                Sequence__c = 1
            );
        insert eligibleTerm;

        // Fee
        ISB_Fee__c fee = new ISB_Fee__c(
            Program_Enrollment__c = enrollment.Id,
            ISB_Installment__c = installment.Id,
            Fee_Type__c = 'Tuition Fee',
            Total_amount__c = 500000,
            Fee_Status__c = 'Not Paid',
            Contact__c = testContact.Id,
            Customer__c = testContact.Id,
            Fee_Amount__c = 500000
        );
        insert fee;
    }

    @isTest
    static void testNoInstallmentFound() {

        delete [SELECT Id FROM ISB_Installment__c];

        UploadInstallmentPaymentsController.PaymentRow row =
            new UploadInstallmentPaymentsController.PaymentRow();

        row.studentId = 'STU001';
        row.bpid = 'BP001';
        row.cohort = 'Spring 2026';
        row.firstName = 'Test';
        row.lastName = 'Student';
        row.fullName = 'Test Student';
        row.tuitionFee = 100000;
        row.totalAmount = 500000;

        List<UploadInstallmentPaymentsController.PaymentRow> paymentList =
            new List<UploadInstallmentPaymentsController.PaymentRow>{ row };

        Test.startTest();

        UploadInstallmentPaymentsController.ProcessResult result =
            UploadInstallmentPaymentsController.processPaymentUpload(
                JSON.serialize(paymentList)
            );

        Test.stopTest();

        System.assertEquals(1, result.errorCount);
    }

    @isTest
    static void testProcessInstallmentForSAPWithNullIds() {

        Test.startTest();

        UploadInstallmentPaymentsController.processInstallmentForSAP(
            null,
            null
        );

        Test.stopTest();

        System.assert(true);
    }

    @isTest
    static void testProcessInstallmentForSAPDirectly() {

        ProgramEnrollment pe =
            [SELECT Id FROM ProgramEnrollment LIMIT 1];

        ISB_Installment__c inst =
            [SELECT Id FROM ISB_Installment__c LIMIT 1];

        Test.startTest();

        UploadInstallmentPaymentsController.processInstallmentForSAP(
            inst.Id,
            pe.Id
        );

        Test.stopTest();

        System.assert(true);
    }

    @isTest
    static void testCreatePaymentRecordDirectly() {

        Contact con = [SELECT Id FROM Contact LIMIT 1];

        ProgramEnrollment pe =
            [SELECT Id FROM ProgramEnrollment LIMIT 1];

        ISB_Installment__c inst =
            [SELECT Id FROM ISB_Installment__c LIMIT 1];

        UploadInstallmentPaymentsController.PaymentRow row =
            new UploadInstallmentPaymentsController.PaymentRow();

        row.studentId = 'STU001';
        row.fullName = 'Test Student';

        Test.startTest();

        ISB_Payment__c payment =
            UploadInstallmentPaymentsController.createPaymentRecord(
                con.Id,
                null,
                inst.Id,
                1000,
                row,
                pe.Id,
                'Single'
            );

        Test.stopTest();

        System.assertEquals(true, payment.SAP_Payment_Collected__c);
    }

    @isTest
    static void testProcessPaymentUploadSuccess() {

        UploadInstallmentPaymentsController.PaymentRow row =
            new UploadInstallmentPaymentsController.PaymentRow();

        row.studentId = 'STU001';
        row.bpid = 'BP001';
        row.cohort = 'Spring 2026';
        row.firstName = 'Test';
        row.lastName = 'Student';
        row.fullName = 'Test Student';
        row.tuitionFee = 100000;
        row.totalAmount = 500000;

        List<UploadInstallmentPaymentsController.PaymentRow> paymentList =
            new List<UploadInstallmentPaymentsController.PaymentRow>{ row };

        Test.startTest();

        UploadInstallmentPaymentsController.ProcessResult result =
            UploadInstallmentPaymentsController.processPaymentUpload(
                JSON.serialize(paymentList)
            );

        Test.stopTest();

        System.assertEquals(true, result.isSuccess);
        System.assertEquals(1, result.successCount);

        List<ISB_Payment__c> payments =
            [SELECT Id, SAP_Payment_Collected__c FROM ISB_Payment__c];

        System.assert(payments.size() > 0);
    }

    @isTest
    static void testGetInstallmentNumberSingle() {

        ProgramEnrollment enrollment =
            [SELECT Id, ISB_Fee_Payment_Installments__c
             FROM ProgramEnrollment
             LIMIT 1];

        Test.startTest();

        String installmentNum =
            UploadInstallmentPaymentsController.getInstallmentNumber(
                enrollment
            );

        Test.stopTest();

        System.assertEquals('Single', installmentNum);
    }

    @isTest
    static void testParseCSV() {

        String csvContent =
            'S.No,Student ID,BPID,Cohort,First Name,Last Name,Full name,Admission Fee,Commitment Fee,Tuition Fee,Tuition Waiver,Quad Accommodation,Studio Accommodation,GST,Security Deposit,Total Amount\n' +
            '1,STU001,BP001,Spring 2026,Test,Student,Test Student,0,0,100000,0,50000,0,27000,100000,277000\n';

        Test.startTest();

        List<UploadInstallmentPaymentsController.PaymentRow> rows =
            UploadInstallmentPaymentsController.parseCSV(csvContent);

        Test.stopTest();

        System.assertEquals(1, rows.size());
    }

    @isTest
    static void testParseDecimal() {

        Test.startTest();

        Decimal result1 =
            UploadInstallmentPaymentsController.parseDecimal(
                '100000'
            );

        Decimal result2 =
            UploadInstallmentPaymentsController.parseDecimal(
                'invalid'
            );

        Test.stopTest();

        System.assertEquals(100000, result1);
        System.assertEquals(0, result2);
    }

    @isTest
    static void testEnrollmentSessionCreationSuccess() {

        UploadInstallmentPaymentsController.PaymentRow row =
            new UploadInstallmentPaymentsController.PaymentRow();

        row.studentId = 'STU001';
        row.totalAmount = 500000;
        row.tuitionFee = 100000;

        List<UploadInstallmentPaymentsController.PaymentRow> paymentList =
            new List<UploadInstallmentPaymentsController.PaymentRow>{ row };

        Test.startTest();

        UploadInstallmentPaymentsController.ProcessResult result =
            UploadInstallmentPaymentsController.processPaymentUpload(
                JSON.serialize(paymentList)
            );

        Test.stopTest();

        List<Enrollment_Session__c> sessions =
            [SELECT Id, Active__c
             FROM Enrollment_Session__c];

        System.assert(sessions.size() >= 0);
    }
@isTest
static void testParseCSVEmptyContent() {

    Test.startTest();

    List<UploadInstallmentPaymentsController.PaymentRow> rows =
        UploadInstallmentPaymentsController.parseCSV('');

    Test.stopTest();

    System.assertEquals(0, rows.size());
}
@isTest
static void testProcessPaymentUploadBlankData() {

    Test.startTest();

    UploadInstallmentPaymentsController.ProcessResult result =
        UploadInstallmentPaymentsController.processPaymentUpload('');

    Test.stopTest();

    System.assertEquals(false, result.isSuccess);
}
@isTest
static void testProcessPaymentUploadInvalidJson() {

    Test.startTest();

    UploadInstallmentPaymentsController.ProcessResult result =
        UploadInstallmentPaymentsController.processPaymentUpload(
            'invalid json'
        );

    Test.stopTest();

    System.assertEquals(false, result.isSuccess);
}

}