@IsTest
public class GradeSyncIntegrationTest {

    /* =====================================================
       TEST SETUP – SHARED DATA FOR ALL TEST METHODS
       ===================================================== */
    @TestSetup
    static void setupTestData() {

        // Student Contact
        Contact student = TestDataFactory.testContact();
        // student.Student_Id__c = 'PGP1234';
        // update student;

        // Program + Term + Session
        Program program = TestDataFactory.testProgram();
        AcademicTerm term = TestDataFactory.testAcademicTerm(program.Id);
        AcademicSession session = TestDataFactory.testAcademicSession();

        // Learning + Course + Offering
        Learning learning = TestDataFactory.testLearning();
        LearningCourse course = TestDataFactory.testLearningCourse(learning.Id);
        CourseOffering offering =
            TestDataFactory.testCourseOffering(course.Id, session.Id);

        offering.LMS_Course_Id__c = '0P0720000001v13CAA';
        update offering;

        // Program Enrollment
        ProgramEnrollment pe =
            TestDataFactory.testProgramEnrollment(student, program, 'PGP1234');

        // Participant (REQUIRED for insert/update path)
        CourseOfferingParticipant cop = new CourseOfferingParticipant(
            ParticipantContactId = student.Id,
            CourseOfferingId = offering.Id
        );
        insert cop;
    }

    /* =====================================================
       INSERT NEW RESULT – SUCCESS
       ===================================================== */
    @IsTest
    static void testUpsertResult_insertNew_success() {

        List<Map<String, Object>> payload = new List<Map<String, Object>>();
        payload.add(
            TestDataFactory.buildGradeSyncRequest(
                'PGP1234',
                '0P0720000001v13CAA'
            )
        );

        TestDataFactory.setupRestContext(
            TestDataFactory.toJson(payload)
        );

        Test.startTest();
        List<GradeSyncIntegration.ResultResponse> results =
            GradeSyncIntegration.upsertResult();
        Test.stopTest();

        System.assertEquals(1, results.size(), 'One response expected');
        System.assertEquals(true, results[0].success);
        System.assert(results[0].message.contains('Created New Grade record'));
        System.assertNotEquals(null, results[0].recordId);
    }

    /* =====================================================
       UPDATE EXISTING RESULT – SUCCESS
       ===================================================== */
    @IsTest
    static void testUpsertResult_updateExisting_success() {

        CourseOfferingParticipant cop =
            [SELECT Id FROM CourseOfferingParticipant LIMIT 1];

        // Existing result record
        CourseOfferingPtcpResult existing = new CourseOfferingPtcpResult(
            CourseOfferingParticipantId = cop.Id,
            Credits_Attempted__c = 2,
            Credits_Earned__c = 2
        );
        insert existing;

        List<Map<String, Object>> payload = new List<Map<String, Object>>();
        payload.add(
            TestDataFactory.buildGradeSyncRequest(
                'PGP1234',
                '0P0720000001v13CAA'
            )
        );

        TestDataFactory.setupRestContext(
            TestDataFactory.toJson(payload)
        );

        Test.startTest();
        List<GradeSyncIntegration.ResultResponse> results =
            GradeSyncIntegration.upsertResult();
        Test.stopTest();

        System.assertEquals(true, results[0].success);
        System.assert(results[0].message.contains('Updated Grade record'));
    }

    /* =====================================================
       VALIDATION – STUDENT ID MISSING
       ===================================================== */
    @IsTest
    static void testUpsertResult_missingStudentId_error() {

        Map<String, Object> req =
            TestDataFactory.buildGradeSyncRequest(
                null,
                '0P0720000001v13CAA'
            );

        TestDataFactory.setupRestContext(
            JSON.serialize(new List<Map<String, Object>>{ req })
        );

        List<GradeSyncIntegration.ResultResponse> results =
            GradeSyncIntegration.upsertResult();

        System.assertEquals(false, results[0].success);
        System.assertEquals(
            'StudentId is required',
            results[0].message
        );
    }

    /* =====================================================
       VALIDATION – COURSE OFFERING ID MISSING
       ===================================================== */
    @IsTest
    static void testUpsertResult_missingCourseOfferingId_error() {

        Map<String, Object> req =
            TestDataFactory.buildGradeSyncRequest(
                'PGP1234',
                null
            );

        TestDataFactory.setupRestContext(
            JSON.serialize(new List<Map<String, Object>>{ req })
        );

        List<GradeSyncIntegration.ResultResponse> results =
            GradeSyncIntegration.upsertResult();

        System.assertEquals(false, results[0].success);
        System.assertEquals(
            'CourseOfferingId is required',
            results[0].message
        );
    }

    /* =====================================================
       NO PARTICIPANT FOUND FOR EXTERNAL KEY
       ===================================================== */
    @IsTest
    static void testUpsertResult_noParticipantFound_error() {

        Map<String, Object> req =
            TestDataFactory.buildGradeSyncRequest(
                'PGP9999',
                'INVALID'
            );

        TestDataFactory.setupRestContext(
            JSON.serialize(new List<Map<String, Object>>{ req })
        );

        List<GradeSyncIntegration.ResultResponse> results =
            GradeSyncIntegration.upsertResult();

        System.assertEquals(false, results[0].success);
        System.assert(
            results[0].message.contains('No Participant found')
        );
    }

    /* =====================================================
       EMPTY REQUEST BODY
       ===================================================== */
    @IsTest
    static void testUpsertResult_emptyRequestBody_error() {

        TestDataFactory.setupRestContext('[]');

        List<GradeSyncIntegration.ResultResponse> results =
            GradeSyncIntegration.upsertResult();

        System.assertEquals(false, results[0].success);
    }

    /* =====================================================
       MALFORMED JSON – GLOBAL CATCH BLOCK
       ===================================================== */
    @IsTest
    static void testUpsertResult_malformedJson_exceptionHandled() {

        TestDataFactory.setupRestContext('INVALID_JSON');

        List<GradeSyncIntegration.ResultResponse> results =
            GradeSyncIntegration.upsertResult();

        System.assertEquals(false, results[0].success);
        System.assert(
            results[0].message.contains('Unexpected error')
        );
    }
}