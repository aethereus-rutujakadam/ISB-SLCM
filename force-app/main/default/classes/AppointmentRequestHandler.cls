/**
 * @description Handles lifecycle events on Appointment_Request__c:
 *              - After Insert:             notifies students of advisor-created appointments
 *              - Cancellation/Rejection:   deletes the linked Salesforce Event
 *              - Reschedule of an Approved request: updates Event start/end times
 * @author DEVSLCM Team
 * @date 2026
 */
public with sharing class AppointmentRequestHandler {

    /**
     * @description Handles after-insert logic for appointment requests.
     *              Detects advisor-created appointments (not created by the student themselves)
     *              and triggers student notification.
     * @param newList List of newly inserted appointment requests
     */
    public static void handleAfterInsert(List<Appointment_Request__c> newList) {
        if (newList == null || newList.isEmpty()) {
            return;
        }

        // Collect student contact IDs to resolve their Salesforce users via User.ContactId
        Set<Id> studentContactIds = new Set<Id>();
        for (Appointment_Request__c req : newList) {
            if (req.Student__c != null) {
                studentContactIds.add(req.Student__c);
            }
        }

        if (studentContactIds.isEmpty()) {
            return;
        }

        // Map each student Contact to an active User record.
        Map<Id, Id> studentUserIdByContactId = new Map<Id, Id>();
        for (User userRecord : [
            SELECT Id, ContactId, IsActive
            FROM User
            WHERE ContactId IN :studentContactIds
        ]) {
            if (userRecord.IsActive) {
                studentUserIdByContactId.put(userRecord.ContactId, userRecord.Id);
            }
        }

        // Filter for advisor-created appointments:
        // CreatedById != Student User (resolved from User.ContactId)
        List<Appointment_Request__c> advisorCreatedAppointments = new List<Appointment_Request__c>();
        for (Appointment_Request__c req : newList) {
            Id studentUserId = studentUserIdByContactId.get(req.Student__c);

            // Skip student-submitted appointment requests from the portal flow.
            if (studentUserId != null && req.Requested_User__c == studentUserId) {
                continue;
            }

            // If CreatedById does NOT match the student's user, it's advisor-created.
            // If no user is found for the student contact, treat it as advisor-created so email still goes out.
            if (studentUserId == null || req.CreatedById != studentUserId) {
                advisorCreatedAppointments.add(req);
            }
        }

        // Notify students of advisor-created appointments
        if (!advisorCreatedAppointments.isEmpty()) {
            AdvisingNotificationService.notifyStudentOfNewAppointment(advisorCreatedAppointments);
        }
    }

    public static void handleBeforeUpdate(
        List<Appointment_Request__c> newList,
        Map<Id, Appointment_Request__c> oldMap
    ) {
        // Validate status transitions before allowing update
        validateStatusTransitions(newList, oldMap);
    }

    public static void handleAfterUpdate(
        List<Appointment_Request__c> newList,
        Map<Id, Appointment_Request__c> oldMap
    ) {
        List<Id>                          eventIdsToDelete   = new List<Id>();
        List<Appointment_Request__c>      syncEventRequests  = new List<Appointment_Request__c>();

        for (Appointment_Request__c req : newList) {
            Appointment_Request__c old = oldMap.get(req.Id);

            Boolean wasActive    = (old.Status__c == 'Approved' || old.Status__c == 'Pending');
            Boolean nowInactive  = (req.Status__c == 'Cancelled' || req.Status__c == 'Rejected');

            // On cancellation or rejection — delete the linked Event
            if (wasActive && nowInactive && String.isNotBlank(req.EventId__c)) {
                eventIdsToDelete.add(req.EventId__c);
            }

            // On approval/link or later edits to an Approved request — sync Event fields
            Boolean timesChanged = (req.Start_DateTime__c != old.Start_DateTime__c
                                 || req.End_DateTime__c   != old.End_DateTime__c);
            Boolean eventJustLinked = (String.isBlank(old.EventId__c) && String.isNotBlank(req.EventId__c));
            Boolean detailsChanged = (req.Reason__c != old.Reason__c
                                   || req.Request_Type__c != old.Request_Type__c
                                   || req.Student__c != old.Student__c
                                   || req.Name != old.Name);

            if (req.Status__c == 'Approved'
                && String.isNotBlank(req.EventId__c)
                && (eventJustLinked || timesChanged || detailsChanged)) {
                syncEventRequests.add(req);
            }
        }

        // ── Delete linked Events for cancelled/rejected requests ─────────────────────
        if (!eventIdsToDelete.isEmpty()) {
            List<Event> eventsToDelete = [SELECT Id FROM Event WHERE Id IN :eventIdsToDelete];
            if (!eventsToDelete.isEmpty()) {
                delete eventsToDelete;
            }
        }

        // ── Sync linked Events from approved requests ────────────────────────────────
        if (!syncEventRequests.isEmpty()) {
            Set<Id>                                 eventIds       = new Set<Id>();
            Map<Id, Appointment_Request__c>         eventToRequest = new Map<Id, Appointment_Request__c>();

            for (Appointment_Request__c req : syncEventRequests) {
                eventIds.add(req.EventId__c);
                eventToRequest.put(req.EventId__c, req);
            }

            List<Event> eventsToUpdate = new List<Event>();
            for (Event evt : [SELECT Id, StartDateTime, EndDateTime, DurationInMinutes,
                                     Subject, Description, Type, ShowAs, WhoId
                               FROM Event WHERE Id IN :eventIds]) {
                Appointment_Request__c req = eventToRequest.get(evt.Id);
                if (req == null) continue;

                Integer durationMinutes = Integer.valueOf(
                    (req.End_DateTime__c.getTime() - req.Start_DateTime__c.getTime()) / 60000
                );

                evt.StartDateTime     = req.Start_DateTime__c;
                evt.EndDateTime       = req.End_DateTime__c;
                evt.DurationInMinutes = durationMinutes;
                evt.Subject           = String.isNotBlank(req.Name)
                    ? req.Name
                    : 'Advising Session';
                evt.Description       = buildEventDescription(req);
                evt.Type              = mapRequestTypeToEventType(req.Request_Type__c);
                evt.ShowAs            = 'Busy';
                evt.WhoId             = req.Student__c;
                eventsToUpdate.add(evt);
            }

            if (!eventsToUpdate.isEmpty()) {
                update eventsToUpdate;
            }
        }

        AdvisingNotificationService.notifyStudentOfAppointmentChanges(newList, oldMap);
    }

    private static String buildEventDescription(Appointment_Request__c req) {
        List<String> lines = new List<String>();
        if (String.isNotBlank(req.Request_Type__c)) {
            lines.add('Request Type: ' + mapRequestTypeToEventType(req.Request_Type__c));
        }
        if (String.isNotBlank(req.Reason__c)) {
            lines.add('Reason: ' + req.Reason__c);
        }
        return String.join(lines, '\n');
    }

    private static String mapRequestTypeToEventType(String requestType) {
        if (requestType == 'cgpa') {
            return 'CGPA Discussion';
        }
        if (requestType == 'attendance') {
            return 'Attendance Flag';
        }
        if (requestType == 'general') {
            return 'General Advising';
        }
        if (requestType == 'other') {
            return 'Other';
        }
        return String.isNotBlank(requestType) ? requestType : null;
    }

    /**
     * @description Validates status transitions on Appointment_Request__c records.
     *              Enforces the following state machine:
     *              - Pending → (Approved or Rejected)
     *              - Approved → (Cancelled, Completed, or No-Show)
     *              - No-Show → (Completed or Cancelled)
     *              - Rejected, Cancelled, Completed are terminal states
     */
    private static void validateStatusTransitions(
        List<Appointment_Request__c> newList,
        Map<Id, Appointment_Request__c> oldMap
    ) {
        for (Appointment_Request__c newReq : newList) {
            Appointment_Request__c oldReq = oldMap.get(newReq.Id);
            
            // Skip validation if status didn't change
            if (newReq.Status__c == oldReq.Status__c) {
                continue;
            }

            String oldStatus = oldReq.Status__c;
            String newStatus = newReq.Status__c;

            Boolean isValidTransition = false;

            // Pending → (Approved or Rejected)
            if (oldStatus == 'Pending' && (newStatus == 'Approved' || newStatus == 'Rejected')) {
                isValidTransition = true;
            }
            // Approved → (Cancelled, Completed, or No-Show)
            else if (oldStatus == 'Approved' && (newStatus == 'Cancelled' || newStatus == 'Completed' || newStatus == 'No-Show')) {
                isValidTransition = true;
            }
            // No-Show → (Completed or Cancelled)
            else if (oldStatus == 'No-Show' && (newStatus == 'Completed' || newStatus == 'Cancelled')) {
                isValidTransition = true;
            }
            // Terminal states: no transitions allowed
            else if (oldStatus == 'Rejected' || oldStatus == 'Cancelled' || oldStatus == 'Completed') {
                isValidTransition = false;
            }

            if (!isValidTransition) {
                newReq.addError(
                    'Invalid status transition from "' + oldStatus + '" to "' + newStatus + '". ' +
                    'Valid transitions: Pending → (Approved|Rejected), Approved → (Cancelled|Completed|No-Show), ' +
                    'No-Show → (Completed|Cancelled). Rejected, Cancelled, and Completed are terminal states.'
                );
            }
        }
    }
}