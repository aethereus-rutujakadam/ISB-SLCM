@IsTest
public class LMS_AAtoCourseAssignmentService_Test {

    /*
     * ------------------------------------------------------------
     * Mock Class – Success Response (200)
     * ------------------------------------------------------------
     */
    private class LMSMockSuccess implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('Assignment Created Successfully');
            return res;
        }
    }

    private class LMSMockSuccess201 implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(201);
            res.setBody('Assignment Created Successfully');
            return res;
        }
    }

    /*
     * ------------------------------------------------------------
     * Mock Class – Error Response (400)
     * ------------------------------------------------------------
     */
    private class LMSMockError implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(400);
            res.setBody('Bad Request');
            return res;
        }
    }

    /*
     * ------------------------------------------------------------
     * Test Success Scenario
     * ------------------------------------------------------------
     */
    @IsTest
    static void testSendAssignmentSuccess() {

        String mockAAId = TestDataFactory.getFakeId(Contact.SObjectType);
        String mockCourseOfferingId = TestDataFactory.getFakeId(CourseOffering.SObjectType);

        Test.setMock(HttpCalloutMock.class, new LMSMockSuccess());

        Test.startTest();
        String result = LMS_AAtoCourseAssignmentService.sendAssignmentToLMS(
            mockAAId,
            mockCourseOfferingId,
            Date.today(),
            Date.today().addDays(30),
            'Test Remarks'
        );
        Test.stopTest();

        System.assert(result.contains('SUCCESS'), 'Should return success for 200 OK');
    }

    @IsTest
    static void testSendAssignmentSuccess201() {

        String mockAAId = TestDataFactory.getFakeId(Contact.SObjectType);
        String mockCourseOfferingId = TestDataFactory.getFakeId(CourseOffering.SObjectType);

        Test.setMock(HttpCalloutMock.class, new LMSMockSuccess201());

        Test.startTest();
        String result = LMS_AAtoCourseAssignmentService.sendAssignmentToLMS(
            mockAAId,
            mockCourseOfferingId,
            Date.today(),
            Date.today().addDays(30),
            'Test Remarks'
        );
        Test.stopTest();

        System.assert(result.contains('SUCCESS'), 'Should return success for 201 Created');
    }

    /*
     * ------------------------------------------------------------
     * Test Error Scenario
     * ------------------------------------------------------------
     */
    @IsTest
    static void testSendAssignmentError() {

        String mockAAId = TestDataFactory.getFakeId(Contact.SObjectType);
        String mockCourseOfferingId = TestDataFactory.getFakeId(CourseOffering.SObjectType);

        Test.setMock(HttpCalloutMock.class, new LMSMockError());

        Test.startTest();
        String result = LMS_AAtoCourseAssignmentService.sendAssignmentToLMS(
            mockAAId,
            mockCourseOfferingId,
            Date.today(),
            Date.today().addDays(30),
            'Test Remarks'
        );
        Test.stopTest();

        System.assert(result.contains('ERROR'), 'Should return error for 400 Bad Request');
    }

    /*
     * ------------------------------------------------------------
     * Test Exception Scenario
     * This will cause NullPointerException (startDate.year())
     * ------------------------------------------------------------
     */
    @IsTest
    static void testSendAssignmentException() {

        String mockAAId = TestDataFactory.getFakeId(Contact.SObjectType);
        String mockCourseOfferingId = TestDataFactory.getFakeId(CourseOffering.SObjectType);

        Test.startTest();
        String result = LMS_AAtoCourseAssignmentService.sendAssignmentToLMS(
            mockAAId,
            mockCourseOfferingId,
            null,                 // This will trigger exception
            Date.today().addDays(30),
            'Test Remarks'
        );
        Test.stopTest();

        System.assert(result.contains('EXCEPTION'));
    }
}