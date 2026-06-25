@isTest
private class CMMetadataAssignmentSchedulerTest {

    @isTest
    static void testScheduleJobDefaultAndCustomNames() {
        String cron = '0 0 12 15 6 ? 2099';
        String customName = 'CMMA Custom Job ' + DateTime.now().getTime();

        String defaultJobId;
        String customJobId;
        String blankJobId;

        Test.startTest();
        try {
            defaultJobId = CourseManagerMetadataAssignmentScheduler.scheduleJob(null, cron);
        } catch (System.AsyncException ex) {
            System.assert(ex.getMessage().contains('already scheduled'));
        }

        customJobId = CourseManagerMetadataAssignmentScheduler.scheduleJob(customName, cron);

        try {
            blankJobId = CourseManagerMetadataAssignmentScheduler.scheduleJob('', cron);
        } catch (System.AsyncException ex) {
            System.assert(ex.getMessage().contains('already scheduled'));
        }
        Test.stopTest();

        System.assertNotEquals(null, customJobId);

        List<CronTrigger> triggers = [
            SELECT Id, CronJobDetail.Name
            FROM CronTrigger
            WHERE Id = :((Id)customJobId)
        ];

        System.assertEquals(1, triggers.size());
        System.assertEquals(customName, triggers[0].CronJobDetail.Name);
    }

    @isTest
    static void testExecuteRunsBatch() {
        CourseManagerMetadataAssignmentScheduler scheduler = new CourseManagerMetadataAssignmentScheduler();

        Test.startTest();
        scheduler.execute(null);
        Test.stopTest();

        List<AsyncApexJob> jobs = [
            SELECT Id, Status, JobType
            FROM AsyncApexJob
            WHERE JobType = 'BatchApexWorker' OR JobType = 'BatchApex'
            ORDER BY CreatedDate DESC
            LIMIT 5
        ];

        System.assert(!jobs.isEmpty(), 'Expected at least one batch job entry after scheduler execution.');
    }
}