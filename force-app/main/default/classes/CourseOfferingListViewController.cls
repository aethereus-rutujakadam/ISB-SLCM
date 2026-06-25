/**
 * @description Controller for CourseOffering List View LWC.
 *              Supports dynamic filtering by Academic Year, Program,
 *              Academic Term, and Academic Session.
 *              Implements pagination and returns filter picklist options.
 * @author      ISB Dev Team
 */
public with sharing class CourseOfferingListViewController {

    // ─── Inner Wrappers ──────────────────────────────────────────────────────

    /**
     * @description Wrapper returned to LWC containing paginated results + metadata.
     */
    public class CourseOfferingResult {
        @AuraEnabled public List<CourseOfferingWrapper> records   { get; set; }
        @AuraEnabled public Integer                     totalCount { get; set; }
        @AuraEnabled public Integer                     pageSize   { get; set; }
        @AuraEnabled public Integer                     pageNumber { get; set; }
        @AuraEnabled public Integer                     totalPages { get; set; }
    }

    /**
     * @description Flattened row wrapper – avoids nested relationship objects
     *              which cannot be serialised cleanly for wire/LWC.
     */
    public class CourseOfferingWrapper {
        @AuraEnabled public String id               { get; set; }
        @AuraEnabled public String name             { get; set; }
        @AuraEnabled public String academicYearName { get; set; }
        @AuraEnabled public String programName      { get; set; }
        @AuraEnabled public String academicTermName { get; set; }
        @AuraEnabled public String academicSession  { get; set; }
        @AuraEnabled public String learningCourse   { get; set; }
        @AuraEnabled public String location         { get; set; }
    }

    /**
     * @description Option for combobox picklists in the filter bar.
     */
    public class FilterOption {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String value { get; set; }
        public FilterOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    // ─── Constants ───────────────────────────────────────────────────────────

    private static final Integer DEFAULT_PAGE_SIZE = 10;
    private static final Integer MAX_PAGE_SIZE     = 200;

    // ─── Public Methods ──────────────────────────────────────────────────────

    /**
     * @description Returns 9 Academic Year records: The current year (Is_this_Current_year__c=true),
     *              plus the previous 4 and upcoming 4 years based on Name.
     */
    @AuraEnabled(cacheable=true)
    public static List<FilterOption> getAcademicYearOptions() {
        List<FilterOption> options = new List<FilterOption>();
        options.add(new FilterOption('-- All Academic Years --', ''));

        for (AcademicYear ay : [
            SELECT Name 
            FROM   AcademicYear 
            ORDER BY Name ASC 
            LIMIT 500
        ]) {
            options.add(new FilterOption(ay.Name, ay.Name));
        }
        return options;
    }

    /**
     * @description Returns ALL Program records from Program,
     *              independent of any CourseOffering data.
     */
    @AuraEnabled(cacheable=true)
    public static List<FilterOption> getProgramOptions() {
        List<FilterOption> options = new List<FilterOption>();
        options.add(new FilterOption('-- All Programs --', ''));
        for (Program prog : [
            SELECT Id, Name
            FROM   Program
            ORDER BY Name ASC
            LIMIT  500
        ]) {
            options.add(new FilterOption(prog.Name, prog.Name));
        }
        return options;
    }

    /**
     * @description Returns Academic Term records that belong to a specific Program AND Academic Year.
     */
    @AuraEnabled(cacheable=true)
    public static List<FilterOption> getAcademicTermOptions(String programName, String academicYearName) {
        List<FilterOption> options = new List<FilterOption>();
        options.add(new FilterOption('-- All Terms --', ''));
        
        List<String> termPredicates = new List<String>();
        if (String.isNotBlank(programName)) {
            // Assuming AcademicTerm has a lookup to Program (custom relationship Program__r)
            termPredicates.add('Program__r.Name = :programName');
        }
        if (String.isNotBlank(academicYearName)) {
            // Standard AcademicTerm has AcademicYearId lookup (AcademicYear relationship)
            termPredicates.add('AcademicYear.Name = :academicYearName');
        }

        String query = 'SELECT Id, Name FROM AcademicTerm';
        if (!termPredicates.isEmpty()) {
            query += ' WHERE ' + String.join(termPredicates, ' AND ');
        }
        query += ' ORDER BY Name ASC LIMIT 500';

        for (AcademicTerm term : Database.query(query)) {
            options.add(new FilterOption(term.Name, term.Name));
        }
        return options;
    }

    /**
     * @description Returns Academic Session records that belong to a specific Program AND Term.
     */
    @AuraEnabled(cacheable=true)
    public static List<FilterOption> getAcademicSessionOptions(String programName, String termName) {
        List<FilterOption> options = new List<FilterOption>();
        options.add(new FilterOption('-- All Sessions --', ''));
        
        List<String> sessPredicates = new List<String>();
        if (String.isNotBlank(programName)) {
            // Assuming AcademicSession has a lookup to Program (custom)
            sessPredicates.add('Program__r.Name = :programName');
        }
        if (String.isNotBlank(termName)) {
            // Standard AcademicSession lookup to AcademicTerm is AcademicTerm
            sessPredicates.add('AcademicTerm.Name = :termName');
        }

        String query = 'SELECT Id, Name FROM AcademicSession';
        if (!sessPredicates.isEmpty()) {
            query += ' WHERE ' + String.join(sessPredicates, ' AND ');
        }
        query += ' ORDER BY Name ASC LIMIT 500';

        for (AcademicSession sess : Database.query(query)) {
            options.add(new FilterOption(sess.Name, sess.Name));
        }
        return options;
    }

    /**
     * @description Main data-fetch method.  Returns a paginated, filtered set of
     *              CourseOffering records wrapped in CourseOfferingResult.
     * @param academicYear    Filter value for Academic_Year__r.Name  (empty = all)
     * @param program         Filter value for Program__r.Name         (empty = all)
     * @param academicTerm    Filter value for Academic_Term__r.Name   (empty = all)
     * @param academicSession Filter value for AcademicSession.Name    (empty = all)
     * @param sortField       API name of the field to sort by         (empty = Name)
     * @param sortDirection   'asc' or 'desc'
     * @param pageNumber      1-based page number
     * @param pageSize        Rows per page (capped at MAX_PAGE_SIZE)
     */
    @AuraEnabled
    public static CourseOfferingResult getCourseOfferings(
        String  academicYear,
        String  program,
        String  academicTerm,
        String  academicSession,
        String  sortField,
        String  sortDirection,
        Integer pageNumber,
        Integer pageSize
    ) {
        try {
            // ── Defaults & guards ─────────────────────────────────────────
            if (pageNumber == null || pageNumber < 1)  { pageNumber = 1; }
            if (pageSize   == null || pageSize   < 1)  { pageSize   = DEFAULT_PAGE_SIZE; }
            if (pageSize > MAX_PAGE_SIZE)               { pageSize   = MAX_PAGE_SIZE; }

            String safeSort = resolveSortField(sortField);
            String safeDir  = ('desc'.equalsIgnoreCase(sortDirection)) ? 'DESC' : 'ASC';

            // ── Build WHERE clause ────────────────────────────────────────
            List<String> predicates = new List<String>();
            if (String.isNotBlank(academicYear)) {
                predicates.add('Academic_Year__r.Name = :academicYear');
            }
            if (String.isNotBlank(program)) {
                predicates.add('Program__r.Name = :program');
            }
            if (String.isNotBlank(academicTerm)) {
                predicates.add('Academic_Term__r.Name = :academicTerm');
            }
            if (String.isNotBlank(academicSession)) {
                predicates.add('AcademicSession.Name = :academicSession');
            }

            String whereClause = predicates.isEmpty() ? '' : ' WHERE ' + String.join(predicates, ' AND ');

            // ── Count query ───────────────────────────────────────────────
            String countQuery = 'SELECT COUNT() FROM CourseOffering' + whereClause;
            Integer totalCount = Database.countQuery(countQuery); //NOPMD

            // ── Data query ────────────────────────────────────────────────
            Integer offset = (pageNumber - 1) * pageSize;
            String dataQuery =
                'SELECT Id, Name, Academic_Year__r.Name, Program__r.Name, ' +
                '       Academic_Term__r.Name, AcademicSession.Name, ' +
                '       LearningCourse.Name, Location__r.Name ' +
                'FROM   CourseOffering' +
                whereClause +
                ' ORDER BY ' + safeSort + ' ' + safeDir +
                ' LIMIT ' + pageSize +
                ' OFFSET ' + offset;

            List<CourseOffering> rawRecords = Database.query(dataQuery); //NOPMD

            // ── Map to wrappers ───────────────────────────────────────────
            List<CourseOfferingWrapper> wrappedList = new List<CourseOfferingWrapper>();
            for (CourseOffering co : rawRecords) {
                CourseOfferingWrapper w = new CourseOfferingWrapper();
                w.id               = co.Id;
                w.name             = co.Name;
                w.academicYearName = co.Academic_Year__r != null ? co.Academic_Year__r.Name : '';
                w.programName      = co.Program__r       != null ? co.Program__r.Name       : '';
                w.academicTermName = co.Academic_Term__r != null ? co.Academic_Term__r.Name : '';
                w.academicSession  = co.AcademicSession  != null ? co.AcademicSession.Name  : '';
                w.learningCourse   = co.LearningCourse   != null ? co.LearningCourse.Name   : '';
                w.location         = co.Location__r      != null ? co.Location__r.Name      : '';
                wrappedList.add(w);
            }

            // ── Package result ────────────────────────────────────────────
            CourseOfferingResult result = new CourseOfferingResult();
            result.records    = wrappedList;
            result.totalCount = totalCount;
            result.pageSize   = pageSize;
            result.pageNumber = pageNumber;
            result.totalPages = (Integer) Math.ceil((Double) totalCount / pageSize);
            return result;

        } catch (Exception ex) {
            throw new AuraHandledException('Error fetching Course Offerings: ' + ex.getMessage());
        }
    }

    // ─── Private Helpers ─────────────────────────────────────────────────────

    /**
     * @description Whitelist allowed sort fields to prevent SOQL injection.
     */
    private static String resolveSortField(String fieldName) {
        Map<String, String> allowedFields = new Map<String, String>{
            'name'             => 'Name',
            'academicyearname' => 'Academic_Year__r.Name',
            'programname'      => 'Program__r.Name',
            'academictermname' => 'Academic_Term__r.Name',
            'academicsession'  => 'AcademicSession.Name',
            'learningcourse'   => 'LearningCourse.Name',
            'location'         => 'Location__r.Name'
        };
        if (String.isNotBlank(fieldName)) {
            String key = fieldName.toLowerCase();
            if (allowedFields.containsKey(key)) {
                return allowedFields.get(key);
            }
        }
        return 'Name'; // safe default
    }
}