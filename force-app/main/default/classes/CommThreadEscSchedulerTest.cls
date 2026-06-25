@isTest
private class CommThreadEscSchedulerTest {

    @isTest
    static void testScheduleJobDefaultAndCustomNames() {
        String cron = '0 0 2 15 6 ? 2099';
        String customName = 'EscalationCustom' + DateTime.now().getTime();

        String customJobId;

        Test.startTest();
        try {
            CommunicationThreadEscalationScheduler.scheduleJob(null, cron);
        } catch (System.AsyncException ex) {
            System.assert(ex.getMessage().contains('already scheduled'));
        }

        customJobId = CommunicationThreadEscalationScheduler.scheduleJob(customName, cron);

        try {
            CommunicationThreadEscalationScheduler.scheduleJob('', cron);
        } catch (System.AsyncException ex) {
            System.assert(ex.getMessage().contains('already scheduled'));
        }
        Test.stopTest();

        System.assertNotEquals(null, customJobId, 'Expected a job id for custom schedule name.');

        List<CronTrigger> triggers = [
            SELECT Id, CronJobDetail.Name
            FROM CronTrigger
            WHERE Id = :((Id) customJobId)
        ];

        System.assertEquals(1, triggers.size());
        System.assertEquals(customName, triggers[0].CronJobDetail.Name);
    }

    @isTest
    static void testExecuteRunsBatch() {
        Test.startTest();
        new CommunicationThreadEscalationScheduler().execute(null);
        Test.stopTest();

        List<AsyncApexJob> jobs = [
            SELECT Id, JobType, Status
            FROM AsyncApexJob
            WHERE JobType = 'BatchApex' OR JobType = 'BatchApexWorker'
            ORDER BY CreatedDate DESC
            LIMIT 5
        ];

        System.assert(!jobs.isEmpty(), 'Expected scheduler execute to enqueue batch work.');
    }
}