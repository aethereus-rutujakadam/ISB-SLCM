/**
 * @description Parses Excel files and creates Course_Checklist_Item__c records
 * from the uploaded Excel. Handles Excel parsing and bulk item creation.
 */
public without sharing class ChecklistItemExcelParser {

    private static final String RECORD_TYPE_NAME = 'Course Manager Checklist';
    private static final String ITEM_TYPE = 'End of Term Action';
    private static final Date EXCEL_EPOCH = Date.newInstance(1899, 12, 30);

    /**
     * @description Called from LWC after SheetJS client-side parsing.
     * Rows are created as Course_Checklist_Item_Template__c records.
     */
    public static ParseResult parseFromJson(String rowsJson) {
        ParseResult result = new ParseResult();
        try {
            if (String.isBlank(rowsJson)) {
                result.addError('No data received');
                return result;
            }

            List<Object> rawRows = (List<Object>) JSON.deserializeUntyped(rowsJson);
            if (rawRows.isEmpty()) {
                result.addError('Excel file has no data rows');
                return result;
            }

            List<Course_Checklist_Item_Template__c> templatesToInsert = new List<Course_Checklist_Item_Template__c>();

            for (Integer i = 0; i < rawRows.size(); i++) {
                Map<String, Object> rawRow = (Map<String, Object>) rawRows[i];

                Map<String, Object> row = buildNormalizedRow(rawRow);

                String subject     = cleanString(getValue(row, new List<String>{ 'subject' }));
                String description = cleanString(getValue(row, new List<String>{ 'description' }));
                String priority    = cleanString(getValue(row, new List<String>{ 'priority' }));
                String itemRole    = cleanString(getValue(row, new List<String>{ 'role', 'ownerrole', 'ownerroles' }));
                String courseType  = cleanString(getValue(row, new List<String>{ 'coursetype', 'coursetypec' }));
                String templateTypeRaw = cleanString(getValue(row, new List<String>{ 'templatetype', 'template', 'type' }));
                String templateType = normalizeTemplateType(templateTypeRaw);
                Date startDate     = parseDate(getValue(row, new List<String>{ 'startdate', 'start' }));
                Date endDate       = parseDate(getValue(row, new List<String>{ 'enddate', 'end' }));
                String reminderLogicRaw = cleanString(getValue(
                    row,
                    new List<String>{
                        'logiccalculation',
                        'logiccalculationforremindertobesent',
                        'reminderlogiccalculation',
                        'reminderlogic',
                        'logic'
                    }
                ));
                String reminderLogic = normalizeReminderLogic(reminderLogicRaw);

                if (String.isBlank(subject)) {
                    result.addWarning('Row ' + (i + 1) + ': Subject is required, skipping');
                    continue;
                }
                if (String.isBlank(itemRole)) {
                    result.addWarning('Row ' + (i + 1) + ': Role is required, skipping');
                    continue;
                }
                if (String.isBlank(priority)) priority = 'Medium';
                if (startDate == null) {
                    result.addWarning('Row ' + (i + 1) + ': Start Date is required, skipping');
                    continue;
                }
                if (endDate == null) {
                    result.addWarning('Row ' + (i + 1) + ': End Date is required, skipping');
                    continue;
                }
                if (String.isBlank(reminderLogic)) {
                    result.addWarning('Row ' + (i + 1) + ': Logic Calculation must be Term Start or Term End, skipping');
                    continue;
                }
                if (String.isBlank(templateType)) {
                    result.addWarning('Row ' + (i + 1) + ': Template Type is required (must be "End of Term Tasks", "Course Checklist", "Zoho Tasks", "Advising Discussions", or "Risk Interventions"), skipping');
                    continue;
                }

                Course_Checklist_Item_Template__c template = new Course_Checklist_Item_Template__c(
                    Subject__c                      = subject,
                    Description__c                  = description,
                    Priority__c                     = priority,
                    Owner_Roles__c                  = itemRole,
                    Course_Type__c                  = courseType,
                    Template_Type__c                = templateType,
                    Active__c                       = true,
                    Start_Date__c                   = startDate,
                    End_Date__c                     = endDate,
                    Reminder_Logic_Calculation__c   = reminderLogic,
                    Reminder_Reference_Days__c      = Math.abs(startDate.daysBetween(endDate))
                );
                templatesToInsert.add(template);
            }

            if (templatesToInsert.isEmpty()) {
                return result;
            }

            Database.SaveResult[] saveResults = Database.insert(templatesToInsert, false);
            for (Integer i = 0; i < saveResults.size(); i++) {
                if (saveResults[i].isSuccess()) {
                    result.successCount++;
                } else {
                    for (Database.Error err : saveResults[i].getErrors()) {
                        result.addWarning('Row ' + (i + 1) + ': ' + err.getMessage());
                    }
                }
            }
            result.totalItemsCreated = result.successCount;

        } catch (Exception e) {
            result.addError('Error processing rows: ' + e.getMessage());
        }
        return result;
    }

    private static Map<String, Object> buildNormalizedRow(Map<String, Object> rawRow) {
        Map<String, Object> row = new Map<String, Object>();
        for (String key : rawRow.keySet()) {
            row.put(normalizeKey(key), rawRow.get(key));
        }
        return row;
    }

    private static Object getValue(Map<String, Object> row, List<String> keyCandidates) {
        for (String keyCandidate : keyCandidates) {
            String normalized = normalizeKey(keyCandidate);
            if (row.containsKey(normalized)) {
                return row.get(normalized);
            }
        }
        return null;
    }

    private static String normalizeKey(String key) {
        if (String.isBlank(key)) return '';
        return key.replaceAll('[^A-Za-z0-9]', '').toLowerCase();
    }

    private static String cleanString(Object val) {
        if (val == null) return '';
        return String.valueOf(val).trim();
    }

    private static String normalizeReminderLogic(String input) {
        String normalized = normalizeKey(input);
        if (normalized == 'termstart') return 'Term Start';
        if (normalized == 'termend') return 'Term End';
        return null;
    }

    private static String normalizeTemplateType(String input) {
        if (String.isBlank(input)) return null;
        String normalized = normalizeKey(input);
        
        if (normalized == 'endoftermtasks') return 'End of Term Tasks';
        if (normalized == 'coursechecklist') return 'Course Checklist';
        if (normalized == 'zohotasks') return 'Zoho Tasks';
        if (normalized == 'advisingdiscussions') return 'Advising Discussions';
        if (normalized == 'riskinterventions') return 'Risk Interventions';
        
        return null;
    }

    private static Date parseDate(Object rawVal) {
        if (rawVal == null) return null;
        if (rawVal instanceof Date) return (Date) rawVal;
        if (rawVal instanceof Datetime) return ((Datetime) rawVal).date();

        if (rawVal instanceof Integer) {
            return EXCEL_EPOCH.addDays((Integer) rawVal);
        }
        if (rawVal instanceof Long) {
            return EXCEL_EPOCH.addDays(Integer.valueOf(String.valueOf((Long) rawVal)));
        }
        if (rawVal instanceof Decimal) {
            return EXCEL_EPOCH.addDays(((Decimal) rawVal).intValue());
        }
        if (rawVal instanceof Double) {
            return EXCEL_EPOCH.addDays(((Double) rawVal).intValue());
        }

        String text = cleanString(rawVal);
        if (String.isBlank(text)) return null;

        // Handle ISO datetime-like values from JS/SheetJS by reading the date part.
        Matcher isoLike = Pattern.compile('^(\\d{4})[-/](\\d{1,2})[-/](\\d{1,2}).*$').matcher(text);
        if (isoLike.matches()) {
            Integer year = Integer.valueOf(isoLike.group(1));
            Integer month = Integer.valueOf(isoLike.group(2));
            Integer day = Integer.valueOf(isoLike.group(3));
            try {
                return Date.newInstance(year, month, day);
            } catch (Exception ex) {
                return null;
            }
        }

        try {
            return Date.valueOf(text);
        } catch (Exception e1) {
            // Try DD/MM/YYYY or MM/DD/YYYY with separators (/, -, .)
            Matcher slashDate = Pattern.compile('^(\\d{1,2})[./-](\\d{1,2})[./-](\\d{2,4})$').matcher(text);
            if (slashDate.matches()) {
                Integer first = Integer.valueOf(slashDate.group(1));
                Integer second = Integer.valueOf(slashDate.group(2));
                Integer year = Integer.valueOf(slashDate.group(3));
                if (year < 100) year += 2000;

                try {
                    // Unambiguous D/M/Y
                    if (first > 12 && second <= 12) {
                        return Date.newInstance(year, second, first);
                    }
                    // Unambiguous M/D/Y
                    if (second > 12 && first <= 12) {
                        return Date.newInstance(year, first, second);
                    }
                    // Ambiguous values: default to D/M/Y for business input pattern.
                    return Date.newInstance(year, second, first);
                } catch (Exception ex2) {
                    return null;
                }
            }
        }

        return null;
    }

    /**
     * @description Gets record type ID by name
     */
    public static Id getRecordTypeId(String recordTypeName) {
        List<RecordType> rts = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Course_Checklist_Item__c'
              AND Name = :recordTypeName
            LIMIT 1
        ];
        return rts.isEmpty() ? null : rts[0].Id;
    }

    public class ChecklistCreateException extends Exception {}

    // ─────────────────────────────────────────────────────────────────────────
    // Result class
    // ─────────────────────────────────────────────────────────────────────────

    public class ParseResult {
        @AuraEnabled public Integer totalItemsCreated = 0;
        @AuraEnabled public Integer successCount = 0;
        @AuraEnabled public Id checklistId = null;
        @AuraEnabled public List<String> warnings = new List<String>();
        @AuraEnabled public List<String> errors = new List<String>();

        public void addWarning(String msg) {
            warnings.add(msg);
        }

        public void addError(String msg) {
            errors.add(msg);
        }

        public Boolean isSuccess() {
            return errors.isEmpty();
        }

        public String getSummary() {
            String summary = 'Created: ' + totalItemsCreated + ' templates. ';
            if (!warnings.isEmpty()) {
                summary += 'Warnings: ' + warnings.size() + '. ';
            }
            if (!errors.isEmpty()) {
                summary += 'Errors: ' + String.join(errors, ', ');
            }
            return summary;
        }
    }
}