/**
 * @description Handles Workshop_Session__c lifecycle:
 *              - Cascades cancellation to all child Workshop_Batch__c records
 * @author DEVSLCM Team
 * @date 2026
 */
public with sharing class WorkshopSessionHandler {

    public static void handleAfterUpdate(
        List<Workshop_Session__c> newList,
        Map<Id, Workshop_Session__c> oldMap
    ) {
        List<Id> cancelledSessionIds = new List<Id>();
        for (Workshop_Session__c ws : newList) {
            if (ws.Status__c == 'Cancelled' && oldMap.get(ws.Id).Status__c != 'Cancelled') {
                cancelledSessionIds.add(ws.Id);
            }
        }
        if (cancelledSessionIds.isEmpty()) return;

        List<Workshop_Batch__c> batchesToCancel = [
            SELECT Id, Status__c
            FROM Workshop_Batch__c
            WHERE Workshop_Session__c IN :cancelledSessionIds
            AND Status__c != 'Cancelled'
        ];

        for (Workshop_Batch__c b : batchesToCancel) {
            b.Status__c = 'Cancelled';
        }

        if (!batchesToCancel.isEmpty()) {
            update batchesToCancel;
        }
    }
}