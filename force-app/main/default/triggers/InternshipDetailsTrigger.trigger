/**
 * @description       :
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             :
 * @last modified on  : 05-15-2026
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
trigger InternshipDetailsTrigger on Internship_Details__c (before insert, before update) {
    if (Trigger.isBefore && Trigger.isInsert) {
        InternshipDetailsTriggerHandler.populateContactFromPE(Trigger.new, null);
    }
    if (Trigger.isBefore && Trigger.isUpdate) {
        InternshipDetailsTriggerHandler.populateContactFromPE(Trigger.new, Trigger.oldMap);
    }
}