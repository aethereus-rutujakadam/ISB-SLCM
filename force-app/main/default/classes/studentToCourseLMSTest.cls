@IsTest
public class studentToCourseLMSTest {

    /* =======================
       SUCCESS MOCK
       ======================= */
    private class SuccessMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setStatus('OK');
            res.setBody('{"message":"Registration successful"}');
            return res;
        }
    }

    /* =======================
       ERROR MOCK
       ======================= */
    private class ErrorMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(400);
            res.setStatus('Bad Request');
            res.setBody('{"error":"Invalid data"}');
            return res;
        }
    }

    /* =======================
       TEST SUCCESS SCENARIO
       ======================= */
    @IsTest
    static void testSendRegistrationToLMS_success_returnsResponseBody() {

        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        studentToCourseLMS.RegistrationRequest req =
            new studentToCourseLMS.RegistrationRequest();
        req.CourseOfferingId = 'CO-001';
        req.StudentPGID = 'STU-123';
        req.Name = 'Test Student';
        req.ParticipationStatus = 'Registered';
        req.RegistrationDateTime = '2025-01-01T10:00:00';

        Test.startTest();
        String response = studentToCourseLMS.sendRegistrationToLMS(req);
        Test.stopTest();

        System.assertNotEquals(null, response);
        System.assert(response.contains('successful'));
    }

    /* =======================
       TEST ERROR RESPONSE
       ======================= */
    @IsTest
    static void testSendRegistrationToLMS_errorResponse_returnsErrorBody() {

        Test.setMock(HttpCalloutMock.class, new ErrorMock());

        studentToCourseLMS.RegistrationRequest req =
            new studentToCourseLMS.RegistrationRequest();
        req.CourseOfferingId = 'CO-002';
        req.StudentPGID = 'STU-456';

        Test.startTest();
        String response = studentToCourseLMS.sendRegistrationToLMS(req);
        Test.stopTest();

        System.assertNotEquals(null, response);
        System.assert(response.contains('Invalid data'));
    }

    /* =======================
       TEST NULL REQUEST (NO EXCEPTION EXPECTED)
       ======================= */
    @IsTest
    static void testSendRegistrationToLMS_nullRequest_executesSafely() {

        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        Test.startTest();
        String response = studentToCourseLMS.sendRegistrationToLMS(null);
        Test.stopTest();

        // serialize(null) is valid → no exception expected
        System.assertNotEquals(null, response);
    }
}