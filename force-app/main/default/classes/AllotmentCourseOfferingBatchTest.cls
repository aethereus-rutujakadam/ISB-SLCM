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

        AcademicSession sess = new AcademicSession(Name = 'Session A', IsActive = true);
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
        Allotment__c a1 = new Allotment__c(
            Name                     = 'Allot Row 1',
            ISB_Line_Up_ID__c        = 'LINEUP-CREATE',
            Sync_Status__c           = 'Pending',
            Program__c               = nonPgp.Id,
            Course__c                = lc1.Id,
            Location__c              = loc.Id,
            Academic_Year__c         = ay.Id,
            Academic_Cohort__c       = at1.Id,
            Academic_Terms_Session__c = sess.Id,
            Faculty__c               = fac1.Id,
            Preferred_Sessions2__c   = '1-2,3-4',
            Area__c                  = 'Finance',
            Course_Type__c           = 'Core',
            ISB_Sessions__c          = '10',
            Section_Number__c        = 'A',
            Status__c                = 'Accepted',
            Teaching_Location_P__c   = 'Hyderabad',
            Teaching_Date__c         = Date.today(),
            Teaching_Dates__c        = 'Mon-Fri',
            Term_Start_Date__c       = Date.today(),
            Term_To_Date__c          = Date.today().addMonths(3)
        );

        Allotment__c a2 = new Allotment__c(
            Name                     = 'Allot Row 2',
            ISB_Line_Up_ID__c        = 'LINEUP-CREATE',
            Sync_Status__c           = 'Pending',
            Program__c               = nonPgp.Id,
            Course__c                = lc1.Id,
            Location__c              = loc.Id,
            Academic_Cohort__c       = at1.Id,
            Academic_Terms_Session__c = sess.Id,
            Faculty__c               = fac2.Id,
            Preferred_Sessions2__c   = '5-6;7-8'
        );

        // SCENARIO 2: Update path
        Allotment__c a3 = new Allotment__c(
            Name                     = 'Allot Row 3 (Update)',
            ISB_Line_Up_ID__c        = 'LINEUP-UPDATE',
            Sync_Status__c           = 'Pending',
            Program__c               = nonPgp.Id,
            Course__c                = lc1.Id,
            Location__c              = loc.Id,
            Academic_Cohort__c       = at1.Id,
            Academic_Terms_Session__c = sess.Id,
            Faculty__c               = fac1.Id,
            Preferred_Sessions2__c   = '6-10'
        );

        // SCENARIO 3: PGP new course
        Allotment__c a4 = new Allotment__c(
            Name                     = 'Allot Row 4 (PGP new course)',
            ISB_Line_Up_ID__c        = 'LINEUP-PGP',
            Sync_Status__c           = 'Pending',
            Program__c               = pgp.Id,
            Course__c                = lc2.Id,
            Location__c              = loc.Id,
            Academic_Cohort__c       = at1.Id,
            Academic_Terms_Session__c = sess.Id,
            Faculty__c               = fac1.Id
        );

        // SCENARIO 4: No Faculty
        Allotment__c a5 = new Allotment__c(
            Name                     = 'Allot Row 5 (No Faculty)',
            ISB_Line_Up_ID__c        = 'LINEUP-NOFAC',
            Sync_Status__c           = 'Pending',
            Program__c               = nonPgp.Id,
            Course__c                = lc1.Id,
            Location__c              = loc.Id,
            Academic_Cohort__c       = at1.Id,
            Academic_Terms_Session__c = sess.Id
        );

        // SCENARIO 5: Retry status
        Allotment__c a6 = new Allotment__c(
            Name                     = 'Allot Row 6 (Retry)',
            ISB_Line_Up_ID__c        = 'LINEUP-RETRY',
            Sync_Status__c           = 'Retry',
            Program__c               = nonPgp.Id,
            Course__c                = lc1.Id,
            Location__c              = loc.Id,
            Academic_Cohort__c       = at1.Id,
            Academic_Terms_Session__c = sess.Id,
            Faculty__c               = fac2.Id,
            Preferred_Sessions2__c   = '9-10'
        );

        // Bulk insert all Allotments in one DML
        insert new List<Allotment__c>{ a1, a2, a3, a4, a5, a6 };

        // Existing CourseOfferings for update + PGP scenarios
        CourseOffering existingCo = new CourseOffering(
            Name               = 'Existing CO',
            ISB_Line_Up_ID__c  = 'LINEUP-UPDATE',
            Preferred_Sessions2__c = '1-5',
            LearningCourseId   = lc1.Id,
            AcademicSessionId  = sess.Id
        );

        CourseOffering pgpOldCo = new CourseOffering(
            Name               = 'PGP Old CO',
            ISB_Line_Up_ID__c  = 'LINEUP-PGP',
            LearningCourseId   = lc1.Id,
            AcademicSessionId  = sess.Id
        );

        // Bulk insert CourseOfferings in one DML
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
        // mergeFinalSessions with empty existing + blank rows
        List<Allotment__c> emptyRows = new List<Allotment__c>();
        emptyRows.add(new Allotment__c(Preferred_Sessions2__c = null));
        emptyRows.add(new Allotment__c(Preferred_Sessions2__c = ''));
        String result1 = AllotmentCourseOfferingHelper.mergeFinalSessions(null, emptyRows);
        System.assertEquals('', result1, 'Blank inputs should return empty string');

        // mergeFinalSessions with existing value + new values including duplicates
        List<Allotment__c> mixedRows = new List<Allotment__c>();
        mixedRows.add(new Allotment__c(Preferred_Sessions2__c = '3-4,1-2'));
        mixedRows.add(new Allotment__c(Preferred_Sessions2__c = '1-2;5-6'));
        String result2 = AllotmentCourseOfferingHelper.mergeFinalSessions('7-8', mixedRows);
        System.assertEquals('1-2,3-4,5-6,7-8', result2, 'Should sort, dedup, and merge');

        // truncateError
        System.assertEquals(null, AllotmentCourseOfferingHelper.truncateError(null, 255));
        System.assertEquals('short', AllotmentCourseOfferingHelper.truncateError('short', 255));

        String longMsg = '';
        for (Integer i = 0; i < 300; i++) { longMsg += 'X'; }
        String truncated = AllotmentCourseOfferingHelper.truncateError(longMsg, 255);
        System.assertEquals(255, truncated.length(), 'Should be truncated to 255');

        // groupByLineup with blank lineup
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
        // Create an Allotment with no Course__c – batch should skip it entirely
        AcademicSession sess = [SELECT Id FROM AcademicSession LIMIT 1];
        Program nonPgp = [SELECT Id FROM Program WHERE Name = 'Executive Programme' LIMIT 1];
        AcademicTerm at = [SELECT Id FROM AcademicTerm LIMIT 1];
        Schema.Location loc = [SELECT Id FROM Location WHERE Name = 'Hyderabad Campus' LIMIT 1];

        Allotment__c noCourse = new Allotment__c(
            Name                     = 'No Course Allotment',
            ISB_Line_Up_ID__c        = 'LINEUP-NOCOURSE',
            Sync_Status__c           = 'Pending',
            Program__c               = nonPgp.Id,
            Location__c              = loc.Id,
            Academic_Cohort__c       = at.Id,
            Academic_Terms_Session__c = sess.Id
            // Course__c intentionally omitted
        );
        insert noCourse;

        Test.startTest();
        AllotmentCourseOfferingBatch batch = new AllotmentCourseOfferingBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();

        Allotment__c result = [
            SELECT Sync_Status__c, Error_Message__c
            FROM Allotment__c
            WHERE ISB_Line_Up_ID__c = 'LINEUP-NOCOURSE'
            LIMIT 1
        ];
        

        // No CourseOffering should have been created for this lineup
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
    
    @isTest
    static void testSessionTermMismatchAndLocationUpdates() {
        Program pgp = [SELECT Id FROM Program WHERE Name = 'Post Graduate Programme in Management' LIMIT 1];
        LearningCourse lc = [SELECT Id FROM LearningCourse LIMIT 1];
        AcademicTerm at1 = [SELECT Id, Name FROM AcademicTerm WHERE Name = 'Term 1' LIMIT 1];
        
        AcademicTerm at2 = new AcademicTerm(Name = 'Term 2');
        insert at2;
        
        Schema.Location loc1 = [SELECT Id FROM Location WHERE Name = 'Hyderabad Campus' LIMIT 1];
        Schema.Location loc2 = new Schema.Location(Name = 'Mohali Campus', LocationType = 'Campus');
        insert loc2;
        
        // Session 1: Term 1, Location 1
        AcademicSession sess1 = new AcademicSession(Name = 'Session Term Mismatch Test', AcademicTermId = at1.Id, Location__c = loc1.Id, IsActive = true);
        insert sess1;

        // Existing Alternative Session
        AcademicSession existingAltSess = new AcademicSession(Name = 'Sess Existing Alt', AcademicTermId = at2.Id, Location__c = loc1.Id, IsActive = true);
        insert existingAltSess;

        AcademicSession origSess = new AcademicSession(Name = 'Sess Existing Alt', AcademicTermId = at1.Id, IsActive = true);
        insert origSess;
        
        // Scenario A: Same term, different location -> Should create alternate session (not update sess1)
        Allotment__c a1 = new Allotment__c(
            Name                     = 'Allot Same Term Diff Loc',
            ISB_Line_Up_ID__c        = 'LINEUP-SESS-UPD',
            Sync_Status__c           = 'Pending',
            Program__c               = pgp.Id,
            Course__c                = lc.Id,
            Location__c              = loc2.Id, 
            Academic_Cohort__c       = at1.Id, 
            Academic_Terms_Session__c = sess1.Id,
            Term_Start_Date__c       = Date.today().addDays(1),
            Term_To_Date__c          = Date.today().addDays(10)
        );
        
        // Scenario B: Different term -> Should create alternative session
        Allotment__c a2 = new Allotment__c(
            Name                     = 'Allot Diff Term',
            ISB_Line_Up_ID__c        = 'LINEUP-SESS-ALT',
            Sync_Status__c           = 'Pending',
            Program__c               = pgp.Id,
            Course__c                = lc.Id,
            Location__c              = loc2.Id,
            Academic_Cohort__c       = at2.Id, 
            Academic_Terms_Session__c = sess1.Id,
            Term_Start_Date__c       = Date.today().addDays(5),
            Term_To_Date__c          = Date.today().addDays(15)
        );

        // Scenario C: Different term with same name already present at another location.
        // Should resolve/create the location-specific session and map offering lookup to it.
        Allotment__c a3 = new Allotment__c(
            Name                     = 'Allot Diff Term Existing Alt',
            ISB_Line_Up_ID__c        = 'LINEUP-SESS-PREALT',
            Sync_Status__c           = 'Pending',
            Program__c               = pgp.Id,
            Course__c                = lc.Id,
            Location__c              = loc2.Id,
            Academic_Cohort__c       = at2.Id, 
            Academic_Terms_Session__c = origSess.Id,
            Term_Start_Date__c       = Date.today().addDays(2),
            Term_To_Date__c          = Date.today().addDays(20)
        );
        
        insert new List<Allotment__c>{ a1, a2, a3 };

        // PRE-CONDITION: Create an existing CourseOffering for LINEUP-SESS-ALT 
        // to force the batch to hit the "update existing" logic instead of "create new"
        CourseOffering preExistingAltCO = new CourseOffering(
            Name              = 'Pre Existing Alt CO',
            ISB_Line_Up_ID__c = 'LINEUP-SESS-ALT',
            LearningCourseId  = lc.Id,
            AcademicSessionId = sess1.Id // Initially tied to the wrong/old session!
        );
        insert preExistingAltCO;
        
        Test.startTest();
        AllotmentCourseOfferingBatch batch = new AllotmentCourseOfferingBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();
        
        // Verification A
        AcademicSession unchangedSess1 = [SELECT Id, Location__c, From_Date__c, To_date__c FROM AcademicSession WHERE Id = :sess1.Id];
        System.assertEquals(loc1.Id, unchangedSess1.Location__c, 'Original session location should remain unchanged');

        List<AcademicSession> sameTermAltSessions = [
            SELECT Id, Name, AcademicTermId, Location__c, From_Date__c, To_date__c
            FROM AcademicSession
            WHERE Name = 'Session Term Mismatch Test' AND AcademicTermId = :at1.Id AND Location__c = :loc2.Id
        ];
        System.assertEquals(1, sameTermAltSessions.size(), 'Same-term different-location alternate session should be created');
        System.assertEquals(Date.today().addDays(1), sameTermAltSessions[0].From_Date__c, 'Alt session from date should be set');
        System.assertEquals(Date.today().addDays(10), sameTermAltSessions[0].To_date__c, 'Alt session to date should be set');

        CourseOffering coSameTermDiffLoc = [
            SELECT AcademicSessionId, Academic_Term__c, Location__c
            FROM CourseOffering
            WHERE ISB_Line_Up_ID__c = 'LINEUP-SESS-UPD'
            LIMIT 1
        ];
        System.assertEquals(sameTermAltSessions[0].Id, coSameTermDiffLoc.AcademicSessionId,
            'CourseOffering should point to same-term/location-specific session');
        System.assertEquals(at1.Id, coSameTermDiffLoc.Academic_Term__c,
            'CourseOffering should retain requested academic term for same-term scenario');
        
        // Verification B
        List<AcademicSession> altSessions = [
            SELECT Id, Name, AcademicTermId, Location__c, From_Date__c, To_date__c
            FROM AcademicSession 
            WHERE Name = 'Session Term Mismatch Test' AND AcademicTermId = :at2.Id AND Location__c = :loc2.Id
        ];
        System.assertEquals(1, altSessions.size(), 'Alternative session should have been created');
        System.assertEquals(loc2.Id, altSessions[0].Location__c, 'Alternative session location should be set');
        System.assertEquals(Date.today().addDays(5), altSessions[0].From_Date__c, 'Alternative session from date should be set');
        System.assertEquals(Date.today().addDays(15), altSessions[0].To_date__c, 'Alternative session to date should be set');
        
        CourseOffering updatedPreExistingAltCO = [SELECT AcademicSessionId, Academic_Term__c FROM CourseOffering WHERE Id = :preExistingAltCO.Id];
        System.assertEquals(altSessions[0].Id, updatedPreExistingAltCO.AcademicSessionId, 'CourseOffering should be moved to the new alternative session');
        System.assertEquals(at2.Id, updatedPreExistingAltCO.Academic_Term__c, 'CourseOffering should be mapped to the new academic term');
        
        // Verification C
        AcademicSession unchangedExistingAlt = [SELECT Id, Location__c, From_Date__c, To_date__c FROM AcademicSession WHERE Id = :existingAltSess.Id];
        System.assertEquals(loc1.Id, unchangedExistingAlt.Location__c,
            'Pre-existing alternate session for another location should remain unchanged');

        List<AcademicSession> preAltLoc2 = [
            SELECT Id, Name, AcademicTermId, Location__c, From_Date__c, To_date__c
            FROM AcademicSession
            WHERE Name = 'Sess Existing Alt' AND AcademicTermId = :at2.Id AND Location__c = :loc2.Id
        ];
        System.assertEquals(1, preAltLoc2.size(),
            'Location-specific alternate session should exist for pre-existing alt name/term pair');
        System.assertEquals(Date.today().addDays(2), preAltLoc2[0].From_Date__c,
            'Location-specific alternate session should use requested from date');
        System.assertEquals(Date.today().addDays(20), preAltLoc2[0].To_date__c,
            'Location-specific alternate session should use requested to date');

        CourseOffering coPreAlt = [
            SELECT AcademicSessionId, Academic_Term__c
            FROM CourseOffering
            WHERE ISB_Line_Up_ID__c = 'LINEUP-SESS-PREALT'
            LIMIT 1
        ];
        System.assertEquals(preAltLoc2[0].Id, coPreAlt.AcademicSessionId,
            'CourseOffering should map to the location-specific alternate session');
        System.assertEquals(at2.Id, coPreAlt.Academic_Term__c,
            'CourseOffering should map to expected academic term for pre-alt scenario');
   
    }
}