public without sharing class COParticipantDashCtrl {

    // ─── Inner classes ───────────────────────────────────────────────────────

    public class FilterOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        public FilterOption(String l, String v) { label = l; value = v; }
    }

    public class OfferingRow {
        @AuraEnabled public Id      id;
        @AuraEnabled public String  name;
        @AuraEnabled public String  academicYear;
        @AuraEnabled public String  programName;
        @AuraEnabled public String  termName;
        @AuraEnabled public String  sessionName;
        @AuraEnabled public Integer totalParticipants;
        @AuraEnabled public Integer pendingCount;
        @AuraEnabled public Integer failedCount;
        @AuraEnabled public Integer successCount;
    }

    public class OfferingResponse {
        @AuraEnabled public List<OfferingRow> records;
        @AuraEnabled public Integer           total;
    }

    public class ParticipantRow {
        @AuraEnabled public Id     id;
        @AuraEnabled public String name;
        @AuraEnabled public String contactId;
        @AuraEnabled public String section;
        @AuraEnabled public String lmsGroupId;
        @AuraEnabled public String lmsSyncStatus;
        @AuraEnabled public String lmsCourseId;   // For display in history views
    }

    public class DashboardStats {
        @AuraEnabled public Integer totalParticipants;
        @AuraEnabled public Integer pendingParticipants;
        @AuraEnabled public Integer successParticipants;
        @AuraEnabled public Integer failedParticipants;
        @AuraEnabled public Integer totalOfferings;
        @AuraEnabled public Integer offeringsNeedingSync;
        @AuraEnabled public Integer offeringsFullySuccess;
        @AuraEnabled public Integer offeringsWithFailed;
    }

    // ─── Cascading Filter Options ────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<FilterOption> getAcademicYearOptions() {
        List<FilterOption> opts = new List<FilterOption>{ new FilterOption('-- All Years --', '') };
        for (AcademicYear ay : [SELECT Name FROM AcademicYear ORDER BY Name ASC LIMIT 100]) {
            opts.add(new FilterOption(ay.Name, ay.Name));
        }
        return opts;
    }

    @AuraEnabled(cacheable=true)
    public static List<FilterOption> getProgramOptions() {
        List<FilterOption> opts = new List<FilterOption>{ new FilterOption('-- All Programs --', '') };
        for (Program p : [SELECT Name FROM Program ORDER BY Name ASC LIMIT 100]) {
            opts.add(new FilterOption(p.Name, p.Name));
        }
        return opts;
    }

    @AuraEnabled(cacheable=true)
    public static List<FilterOption> getTermOptions(String programName, String yearName) {
        List<FilterOption> opts = new List<FilterOption>{ new FilterOption('-- All Terms --', '') };
        String q = 'SELECT Name FROM AcademicTerm WHERE Id != NULL';
        if (String.isNotBlank(programName)) q += ' AND Program__r.Name = :programName';
        if (String.isNotBlank(yearName))    q += ' AND AcademicYear.Name = :yearName';
        q += ' ORDER BY Name ASC LIMIT 100';
        for (AcademicTerm t : Database.query(q)) opts.add(new FilterOption(t.Name, t.Name));
        return opts;
    }

    @AuraEnabled(cacheable=true)
    public static List<FilterOption> getSessionOptions(String programName, String termName) {
        List<FilterOption> opts = new List<FilterOption>{ new FilterOption('-- All Sessions --', '') };
        String q = 'SELECT Name FROM AcademicSession WHERE Id != NULL';
        if (String.isNotBlank(programName)) q += ' AND Program__r.Name = :programName';
        if (String.isNotBlank(termName))    q += ' AND AcademicTerm.Name = :termName';
        q += ' ORDER BY Name ASC LIMIT 100';
        for (AcademicSession s : Database.query(q)) opts.add(new FilterOption(s.Name, s.Name));
        return opts;
    }

    // ─── Dashboard Stats ─────────────────────────────────────────────────────

    @AuraEnabled
    public static DashboardStats getDashboardStats() {
        DashboardStats stats = new DashboardStats();
        stats.totalParticipants    = 0;
        stats.pendingParticipants  = 0;
        stats.successParticipants  = 0;
        stats.failedParticipants   = 0;
        stats.totalOfferings       = 0;

        for (AggregateResult ar : [
            SELECT LMS_Sync_Status__c status, COUNT(Id) cnt
            FROM CourseOfferingParticipant
            GROUP BY LMS_Sync_Status__c
        ]) {
            String status = (String) ar.get('status');
            Integer cnt   = (Integer) ar.get('cnt');
            stats.totalParticipants += cnt;
            if (status == 'Pending') stats.pendingParticipants  += cnt;
            else if (status == 'Success') stats.successParticipants += cnt;
            else if (status == 'Failed')  stats.failedParticipants  += cnt;
            else stats.pendingParticipants += cnt; // null = treat as pending
        }

        stats.totalOfferings = [SELECT COUNT() FROM CourseOffering];

        Set<Id> needsSyncCoIds  = new Set<Id>();
        Set<Id> failedCoIds     = new Set<Id>();
        Set<Id> successCoIds    = new Set<Id>();
        for (AggregateResult ar : [
            SELECT CourseOfferingId cid, LMS_Sync_Status__c status
            FROM CourseOfferingParticipant
            GROUP BY CourseOfferingId, LMS_Sync_Status__c
        ]) {
            Id cid    = (Id) ar.get('cid');
            String st = (String) ar.get('status');
            if (st == 'Pending' || st == 'Failed' || st == null) needsSyncCoIds.add(cid);
            if (st == 'Failed')  failedCoIds.add(cid);
            if (st == 'Success') successCoIds.add(cid);
        }
        stats.offeringsNeedingSync  = needsSyncCoIds.size();
        stats.offeringsWithFailed   = failedCoIds.size();
        stats.offeringsFullySuccess = successCoIds.size();

        return stats;
    }

    // ─── Main Offering List (supports syncFilter) ────────────────────────────
    // syncFilter values: null/'ALL' | 'NEEDS_SYNC' | 'SUCCESS' | 'FAILED'

    @AuraEnabled(cacheable=true)
    public static OfferingResponse getOfferings(
        String academicYear,
        String programName,
        String termName,
        String sessionName,
        String searchTerm,
        Integer pSize,
        Integer pOffset,
        String syncFilter
    ) {
        if (pSize   == null) pSize   = 50;
        if (pOffset == null) pOffset = 0;

        List<String> conditions = new List<String>();
        if (String.isNotBlank(academicYear)) conditions.add('Academic_Year__r.Name = :academicYear');
        if (String.isNotBlank(programName))  conditions.add('Program__r.Name = :programName');
        if (String.isNotBlank(termName))     conditions.add('Academic_Term__r.Name = :termName');
        if (String.isNotBlank(sessionName))  conditions.add('AcademicSession.Name = :sessionName');
        if (String.isNotBlank(searchTerm)) {
            conditions.add('Name LIKE \'%' + String.escapeSingleQuotes(searchTerm) + '%\'');
        }

        // Sync status filter — semi-join subqueries on CourseOfferingParticipant
        if (syncFilter == 'NEEDS_SYNC') {
            conditions.add('Id IN (SELECT CourseOfferingId FROM CourseOfferingParticipant WHERE LMS_Sync_Status__c IN (\'Pending\', \'Failed\') OR LMS_Sync_Status__c = null)');
        } else if (syncFilter == 'SUCCESS') {
            conditions.add('Id IN (SELECT CourseOfferingId FROM CourseOfferingParticipant WHERE LMS_Sync_Status__c = \'Success\')');
        } else if (syncFilter == 'FAILED') {
            conditions.add('Id IN (SELECT CourseOfferingId FROM CourseOfferingParticipant WHERE LMS_Sync_Status__c = \'Failed\')');
        }

        String whereClause = conditions.isEmpty() ? '' : ' WHERE ' + String.join(conditions, ' AND ');
        Integer total = Database.countQuery('SELECT COUNT() FROM CourseOffering' + whereClause);

        String mainQ = 'SELECT Id, Name, Academic_Year__r.Name, Program__r.Name, Academic_Term__r.Name, AcademicSession.Name, LMS_Course_Id__c'
            + ' FROM CourseOffering' + whereClause
            + ' ORDER BY Name ASC LIMIT :pSize OFFSET :pOffset';
        List<CourseOffering> offerings = Database.query(mainQ);
        Set<Id> offeringIds = new Map<Id, CourseOffering>(offerings).keySet();

        // Aggregate sync status counts per offering
        Map<Id, OfferingRow> countMap = new Map<Id, OfferingRow>();
        for (Id oId : offeringIds) {
            OfferingRow r = new OfferingRow();
            r.totalParticipants = 0; r.pendingCount = 0; r.failedCount = 0; r.successCount = 0;
            countMap.put(oId, r);
        }
        if (!offeringIds.isEmpty()) {
            for (AggregateResult ar : [
                SELECT CourseOfferingId cid, LMS_Sync_Status__c status, COUNT(Id) cnt
                FROM CourseOfferingParticipant
                WHERE CourseOfferingId IN :offeringIds
                GROUP BY CourseOfferingId, LMS_Sync_Status__c
            ]) {
                Id oId      = (Id)      ar.get('cid');
                String stat = (String)  ar.get('status');
                Integer cnt = (Integer) ar.get('cnt');
                OfferingRow r = countMap.get(oId);
                r.totalParticipants += cnt;
                if (stat == 'Pending') r.pendingCount += cnt;
                else if (stat == 'Failed')  r.failedCount  += cnt;
                else if (stat == 'Success') r.successCount += cnt;
                else r.pendingCount += cnt; // null → treat as Pending
            }
        }

        List<OfferingRow> rows = new List<OfferingRow>();
        for (CourseOffering o : offerings) {
            OfferingRow r = countMap.get(o.Id);
            r.id          = o.Id;
            r.name        = o.Name;
            r.academicYear = o.Academic_Year__r != null ? o.Academic_Year__r.Name : '';
            r.programName  = o.Program__r        != null ? o.Program__r.Name        : '';
            r.termName     = o.Academic_Term__r  != null ? o.Academic_Term__r.Name  : '';
            r.sessionName  = o.AcademicSession   != null ? o.AcademicSession.Name   : '';
            rows.add(r);
        }

        OfferingResponse resp = new OfferingResponse();
        resp.records = rows;
        resp.total   = total;
        return resp;
    }

    // ─── Participants filtered by sync status for modal view ─────────────────
    // statusFilter: null = Pending+Failed | 'Success' | 'Failed' | 'Pending'

    @AuraEnabled(cacheable=true)
    public static List<ParticipantRow> getParticipantsByStatusFilter(Id offeringId, String statusFilter) {
        if (offeringId == null) return new List<ParticipantRow>();

        String query = 'SELECT Id, ParticipantContactId, ParticipantContact.Name, Section_Name__c, '
            + 'LMS_Group_Id__c, LMS_Sync_Status__c, CourseOffering.Section_Mappings__c, CourseOffering.LMS_Course_Id__c '
            + 'FROM CourseOfferingParticipant '
            + 'WHERE CourseOfferingId = :offeringId';

        if (statusFilter == 'Success') {
            query += ' AND LMS_Sync_Status__c = \'Success\'';
        } else if (statusFilter == 'Failed') {
            query += ' AND LMS_Sync_Status__c = \'Failed\'';
        } else if (statusFilter == 'Pending') {
            query += ' AND (LMS_Sync_Status__c = \'Pending\' OR LMS_Sync_Status__c = null)';
        } else {
            // Default: show Pending + Failed (needs sync)
            query += ' AND (LMS_Sync_Status__c IN (\'Pending\', \'Failed\') OR LMS_Sync_Status__c = null)';
        }
        query += ' ORDER BY ParticipantContact.Name ASC LIMIT 5000';

        List<ParticipantRow> rows = new List<ParticipantRow>();
        for (CourseOfferingParticipant p : Database.query(query)) {
            ParticipantRow r = new ParticipantRow();
            r.id           = p.Id;
            r.name         = p.ParticipantContact != null ? p.ParticipantContact.Name : 'Unknown';
            r.contactId    = p.ParticipantContactId;
            r.section      = p.Section_Name__c;
            r.lmsSyncStatus = p.LMS_Sync_Status__c;
            r.lmsCourseId  = p.CourseOffering != null ? p.CourseOffering.LMS_Course_Id__c : '';

            // Resolve group ID visually if not stamped yet
            String resolvedGroup = p.LMS_Group_Id__c;
            if (String.isBlank(resolvedGroup) && p.CourseOffering != null && String.isNotBlank(p.CourseOffering.Section_Mappings__c)) {
                String sectionToMatch = p.Section_Name__c;
                List<String> mappings = p.CourseOffering.Section_Mappings__c.split(',');
                if (String.isBlank(sectionToMatch) && mappings.size() == 1) {
                    sectionToMatch = mappings[0].split(':')[0].trim();
                }
                if (String.isNotBlank(sectionToMatch)) {
                    for (String pair : mappings) {
                        List<String> parts = pair.split(':');
                        if (parts.size() == 2 && parts[0].trim() == sectionToMatch.trim()) {
                            resolvedGroup = parts[1].trim(); break;
                        }
                    }
                }
            }
            r.lmsGroupId = resolvedGroup;
            rows.add(r);
        }
        return rows;
    }

    // ─── Legacy method kept for backward compatibility ────────────────────────
    @AuraEnabled(cacheable=true)
    public static List<ParticipantRow> getParticipants(Id offeringId) {
        return getParticipantsByStatusFilter(offeringId, null);
    }

    // ─── Sync Actions ────────────────────────────────────────────────────────

    @AuraEnabled
    public static String enqueueSyncForCOP(List<Id> copIds) {
        if (copIds == null || copIds.isEmpty()) return 'No participants selected.';
        try {
            CourseOfferingParticipantLMSService.enqueueSyncFromLWC(copIds);
            return 'Sync queued for ' + copIds.size() + ' participant(s). Phase 1 (Course Enrolment) will run first, followed by Phase 2 (Section Assignment).';
        } catch (Exception e) { throw new AuraHandledException(e.getMessage()); }
    }

    @AuraEnabled
    public static String enqueueSyncForCO(List<Id> courseOfferingIds) {
        if (courseOfferingIds == null || courseOfferingIds.isEmpty()) return 'No courses selected.';
        try {
            List<CourseOfferingParticipant> eligible = [
                SELECT Id FROM CourseOfferingParticipant
                WHERE CourseOfferingId IN :courseOfferingIds
                AND (LMS_Sync_Status__c = 'Pending' OR LMS_Sync_Status__c = 'Failed' OR LMS_Sync_Status__c = null)
                LIMIT 5000
            ];
            if (eligible.isEmpty()) return 'All participants in the selected course(s) are already synced.';

            List<Id> pIds = new List<Id>();
            for (CourseOfferingParticipant p : eligible) pIds.add(p.Id);

            CourseOfferingParticipantLMSService.enqueueSyncFromLWC(pIds);
            return 'Two-phase LMS Sync queued for ' + pIds.size() + ' participant(s) across ' + courseOfferingIds.size() + ' course(s).';
        } catch (Exception e) { throw new AuraHandledException(e.getMessage()); }
    }

    // ─── Polling ─────────────────────────────────────────────────────────────

    @AuraEnabled
    public static Map<Id, String> getSyncStatusForCOPs(List<Id> copIds) {
        Map<Id, String> statusMap = new Map<Id, String>();
        for (CourseOfferingParticipant p : [SELECT Id, LMS_Sync_Status__c FROM CourseOfferingParticipant WHERE Id IN :copIds]) {
            statusMap.put(p.Id, p.LMS_Sync_Status__c);
        }
        return statusMap;
    }
}