/**
 * @description Handler for Event trigger - Detects advisor-created appointments
 *              and notifies students via AdvisingNotificationService.
 *              Bulkified to handle up to 200 events in a single transaction.
 * @author DEVSLCM Team
 * @date 2026
 */
public with sharing class EventHandler {

    /**
     * @description Handles after-insert Event trigger logic:
     *              Enqueues a job to send email notifications to event attendees
     *              Uses Queueable to ensure EventRelation records are created before querying
     * @param newEvents List of newly inserted Event records
     */
    public static void handleAfterInsert(List<Event> newEvents) {
        if (newEvents == null || newEvents.isEmpty()) {
            return;
        }

        try {
            // Collect Event IDs
            Set<Id> eventIds = new Set<Id>();
            for (Event evt : newEvents) {
                eventIds.add(evt.Id);
            }
            
            System.debug('EventHandler: Enqueuing EventAttendeeEmailQueueable for ' + eventIds.size() + ' events');
            
            // Enqueue job to send attendee notifications
            // Queueable executes after transaction commits, ensuring EventRelation records exist
            System.enqueueJob(new EventAttendeeEmailQueueable(eventIds));

        } catch (Exception ex) {
            System.debug('EventHandler.handleAfterInsert error: ' + ex.getMessage());
            System.debug('EventHandler.handleAfterInsert stack trace: ' + ex.getStackTraceString());
        }
    }
}