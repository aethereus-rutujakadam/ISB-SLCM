public with sharing class ISBContactExitDateBatch implements Database.Batchable<SObject>, Database.Stateful {

    private Integer recordsProcessed = 0;

    public Database.QueryLocator start(Database.BatchableContext bc) {
        System.debug('ISBContactExitDateBatch: Starting batch. Querying Academic Associate contacts with passed exit date.');

        Id academicAssociateRTId = null;
        Map<String, Schema.RecordTypeInfo> rtMap = Schema.SObjectType.Contact.getRecordTypeInfosByName();
        if (rtMap.containsKey('Academic Associate')) {
            academicAssociateRTId = rtMap.get('Academic Associate').getRecordTypeId();
        }

        return Database.getQueryLocator([
            SELECT Id, Active_Status__c, Date_of_Exit__c
            FROM Contact
            WHERE RecordTypeId = :academicAssociateRTId
            AND Active_Status__c = 'Active'
            AND Date_of_Exit__c != null
            AND Date_of_Exit__c < TODAY
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Contact> scope) {
        List<Contact> toUpdate = new List<Contact>();

        for (Contact con : scope) {
            System.debug('ISBContactExitDateBatch: Setting Contact ID ' + con.Id + ' to Inactive. Date of Exit: ' + con.Date_of_Exit__c);
            con.Active_Status__c = 'Inactive';
            toUpdate.add(con);
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
            recordsProcessed += toUpdate.size();
            System.debug('ISBContactExitDateBatch: Updated ' + toUpdate.size() + ' contacts in this batch.');
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('ISBContactExitDateBatch: Batch completed. Total records updated: ' + recordsProcessed);
    }
}