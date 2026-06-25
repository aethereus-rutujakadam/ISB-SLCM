public with sharing class OutgoingExchangePortalController {

    @AuraEnabled(cacheable=true)
    public static List<Exchange_Course__c> getExchangeCourses(Id programEnrollmentId) {
        return [
            SELECT Id, Name, Course_Code__c, Course_Name__c, Partner_Credits__c,
                   Contact_Hours__c, ISB_Credits__c, Partner_Grade__c, Letter_Grade__c, Status__c
            FROM Exchange_Course__c
            WHERE ProgramEnrollment__c = :programEnrollmentId
            ORDER BY Course_Name__c ASC
        ];
    }

    @AuraEnabled(cacheable=true)
    public static Case getOutgoingCaseForContact(Id contactId) {
        Id outgoingRTId = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName()
            .containsKey('Outgoing_Exchange')
            ? Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName().get('Outgoing_Exchange').getRecordTypeId()
            : null;
        if (outgoingRTId == null) return null;
        List<Case> cases = [
            SELECT Id, Status, Exchange_School_Partner__c, Exchange_School_Partner__r.Name,
                   Exchange_Coordinator_Name__c, Exchange_Coordinator_Email__c,
                   From_Term__c, To_Term__c, Transcript_Dispatched__c, Dispatch_Date__c
            FROM Case
            WHERE ContactId = :contactId
              AND RecordTypeId = :outgoingRTId
              AND Status != 'Closed'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return cases.isEmpty() ? null : cases[0];
    }
}