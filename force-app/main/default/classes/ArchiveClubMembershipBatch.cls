public with sharing class ArchiveClubMembershipBatch implements Database.Batchable<sObject>, Schedulable {
    
    public void execute(SchedulableContext context) {
        // Schedule the batch job
        Database.executeBatch(new ArchiveClubMembershipBatch(), 200);
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        // Query all active club memberships
        // Active status is defined as records with Status__c = 'Active' or similar
        return Database.getQueryLocator(
            'SELECT Id, Status__c FROM Club_Membership__c WHERE Status__c = \'Active\' LIMIT 50000'
        );
    }

    public void execute(Database.BatchableContext context, List<Club_Membership__c> scope) {
        List<Club_Membership__c> membershipsToArchive = new List<Club_Membership__c>();

        for (Club_Membership__c membership : scope) {
            // Mark membership as Archived
            membership.Status__c = 'Archived';
            membershipsToArchive.add(membership);
        }

        // Perform bulk update
        if (!membershipsToArchive.isEmpty()) {
            update membershipsToArchive;
        }
    }

    public void finish(Database.BatchableContext context) {
        // Optional: Send notification or log completion
        System.debug('ArchiveClubMembershipBatch completed. Job ID: ' + context.getJobId());
    }
}