/**
 * @description Schedulable wrapper that runs RecurringProbationTaskBatch daily.
 *              Creates recurring "Meet Primary Advisor" tasks for students
 *              on academic probation with completed previous tasks (14-day interval).
 *
 * One-time setup (Anonymous Apex):
 *   System.schedule(
 *       'Recurring Probation Task Creator (Daily 2AM)',
 *       '0 0 2 * * ?',
 *       new RecurringProbationTaskBatchScheduler()
 *   );
 *
 * To cancel:
 *   List<CronTrigger> jobs = [SELECT Id FROM CronTrigger
 *       WHERE CronJobDetail.Name = 'Recurring Probation Task Creator (Daily 2AM)'];
 *   if (!jobs.isEmpty()) System.abortJob(jobs[0].Id);
 */
public with sharing class RecurringProbationTaskBatchScheduler implements Schedulable {

    private final Integer batchSize;

    public RecurringProbationTaskBatchScheduler() {
        this.batchSize = 50;
    }

    public RecurringProbationTaskBatchScheduler(Integer batchSize) {
        this.batchSize = (batchSize != null && batchSize > 0) ? batchSize : 50;
    }

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new RecurringProbationTaskBatch(), batchSize);
    }
}