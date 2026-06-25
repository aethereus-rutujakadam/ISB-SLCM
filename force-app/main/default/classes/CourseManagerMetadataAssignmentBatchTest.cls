@isTest
private class CourseManagerMetadataAssignmentBatchTest {

    private static CourseOffering createOffering(String nameValue) {
        Program program = new Program(
            Name = nameValue + ' Program',
            Program_Code__c = 'PGP'
        );
        insert program;

        AcademicTerm term = new AcademicTerm(Name = nameValue + ' Term');
        insert term;

        Learning learning = new Learning(Name = nameValue + ' Learning');
        insert learning;

        LearningCourse course = new LearningCourse(
            Name = nameValue + ' Course',
            LearningId = learning.Id
        );
        insert course;

        Schema.Location loc = new Schema.Location(
            Name = nameValue + ' Location',
            LocationType = 'Campus'
        );
        insert loc;

        CourseOffering offering = new CourseOffering(
            Name = nameValue,
            LearningCourseId = course.Id,
            Program__c = program.Id,
            Academic_Term__c = term.Id,
            Location__c = loc.Id,
            Course_Type__c = 'Core',
            StartDate = Date.today(),
            EndDate = Date.today().addDays(10)
        );
        insert offering;

        return offering;
    }

    @isTest
    static void testConstructorsAndStartPaths() {
        CourseOffering offering = createOffering('CMMA Start Scoped');

        CourseManagerMetadataAssignmentBatch scopedBatch =
            new CourseManagerMetadataAssignmentBatch(new Set<Id>{ offering.Id });
        CourseManagerMetadataAssignmentBatch defaultBatch =
            new CourseManagerMetadataAssignmentBatch();

        Database.QueryLocator scopedLocator = scopedBatch.start(null);
        Database.QueryLocator defaultLocator = defaultBatch.start(null);

        System.assertNotEquals(null, scopedLocator);
        System.assertNotEquals(null, defaultLocator);
    }

    @isTest
    static void testExecuteAndFinishViaDatabaseBatch() {
        CourseOffering offering = createOffering('CMMA Execute');

        Test.startTest();
        Id jobId = Database.executeBatch(
            new CourseManagerMetadataAssignmentBatch(new Set<Id>{ offering.Id }),
            1
        );
        Test.stopTest();

        AsyncApexJob job = [
            SELECT Id, Status, NumberOfErrors
            FROM AsyncApexJob
            WHERE Id = :jobId
        ];

        System.assertEquals('Completed', job.Status);
        System.assertEquals(0, job.NumberOfErrors);
    }

    @isTest
    static void testExecuteWithEmptyScope() {
        CourseManagerMetadataAssignmentBatch batch = new CourseManagerMetadataAssignmentBatch();

        batch.execute(null, new List<SObject>());
        batch.finish(null);

        System.assertEquals(0, batch.offeringsProcessed);
        System.assertEquals(0, batch.assignmentsAttempted);
        System.assertEquals(0, batch.assignmentsCreated);
        System.assertEquals(0, batch.assignmentsSkipped);
        System.assertEquals(0, batch.errorsLogged);
    }
}