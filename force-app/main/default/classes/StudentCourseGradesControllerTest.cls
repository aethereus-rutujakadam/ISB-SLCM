@isTest
public class StudentCourseGradesControllerTest {

    private static String uniqueKey = String.valueOf(DateTime.now().getTime());

    // ----------------------------
    // TEST SETUP - reusable test data
    // ----------------------------
    @TestSetup
    static void setupTestData() {
        // 1. Create Account
        Account acct = TestDataFactory.testAccount('Test Student Account');

        // 2. Create Student
        Contact student = TestDataFactory.testContact(acct.Id);

        // 2. Create Learning
        Learning lrn = TestDataFactory.testLearning();

        // 3. Create Learning Course
        LearningCourse lc = TestDataFactory.testLearningCourse(lrn.Id);

        // 4. Create Session
        AcademicSession sess = TestDataFactory.testAcademicSession();

        // 5. Create Course Offering
        CourseOffering co = new CourseOffering(
            Name = 'Course Offering ' + uniqueKey,
            IsActive = true,
            AcademicSessionId = sess.Id,
            LearningCourseId = lc.Id
        );
        insert co;

        // 6. Create Participant
        CourseOfferingParticipant cop = new CourseOfferingParticipant(
            CourseOfferingId = co.Id,
            ParticipantContactId = student.Id,
            ParticipationStatus = 'Enrolled'
        );
        insert cop;

        // 7. Create Result
        CourseOfferingPtcpResult result = new CourseOfferingPtcpResult(
            CourseOfferingParticipantId = cop.Id,
            Grade_Letter__c = 'A',
            NumericGrade = 90
        );
        insert result;
    }

    // ----------------------------
    // INTEGRATION TEST: Happy Path
    // ----------------------------
    @isTest
    static void test_getStudentGrades_withRecords_returnsWrapper() {
        Id studentContactId = TestDataFactory.testDataMap.get('contactWithAccountId');
        if(studentContactId == null) studentContactId = [SELECT Id FROM Contact LIMIT 1].Id;

        Test.startTest();
        List<StudentCourseGradesController.GradeWrapper> wrappers =
            StudentCourseGradesController.getStudentGrades(studentContactId);
        Test.stopTest();

        System.assertEquals(1, wrappers.size(), 'Expected one wrapper record');
        System.assertEquals('A', wrappers[0].letterGrade);
        System.assertEquals(90, wrappers[0].numericGrade);
    }

    // ----------------------------
    // INTEGRATION TEST: No Records
    // ----------------------------
    @isTest
    static void test_getStudentGrades_noRecords_returnsEmptyList() {
        Id fakeContactId = (Id) TestDataFactory.getFakeId(Contact.SObjectType);

        Test.startTest();
        List<StudentCourseGradesController.GradeWrapper> wrappers =
            StudentCourseGradesController.getStudentGrades(fakeContactId);
        Test.stopTest();

        System.assertEquals(0, wrappers.size());
    }

    // ----------------------------
    // UNIT TEST: Wrapper Logic & Fallback
    // Uses JSON.deserialize to mock the relationship structure in memory
    // entirely avoiding DML and "Invalid Field" errors.
    // ----------------------------
    @isTest
    static void test_GradeWrapper_Logic_Fallback() {
        // We construct the JSON to mimic the SOQL result structure exactly.
        // This simulates a scenario where LearningCourse Name is NULL, 
        // triggering the fallback to CourseOffering Name.
        
        String mockJson = '{' +
            '"attributes": {"type": "CourseOfferingPtcpResult"},' +
            '"Grade_Letter__c": "B",' +
            '"NumericGrade": 75,' +
            '"CourseOfferingParticipant": {' +
                '"attributes": {"type": "CourseOfferingParticipant"},' +
                '"ParticipationStatus": "Completed",' +
                '"CourseOffering": {' +
                    '"attributes": {"type": "CourseOffering"},' +
                    '"Name": "Fallback Course Name",' + 
                    '"AcademicSession": {' +
                        '"attributes": {"type": "AcademicSession"},' +
                        '"Name": "Fall 2025"' +
                    '},' +
                    '"LearningCourse": {' +
                        '"attributes": {"type": "LearningCourse"},' +
                        '"Name": null' + // Simulating null/blank name
                    '}' +
                '}' +
            '}' +
        '}';

        // Deserialize into the Object
        CourseOfferingPtcpResult mockResult = (CourseOfferingPtcpResult) JSON.deserialize(mockJson, CourseOfferingPtcpResult.class);

        Test.startTest();
        // Pass the mocked SObject to the Wrapper constructor
        StudentCourseGradesController.GradeWrapper wrapper = 
            new StudentCourseGradesController.GradeWrapper(mockResult);
        Test.stopTest();

        // Assertions
        System.assertEquals('Fallback Course Name', wrapper.courseName, 'Should fallback to Course Offering Name when Learning Course Name is null');
        System.assertEquals('Fall 2025', wrapper.academicSession);
        System.assertEquals('B', wrapper.letterGrade);
        System.assertEquals(75, wrapper.numericGrade);
        System.assertEquals('Completed', wrapper.enrollmentStatus);
    }
}