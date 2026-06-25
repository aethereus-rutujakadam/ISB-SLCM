public with sharing class TranscriptExportController {

    @AuraEnabled(cacheable=true)
    public static List<Transcript__c> getTranscripts(String viewType) {
        return [
            SELECT 
                Student__r.Name,
                Program__r.Name,
                Academic_Term__r.Name,
                Academic_Session__r.Name,
				Course__r.Name,
                Credits__c,
                Grade__c,
                Grade_Points__c,
                Term_GPA__c,
                Credits_Earned_Till_Term__c,
                CGPA__c,
                Total_Credits__c
            FROM Transcript__c
            WHERE View_Type__c = :viewType
        ];
    }
}