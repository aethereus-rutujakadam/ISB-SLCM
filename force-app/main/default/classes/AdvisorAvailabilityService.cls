/**
 * @description Generates available time slots for an advisor on a given date,
 *              excluding existing busy Events and approved Appointment Requests.
 *              Working hours default: 08:00 – 17:00 in the org's running-user timezone.
 * @author DEVSLCM Team
 * @date 2026
 */
public without sharing class AdvisorAvailabilityService {

    /**
     * Lightweight wrapper returned to LWC for each candidate time slot.
     */
    public class TimeSlotWrapper {
        @AuraEnabled public String  label       { get; set; } // e.g. "9:00 AM – 9:30 AM"
        @AuraEnabled public String  startISO    { get; set; } // "2026-04-23T09:00:00"
        @AuraEnabled public String  endISO      { get; set; } // "2026-04-23T09:30:00"
        @AuraEnabled public Boolean isAvailable { get; set; }
    }

    /**
     * @description Returns all slots for a given advisor and date, flagged by availability.
     * @param advisorUserId   Salesforce User ID of the advisor (Event.OwnerId)
     * @param dateString      Date in "YYYY-MM-DD" format
     * @param slotDurationMinutes Slot length in minutes (e.g. 30)
     */
    @AuraEnabled(cacheable=true)
    public static List<TimeSlotWrapper> getAvailableSlots(
        Id      advisorUserId,
        String  dateString,
        Integer slotDurationMinutes
    ) {
        try {
            if (advisorUserId == null || String.isBlank(dateString)) {
                return new List<TimeSlotWrapper>();
            }
            if (slotDurationMinutes == null || slotDurationMinutes <= 0) {
                slotDurationMinutes = 30;
            }

            Date targetDate = Date.valueOf(dateString);

            // Working hours: 08:00 – 17:00 (configurable via Custom Metadata in future)
            Datetime dayStart = Datetime.newInstance(targetDate, Time.newInstance(8,  0, 0, 0));
            Datetime dayEnd   = Datetime.newInstance(targetDate, Time.newInstance(17, 0, 0, 0));

            // ── 1. Calendar Events (EAC-synced Outlook meetings + manually created) ────
            List<Event> busyEvents = [
                SELECT StartDateTime, EndDateTime
                FROM   Event
                WHERE  OwnerId        = :advisorUserId
                AND    StartDateTime  < :dayEnd
                AND    EndDateTime    > :dayStart
                AND    IsDeleted      = false
                AND    ShowAs         IN ('Busy', 'OutOfOffice')
            ];

            // ── 2. Pending Appointment Requests (double-booking guard) ───────────────
            //        Approved requests are already reflected as Events on the advisor's
            //        calendar (created at approval time), so the Event check above covers
            //        them.  We only need to block Pending requests here so a student cannot
            //        book a slot where another student's request is awaiting approval.
            //        'Cancelled' and 'Rejected' are intentionally excluded — those slots
            //        should become available again.
            List<Appointment_Request__c> approvedAppts = [
                SELECT Start_DateTime__c, End_DateTime__c
                FROM   Appointment_Request__c
                WHERE  Primary_Advisor__c = :advisorUserId
                AND    Status__c          = 'Pending'
                AND    Start_DateTime__c  < :dayEnd
                AND    End_DateTime__c    > :dayStart
            ];

            // ── 3. Generate slots and mark availability ───────────────────────────────
            List<TimeSlotWrapper> slots = new List<TimeSlotWrapper>();
            Datetime current = dayStart;

            while (current.addMinutes(slotDurationMinutes) <= dayEnd) {
                Datetime slotEnd = current.addMinutes(slotDurationMinutes);

                Boolean busy = false;

                // Check calendar events
                for (Event ev : busyEvents) {
                    if (current < ev.EndDateTime && slotEnd > ev.StartDateTime) {
                        busy = true;
                        break;
                    }
                }
                // Check approved appointment requests
                if (!busy) {
                    for (Appointment_Request__c appt : approvedAppts) {
                        if (current < appt.End_DateTime__c && slotEnd > appt.Start_DateTime__c) {
                            busy = true;
                            break;
                        }
                    }
                }

                TimeSlotWrapper slot = new TimeSlotWrapper();
                slot.startISO    = current.format('yyyy-MM-dd\'T\'HH:mm:ss');
                slot.endISO      = slotEnd.format('yyyy-MM-dd\'T\'HH:mm:ss');
                slot.label       = formatTime(current) + ' \u2013 ' + formatTime(slotEnd);
                slot.isAvailable = !busy;
                slots.add(slot);

                current = slotEnd;
            }

            return slots;

        } catch (Exception e) {
            System.debug('AdvisorAvailabilityService.getAvailableSlots error: ' + e.getMessage());
            throw new AuraHandledException('Failed to load available slots: ' + e.getMessage());
        }
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    private static String formatTime(Datetime dt) {
        Integer hour   = Integer.valueOf(dt.format('H'));
        Integer minute = Integer.valueOf(dt.format('m'));
        String  period = hour >= 12 ? 'PM' : 'AM';
        Integer display = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
        String  minStr  = minute < 10 ? '0' + minute : String.valueOf(minute);
        return display + ':' + minStr + ' ' + period;
    }
}