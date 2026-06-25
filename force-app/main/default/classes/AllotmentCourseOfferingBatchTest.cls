@isTest
public class AllotmentCourseOfferingBatchTest {

    @testSetup
    static void setupTestData() {

        // Programs
        Program pgp = new Program(Name = 'Post Graduate Programme in Management');
        Program nonPgp = new Program(Name = 'Executive Programme');
        insert new List<Program>{ pgp, nonPgp };

        // Location
        Schema.Location loc = new Schema.Location(
            Name        = 'Hyderabad Campus',
            LocationType = 'Campus'
        );
        insert loc;

        // Learnings
        Learning learn1 = new Learning(Name = 'Test Learning 1');
        Learning learn2 = new Learning(Name = 'Test Learning 2');
        insert new List<Learning>{ learn1, learn2 };

        // Learning Courses
        LearningCourse lc1 = new LearningCourse(Name = 'Finance 101', LearningId = learn1.Id);
        LearningCourse lc2 = new LearningCourse(Name = 'Marketing 201', LearningId = learn2.Id);
        insert new List<LearningCourse>{ lc1, lc2 };

        // Academic Year + Term + Session
        AcademicYear ay = new AcademicYear(Name = '2026');
        insert ay;

        AcademicTerm at1 = new AcademicTerm(Name = 'Term 1');
        insert at1;

        // AcademicSession now requires ISB_External_Id__c so the batch can resolve it via lookup
        AcademicSession sess = new AcademicSession(
            Name                = 'Session A',
            AcademicTermId      = at1.Id,
            Location__c         = loc.Id,
            IsActive            = true,
            ISB_External_Id__c  = 'Session A' + loc.Id + at1.Id
        );
        insert sess;

        Id facultyRecordTypeId = Schema.SObjectType.Contact.getRecordTypeInfosByName().get('Faculty').getRecordTypeId();

        // Faculty Contacts
        Contact fac1 = new Contact(
            LastName = 'Faculty Alpha',
            Contact_Role__c = 'Academic Associate',
            hed__Preferred_Email__c = 'VF Email ID',
            VF_Email_ID__c = 'bodhtree.admin@isb.com',
            RecordTypeId = facultyRecordTypeId
        );
        Contact fac2 = new Contact(
            LastName = 'Faculty Beta',
            Contact_Role__c = 'Academic Associate',
            hed__Preferred_Email__c = 'VF Email ID',
            VF_Email_ID__c = 'bodhtree2.admin@isb.com',
            RecordTypeId = facultyRecordTypeId
        );
        insert new List<Contact>{ fac1, fac2 };

        // SCENARIO 1: Brand-new Lineup (Create)
        // a1 and a2 share LINEUP-CREATE — values will be merged on the CO
        Allotment__c a1 = new Allotment__c(
            Name                          = 'Allot Row 1',
            ISB_Line_Up_ID__c             = 'LINEUP-CREATE',
            Sync_Status__c                = 'Pending',
            Program__c                    = nonPgp.Id,
            Course__c                     = lc1.Id,
            Location__c                   = loc.Id,
            Academic_Year__c              = ay.Id,
            Academic_Cohort__c            = at1.Id,
            Academic_Terms_Session__c     = sess.Id,
            Faculty__c                    = fac1.Id,
            Preferred_Sessions2__c        = '1-2,3-4',
            Area__c                       = 'Finance',
            Course_Type__c                = 'Core',
            ISB_Sessions__c               = '10',
            Section_Number__c             = 'A',
            Status__c                     = 'Accepted',
            Teaching_Location_P__c        = 'Hyderabad',
            Teaching_Date__c              = Date.today(),
            Teaching_Dates__c             = 'Mon-Fri',
            Term_Start_Date__c            = Date.today(),
            Term_To_Date__c               = Date.today().addMonths(3),
            Industry_Specialization_p__c  = 'Manufacturing',        // valid picklist value
            Concentration_p__c            = 'Strategy and Leadership' // valid picklist value
        );

        Allotment__c a2 = new Allotment__c(
            Name                          = 'Allot Row 2',
            ISB_Line_Up_ID__c             = 'LINEUP-CREATE',
            Sync_Status__c                = 'Pending',
            Program__c                    = nonPgp.Id,
            Course__c                     = lc1.Id,
            Location__c                   = loc.Id,
            Academic_Cohort__c            = at1.Id,
            Academic_Terms_Session__c     = sess.Id,
            Faculty__c                    = fac2.Id,
            Preferred_Sessions2__c        = '5-6;7-8',
            Industry_Specialization_p__c  = 'Public Policy',        // valid picklist value — different from a1
            Concentration_p__c            = 'Operations Management'  // valid picklist value — different from a1
        );

        // SCENARIO 2: Update path
        // a3 is the only pending allotment for LINEUP-UPDATE
        // existingCo already exists — batch will update it
        // new field values come only from a3, no seeding from existingCo
        Allotment__c a3 = new Allotment__c(
            Name                          = 'Allot Row 3 (Update)',
            ISB_Line_Up_ID__c             = 'LINEUP-UPDATE',
            Sync_Status__c                = 'Pending',
            Program__c                    = nonPgp.Id,
            Course__c                     = lc1.Id,
            Location__c                   = loc.Id,
            Academic_Cohort__c            = at1.Id,
            Academic_Terms_Session__c     = sess.Id,
            Faculty__c                    = fac1.Id,
            Preferred_Sessions2__c        = '6-10',
            Industry_Specialization_p__c  = 'Infrastructure',       // valid picklist value
            Concentration_p__c            = 'Entrepreneurship;Operations Management' // two valid values
        );

        // SCENARIO 3: PGP new course
        Allotment__c a4 = new Allotment__c(
            Name                      = 'Allot Row 4 (PGP new course)',
            ISB_Line_Up_ID__c         = 'LINEUP-PGP',
            Sync_Status__c            = 'Pending',
            Program__c                = pgp.Id,
            Course__c                 = lc2.Id,
            Location__c               = loc.Id,
            Academic_Cohort__c        = at1.Id,
            Academic_Terms_Session__c = sess.Id,
            Faculty__c                = fac1.Id
        );

        // SCENARIO 4: No Faculty
        Allotment__c a5 = new Allotment__c(
            Name                      = 'Allot Row 5 (No Faculty)',
            ISB_Line_Up_ID__c         = 'LINEUP-NOFAC',
            Sync_Status__c            = 'Pending',
            Program__c                = nonPgp.Id,
            Course__c                 = lc1.Id,
            Location__c               = loc.Id,
            Academic_Cohort__c        = at1.Id,
            Academic_Terms_Session__c = sess.Id
        );

        // SCENARIO 5: Retry status
        Allotment__c a6 = new Allotment__c(
            Name                      = 'Allot Row 6 (Retry)',
            ISB_Line_Up_ID__c         = 'LINEUP-RETRY',
            Sync_Status__c            = 'Retry',
            Program__c                = nonPgp.Id,
            Course__c                 = lc1.Id,
            Location__c               = loc.Id,
            Academic_Cohort__c        = at1.Id,
            Academic_Terms_Session__c = sess.Id,
            Faculty__c                = fac2.Id,
            Preferred_Sessions2__c    = '9-10'
        );

        insert new List<Allotment__c>{ a1, a2, a3, a4, a5, a6 };

        // Existing CourseOffering for update scenario
        // Industry_Specialization_p__c and Concentration_p__c intentionally NOT set
        // because we no longer seed from existingCo for these fields
        CourseOffering existingCo = new CourseOffering(
            Name                   = 'Existing CO',
            ISB_Line_Up_ID__c      = 'LINEUP-UPDATE',
            Preferred_Sessions2__c = '1-5',
            LearningCourseId       = lc1.Id,
            AcademicSessionId      = sess.Id
        );

        CourseOffering pgpOldCo = new CourseOffering(
            Name              = 'PGP Old CO',
            ISB_Line_Up_ID__c = 'LINEUP-PGP',
            LearningCourseId  = lc1.Id,
            AcademicSessionId = sess.Id
        );

        insert new List<CourseOffering>{ existingCo, pgpOldCo };

        // Pre-existing faculty link (dedup test)
        Course_Faculty__c existingCf = new Course_Faculty__c(
            Course_Offering__c = existingCo.Id,
            Faculty__c         = fac1.Id,
            Name               = 'Faculty Alpha'
        );
        insert existingCf;
    }

    @isTest
    static void testFullBatchExecution() {
        Test.startTest();
        AllotmentCourseOfferingBatch batch = new AllotmentCourseOfferingBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();

        // Check for silent errors
        List<Allotment__c> errorRows = [
            SELECT Id, ISB_Line_Up_ID__c, Error_Message__c, Sync_Status__c
            FROM Allotment__c
            WHERE Sync_Status__c = 'Error'
        ];
        String errorInfo = '';
        for (Allotment__c er : errorRows) {
            errorInfo += er.ISB_Line_Up_ID__c + ' => ' + er.Error_Message__c + '; ';
        }

        // Verify Scenario 2: UPDATE path + faculty dedup
        CourseOffering co2 = [
            SELECT Id, Preferred_Sessions2__c, Academic_Term__c
            FROM CourseOffering
            WHERE ISB_Line_Up_ID__c = 'LINEUP-UPDATE'
            LIMIT 1
        ];
        System.assert(co2.Preferred_Sessions2__c.contains('1-5'), 'Existing session should be preserved');
        System.assert(co2.Preferred_Sessions2__c.contains('6-10'), 'New session should be merged in');

        AcademicTerm at1 = [SELECT Id FROM AcademicTerm WHERE Name = 'Term 1' LIMIT 1];
        System.assertEquals(at1.Id, co2.Academic_Term__c, 'Academic Term should be stamped on the Course Offering');

        Integer facCount2 = [SELECT COUNT() FROM Course_Faculty__c WHERE Course_Offering__c = :co2.Id];
        System.assertEquals(1, facCount2, 'Faculty dedup should prevent duplicate');

        
        CourseOffering co1 = [
            SELECT Id, Industry_Specialization_p__c, Concentration_p__c
            FROM CourseOffering
            WHERE ISB_Line_Up_ID__c = 'LINEUP-CREATE'
            LIMIT 1
        ];

        System.assertEquals(
        'Public Policy;Manufacturing',
        co1.Industry_Specialization_p__c
        );
        System.assertEquals(
            'Strategy and Leadership;Operations Management',
            co1.Concentration_p__c
        );

        // Verify Scenario 2: UPDATE path — only pending allotment values, no seeding from existingCo
        // a3: Industry=Infrastructure, Concentration=Entrepreneurship;Operations Management
        // Entrepreneurship comes before Operations Management alphabetically
        CourseOffering co2WithNewFields = [
            SELECT Id, Industry_Specialization_p__c, Concentration_p__c
            FROM CourseOffering
            WHERE ISB_Line_Up_ID__c = 'LINEUP-UPDATE'
            LIMIT 1
        ];
        System.assertEquals(
            'Infrastructure',
            co2WithNewFields.Industry_Specialization_p__c,
            'Only a3 Infrastructure value should be present, existing CO value not seeded'
        );
       Set<String> actualValues = new Set<String>(
    co2WithNewFields.Concentration_p__c.split(';')
);

    System.assertEquals(
    new Set<String>{'Entrepreneurship', 'Operations Management'},
    actualValues
);

        // Verify Scenario 3: PGP override
        List<CourseOffering> co3 = [
            SELECT Id
            FROM CourseOffering
            WHERE ISB_Line_Up_ID__c = 'LINEUP-PGP'
        ];
        System.assertEquals(2, co3.size(), 'PGP with changed course should create a 2nd CO');

        // Verify Scenario 4: No-faculty path
        List<CourseOffering> co4 = [
            SELECT Id
            FROM CourseOffering
            WHERE ISB_Line_Up_ID__c = 'LINEUP-NOFAC'
        ];
        System.assertEquals(1, co4.size(), 'CO should still be created even without faculty');
        Integer facCount4 = [SELECT COUNT() FROM Course_Faculty__c WHERE Course_Offering__c = :co4[0].Id];
        System.assertEquals(0, facCount4, 'No faculty records should be created');

        // Verify Scenario 5: Retry status picked up
        List<CourseOffering> co5 = [
            SELECT Id
            FROM CourseOffering
            WHERE ISB_Line_Up_ID__c = 'LINEUP-RETRY'
        ];
        System.assertEquals(1, co5.size(), 'Retry-status allotments should be processed');

        // Verify all staging rows moved out of Pending/Retry
        Integer pendingCount = [
            SELECT COUNT()
            FROM Allotment__c
            WHERE Sync_Status__c IN ('Pending', 'Retry')
        ];
        System.assertEquals(0, pendingCount, 'All staging rows should be synced');
    }

    @isTest
    static void testScheduler() {
        Test.startTest();
        String cronExp = '0 0 0 * * ?';
        String jobId = System.schedule(
            'Test Allotment Sync',
            cronExp,
            new AllotmentCourseOfferingScheduler()
        );
        Test.stopTest();
        System.assertNotEquals(null, jobId, 'Scheduled job should return a valid ID');
    }

    @isTest
    static void testHelperUtilities() {
        List<Allotment__c> emptyRows = new List<Allotment__c>();
        emptyRows.add(new Allotment__c(Preferred_Sessions2__c = null));
        emptyRows.add(new Allotment__c(Preferred_Sessions2__c = ''));
        String result1 = AllotmentCourseOfferingHelper.mergeFinalSessions(null, emptyRows);
        System.assertEquals('', result1, 'Blank inputs should return empty string');

        List<Allotment__c> mixedRows = new List<Allotment__c>();
        mixedRows.add(new Allotment__c(Preferred_Sessions2__c = '3-4,1-2'));
        mixedRows.add(new Allotment__c(Preferred_Sessions2__c = '1-2;5-6'));
        String result2 = AllotmentCourseOfferingHelper.mergeFinalSessions('7-8', mixedRows);
        System.assertEquals('1-2,3-4,5-6,7-8', result2, 'Should sort, dedup, and merge');

        System.assertEquals(null, AllotmentCourseOfferingHelper.truncateError(null, 255));
        System.assertEquals('short', AllotmentCourseOfferingHelper.truncateError('short', 255));

        String longMsg = '';
        for (Integer i = 0; i < 300; i++) { longMsg += 'X'; }
        String truncated = AllotmentCourseOfferingHelper.truncateError(longMsg, 255);
        System.assertEquals(255, truncated.length(), 'Should be truncated to 255');

        List<Allotment__c> blankLineupRows = new List<Allotment__c>();
        blankLineupRows.add(new Allotment__c(ISB_Line_Up_ID__c = null));
        blankLineupRows.add(new Allotment__c(ISB_Line_Up_ID__c = ''));
        blankLineupRows.add(new Allotment__c(ISB_Line_Up_ID__c = 'VALID'));
        Map<String, List<Allotment__c>> grouped = AllotmentCourseOfferingHelper.groupByLineup(blankLineupRows);
        System.assertEquals(1, grouped.size(), 'Only non-blank lineups should be grouped');
        System.assert(grouped.containsKey('VALID'), 'Should contain VALID key');
    }

    @isTest
    static void testMissingCourseSkipsLineup() {
        AcademicSession sess = [SELECT Id FROM AcademicSession LIMIT 1];
        Program nonPgp = [SELECT Id FROM Program WHERE Name = 'Executive Programme' LIMIT 1];
        AcademicTerm at = [SELECT Id FROM AcademicTerm LIMIT 1];
        Schema.Location loc = [SELECT Id FROM Location WHERE Name = 'Hyderabad Campus' LIMIT 1];

        Allotment__c noCourse = new Allotment__c(
            Name                      = 'No Course Allotment',
            ISB_Line_Up_ID__c         = 'LINEUP-NOCOURSE',
            Sync_Status__c            = 'Pending',
            Program__c                = nonPgp.Id,
            Location__c               = loc.Id,
            Academic_Cohort__c        = at.Id,
            Academic_Terms_Session__c = sess.Id
        );
        insert noCourse;

        Test.startTest();
        AllotmentCourseOfferingBatch batch = new AllotmentCourseOfferingBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();

        Integer coCount = [SELECT COUNT() FROM CourseOffering WHERE ISB_Line_Up_ID__c = 'LINEUP-NOCOURSE'];
        System.assertEquals(0, coCount, 'No CourseOffering should be created when Course is missing');
    }

    @isTest
    static void testExecuteWithEmptyScope() {
        AllotmentCourseOfferingBatch batch = new AllotmentCourseOfferingBatch();
        batch.execute(null, null);
        batch.execute(null, new List<String>());
        batch.execute(null, new List<String>{ 'NONEXISTENT-LINEUP' });
        batch.finish(null);
    }

    // ── Replaces old testSessionTermMismatchAndLocationUpdates() ────────────
    // Old test validated that the batch CREATED a new AcademicSession when no
    // exact Name+Term+Location match existed. The batch no longer creates
    // AcademicSession records — it only looks them up via ISB_External_Id__c.
    // This test validates that lookup-and-resolve behavior instead.
    @isTest
    static void testSessionResolutionViaExternalId() {
        Program pgp = [SELECT Id FROM Program WHERE Name = 'Post Graduate Programme in Management' LIMIT 1];
        LearningCourse lc = [SELECT Id FROM LearningCourse LIMIT 1];
        AcademicTerm at1 = [SELECT Id FROM AcademicTerm WHERE Name = 'Term 1' LIMIT 1];

        Schema.Location loc2 = new Schema.Location(Name = 'Mohali Campus', LocationType = 'Campus');
        insert loc2;

        // The session that SHOULD be resolved to, identified purely by ISB_External_Id__c
        String expectedExtId = 'Session Match Test' + loc2.Id + at1.Id;
        AcademicSession matchingSession = new AcademicSession(
            Name                = 'Session Match Test',
            AcademicTermId      = at1.Id,
            Location__c         = loc2.Id,
            IsActive            = true,
            ISB_External_Id__c  = expectedExtId
        );
        insert matchingSession;

        // The allotment references a DIFFERENT session record by Id (no term/location set),
        // but its Name + Location__c + Academic_Cohort__c combo should resolve via external ID
        // to matchingSession.
        AcademicSession referencedSession = new AcademicSession(
            Name     = 'Session Match Test',
            IsActive = true
        );
        insert referencedSession;

        Allotment__c a1 = new Allotment__c(
            Name                      = 'Allot External ID Match',
            ISB_Line_Up_ID__c         = 'LINEUP-EXTID-MATCH',
            Sync_Status__c            = 'Pending',
            Program__c                = pgp.Id,
            Course__c                 = lc.Id,
            Location__c               = loc2.Id,
            Academic_Cohort__c        = at1.Id,
            Academic_Terms_Session__c = referencedSession.Id
        );
        insert a1;

        Test.startTest();
        Database.executeBatch(new AllotmentCourseOfferingBatch(), 200);
        Test.stopTest();

        CourseOffering co = [
            SELECT AcademicSessionId
            FROM CourseOffering
            WHERE ISB_Line_Up_ID__c = 'LINEUP-EXTID-MATCH'
            LIMIT 1
        ];
        System.assertEquals(matchingSession.Id, co.AcademicSessionId,
            'CourseOffering should resolve to the session found via ISB_External_Id__c');
    }

    @isTest
    static void testSessionResolutionNoMatchFallsBack() {
        Program pgp = [SELECT Id FROM Program WHERE Name = 'Post Graduate Programme in Management' LIMIT 1];
        LearningCourse lc = [SELECT Id FROM LearningCourse LIMIT 1];
        AcademicTerm at1 = [SELECT Id FROM AcademicTerm WHERE Name = 'Term 1' LIMIT 1];
        Schema.Location loc = [SELECT Id FROM Location WHERE Name = 'Hyderabad Campus' LIMIT 1];

        // No ISB_External_Id__c set — will never match anything built by the batch
        AcademicSession orphanSession = new AcademicSession(
            Name     = 'No External Id Session',
            IsActive = true
        );
        insert orphanSession;

        Integer sessionCountBefore = [SELECT COUNT() FROM AcademicSession];

        Allotment__c a1 = new Allotment__c(
            Name                      = 'Allot No Match',
            ISB_Line_Up_ID__c         = 'LINEUP-NO-MATCH',
            Sync_Status__c            = 'Pending',
            Program__c                = pgp.Id,
            Course__c                 = lc.Id,
            Location__c               = loc.Id,
            Academic_Cohort__c        = at1.Id,
            Academic_Terms_Session__c = orphanSession.Id
        );
        insert a1;

        Test.startTest();
        Database.executeBatch(new AllotmentCourseOfferingBatch(), 200);
        Test.stopTest();

        Integer sessionCountAfter = [SELECT COUNT() FROM AcademicSession];
        System.assertEquals(sessionCountBefore, sessionCountAfter,
            'No new AcademicSession should ever be created by the batch');

        CourseOffering co = [
            SELECT AcademicSessionId
            FROM CourseOffering
            WHERE ISB_Line_Up_ID__c = 'LINEUP-NO-MATCH'
            LIMIT 1
        ];
        System.assertEquals(orphanSession.Id, co.AcademicSessionId,
            'Should fall back to the original academicSessionId when no external ID match is found');
    }
}