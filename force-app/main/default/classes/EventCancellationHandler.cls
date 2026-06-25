/**
 * @description Handles Event after-delete to automatically cancel the linked
 *              Appointment_Request__c when an advisor deletes the calendar event
 *              (e.g. cancels the meeting from Outlook via EAC sync).
 *
 *              Logic:
 *              - Collect Ids of all deleted Events.
 *              - Find Appointment_Request__c records where EventId__c is in that set
 *                and Status__c is 'Approved' (only approved requests have a linked Event).
 *              - Set Status__c = 'Cancelled' and stamp Notes_and_Remarks__c with the
 *                date/time so the student sees the reason on their portal.
 *
 * @author DEVSLCM Team
 * @date 2026
 */
public without sharing class EventCancellationHandler {

    public static void handleAfterDelete(List<Event> deletedEvents) {

        if (deletedEvents == null || deletedEvents.isEmpty()) return;

        // Collect the IDs of all deleted events
        Set<Id> deletedEventIds = new Set<Id>();
        for (Event evt : deletedEvents) {
            if (evt.Id != null) {
                deletedEventIds.add(evt.Id);
            }
        }

        if (deletedEventIds.isEmpty()) return;

        // Find linked Appointment Requests (approved records with a matching EventId__c)
        List<Appointment_Request__c> toCancel = [
            SELECT Id, Status__c, Notes_and_Remarks__c, EventId__c
            FROM   Appointment_Request__c
            WHERE  EventId__c IN :deletedEventIds
            AND    Status__c  = 'Approved'
        ];

        if (toCancel.isEmpty()) return;

        String cancelledOn = Datetime.now().format('MMMM d, yyyy \'at\' h:mm a');
        String note = 'This meeting was cancelled by the advisor on ' + cancelledOn + '. '
                    + 'Please contact your advisor or re-book through the advising portal.';

        for (Appointment_Request__c req : toCancel) {
            req.Status__c             = 'Cancelled';
            req.Notes_and_Remarks__c = note;
        }

        update toCancel;
    }
}