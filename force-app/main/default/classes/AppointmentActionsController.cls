/**
 * @description Handles advisor-initiated Approve and Reject actions on Appointment_Request__c
 *              records. On approval, creates a Salesforce Event and adds the student as an
 *              EventRelation attendee so Einstein Activity Capture syncs the meeting to Outlook.
 *              Uses FOR UPDATE record locking to prevent race conditions on concurrent clicks.
 * @author DEVSLCM Team
 * @date 2026
 */
public with sharing class AppointmentActionsController {

    /**
     * @description Approves a pending appointment request, creates a Salesforce Event
     *              for the advisor, adds the student as an attendee, and links the Event
     *              back to the request via EventId__c.
     * @param requestId Id of the Appointment_Request__c to approve
     */
    @AuraEnabled
    public static void approveRequest(Id requestId) {
        try {
            // ── 1. Lock the record to prevent concurrent approval race conditions ──────
            List<Appointment_Request__c> requests = [
                SELECT Id, Status__c, Student__c, Primary_Advisor__c,
                       Start_DateTime__c, End_DateTime__c,
                       Reason__c, Request_Type__c, Name
                FROM   Appointment_Request__c
                WHERE  Id = :requestId
                FOR UPDATE
            ];

            if (requests.isEmpty()) {
                throw new AuraHandledException('Appointment Request not found.');
            }

            Appointment_Request__c req = requests[0];

            // ── 2. Re-validate status after lock (handles double-click / concurrent advisors) ─
            if (req.Status__c != 'Pending') {
                throw new AuraHandledException(
                    'This request is no longer Pending (current status: ' + req.Status__c + ').'
                );
            }

            // ── 3. Resolve student User ────────────────────────────────────────────────
            List<User> studentUsers = [
                SELECT Id, Name
                FROM   User
                WHERE  ContactId = :req.Student__c
                AND    IsActive  = true
                LIMIT  1
            ];
            if (studentUsers.isEmpty()) {
                throw new AuraHandledException(
                    'No active Salesforce User found for this student. Ensure the student has a portal account.'
                );
            }
            User studentUser = studentUsers[0];

            // ── 4. Check for conflicting Events on the advisor's calendar ──────────────
            List<Event> conflicts = [
                SELECT Id
                FROM   Event
                WHERE  OwnerId       = :req.Primary_Advisor__c
                AND    StartDateTime < :req.End_DateTime__c
                AND    EndDateTime   > :req.Start_DateTime__c
                AND    IsDeleted     = false
                AND    ShowAs        IN ('Busy', 'OutOfOffice')
                LIMIT  1
            ];
            if (!conflicts.isEmpty()) {
                throw new AuraHandledException(
                    'A calendar conflict exists: the advisor already has a meeting during this period.'
                );
            }

            // ── 5. Check for other Approved requests in the same slot ─────────────────
            List<Appointment_Request__c> apptConflicts = [
                SELECT Id
                FROM   Appointment_Request__c
                WHERE  Id                != :requestId
                AND    Primary_Advisor__c = :req.Primary_Advisor__c
                AND    Status__c          = 'Approved'
                AND    Start_DateTime__c  < :req.End_DateTime__c
                AND    End_DateTime__c    > :req.Start_DateTime__c
                LIMIT  1
            ];
            if (!apptConflicts.isEmpty()) {
                throw new AuraHandledException(
                    'Another appointment has already been approved for this time slot.'
                );
            }

            // ── 6. Create Event ────────────────────────────────────────────────────────
            Integer durationMins = Integer.valueOf((req.End_DateTime__c.getTime() - req.Start_DateTime__c.getTime()) / 60000);

            Event evt = new Event();
            evt.OwnerId           = req.Primary_Advisor__c;
            evt.StartDateTime     = req.Start_DateTime__c;
            evt.EndDateTime       = req.End_DateTime__c;
            evt.DurationInMinutes = durationMins;
            evt.Subject           = 'Advising Session \u2013 ' + studentUser.Name;
            evt.WhoId             = req.Student__c;  // Must be Contact ID, not User ID
            evt.ShowAs            = 'Busy';
            evt.Description       = 'Request Type: ' + req.Request_Type__c
                                  + '\nReason: ' + req.Reason__c;
            insert evt;

            // ── 7. Add student as EventRelation attendee (syncs to Outlook via EAC) ───
            EventRelation er = new EventRelation();
            er.EventId    = evt.Id;
            er.RelationId = studentUser.Id;
            er.Status     = 'Accepted';
            er.IsWhat     = false;
            insert er;

            // ── 8. Update Appointment Request ────────────────────────────────────────
            req.Status__c  = 'Approved';
            req.EventId__c = evt.Id;
            update req;

            AdvisingNotificationService.notifyStudentOfApprovedAppointment(
                new List<Appointment_Request__c>{ req }
            );

        } catch (AuraHandledException auraEx) {
            throw auraEx;
        } catch (Exception e) {
            System.debug('approveRequest error: ' + e.getMessage() + '\n' + e.getStackTraceString());
            throw new AuraHandledException('Failed to approve appointment: ' + e.getMessage());
        }
    }

    /**
     * @description Rejects a pending appointment request, stores the rejection reason,
     *              and cleans up any orphaned Event if present.
     * @param requestId       Id of the Appointment_Request__c to reject
     * @param rejectionReason Advisor's reason for rejection (displayed to student)
     */
    @AuraEnabled
    public static void rejectRequest(Id requestId, String rejectionReason) {
        try {
            List<Appointment_Request__c> requests = [
                SELECT Id, Status__c, EventId__c
                FROM   Appointment_Request__c
                WHERE  Id = :requestId
                FOR UPDATE
            ];

            if (requests.isEmpty()) {
                throw new AuraHandledException('Appointment Request not found.');
            }

            Appointment_Request__c req = requests[0];

            if (req.Status__c != 'Pending') {
                throw new AuraHandledException(
                    'This request is no longer Pending (current status: ' + req.Status__c + ').'
                );
            }

            // Clean up any orphaned linked Event
            if (String.isNotBlank(req.EventId__c)) {
                try {
                    List<Event> orphaned = [SELECT Id FROM Event WHERE Id = :req.EventId__c LIMIT 1];
                    if (!orphaned.isEmpty()) {
                        delete orphaned[0];
                    }
                } catch (Exception cleanupEx) {
                    System.debug('Event cleanup on reject (non-blocking): ' + cleanupEx.getMessage());
                }
            }

            req.Status__c          = 'Rejected';
            req.Rejection_Reason__c = String.isNotBlank(rejectionReason) ? rejectionReason.trim() : null;
            req.EventId__c          = null;
            update req;

        } catch (AuraHandledException auraEx) {
            throw auraEx;
        } catch (Exception e) {
            System.debug('rejectRequest error: ' + e.getMessage());
            throw new AuraHandledException('Failed to reject appointment: ' + e.getMessage());
        }
    }
}