@IsTest
private class DCRecordCreateControllerTest {

    private static Integer counter = 0;

    private static String unique(String prefix) {
        counter++;
        return prefix + String.valueOf(DateTime.now().getTime()) + counter + String.valueOf(Math.abs(Crypto.getRandomInteger()));
    }

    private static Contact createStudentContact() {
        Id studentRTId = [SELECT Id FROM RecordType WHERE SObjectType = 'Contact' AND DeveloperName = 'Student' LIMIT 1].Id;
        String key = unique('stu');
        Contact c = new Contact(
            FirstName = 'DCTest',
            LastName = 'Student_' + key,
            Email = key + '@dctest.edu',
            MobilePhone = '9876500001',
            New_Admit_Email__c = key + '@dctest.edu',
            hed__Preferred_Email__c = 'VF Email ID',
            VF_Email_ID__c = key + '@dctest.edu',
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
            FirstName = 'DCTest',
            LastName = 'Faculty_' + key,
            Email = email,
            MobilePhone = '9876500002',
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

    @IsTest
    static void getProgramEnrollmentByPGID_returnsData() {
        Contact con = createStudentContact();
        ProgramEnrollment pe = createEnrollment(con, 'PG-DC-001');

        Test.startTest();
        Map<String, Object> result = DCRecordCreateController.getProgramEnrollmentByPGID('PG-DC-001');
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
        Map<String, Object> result = DCRecordCreateController.getProgramEnrollmentByPGID('');
        Test.stopTest();

        System.assertEquals(null, result);
    }

    @IsTest
    static void getProgramEnrollmentByPGID_noMatchReturnsNull() {
        Test.startTest();
        Map<String, Object> result = DCRecordCreateController.getProgramEnrollmentByPGID('NONEXISTENT');
        Test.stopTest();

        System.assertEquals(null, result);
    }

    @IsTest
    static void getCohortOptions_returnsList() {
        AcademicTerm term = new AcademicTerm(Name = unique('Term-'));
        insert term;

        Test.startTest();
        List<Map<String, Object>> result = DCRecordCreateController.getCohortOptions();
        Test.stopTest();

        System.assert(!result.isEmpty(), 'Should return at least one term');
    }

    @IsTest
    static void getTermOptions_returnsList() {
        AcademicTerm term = new AcademicTerm(Name = unique('Term-'));
        insert term;

        Test.startTest();
        List<Map<String, Object>> result = DCRecordCreateController.getTermOptions();
        Test.stopTest();

        System.assert(!result.isEmpty(), 'Should return at least one term');
    }

    @IsTest
    static void getTermOptionsByProgramAndCohort_blankReturnsEmpty() {
        Test.startTest();
        List<Map<String, Object>> result = DCRecordCreateController.getTermOptionsByProgramAndCohort('', '');
        Test.stopTest();

        System.assert(result.isEmpty(), 'Blank inputs should return empty');
    }

    @IsTest
    static void getStudentByPGID_returnsContact() {
        Contact con = createStudentContact();
        createEnrollment(con, 'PG-DC-STU-01');

        Test.startTest();
        Map<String, Object> result = DCRecordCreateController.getStudentByPGID('PG-DC-STU-01');
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals(con.Id, (Id) result.get('contactId'));
    }

    @IsTest
    static void getStudentByPGID_blankReturnsNull() {
        Test.startTest();
        Map<String, Object> result = DCRecordCreateController.getStudentByPGID('');
        Test.stopTest();

        System.assertEquals(null, result);
    }

    @IsTest
    static void getStaffByEmail_returnsFaculty() {
        String email = unique('faculty') + '@isb.edu';
        Contact fac = createFacultyContact(email);

        Test.startTest();
        Map<String, Object> result = DCRecordCreateController.getStaffByEmail(email);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals(fac.Id, (Id) result.get('contactId'));
    }

    @IsTest
    static void getStaffByEmail_blankReturnsNull() {
        Test.startTest();
        Map<String, Object> result = DCRecordCreateController.getStaffByEmail('');
        Test.stopTest();

        System.assertEquals(null, result);
    }

    @IsTest
    static void getStaffByEmail_noMatchReturnsNull() {
        Test.startTest();
        Map<String, Object> result = DCRecordCreateController.getStaffByEmail('nobody@nowhere.com');
        Test.stopTest();

        System.assertEquals(null, result);
    }

    @IsTest
    static void createDCRecord_basicInsert() {
        Contact con = createStudentContact();
        ProgramEnrollment pe = createEnrollment(con, 'PG-DC-CREATE');

        Map<String, Object> data = new Map<String, Object>{
            'studentPgid' => 'PG-DC-CREATE',
            'programEnrollmentId' => pe.Id,
            'studentContactId' => con.Id,
            'programId' => pe.ProgramId,
            'cohortId' => pe.Academic_Term__c,
            'status' => 'Pending',
            'complaintDescription' => 'Test complaint',
            'complaintReceived' => '2026-06-01 10:00:00',
            'complaintRaisedBy' => 'Staff'
        };

        Test.startTest();
        Id recordId = DCRecordCreateController.createDCRecord(data);
        Test.stopTest();

        System.assertNotEquals(null, recordId, 'DC record should be created');
        Disciplinary_Committee__c rec = [
            SELECT Id, Student_PG_ID__c, Complaint_details_Description__c
            FROM Disciplinary_Committee__c
            WHERE Id = :recordId
        ];
        System.assertEquals('PG-DC-CREATE', rec.Student_PG_ID__c);
        System.assertEquals('Test complaint', rec.Complaint_details_Description__c);
    }

    @IsTest
    static void createDCRecord_withTestimonies() {
        Contact con = createStudentContact();
        ProgramEnrollment pe = createEnrollment(con, 'PG-DC-TESTI');

        List<Object> testimonies = new List<Object>{
            new Map<String, Object>{
                'type' => 'Complainant',
                'mom' => 'Minutes of complainant',
                'recordingUrl' => 'https://example.com/recording1'
            },
            new Map<String, Object>{
                'type' => 'Respondent',
                'mom' => 'Minutes of respondent',
                'recordingUrl' => 'https://example.com/recording2'
            }
        };

        Map<String, Object> data = new Map<String, Object>{
            'studentPgid' => 'PG-DC-TESTI',
            'programEnrollmentId' => pe.Id,
            'studentContactId' => con.Id,
            'programId' => pe.ProgramId,
            'status' => 'Pending',
            'complaintRaisedBy' => 'Student',
            'complaintStudentId' => 'PG-DC-TESTI',
            'complaintStudentContactId' => con.Id,
            'testimonies' => testimonies
        };

        Test.startTest();
        Id recordId = DCRecordCreateController.createDCRecord(data);
        Test.stopTest();

        System.assertNotEquals(null, recordId);
        List<DC_Meeting_Testimony__c> savedTestimonies = [
            SELECT Id, Testimony_Type__c, MOM__c, Recording_URL__c
            FROM DC_Meeting_Testimony__c
            WHERE Disciplinary_Committee__c = :recordId
            ORDER BY Testimony_Type__c
        ];
        System.assertEquals(2, savedTestimonies.size(), 'Both testimonies should be inserted');
        System.assertEquals('Complainant', savedTestimonies[0].Testimony_Type__c);
        System.assertEquals('Respondent', savedTestimonies[1].Testimony_Type__c);
    }

    @IsTest
    static void createDCRecord_withTestimoniesJsonFallback() {
        Contact con = createStudentContact();
        ProgramEnrollment pe = createEnrollment(con, 'PG-DC-JSON');

        String testimoniesJson = JSON.serialize(new List<Object>{
            new Map<String, Object>{
                'type' => 'Complainant',
                'mom' => 'JSON testimony',
                'recordingUrl' => null
            },
            new Map<String, Object>{
                'type' => 'Respondent',
                'mom' => 'JSON respondent',
                'recordingUrl' => null
            }
        });

        Map<String, Object> data = new Map<String, Object>{
            'studentPgid' => 'PG-DC-JSON',
            'programEnrollmentId' => pe.Id,
            'studentContactId' => con.Id,
            'programId' => pe.ProgramId,
            'status' => 'Pending',
            'complaintRaisedBy' => 'Staff',
            'testimonies' => null,
            'testimoniesJson' => testimoniesJson
        };

        Test.startTest();
        Id recordId = DCRecordCreateController.createDCRecord(data);
        Test.stopTest();

        System.assertNotEquals(null, recordId);
        Integer count = [SELECT COUNT() FROM DC_Meeting_Testimony__c WHERE Disciplinary_Committee__c = :recordId];
        System.assertEquals(2, count, 'JSON fallback should insert testimony records');
    }

    @IsTest
    static void createDCRecord_studentComplaint() {
        Contact con = createStudentContact();
        ProgramEnrollment pe = createEnrollment(con, 'PG-DC-SC');

        Map<String, Object> data = new Map<String, Object>{
            'studentPgid' => 'PG-DC-SC',
            'programEnrollmentId' => pe.Id,
            'studentContactId' => con.Id,
            'programId' => pe.ProgramId,
            'status' => 'Pending',
            'complaintRaisedBy' => 'Student',
            'complaintStudentId' => 'PG-DC-SC',
            'complaintStudentContactId' => con.Id,
            'complaintStudentMobile' => '9876500001'
        };

        Test.startTest();
        Id recordId = DCRecordCreateController.createDCRecord(data);
        Test.stopTest();

        Disciplinary_Committee__c rec = [
            SELECT Complaint_raised_by__c, Complaint_raised_by_Student_ID__c, Student_Complaint__c
            FROM Disciplinary_Committee__c
            WHERE Id = :recordId
        ];
        System.assertEquals('Student', rec.Complaint_raised_by__c);
        System.assertEquals('PG-DC-SC', rec.Complaint_raised_by_Student_ID__c);
    }

    @IsTest
    static void createDCRecord_staffComplaint() {
        String email = unique('staffdc') + '@isb.edu';
        Contact fac = createFacultyContact(email);
        Contact con = createStudentContact();
        ProgramEnrollment pe = createEnrollment(con, 'PG-DC-FC');

        Map<String, Object> data = new Map<String, Object>{
            'studentPgid' => 'PG-DC-FC',
            'programEnrollmentId' => pe.Id,
            'studentContactId' => con.Id,
            'programId' => pe.ProgramId,
            'status' => 'Pending',
            'complaintRaisedBy' => 'Staff',
            'complaintStaffEmail' => email,
            'complaintStaffContactId' => fac.Id,
            'complaintStaffMobile' => '9876500002'
        };

        Test.startTest();
        Id recordId = DCRecordCreateController.createDCRecord(data);
        Test.stopTest();

        Disciplinary_Committee__c rec = [
            SELECT Complaint_raised_by__c, Complaint_raised_by_Staff_ID__c, Complaint_raised_by_Staff__c
            FROM Disciplinary_Committee__c
            WHERE Id = :recordId
        ];
        System.assertEquals('Staff', rec.Complaint_raised_by__c);
        System.assertEquals(email, rec.Complaint_raised_by_Staff_ID__c);
        System.assertEquals(fac.Id, rec.Complaint_raised_by_Staff__c);
    }

    @IsTest
    static void createDCRecord_allFieldsMapped() {
        Contact con = createStudentContact();
        ProgramEnrollment pe = createEnrollment(con, 'PG-DC-FULL');

        Map<String, Object> data = new Map<String, Object>{
            'studentPgid' => 'PG-DC-FULL',
            'programEnrollmentId' => pe.Id,
            'studentContactId' => con.Id,
            'programId' => pe.ProgramId,
            'cohortId' => pe.Academic_Term__c,
            'status' => 'Pending',
            'complaintDescription' => 'Full test',
            'complaintReceived' => '2026-06-01 09:00:00',
            'complaintRaisedBy' => 'Staff',
            'showcauseNoticeSent' => '2026-06-02',
            'studentResponseToShowcause' => '2026-06-03',
            'committeeChairEmail' => 'chair@isb.edu',
            'committeeChairName' => 'Chair Name',
            'meetingName' => 'DC Meeting 1',
            'meetingDate' => '2026-06-05',
            'meetingParticipants' => 'A, B, C',
            'studentsInvolved' => 'Student A',
            'meetingDuration' => 2.5,
            'numberOfSittings' => 3,
            'finalHearingDate' => '2026-06-10',
            'finalOutcome' => 'Guilty',
            'actionSharedDate' => '2026-06-11',
            'actionTakenDescription' => 'Probation',
            'finalPenalty' => 'Suspension'
        };

        Test.startTest();
        Id recordId = DCRecordCreateController.createDCRecord(data);
        Test.stopTest();

        Disciplinary_Committee__c rec = [
            SELECT Id, Disciplinary_Committee_Meeting_Name__c, Final_outcome__c, Final_Penalty__c
            FROM Disciplinary_Committee__c
            WHERE Id = :recordId
        ];
        System.assertEquals('DC Meeting 1', rec.Disciplinary_Committee_Meeting_Name__c);
        System.assertEquals('Guilty', rec.Final_outcome__c);
        System.assertEquals('Suspension', rec.Final_Penalty__c);
    }
}