/**
 * @description Before-insert/update guard on Event that prevents overlapping Busy/OutOfOffice
 *              events for the same owner. Called by EventConflictTrigger.
 * @author DEVSLCM Team
 * @date 2026
 */
public with sharing class EventConflictValidator {

    public static void validate(List<Event> newEvents, Map<Id, Event> oldMap) {

        // Collect owners of events being inserted/updated that are Busy or OutOfOffice
        Set<Id> ownerIds   = new Set<Id>();
        Set<Id> currentIds = new Set<Id>();

        for (Event evt : newEvents) {
            if (evt.ShowAs == 'Busy' || evt.ShowAs == 'OutOfOffice') {
                if (evt.OwnerId != null) ownerIds.add(evt.OwnerId);
                if (evt.Id      != null) currentIds.add(evt.Id);
            }
        }

        if (ownerIds.isEmpty()) return;

        // Fetch existing Busy/OutOfOffice events for those owners, excluding the current records
        List<Event> existingEvents = [
            SELECT Id, OwnerId, StartDateTime, EndDateTime
            FROM   Event
            WHERE  OwnerId    IN :ownerIds
            AND    Id         NOT IN :currentIds
            AND    IsDeleted  = false
            AND    ShowAs     IN ('Busy', 'OutOfOffice')
        ];

        if (existingEvents.isEmpty()) return;

        // Group by OwnerId for efficient lookup
        Map<Id, List<Event>> byOwner = new Map<Id, List<Event>>();
        for (Event ev : existingEvents) {
            if (!byOwner.containsKey(ev.OwnerId)) {
                byOwner.put(ev.OwnerId, new List<Event>());
            }
            byOwner.get(ev.OwnerId).add(ev);
        }

        // Evaluate each incoming event against existing calendar
        for (Event evt : newEvents) {
            if (evt.ShowAs != 'Busy' && evt.ShowAs != 'OutOfOffice') continue;
            if (evt.StartDateTime == null || evt.EndDateTime == null) continue;
            if (!byOwner.containsKey(evt.OwnerId)) continue;

            for (Event existing : byOwner.get(evt.OwnerId)) {
                if (existing.StartDateTime == null || existing.EndDateTime == null) continue;

                Boolean overlaps = evt.StartDateTime < existing.EndDateTime
                                && evt.EndDateTime   > existing.StartDateTime;

                if (overlaps) {
                    evt.addError(
                        'Calendar conflict: a busy event already exists from '
                        + existing.StartDateTime.format('h:mm a, MMM d')
                        + ' to '
                        + existing.EndDateTime.format('h:mm a')
                        + '. Please choose a different time.'
                    );
                    break;
                }
            }
        }
    }
}