global without sharing class CommunicationThreadEscalationBatch implements Database.Batchable<SObject> {
    global Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id
            FROM Communication_Thread__c
            WHERE Status__c IN ('Open', 'Pending Review')
            AND Course_Offering__c != null
            AND Course_Offering__r.Term_Start_Date__c != null
        ]);
    }

    global void execute(Database.BatchableContext bc, List<SObject> scope) {
        List<Communication_Thread__c> threads = (List<Communication_Thread__c>) scope;
        CommunicationThreadEscalationService.processScope(threads);
    }

    global void finish(Database.BatchableContext bc) {
    }
}