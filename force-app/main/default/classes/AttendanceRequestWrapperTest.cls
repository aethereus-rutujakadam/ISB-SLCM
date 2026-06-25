@IsTest
public class AttendanceRequestWrapperTest {

    @IsTest
    static void testAttendanceRequestSerialization() {

        // ----------------------------------------
        // Arrange (use TestDataFactory)
        // ----------------------------------------
        Contact student = TestDataFactory.testContact();

        AttendanceRequestWrapper.StudentData sd =
            new AttendanceRequestWrapper.StudentData();
        sd.StudentPGID = student.Id;
        sd.Status = 'Present';

        List<AttendanceRequestWrapper.StudentData> students =
            new List<AttendanceRequestWrapper.StudentData>{ sd };

        AttendanceRequestWrapper req = new AttendanceRequestWrapper();
        req.CourseOfferingId = 'CO-001';
        req.Section = 'A';
        req.SessionDate = '2025-09-01';
        req.SessionTime = '10:00 AM';
        req.Students = students;

        // ----------------------------------------
        // Act (serialize + deserialize)
        // ----------------------------------------
        String jsonPayload = JSON.serialize(req);

        AttendanceRequestWrapper parsed =
            (AttendanceRequestWrapper)
                JSON.deserialize(jsonPayload, AttendanceRequestWrapper.class);

        // ----------------------------------------
        // Assert
        // ----------------------------------------
        System.assertEquals('CO-001', parsed.CourseOfferingId);
        System.assertEquals('A', parsed.Section);
        System.assertEquals('2025-09-01', parsed.SessionDate);
        System.assertEquals('10:00 AM', parsed.SessionTime);

        System.assertNotEquals(null, parsed.Students);
        System.assertEquals(1, parsed.Students.size());
        System.assertEquals(student.Id, parsed.Students[0].StudentPGID);
        System.assertEquals('Present', parsed.Students[0].Status);
    }
}