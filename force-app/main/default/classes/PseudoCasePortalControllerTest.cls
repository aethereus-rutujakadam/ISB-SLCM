@IsTest
public class PseudoCasePortalControllerTest {

    /* =========================================================
       @TestSetup
       Reusable base data for all tests
       ========================================================= */
    @TestSetup
    static void setupData() {

        // Student Contact
        Contact student = TestDataFactory.testContact();

        // Program + Enrollment
        Program program = TestDataFactory.testProgram();
        ProgramEnrollment pe =
            TestDataFactory.testProgramEnrollment(student, program);

        // Academic Session + Enrollment Session
        AcademicSession session =
            TestDataFactory.testAcademicSession();

        TestDataFactory.createEnrollmentSession(
            pe.Id,
            session.Id,
            'Registered' // ✔ valid restricted picklist
        );
    }

    /* =========================================================
       OTP METHODS
       ========================================================= */

    @IsTest
    static void verifyEmailAndSendOTP_validEmail_otpReturned() {
        Contact c = [SELECT Id, Email FROM Contact LIMIT 1];

        Test.startTest();
        Map<String, String> result =
            PseudoCasePortalController.verifyEmailAndSendOTP(c.Email);
        Test.stopTest();

        System.assertEquals(c.Id, result.get('contactId'));
        System.assertNotEquals(null, result.get('otp'));
        System.assertEquals(6, result.get('otp').length());
    }

    @IsTest
    static void verifyEmailAndSendOTP_blankEmail_exceptionThrown() {
        try {
            PseudoCasePortalController.verifyEmailAndSendOTP('');
            System.assert(false, 'Exception expected');
        } catch (AuraHandledException e) {
           System.assert(true);
        }
    }

    @IsTest
    static void verifyEmailAndSendOTP_emailNotFound_exceptionThrown() {
        try {
            PseudoCasePortalController.verifyEmailAndSendOTP('noone@test.com');
            System.assert(false, 'Exception expected');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void resendOTP_validEmail_otpReturned() {
        Contact c = [SELECT Id, Email FROM Contact LIMIT 1];

        Test.startTest();
        Map<String, String> result =
            PseudoCasePortalController.resendOTP(c.Email);
        Test.stopTest();

        System.assertEquals(c.Id, result.get('contactId'));
        System.assertEquals(6, result.get('otp').length());
    }

    /* =========================================================
       RECORD TYPE METHODS
       ========================================================= */

    @IsTest
    static void getCaseRecordTypes_activeRecordTypesReturned() {
        Test.startTest();
        List<PseudoCasePortalController.RecordTypeDTO> result =
            PseudoCasePortalController.getCaseRecordTypes();
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(result.size() > 0);
        System.assertNotEquals(null, result[0].id);
    }

    /* =========================================================
       PROGRAM ENROLLMENT METHODS
       ========================================================= */

    @IsTest
    static void getProgramEnrollmentsForContact_validContact_recordsReturned() {
        Contact c = [SELECT Id FROM Contact LIMIT 1];

        List<ProgramEnrollment> result =
            PseudoCasePortalController.getProgramEnrollmentsForContact(c.Id);

        System.assertEquals(1, result.size());
    }

    @IsTest
    static void getProgramEnrollmentsForContact_nullContact_exceptionThrown() {
        try {
            PseudoCasePortalController.getProgramEnrollmentsForContact(null);
            System.assert(false, 'Exception expected');
        } catch (AuraHandledException e) {
           System.assert(true);
        }
    }

    @IsTest
    static void getTermsForProgramEnrollment_validPE_termsReturned() {
        ProgramEnrollment pe = [SELECT Id FROM ProgramEnrollment LIMIT 1];

        List<PseudoCasePortalController.TermDTO> result =
            PseudoCasePortalController.getTermsForProgramEnrollment(pe.Id);

        System.assertEquals(1, result.size());
        System.assertEquals('Registered', result[0].status);
    }

    @IsTest
    static void getTermsForProgramEnrollment_nullPE_exceptionThrown() {
        try {
            PseudoCasePortalController.getTermsForProgramEnrollment(null);
            System.assert(false, 'Exception expected');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    /* =========================================================
       CASE CREATION METHODS
       ========================================================= */

    @IsTest
    static void createCaseRequest_validPayload_caseCreated() {
        Contact c = [SELECT Id FROM Contact LIMIT 1];

        Id rtId = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Case'
            AND IsActive = true
            LIMIT 1
        ].Id;

        Map<String, String> payload = new Map<String, String>{
            'recordTypeId' => rtId,
            'contactId' => c.Id,
            'subject' => 'Test Case',
            'description' => 'Test Description',
            'requestType' => 'General'
        };

        Test.startTest();
        Map<String, String> result =
            PseudoCasePortalController.createCaseRequest(payload);
        Test.stopTest();

        System.assertEquals('success', result.get('status'));
        System.assertNotEquals(null, result.get('caseNumber'));
    }

    @IsTest
    static void createCaseRequest_missingRecordType_exceptionThrown() {
        Contact c = [SELECT Id FROM Contact LIMIT 1];

        Map<String, String> payload = new Map<String, String>{
            'contactId' => c.Id
        };

        try {
            PseudoCasePortalController.createCaseRequest(payload);
            System.assert(false, 'Exception expected');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void createCaseRequest_missingContact_exceptionThrown() {
        Id rtId = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Case'
            AND IsActive = true
            LIMIT 1
        ].Id;

        Map<String, String> payload = new Map<String, String>{
            'recordTypeId' => rtId
        };

        try {
            PseudoCasePortalController.createCaseRequest(payload);
            System.assert(false, 'Exception expected');
        } catch (AuraHandledException e) {
            System.assert(true);     
        }
    }

    /* =========================================================
       FUTURE METHODS (EMAIL)
       ========================================================= */

    @IsTest
    static void sendCaseConfirmationEmailAsync_executesSuccessfully() {
        Contact c = [SELECT Id, Email FROM Contact LIMIT 1];

        Case cs = new Case(
            ContactId = c.Id,
            Status = 'New',
            Origin = 'Web',
            Subject = 'Async Email Test'
        );
        insert cs;

        Test.startTest();
        PseudoCasePortalController.sendCaseConfirmationEmailAsync(cs.Id, c.Id);
        Test.stopTest();

        // No exception = pass
        System.assert(true);
    }
}