public with sharing class FacultySearchController {
    @AuraEnabled(cacheable=true)
    public static List<Contact> getFacultyList(String searchKey) {
        try {
            return [
                SELECT Id, Name, Email
                FROM Contact
                WHERE RecordType.DeveloperName = 'Faculty'
                AND Name LIKE :('%' + searchKey + '%')
                ORDER BY Name ASC
                LIMIT 50
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error searching faculty: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static AA_Profile__c getAA(Id recordId) {
        try {
            return [
                SELECT Id, Preferred_By_Faculty__c
                FROM AA_Profile__c
                WHERE Id = :recordId
                LIMIT 1
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error loading AA Profile: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void updateAA(Id recordId, String preferredListString) {
        try {
            AA_Profile__c aa = new AA_Profile__c(
                Id = recordId,
                Preferred_By_Faculty__c = preferredListString
            );
            update aa;
        } catch (Exception e) {
            throw new AuraHandledException('Error updating preferred faculty: ' + e.getMessage());
        }
    }
}