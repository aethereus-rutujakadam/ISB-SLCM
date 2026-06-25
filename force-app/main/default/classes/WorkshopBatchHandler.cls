/**
 * @description Handles Workshop_Batch__c lifecycle:
 *              - Validates Start/End DateTime ordering
 *              - Auto-assigns Batch_Label__c if blank
 *              - Syncs Status between Open/Full based on Total_Registered__c vs Capacity__c
 *              - Cascades batch cancellation to registrations
 * @author DEVSLCM Team
 * @date 2026
 */
public without sharing class WorkshopBatchHandler {

    public static void handleBeforeInsert(List<Workshop_Batch__c> newList) {
        validateDateTimes(newList);
        populateWorkshopFromSession(newList, null);
        autoAssignBatchLabels(newList, null);
    }

    public static void handleBeforeUpdate(
        List<Workshop_Batch__c> newList,
        Map<Id, Workshop_Batch__c> oldMap
    ) {
        validateDateTimes(newList);
        populateWorkshopFromSession(newList, oldMap);
    }

    public static void handleAfterUpdate(
        List<Workshop_Batch__c> newList,
        Map<Id, Workshop_Batch__c> oldMap
    ) {
        syncBatchStatuses(newList, oldMap);
        cancelRegistrationsForCancelledBatches(newList, oldMap);
    }

    // ── Private helpers ──────────────────────────────────────────────────────────

    private static void validateDateTimes(List<Workshop_Batch__c> batches) {
        for (Workshop_Batch__c b : batches) {
            if (b.Start_DateTime__c != null && b.End_DateTime__c != null
                && b.End_DateTime__c <= b.Start_DateTime__c) {
                b.End_DateTime__c.addError('End DateTime must be after Start DateTime.');
            }
        }
    }

    private static void autoAssignBatchLabels(
        List<Workshop_Batch__c> batches,
        Map<Id, Workshop_Batch__c> oldMap
    ) {
        // Collect sessions needing label assignment
        Set<Id> sessionIds = new Set<Id>();
        for (Workshop_Batch__c b : batches) {
            if (String.isBlank(b.Batch_Label__c) && b.Workshop_Session__c != null) {
                sessionIds.add(b.Workshop_Session__c);
            }
        }
        if (sessionIds.isEmpty()) return;

        // Count existing batches per session for labelling sequence
        Map<Id, Integer> existingPerSession = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Workshop_Session__c sId, COUNT(Id) cnt
            FROM Workshop_Batch__c
            WHERE Workshop_Session__c IN :sessionIds
            GROUP BY Workshop_Session__c
        ]) {
            existingPerSession.put((Id) ar.get('sId'), Integer.valueOf(ar.get('cnt')));
        }

        // Track increment within this transaction per session
        Map<Id, Integer> counter = new Map<Id, Integer>();
        String[] labels = new String[]{'A','B','C','D','E','F','G','H'};

        for (Workshop_Batch__c b : batches) {
            if (String.isNotBlank(b.Batch_Label__c) || b.Workshop_Session__c == null) continue;
            Integer base = existingPerSession.containsKey(b.Workshop_Session__c)
                ? existingPerSession.get(b.Workshop_Session__c) : 0;
            Integer offset = counter.containsKey(b.Workshop_Session__c)
                ? counter.get(b.Workshop_Session__c) : 0;
            Integer idx = base + offset;
            b.Batch_Label__c = 'Batch ' + (idx < labels.size() ? labels[idx] : String.valueOf(idx + 1));
            counter.put(b.Workshop_Session__c, offset + 1);
        }
    }

    private static void populateWorkshopFromSession(
        List<Workshop_Batch__c> batches,
        Map<Id, Workshop_Batch__c> oldMap
    ) {
        Set<Id> sessionIds = new Set<Id>();
        for (Workshop_Batch__c b : batches) {
            if (b.Workshop_Session__c == null) continue;

            Boolean shouldPopulate = oldMap == null
                || b.Workshop__c == null
                || b.Workshop_Session__c != oldMap.get(b.Id).Workshop_Session__c;

            if (shouldPopulate) {
                sessionIds.add(b.Workshop_Session__c);
            }
        }

        if (sessionIds.isEmpty()) return;

        Map<Id, Id> workshopBySessionId = new Map<Id, Id>();
        for (Workshop_Session__c ws : [
            SELECT Id, Workshop__c
            FROM Workshop_Session__c
            WHERE Id IN :sessionIds
        ]) {
            workshopBySessionId.put(ws.Id, ws.Workshop__c);
        }

        for (Workshop_Batch__c b : batches) {
            if (b.Workshop_Session__c == null) continue;

            Boolean shouldPopulate = oldMap == null
                || b.Workshop__c == null
                || b.Workshop_Session__c != oldMap.get(b.Id).Workshop_Session__c;

            if (shouldPopulate && workshopBySessionId.containsKey(b.Workshop_Session__c)) {
                b.Workshop__c = workshopBySessionId.get(b.Workshop_Session__c);
            }
        }
    }

    private static void syncBatchStatuses(
        List<Workshop_Batch__c> newList,
        Map<Id, Workshop_Batch__c> oldMap
    ) {
        List<Workshop_Batch__c> toUpdate = new List<Workshop_Batch__c>();
        for (Workshop_Batch__c b : newList) {
            if (b.Status__c == 'Cancelled') continue; // Don't touch cancelled
            if (b.Capacity__c == null) continue;       // Unlimited — always Open

            Boolean regChanged = b.Total_Registered__c != oldMap.get(b.Id).Total_Registered__c;
            if (!regChanged) continue;

            String newStatus = (b.Total_Registered__c >= b.Capacity__c) ? 'Full' : 'Open';
            if (newStatus != b.Status__c) {
                toUpdate.add(new Workshop_Batch__c(Id = b.Id, Status__c = newStatus));
            }
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    private static void cancelRegistrationsForCancelledBatches(
        List<Workshop_Batch__c> newList,
        Map<Id, Workshop_Batch__c> oldMap
    ) {
        // Collect newly cancelled batches with their Workshop + Batch Label
        Map<String, Workshop_Batch__c> cancelledBatchesByKey = new Map<String, Workshop_Batch__c>();
        Set<Id> newlyCancelledBatchIds = new Set<Id>();
        
        for (Workshop_Batch__c b : newList) {
            if (b.Status__c == 'Cancelled' && oldMap.get(b.Id).Status__c != 'Cancelled') {
                newlyCancelledBatchIds.add(b.Id);
            }
        }
        
        if (newlyCancelledBatchIds.isEmpty()) return;

        // Query full batch details including Workshop and Batch Label
        List<Workshop_Batch__c> cancelledBatches = [
            SELECT Id, Batch_Label__c, Workshop_Session__r.Workshop__c
            FROM Workshop_Batch__c
            WHERE Id IN :newlyCancelledBatchIds
        ];

        // Build keys and collect workshop IDs + labels
        Set<Id> workshopIds = new Set<Id>();
        Set<String> batchLabels = new Set<String>();
        
        for (Workshop_Batch__c b : cancelledBatches) {
            String key = b.Workshop_Session__r.Workshop__c + '_' + b.Batch_Label__c;
            cancelledBatchesByKey.put(key, b);
            workshopIds.add(b.Workshop_Session__r.Workshop__c);
            batchLabels.add(b.Batch_Label__c);
        }

        if (workshopIds.isEmpty()) return;

        // Query registrations by Workshop + Batch Label
        List<Workshop_Registration__c> regsToCancel = [
            SELECT Id, Status__c, Workshop__c, Batch_Label__c
            FROM Workshop_Registration__c
            WHERE Workshop__c IN :workshopIds
            AND Batch_Label__c IN :batchLabels
            AND Status__c IN ('Registered', 'Waitlisted')
        ];

        // Only cancel registrations that match cancelled batches
        List<Workshop_Registration__c> toUpdate = new List<Workshop_Registration__c>();
        for (Workshop_Registration__c reg : regsToCancel) {
            String key = reg.Workshop__c + '_' + reg.Batch_Label__c;
            if (cancelledBatchesByKey.containsKey(key)) {
                reg.Status__c = 'Not Registered';
                toUpdate.add(reg);
            }
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }
}