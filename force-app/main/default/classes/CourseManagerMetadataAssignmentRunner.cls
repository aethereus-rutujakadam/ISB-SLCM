public without sharing class CourseManagerMetadataAssignmentRunner {

    public static Id runNow() {
        return runNow(200);
    }

    public static Id runNow(Integer batchSize) {
        Integer effectiveBatchSize = (batchSize == null || batchSize <= 0 || batchSize > 2000)
            ? 200
            : batchSize;

        return Database.executeBatch(new CourseManagerMetadataAssignmentBatch(), effectiveBatchSize);
    }
}