@IsTest
public class TranscriptExportControllerTest {

    @TestSetup
    static void setupTestData() {

        // Create core related records using TestDataFactory
        Contact student = TestDataFactory.testContact();
        Program program = TestDataFactory.testProgram();
        AcademicTerm term = TestDataFactory.testAcademicTerm(program.Id);
        AcademicSession session = TestDataFactory.testAcademicSession();

        // Transcript with matching View_Type__c
        Transcript__c transcriptMatch = new Transcript__c(
            Student__c = student.Id,
            Program__c = program.Id,
            Academic_Term__c = term.Id,
            Academic_Session__c = session.Id,
            Course__c = null,
            Credits__c = 4,
            Grade__c = 'A',
            Grade_Points__c = 8,
            Term_GPA__c = 3.8,
            Credits_Earned_Till_Term__c = 20,
            CGPA__c = 3.6,
            Total_Credits__c = 30,
            View_Type__c = 'Student'
        );

        // Transcript with NON-matching View_Type__c
        Transcript__c transcriptNonMatch = new Transcript__c(
            Student__c = student.Id,
            Program__c = program.Id,
            Academic_Term__c = term.Id,
            Academic_Session__c = session.Id,
            Credits__c = 3,
            Grade__c = 'B',
            View_Type__c = 'Admin'
        );

        insert new List<Transcript__c>{
            transcriptMatch,
            transcriptNonMatch
        };
    }

    /* =========================================================
     * Test Case 1
     * When View Type matches, records should be returned
     * ========================================================= */
    @IsTest
    static void testGetTranscripts_matchingViewType_recordsReturned() {

        Test.startTest();
        List<Transcript__c> results =
            TranscriptExportController.getTranscripts('Student');
        Test.stopTest();

        System.assertEquals(
            1,
            results.size(),
            'Exactly one transcript should match the Student view type'
        );

        Transcript__c t = results[0];

        System.assertNotEquals(null, t.Student__r.Name, 'Student name should be populated');
        System.assertNotEquals(null, t.Program__r.Name, 'Program name should be populated');
        System.assertEquals('A', t.Grade__c, 'Grade should match expected value');
        System.assertEquals(3.6, t.CGPA__c, 'CGPA should be returned correctly');
    }

    /* =========================================================
     * Test Case 2
     * When View Type does NOT match, no records returned
     * ========================================================= */
    @IsTest
    static void testGetTranscripts_nonMatchingViewType_noRecordsReturned() {

        Test.startTest();
        List<Transcript__c> results =
            TranscriptExportController.getTranscripts('Faculty');
        Test.stopTest();

        System.assertEquals(
            0,
            results.size(),
            'No transcripts should be returned for unmatched view type'
        );
    }

    /* =========================================================
     * Test Case 3
     * When View Type exists but has limited fields
     * ========================================================= */
    @IsTest
    static void testGetTranscripts_adminView_returnsCorrectRecord() {

        Test.startTest();
        List<Transcript__c> results =
            TranscriptExportController.getTranscripts('Admin');
        Test.stopTest();

        System.assertEquals(
            1,
            results.size(),
            'Admin view should return exactly one transcript'
        );

        System.assertEquals(
            'B',
            results[0].Grade__c,
            'Grade should match Admin transcript record'
        );
    }

    /* =========================================================
     * Test Case 4
     * Null View Type should safely return empty list
     * ========================================================= */
    @IsTest
    static void testGetTranscripts_nullViewType_returnsEmptyList() {

        Test.startTest();
        List<Transcript__c> results =
            TranscriptExportController.getTranscripts(null);
        Test.stopTest();

        System.assertEquals(
            0,
            results.size(),
            'Null view type should return empty results safely'
        );
    }
}