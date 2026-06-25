public with sharing class AcademicAlertController {
    
    @AuraEnabled(cacheable=true)
    public static List<Case> getAcademicAlertCases() {
        try {
            // Get Record Type IDs for Academic Probation and Attendance Exception
            Map<String, Schema.RecordTypeInfo> rtInfos = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName();
            Set<Id> targetRTIds = new Set<Id>();
            
            if(rtInfos.containsKey('Academic_Probation')) {
                targetRTIds.add(rtInfos.get('Academic_Probation').getRecordTypeId());
            }
            if(rtInfos.containsKey('Attendance_Exception')) {
                targetRTIds.add(rtInfos.get('Attendance_Exception').getRecordTypeId());
            }
            
            system.debug('Target Record Type IDs: ' + targetRTIds);
            
            if(targetRTIds.isEmpty()) {
                return new List<Case>();
            }

            // Query cases for current user with specified record types and Program Enrollment checked
            return [
                SELECT Id, CaseNumber, Subject, Status, CreatedDate, Description, RecordType.DeveloperName, RecordType.Name
                FROM Case 
                WHERE RecordTypeId IN :targetRTIds 
                AND ProgramEnrollment__c = true
                AND IsClosed = false
                AND Status != 'Closed'
                AND ContactId = :getCurrentContactId()
                ORDER BY CreatedDate DESC
                LIMIT 5
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching academic alert cases: ' + e.getMessage());
        }
    }
    
    // Helper method to get current portal user's contact ID
    private static Id getCurrentContactId() {
        User currentUser = [SELECT ContactId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        return currentUser.ContactId;
    }
}