public without sharing class CourseOfferingParticipantLMSService {

    public enum SyncOperation { ENROLL, REMOVE, REASSIGN }

    public class COPContext {
        public Id copId;
        public Id courseOfferingId;
        public String sectionName;
        public String oldLmsGroupId;
        public String newLmsGroupId;
        public String lmsCourseId;       // Moodle Course ID from CourseOffering.LMS_Course_Id__c
        public SyncOperation operation;
        public Id participantContactId;
        public String moodleUserId;
        public CourseOfferingParticipant record;

        public COPContext(CourseOfferingParticipant cop, SyncOperation op) {
            this.copId              = cop.Id;
            this.courseOfferingId   = cop.CourseOfferingId;
            this.sectionName        = cop.Section_Name__c;
            this.oldLmsGroupId      = cop.LMS_Group_Id__c;
            this.operation          = op;
            this.participantContactId = cop.ParticipantContactId;
            this.record             = cop;
        }
    }

    // Deferred DML — populated during callouts, flushed after all callouts finish
    private static List<Error_Handling__c> pendingErrorLogs    = new List<Error_Handling__c>();
    private static Map<Id, Contact>        pendingContactUpdates = new Map<Id, Contact>();

    // ─────────────────────────────────────────────────────────────────────────
    // PUBLIC ENTRY POINT (from LWC via Controller)
    // ─────────────────────────────────────────────────────────────────────────
    public static void enqueueSyncFromLWC(List<Id> copIds) {
        // Mark all as Pending before enqueueing
        List<CourseOfferingParticipant> statusUpdate = new List<CourseOfferingParticipant>();
        for (Id id : copIds) {
            statusUpdate.add(new CourseOfferingParticipant(Id = id, LMS_Sync_Status__c = 'Pending'));
        }
        update statusUpdate;

        List<COPContext> contexts = buildContexts(copIds);
        batchAndEnqueue(contexts, false);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // BATCHING  (10 per queueable to respect API callout limits)
    // ─────────────────────────────────────────────────────────────────────────
    private static void batchAndEnqueue(List<COPContext> allContexts, Boolean isDelete) {
        if (allContexts.isEmpty()) return;
        List<COPContext> batch = new List<COPContext>();
        for (COPContext ctx : allContexts) {
            batch.add(ctx);
            if (batch.size() >= 10) {
                System.enqueueJob(new CourseOfferingParticipantLMSQueueable(batch, isDelete));
                batch = new List<COPContext>();
            }
        }
        if (!batch.isEmpty()) {
            System.enqueueJob(new CourseOfferingParticipantLMSQueueable(batch, isDelete));
        }
    }

    private static List<COPContext> buildContexts(List<Id> copIds) {
        List<COPContext> result = new List<COPContext>();
        for (CourseOfferingParticipant cop : [
            SELECT Id, CourseOfferingId, Section_Name__c, LMS_Group_Id__c, ParticipantContactId, LMS_Sync_Status__c
            FROM CourseOfferingParticipant
            WHERE Id IN :copIds AND LMS_Sync_Status__c != 'Success'
        ]) {
            result.add(new COPContext(cop, SyncOperation.ENROLL));
        }
        return result;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // QUEUEABLE ENTRY POINT
    // ─────────────────────────────────────────────────────────────────────────
    public static void processQueueableSync(List<COPContext> contexts, Boolean isDelete) {
        // Reset deferred collections for this queueable execution
        pendingErrorLogs     = new List<Error_Handling__c>();
        pendingContactUpdates = new Map<Id, Contact>();

        Set<Id> coIds      = new Set<Id>();
        Set<Id> contactIds = new Set<Id>();
        for (COPContext ctx : contexts) {
            coIds.add(ctx.courseOfferingId);
            if (ctx.participantContactId != null) contactIds.add(ctx.participantContactId);
        }

        // ── Fetch CourseOffering data (LMS Course ID + Section Mappings) ──
        Map<Id, CourseOffering> coMap = new Map<Id, CourseOffering>([
            SELECT Id, LMS_Course_Id__c, Section_Mappings__c
            FROM CourseOffering
            WHERE Id IN :coIds
        ]);

        // Parse section mapping strings  →  Map<coId, Map<SectionName, GroupId>>
        Map<Id, Map<String, String>> coSectionMap = new Map<Id, Map<String, String>>();
        for (CourseOffering co : coMap.values()) {
            Map<String, String> m = new Map<String, String>();
            if (String.isNotBlank(co.Section_Mappings__c)) {
                for (String pair : co.Section_Mappings__c.split(',')) {
                    List<String> parts = pair.split(':');
                    if (parts.size() == 2) m.put(parts[0].trim(), parts[1].trim());
                }
            }
            coSectionMap.put(co.Id, m);
        }

        // ── Resolve Moodle User IDs ──
        Map<Id, String> moodleUserMap = getMoodleUserIds(contactIds);

        // Load metadata configs
        LMS_Config__mdt enrolConfig  = LMS_Config__mdt.getInstance('EnrolStudentsToCourse');
        LMS_Config__mdt assignConfig = LMS_Config__mdt.getInstance('AssignStudentsToGroup');
        LMS_Config__mdt removeConfig = LMS_Config__mdt.getInstance('UnassignStudentsFromGroup');

        List<CourseOfferingParticipant> toUpdate = new List<CourseOfferingParticipant>();

        if (isDelete) {
            processDeleteSync(contexts, moodleUserMap, removeConfig, toUpdate);
        } else {
            processTwoPhaseSync(contexts, coMap, coSectionMap, moodleUserMap, enrolConfig, assignConfig, removeConfig, toUpdate);
        }

        // ── Flush all deferred DML after all callouts ──
        if (!toUpdate.isEmpty()) {
            Map<Id, CourseOfferingParticipant> deduped = new Map<Id, CourseOfferingParticipant>();
            for (CourseOfferingParticipant p : toUpdate) deduped.put(p.Id, p);
            update deduped.values();
        }
        if (!pendingContactUpdates.isEmpty()) update pendingContactUpdates.values();
        if (!pendingErrorLogs.isEmpty())      insert pendingErrorLogs;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TWO-PHASE SYNC
    // Phase 1 → Enrol student to Moodle Course  (enrol_manual_enrol_users)
    // Phase 2 → Assign student to Group/Section (core_group_add_group_members)
    // ─────────────────────────────────────────────────────────────────────────
    private static void processTwoPhaseSync(
        List<COPContext> contexts,
        Map<Id, CourseOffering> coMap,
        Map<Id, Map<String, String>> coSectionMap,
        Map<Id, String> moodleUserMap,
        LMS_Config__mdt enrolConfig,
        LMS_Config__mdt assignConfig,
        LMS_Config__mdt removeConfig,
        List<CourseOfferingParticipant> toUpdate
    ) {
        // ── Pre-validate all contexts ──
        List<COPContext> phase1Eligible = new List<COPContext>();

        for (COPContext ctx : contexts) {
            ctx.moodleUserId = moodleUserMap.get(ctx.participantContactId);
            if (String.isBlank(ctx.moodleUserId)) {
                logError('Phase 1 – Course Enrolment',
                    'No Moodle User ID resolved for Contact [' + ctx.participantContactId + ']. ' +
                    'Ensure Admit_Email__c (for Students) or Email is populated and matches a Moodle username. COP Id: ' + ctx.copId,
                    'VALIDATION_ERROR', ctx.copId, '', '');
                ctx.record.LMS_Sync_Status__c = 'Failed';
                toUpdate.add(ctx.record);
                continue;
            }

            CourseOffering co = coMap.get(ctx.courseOfferingId);
            ctx.lmsCourseId = (co != null) ? co.LMS_Course_Id__c : null;
            if (String.isBlank(ctx.lmsCourseId)) {
                logError('Phase 1 – Course Enrolment',
                    'LMS_Course_Id__c is blank on Course Offering [' + ctx.courseOfferingId + ']. ' +
                    'Please populate the Moodle Course ID before syncing. COP Id: ' + ctx.copId,
                    'VALIDATION_ERROR', ctx.copId, '', '');
                ctx.record.LMS_Sync_Status__c = 'Failed';
                toUpdate.add(ctx.record);
                continue;
            }
            phase1Eligible.add(ctx);
        }

        if (phase1Eligible.isEmpty()) return;

        // ── PHASE 1: Course Enrolment ──
        List<COPContext> phase2Eligible = new List<COPContext>();
        if (enrolConfig != null) {
            phase2Eligible = executeCourseEnrolment(phase1Eligible, enrolConfig, toUpdate);
        } else {
            // If metadata not deployed yet, skip Phase 1 and proceed to group mapping only
            logError('Phase 1 – Course Enrolment',
                'EnrolStudentsToCourse LMS_Config__mdt record is missing. Skipping Phase 1 and proceeding to Group Assignment.',
                'CONFIG_MISSING', null, '', '');
            phase2Eligible = phase1Eligible;
        }

        if (phase2Eligible.isEmpty()) return;

        // ── PHASE 2: Group/Section Assignment ──
        String removeBody = removeConfig != null
            ? 'wstoken=' + removeConfig.wsToken__c + '&wsfunction=' + removeConfig.wsFunction__c + '&moodlewsrestformat=json' : '';
        String assignBody = assignConfig != null
            ? 'wstoken=' + assignConfig.wsToken__c + '&wsfunction=' + assignConfig.wsFunction__c + '&moodlewsrestformat=json' : '';

        List<COPContext> removeSubjects = new List<COPContext>();
        List<COPContext> assignSubjects = new List<COPContext>();
        Integer removeIdx = 0;
        Integer assignIdx = 0;

        for (COPContext ctx : phase2Eligible) {
            Map<String, String> sectionMapForCO = coSectionMap.get(ctx.courseOfferingId);

            // Single-section fallback: auto-use the only section
            if (String.isBlank(ctx.sectionName) && sectionMapForCO != null && sectionMapForCO.size() == 1) {
                ctx.sectionName = new List<String>(sectionMapForCO.keySet())[0];
            }

            if (sectionMapForCO != null && String.isNotBlank(ctx.sectionName)
                    && sectionMapForCO.containsKey(ctx.sectionName.trim())) {
                ctx.newLmsGroupId = sectionMapForCO.get(ctx.sectionName.trim());
            }

            if (String.isBlank(ctx.newLmsGroupId)) {
                logError('Phase 2 – Group Assignment',
                    'Section "' + ctx.sectionName + '" not found in Section_Mappings__c for Course Offering [' + ctx.courseOfferingId + ']. ' +
                    'Expected format: SectionA:GroupId1,SectionB:GroupId2. COP Id: ' + ctx.copId,
                    'MAPPING_ERROR', ctx.copId, '', '');
                ctx.record.LMS_Sync_Status__c = 'Failed';
                toUpdate.add(ctx.record);
                continue;
            }

            // Determine reassign vs fresh enrol
            if (String.isNotBlank(ctx.oldLmsGroupId) && ctx.oldLmsGroupId != ctx.newLmsGroupId) {
                ctx.operation = SyncOperation.REASSIGN;
            } else {
                ctx.operation = SyncOperation.ENROLL;
            }

            if (ctx.operation == SyncOperation.REASSIGN && removeConfig != null) {
                removeBody += '&members[' + removeIdx + '][groupid]=' + ctx.oldLmsGroupId;
                removeBody += '&members[' + removeIdx + '][userid]='  + ctx.moodleUserId;
                removeSubjects.add(ctx);
                removeIdx++;
            }

            if (assignConfig != null) {
                assignBody += '&members[' + assignIdx + '][groupid]=' + ctx.newLmsGroupId;
                assignBody += '&members[' + assignIdx + '][userid]='  + ctx.moodleUserId;
                assignSubjects.add(ctx);
                assignIdx++;
            }
        }

        if (removeIdx > 0) executeGroupCallout(removeBody, removeSubjects, false, toUpdate);
        if (assignIdx > 0) executeGroupCallout(assignBody, assignSubjects, true, toUpdate);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // PHASE 1 – Course Enrolment Callout
    // Returns list of contexts that succeeded (eligible for Phase 2)
    // ─────────────────────────────────────────────────────────────────────────
    private static List<COPContext> executeCourseEnrolment(
        List<COPContext> subjects,
        LMS_Config__mdt config,
        List<CourseOfferingParticipant> toUpdate
    ) {
        String body = 'wstoken=' + config.wsToken__c
            + '&wsfunction=' + config.wsFunction__c
            + '&moodlewsrestformat=json';

        Integer idx = 0;
        for (COPContext ctx : subjects) {
            body += '&enrolments[' + idx + '][userid]='   + ctx.moodleUserId;
            body += '&enrolments[' + idx + '][courseid]=' + ctx.lmsCourseId;
            body += '&enrolments[' + idx + '][roleid]=5'; // 5 = Student role in Moodle
            idx++;
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:LMS_Integration');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        req.setTimeout(120000);
        req.setBody(body);

        try {
            HttpResponse res = new Http().send(req);
            String resBody   = res.getBody();
            if (res.getStatusCode() == 200 && !resBody.contains('"exception":')) {
                return subjects; // All passed → proceed to Phase 2
            } else {
                String errMsg = 'Phase 1 Course Enrolment rejected by Moodle. ';
                errMsg += resBody.contains('"message":') ? parseMoodleError(resBody)
                    : 'HTTP ' + res.getStatusCode() + ': ' + resBody.left(500);
                for (COPContext ctx : subjects) {
                    logError('Phase 1 – Course Enrolment',
                        errMsg + ' | Moodle User: ' + ctx.moodleUserId + ' | Course: ' + ctx.lmsCourseId + ' | COP: ' + ctx.copId,
                        String.valueOf(res.getStatusCode()), ctx.copId, body, resBody);
                    ctx.record.LMS_Sync_Status__c = 'Failed';
                    toUpdate.add(ctx.record);
                }
                return new List<COPContext>(); // Nothing proceeds to Phase 2
            }
        } catch (Exception e) {
            for (COPContext ctx : subjects) {
                logError('Phase 1 – Course Enrolment',
                    'API Exception: ' + e.getMessage() + ' | Moodle User: ' + ctx.moodleUserId + ' | Course: ' + ctx.lmsCourseId + ' | COP: ' + ctx.copId,
                    'EXCEPTION', ctx.copId, body, '');
                ctx.record.LMS_Sync_Status__c = 'Failed';
                toUpdate.add(ctx.record);
            }
            return new List<COPContext>();
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // PHASE 2 – Group Assignment Callout
    // ─────────────────────────────────────────────────────────────────────────
    private static void executeGroupCallout(
        String body,
        List<COPContext> subjects,
        Boolean isAssign,
        List<CourseOfferingParticipant> toUpdate
    ) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:LMS_Integration');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        req.setTimeout(120000);
        req.setBody(body);

        try {
            HttpResponse res = new Http().send(req);
            String resBody   = res.getBody();
            if (res.getStatusCode() == 200 && !resBody.contains('"exception":')) {
                if (isAssign) {
                    for (COPContext ctx : subjects) {
                        ctx.record.LMS_Group_Id__c   = ctx.newLmsGroupId;
                        ctx.record.Section_Name__c   = ctx.sectionName;
                        ctx.record.LMS_Sync_Status__c = 'Success';
                        toUpdate.add(ctx.record);
                    }
                }
            } else {
                if (isAssign) {
                    String errMsg = 'Phase 2 Group Assignment rejected by Moodle. ';
                    errMsg += resBody.contains('"message":') ? parseMoodleError(resBody)
                        : 'HTTP ' + res.getStatusCode() + ': ' + resBody.left(500);
                    for (COPContext ctx : subjects) {
                        logError('Phase 2 – Group Assignment',
                            errMsg + ' | Moodle User: ' + ctx.moodleUserId + ' | Group: ' + ctx.newLmsGroupId + ' | COP: ' + ctx.copId,
                            String.valueOf(res.getStatusCode()), ctx.copId, body, resBody);
                        ctx.record.LMS_Sync_Status__c = 'Failed';
                        toUpdate.add(ctx.record);
                    }
                }
            }
        } catch (Exception e) {
            if (isAssign) {
                for (COPContext ctx : subjects) {
                    logError('Phase 2 – Group Assignment',
                        'API Exception: ' + e.getMessage() + ' | Moodle User: ' + ctx.moodleUserId + ' | Group: ' + ctx.newLmsGroupId + ' | COP: ' + ctx.copId,
                        'EXCEPTION', ctx.copId, body, '');
                    ctx.record.LMS_Sync_Status__c = 'Failed';
                    toUpdate.add(ctx.record);
                }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // DELETE SYNC (Un-enrol from group on COP deletion)
    // ─────────────────────────────────────────────────────────────────────────
    private static void processDeleteSync(
        List<COPContext> contexts,
        Map<Id, String> moodleUserMap,
        LMS_Config__mdt removeConfig,
        List<CourseOfferingParticipant> toUpdate
    ) {
        if (removeConfig == null) return;
        String removeBody = 'wstoken=' + removeConfig.wsToken__c + '&wsfunction=' + removeConfig.wsFunction__c + '&moodlewsrestformat=json';
        List<COPContext> removeSubjects = new List<COPContext>();
        Integer idx = 0;
        for (COPContext ctx : contexts) {
            ctx.moodleUserId = moodleUserMap.get(ctx.participantContactId);
            if (String.isBlank(ctx.moodleUserId) || String.isBlank(ctx.oldLmsGroupId)) continue;
            removeBody += '&members[' + idx + '][groupid]=' + ctx.oldLmsGroupId;
            removeBody += '&members[' + idx + '][userid]='  + ctx.moodleUserId;
            removeSubjects.add(ctx);
            idx++;
        }
        if (idx > 0) executeGroupCallout(removeBody, removeSubjects, false, toUpdate);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MOODLE USER ID RESOLUTION
    // Priority: cached LMS_External_ID__c → New_Admit_Email__c (Students) → Email
    // ─────────────────────────────────────────────────────────────────────────
    public static Map<Id, String> getMoodleUserIds(Set<Id> contactIds) {
        Map<Id, String> results = new Map<Id, String>();
        LMS_Config__mdt config = LMS_Config__mdt.getInstance('MoodleUserIdSync');
        if (config == null || contactIds.isEmpty()) return results;

        Map<Id, Contact> contactMap = new Map<Id, Contact>([
            SELECT Id, Email, New_Admit_Email__c, RecordType.Name, LMS_External_ID__c
            FROM Contact
            WHERE Id IN :contactIds
        ]);

        Map<String, List<Id>> emailToContactIds = new Map<String, List<Id>>();
        String body = 'wstoken=' + config.wsToken__c + '&wsfunction=' + config.wsFunction__c + '&moodlewsrestformat=json&field=username';
        Integer valIdx = 0;

        for (Contact c : contactMap.values()) {
            // Use cached Moodle ID if available — avoids redundant API callout
            if (String.isNotBlank(c.LMS_External_ID__c)) {
                results.put(c.Id, c.LMS_External_ID__c);
                continue;
            }

            // Pick the correct email: Admit email for Students, standard email otherwise
            String targetEmail = c.Email;
            if (c.RecordType != null && c.RecordType.Name == 'Student' && String.isNotBlank(c.New_Admit_Email__c)) {
                targetEmail = c.New_Admit_Email__c;
            }

            if (String.isNotBlank(targetEmail)) {
                String emailKey = targetEmail.trim().toLowerCase();
                body += '&values[' + (valIdx++) + ']=' + EncodingUtil.urlEncode(emailKey, 'UTF-8');
                if (!emailToContactIds.containsKey(emailKey)) emailToContactIds.put(emailKey, new List<Id>());
                emailToContactIds.get(emailKey).add(c.Id);
            }
        }

        if (valIdx == 0) return results; // All IDs were cached — no callout needed

        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:LMS_Integration');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        req.setBody(body);

        try {
            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() == 200) {
                List<Object> userList = (List<Object>) JSON.deserializeUntyped(res.getBody());
                for (Object obj : userList) {
                    Map<String, Object> uMap = (Map<String, Object>) obj;
                    String mId  = String.valueOf(uMap.get('id'));
                    String uname = String.valueOf(uMap.get('username'));
                    if (String.isNotBlank(uname)) {
                        uname = uname.toLowerCase();
                        if (emailToContactIds.containsKey(uname)) {
                            for (Id cId : emailToContactIds.get(uname)) {
                                results.put(cId, mId);
                                // Cache to Contact.LMS_External_ID__c for future syncs (deferred DML)
                                pendingContactUpdates.put(cId, new Contact(Id = cId, LMS_External_ID__c = mId));
                            }
                        }
                    }
                }
            }
        } catch (Exception e) {}

        return results;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // HELPERS
    // ─────────────────────────────────────────────────────────────────────────
    private static String parseMoodleError(String body) {
        try {
            Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(body);
            String msg = String.valueOf(m.get('message'));
            if (m.containsKey('debuginfo')       && m.get('debuginfo')       != null) msg += ' | Debug: '         + String.valueOf(m.get('debuginfo'));
            if (m.containsKey('invalidparameter') && m.get('invalidparameter') != null) msg += ' | Invalid Param: ' + String.valueOf(m.get('invalidparameter'));
            return msg;
        } catch (Exception e) { return body; }
    }

    private static void logError(String component, String message, String statusCode, String recordId, String request, String response) {
        Error_Handling__c log = new Error_Handling__c();
        log.Component_Type__c    = component;
        log.Error_message__c     = message  != null && message.length()  > 255    ? message.substring(0, 255)    : message;
        log.Error_Status_Code__c = statusCode;
        log.Record_Refrence_Id__c = recordId;
        log.Request__c           = request  != null && request.length()  > 131000 ? request.substring(0, 131000)  : request;
        log.Response__c          = response != null && response.length() > 131000 ? response.substring(0, 131000) : response;
        pendingErrorLogs.add(log);
    }
}