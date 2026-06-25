public without sharing class CourseOfferingLMSController {

    // ─── Inner classes for Dashboard ─────────────────────────────────────────

    public class FilterOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        public FilterOption(String l, String v) { label = l; value = v; }
    }

    public class DashboardStats {
        @AuraEnabled public Integer totalCourses;
        @AuraEnabled public Integer pendingCourses;
        @AuraEnabled public Integer successCourses;
        @AuraEnabled public Integer failedCourses;
    }

    public class OfferingResponse {
        @AuraEnabled public List<CourseOffering> records;
        @AuraEnabled public Integer total;
    }

    // ─── Filter Options (Cascading) ──────────────────────────────────────────

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
        stats.totalCourses   = [SELECT COUNT() FROM CourseOffering];
        
        // Count by LMS Sync Status
        AggregateResult[] groupedResults = [
            SELECT LMS_Sync_Status__c status, COUNT(Id) cnt 
            FROM CourseOffering 
            GROUP BY LMS_Sync_Status__c
        ];
        
        stats.pendingCourses = 0;
        stats.successCourses = 0;
        stats.failedCourses  = 0;
        
        for (AggregateResult ar : groupedResults) {
            String status = (String) ar.get('status');
            Integer count = (Integer) ar.get('cnt');
            if (status == 'Success') stats.successCourses += count;
            else if (status == 'Failed') stats.failedCourses += count;
            else stats.pendingCourses += count; // null or anything else is pending
        }
        return stats;
    }

    // ─── Main Course List ────────────────────────────────────────────────────

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
        if (pSize == null) pSize = 50;
        if (pOffset == null) pOffset = 0;

        List<String> conditions = new List<String>();
        
        // Filters
        if (String.isNotBlank(academicYear)) conditions.add('Academic_Year__r.Name = :academicYear');
        if (String.isNotBlank(programName))  conditions.add('Program__r.Name = :programName');
        if (String.isNotBlank(termName))     conditions.add('Academic_Term__r.Name = :termName');
        if (String.isNotBlank(sessionName))  conditions.add('AcademicSession.Name = :sessionName');
        if (String.isNotBlank(searchTerm)) {
            conditions.add('Name LIKE \'%' + String.escapeSingleQuotes(searchTerm) + '%\'');
        }

        // Sync Status Filter
        if (syncFilter == 'NEEDS_SYNC') {
            // Show all records that need sync: new records (no LMS ID) OR explicitly marked as Pending/Failed
            conditions.add('(LMS_Sync_Status__c IN (\'Pending\', \'Failed\') OR LMS_Sync_Status__c = NULL OR LMS_Course_Id__c = NULL)');
        } else if (syncFilter == 'SUCCESS') {
            conditions.add('LMS_Sync_Status__c = \'Success\'');
            conditions.add('LMS_Course_Id__c != NULL');
        } else if (syncFilter == 'FAILED') {
            conditions.add('LMS_Sync_Status__c = \'Failed\'');
        }

        String whereClause = conditions.isEmpty() ? '' : ' WHERE ' + String.join(conditions, ' AND ');
        
        Integer total = Database.countQuery('SELECT COUNT() FROM CourseOffering' + whereClause);

        String query = 'SELECT Id, Name, ISB_External_Id__c, Academic_Term__r.Name, ' +
                       'No_of_Sections__c, LMS_Course_Id__c, Academic_Year__r.Name, ' +
                       'LearningCourse.Name, Section_Name__c, Program__r.Name, ' +
                       'AcademicSession.Name, LMS_Sync_Status__c, LMS_Error__c, Section_Mappings__c ' +
                       'FROM CourseOffering' + whereClause + 
                       ' ORDER BY Name ASC LIMIT :pSize OFFSET :pOffset';
                       
        OfferingResponse resp = new OfferingResponse();
        resp.records = Database.query(query);
        resp.total   = total;
        return resp;
    }
    
    // Note: I'll complete the actual data return in the next step to keep chunks clean.
    // Wait, I should just write the whole thing.

    @AuraEnabled
    public static String pushToLMS(List<Id> courseOfferingIds) {
        try {
            if (courseOfferingIds == null || courseOfferingIds.isEmpty()) {
                throw new AuraHandledException('No records selected.');
            }
            
            // Start the asynchronous job
            System.enqueueJob(new CourseOfferingLMSQueueable(courseOfferingIds));

            return 'Sync process started for ' + courseOfferingIds.size() + ' records. Please refresh the dashboard in a few moments to see updated status.';
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    public class SyncResultWrapper {
        @AuraEnabled public List<CourseOffering> successRecords = new List<CourseOffering>();
        @AuraEnabled public List<CourseOffering> failedRecords = new List<CourseOffering>();
    }
}