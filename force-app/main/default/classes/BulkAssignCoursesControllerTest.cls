@IsTest
public class BulkAssignCoursesControllerTest {

    // ---------- Helpers ----------
    private static String uniq() {
        return String.valueOf(System.now().getTime()) + '_' + String.valueOf(Math.abs(Crypto.getRandomInteger()));
    }

    private static String getAllowedEnrollmentSessionStatus() {
        Set<String> allowed = new Set<String>{ 'Registered', 'Completed', 'Rejoined', 'Re-Registered' };

        Schema.DescribeFieldResult d =
            Enrollment_Session__c.SObjectType
                .getDescribe()
                .fields.getMap()
                .get('Status__c')
                .getDescribe();

        for (Schema.PicklistEntry p : d.getPicklistValues()) {
            if (p.isActive() && allowed.contains(p.getValue())) return p.getValue();
        }
        // fallback: any active value
        for (Schema.PicklistEntry p : d.getPicklistValues()) {
            if (p.isActive()) return p.getValue();
        }
        return null;
    }

    // Duplicate-rule safe + lookup-filter friendly contact
    private static Contact createUniqueStudentContact() {
        String key = uniq();

        Account a = new Account(Name = 'Test Student Account ' + key);
        insert a;

        Contact c = new Contact(
            FirstName = 'Test',
            LastName  = 'Student ' + key,
            AccountId = a.Id,
            Email     = 'student.' + key + '@example.com'
        );

        // Set only if fields exist in the org
        Map<String, Schema.SObjectField> f = Contact.SObjectType.getDescribe().fields.getMap();
        if (f.containsKey('hed__Preferred_Email__c')) c.put('hed__Preferred_Email__c', 'VF Email ID');
        if (f.containsKey('VF_Email_ID__c')) c.put('VF_Email_ID__c', 'student.' + key + '@example.com');

        // Optional: Student record type if exists
        List<RecordType> rts = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Contact'
            AND (DeveloperName = 'Student' OR Name = 'Student')
            LIMIT 1
        ];
        if (!rts.isEmpty()) c.RecordTypeId = rts[0].Id;

        insert c;
        return c;
    }

    // ---------- Test Setup ----------
    @testSetup
    static void makeData() {
        Program prog = TestDataFactory.testProgram();

        AcademicTerm term = TestDataFactory.createTerm(
            prog.Id,
            'Term 2025 ' + uniq(),
            Date.today()
        );

        AcademicSession session = new AcademicSession(
            Name = 'Session 2025 ' + uniq(),
            AcademicTermId = term.Id
        );
        insert session;

        Learning l = TestDataFactory.testLearning();
        LearningCourse lc = TestDataFactory.testLearningCourse(l.Id);

        CourseOffering co = TestDataFactory.testCourseOffering(lc.Id, session.Id);
        co.Program__c = prog.Id;
        update co;

        Contact student = createUniqueStudentContact();

        ProgramEnrollment pe = TestDataFactory.testProgramEnrollment(student, prog);
        pe.Status = 'Registered';
        pe.Sub_Status__c = 'Student';
        update pe;

        String esStatus = getAllowedEnrollmentSessionStatus();
        System.assertNotEquals(null, esStatus, 'No valid Enrollment_Session__c.Status__c value found');

        TestDataFactory.createEnrollmentSession(pe.Id, session.Id, esStatus);
    }

    // ---------- Tests ----------
    @IsTest
    static void testGetCourseOfferingDetails() {
        CourseOffering co = [SELECT Id FROM CourseOffering LIMIT 1];

        Test.startTest();
        Map<String, Object> details = BulkAssignCoursesController.getCourseOfferingDetails(co.Id);
        Test.stopTest();

        System.assertNotEquals(null, details);
        System.assertNotEquals(null, details.get('programId'));
        System.assertNotEquals(null, details.get('academicTermId')); // (controller returns AcademicSessionId)
    }

    @IsTest
    static void testSearchStudents() {
        Program prog = [SELECT Id FROM Program LIMIT 1];
        AcademicTerm term = [SELECT Id FROM AcademicTerm LIMIT 1];
        AcademicSession session = [SELECT Id FROM AcademicSession LIMIT 1];

        Test.startTest();
        List<ProgramEnrollment> results = BulkAssignCoursesController.searchStudents(prog.Id, term.Id, session.Id);
        Test.stopTest();

        System.assert(results.size() > 0, 'Should find at least one student');
        System.assertNotEquals(null, results[0].ContactId);
    }

    @IsTest
    static void testGetCourseOfferingsByLearningCourse() {
        LearningCourse lc = [SELECT Id FROM LearningCourse LIMIT 1];
        AcademicSession session = [SELECT Id FROM AcademicSession LIMIT 1];

        Test.startTest();
        List<Map<String, String>> results =
            BulkAssignCoursesController.getCourseOfferingsByLearningCourse(lc.Id, session.Id);
        Test.stopTest();

        System.assert(results.size() > 0);
    }

    @IsTest
    static void testGetAcademicTermsByProgram() {
        Program prog = [SELECT Id FROM Program LIMIT 1];

        Test.startTest();
        List<Map<String, String>> results = BulkAssignCoursesController.getAcademicTermsByProgram(prog.Id);
        Test.stopTest();

        System.assert(results.size() > 0);
    }

    @IsTest
    static void testGetAcademicSessionsByTerm() {
        AcademicTerm term = [SELECT Id FROM AcademicTerm LIMIT 1];

        Test.startTest();
        List<Map<String, String>> results = BulkAssignCoursesController.getAcademicSessionsByTerm(term.Id);
        Test.stopTest();

        System.assert(results.size() > 0);
    }

    @IsTest
    static void testGetLearningCoursesBySession() {
        AcademicSession session = [SELECT Id FROM AcademicSession LIMIT 1];

        Test.startTest();
        List<Map<String, String>> results = BulkAssignCoursesController.getLearningCoursesBySession(session.Id);
        Test.stopTest();

        System.assert(results.size() > 0);
    }

    @IsTest
    static void testGetCourseTypePicklistValues() {
        Test.startTest();
        List<Map<String, String>> results = BulkAssignCoursesController.getCourseTypePicklistValues();
        Test.stopTest();

        System.assertNotEquals(null, results);
    }

    @IsTest
    static void testGetObjectApiNames() {
        Test.startTest();
        String programObj = BulkAssignCoursesController.getProgramObjectApiName();
        String termObj = BulkAssignCoursesController.getTermObjectApiName();
        Test.stopTest();

        System.assertNotEquals(null, programObj);
        System.assertEquals('AcademicTerm', termObj);
    }

    @IsTest
    static void testCreateParticipants_Success() {
        Contact student = [SELECT Id FROM Contact LIMIT 1];
        CourseOffering co = [SELECT Id, AcademicSessionId FROM CourseOffering LIMIT 1];
        System.assertNotEquals(null, co.AcademicSessionId, 'AcademicSessionId must be set for validation');

        Test.startTest();
        Integer count = BulkAssignCoursesController.createParticipants(
            new List<Id>{ student.Id },
            co.Id,
            'Core'
        );
        Test.stopTest();

        System.assertEquals(1, count);
        System.assertEquals(
            1,
            [SELECT COUNT() FROM CourseOfferingParticipant WHERE CourseOfferingId = :co.Id AND ParticipantContactId = :student.Id]
        );
    }

    // ✅ UPDATED: Do not assert exception message (org may wrap it as "Script-thrown exception")
    @IsTest
    static void testCreateParticipants_DuplicateError() {
        Contact student = [SELECT Id FROM Contact LIMIT 1];
        CourseOffering co = [SELECT Id, AcademicSessionId FROM CourseOffering LIMIT 1];
        System.assertNotEquals(null, co.AcademicSessionId, 'AcademicSessionId must be set for validation');

        Test.startTest();

        // First insert should succeed
        Integer first = BulkAssignCoursesController.createParticipants(
            new List<Id>{ student.Id },
            co.Id,
            'Core'
        );
        System.assertEquals(1, first);

        Boolean threw = false;
        try {
            // Second insert should throw (duplicate)
            BulkAssignCoursesController.createParticipants(
                new List<Id>{ student.Id },
                co.Id,
                'Core'
            );
        } catch (AuraHandledException e) {
            threw = true;
        }

        Test.stopTest();
        System.assert(threw, 'Expected duplicate exception');
    }

    // ✅ UPDATED: No message assertions (keep stable across org wrappers)
    @IsTest
    static void testCreateParticipants_ValidationError_NotEnrolledInSession() {
        Contact notEnrolled = createUniqueStudentContact();
        CourseOffering co = [SELECT Id, AcademicSessionId FROM CourseOffering LIMIT 1];
        System.assertNotEquals(null, co.AcademicSessionId, 'AcademicSessionId must be set for validation');

        Boolean threw = false;

        Test.startTest();
        try {
            BulkAssignCoursesController.createParticipants(
                new List<Id>{ notEnrolled.Id },
                co.Id,
                'Core'
            );
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'Expected validation exception');
    }

    // ✅ UPDATED: No message assertions (keep stable across org wrappers)
    @IsTest
    static void testCreateParticipants_MissingInput() {
        Boolean threw = false;

        Test.startTest();
        try {
            BulkAssignCoursesController.createParticipants(null, null, null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'Expected missing input exception');
    }
}