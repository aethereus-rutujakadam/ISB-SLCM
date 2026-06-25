/**
 * @description Advisor-facing controller for Workshop & Tutoring management.
 *              Provides AuraEnabled methods for creating, editing, and managing
 *              workshops, sessions, batches, registrations, and attendance.
 * @author DEVSLCM Team
 * @date 2026
 */
public with sharing class WorkshopController {

    // ── Wrappers ─────────────────────────────────────────────────────────────────

    public class WorkshopDashboardWrapper {
        @AuraEnabled public Id workshopId { get; set; }
        @AuraEnabled public String workshopName { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String campusName { get; set; }
        @AuraEnabled public String programName { get; set; }
        @AuraEnabled public String eligibleTermName { get; set; }
        @AuraEnabled public Decimal totalSessions { get; set; }
        @AuraEnabled public Decimal totalRegistrations { get; set; }
        @AuraEnabled public Boolean canActivate { get; set; }
        @AuraEnabled public Boolean canDeactivate { get; set; }
        @AuraEnabled public List<WorkshopSessionDashboardWrapper> sessions { get; set; }
    }

    public class WorkshopSessionDashboardWrapper {
        @AuraEnabled public Id sessionId { get; set; }
        @AuraEnabled public String sessionName { get; set; }
        @AuraEnabled public Decimal sessionNumber { get; set; }
        @AuraEnabled public Datetime sessionDate { get; set; }
        @AuraEnabled public String mode { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Integer totalBatches { get; set; }
        @AuraEnabled public Integer registeredCount { get; set; }
        @AuraEnabled public Integer waitlistedCount { get; set; }
        @AuraEnabled public List<WorkshopBatchDashboardWrapper> batches { get; set; }
    }

    public class WorkshopBatchDashboardWrapper {
        @AuraEnabled public Id batchId { get; set; }
        @AuraEnabled public String batchName { get; set; }
        @AuraEnabled public String batchLabel { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Integer capacity { get; set; }
        @AuraEnabled public Integer totalRegistered { get; set; }
        @AuraEnabled public Integer remainingSeats { get; set; }
        @AuraEnabled public Integer waitlistedCount { get; set; }
        @AuraEnabled public Boolean isFull { get; set; }
        @AuraEnabled public Boolean isInactive { get; set; }
        @AuraEnabled public List<WorkshopRegistrationDashboardWrapper> registrations { get; set; }
    }

    public class WorkshopRegistrationDashboardWrapper {
        @AuraEnabled public Id registrationId { get; set; }
        @AuraEnabled public Id studentId { get; set; }
        @AuraEnabled public String studentName { get; set; }
        @AuraEnabled public String email { get; set; }
        @AuraEnabled public String batchLabel { get; set; }
        @AuraEnabled public String registrationStatus { get; set; }
    }

    public class WorkshopWrapper {
        @AuraEnabled public Workshop__c workshop { get; set; }
        @AuraEnabled public List<Workshop_Session__c> sessions { get; set; }
        @AuraEnabled public Integer totalBatches { get; set; }
        @AuraEnabled public Integer totalRegistrations { get; set; }
    }

    public class BatchWrapper {
        @AuraEnabled public Workshop_Batch__c batch { get; set; }
        @AuraEnabled public Integer availableSeats { get; set; }
        @AuraEnabled public List<Workshop_Registration__c> registrations { get; set; }
    }

    // ── Workshop CRUD ─────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<Workshop__c> getWorkshops(String statusFilter) {
        String soql = 'SELECT Id, Name, Status__c, Workshop_Series__c, Eligible_Term__c, '
                    + 'Campus__c, Campus__r.Name, Cohort__c, Cohort__r.Name, Total_Sessions__c, Total_Registrations__c, '
                    + 'Description__c, Program__c, Program__r.Name '
                    + 'FROM Workshop__c';
        if (String.isNotBlank(statusFilter)) {
            soql += ' WHERE Status__c = :statusFilter';
        }
        soql += ' ORDER BY CreatedDate DESC LIMIT 200';
        return Database.query(soql);
    }

    @AuraEnabled(cacheable=true)
    public static List<WorkshopDashboardWrapper> getWorkshopDashboard(String statusFilter) {
        assertWorkshopDashboardReadAccess();

        String soql = 'SELECT Id, Name, Status__c, Campus__r.Name, Program__r.Name, Cohort__r.Name, '
                    + 'Eligible_Term__r.Name, Total_Sessions__c, Total_Registrations__c '
                    + 'FROM Workshop__c';
        if (String.isNotBlank(statusFilter)) {
            soql += ' WHERE Status__c = :statusFilter';
        }
        soql += ' ORDER BY CreatedDate DESC LIMIT 200';

        List<Workshop__c> workshops = Database.query(soql);
        if (workshops.isEmpty()) {
            return new List<WorkshopDashboardWrapper>();
        }

        Map<Id, WorkshopDashboardWrapper> workshopWrappersById = new Map<Id, WorkshopDashboardWrapper>();
        Set<Id> workshopIds = new Set<Id>();
        for (Workshop__c workshopRecord : workshops) {
            workshopIds.add(workshopRecord.Id);

            WorkshopDashboardWrapper workshopWrapper = new WorkshopDashboardWrapper();
            workshopWrapper.workshopId = workshopRecord.Id;
            workshopWrapper.workshopName = workshopRecord.Name;
            workshopWrapper.status = workshopRecord.Status__c;
            workshopWrapper.campusName = workshopRecord.Campus__r != null ? workshopRecord.Campus__r.Name : null;
            workshopWrapper.programName = workshopRecord.Program__r != null ? workshopRecord.Program__r.Name : null;
            workshopWrapper.eligibleTermName = workshopRecord.Eligible_Term__r != null
                ? workshopRecord.Eligible_Term__r.Name : null;
            workshopWrapper.totalSessions = workshopRecord.Total_Sessions__c;
            workshopWrapper.totalRegistrations = workshopRecord.Total_Registrations__c;
            workshopWrapper.canActivate = workshopRecord.Status__c == 'Draft' || workshopRecord.Status__c == 'Inactive';
            workshopWrapper.canDeactivate = workshopRecord.Status__c == 'Published';
            workshopWrapper.sessions = new List<WorkshopSessionDashboardWrapper>();
            workshopWrappersById.put(workshopRecord.Id, workshopWrapper);
        }

        List<Workshop_Session__c> sessions = [
            SELECT Id, Name, Session_Number__c, Session_Date__c, Mode__c, Status__c, Workshop__c
            FROM Workshop_Session__c
            WHERE Workshop__c IN :workshopIds
            ORDER BY Workshop__c, Session_Number__c ASC, Session_Date__c ASC
        ];

        Map<Id, WorkshopSessionDashboardWrapper> sessionWrappersById = new Map<Id, WorkshopSessionDashboardWrapper>();
        Set<Id> sessionIds = new Set<Id>();
        for (Workshop_Session__c sessionRecord : sessions) {
            sessionIds.add(sessionRecord.Id);

            WorkshopSessionDashboardWrapper sessionWrapper = new WorkshopSessionDashboardWrapper();
            sessionWrapper.sessionId = sessionRecord.Id;
            sessionWrapper.sessionName = sessionRecord.Name;
            sessionWrapper.sessionNumber = sessionRecord.Session_Number__c;
            sessionWrapper.sessionDate = sessionRecord.Session_Date__c;
            sessionWrapper.mode = sessionRecord.Mode__c;
            sessionWrapper.status = sessionRecord.Status__c;
            sessionWrapper.totalBatches = 0;
            sessionWrapper.registeredCount = 0;
            sessionWrapper.waitlistedCount = 0;
            sessionWrapper.batches = new List<WorkshopBatchDashboardWrapper>();
            sessionWrappersById.put(sessionRecord.Id, sessionWrapper);

            WorkshopDashboardWrapper parentWorkshop = workshopWrappersById.get(sessionRecord.Workshop__c);
            if (parentWorkshop != null) {
                parentWorkshop.sessions.add(sessionWrapper);
            }
        }

        Map<String, WorkshopBatchDashboardWrapper> batchWrappersByKey = new Map<String, WorkshopBatchDashboardWrapper>();
        if (!sessionIds.isEmpty()) {
            for (Workshop_Batch__c batchRecord : [
                SELECT Id, Name, Batch_Label__c, Status__c, Capacity__c, Total_Registered__c,
                       Available_Seats__c, Workshop_Session__c, Workshop_Session__r.Workshop__c
                FROM Workshop_Batch__c
                WHERE Workshop_Session__c IN :sessionIds
                ORDER BY Workshop_Session__c, Start_DateTime__c ASC, Name ASC
            ]) {
                WorkshopBatchDashboardWrapper batchWrapper = new WorkshopBatchDashboardWrapper();
                batchWrapper.batchId = batchRecord.Id;
                batchWrapper.batchName = batchRecord.Name;
                batchWrapper.batchLabel = batchRecord.Batch_Label__c;
                batchWrapper.status = batchRecord.Status__c;
                batchWrapper.capacity = batchRecord.Capacity__c != null ? batchRecord.Capacity__c.intValue() : null;
                batchWrapper.totalRegistered = batchRecord.Total_Registered__c != null
                    ? batchRecord.Total_Registered__c.intValue() : 0;
                Integer availableSeats = batchRecord.Available_Seats__c != null
                    ? batchRecord.Available_Seats__c.intValue()
                    : (batchWrapper.capacity != null ? batchWrapper.capacity - batchWrapper.totalRegistered : null);
                batchWrapper.remainingSeats = availableSeats;
                batchWrapper.waitlistedCount = 0;
                batchWrapper.isFull = batchRecord.Status__c == 'Full'
                    || (batchWrapper.capacity != null && batchWrapper.totalRegistered >= batchWrapper.capacity);
                batchWrapper.isInactive = batchRecord.Status__c == 'Cancelled';
                batchWrapper.registrations = new List<WorkshopRegistrationDashboardWrapper>();

                WorkshopSessionDashboardWrapper parentSession = sessionWrappersById.get(batchRecord.Workshop_Session__c);
                if (parentSession != null) {
                    parentSession.totalBatches++;
                    parentSession.batches.add(batchWrapper);
                }

                String batchKey = buildBatchKey(batchRecord.Workshop_Session__r.Workshop__c, batchRecord.Batch_Label__c);
                batchWrappersByKey.put(batchKey, batchWrapper);
            }
        }

        if (!workshopIds.isEmpty()) {
            for (Workshop_Registration__c registrationRecord : [
                SELECT Id, Student__c, Student__r.Name, Student__r.Email, Status__c, Batch_Label__c,
                       Workshop__c, Workshop__r.Id
                FROM Workshop_Registration__c
                WHERE Workshop__c IN :workshopIds
                AND Status__c IN ('Registered', 'Waitlisted')
                ORDER BY Registration_Date__c ASC, Student__r.Name ASC
            ]) {
                String batchKey = buildBatchKey(registrationRecord.Workshop__c, registrationRecord.Batch_Label__c);
                WorkshopBatchDashboardWrapper batchWrapper = batchWrappersByKey.get(batchKey);
                if (batchWrapper == null) {
                    continue;
                }

                WorkshopRegistrationDashboardWrapper registrationWrapper = new WorkshopRegistrationDashboardWrapper();
                registrationWrapper.registrationId = registrationRecord.Id;
                registrationWrapper.studentId = registrationRecord.Student__c;
                registrationWrapper.studentName = registrationRecord.Student__r != null
                    ? registrationRecord.Student__r.Name : null;
                registrationWrapper.email = registrationRecord.Student__r != null
                    ? registrationRecord.Student__r.Email : null;
                registrationWrapper.batchLabel = registrationRecord.Batch_Label__c;
                registrationWrapper.registrationStatus = registrationRecord.Status__c;
                batchWrapper.registrations.add(registrationWrapper);

                if (registrationRecord.Status__c == 'Waitlisted') {
                    batchWrapper.waitlistedCount++;
                }
            }
        }

        for (WorkshopDashboardWrapper workshopWrapper : workshopWrappersById.values()) {
            for (WorkshopSessionDashboardWrapper sessionWrapper : workshopWrapper.sessions) {
                Integer registeredCount = 0;
                Integer waitlistedCount = 0;
                for (WorkshopBatchDashboardWrapper batchWrapper : sessionWrapper.batches) {
                    registeredCount += batchWrapper.totalRegistered;
                    waitlistedCount += batchWrapper.waitlistedCount;
                }
                sessionWrapper.registeredCount = registeredCount;
                sessionWrapper.waitlistedCount = waitlistedCount;
            }
        }

        return workshopWrappersById.values();
    }

    @AuraEnabled(cacheable=true)
    public static WorkshopWrapper getWorkshopDetail(Id workshopId) {
        WorkshopWrapper wrapper = new WorkshopWrapper();

        wrapper.workshop = [
            SELECT Id, Name, Status__c, Workshop_Series__c, Eligible_Term__c,
                   Campus__c, Campus__r.Name, Total_Sessions__c, Total_Registrations__c,
                     Description__c, Program__c, Program__r.Name, Cohort__c, Cohort__r.Name
            FROM Workshop__c
            WHERE Id = :workshopId
            LIMIT 1
        ];

        wrapper.sessions = [
            SELECT Id, Name, Session_Number__c, Session_Date__c, Mode__c,
                   Location__c, Meeting_Link__c, Status__c, Description__c,
                   Course_Offering__c, Program__c,
                   (SELECT Id, Name, Batch_Label__c, Start_DateTime__c, End_DateTime__c,
                           Mode__c, Location__c, Capacity__c, Total_Registered__c,
                           Available_Seats__c, Status__c, Overbooking_Threshold__c
                    FROM Workshop_Batches__r
                    ORDER BY Start_DateTime__c ASC)
            FROM Workshop_Session__c
            WHERE Workshop__c = :workshopId
            ORDER BY Session_Number__c ASC
        ];

        AggregateResult batchCount = [
            SELECT COUNT(Id) cnt FROM Workshop_Batch__c
            WHERE Workshop_Session__r.Workshop__c = :workshopId
        ];
        wrapper.totalBatches        = Integer.valueOf(batchCount.get('cnt'));
        wrapper.totalRegistrations  = Integer.valueOf(
            wrapper.workshop.Total_Registrations__c != null ? wrapper.workshop.Total_Registrations__c : 0
        );

        return wrapper;
    }

    @AuraEnabled
    public static Workshop__c saveWorkshop(Workshop__c workshop) {
        // Editing is allowed only when status is Draft
        if (workshop.Id != null) {
            Workshop__c existing = [SELECT Status__c FROM Workshop__c WHERE Id = :workshop.Id LIMIT 1];
            if (existing.Status__c == 'Published' || existing.Status__c == 'Inactive' || existing.Status__c == 'Completed') {
                throw new AuraHandledException('Workshop cannot be edited once it is Published, Inactive, or Completed.');
            }
        }

        validateRequiredWorkshopFields(workshop);

        upsert workshop;
        return workshop;
    }

    @AuraEnabled
    public static void activateWorkshop(Id workshopId) {
        assertWorkshopStatusUpdateAccess();
        Workshop__c w = [
            SELECT Id, Status__c, Program__c, Cohort__c, Eligible_Term__c, Total_Sessions__c
            FROM Workshop__c
            WHERE Id = :workshopId
            LIMIT 1
        ];
        if (w.Status__c != 'Draft' && w.Status__c != 'Inactive') {
            throw new AuraHandledException('Only Draft or Inactive workshops can be published.');
        }

        validateRequiredWorkshopFields(w);

        w.Status__c = 'Published';
        update w;
    }

    @AuraEnabled
    public static void deactivateWorkshop(Id workshopId) {
        assertWorkshopStatusUpdateAccess();
        Workshop__c w = [SELECT Id, Status__c FROM Workshop__c WHERE Id = :workshopId LIMIT 1];
        if (w.Status__c != 'Published') {
            throw new AuraHandledException('Only Published workshops can be deactivated.');
        }
        w.Status__c = 'Inactive';
        update w;
    }

    @AuraEnabled
    public static void cancelWorkshop(Id workshopId) {
        Workshop__c w = [SELECT Id, Status__c FROM Workshop__c WHERE Id = :workshopId LIMIT 1];
        if (w.Status__c == 'Completed') {
            throw new AuraHandledException('Cannot cancel a Completed workshop.');
        }
        w.Status__c = 'Cancelled';
        update w;
    }

    // ── Session CRUD ─────────────────────────────────────────────────────────────

    @AuraEnabled
    public static Workshop_Session__c saveSession(Workshop_Session__c session) {
        upsert session;
        return session;
    }

    @AuraEnabled
    public static void deleteSession(Id sessionId) {
        delete [SELECT Id FROM Workshop_Session__c WHERE Id = :sessionId LIMIT 1];
    }

    // ── Batch CRUD ───────────────────────────────────────────────────────────────

    @AuraEnabled
    public static Workshop_Batch__c saveBatch(Workshop_Batch__c batch) {
        upsert batch;
        return batch;
    }

    @AuraEnabled
    public static void deleteBatch(Id batchId) {
        delete [SELECT Id FROM Workshop_Batch__c WHERE Id = :batchId LIMIT 1];
    }

    @AuraEnabled(cacheable=true)
    public static BatchWrapper getBatchDetail(Id batchId) {
        BatchWrapper wrapper = new BatchWrapper();

        wrapper.batch = [
            SELECT Id, Name, Batch_Label__c, Start_DateTime__c, End_DateTime__c,
                   Mode__c, Location__c, Meeting_Link__c, Capacity__c,
                   Total_Registered__c, Available_Seats__c, Status__c,
                   Overbooking_Threshold__c,
                   Workshop_Session__r.Workshop__c
            FROM Workshop_Batch__c
            WHERE Id = :batchId
            LIMIT 1
        ];

        wrapper.availableSeats = wrapper.batch.Available_Seats__c != null
            ? wrapper.batch.Available_Seats__c.intValue() : 9999;

        // Query registrations matching this batch's workshop + label
        wrapper.registrations = [
            SELECT Id, Name, Student__c, Student__r.Name, Student__r.Email,
                   Status__c, Registration_Date__c
            FROM Workshop_Registration__c
            WHERE Workshop__c = :wrapper.batch.Workshop_Session__r.Workshop__c
            AND Batch_Label__c = :wrapper.batch.Batch_Label__c
            AND Status__c IN ('Registered', 'Waitlisted')
            ORDER BY Registration_Date__c ASC
        ];

        return wrapper;
    }

    // ── Registration management ──────────────────────────────────────────────────

    @AuraEnabled
    public static void updateRegistrationStatus(Id registrationId, String newStatus) {
        Workshop_Registration__c reg = [
            SELECT Id, Status__c FROM Workshop_Registration__c WHERE Id = :registrationId LIMIT 1
        ];
        reg.Status__c = newStatus;
        update reg;
    }

    // ── Attendance management ─────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<Workshop_Attendance__c> getBatchAttendance(Id batchId) {
        return [
            SELECT Id, Name, Student__c, Student__r.Name, Attendance_Status__c,
                   Marked_Date__c, Notes__c, Workshop_Registration__c
            FROM Workshop_Attendance__c
            WHERE Workshop_Batch__c = :batchId
            ORDER BY Student__r.Name ASC
        ];
    }

    @AuraEnabled
    public static void saveAttendance(List<Workshop_Attendance__c> attendanceList) {
        if (attendanceList == null || attendanceList.isEmpty()) return;
        for (Workshop_Attendance__c att : attendanceList) {
            if (att.Attendance_Status__c != 'Pending') {
                att.Marked_Date__c = Date.today();
            }
        }
        update attendanceList;
    }

    // ── Lookup helpers ────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<AcademicSession> getAcademicSessions() {
        return [
            SELECT Id, Name FROM AcademicSession
            ORDER BY Name ASC
            LIMIT 100
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<SObject> getCampuses() {
        return [
            SELECT Id, Name FROM Location
            WHERE LocationType = 'Site'
            ORDER BY Name ASC
            LIMIT 50
        ];
    }

    private static void assertWorkshopDashboardReadAccess() {
        assertObjectReadable(Schema.SObjectType.Workshop__c, 'Workshop');
        assertObjectReadable(Schema.SObjectType.Workshop_Session__c, 'Workshop Session');
        assertObjectReadable(Schema.SObjectType.Workshop_Batch__c, 'Workshop Batch');
        assertObjectReadable(Schema.SObjectType.Workshop_Registration__c, 'Workshop Registration');
        assertObjectReadable(Schema.SObjectType.Contact, 'Contact');
        assertObjectReadable(Schema.SObjectType.Program, 'Program');
        assertObjectReadable(Schema.SObjectType.AcademicSession, 'Academic Session');
        assertObjectReadable(Schema.SObjectType.Location, 'Location');

        assertFieldReadable(Workshop__c.Name, 'Workshop Name');
        assertFieldReadable(Workshop__c.Status__c, 'Workshop Status');
        assertFieldReadable(Workshop__c.Total_Sessions__c, 'Total Sessions');
        assertFieldReadable(Workshop__c.Total_Registrations__c, 'Total Registrations');
        assertFieldReadable(Workshop__c.Program__c, 'Program');
        assertFieldReadable(Workshop__c.Cohort__c, 'Cohort');
        assertFieldReadable(Workshop__c.Eligible_Term__c, 'Eligible Term');
        assertFieldReadable(Workshop__c.Campus__c, 'Campus');
        assertFieldReadable(Workshop_Session__c.Session_Number__c, 'Session Number');
        assertFieldReadable(Workshop_Session__c.Session_Date__c, 'Session Date');
        assertFieldReadable(Workshop_Session__c.Mode__c, 'Session Mode');
        assertFieldReadable(Workshop_Session__c.Status__c, 'Session Status');
        assertFieldReadable(Workshop_Batch__c.Batch_Label__c, 'Batch Label');
        assertFieldReadable(Workshop_Batch__c.Status__c, 'Batch Status');
        assertFieldReadable(Workshop_Batch__c.Capacity__c, 'Batch Capacity');
        assertFieldReadable(Workshop_Batch__c.Total_Registered__c, 'Batch Total Registered');
        assertFieldReadable(Workshop_Batch__c.Available_Seats__c, 'Batch Available Seats');
        assertFieldReadable(Workshop_Registration__c.Student__c, 'Registration Student');
        assertFieldReadable(Workshop_Registration__c.Status__c, 'Registration Status');
        assertFieldReadable(Workshop_Registration__c.Batch_Label__c, 'Registration Batch Label');
        assertFieldReadable(Contact.Name, 'Student Name');
        assertFieldReadable(Contact.Email, 'Student Email');
    }

    private static void assertWorkshopStatusUpdateAccess() {
        DescribeSObjectResult describeResult = Workshop__c.SObjectType.getDescribe();
        if (!describeResult.isAccessible() || !describeResult.isUpdateable()) {
            throw new AuraHandledException('You do not have permission to update Workshops.');
        }
        if (!Workshop__c.Status__c.getDescribe().isUpdateable()) {
            throw new AuraHandledException('You do not have permission to update Workshop status.');
        }
    }

    private static void assertObjectReadable(Schema.DescribeSObjectResult describeResult, String label) {
        if (!describeResult.isAccessible()) {
            throw new AuraHandledException('You do not have access to ' + label + ' data.');
        }
    }

    private static void assertFieldReadable(Schema.SObjectField fieldRef, String label) {
        if (!fieldRef.getDescribe().isAccessible()) {
            throw new AuraHandledException('You do not have field access for ' + label + '.');
        }
    }

    private static String buildBatchKey(Id workshopId, String batchLabel) {
        return String.valueOf(workshopId) + '::' + String.valueOf(batchLabel);
    }

    private static void validateRequiredWorkshopFields(Workshop__c workshop) {
        if (workshop == null
            || workshop.Program__c == null
            || workshop.Cohort__c == null
            || workshop.Eligible_Term__c == null
            || workshop.Total_Sessions__c == null
            || workshop.Total_Sessions__c <= 0
        ) {
            throw new AuraHandledException(
                'Program, Cohort, Eligible Term, and Total Sessions (greater than 0) are required when creating or updating a Workshop.'
            );
        }
        
        // Check Description__c for publishing (required by validation rule)
        if (String.isBlank(workshop.Description__c)) {
            throw new AuraHandledException(
                'Workshop Description is required before publishing. Please add a description to the workshop record.'
            );
        }
    }

    // ── Workshop Publish Quick Action (R4: ISB-6020) ─────────────────────────────

    /**
     * @description Publishes a workshop and sends a custom email notification to eligible students.
     *              Called from workshopPublishModal LWC Quick Action.
     * @param workshopId ID of the Workshop__c record to publish
     * @param subject Custom email subject
     * @param body Custom email body
     * @param contentDocIds List of ContentDocument IDs to attach (optional)
     */
    @AuraEnabled
    public static void publishWorkshopWithEmail(Id workshopId, String subject, String body, List<String> contentDocIds) {
        if (workshopId == null) {
            throw new AuraHandledException('Workshop ID is required.');
        }
        if (String.isBlank(subject) || String.isBlank(body)) {
            throw new AuraHandledException('Subject and body are required.');
        }

        // Load workshop and validate permissions
        List<Workshop__c> workshops = [
            SELECT Id, Status__c, Name, Description__c, Program__c, Cohort__c, Eligible_Term__c, Total_Sessions__c
            FROM Workshop__c
            WHERE Id = :workshopId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        if (workshops.isEmpty()) {
            throw new AuraHandledException('Workshop not found.');
        }

        Workshop__c w = workshops[0];

        // Validate required fields before publishing
        validateRequiredWorkshopFields(w);

        // Update workshop status and set Published_Via_Quick_Action flag
        w.Status__c = 'Published';
        w.Published_Via_Quick_Action__c = true;

        try {
            update w;
        } catch (Exception ex) {
            throw new AuraHandledException('Failed to publish workshop: ' + ex.getMessage());
        }

        // Send custom email via WorkshopNotificationService
        try {
            WorkshopNotificationService.sendCustomPublishEmail(workshopId, subject, body, contentDocIds);
        } catch (Exception ex) {
            System.debug('WorkshopController.publishWorkshopWithEmail email error: ' + ex.getMessage());
            throw new AuraHandledException('Workshop published, but email notification failed: ' + ex.getMessage());
        }
    }

    /**
     * @description Returns the count of eligible students for a workshop's publish email.
     *              Used by workshopPublishModal LWC to show recipient preview.
     * @param workshopId ID of the Workshop__c record
     * @return Integer count of eligible ProgramEnrollment records
     */
    @AuraEnabled(cacheable=true)
    public static Integer getPublishRecipientCount(Id workshopId) {
        if (workshopId == null) {
            return 0;
        }

        try {
            List<Workshop__c> workshops = [
                SELECT Id, Program__c, Cohort__c, Campus__c
                FROM Workshop__c
                WHERE Id = :workshopId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            if (workshops.isEmpty() || workshops[0].Program__c == null) {
                return 0;
            }

            Workshop__c w = workshops[0];

            // Audience parity with WorkshopNotificationService:
            // ProgramEnrollment.ProgramId + Cohort(Academic_Term__c) + Location(Location__c).
            List<ProgramEnrollment> enrollments = [
                SELECT ContactId, Academic_Term__c, Location__c
                FROM ProgramEnrollment
                WHERE ProgramId = :w.Program__c
                  AND IsActive = true
                  AND ContactId != null
            ];

            Set<Id> recipientContactIds = new Set<Id>();
            for (ProgramEnrollment pe : enrollments) {
                if (w.Cohort__c != null && pe.Academic_Term__c != w.Cohort__c) {
                    continue;
                }
                if (w.Campus__c != null && pe.Location__c != w.Campus__c) {
                    continue;
                }
                recipientContactIds.add(pe.ContactId);
            }

            return recipientContactIds.size();
        } catch (Exception ex) {
            System.debug('WorkshopController.getPublishRecipientCount error: ' + ex.getMessage());
            return 0;
        }
    }
}