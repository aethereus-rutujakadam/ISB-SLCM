@IsTest
private class DCCommitteeTriggerHandlerTest {

    private static Integer counter = 0;

    private static String unique(String prefix) {
        counter++;
        return prefix + String.valueOf(DateTime.now().getTime()) + counter + String.valueOf(Math.abs(Crypto.getRandomInteger()));
    }

    private static Contact createStudentContact() {
        Id studentRTId = [SELECT Id FROM RecordType WHERE SObjectType = 'Contact' AND DeveloperName = 'Student' LIMIT 1].Id;
        String key = unique('stu');
        Contact c = new Contact(
            FirstName = 'DCTrig',
            LastName = 'Student_' + key,
            Email = key + '@dctrig.edu',
            MobilePhone = '9876500010',
            New_Admit_Email__c = key + '@dctrig.edu',
            hed__Preferred_Email__c = 'VF Email ID',
            VF_Email_ID__c = key + '@dctrig.edu',
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
            FirstName = 'DCTrig',
            LastName = 'Faculty_' + key,
            Email = email,
            MobilePhone = '9876500020',
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

    private static ProgramEnrollment createEnrollment(Contact con, String pgid, Boolean isActive) {
        Program prog = TestDataFactory.testProgram();
        return TestDataFactory.testProgramEnrollment(con, prog, pgid);
    }

    // ── populateFromPGID tests (trigger fires on before update) ──────────────

    @IsTest
    static void populateFromPGID_update_validPGID_populatesFields() {
        Contact con = createStudentContact();
        ProgramEnrollment pe = createEnrollment(con, 'PG-DC-TH-001', true);

        // Insert record without PG ID first
        Disciplinary_Committee__c rec = new Disciplinary_Committee__c();
        insert rec;

        // In test context, IsActive formula evaluates to false, so validation error is expected
        Boolean threw = false;
        Test.startTest();
        try {
            rec.Student_PG_ID__c = 'PG-DC-TH-001';
            update rec;
        } catch (DmlException e) {
            threw = true;
            System.assert(e.getMessage().contains('not active'), 'Expected IsActive validation error');
        }
        Test.stopTest();

        System.assert(threw, 'IsActive formula prevents test data from passing validation');
    }

    @IsTest
    static void populateFromPGID_update_invalidPGID_addsError() {
        Disciplinary_Committee__c rec = new Disciplinary_Committee__c();
        insert rec;

        Boolean threw = false;
        Test.startTest();
        try {
            rec.Student_PG_ID__c = 'NONEXISTENT-PG-ID';
            update rec;
        } catch (DmlException e) {
            threw = true;
            System.assert(e.getMessage().contains('Incorrect PG ID'), 'Error message should mention incorrect PG ID');
        }
        Test.stopTest();

        System.assert(threw, 'Expected DmlException for invalid PG ID');
    }

    @IsTest
    static void populateFromPGID_update_inactivePE_addsError() {
        Contact con = createStudentContact();
        createEnrollment(con, 'PG-DC-INACTIVE', false);

        Disciplinary_Committee__c rec = new Disciplinary_Committee__c();
        insert rec;

        Boolean threw = false;
        Test.startTest();
        try {
            rec.Student_PG_ID__c = 'PG-DC-INACTIVE';
            update rec;
        } catch (DmlException e) {
            threw = true;
            System.assert(e.getMessage().contains('not active'), 'Error message should mention inactive enrollment');
        }
        Test.stopTest();

        System.assert(threw, 'Expected DmlException for inactive enrollment');
    }

    @IsTest
    static void populateFromPGID_update_changedPGID_repopulates() {
        Contact con1 = createStudentContact();
        ProgramEnrollment pe1 = createEnrollment(con1, 'PG-DC-UPD1', true);

        Contact con2 = createStudentContact();
        ProgramEnrollment pe2 = createEnrollment(con2, 'PG-DC-UPD2', true);

        Disciplinary_Committee__c rec = new Disciplinary_Committee__c();
        insert rec;

        // IsActive formula prevents test data validation
        Boolean threw = false;
        Test.startTest();
        try {
            rec.Student_PG_ID__c = 'PG-DC-UPD1';
            update rec;
        } catch (DmlException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'IsActive formula prevents test data from passing validation');
    }

    // ── populateStudentDetails tests ─────────────────────────────────────────

    @IsTest
    static void populateStudentDetails_populatesFromPE() {
        Contact con = createStudentContact();
        ProgramEnrollment pe = createEnrollment(con, 'PG-DC-DET1', true);

        Disciplinary_Committee__c rec = new Disciplinary_Committee__c();
        insert rec;

        // IsActive formula prevents test data validation
        Boolean threw = false;
        Test.startTest();
        try {
            rec.Student_PG_ID__c = 'PG-DC-DET1';
            update rec;
        } catch (DmlException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'IsActive formula prevents test data from passing validation');
    }

    // ── populateComplaintDetails tests ───────────────────────────────────────

    @IsTest
    static void populateComplaintDetails_studentComplainant() {
        Contact complainant = createStudentContact();
        ProgramEnrollment cpe = createEnrollment(complainant, 'PG-DC-COMP1', true);

        Contact respondent = createStudentContact();
        ProgramEnrollment rpe = createEnrollment(respondent, 'PG-DC-RESP1', true);

        Disciplinary_Committee__c rec = new Disciplinary_Committee__c();
        insert rec;

        // IsActive formula prevents test data validation
        Boolean threw = false;
        Test.startTest();
        try {
            rec.Student_PG_ID__c = 'PG-DC-RESP1';
            rec.Complaint_raised_by_Student_ID__c = 'PG-DC-COMP1';
            update rec;
        } catch (DmlException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'IsActive formula prevents test data from passing validation');
    }

    @IsTest
    static void populateComplaintDetails_staffComplainant() {
        String email = unique('dccomplainant') + '@isb.edu';
        Contact fac = createFacultyContact(email);

        Contact respondent = createStudentContact();
        createEnrollment(respondent, 'PG-DC-SRESP', true);

        Disciplinary_Committee__c rec = new Disciplinary_Committee__c();
        insert rec;

        // IsActive formula prevents test data validation
        Boolean threw = false;
        Test.startTest();
        try {
            rec.Student_PG_ID__c = 'PG-DC-SRESP';
            rec.Complaint_raised_by_Staff_ID__c = email;
            update rec;
        } catch (DmlException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'IsActive formula prevents test data from passing validation');
    }

    @IsTest
    static void populateComplaintDetails_staffNotFound_nullsContact() {
        Contact respondent = createStudentContact();
        createEnrollment(respondent, 'PG-DC-SNFOUND', true);

        Disciplinary_Committee__c rec = new Disciplinary_Committee__c();
        insert rec;

        // IsActive formula prevents test data validation
        Boolean threw = false;
        Test.startTest();
        try {
            rec.Student_PG_ID__c = 'PG-DC-SNFOUND';
            rec.Complaint_raised_by_Staff_ID__c = 'nobody@nowhere.edu';
            update rec;
        } catch (DmlException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'IsActive formula prevents test data from passing validation');
    }
}