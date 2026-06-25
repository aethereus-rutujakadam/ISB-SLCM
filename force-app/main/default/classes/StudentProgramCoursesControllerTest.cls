@IsTest
public class StudentProgramCoursesControllerTest {

    private static final String PORTAL_ALIAS = 'pusr1';

    @TestSetup
    static void setupData() {

        // ---------------------------------------------------
        // STEP A: Create setup objects (Role + Users) safely
        // Using runAs to avoid MIXED_DML
        // ---------------------------------------------------
        Profile adminProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'System Administrator'
            LIMIT 1
        ];

        // 1) Create a "runner" user first (no role needed)
        User runner = new User(
            FirstName = 'Runner',
            LastName  = 'User',
            Alias     = 'runr',
            Email     = 'runner@test.com',
            Username  = 'runner.' + System.currentTimeMillis() + '@test.com',
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey   = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = adminProfile.Id
        );
        insert runner;

        // 2) Now create Role + AccountOwner + PortalUser inside runAs(runner)
        System.runAs(runner) {
            UserRole ur = new UserRole(Name = 'Test Portal Owner Role');
            insert ur;

            User acctOwner = new User(
                FirstName = 'Acct',
                LastName  = 'Owner',
                Alias     = 'aown',
                Email     = 'acct.owner@test.com',
                Username  = 'acct.owner.' + System.currentTimeMillis() + '@test.com',
                TimeZoneSidKey = 'Asia/Kolkata',
                LocaleSidKey   = 'en_US',
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US',
                ProfileId = adminProfile.Id,
                UserRoleId = ur.Id
            );
            insert acctOwner;

            // Store acctOwner Id somewhere accessible later via query (Alias = 'aown')
            // Portal user will be created later AFTER non-setup records exist (Contact)
        }

        // ---------------------------------------------------
        // STEP B: Create non-setup data (Program/Account/Contact/etc.)
        // ---------------------------------------------------

        // Fetch Account Owner (setup object created above)
        User acctOwner = [SELECT Id FROM User WHERE Alias = 'aown' LIMIT 1];

        // Base metadata
        Program prog = TestDataFactory.testProgram();
        AcademicYear ay = TestDataFactory.testAcademicYear();
        AcademicSession sess = TestDataFactory.testAcademicSession();
        AcademicTerm term = TestDataFactory.testAcademicTerm(prog.Id);
        Learning lrn = TestDataFactory.testLearning();
        LearningCourse lc = TestDataFactory.testLearningCourse(lrn.Id);
        CourseOffering offering = TestDataFactory.testCourseOffering(lc.Id, sess.Id, prog.Id, term.Id, null, null);

        // Student Account must be owned by role user
        Account acc = new Account(Name = 'Student Account', OwnerId = acctOwner.Id);
        insert acc;

        Contact student = TestDataFactory.testContact(acc.Id);

        // ---------------------------------------------------
        // STEP C: Create portal user (setup object) in runAs again
        // after Contact exists
        // ---------------------------------------------------
        User runner1 = [SELECT Id FROM User WHERE Alias = 'runr' LIMIT 1];

        System.runAs(runner1) {
            User portalUser = TestDataFactory.testPortalUser(student, 'Customer Community Plus User');

            // make portal user query deterministic
            try {
                portalUser.Alias = PORTAL_ALIAS;
                update portalUser;
            } catch (Exception e) {
                // If Alias can't be updated, set alias in factory instead.
            }
        }

        // Get portal user for ownership
        User portalUser = [SELECT Id FROM User WHERE Alias = :PORTAL_ALIAS LIMIT 1];

        // Program Enrollment (insert with final values; avoid update)
        ProgramEnrollment pe = new ProgramEnrollment(
            ContactId = student.Id,
            ProgramId = prog.Id,
            Status = 'Registered',
            OwnerId = portalUser.Id
        );
        insert pe;

        AcademicTermEnrollment ate =
            TestDataFactory.createAcademicTermEnrollment(term.Id, student.Id, portalUser.Id);

        TestDataFactory.createEnrollmentSession(pe.Id, sess.Id, 'Registered');

        CourseOfferingParticipant cop = new CourseOfferingParticipant(
            CourseOfferingId = offering.Id,
            ParticipantContactId = student.Id,
            AcademicTermEnrollmentId = ate.Id,
            ParticipationStatus = 'Enrolled',
            OwnerId = portalUser.Id
        );
        insert cop;

        CourseOfferingPtcpResult res = new CourseOfferingPtcpResult(
            CourseOfferingParticipantId = cop.Id,
            Grade_Letter__c = 'A',
            LetterGrade = 'A',
            NumericGrade = 4.0,
            Marks_Percentage__c = 95,
            UnitsEarned = 3
        );
        insert res;
    }

    // -----------------------
    // Tests
    // -----------------------
    @IsTest
    static void testGetProgramEnrollments_success() {
        User u = [SELECT Id FROM User WHERE Alias = :PORTAL_ALIAS LIMIT 1];
        System.runAs(u) {
            Test.startTest();
            Map<String, Object> result = StudentProgramCoursesController.getProgramEnrollments();
            Test.stopTest();

            List<Object> current = (List<Object>) result.get('currentEnrollments');
            System.assertNotEquals(null, current);
            System.assert(current.size() > 0, 'User should see Registered enrollment');
        }
    }

    @IsTest
    static void testGetStudentCourses_success() {
        User u = [SELECT Id FROM User WHERE Alias = :PORTAL_ALIAS LIMIT 1];
        System.runAs(u) {
            Test.startTest();
            List<Map<String, Object>> courses = StudentProgramCoursesController.getStudentCourses();
            Test.stopTest();

            System.assertNotEquals(null, courses);
            System.assertEquals(1, courses.size(), 'User should see 1 enrolled course');
        }
    }

    @IsTest
    static void testGetStudentGrades_success() {
        User u = [SELECT Id FROM User WHERE Alias = :PORTAL_ALIAS LIMIT 1];
        System.runAs(u) {
            Test.startTest();
            List<Map<String, Object>> grades = StudentProgramCoursesController.getStudentGrades();
            Test.stopTest();

            System.assertEquals(1, grades.size(), 'User should see their grade record');
            System.assertEquals('A', (String)grades[0].get('letterGrade'));
        }
    }

    @IsTest
    static void testGetEnrollmentSessions_success() {
        ProgramEnrollment pe = [SELECT Id FROM ProgramEnrollment LIMIT 1];

        Test.startTest();
        List<Map<String, Object>> sessions = StudentProgramCoursesController.getEnrollmentSessions(pe.Id);
        Test.stopTest();

        System.assertNotEquals(0, sessions.size());
    }

    @IsTest
    static void testGetProgramEnrollments_noContact_exception() {
        User u = TestDataFactory.testUser('nocont', 'nocont@test.com');
        System.runAs(u) {
            Test.startTest();
            Boolean thrown = false;
            try {
                StudentProgramCoursesController.getProgramEnrollments();
            } catch (AuraHandledException e) {
                thrown = true;
            }
            Test.stopTest();
            System.assert(thrown);
        }
    }
}