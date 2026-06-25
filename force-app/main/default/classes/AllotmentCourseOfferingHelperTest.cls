@isTest
public class AllotmentCourseOfferingHelperTest {

    @testSetup
    static void setupTestData() {
        Id facultyRecordTypeId = Schema.SObjectType.Contact.getRecordTypeInfosByName().get('Faculty').getRecordTypeId();

        Contact fac = new Contact(
            LastName = 'Helper Faculty',
            Contact_Role__c = 'Academic Associate',
            hed__Preferred_Email__c = 'VF Email ID',
            VF_Email_ID__c = 'helper.admin@isb.com',
            RecordTypeId = facultyRecordTypeId
        );
        insert fac;
    }

    @isTest
    static void testGroupByLineup() {
        List<Allotment__c> rows = new List<Allotment__c>();
        rows.add(new Allotment__c(ISB_Line_Up_ID__c = null));
        rows.add(new Allotment__c(ISB_Line_Up_ID__c = ''));
        rows.add(new Allotment__c(ISB_Line_Up_ID__c = 'L1'));
        rows.add(new Allotment__c(ISB_Line_Up_ID__c = 'L1'));
        rows.add(new Allotment__c(ISB_Line_Up_ID__c = 'L2'));

        Map<String, List<Allotment__c>> grouped = AllotmentCourseOfferingHelper.groupByLineup(rows);

        System.assertEquals(2, grouped.size(), 'Should have 2 lineup keys');
        System.assertEquals(2, grouped.get('L1').size(), 'L1 should have 2 rows');
        System.assertEquals(1, grouped.get('L2').size(), 'L2 should have 1 row');
    }

    @isTest
    static void testLoadReferenceData() {
        AcademicSession sess = new AcademicSession(Name = 'Ref Test Session', IsActive = true);
        insert sess;

        Learning learn = new Learning(Name = 'Ref Test Learning');
        insert learn;

        LearningCourse lc = new LearningCourse(Name = 'Ref Test Course', LearningId = learn.Id);
        insert lc;

        CourseOffering co = new CourseOffering(
            Name              = 'Ref Test CO',
            ISB_Line_Up_ID__c = 'REFTEST-LINEUP',
            LearningCourseId  = lc.Id,
            AcademicSessionId = sess.Id
        );
        insert co;

        List<Allotment__c> rows = new List<Allotment__c>();
        rows.add(new Allotment__c(
            Academic_Terms_Session__c = String.valueOf(sess.Id),
            ISB_Line_Up_ID__c         = 'REFTEST-LINEUP'
        ));
        rows.add(new Allotment__c(
            Academic_Terms_Session__c = null,
            ISB_Line_Up_ID__c         = 'REFTEST-LINEUP'
        ));

        List<String> scopeLineups = new List<String>{ 'REFTEST-LINEUP' };

        AllotmentCourseOfferingHelper.ReferenceData refData =
            AllotmentCourseOfferingHelper.loadReferenceData(rows, scopeLineups);

        System.assertEquals(1, refData.sessionById.size(), 'Should load 1 AcademicSession');
        System.assert(refData.sessionById.containsKey(sess.Id), 'Session should be keyed by its Id');
        System.assertEquals(1, refData.offeringsByLineup.size(), 'Should load 1 lineup group');
        System.assertEquals(1, refData.offeringsByLineup.get('REFTEST-LINEUP').size(), 'Should have 1 CO under the lineup');
        System.assertEquals(sess.Id, refData.offeringsByLineup.get('REFTEST-LINEUP')[0].AcademicSessionId, 'Should query AcademicSessionId from the Helper');
    }

    @isTest
    static void testLoadReferenceDataEmpty() {
        List<Allotment__c> emptyRows = new List<Allotment__c>();
        List<String> emptyScope = new List<String>();

        AllotmentCourseOfferingHelper.ReferenceData refData =
            AllotmentCourseOfferingHelper.loadReferenceData(emptyRows, emptyScope);

        System.assertEquals(0, refData.sessionById.size(), 'No sessions expected');
        System.assertEquals(0, refData.offeringsByLineup.size(), 'No offerings expected');
    }

    @isTest
    static void testPopulateCreateFields() {
        Allotment__c src = new Allotment__c(
            Name                   = 'Create Test',
            ISB_Line_Up_ID__c      = 'CREATE-TEST',
            Area__c                = 'Finance',
            Course_Type__c         = 'Elective',
            ISB_Sessions__c        = '5',
            Section_Number__c      = 'B',
            Status__c              = 'Active',
            Teaching_Location_P__c = 'Hyderabad',
            Teaching_Date__c       = Date.today(),
            Teaching_Dates__c      = 'Mon-Wed',
            Term_Start_Date__c     = Date.today(),
            Term_To_Date__c        = Date.today().addMonths(6)
        );

        Id fakeSessionId = '000000000000001AAA';
        Id fakeTermId    = '000000000000002AAA';

        CourseOffering co = new CourseOffering();
        AllotmentCourseOfferingHelper.populateCreateFields(
            co, src, fakeSessionId, fakeTermId, null, null, null, null
        );

        System.assertEquals(fakeSessionId, co.AcademicSessionId, 'Should map Session ID');
        System.assertEquals(fakeTermId, co.Academic_Term__c, 'Should map Term ID');
        System.assertEquals('Create Test', co.Name);
        System.assertEquals('CREATE-TEST', co.ISB_Line_Up_ID__c);
        System.assertEquals('Finance', co.Area__c);
        System.assertEquals('Elective', co.Course_Type__c);
        System.assertEquals('5', co.ISB_Sessions__c);
        System.assertEquals('B', co.SectionNumber);
        System.assertEquals('Active', co.Status__c);
        System.assertEquals('Hyderabad', co.Teaching_Location_P__c);
        System.assertEquals(Date.today(), co.Teaching_Date__c);
        System.assertEquals('Mon-Wed', co.Teaching_Dates__c);
        System.assertEquals(Date.today(), co.Term_Start_Date__c);
        System.assertEquals(Date.today().addMonths(6), co.Term_To_Date__c);
    }

    @isTest
    static void testPopulateUpdateFields() {
        Allotment__c src = new Allotment__c(
            Area__c                = 'Marketing',
            ISB_Sessions__c        = '8',
            Section_Number__c      = 'C',
            Teaching_Location_P__c = 'Mohali'
        );

        Schema.Location loc = new Schema.Location(Name = 'Mock Campus', LocationType = 'Campus');
        insert loc;

        Id fakeSessionId = '000000000000001AAA';
        Id fakeTermId    = '000000000000002AAA';

        CourseOffering co = new CourseOffering();
        AllotmentCourseOfferingHelper.populateUpdateFields(
        co,
        src,
        fakeSessionId,
        fakeTermId,
        null,          // academicYearId
        loc.Id,        // locationId
        '1-2,3-4',     // finalSessions
        'Healthcare',  // industrySpecialization
        'Finance'      // concentration
        );

        System.assertEquals(fakeSessionId, co.AcademicSessionId, 'Update should map Session');
        System.assertEquals(fakeTermId, co.Academic_Term__c, 'Update should map Term');
        System.assertEquals('Marketing', co.Area__c);
        System.assertEquals('1-2,3-4', co.Preferred_Sessions2__c);
        System.assertEquals('8', co.ISB_Sessions__c);
        System.assertEquals('C', co.SectionNumber);
        System.assertEquals('Mohali', co.Teaching_Location_P__c);
        System.assertEquals(loc.Id, co.Location__c);
        System.assertEquals('Healthcare', co.Industry_Specialization_p__c);
        System.assertEquals('Finance', co.Concentration_p__c);
    }

    @isTest
    static void testMergeFinalSessions() {
        List<Allotment__c> blankRows = new List<Allotment__c>{
            new Allotment__c(Preferred_Sessions2__c = null),
            new Allotment__c(Preferred_Sessions2__c = '')
        };
        String r1 = AllotmentCourseOfferingHelper.mergeFinalSessions(null, blankRows);
        System.assertEquals('', r1, 'All blanks should return empty string');

        List<Allotment__c> emptyRows = new List<Allotment__c>();
        String r2 = AllotmentCourseOfferingHelper.mergeFinalSessions('5-6', emptyRows);
        System.assertEquals('5-6', r2, 'Should return existing value unchanged');

        List<Allotment__c> dupeRows = new List<Allotment__c>{
            new Allotment__c(Preferred_Sessions2__c = '3-4,1-2'),
            new Allotment__c(Preferred_Sessions2__c = '1-2;5-6')
        };
        String r3 = AllotmentCourseOfferingHelper.mergeFinalSessions('7-8', dupeRows);
        System.assertEquals('1-2,3-4,5-6,7-8', r3, 'Should sort, dedup, merge across commas and semicolons');

        List<Allotment__c> singleRow = new List<Allotment__c>{
            new Allotment__c(Preferred_Sessions2__c = '9-10')
        };
        String r4 = AllotmentCourseOfferingHelper.mergeFinalSessions(null, singleRow);
        System.assertEquals('9-10', r4, 'Single value should pass through');
    }

    @isTest
    static void testMergeMultiSelectField() {
        // All nulls / blanks — should return empty string
        List<Allotment__c> blankRows = new List<Allotment__c>{
            new Allotment__c(Industry_Specialization_p__c = null),
            new Allotment__c(Industry_Specialization_p__c = '')
        };
        String r1 = AllotmentCourseOfferingHelper.mergeMultiSelectField(
            null, blankRows, 'Industry_Specialization_p__c');
        System.assertEquals('', r1, 'All blanks should return empty string');

        // Existing value only, no new rows — should return existing unchanged
        List<Allotment__c> emptyRows = new List<Allotment__c>();
        String r2 = AllotmentCourseOfferingHelper.mergeMultiSelectField(
            'Manufacturing', emptyRows, 'Industry_Specialization_p__c');
        System.assertEquals('Manufacturing', r2, 'Should return existing value unchanged');

        // Merge with duplicates — Healthcare appears twice, should be deduped
        // Valid values: Healthcare, Infrastructure, Manufacturing — sorted alphabetically
        List<Allotment__c> dupeRows = new List<Allotment__c>{
            new Allotment__c(Industry_Specialization_p__c = 'Manufacturing;Healthcare'),
            new Allotment__c(Industry_Specialization_p__c = 'Healthcare;Infrastructure')
        };
        String r3 = AllotmentCourseOfferingHelper.mergeMultiSelectField(
            'Public Policy', dupeRows, 'Industry_Specialization_p__c');
        // Healthcare, Infrastructure, Manufacturing, Public Policy — alphabetical
        System.assertEquals(
            'Healthcare;Infrastructure;Manufacturing;Public Policy',
            r3,
            'Should sort, dedup, merge across semicolons — Healthcare deduped'
        );

        // Concentration field — valid values used
        // Entrepreneurship, Operations Management, Strategy and Leadership — alphabetical
        List<Allotment__c> concRows = new List<Allotment__c>{
            new Allotment__c(Concentration_p__c = 'Strategy and Leadership;Entrepreneurship'),
            new Allotment__c(Concentration_p__c = 'Entrepreneurship;Operations Management')
        };
        String r4 = AllotmentCourseOfferingHelper.mergeMultiSelectField(
            null, concRows, 'Concentration_p__c');
        // Entrepreneurship comes before Operations Management, which comes before Strategy and Leadership
        System.assertEquals(
            'Entrepreneurship;Operations Management;Strategy and Leadership',
            r4,
            'Should sort, dedup — Entrepreneurship deduped, alphabetical order'
        );
    }

    @isTest
    static void testTruncateError() {
        System.assertEquals(null, AllotmentCourseOfferingHelper.truncateError(null, 255));
        System.assertEquals('short error', AllotmentCourseOfferingHelper.truncateError('short error', 255));

        String exact = 'X'.repeat(255);
        System.assertEquals(255, AllotmentCourseOfferingHelper.truncateError(exact, 255).length());

        String longMsg = 'Y'.repeat(500);
        String truncated = AllotmentCourseOfferingHelper.truncateError(longMsg, 255);
        System.assertEquals(255, truncated.length(), 'Should truncate to 255');
        System.assert(truncated.startsWith('YYYYY'), 'Should keep the start of the message');
    }

    // ── Replaces old testTagCorrectAcademicSessions() ───────────────────────
    // Old test validated matching via Name + AcademicTermId + Location__c key.
    // tagCorrectAcademicSessions() now matches purely via ISB_External_Id__c,
    // so both sessions below must have that field populated for the lookup
    // to succeed.
    @isTest
    static void testTagCorrectAcademicSessionsViaExternalId() {
        AcademicTerm termOld = new AcademicTerm(Name = 'Term Old');
        AcademicTerm termNew = new AcademicTerm(Name = 'Term New');
        insert new List<AcademicTerm>{ termOld, termNew };

        Schema.Location loc1 = new Schema.Location(Name = 'Tag Helper Campus 1', LocationType = 'Campus');
        insert loc1;

        AcademicSession oldSession = new AcademicSession(
            Name                = 'Term Match Engine',
            AcademicTermId      = termOld.Id,
            Location__c         = loc1.Id,
            IsActive            = true,
            ISB_External_Id__c  = 'Term Match Engine' + loc1.Id + termOld.Id
        );
        AcademicSession correctSession = new AcademicSession(
            Name                = 'Term Match Engine',
            AcademicTermId      = termNew.Id,
            Location__c         = loc1.Id,
            IsActive            = true,
            ISB_External_Id__c  = 'Term Match Engine' + loc1.Id + termNew.Id
        );
        insert new List<AcademicSession>{ oldSession, correctSession };

        // CourseOffering currently points to oldSession, but its Academic_Term__c
        // says it should actually be on correctSession (same name, different term)
        CourseOffering co = new CourseOffering(
            AcademicSessionId = oldSession.Id,
            Academic_Term__c  = termNew.Id,
            Location__c       = loc1.Id
        );

        Test.startTest();
        AllotmentCourseOfferingHelper.tagCorrectAcademicSessions(new List<CourseOffering>{ co });
        Test.stopTest();

        System.assertEquals(correctSession.Id, co.AcademicSessionId,
            'Should re-tag to the session matching via ISB_External_Id__c for the correct term');
    }

    @isTest
    static void testTagCorrectAcademicSessionsNoMatch() {
        AcademicTerm termOld = new AcademicTerm(Name = 'Term Old NoMatch');
        AcademicTerm termNew = new AcademicTerm(Name = 'Term New NoMatch');
        insert new List<AcademicTerm>{ termOld, termNew };

        Schema.Location loc1 = new Schema.Location(Name = 'NoMatch Campus', LocationType = 'Campus');
        insert loc1;

        AcademicSession oldSession = new AcademicSession(
            Name                = 'NoMatch Session',
            AcademicTermId      = termOld.Id,
            Location__c         = loc1.Id,
            IsActive            = true,
            ISB_External_Id__c  = 'NoMatch Session' + loc1.Id + termOld.Id
        );
        insert oldSession;
        // No session exists for the termNew combo, and none has a matching
        // ISB_External_Id__c — the lookup should find nothing.

        CourseOffering co = new CourseOffering(
            AcademicSessionId = oldSession.Id,
            Academic_Term__c  = termNew.Id,
            Location__c       = loc1.Id
        );

        Test.startTest();
        AllotmentCourseOfferingHelper.tagCorrectAcademicSessions(new List<CourseOffering>{ co });
        Test.stopTest();

        System.assertEquals(oldSession.Id, co.AcademicSessionId,
            'Should remain unchanged when no matching ISB_External_Id__c is found');
    }

    @isTest
    static void testTagCorrectAcademicSessionsNullLocationOrTermSkipped() {
        AcademicTerm term = new AcademicTerm(Name = 'Term Null Guard');
        insert term;

        Schema.Location loc1 = new Schema.Location(Name = 'Null Guard Campus', LocationType = 'Campus');
        insert loc1;

        AcademicSession session = new AcademicSession(
            Name                = 'Null Guard Session',
            AcademicTermId      = term.Id,
            Location__c         = loc1.Id,
            IsActive            = true,
            ISB_External_Id__c  = 'Null Guard Session' + loc1.Id + term.Id
        );
        insert session;

        // CourseOffering with no Location__c set — should be skipped by the
        // null guard inside tagCorrectAcademicSessions() and left unchanged.
        CourseOffering co = new CourseOffering(
            AcademicSessionId = session.Id,
            Academic_Term__c  = term.Id,
            Location__c       = null
        );

        Test.startTest();
        AllotmentCourseOfferingHelper.tagCorrectAcademicSessions(new List<CourseOffering>{ co });
        Test.stopTest();

        System.assertEquals(session.Id, co.AcademicSessionId,
            'CourseOffering with null Location__c should be skipped and left unchanged');
    }
}