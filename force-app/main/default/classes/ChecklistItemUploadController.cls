/**
 * @description Controller for Excel upload and parsing on Course_Offering__c
 */
public with sharing class ChecklistItemUploadController {

    /**
     * @description Accepts parsed Excel rows as JSON and creates checklist + items.
     * Called from LWC after client-side XLSX parsing via SheetJS.
     * Each row is a map of column header -> cell value.
        * Expected headers: Subject, Description, Priority, Role, CourseType,
        * Start Date, End Date, Logic Calculation
     */
    @AuraEnabled
    public static ChecklistItemExcelParser.ParseResult uploadChecklistRows(String rowsJson) {
        try {
            return ChecklistItemExcelParser.parseFromJson(rowsJson);
        } catch (Exception e) {
            throw new AuraHandledException('Error creating checklist items: ' + e.getMessage());
        }
    }


    /**
     * @description Gets the CourseType from a CourseOffering record
     * @param courseOfferingId The Course_Offering__c ID
     * @return The Course_Type__c value
     */
    @AuraEnabled
    public static String getCourseType(Id courseOfferingId) {
        try {
            CourseOffering offering = [
                SELECT Id, Course_Type__c
                FROM CourseOffering
                WHERE Id = :courseOfferingId
                LIMIT 1
            ];
            return offering.Course_Type__c;
        } catch (Exception e) {
            // If field doesn't exist or error occurs, return empty string
            return '';
        }
    }

    /**
     * @description Gets available roles from course_managers__c
     */
    @AuraEnabled
    public static List<String> getAvailableRoles() {
        try {
            List<AggregateResult> results = [
                SELECT Role__c
                FROM course_managers__c
                WHERE Role__c != null
                GROUP BY Role__c
                ORDER BY Role__c
            ];

            List<String> roles = new List<String>();
            for (AggregateResult ar : results) {
                roles.add((String) ar.get('Role__c'));
            }

            // Add common default roles if none exist
            if (roles.isEmpty()) {
                roles.add('Manager');
                roles.add('Associate');
                roles.add('Delivery Manager');
                roles.add('Administrator');
            }

            return roles;
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving roles: ' + e.getMessage());
        }
    }
}