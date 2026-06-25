public without sharing class AllotmentCourseOfferingScheduler implements Schedulable {
    public void execute(SchedulableContext sc) {
        Database.executeBatch(new AllotmentCourseOfferingBatch(), 20);
    }
}