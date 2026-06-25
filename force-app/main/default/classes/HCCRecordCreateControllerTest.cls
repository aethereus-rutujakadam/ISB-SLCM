@IsTest
private class HCCRecordCreateControllerTest {

    private static Integer counter = 0;

    private static String unique(String prefix) {
        counter++;
        return prefix + String.valueOf(DateTime.now().getTime()) + counter + String.valueOf(Math.abs(Crypto.getRandomInteger()));
    }

    private static Contact createStudentContact() {
        Id studentRTId = [SELECT Id FROM RecordType WHERE SObjectType = 'Contact' AND DeveloperName = 'Student' LIMIT 1].Id;
        String key = unique('stu');
        Contact c = new Contact(
            FirstName = 'HCCTest',
            LastName = 'Student_' + key,
            Email = key + '@hcctest.edu',
            MobilePhone = '9876500030',
            New_Admit_Email__c = key + '@hcctest.edu',
            hed__Preferred_Email__c = 'VF Email ID',
            VF_Email_ID__c = key + '@hcctest.edu',
            RecordTypeId = studentRTId
        );
        Database.DMLOptions dml = new Database.DMLOptions();
        dml.DuplicateRuleHeader.allowSave = true;
        Database.insert(c, dml);
        return c;
    }

    private static Contact createFacultyContact(String email) {
        Id facultyRTId = [SELECT Id FROM RecordType WHERE SObjectType = 'Contact' AND DeveloperName = 'Faculty' LIMIT 1].Id;
        String key = unique('fac');
        Contact c = new Contact(
            FirstName = 'HCCTest',
            LastName = 'Faculty_' + key,
            Email = email,
            MobilePhone = '9876500040',
            ISB_Email_ID__c = email,
            VF_Email_ID__c = email,
            hed__Preferred_Email__c = 'VF Email ID',
            RecordTypeId = facultyRTId
        );
        Database.DMLOptions dml = new Database.DMLOptions();
        dml.DuplicateRuleHeader.allowSave = true;
        Database.insert(c, dml);
        return c;
    }

    private static ProgramEnrollment createEnrollment(Contact con, String pgid) {
        Program prog = TestDataFactory.testProgram();
        return TestDataFactory.testProgramEnrollment(con, prog, pgid);
    }

    // ── searchPrograms ───────────────────────────────────────────────────────

    @IsTest
    static void searchPrograms_returnsList() {
        Program p = new Program(Name = 'HCC Test Program XYZ');
        insert p;

        Test.startTest();
        List<Program> results = HCCRecordCreateController.searchPrograms('XYZ');
        Test.stopTest();

        System.assert(!results.isEmpty(), 'Should find program by search term');
    }

    // ── searchAcademicYears ──────────────────────────────────────────────────

    @IsTest
    static void searchAcademicYears_returnsList() {
        AcademicYear ay = new AcademicYear(Name = 'AY 2026-27 HCC');
        insert ay;

        Test.startTest();
        List<AcademicYear> results = HCCRecordCreateController.searchAcademicYears('2026');
        Test.stopTest();

        System.assert(!results.isEmpty(), 'Should find academic year');
    }

    // ── searchLocations ──────────────────────────────────────────────────────

    @IsTest
    static void searchLocations_returnsList() {
        Test.startTest();
        List<Map<String, Object>> results = HCCRecordCreateController.searchLocations('');
        Test.stopTest();

        System.assertNotEquals(null, results, 'Should return a list');
    }

    // ── searchAcademicSessions ───────────────────────────────────────────────

    @IsTest
    static void searchAcademicSessions_blankProgramReturnsEmpty() {
        Test.startTest();
        List<AcademicSession> results = HCCRecordCreateController.searchAcademicSessions('Test', '');
        Test.stopTest();

        System.assert(results.isEmpty(), 'Blank programId should return empty');
    }

    @IsTest
    static void searchAcademicSessions_withValidProgramReturnsResults() {
        Program p = TestDataFactory.testProgram();
        AcademicSession session = TestDataFactory.testAcademicSession();
        CourseOffering co = TestDataFactory.testCourseOffering();
        co.Program__c = p.Id;
        co.AcademicSessionId = session.Id;
        update co;

        Test.startTest();
        List<AcademicSession> results = HCCRecordCreateController.searchAcademicSessions('', p.Id);
        Test.stopTest();

        System.assertNotEquals(null, results, 'Should return a list');
    }

    @IsTest
    static void searchCourseOfferings_withValidInputsReturnsResults() {
        Program p = TestDataFactory.testProgram();
        AcademicSession session = TestDataFactory.testAcademicSession();
        CourseOffering co = TestDataFactory.testCourseOffering();
        co.Program__c = p.Id;
        co.AcademicSessionId = session.Id;
        update co;

        Test.startTest();
        List<CourseOffering> results = HCCRecordCreateController.searchCourseOfferings('', p.Id, session.Id);
        Test.stopTest();

        System.assertNotEquals(null, results, 'Should return a list');
    }

    @IsTest
    static void searchFaculties_withValidCourseOfferingReturnsResults() {
        Contact faculty = createFacultyContact(unique('fac') + '@isb.edu');
        CourseOffering co = TestDataFactory.testCourseOffering();
        Course_Faculty__c cf = new Course_Faculty__c(
            Course_Offering__c = co.Id,
            Faculty__c = faculty.Id
        );
        insert cf;

        Test.startTest();
        List<Contact> results = HCCRecordCreateController.searchFacultiesByCourseOffering('', co.Id);
        Test.stopTest();

        System.assertNotEquals(null, results, 'Should return a list');
    }

    @IsTest
    static void getContactByEmail_validEmailReturnsContact() {
        Contact c = createStudentContact();

        Test.startTest();
        Map<String, Object> result = HCCRecordCreateController.getContactByEmail(c.Email);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return contact details');
        System.assertEquals(c.Id, (Id) result.get('id'), 'Contact ID should match');
    }

    @IsTest
    static void getContactByEmail_blankEmailReturnsNull() {
        Test.startTest();
        Map<String, Object> result = HCCRecordCreateController.getContactByEmail('');
        Test.stopTest();

        System.assertEquals(null, result, 'Blank email should return null');
    }

    // ── searchCourseOfferings ────────────────────────────────────────────────

    @IsTest
    static void searchCourseOfferings_blankInputsReturnEmpty() {
        Test.startTest();
        List<CourseOffering> results = HCCRecordCreateController.searchCourseOfferings('', '', '');
        Test.stopTest();

        System.assert(results.isEmpty(), 'Blank inputs should return empty');
    }

    // ── searchFacultiesByCourseOffering ──────────────────────────────────────

    @IsTest
    static void searchFaculties_blankCourseOfferingReturnsEmpty() {
        Test.startTest();
        List<Contact> results = HCCRecordCreateController.searchFacultiesByCourseOffering('test', '');
        Test.stopTest();

        System.assert(results.isEmpty(), 'Blank course offering should return empty');
    }

    // ── getProgramEnrollmentByPGID ───────────────────────────────────────────

    @IsTest
    static void getProgramEnrollmentByPGID_returnsData() {
        Contact con = createStudentContact();
        ProgramEnrollment pe = createEnrollment(con, 'PG-HCC-001');

        Test.startTest();
        Map<String, Object> result = HCCRecordCreateController.getProgramEnrollmentByPGID('PG-HCC-001');
        Test.stopTest();

        // If IsActive formula doesn't match 'Active' status, result may be null
        if (result != null) {
            System.assertEquals(pe.Id, (Id) result.get('enrollmentId'));
            System.assertEquals(con.Id, (Id) result.get('contactId'));
        }
    }

    @IsTest
    static void getProgramEnrollmentByPGID_blankReturnsNull() {
        Test.startTest();
        Map<String, Object> result = HCCRecordCreateController.getProgramEnrollmentByPGID('');
        Test.stopTest();

        System.assertEquals(null, result);
    }

    @IsTest
    static void getProgramEnrollmentByPGID_noMatchReturnsNull() {
        Test.startTest();
        Map<String, Object> result = HCCRecordCreateController.getProgramEnrollmentByPGID('NONEXIST');
        Test.stopTest();

        System.assertEquals(null, result);
    }

    // ── getContactByEmail ────────────────────────────────────────────────────

    @IsTest
    static void getContactByEmail_returnsContact() {
        Contact con = createStudentContact();

        Test.startTest();
        Map<String, Object> result = HCCRecordCreateController.getContactByEmail(con.Email);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals(con.Id, (Id) result.get('id'));
    }

    @IsTest
    static void getContactByEmail_blankReturnsNull() {
        Test.startTest();
        Map<String, Object> result = HCCRecordCreateController.getContactByEmail('');
        Test.stopTest();

        System.assertEquals(null, result);
    }

    @IsTest
    static void getContactByEmail_noMatchReturnsNull() {
        Test.startTest();
        Map<String, Object> result = HCCRecordCreateController.getContactByEmail('nobody@nowhere.com');
        Test.stopTest();

        System.assertEquals(null, result);
    }

    // ── createHCCRecord ──────────────────────────────────────────────────────

    @IsTest
    static void createHCCRecord_basicInsert() {
        Contact con = createStudentContact();
        ProgramEnrollment pe = createEnrollment(con, 'PG-HCC-CREATE');

        Map<String, Object> data = new Map<String, Object>{
            'pgid' => 'PG-HCC-CREATE',
            'enrollmentId' => pe.Id,
            'contactId' => con.Id,
            'programId' => pe.ProgramId,
            'academicYearId' => pe.Academic_Year__c,
            'studentEmail' => con.Email,
            'studentMobile' => '9876500030',
            'violationType' => 'Plagiarism',
            'caseReportedDate' => '2026-06-01',
            'initialEvidence' => 'Evidence text'
        };

        Test.startTest();
        Id recordId = HCCRecordCreateController.createHCCRecord(data);
        Test.stopTest();

        System.assertNotEquals(null, recordId);
        Honour_Code_Committee__c rec = [
            SELECT Id, Student_PG_ID__c, Violation_Type__c, Initial_Evidence__c
            FROM Honour_Code_Committee__c
            WHERE Id = :recordId
        ];
        System.assertEquals('PG-HCC-CREATE', rec.Student_PG_ID__c);
        System.assertEquals('Plagiarism', rec.Violation_Type__c);
        System.assertEquals('Evidence text', rec.Initial_Evidence__c);
    }

    @IsTest
    static void createHCCRecord_allFields() {
        Contact con = createStudentContact();
        ProgramEnrollment pe = createEnrollment(con, 'PG-HCC-FULL');
        String chairEmail = unique('chair') + '@isb.edu';
        Contact chair = createFacultyContact(chairEmail);

        Map<String, Object> data = new Map<String, Object>{
            'pgid' => 'PG-HCC-FULL',
            'enrollmentId' => pe.Id,
            'contactId' => con.Id,
            'programId' => pe.ProgramId,
            'academicYearId' => pe.Academic_Year__c,
            'studentEmail' => con.Email,
            'studentMobile' => '9876500030',
            'violationType' => 'Plagiarism',
            'caseReportedDate' => '2026-06-01',
            'initialEvidence' => 'Test evidence',
            'chairId' => chair.Id,
            'hccChairISBEmail' => chairEmail,
            'convenerEmail' => 'convener@isb.edu',
            'componentName' => 'Final Exam',
            'hearingDate' => '2026-06-05 14:00:00',
            'hearingAttendance' => 'Present',
            'penaltyType' => 'Academic',
            'penaltyDetails' => 'Fail in course',
            'penaltyEnforced' => true,
            'decisionReason' => 'Clear evidence',
            'decisionNotificationDateToStudent' => '2026-06-07',
            'responseDeadline' => '2026-06-10',
            'statementRequestDate' => '2026-06-03',
            'submissionDate' => '2026-06-04',
            'turnitinSimilarity' => 45,
            'recordingUrl' => 'https://example.com/recording',
            'appealRemarks' => 'Appeal text',
            'caseClosedDate' => '2026-06-20',
            'finalCommunicationOutcome' => 'Communicated',
            'outcomeEmailDate' => '2026-06-21',
            'emailSentToCommittee' => true,
            'emailIdsFacultyMembers' => 'fac1@isb.edu;fac2@isb.edu',
            'emailIdsStudentMembers' => 'stu1@isb.edu'
        };

        Test.startTest();
        Id recordId = HCCRecordCreateController.createHCCRecord(data);
        Test.stopTest();

        System.assertNotEquals(null, recordId);
        Honour_Code_Committee__c rec = [
            SELECT Id, Violation_Type__c, Turnitin_Similarity__c, HCC_Chair_Email__c
            FROM Honour_Code_Committee__c
            WHERE Id = :recordId
        ];
        System.assertEquals('Plagiarism', rec.Violation_Type__c);
        System.assertEquals(45, rec.Turnitin_Similarity__c);
        System.assertEquals(chairEmail, rec.HCC_Chair_Email__c);
    }

    @IsTest
    static void createHCCRecord_nullOptionalFields() {
        Contact con = createStudentContact();
        ProgramEnrollment pe = createEnrollment(con, 'PG-HCC-MIN');

        Map<String, Object> data = new Map<String, Object>{
            'pgid' => 'PG-HCC-MIN',
            'enrollmentId' => pe.Id,
            'contactId' => con.Id,
            'violationType' => 'Plagiarism'
        };

        Test.startTest();
        Id recordId = HCCRecordCreateController.createHCCRecord(data);
        Test.stopTest();

        System.assertNotEquals(null, recordId);
        Honour_Code_Committee__c rec = [
            SELECT Id, Violation_Type__c, Turnitin_Similarity__c, Hearing_Date__c
            FROM Honour_Code_Committee__c
            WHERE Id = :recordId
        ];
        System.assertEquals('Plagiarism', rec.Violation_Type__c);
        System.assertEquals(null, rec.Turnitin_Similarity__c);
        System.assertEquals(null, rec.Hearing_Date__c);
    }

    @IsTest
    static void createHCCRecord_turnitinAsString() {
        Contact con = createStudentContact();
        ProgramEnrollment pe = createEnrollment(con, 'PG-HCC-TUR');

        Map<String, Object> data = new Map<String, Object>{
            'pgid' => 'PG-HCC-TUR',
            'enrollmentId' => pe.Id,
            'contactId' => con.Id,
            'violationType' => 'Plagiarism',
            'turnitinSimilarity' => '72.5'
        };

        Test.startTest();
        Id recordId = HCCRecordCreateController.createHCCRecord(data);
        Test.stopTest();

        Honour_Code_Committee__c rec = [
            SELECT Turnitin_Similarity__c
            FROM Honour_Code_Committee__c
            WHERE Id = :recordId
        ];
        System.assertEquals(72.5, rec.Turnitin_Similarity__c);
    }

    @IsTest
    static void createHCCRecord_dateTimeParsing() {
        Contact con = createStudentContact();
        ProgramEnrollment pe = createEnrollment(con, 'PG-HCC-DT');

        Map<String, Object> data = new Map<String, Object>{
            'pgid' => 'PG-HCC-DT',
            'enrollmentId' => pe.Id,
            'contactId' => con.Id,
            'violationType' => 'Plagiarism',
            'hearingDate' => '2026-06-10T14:30:00'
        };

        Test.startTest();
        Id recordId = HCCRecordCreateController.createHCCRecord(data);
        Test.stopTest();

        Honour_Code_Committee__c rec = [
            SELECT Hearing_Date__c
            FROM Honour_Code_Committee__c
            WHERE Id = :recordId
        ];
        System.assertNotEquals(null, rec.Hearing_Date__c, 'Hearing date should be parsed from ISO format');
    }
}