public without sharing class CourseOfferingLMSQueueable implements Queueable, Database.AllowsCallouts {
    
    private List<Id> recordIds;
    private Integer batchSize = 50; // Process 50 at a time to stay safe within 100 callouts limit

    public CourseOfferingLMSQueueable(List<Id> ids) {
        this.recordIds = ids;
    }

    public void execute(QueueableContext context) {
        if (recordIds == null || recordIds.isEmpty()) return;

        // 1. Get current chunk
        List<Id> currentChunk = new List<Id>();
        List<Id> remainingIds = new List<Id>();

        for (Integer i = 0; i < recordIds.size(); i++) {
            if (i < batchSize) currentChunk.add(recordIds[i]);
            else remainingIds.add(recordIds[i]);
        }

        // 2. Query data for current chunk
        List<CourseOffering> validOfferings = [
            SELECT Id, Name, Academic_Term__c, No_of_Sections__c, LMS_Course_Id__c,
                   Academic_Year__r.Category_Id__c, LearningCourse.Name, Section_Name__c, Section_Mappings__c
            FROM CourseOffering
            WHERE Id IN :currentChunk
        ];

        // 3. Perform Sync (this method now handles individual callouts inside)
        CourseOfferingLMSService.SyncResult res = CourseOfferingLMSService.sync(validOfferings);

        // 4. Update Records
        List<CourseOffering> toUpdate = new List<CourseOffering>();
        toUpdate.addAll(res.successRecords);
        toUpdate.addAll(res.failedRecords);
        if(!toUpdate.isEmpty()) {
            update toUpdate;
        }

        // 5. Chain next job if more records exist
        if (!remainingIds.isEmpty() && !Test.isRunningTest()) {
            System.enqueueJob(new CourseOfferingLMSQueueable(remainingIds));
        }
    }
}