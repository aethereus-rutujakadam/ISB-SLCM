@isTest
private class CMMetadataAssignmentRunnerTest {

    @isTest
    static void testRunNowOverloads() {
        Test.startTest();
        Id defaultJobId = CourseManagerMetadataAssignmentRunner.runNow();
        Id smallJobId = CourseManagerMetadataAssignmentRunner.runNow(10);
        Id invalidLargeJobId = CourseManagerMetadataAssignmentRunner.runNow(2501);
        Test.stopTest();

        System.assertNotEquals(null, defaultJobId);
        System.assertNotEquals(null, smallJobId);
        System.assertNotEquals(null, invalidLargeJobId);

        List<AsyncApexJob> jobs = [
            SELECT Id, Status
            FROM AsyncApexJob
            WHERE Id IN :new Set<Id>{ defaultJobId, smallJobId, invalidLargeJobId }
        ];

        System.assertEquals(3, jobs.size());
    }

    @isTest
    static void testRunNowWithNullAndZero() {
        Test.startTest();
        Id nullBatchSizeJobId = CourseManagerMetadataAssignmentRunner.runNow(null);
        Id zeroBatchSizeJobId = CourseManagerMetadataAssignmentRunner.runNow(0);
        Test.stopTest();

        System.assertNotEquals(null, nullBatchSizeJobId);
        System.assertNotEquals(null, zeroBatchSizeJobId);
    }
}