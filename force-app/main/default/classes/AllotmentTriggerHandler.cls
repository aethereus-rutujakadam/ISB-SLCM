public with sharing class AllotmentTriggerHandler {

    public static void handleAfterUpdate(
        List<Allotment__c> newRecords,
        Map<Id, Allotment__c> oldMap
    ) {
        // Step 1 — Collect lineup IDs from records that transitioned to Pending
        Set<String> lineUpIds = new Set<String>();

        for (Allotment__c rec : newRecords) {
            if (rec.Sync_Status__c == 'Pending'
                && String.isNotBlank(rec.ISB_Line_Up_ID__c)
                && rec.Sync_Status__c != oldMap.get(rec.Id).Sync_Status__c) {
                    lineUpIds.add(rec.ISB_Line_Up_ID__c);
            }
        }

        if (lineUpIds.isEmpty()) return;

        // Step 2 — Query all Allotment records with matching lineup IDs
        // that are not already Pending
        List<Allotment__c> toUpdate = [
            SELECT Id, Sync_Status__c
            FROM   Allotment__c
            WHERE  ISB_Line_Up_ID__c IN :lineUpIds
            AND    Sync_Status__c    != 'Pending'
        ];

        if (toUpdate.isEmpty()) return;

        // Step 3 — Stamp all to Pending and update in one DML
        for (Allotment__c rec : toUpdate) {
            rec.Sync_Status__c = 'Pending';
        }

        update toUpdate;
    }
}