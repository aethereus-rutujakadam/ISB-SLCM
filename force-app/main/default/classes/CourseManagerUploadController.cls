/*
 * @description Controller for Course Manager Upload LWC.
 * Provides @AuraEnabled method to accept Excel data from client and initiate batch processing.
 */
public with sharing class CourseManagerUploadController {

    /**
     * @description Receives parsed Excel data from LWC and initiates batch processing
     * @param rowsJson JSON string containing Excel rows
     * @return ParseResult with batch job ID and validation results
     */
    @AuraEnabled
    public static CourseManagerExcelParser.ParseResult uploadCourseManagers(String rowsJson) {
        try {
            return CourseManagerExcelParser.parseFromJson(rowsJson);
        } catch (Exception e) {
            throw new AuraHandledException('Error uploading course managers: ' + e.getMessage());
        }
    }
}