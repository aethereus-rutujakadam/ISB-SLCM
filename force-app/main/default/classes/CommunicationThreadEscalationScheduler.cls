public without sharing class CommunicationThreadEscalationScheduler implements Schedulable {
    public void execute(SchedulableContext sc) {
        Database.executeBatch(new CommunicationThreadEscalationBatch(), 200);
    }

    public static String scheduleJob(String jobName, String cronExpression) {
        String effectiveJobName = String.isBlank(jobName)
            ? 'CommunicationThreadEscalation'
            : jobName;
        return System.schedule(effectiveJobName, cronExpression, new CommunicationThreadEscalationScheduler());
    }
}