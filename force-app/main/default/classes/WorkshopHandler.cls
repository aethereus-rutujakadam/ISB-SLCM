/**
 * @description Handles Workshop__c lifecycle:
 *              - Auto-creates Workshop_Session__c stubs when Total_Sessions__c is set
 *              - Adjusts session count when Total_Sessions__c changes
 *              - Notifies enrolled students when a workshop is published
 * @author DEVSLCM Team
 * @date 2026
 */
public with sharing class WorkshopHandler {

    public static void handleBeforeUpdate(
        List<Workshop__c> newList,
        Map<Id, Workshop__c> oldMap
    ) {
        for (Workshop__c w : newList) {
            Workshop__c old = oldMap.get(w.Id);
            if (w.Status__c == 'Published'
                    && old.Status__c != 'Published'
                    && String.isBlank(w.Description__c)) {
                w.Status__c.addError(
                    'A workshop description (email content) is required before publishing.'
                );
            }
        }
    }

    public static void handleAfterInsert(List<Workshop__c> newList) {
        createSessionStubs(newList, null);
    }

    public static void handleAfterUpdate(
        List<Workshop__c> newList,
        Map<Id, Workshop__c> oldMap
    ) {
        List<Workshop__c> sessionChanged  = new List<Workshop__c>();
        Set<Id>           justPublished   = new Set<Id>();

        for (Workshop__c w : newList) {
            Workshop__c old = oldMap.get(w.Id);

            if (w.Total_Sessions__c != old.Total_Sessions__c) {
                sessionChanged.add(w);
            }

            // R4: ISB-6020 - Only trigger automatic notification if NOT published via Quick Action
            if (w.Status__c == 'Published' 
                && old.Status__c != 'Published' 
                && w.Published_Via_Quick_Action__c != true) {
                justPublished.add(w.Id);
            }
        }

        if (!sessionChanged.isEmpty()) {
            createSessionStubs(sessionChanged, oldMap);
        }

        if (!justPublished.isEmpty()) {
            WorkshopNotificationService.sendWorkshopPublishedNotifications(justPublished);
        }
    }

    // ── Private helpers ──────────────────────────────────────────────────────────

    private static void createSessionStubs(
        List<Workshop__c> workshops,
        Map<Id, Workshop__c> oldMap
    ) {
        // Fetch existing session counts per workshop
        Map<Id, Integer> existingCount = new Map<Id, Integer>();
        Set<Id> workshopIds = new Set<Id>();
        for (Workshop__c w : workshops) {
            if (w.Total_Sessions__c != null && w.Total_Sessions__c > 0) {
                workshopIds.add(w.Id);
            }
        }
        if (workshopIds.isEmpty()) return;

        for (AggregateResult ar : [
            SELECT Workshop__c wId, COUNT(Id) cnt
            FROM Workshop_Session__c
            WHERE Workshop__c IN :workshopIds
            GROUP BY Workshop__c
        ]) {
            existingCount.put((Id) ar.get('wId'), Integer.valueOf(ar.get('cnt')));
        }

        List<Workshop_Session__c> toInsert = new List<Workshop_Session__c>();
        for (Workshop__c w : workshops) {
            if (w.Total_Sessions__c == null || w.Total_Sessions__c <= 0) continue;

            Integer target  = w.Total_Sessions__c.intValue();
            Integer current = existingCount.containsKey(w.Id) ? existingCount.get(w.Id) : 0;

            for (Integer i = current + 1; i <= target; i++) {
                toInsert.add(new Workshop_Session__c(
                    Workshop__c     = w.Id,
                    Program__c      = w.Program__c,
                    Name            = w.Name + ' – Session ' + i,
                    Session_Number__c = i,
                    Status__c       = 'Scheduled'
                ));
            }
        }

        if (!toInsert.isEmpty()) {
            insert toInsert;
        }
    }
}