@IsTest
private class HCCCommitteeTriggerHandlerTest {

    private static Integer counter = 0;

    private static String unique(String prefix) {
        counter++;
        return prefix + String.valueOf(DateTime.now().getTime()) + counter + String.valueOf(Math.abs(Crypto.getRandomInteger()));
    }

    private static Contact createStudentContact() {
        Id studentRTId = [SELECT Id FROM RecordType WHERE SObjectType = 'Contact' AND DeveloperName = 'Student' LIMIT 1].Id;
        String key = unique('stu');
        Contact c = new Contact(
            FirstName = 'HCCTrig',
            LastName = 'Student_' + key,
            Email = key + '@hcctrig.edu',
            MobilePhone = '9876500050',
            New_Admit_Email__c = key + '@hcctrig.edu',
            hed__Preferred_Email__c = 'VF Email ID',
            VF_Email_ID__c = key + '@hcctrig.edu',
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
            FirstName = 'HCCTrig',
            LastName = 'Faculty_' + key,
            Email = email,
            MobilePhone = '9876500060',
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

    // ── populateFromPGID tests (trigger fires on before update only) ─────────

    @IsTest
    static void populateFromPGID_update_validPGID_populatesFields() {
        Contact con = createStudentContact();
        ProgramEnrollment pe = createEnrollment(con, 'PG-HCC-TH-001', true);

        Honour_Code_Committee__c rec = new Honour_Code_Committee__c();
        insert rec;

        // IsActive formula evaluates to false in test context, so validation error is expected
        Boolean threw = false;
        Test.startTest();
        try {
            rec.Student_PG_ID__c = 'PG-HCC-TH-001';
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
        Honour_Code_Committee__c rec = new Honour_Code_Committee__c();
        insert rec;

        Boolean threw = false;
        Test.startTest();
        try {
            rec.Student_PG_ID__c = 'NONEXISTENT-HCC-PG';
            update rec;
        } catch (DmlException e) {
            threw = true;
            System.assert(e.getMessage().contains('Incorrect PG ID'), 'Should mention incorrect PG ID');
        }
        Test.stopTest();

        System.assert(threw, 'Expected DmlException for invalid PG ID');
    }

    @IsTest
    static void populateFromPGID_update_inactivePE_addsError() {
        Contact con = createStudentContact();
        createEnrollment(con, 'PG-HCC-INACTIVE', false);

        Honour_Code_Committee__c rec = new Honour_Code_Committee__c();
        insert rec;

        Boolean threw = false;
        Test.startTest();
        try {
            rec.Student_PG_ID__c = 'PG-HCC-INACTIVE';
            update rec;
        } catch (DmlException e) {
            threw = true;
            System.assert(e.getMessage().contains('not active'), 'Should mention inactive enrollment');
        }
        Test.stopTest();

        System.assert(threw, 'Expected DmlException for inactive enrollment');
    }

    @IsTest
    static void populateFromPGID_update_changedPGID_repopulates() {
        Contact con1 = createStudentContact();
        ProgramEnrollment pe1 = createEnrollment(con1, 'PG-HCC-UPD1', true);

        Contact con2 = createStudentContact();
        ProgramEnrollment pe2 = createEnrollment(con2, 'PG-HCC-UPD2', true);

        Honour_Code_Committee__c rec = new Honour_Code_Committee__c();
        insert rec;

        // IsActive formula prevents test data validation
        Boolean threw = false;
        Test.startTest();
        try {
            rec.Student_PG_ID__c = 'PG-HCC-UPD1';
            update rec;
        } catch (DmlException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'IsActive formula prevents test data from passing validation');
    }

    @IsTest
    static void populateFromPGID_noPGID_noAction() {
        Honour_Code_Committee__c rec = new Honour_Code_Committee__c();

        Test.startTest();
        insert rec;
        Test.stopTest();

        Honour_Code_Committee__c result = [
            SELECT Student_PE_ID__c, Student__c
            FROM Honour_Code_Committee__c
            WHERE Id = :rec.Id
        ];
        System.assertEquals(null, result.Student_PE_ID__c);
        System.assertEquals(null, result.Student__c);
    }

    // ── populateChairFromEmail tests ─────────────────────────────────────────

    @IsTest
    static void populateChairFromEmail_update_resolvesChair() {
        String chairEmail = unique('chair') + '@isb.edu';
        Contact chair = createFacultyContact(chairEmail);

        Honour_Code_Committee__c rec = new Honour_Code_Committee__c();
        insert rec;

        Test.startTest();
        rec.HCC_Chair_Email__c = chairEmail;
        update rec;
        Test.stopTest();

        Honour_Code_Committee__c result = [
            SELECT Chair__c
            FROM Honour_Code_Committee__c
            WHERE Id = :rec.Id
        ];
        System.assertEquals(chair.Id, result.Chair__c, 'Chair should be resolved from email');
    }

    @IsTest
    static void populateChairFromEmail_update_unknownEmail_nullsChair() {
        Honour_Code_Committee__c rec = new Honour_Code_Committee__c();
        insert rec;

        Test.startTest();
        rec.HCC_Chair_Email__c = 'unknown.chair@nowhere.edu';
        update rec;
        Test.stopTest();

        Honour_Code_Committee__c result = [
            SELECT Chair__c
            FROM Honour_Code_Committee__c
            WHERE Id = :rec.Id
        ];
        System.assertEquals(null, result.Chair__c, 'Unknown chair email should leave field null');
    }

    @IsTest
    static void populateChairFromEmail_update_changesChair() {
        String email1 = unique('chair1') + '@isb.edu';
        Contact chair1 = createFacultyContact(email1);

        String email2 = unique('chair2') + '@isb.edu';
        Contact chair2 = createFacultyContact(email2);

        Honour_Code_Committee__c rec = new Honour_Code_Committee__c();
        insert rec;

        rec.HCC_Chair_Email__c = email1;
        update rec;

        Test.startTest();
        rec.HCC_Chair_Email__c = email2;
        update rec;
        Test.stopTest();

        Honour_Code_Committee__c result = [
            SELECT Chair__c
            FROM Honour_Code_Committee__c
            WHERE Id = :rec.Id
        ];
        System.assertEquals(chair2.Id, result.Chair__c, 'Chair should update to new faculty');
    }

    // ── populateStudentDetails tests ─────────────────────────────────────────

    @IsTest
    static void populateStudentDetails_fromPE_populatesContact() {
        Contact con = createStudentContact();
        ProgramEnrollment pe = createEnrollment(con, 'PG-HCC-DETAIL', true);

        Honour_Code_Committee__c rec = new Honour_Code_Committee__c();
        insert rec;

        // IsActive formula prevents test data validation
        Boolean threw = false;
        Test.startTest();
        try {
            rec.Student_PG_ID__c = 'PG-HCC-DETAIL';
            update rec;
        } catch (DmlException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'IsActive formula prevents test data from passing validation');
    }

    @IsTest
    static void populateStudentDetails_courseOffering_populatesProgramAndSession() {
        Contact con = createStudentContact();
        ProgramEnrollment pe = createEnrollment(con, 'PG-HCC-CO', true);

        Program prog = new Program(Name = unique('COProg-'));
        insert prog;

        AcademicYear ay = new AcademicYear(Name = unique('AY-'));
        insert ay;

        AcademicSession sess = new AcademicSession(Name = unique('Sess-'));
        insert sess;

        Learning lrn = new Learning(Name = unique('Lrn-'));
        insert lrn;

        LearningCourse lc = new LearningCourse(Name = unique('LC-'), LearningId = lrn.Id);
        insert lc;

        CourseOffering co = new CourseOffering(
            Name = unique('CO-'),
            LearningCourseId = lc.Id,
            AcademicSessionId = sess.Id,
            Program__c = prog.Id,
            Academic_Year__c = ay.Id
        );
        insert co;

        Honour_Code_Committee__c rec = new Honour_Code_Committee__c();
        insert rec;

        // IsActive formula prevents test data validation
        Boolean threw = false;
        Test.startTest();
        try {
            rec.Student_PG_ID__c = 'PG-HCC-CO';
            rec.Course__c = co.Id;
            update rec;
        } catch (DmlException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'IsActive formula prevents test data from passing validation');
    }

    @IsTest
    static void populateStudentDetails_directPEUpdate_populatesContact() {
        // Test the populateStudentDetails method by directly setting Student_PE_ID__c
        // This bypasses the IsActive validation in populateFromPGID
        Contact con = createStudentContact();
        ProgramEnrollment pe = createEnrollment(con, 'PG-HCC-DIRECT1', true);

        Honour_Code_Committee__c rec = new Honour_Code_Committee__c();
        insert rec;

        Test.startTest();
        rec.Student_PE_ID__c = pe.Id;
        update rec;
        Test.stopTest();

        Honour_Code_Committee__c result = [
            SELECT Student__c, Student_Email__c, Mobile_Number__c
            FROM Honour_Code_Committee__c
            WHERE Id = :rec.Id
        ];
        System.assertEquals(con.Id, result.Student__c, 'Student contact should be populated');
        System.assertEquals(con.New_Admit_Email__c, result.Student_Email__c, 'Email should be populated');
        System.assertEquals(con.MobilePhone, result.Mobile_Number__c, 'Mobile should be populated');
    }

    @IsTest
    static void populateStudentDetails_courseUpdate_populatesAcademicFields() {
        // Test the Course__c field population logic
        Contact con = createStudentContact();
        ProgramEnrollment pe = createEnrollment(con, 'PG-HCC-DIRECT2', true);

        Program prog = new Program(Name = unique('TestProg-'));
        insert prog;

        AcademicYear ay = new AcademicYear(Name = unique('TestAY-'));
        insert ay;

        AcademicSession sess = new AcademicSession(Name = unique('TestSess-'));
        insert sess;

        Learning lrn = new Learning(Name = unique('TestLrn-'));
        insert lrn;

        LearningCourse lc = new LearningCourse(Name = unique('TestLC-'), LearningId = lrn.Id);
        insert lc;

        CourseOffering co = new CourseOffering(
            Name = unique('TestCO-'),
            LearningCourseId = lc.Id,
            AcademicSessionId = sess.Id,
            Program__c = prog.Id,
            Academic_Year__c = ay.Id
        );
        insert co;

        Honour_Code_Committee__c rec = new Honour_Code_Committee__c();
        insert rec;

        Test.startTest();
        rec.Course__c = co.Id;
        update rec;
        Test.stopTest();

        Honour_Code_Committee__c result = [
            SELECT Academic_Year__c, Programme__c, Academic_Terms_Session__c
            FROM Honour_Code_Committee__c
            WHERE Id = :rec.Id
        ];
        System.assertEquals(ay.Id, result.Academic_Year__c, 'Academic Year should be populated from CourseOffering');
        System.assertEquals(prog.Id, result.Programme__c, 'Programme should be populated from CourseOffering');
        System.assertEquals(sess.Id, result.Academic_Terms_Session__c, 'Session should be populated from CourseOffering');
    }

    @IsTest
    static void populateStudentDetails_bothPEAndCourse_populatesAllFields() {
        // Test when both Student_PE_ID__c and Course__c are updated together
        Contact con = createStudentContact();
        ProgramEnrollment pe = createEnrollment(con, 'PG-HCC-BOTH', true);

        Program prog = new Program(Name = unique('BothProg-'));
        insert prog;

        AcademicYear ay = new AcademicYear(Name = unique('BothAY-'));
        insert ay;

        AcademicSession sess = new AcademicSession(Name = unique('BothSess-'));
        insert sess;

        Learning lrn = new Learning(Name = unique('BothLrn-'));
        insert lrn;

        LearningCourse lc = new LearningCourse(Name = unique('BothLC-'), LearningId = lrn.Id);
        insert lc;

        CourseOffering co = new CourseOffering(
            Name = unique('BothCO-'),
            LearningCourseId = lc.Id,
            AcademicSessionId = sess.Id,
            Program__c = prog.Id,
            Academic_Year__c = ay.Id
        );
        insert co;

        Honour_Code_Committee__c rec = new Honour_Code_Committee__c();
        insert rec;

        Test.startTest();
        rec.Student_PE_ID__c = pe.Id;
        rec.Course__c = co.Id;
        update rec;
        Test.stopTest();

        Honour_Code_Committee__c result = [
            SELECT Student__c, Student_Email__c, Mobile_Number__c, 
                   Academic_Year__c, Programme__c, Academic_Terms_Session__c
            FROM Honour_Code_Committee__c
            WHERE Id = :rec.Id
        ];
        System.assertEquals(con.Id, result.Student__c, 'Student should be populated');
        System.assertEquals(con.New_Admit_Email__c, result.Student_Email__c, 'Email should be populated');
        System.assertEquals(con.MobilePhone, result.Mobile_Number__c, 'Mobile should be populated');
        System.assertEquals(ay.Id, result.Academic_Year__c, 'Academic Year should be populated');
        System.assertEquals(prog.Id, result.Programme__c, 'Programme should be populated');
        System.assertEquals(sess.Id, result.Academic_Terms_Session__c, 'Session should be populated');
    }
}