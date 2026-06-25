/**
 * Handler for CourseOffering trigger.
 * Responsibilities:
 *  - Parse multi-select picklist Exam_Types__c
 *  - Ensure an Exam_Schedule__c exists per Program / Academic_term__c / Location__c
 *  - Ensure Examination records exist per CourseOffering + Exam Type under the schedule
 *  - Assign created Examination records to the Exam_Managers queue (if available)
 *  - Send a single notification email to queue members listing created Examination records
 *
 * Notes / assumptions:
 *  - CourseOffering object has fields: Program__c, Academic_term__c, Location__c, Academic_Session__c
 *  - Exam_Schedule__c has fields: Program__c, Academic_term__c, Location__c
 *  - Examination object has fields: Program__c, Academic_term__c, Academic_Session__c,
 *      Course_Offering__c (lookup), Location__c, Exam_Schedule__c (lookup), Exam_Types__c
 *  - Queue name for assignment is 'Exam_Managers' (Group with Type = 'Queue'). If not found,
 *    the owner falls back to the running user.
 *  - Multi-select values are semicolon (;) separated. The special value 'No-Exam' is ignored.
 */
public without sharing class CourseOfferingTriggerHandler {

    public static Id ExamScheduleIds;

    // Custom Exception class for cleaner UI error messages
    public class CourseOfferingException extends Exception {}

    private static void handleDmlError(DmlException e) {
        String msg = e.getDmlMessage(0);
        // Clean error message directly for Flow presentation
        String cleanMsg = 'Error: ' + msg.substringBefore('\n');
        Boolean addedToTrigger = false;
        if (Trigger.isExecuting && Trigger.new != null) {
            for (SObject rec : Trigger.new) {
                try {
                    rec.addError(cleanMsg, false);
                    addedToTrigger = true;
                } catch (Exception ex) {}
            }
        }
        if (!addedToTrigger) {
            AuraHandledException auraEx = new AuraHandledException(cleanMsg);
            auraEx.setMessage(cleanMsg);
            throw auraEx;
        }
    }

    // Simple recursion guard for same transaction
    private static Boolean hasRun = false;

    // ===== Fix by Diksha =====
    // Normalize Exam Type to ACTIVE Examination picklist values
    private static String normalizeExamType(String examType) {
        if (String.isBlank(examType)) return examType;

        if (examType.equalsIgnoreCase('Midterm')) {
            return 'Mid-Term';
        }
        if (examType.equalsIgnoreCase('Endterm')) {
            return 'End-Term';
        }
        return examType;
    }

    public static void handleAfter(List<CourseOffering> newRecords) {
        if (hasRun) return;
        hasRun = true;

        if (newRecords == null || newRecords.isEmpty()) return;

        final String QUEUE_NAME = 'Exam Managers';
        final String NO_EXAM_VALUE = 'No-Exam';

        // ===== DYNAMIC LOCATION RESOLUTION =====
        Set<Id> locIds = new Set<Id>();
        for (CourseOffering co : newRecords) {
            if (co.Location__c != null) locIds.add(co.Location__c);
        }
        
        Id triggerLocId = null;
        Set<String> namesToQuery = new Set<String>();
        if (ExamScheduleIds != null) {
            for (SObject es : Database.query('SELECT Location__c FROM Exam_Schedule__c WHERE Id = :ExamScheduleIds')) {
                Id lId = (Id)es.get('Location__c');
                if (lId != null) {
                    locIds.add(lId);
                    triggerLocId = lId;
                }
            }
        }

        Map<String, Id> nameToLocId = new Map<String, Id>();
        Map<Id, String> idToLocName = new Map<Id, String>();

        if (!locIds.isEmpty()) {
            for (SObject loc : Database.query('SELECT Id, Name FROM Location WHERE Id IN :locIds')) {
                String n = (String)loc.get('Name');
                Id i = (Id)loc.get('Id');
                idToLocName.put(i, n);
                if (n != null) {
                    nameToLocId.put(n, i);
                    if (triggerLocId == null || i == triggerLocId) {
                        if (n.contains('&')) {
                            for (String s : n.split('&')) namesToQuery.add(s.trim());
                        }
                    }
                }
            }
        }
        if (!namesToQuery.isEmpty()) {
            for (SObject loc : Database.query('SELECT Id, Name FROM Location WHERE Name IN :namesToQuery')) {
                nameToLocId.put((String)loc.get('Name'), (Id)loc.get('Id'));
                idToLocName.put((Id)loc.get('Id'), (String)loc.get('Name'));
            }
        }

        Map<String, List<CourseOffering>> keyToCourseOfferings = new Map<String, List<CourseOffering>>();
        Set<String> programSet = new Set<String>();
        Set<String> termSet = new Set<String>();
        Set<String> locationSet = new Set<String>();
        Map<Id, Set<String>> coToExamTypes = new Map<Id, Set<String>>();

        for (CourseOffering co : newRecords) {
            // STRICT FILTERING: Only process Course Offerings whose Location EXACTLY matches
            // the created Exam Schedule's Location (if launched manually from UI via Flow).
            if (triggerLocId != null && co.Location__c != triggerLocId) {
                continue;
            }

            Set<String> parsed = new Set<String>();
            Boolean skipThisCourseOffering = false;

            try {
                if (co.Exam_Types__c != null && co.Exam_Types__c != 'No-Exam') {
                    for (String s : co.Exam_Types__c.split(';')) {
                        String trimmed = s != null ? s.trim() : '';
                        if (trimmed == '') continue;

                        if (trimmed.equalsIgnoreCase(NO_EXAM_VALUE)) {
                            skipThisCourseOffering = true;
                            break;
                        }

                        // existing logic (unchanged)
                        if (trimmed.equalsIgnoreCase('Mid-Term')) {
                            trimmed = 'Midterm';
                        } else if (trimmed.equalsIgnoreCase('End-Term')) {
                            trimmed = 'Endterm';
                        }

                        parsed.add(trimmed);
                    }
                }
            } catch (Exception ex) {
                // defensive
            }

            if (skipThisCourseOffering || parsed.isEmpty()) continue;

            coToExamTypes.put(co.Id, parsed);

            String prog = co.Program__c;
            String term = co.Academic_term__c;
            
            // ===== REQUIREMENT: Split "Hyderabad & Mohali" etc into separate locations for separate schedules =====
            List<String> locsToProcess = new List<String>();
            if (co.Location__c != null) {
                String locName = idToLocName.get(co.Location__c);
                if (locName != null && locName.contains('&')) {
                    for (String part : locName.split('&')) {
                        String trimmedName = part.trim();
                        if (nameToLocId.containsKey(trimmedName)) {
                            locsToProcess.add(nameToLocId.get(trimmedName));
                        }
                    }
                    if (locsToProcess.isEmpty()) {
                        locsToProcess.add(co.Location__c);
                    }
                } else {
                    locsToProcess.add(co.Location__c);
                }
            }

            for (String locId : locsToProcess) {

                String key = (prog == null ? '' : prog) + '||' +
                             (term == null ? '' : term) + '||' +
                             locId;

                if (!keyToCourseOfferings.containsKey(key)) {
                    keyToCourseOfferings.put(key, new List<CourseOffering>());
                }
                keyToCourseOfferings.get(key).add(co);

                if (prog != null) programSet.add(prog);
                if (term != null) termSet.add(term);
                locationSet.add(locId);
            }
        }

        if (coToExamTypes.isEmpty()) return;

        List<Exam_Schedule__c> schedules = new List<Exam_Schedule__c>();

        if (!programSet.isEmpty() || !termSet.isEmpty() || !locationSet.isEmpty() || ExamScheduleIds != null) {
            String q = 'SELECT Id, Program__c, Academic_term__c, Location__c FROM Exam_Schedule__c WHERE ';
            List<String> clauses = new List<String>();

            if (!programSet.isEmpty()) clauses.add('Program__c IN :programSet');
            if (!termSet.isEmpty()) clauses.add('Academic_term__c IN :termSet');
            
            // FIX: Ensure locationSet contains IDs to satisfy the IN clause for Lookup fields
            if (!locationSet.isEmpty()) clauses.add('Location__c IN :locationSet');

            if (ExamScheduleIds != null) {
                q += 'Id = \'' + ExamScheduleIds + '\'';
                if (!clauses.isEmpty()) {
                    q += ' OR (' + String.join(clauses, ' AND ') + ')';
                }
            } else if (!clauses.isEmpty()) {
                q += String.join(clauses, ' AND ');
            }

            q += ' ORDER BY CreatedDate Desc';
            schedules = Database.query(q);
        }

        Map<String, Exam_Schedule__c> keyToSchedule = new Map<String, Exam_Schedule__c>();
        Exam_Schedule__c flowProvidedSchedule = null;

        for (Exam_Schedule__c s : schedules) {
            String k = (s.Program__c == null ? '' : s.Program__c) + '||' +
                       (s.Academic_term__c == null ? '' : s.Academic_term__c) + '||' +
                       (s.Location__c == null ? '' : s.Location__c);
            if (!keyToSchedule.containsKey(k)) keyToSchedule.put(k, s);
            
            if (ExamScheduleIds != null && (Id)s.Id == (Id)ExamScheduleIds) {
                // ONLY allow repurposing if the explicitly created schedule is a compound one.
                // If the user created a single location schedule (e.g., 'Mohali'), respect it completely!
                String locName = idToLocName.get(s.Location__c);
                if (locName != null && locName.contains('&')) {
                    flowProvidedSchedule = s;
                }
            }
        }

        List<Exam_Schedule__c> schedulesToInsert = new List<Exam_Schedule__c>();
        List<Exam_Schedule__c> schedulesToUpdate = new List<Exam_Schedule__c>();

        for (String key : keyToCourseOfferings.keySet()) {
            if (!keyToSchedule.containsKey(key)) {
                List<String> parts = key.split('\\|\\|');
                
                if (flowProvidedSchedule != null && flowProvidedSchedule.Id != null) {
                    if (parts.size() > 0 && parts[0] != '') flowProvidedSchedule.Program__c = parts[0];
                    if (parts.size() > 1 && parts[1] != '') flowProvidedSchedule.Academic_term__c = parts[1];
                    if (parts.size() > 2 && parts[2] != '') flowProvidedSchedule.Location__c = (Id)parts[2];
                    schedulesToUpdate.add(flowProvidedSchedule);
                    keyToSchedule.put(key, flowProvidedSchedule);
                    flowProvidedSchedule = null;
                } else {
                    Exam_Schedule__c es = new Exam_Schedule__c();
                    if (parts.size() > 0 && parts[0] != '') es.Program__c = parts[0];
                    if (parts.size() > 1 && parts[1] != '') es.Academic_term__c = parts[1];
                    // Assignment to Lookup is now safe because parts[2] is a resolved ID
                    if (parts.size() > 2 && parts[2] != '') es.Location__c = (Id)parts[2];
                    schedulesToInsert.add(es);
                }
            }
        }

        if (!schedulesToUpdate.isEmpty()) {
            try {
                update schedulesToUpdate;
            } catch (DmlException e) {
                handleDmlError(e);
                return;
            }
        }

        if (!schedulesToInsert.isEmpty()) {
            try {
                insert schedulesToInsert;
                for (Exam_Schedule__c s : schedulesToInsert) {
                    String k = (s.Program__c == null ? '' : s.Program__c) + '||' +
                               (s.Academic_term__c == null ? '' : s.Academic_term__c) + '||' +
                               (s.Location__c == null ? '' : s.Location__c);
                    keyToSchedule.put(k, s);
                }
            } catch (DmlException e) { handleDmlError(e); return; }
        }

        // Cleanup: If the UI-created record had '&' and wasn't reused/fixed, delete it to avoid 'unwanted' 0-exam records
        if (flowProvidedSchedule != null && flowProvidedSchedule.Id != null) {
            String ln = idToLocName.get(flowProvidedSchedule.Location__c);
            if (ln != null && ln.contains('&')) {
                try { delete flowProvidedSchedule; } catch (Exception ignore) {}
            }
        }

        Set<Id> scheduleIds = new Set<Id>();
        for (Exam_Schedule__c s : keyToSchedule.values()) scheduleIds.add(s.Id);

        Map<String, Examination> uniqueExamLookup = new Map<String, Examination>();
        for (Examination ex : [
            SELECT Id, Exam_Schedule__c, Course_Offering__c, Exam_Type__c
            FROM Examination
            WHERE Exam_Schedule__c IN :scheduleIds
            AND Course_Offering__c IN :coToExamTypes.keySet()
        ]) {
            String k = ex.Exam_Schedule__c + '||' + ex.Course_Offering__c + '||' + ex.Exam_Type__c;
            uniqueExamLookup.put(k, ex);
        }

        List<Examination> examsToInsert = new List<Examination>();

        for (String key : keyToCourseOfferings.keySet()) {
            Exam_Schedule__c schedule = keyToSchedule.get(key);
            for (CourseOffering co : keyToCourseOfferings.get(key)) {
for (String et : coToExamTypes.get(co.Id)) {
                    String examKey = schedule.Id + '||' + co.Id + '||' + normalizeExamType(et);
                    if (!uniqueExamLookup.containsKey(examKey)) {
                        Examination ex = new Examination();
                        ex.Exam_Schedule__c = schedule.Id;
                        ex.Course_Offering__c = co.Id;

                        // ===== Fix by Diksha =====
                        ex.Exam_Type__c = normalizeExamType(et);

                        ex.Program__c = co.Program__c;
                        ex.Academic_term__c = co.Academic_term__c;

                        // RESOLUTION: Resolve Name string from ID for record Name field
                        String campusName = idToLocName.containsKey(schedule.Location__c) ? idToLocName.get(schedule.Location__c) : '';
                        ex.Name = 'Exam-' +
                            co.Name + ' - ' +
                            normalizeExamType(et) + ' - ' +
                            campusName;
                        try { ex.Academic_Session__c = co.AcademicSessionId; } catch (Exception ignore) {}
                        ex.Venue__c = schedule.Location__c; // Assign the ID from schedule
                        try {
                            // Assign Location Name to Location field to correctly display the Name visually
                            ex.put('Location__c', campusName);
                        } catch (Exception ignore) {}
                        ex.Course_Catalog__c = co.LearningCourseId;
                        examsToInsert.add(ex);
                        uniqueExamLookup.put(examKey, ex);
                    }
                }
            }
        }

        if (examsToInsert.isEmpty()) return;

        Id ownerId = null;
        Group targetQueue = null;
        try {
            List<Group> groups = [SELECT Id FROM Group WHERE Type = 'Queue' AND Name = :QUEUE_NAME LIMIT 1];
            if (!groups.isEmpty()) {
                targetQueue = groups[0];
                ownerId = targetQueue.Id;
            }
        } catch (Exception e) {}

        if (ownerId == null) ownerId = UserInfo.getUserId();

        for (Examination ex : examsToInsert) {
            ex.OwnerId = ownerId;
        }

        try {
            insert examsToInsert;
        } catch (DmlException e) {
            handleDmlError(e);
            return;
        }

        Set<String> recipientUserIds = new Set<String>();
        if (targetQueue != null) {
            for (GroupMember gm : [SELECT UserOrGroupId FROM GroupMember WHERE GroupId = :targetQueue.Id]) {
                recipientUserIds.add(gm.UserOrGroupId);
            }
            if (!recipientUserIds.isEmpty()) {
                Set<String> realUsers = new Set<String>();
                for (User u : [SELECT Id FROM User WHERE Id IN :recipientUserIds]) realUsers.add(u.Id);
                recipientUserIds = realUsers;
            }
        }

        if (recipientUserIds.isEmpty()) recipientUserIds.add(UserInfo.getUserId());

        CustomNotificationType cnType =
            [SELECT Id FROM CustomNotificationType WHERE DeveloperName = 'Push_Notification' LIMIT 1];

        Set<Id> ExScIds = new Set<Id>();
        for (Examination ex : examsToInsert) {
            if (ExScIds.contains(ex.Exam_Schedule__c)) continue;

            ExScIds.add(ex.Exam_Schedule__c);
            Messaging.CustomNotification cn = new Messaging.CustomNotification();
            cn.setTitle('Action Needed: Exam Schedule');
            cn.setBody('Exam Schedule requires your attention.');
            cn.setTargetId(ex.Exam_Schedule__c);
            cn.setNotificationTypeId(cnType.Id);
            cn.setSenderId(UserInfo.getUserId());
            cn.send(recipientUserIds);
        }
    }

    @InvocableMethod(label='createExamFromExamSchedule' description='Create Examination records from Exam Schedule records' category='ISB')
    public static void createExamFromExamSchedule(List<coWrapper> wrappers) {
        if (wrappers == null || wrappers.isEmpty()) return;
        ExamScheduleIds = wrappers[0].EsId;
        handleAfter(wrappers[0].courseOfferings);
    }

    public class coWrapper {
        @InvocableVariable(label='Exam Type' description='Exam Type to create Examination for')
        public List<CourseOffering> courseOfferings;
        @InvocableVariable public Id EsId;
    }
}