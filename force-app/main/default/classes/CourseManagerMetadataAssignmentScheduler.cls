public without sharing class CourseManagerMetadataAssignmentScheduler implements Schedulable {

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new CourseManagerMetadataAssignmentBatch(), 200);
    }

    public static String scheduleJob(String jobName, String cronExpression) {
        String effectiveJobName = String.isBlank(jobName) ? 'CourseManagerMetadataAssignment' : jobName;
        return System.schedule(effectiveJobName, cronExpression, new CourseManagerMetadataAssignmentScheduler());
    }
}