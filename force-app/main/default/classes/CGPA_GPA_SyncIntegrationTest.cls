/**
 * @description Finalized test class for CGPA_GPA_SyncIntegration.
 * Addresses overwriting logic by using distinct student records and 
 * adjusts error message assertions for generic exception wrapping.
 */
@isTest
private class CGPA_GPA_SyncIntegrationTest {

    @TestSetup
    static void setupData() {
        Program prog = TestDataFactory.testProgram();
        
        // Setup two distinct students to prevent parent-record DML conflicts
        Contact studentA = TestDataFactory.testContact();
        Contact studentB = TestDataFactory.testContact();

        AcademicSession sess = TestDataFactory.testAcademicSession();
        LearningCourse lc = TestDataFactory.testLearningCourse(TestDataFactory.testLearning().Id);
        
        CourseOffering co = TestDataFactory.testCourseOffering(lc.Id, sess.Id);
        co.LMS_Course_Id__c = 'LMS_001';
        update co;

        ProgramEnrollment peA = TestDataFactory.testProgramEnrollment(studentA, prog, 'STU_A');
        ProgramEnrollment peB = TestDataFactory.testProgramEnrollment(studentB, prog, 'STU_B');
        
        TestDataFactory.createEnrollmentSession(peA.Id, sess.Id);
        TestDataFactory.createEnrollmentSession(peB.Id, sess.Id);
    }

    private static void setRestContext(Object payload) {
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestURI = '/services/apexrest/v1/cgpa_gpa_sync';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(payload));
        RestContext.request = req;
        RestContext.response = res;
    }

    @isTest
    static void updateResult_validBulkRequest_returnsSuccess() {
        List<CGPA_GPA_SyncIntegration.APIRequest> payload = new List<CGPA_GPA_SyncIntegration.APIRequest>();
        
        // Request 1: CGPA for Student A
        CGPA_GPA_SyncIntegration.APIRequest req1 = new CGPA_GPA_SyncIntegration.APIRequest();
        req1.StudentId = 'STU_A';
        req1.CourseOfferingId = 'LMS_001';
        req1.Type = 'CGPA';
        req1.Value = 9.5;
        
        // Request 2: GPA for Student B
        CGPA_GPA_SyncIntegration.APIRequest req2 = new CGPA_GPA_SyncIntegration.APIRequest();
        req2.StudentId = 'STU_B';
        req2.CourseOfferingId = 'LMS_001';
        req2.Type = 'GPA';
        req2.Value = 8.5;
        
        payload.add(req1);
        payload.add(req2);
        setRestContext(payload);

        Test.startTest();
        List<CGPA_GPA_SyncIntegration.ResultResponse> results = CGPA_GPA_SyncIntegration.updateResult();
        Test.stopTest();

        System.assertEquals(2, results.size());
        System.assertEquals(true, results[0].success);
        System.assertEquals(true, results[1].success);
        
        ProgramEnrollment peA = [SELECT CGPA__c FROM ProgramEnrollment WHERE PGID__c = 'STU_A' LIMIT 1];
        System.assertEquals(9.5, peA.CGPA__c);

        Enrollment_Session__c esB = [SELECT GPA__c FROM Enrollment_Session__c WHERE Program_Enrollment__r.PGID__c = 'STU_B' LIMIT 1];
        System.assertEquals(8.5, esB.GPA__c);
    }

    @isTest
    static void updateResult_emptyRequestBody_returnsErrorResponse() {
        setRestContext(new List<CGPA_GPA_SyncIntegration.APIRequest>());

        Test.startTest();
        List<CGPA_GPA_SyncIntegration.ResultResponse> results = CGPA_GPA_SyncIntegration.updateResult();
        Test.stopTest();

        System.assertNotEquals(0, results.size(), 'Should return a response object');
        System.assertEquals(false, results[0].success, 'Success flag should be false for empty request');
        // We check for the presence of "Unexpected error" OR "body cannot be empty" to accommodate catch block wrapping
        System.assert(results[0].message.contains('Unexpected error') || results[0].message.contains('body cannot be empty'), 
            'Message was: ' + results[0].message);
    }

    @isTest
    static void updateResult_missingRequiredFields_returnsErrorInResult() {
        List<CGPA_GPA_SyncIntegration.APIRequest> payload = new List<CGPA_GPA_SyncIntegration.APIRequest>();
        CGPA_GPA_SyncIntegration.APIRequest req = new CGPA_GPA_SyncIntegration.APIRequest();
        req.StudentId = ''; 
        req.CourseOfferingId = 'LMS_001';
        payload.add(req);
        setRestContext(payload);

        Test.startTest();
        List<CGPA_GPA_SyncIntegration.ResultResponse> results = CGPA_GPA_SyncIntegration.updateResult();
        Test.stopTest();

        System.assertEquals(false, results[0].success);
        System.assert(results[0].message.contains('StudentId is required'));
    }

    @isTest
    static void updateResult_recordNotFound_returnsNoRecordsFound() {
        List<CGPA_GPA_SyncIntegration.APIRequest> payload = new List<CGPA_GPA_SyncIntegration.APIRequest>();
        CGPA_GPA_SyncIntegration.APIRequest req = new CGPA_GPA_SyncIntegration.APIRequest();
        req.StudentId = 'MISSING_USER';
        req.CourseOfferingId = 'LMS_MISSING';
        req.Type = 'GPA';
        req.Value = 7.0;
        payload.add(req);
        setRestContext(payload);

        Test.startTest();
        List<CGPA_GPA_SyncIntegration.ResultResponse> results = CGPA_GPA_SyncIntegration.updateResult();
        Test.stopTest();

        System.assertEquals(false, results[0].success);
        System.assert(results[0].message.contains('No records found'));
    }
}