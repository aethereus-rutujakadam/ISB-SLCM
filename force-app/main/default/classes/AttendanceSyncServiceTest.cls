@IsTest
public class AttendanceSyncServiceTest {

    // Helper to set REST context
    private static void setRest(String body) {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/LMS/AttendanceSync';
        req.httpMethod = 'POST';
        if (body != null) req.requestBody = Blob.valueOf(body);
        RestContext.request = req;
        RestContext.response = new RestResponse();
    }

    @IsTest
    static void testReceiveAttendance_success() {
        // -----------------------------
        // 1) Base Data
        // -----------------------------
        Contact student = TestDataFactory.testContact();
        Program program = TestDataFactory.testProgram();

        // Create a Term we will use consistently everywhere
        AcademicTerm term = TestDataFactory.createTerm(program.Id, 'Term 1', Date.today());

        // Create an Academic Session linked to the same term
        AcademicSession session = new AcademicSession(
            Name = 'Term 1',
            AcademicTermId = term.Id
        );
        insert session;

        // Program Enrollment must match PGID + Term (service uses PGID__c + Academic_Term__c)
        ProgramEnrollment pe = TestDataFactory.testProgramEnrollment(student, program);
        pe.PGID__c = 'PG001';
        pe.Academic_Term__c = term.Id;
        update pe;

        // Enrollment Session must exist for that PE (service queries Enrollment_Session__c by PE)
        Enrollment_Session__c es = TestDataFactory.createEnrollmentSession(pe.Id, session.Id);

        // Learning / LearningCourse / Offering
        Learning learning = TestDataFactory.testLearning();
        LearningCourse lc = TestDataFactory.testLearningCourse(learning.Id);

        CourseOffering offering = TestDataFactory.testCourseOffering(lc.Id, session.Id);
        String lmsId = 'LMS-CO-1';

        offering.LMS_Course_ID__c = lmsId;     // ✅ critical: service maps by LMS_Course_ID__c
        offering.Academic_Term__c = term.Id;   // ✅ critical: service collects termIds from offerings
        update offering;

        // -----------------------------
        // 2) Build REST Payload (CourseOfferingId MUST be LMS ID string)
        // -----------------------------
        AttendanceSyncService.StudentData stu = new AttendanceSyncService.StudentData();
        stu.StudentPGID = 'PG001';
        stu.Status = 'Present';

        AttendanceSyncService.AttendanceRequestWrapper row = new AttendanceSyncService.AttendanceRequestWrapper();
        row.CourseOfferingId = lmsId; // ✅ send LMS Course Id, NOT offering.Id
        row.Section = 'A';
        row.SessionDate = String.valueOf(Date.today());
        row.SessionTime = '10:00 AM';
        row.Students = new List<AttendanceSyncService.StudentData>{ stu };

        List<AttendanceSyncService.AttendanceRequestWrapper> payload =
            new List<AttendanceSyncService.AttendanceRequestWrapper>{ row };

        setRest(JSON.serialize(payload));

        // -----------------------------
        // 3) Execute
        // -----------------------------
        Test.startTest();
        AttendanceSyncService.ResponseWrapper res = AttendanceSyncService.receiveAttendance();
        Test.stopTest();

        // -----------------------------
        // 4) Assertions
        // -----------------------------
        System.assertNotEquals(null, res, 'Response should not be null');
        System.assertEquals('SUCCESS', res.status, 'Expected SUCCESS. Actual message: ' + res.message);
        System.assert(res.message.contains('Attendance processing completed'), 'Unexpected message: ' + res.message);

        System.assertEquals(
            1,
            [SELECT COUNT() FROM Session_Attendance__c],
            'Session_Attendance__c should be created'
        );

        System.assertEquals(
            1,
            [SELECT COUNT() FROM Course_Attendance__c],
            'Course_Attendance__c should be created'
        );
    }

    @IsTest
    static void testReceiveAttendance_nullBody() {
        // requestBody stays null
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/LMS/AttendanceSync';
        req.httpMethod = 'POST';
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        AttendanceSyncService.ResponseWrapper res = AttendanceSyncService.receiveAttendance();
        Test.stopTest();

        System.assertEquals('ERROR', res.status);
        System.assert(res.message.toLowerCase().contains('request body is empty'));
    }

    @IsTest
    static void testReceiveAttendance_emptyList() {
        setRest(JSON.serialize(new List<AttendanceSyncService.AttendanceRequestWrapper>()));

        Test.startTest();
        AttendanceSyncService.ResponseWrapper res = AttendanceSyncService.receiveAttendance();
        Test.stopTest();

        System.assertEquals('ERROR', res.status);
        System.assert(res.message.toLowerCase().contains('request body list is empty'));
    }

    @IsTest
    static void testReceiveAttendance_missingCourseOfferingId() {
        AttendanceSyncService.AttendanceRequestWrapper row = new AttendanceSyncService.AttendanceRequestWrapper();
        row.Section = 'A';
        row.SessionDate = String.valueOf(Date.today());
        row.SessionTime = '10:00 AM';
        row.Students = new List<AttendanceSyncService.StudentData>();

        setRest(JSON.serialize(new List<AttendanceSyncService.AttendanceRequestWrapper>{ row }));

        Test.startTest();
        AttendanceSyncService.ResponseWrapper res = AttendanceSyncService.receiveAttendance();
        Test.stopTest();

        System.assertEquals('ERROR', res.status);
        System.assert(res.message.toLowerCase().contains('missing courseofferingid'));
    }

    @IsTest
    static void testReceiveAttendance_missingDateOrTime() {
        AttendanceSyncService.AttendanceRequestWrapper row = new AttendanceSyncService.AttendanceRequestWrapper();
        row.CourseOfferingId = 'LMS-CO-X';
        row.Section = 'A';
        row.SessionDate = null;       // missing
        row.SessionTime = '10:00 AM'; // present
        row.Students = new List<AttendanceSyncService.StudentData>();

        setRest(JSON.serialize(new List<AttendanceSyncService.AttendanceRequestWrapper>{ row }));

        Test.startTest();
        AttendanceSyncService.ResponseWrapper res = AttendanceSyncService.receiveAttendance();
        Test.stopTest();

        System.assertEquals('ERROR', res.status);
        System.assert(res.message.toLowerCase().contains('missing sessiondate/sessiontime'));
    }

    @IsTest
    static void testReceiveAttendance_offeringNotFoundByLmsId() {
        // Valid payload shape, but LMS_Course_ID__c won't match anything -> service should fail after session insert
        AttendanceSyncService.StudentData stu = new AttendanceSyncService.StudentData();
        stu.StudentPGID = 'PG001';
        stu.Status = 'Present';

        AttendanceSyncService.AttendanceRequestWrapper row = new AttendanceSyncService.AttendanceRequestWrapper();
        row.CourseOfferingId = 'LMS-NOT-FOUND';
        row.Section = 'A';
        row.SessionDate = String.valueOf(Date.today());
        row.SessionTime = '10:00 AM';
        row.Students = new List<AttendanceSyncService.StudentData>{ stu };

        setRest(JSON.serialize(new List<AttendanceSyncService.AttendanceRequestWrapper>{ row }));

        Test.startTest();
        AttendanceSyncService.ResponseWrapper res = AttendanceSyncService.receiveAttendance();
        Test.stopTest();

        System.assertEquals('ERROR', res.status);
        System.assert(
            res.message.toLowerCase().contains('failed to create any session_attendance__c') ||
            res.message.toLowerCase().contains('check lms course ids'),
            'Unexpected message: ' + res.message
        );
    }
}