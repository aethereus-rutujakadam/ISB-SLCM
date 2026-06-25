/**
 * @description Student-facing controller for Workshop Portal.
 *              Runs without sharing to allow students to query workshop data
 *              and register for workshops using BATCH LABELS.
 *
 *              Students register for Workshop + Batch Label (e.g., "Morning"),
 *              and attendance is auto-created for ALL matching batches across ALL sessions.
 *
 *              Workshops are filtered by:
 *                - Status = Published
 *                - Eligible_Term__c matching one of the student's registered Enrollment Sessions
 *                - Program__c matching one of the student's enrolled Programs
 *                - Cohort__c matching one of the student's enrolled Academic Terms
 *                - Campus__c matching the logged-in student's Primary_Campus__c
 *
 * @author DEVSLCM Team
 * @date 2026
 */
public without sharing class WorkshopPortalController {

    @TestVisible
    private static Id testStudentContactId;

    // ── Wrappers ─────────────────────────────────────────────────────────────────

    public class WorkshopPortalWrapper {
        @AuraEnabled public Workshop__c workshop { get; set; }
        @AuraEnabled public List<BatchLabelOption> batchOptions { get; set; }
        @AuraEnabled public String registeredBatchLabel { get; set; }
        @AuraEnabled public String registrationStatus { get; set; }
        @AuraEnabled public List<SessionBatchInfo> sessionBatchDetails { get; set; } // For modal display
        @AuraEnabled public Boolean registrationRequired { get; set; }
    }

    public class BatchLabelOption {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public Integer totalCapacity { get; set; }
        @AuraEnabled public Integer totalRegistered { get; set; }
        @AuraEnabled public Integer availableSeats { get; set; }
        @AuraEnabled public Boolean isAtCapacity { get; set; }
        @AuraEnabled public Boolean isFullyBlocked { get; set; }
        @AuraEnabled public BatchDetail sampleBatchInfo { get; set; } // Session 1 batch details for display
    }

    public class BatchDetail {
        @AuraEnabled public DateTime startDateTime { get; set; }
        @AuraEnabled public DateTime endDateTime { get; set; }
        @AuraEnabled public String mode { get; set; }
        @AuraEnabled public String location { get; set; }
        @AuraEnabled public String meetingLink { get; set; }
    }

    public class SessionBatchInfo {
        @AuraEnabled public Integer sessionNumber { get; set; }
        @AuraEnabled public String sessionName { get; set; }
        @AuraEnabled public DateTime sessionDate { get; set; }
        @AuraEnabled public String batchLabel { get; set; }
        @AuraEnabled public DateTime startDateTime { get; set; }
        @AuraEnabled public DateTime endDateTime { get; set; }
        @AuraEnabled public String mode { get; set; }
        @AuraEnabled public String location { get; set; }
        @AuraEnabled public String meetingLink { get; set; }
    }

    public class RegistrationResult {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String status { get; set; }   // Registered or Waitlisted
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public Boolean showWarning { get; set; } // True when Waitlisted
    }



    // ── Main portal data ──────────────────────────────────────────────────────────

    /**
     * @description Returns workshops eligible for the logged-in student,
     *              with batch labels and aggregated capacity across all sessions.
     */
    @AuraEnabled
    public static List<WorkshopPortalWrapper> getEligibleWorkshops(Id termId) {
        Id studentContactId = getStudentContactId();
        Id studentCampusId  = getStudentCampusId(studentContactId);
        Set<Id> enrolledSessionIds  = getStudentAcademicSessionIds(studentContactId);
        Set<Id> enrolledProgramIds = getStudentEnrolledProgramIds(studentContactId);
        Set<Id> enrolledAcademicTermIds = getStudentAcademicTermIds(studentContactId);

        // No active/enrolled academic sessions means no workshop visibility.
        if (enrolledSessionIds.isEmpty() || enrolledProgramIds.isEmpty() || enrolledAcademicTermIds.isEmpty()) {
            return new List<WorkshopPortalWrapper>();
        }

        // Guard against client-side tampering: requested term must belong to the student.
        if (termId != null && !enrolledSessionIds.contains(termId)) {
            return new List<WorkshopPortalWrapper>();
        }

        Set<Id> eligibleSessionFilter = new Set<Id>();
        if (termId != null) {
            eligibleSessionFilter.add(termId);
        } else {
            eligibleSessionFilter.addAll(enrolledSessionIds);
        }

        String soql =
            'SELECT Id, Name, Status__c, Workshop_Series__c, Description__c, '
            + 'Eligible_Term__c, Campus__c, Campus__r.Name, Cohort__c, '
            + 'Total_Sessions__c, Total_Registrations__c, Registration_Required__c '
            + 'FROM Workshop__c '
            + 'WHERE Status__c = \'Published\' '
            + 'AND Eligible_Term__c IN :eligibleSessionFilter '
            + 'AND Program__c IN :enrolledProgramIds '
            + 'AND Cohort__c IN :enrolledAcademicTermIds';

        if (studentCampusId != null) {
            soql += ' AND Campus__c = :studentCampusId';
        }

        soql += ' ORDER BY Name ASC LIMIT 200';

        List<Workshop__c> workshops = Database.query(soql);

        if (workshops.isEmpty()) return new List<WorkshopPortalWrapper>();

        Set<Id> workshopIds = new Map<Id, Workshop__c>(workshops).keySet();

        // Load all batches across all sessions for these workshops
        List<Workshop_Batch__c> allBatches = [
            SELECT Id, Batch_Label__c, Start_DateTime__c, End_DateTime__c,
                   Mode__c, Location__c, Meeting_Link__c, Capacity__c,
                   Total_Registered__c, Overbooking_Threshold__c, Status__c,
                   Workshop_Session__c, Workshop_Session__r.Workshop__c,
                   Workshop_Session__r.Session_Number__c,
                   Workshop_Session__r.Name, Workshop_Session__r.Session_Date__c
            FROM Workshop_Batch__c
            WHERE Workshop_Session__r.Workshop__c IN :workshopIds
            AND Status__c != 'Cancelled'
            ORDER BY Workshop_Session__r.Session_Number__c ASC, Start_DateTime__c ASC
        ];

        // Group batches by workshop + label
        Map<String, List<Workshop_Batch__c>> workshopLabelToBatches = new Map<String, List<Workshop_Batch__c>>();
        for (Workshop_Batch__c b : allBatches) {
            String key = b.Workshop_Session__r.Workshop__c + '_' + b.Batch_Label__c;
            if (!workshopLabelToBatches.containsKey(key)) {
                workshopLabelToBatches.put(key, new List<Workshop_Batch__c>());
            }
            workshopLabelToBatches.get(key).add(b);
        }

        // Load student's existing registrations with attendance records
        Map<Id, Workshop_Registration__c> regByWorkshop = new Map<Id, Workshop_Registration__c>();
        for (Workshop_Registration__c reg : [
            SELECT Id, Workshop__c, Batch_Label__c, Status__c,
                   (SELECT Id, Workshop_Batch__c, Workshop_Batch__r.Batch_Label__c 
                    FROM Workshop_Attendances__r 
                    WHERE Attendance_Status__c != 'Cancelled'
                    LIMIT 1)
            FROM Workshop_Registration__c
            WHERE Student__c = :studentContactId
            AND Workshop__c IN :workshopIds
            AND Status__c IN ('Registered', 'Waitlisted')
        ]) {
            // If Batch_Label__c is empty, retrieve it from the first attendance record
            if (String.isBlank(reg.Batch_Label__c) && !reg.Workshop_Attendances__r.isEmpty()) {
                reg.Batch_Label__c = reg.Workshop_Attendances__r[0].Workshop_Batch__r.Batch_Label__c;
            }
            regByWorkshop.put(reg.Workshop__c, reg);
        }

        // Build wrappers
        List<WorkshopPortalWrapper> result = new List<WorkshopPortalWrapper>();
        for (Workshop__c w : workshops) {
            WorkshopPortalWrapper pw = new WorkshopPortalWrapper();
            pw.workshop = w;
            pw.batchOptions = new List<BatchLabelOption>();
            pw.sessionBatchDetails = new List<SessionBatchInfo>();
            pw.registrationRequired = w.Registration_Required__c;

            Workshop_Registration__c existing = regByWorkshop.get(w.Id);
            pw.registeredBatchLabel = existing != null ? existing.Batch_Label__c : null;
            pw.registrationStatus   = existing != null ? existing.Status__c : null;

            // Get unique batch labels for this workshop
            Set<String> batchLabels = new Set<String>();
            Map<String, Workshop_Batch__c> labelToFirstBatch = new Map<String, Workshop_Batch__c>();
            
            for (Workshop_Batch__c b : allBatches) {
                if (b.Workshop_Session__r.Workshop__c == w.Id && b.Batch_Label__c != null) {
                    batchLabels.add(b.Batch_Label__c);
                    
                    // Keep first batch (session 1) as sample for UI display
                    if (!labelToFirstBatch.containsKey(b.Batch_Label__c)) {
                        labelToFirstBatch.put(b.Batch_Label__c, b);
                    }

                    // Build session batch details for modal
                    SessionBatchInfo sbi = new SessionBatchInfo();
                    sbi.sessionNumber = b.Workshop_Session__r.Session_Number__c.intValue();
                    sbi.sessionName = b.Workshop_Session__r.Name;
                    sbi.sessionDate = b.Workshop_Session__r.Session_Date__c;
                    sbi.batchLabel = b.Batch_Label__c;
                    sbi.startDateTime = b.Start_DateTime__c;
                    sbi.endDateTime = b.End_DateTime__c;
                    sbi.mode = b.Mode__c;
                    sbi.location = b.Location__c;
                    sbi.meetingLink = b.Meeting_Link__c;
                    pw.sessionBatchDetails.add(sbi);
                }
            }

            // For each batch label, aggregate capacity across all sessions
            for (String label : batchLabels) {
                String key = w.Id + '_' + label;
                List<Workshop_Batch__c> batches = workshopLabelToBatches.get(key);
                
                if (batches == null || batches.isEmpty()) continue;

                BatchLabelOption blo = new BatchLabelOption();
                blo.label = label;
                
                // Aggregate capacity
                Integer totalCap = 0;
                Integer totalReg = 0;
                Integer totalThreshold = 0;
                Boolean hasUnlimited = false;
                
                for (Workshop_Batch__c b : batches) {
                    if (b.Capacity__c == null) {
                        hasUnlimited = true;
                        break;
                    }
                    totalCap += b.Capacity__c.intValue();
                    totalReg += (b.Total_Registered__c != null ? b.Total_Registered__c : 0).intValue();
                    totalThreshold += (b.Overbooking_Threshold__c != null ? b.Overbooking_Threshold__c : 0).intValue();
                }
                
                if (hasUnlimited) {
                    blo.totalCapacity = 9999;
                    blo.totalRegistered = totalReg;
                    blo.availableSeats = 9999;
                    blo.isAtCapacity = false;
                    blo.isFullyBlocked = false;
                } else {
                    blo.totalCapacity = totalCap;
                    blo.totalRegistered = totalReg;
                    blo.availableSeats = totalCap - totalReg;
                    blo.isAtCapacity = totalReg >= totalCap;
                    blo.isFullyBlocked = totalReg >= (totalCap + totalThreshold);
                }

                // Add sample batch info for UI display (Session 1 details)
                Workshop_Batch__c sampleBatch = labelToFirstBatch.get(label);
                if (sampleBatch != null) {
                    BatchDetail bd = new BatchDetail();
                    bd.startDateTime = sampleBatch.Start_DateTime__c;
                    bd.endDateTime = sampleBatch.End_DateTime__c;
                    bd.mode = sampleBatch.Mode__c;
                    bd.location = sampleBatch.Location__c;
                    bd.meetingLink = sampleBatch.Meeting_Link__c;
                    blo.sampleBatchInfo = bd;
                }
                
                pw.batchOptions.add(blo);
            }
            
            result.add(pw);
        }
        return result;
    }

    /**
     * @description Returns the student's current registrations across all workshops,
     *              including their batch label and related attendance records.
     */
    @AuraEnabled(cacheable=true)
    public static List<Workshop_Registration__c> getMyRegistrations() {
        Id studentContactId = getStudentContactId();
        return [
            SELECT Id, Name, Status__c, Registration_Date__c,
                   Workshop__c, Workshop__r.Name, Workshop__r.Workshop_Series__c,
                   Batch_Label__c,
                   (SELECT Id, Name, Attendance_Status__c,
                           Workshop_Batch__c, Workshop_Batch__r.Batch_Label__c,
                           Workshop_Batch__r.Start_DateTime__c, Workshop_Batch__r.End_DateTime__c,
                           Workshop_Batch__r.Mode__c, Workshop_Batch__r.Location__c,
                           Workshop_Batch__r.Meeting_Link__c,
                           Workshop_Session__c, Workshop_Session__r.Name,
                           Workshop_Session__r.Session_Number__c
                    FROM Workshop_Attendances__r
                    ORDER BY Workshop_Session__r.Session_Number__c ASC)
            FROM Workshop_Registration__c
            WHERE Student__c = :studentContactId
            AND Status__c IN ('Registered', 'Waitlisted')
            ORDER BY Registration_Date__c DESC
        ];
    }

    /**
     * @description Returns the student's attendance records.
     */
    @AuraEnabled(cacheable=true)
    public static List<Workshop_Attendance__c> getMyAttendance() {
        Id studentContactId = getStudentContactId();
        return [
            SELECT Id, Name, Attendance_Status__c, Marked_Date__c,
                   Workshop__c, Workshop__r.Name,
                   Workshop_Batch__c, Workshop_Batch__r.Batch_Label__c,
                   Workshop_Batch__r.Start_DateTime__c,
                   Workshop_Session__c, Workshop_Session__r.Name,
                   Workshop_Session__r.Session_Number__c
            FROM Workshop_Attendance__c
            WHERE Student__c = :studentContactId
            ORDER BY Workshop_Batch__r.Start_DateTime__c ASC
        ];
    }

    /**
     * @description Registers the logged-in student for a workshop by batch label.
     *              This creates attendance records for ALL batches with the matching label
     *              across all sessions. Returns a RegistrationResult with success/warning info.
     */
    @AuraEnabled
    public static RegistrationResult registerForWorkshop(Id workshopId, String batchLabel) {
        RegistrationResult result = new RegistrationResult();
        Id studentContactId = getStudentContactId();

        // Validate workshop exists and is Published
        List<Workshop__c> workshops = [
            SELECT Id, Status__c, Registration_Required__c
            FROM Workshop__c
            WHERE Id = :workshopId
            LIMIT 1
        ];
        
        if (workshops.isEmpty()) {
            result.success = false;
            result.message = 'Workshop not found. Please refresh and try again.';
            return result;
        }
        
        if (workshops[0].Status__c != 'Published') {
            result.success = false;
            result.message = 'This workshop is not currently available for registration.';
            return result;
        }

        if (workshops[0].Registration_Required__c == false) {
            result.success = false;
            result.message = 'This workshop does not require registration. You can view workshop details in read-only mode.';
            return result;
        }

        // Pre-check: duplicate — student already registered for this workshop
        List<Workshop_Registration__c> existingReg = [
            SELECT Id
            FROM Workshop_Registration__c
            WHERE Student__c = :studentContactId
            AND Workshop__c  = :workshopId
            AND Status__c IN ('Registered', 'Waitlisted')
            LIMIT 1
        ];
        if (!existingReg.isEmpty()) {
            result.success = false;
            result.message = 'You are already registered for this workshop. Only one registration per workshop is allowed.';
            return result;
        }

        // Query all batches with this label across all sessions for capacity check
        List<Workshop_Batch__c> matchingBatches = [
            SELECT Id, Status__c, Capacity__c, Total_Registered__c, Overbooking_Threshold__c
            FROM Workshop_Batch__c
            WHERE Workshop_Session__r.Workshop__c = :workshopId
            AND Batch_Label__c = :batchLabel
            AND Status__c != 'Cancelled'
        ];
        
        if (matchingBatches.isEmpty()) {
            result.success = false;
            result.message = 'No available batches found for the selected option. Please refresh and try again.';
            return result;
        }

        // Aggregate capacity check across all batches with this label
        Integer totalCapacity = 0;
        Integer totalRegistered = 0;
        Integer totalThreshold = 0;
        Boolean hasUnlimitedCapacity = false;
        
        for (Workshop_Batch__c b : matchingBatches) {
            if (b.Status__c == 'Cancelled') continue;
            
            if (b.Capacity__c == null) {
                hasUnlimitedCapacity = true;
                break;
            }
            totalCapacity += b.Capacity__c.intValue();
            totalRegistered += (b.Total_Registered__c != null ? b.Total_Registered__c : 0).intValue();
            totalThreshold += (b.Overbooking_Threshold__c != null ? b.Overbooking_Threshold__c : 0).intValue();
        }
        
        if (!hasUnlimitedCapacity && totalRegistered >= totalCapacity + totalThreshold) {
            result.success = false;
            result.message = 'This batch option is at full capacity. Please try a different time slot.';
            return result;
        }

        try {
            Workshop_Registration__c reg = new Workshop_Registration__c(
                Student__c      = studentContactId,
                Workshop__c     = workshopId,
                Batch_Label__c  = batchLabel
            );
            insert reg;

            // Reload to get trigger-set status
            reg = [SELECT Id, Status__c FROM Workshop_Registration__c WHERE Id = :reg.Id LIMIT 1];
            result.success     = true;
            result.status      = reg.Status__c;
            result.showWarning = reg.Status__c == 'Waitlisted';
            result.message     = reg.Status__c == 'Waitlisted'
                ? 'You have been added to the waitlist for this workshop. You will be notified if a seat becomes available.'
                : 'You have been successfully registered for this workshop.';

        } catch (DmlException ex) {
            result.success = false;
            result.message = ex.getDmlMessage(0);
        }

        return result;
    }

    /**
     * @description Cancels the student's registration for a specific batch.
     */
    @AuraEnabled
    public static void cancelRegistration(Id registrationId) {
        Id studentContactId = getStudentContactId();
        Workshop_Registration__c reg = [
            SELECT Id, Student__c, Status__c
            FROM Workshop_Registration__c
            WHERE Id = :registrationId
            LIMIT 1
        ];
        if (reg.Student__c != studentContactId) {
            throw new AuraHandledException('You can only cancel your own registrations.');
        }
        reg.Status__c = 'Not Registered';
        update reg;
    }

    /**
     * @description Returns AcademicSession records for terms in which the current
     *              student is enrolled, sourced from their Enrollment_Session__c records.
     */
    @AuraEnabled(cacheable=true)
    public static List<AcademicSession> getAcademicTerms() {
        Id studentContactId = getStudentContactId();
        Set<Id> sessionIds = getStudentAcademicSessionIds(studentContactId);

        if (sessionIds.isEmpty()) return new List<AcademicSession>();

        return [
            SELECT Id, Name
            FROM AcademicSession
            WHERE Id IN :sessionIds
            ORDER BY Name ASC
        ];
    }

    private static Set<Id> getStudentAcademicSessionIds(Id studentContactId) {
        Set<Id> sessionIds = new Set<Id>();
        for (Enrollment_Session__c es : [
            SELECT Academic_Session__c
            FROM Enrollment_Session__c
            WHERE Program_Enrollment__r.ContactId = :studentContactId
            AND Academic_Session__c != null
            AND Status__c = 'Registered'
        ]) {
            sessionIds.add(es.Academic_Session__c);
        }
        return sessionIds;
    }

    private static Set<Id> getStudentEnrolledProgramIds(Id studentContactId) {
        Set<Id> programIds = new Set<Id>();
        for (Enrollment_Session__c es : [
            SELECT Program_Enrollment__r.ProgramId
            FROM Enrollment_Session__c
            WHERE Program_Enrollment__r.ContactId = :studentContactId
            AND Program_Enrollment__r.ProgramId != null
            AND Status__c = 'Registered'
        ]) {
            programIds.add(es.Program_Enrollment__r.ProgramId);
        }
        return programIds;
    }

    private static Set<Id> getStudentAcademicTermIds(Id studentContactId) {
        Set<Id> academicTermIds = new Set<Id>();
        for (Enrollment_Session__c es : [
            SELECT Academic_Session__r.AcademicTermId
            FROM Enrollment_Session__c
            WHERE Program_Enrollment__r.ContactId = :studentContactId
            AND Academic_Session__r.AcademicTermId != null
            AND Status__c = 'Registered'
        ]) {
            academicTermIds.add(es.Academic_Session__r.AcademicTermId);
        }
        return academicTermIds;
    }

    // ── Private helpers ──────────────────────────────────────────────────────────

    private static Id getStudentContactId() {
        if (Test.isRunningTest() && testStudentContactId != null) {
            return testStudentContactId;
        }

        Id userId = UserInfo.getUserId();
        User u = [SELECT ContactId FROM User WHERE Id = :userId LIMIT 1];
        if (u.ContactId == null) {
            throw new AuraHandledException('No student contact found for the current user.');
        }
        return u.ContactId;
    }

    private static Id getStudentCampusId(Id contactId) {
        List<Contact> contacts = [
            SELECT Primary_Campus__c FROM Contact WHERE Id = :contactId LIMIT 1
        ];
        if (!contacts.isEmpty()) {
            return contacts[0].Primary_Campus__c;
        }
        return null;
    }
}