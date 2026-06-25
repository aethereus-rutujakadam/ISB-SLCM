/**
 * @description Wrapper class for Course Manager Excel upload processing.
 * Receives JSON from LWC, validates data, and initiates batch processing.
 * Batch processing is required due to downstream trigger operations (checklist creation).
 */
public without sharing class CourseManagerExcelParser {

    /**
     * @description Main entry point from LWC. Validates JSON and starts batch job.
        * @param rowsJson JSON string containing Excel rows with Owner, Courses, CourseCode, CourseType, Location, AcademicYear, AcademicTerm, Roles
     * @return ParseResult containing batch job ID and validation results
     */
    public static ParseResult parseFromJson(String rowsJson) {
        ParseResult result = new ParseResult();
        
        try {
            // Validate input
            if (String.isBlank(rowsJson)) {
                result.addError('No data received');
                return result;
            }

            // Deserialize JSON to untyped objects
            List<Object> rawRows = (List<Object>) JSON.deserializeUntyped(rowsJson);
            
            if (rawRows == null || rawRows.isEmpty()) {
                result.addError('Excel file has no data rows');
                return result;
            }

            // Validate required columns exist in Excel header
            Map<String, Object> firstRawRow = (Map<String, Object>) rawRows[0];
            Set<String> fileColumns = new Set<String>();
            for (String key : firstRawRow.keySet()) {
                fileColumns.add(key.trim().toLowerCase());
            }
            
            List<String> requiredColumns = new List<String>{
                'owner', 'courses', 'coursecode', 'coursetype', 'location', 
                'academicyear', 'academicterm', 'academicsession', 'roles'
            };
            
            for (String reqCol : requiredColumns) {
                if (!fileColumns.contains(reqCol)) {
                    String displayName = reqCol.substring(0, 1).toUpperCase() + reqCol.substring(1);
                    if (reqCol == 'coursecode') displayName = 'CourseCode';
                    if (reqCol == 'coursetype') displayName = 'CourseType';
                    if (reqCol == 'academicyear') displayName = 'AcademicYear';
                    if (reqCol == 'academicterm') displayName = 'AcademicTerm';
                    if (reqCol == 'academicsession') displayName = 'AcademicSession';
                    result.addError(displayName + ' column is required in the excel');
                    return result;
                }
            }

            // Convert to ExcelRow objects with validation
            List<ExcelRow> excelRows = new List<ExcelRow>();
            Set<String> uniqueRowKeys = new Set<String>(); // For within-file duplicate detection
            
            for (Integer i = 0; i < rawRows.size(); i++) {
                Map<String, Object> rawRow = (Map<String, Object>) rawRows[i];
                
                // Build case-insensitive normalized map (trim + lowercase keys)
                Map<String, Object> row = new Map<String, Object>();
                for (String key : rawRow.keySet()) {
                    row.put(key.trim().toLowerCase(), rawRow.get(key));
                }

                // Extract fields (case-insensitive)
                String owner = cleanString(row.get('owner'));
                String courses = cleanString(row.get('courses'));
                String courseCode = cleanString(row.get('coursecode'));
                String courseType = cleanString(row.get('coursetype'));
                String location = cleanString(row.get('location'));
                String academicYear = cleanString(row.get('academicyear'));
                String academicTerm = cleanString(row.get('academicterm'));
                String academicSession = cleanString(row.get('academicsession'));
                String roles = cleanString(row.get('roles'));

                // Validate required fields
                if (String.isBlank(owner)) {
                    result.addWarning('Row ' + (i + 1) + ': Owner is required, skipping');
                    continue;
                }
                if (String.isBlank(courses)) {
                    result.addWarning('Row ' + (i + 1) + ': Courses is required, skipping');
                    continue;
                }
                if (String.isBlank(courseCode)) {
                    result.addWarning('Row ' + (i + 1) + ': CourseCode is required, skipping');
                    continue;
                }
                if (String.isBlank(courseType)) {
                    result.addWarning('Row ' + (i + 1) + ': CourseType is required, skipping');
                    continue;
                }
                if (String.isBlank(location)) {
                    result.addWarning('Row ' + (i + 1) + ': Location is required, skipping');
                    continue;
                }
                if (String.isBlank(academicYear)) {
                    result.addWarning('Row ' + (i + 1) + ': AcademicYear is required, skipping');
                    continue;
                }
                if (String.isBlank(academicTerm)) {
                    result.addWarning('Row ' + (i + 1) + ': AcademicTerm is required, skipping');
                    continue;
                }
                if (String.isBlank(academicSession)) {
                    result.addWarning('Row ' + (i + 1) + ': AcademicSession is required, skipping');
                    continue;
                }
                if (String.isBlank(roles)) {
                    result.addWarning('Row ' + (i + 1) + ': Roles is required, skipping');
                    continue;
                }

                // Create unique key for duplicate detection
                String rowKey = (owner + '|' + courses + '|' + courseCode + '|' + courseType + '|' + location + '|' + academicYear + '|' + academicTerm + '|' + academicSession + '|' + roles).toLowerCase();
                
                if (uniqueRowKeys.contains(rowKey)) {
                    result.addWarning('Row ' + (i + 1) + ': Duplicate row detected, skipping');
                    continue;
                }
                uniqueRowKeys.add(rowKey);

                // Create ExcelRow object
                ExcelRow excelRow = new ExcelRow();
                excelRow.rowNumber = i + 1;
                excelRow.owner = owner;
                excelRow.courses = courses;
                excelRow.courseCode = courseCode;
                excelRow.courseType = courseType;
                excelRow.location = location;
                excelRow.academicYear = academicYear;
                excelRow.academicTerm = academicTerm;
                excelRow.academicSession = academicSession;
                excelRow.roles = roles;
                
                excelRows.add(excelRow);
            }

            if (excelRows.isEmpty()) {
                result.addError('No valid rows to process after validation');
                return result;
            }

            // Start batch job
            CourseManagerBatchProcessor batch = new CourseManagerBatchProcessor(excelRows);
            Id batchJobId = Database.executeBatch(batch, 100);
            
            result.batchJobId = batchJobId;
            result.totalRowsSubmitted = excelRows.size();
            result.isSuccess = true;

        } catch (Exception e) {
            result.addError('Error processing upload: ' + e.getMessage() + ' [' + e.getStackTraceString() + ']');
        }
        
        return result;
    }

    /**
     * @description Cleans and trims string values from Excel
     */
    private static String cleanString(Object val) {
        if (val == null) return '';
        return String.valueOf(val).trim();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Inner Classes
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Wrapper for a single Excel row
     */
    public class ExcelRow {
        public Integer rowNumber;
        public String owner;
        public String courses;
        public String courseCode;
        public String courseType;
        public String location;
        public String academicYear;
        public String academicTerm;
        public String academicSession;
        public String roles;
    }

    /**
     * @description Result class returned to LWC
     */
    public class ParseResult {
        @AuraEnabled public Boolean isSuccess = false;
        @AuraEnabled public Integer totalRowsSubmitted = 0;
        @AuraEnabled public Id batchJobId = null;
        @AuraEnabled public List<String> warnings = new List<String>();
        @AuraEnabled public List<String> errors = new List<String>();

        public void addWarning(String msg) {
            warnings.add(msg);
        }

        public void addError(String msg) {
            errors.add(msg);
        }
    }
}