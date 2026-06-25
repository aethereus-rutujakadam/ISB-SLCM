/**
 * @description Schedulable wrapper that runs TaskReminderBatch in Overdue mode only.
 *              Intended to be scheduled fortnightly on the 1st and 15th of each month at 8:00 AM.
 *
 *  One-time setup (Anonymous Apex):
 *    System.schedule(
 *        'Task Reminder - Overdue (Fortnightly 8AM)',
 *        '0 0 8 1,15 * ?',
 *        new TaskReminderFortnightlyScheduler()
 *    );
 *
 *  To cancel:
 *    List<CronTrigger> jobs = [SELECT Id FROM CronTrigger
 *        WHERE CronJobDetail.Name = 'Task Reminder - Overdue (Fortnightly 8AM)'];
 *    if (!jobs.isEmpty()) System.abortJob(jobs[0].Id);
 */
public with sharing class TaskReminderFortnightlyScheduler implements Schedulable {

    private final Integer batchSize;

    public TaskReminderFortnightlyScheduler() {
        this.batchSize = 200;
    }

    public TaskReminderFortnightlyScheduler(Integer batchSize) {
        this.batchSize = (batchSize != null && batchSize > 0) ? batchSize : 200;
    }

    public void execute(SchedulableContext sc) {
        // sendDueToday = false, sendOverdue = true
        Database.executeBatch(new TaskReminderBatch(false, true), batchSize);
    }
}