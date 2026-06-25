public without sharing class CourseManagerMetadataAssignmentBatch implements Database.Batchable<SObject>, Database.Stateful {

    private Set<Id> scopedOfferingIds;

    public Integer offeringsProcessed = 0;
    public Integer assignmentsAttempted = 0;
    public Integer assignmentsCreated = 0;
    public Integer assignmentsSkipped = 0;
    public Integer errorsLogged = 0;

    public CourseManagerMetadataAssignmentBatch() {
        this.scopedOfferingIds = null;
    }

    public CourseManagerMetadataAssignmentBatch(Set<Id> scopedOfferingIds) {
        this.scopedOfferingIds = (scopedOfferingIds == null || scopedOfferingIds.isEmpty()) ? null : scopedOfferingIds;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        if (scopedOfferingIds != null) {
            return Database.getQueryLocator([
                SELECT Id
                FROM CourseOffering
                WHERE Id IN :scopedOfferingIds
            ]);
        }

        return Database.getQueryLocator([
            SELECT Id
            FROM CourseOffering
            WHERE Program__c != null
              AND Location__c != null
              AND Course_Type__c != null
                            AND Academic_Term__c != null
              AND Id IN (
                  SELECT Course_Offering__c
                  FROM Allotment__c
                  WHERE Sync_Status__c = 'Synced'
                    AND Course_Offering__c != null
              )
        ]);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        Set<Id> offeringIds = new Set<Id>();
        for (SObject row : scope) {
            offeringIds.add((Id)row.get('Id'));
        }

        CourseManagerMetadataAssignmentService.AssignmentStats stats =
            CourseManagerMetadataAssignmentService.assignForOfferings(offeringIds);

        offeringsProcessed += stats.totalOfferingsEvaluated;
        assignmentsAttempted += stats.totalAssignmentsAttempted;
        assignmentsCreated += stats.totalAssignmentsCreated;
        assignmentsSkipped += stats.totalAssignmentsSkipped;
        errorsLogged += stats.totalErrorsLogged;
    }

    public void finish(Database.BatchableContext bc) {
        System.debug(
            'CourseManagerMetadataAssignmentBatch complete.' +
            ' OfferingsProcessed=' + offeringsProcessed +
            ', AssignmentsAttempted=' + assignmentsAttempted +
            ', AssignmentsCreated=' + assignmentsCreated +
            ', AssignmentsSkipped=' + assignmentsSkipped +
            ', ErrorsLogged=' + errorsLogged
        );
    }
}