/**
 * @description       :
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             :
 * @last modified on  : 05-15-2026
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
public without sharing class InternshipDetailsTriggerHandler {

    public static void populateContactFromPE(List<Internship_Details__c> newList, Map<Id, Internship_Details__c> oldMap) {
        Boolean isNew = (oldMap == null);

        Set<Id> peIds = new Set<Id>();

        for (Internship_Details__c rec : newList) {
            if (rec.Program_Enrollment__c != null) {
                Boolean changed = isNew || rec.Program_Enrollment__c != oldMap.get(rec.Id).Program_Enrollment__c;
                if (changed) peIds.add(rec.Program_Enrollment__c);
            }
        }

        if (peIds.isEmpty()) return;

        Map<Id, ProgramEnrollment> peMap = new Map<Id, ProgramEnrollment>(
            [SELECT Id, ContactId FROM ProgramEnrollment WHERE Id IN :peIds]
        );

        for (Internship_Details__c rec : newList) {
            if (rec.Program_Enrollment__c != null) {
                Boolean changed = isNew || rec.Program_Enrollment__c != oldMap.get(rec.Id).Program_Enrollment__c;
                if (changed) {
                    ProgramEnrollment pe = peMap.get(rec.Program_Enrollment__c);
                    if (pe != null && pe.ContactId != null) {
                        rec.Contact__c = pe.ContactId;
                    }
                }
            }
        }
    }
}