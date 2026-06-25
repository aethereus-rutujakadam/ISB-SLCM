public with sharing class ISBContactExitDateScheduler implements Schedulable {

    public void execute(SchedulableContext sc) {
        System.debug('ISBContactExitDateScheduler: Triggering ISBContactExitDateBatch.');
        ISBContactExitDateBatch batch = new ISBContactExitDateBatch();
        Database.executeBatch(batch, 200);
    }

    /**
     * Helper method to schedule the job to run daily at midnight.
     * Run this once from Anonymous Apex to register the schedule:
     *   ISBContactExitDateScheduler.scheduleDaily();
     */
    public static void scheduleDaily() {
        String cronExp = '0 0 0 * * ?'; // Every day at midnight
        String jobName = 'ISB Contact Exit Date Daily Deactivation';

        // Abort existing job with same name if already scheduled
        for (CronTrigger ct : [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name = :jobName]) {
            System.abortJob(ct.Id);
        }

        System.schedule(jobName, cronExp, new ISBContactExitDateScheduler());
        System.debug('ISBContactExitDateScheduler: Scheduled job "' + jobName + '" with cron: ' + cronExp);
    }
}