/**
 * @description Schedulable wrapper for TaskReminderBatch.
 *
 *  Schedules the batch to run daily at 8:00 AM org timezone.
 *
 *  To schedule from Anonymous Apex (one-time setup):
 *    String cronExp = '0 0 8 * * ?';   // 8:00 AM every day
 *    System.schedule('Task Reminder Batch - Daily 8AM', cronExp, new TaskReminderBatchScheduler());
 *
 *  To cancel:
 *    List<CronTrigger> jobs = [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name = 'Task Reminder Batch - Daily 8AM'];
 *    if (!jobs.isEmpty()) System.abortJob(jobs[0].Id);
 */
public with sharing class TaskReminderBatchScheduler implements Schedulable {

    private final Integer batchSize;

    /** Default constructor – runs with a batch size of 200. */
    public TaskReminderBatchScheduler() {
        this.batchSize = 200;
    }

    /** Overloaded constructor so callers can control the batch size. */
    public TaskReminderBatchScheduler(Integer batchSize) {
        this.batchSize = (batchSize != null && batchSize > 0) ? batchSize : 200;
    }

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new TaskReminderBatch(), batchSize);
    }
}