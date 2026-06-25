/**
 * @description Schedulable wrapper that runs TaskReminderBatch in Due-Today mode only.
 *              Intended to be scheduled daily at 8:00 AM.
 *
 *  One-time setup (Anonymous Apex):
 *    System.schedule(
 *        'Task Reminder - Due Today (Daily 8AM)',
 *        '0 0 8 * * ?',
 *        new TaskReminderDailyScheduler()
 *    );
 *
 *  To cancel:
 *    List<CronTrigger> jobs = [SELECT Id FROM CronTrigger
 *        WHERE CronJobDetail.Name = 'Task Reminder - Due Today (Daily 8AM)'];
 *    if (!jobs.isEmpty()) System.abortJob(jobs[0].Id);
 */
public with sharing class TaskReminderDailyScheduler implements Schedulable {

    private final Integer batchSize;

    public TaskReminderDailyScheduler() {
        this.batchSize = 200;
    }

    public TaskReminderDailyScheduler(Integer batchSize) {
        this.batchSize = (batchSize != null && batchSize > 0) ? batchSize : 200;
    }

    public void execute(SchedulableContext sc) {
        // sendDueToday = true, sendOverdue = false
        Database.executeBatch(new TaskReminderBatch(true, false), batchSize);
    }
}