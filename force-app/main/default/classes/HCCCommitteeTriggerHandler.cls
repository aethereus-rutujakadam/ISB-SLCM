/**
 * @description       :
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             :
 * @last modified on  : 05-12-2026
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
public without sharing class HCCCommitteeTriggerHandler {

    public static void populateFromPGID(List<Honour_Code_Committee__c> newList, Map<Id, Honour_Code_Committee__c> oldMap) {
        Boolean isNew = (oldMap == null);

        Set<String> pgIds = new Set<String>();

        for (Honour_Code_Committee__c rec : newList) {
            if (!String.isBlank(rec.Student_PG_ID__c)) {
                Boolean changed = isNew || rec.Student_PG_ID__c != oldMap.get(rec.Id).Student_PG_ID__c;
                if (changed) pgIds.add(rec.Student_PG_ID__c.trim());
            }
        }

        if (pgIds.isEmpty()) return;

        // Query ProgramEnrollment by PGID__c
        Map<String, ProgramEnrollment> pgIdToPE = new Map<String, ProgramEnrollment>();
        for (ProgramEnrollment pe : [
            SELECT Id, ContactId, PGID__c, IsActive
            FROM ProgramEnrollment
            WHERE PGID__c IN :pgIds
        ]) {
            if (pe.PGID__c != null) pgIdToPE.put(pe.PGID__c, pe);
        }

        // Collect contactIds to fetch email + mobile
        Set<Id> contactIds = new Set<Id>();
        for (ProgramEnrollment pe : pgIdToPE.values()) {
            if (pe.ContactId != null) contactIds.add(pe.ContactId);
        }

        Map<Id, Contact> contactMap = new Map<Id, Contact>();
        if (!contactIds.isEmpty()) {
            contactMap = new Map<Id, Contact>(
                [SELECT Id, New_Admit_Email__c, MobilePhone FROM Contact WHERE Id IN :contactIds]
            );
        }

        // Apply or error
        for (Honour_Code_Committee__c rec : newList) {
            if (!String.isBlank(rec.Student_PG_ID__c)) {
                Boolean changed = isNew || rec.Student_PG_ID__c != oldMap.get(rec.Id).Student_PG_ID__c;
                if (changed) {
                    ProgramEnrollment pe = pgIdToPE.get(rec.Student_PG_ID__c.trim());
                    if (pe == null) {
                        rec.Student_PG_ID__c.addError('Incorrect PG ID. No student found with PG ID: ' + rec.Student_PG_ID__c);
                    } else if (!pe.IsActive) {
                        rec.Student_PG_ID__c.addError('Student is not active. The Program Enrollment for PG ID ' + rec.Student_PG_ID__c + ' is not active.');
                    } else {
                        rec.Student_PE_ID__c = pe.Id;
                        if (pe.ContactId != null) {
                            rec.Student__c = pe.ContactId;
                            Contact con = contactMap.get(pe.ContactId);
                            if (con != null) {
                                rec.Student_Email__c = con.New_Admit_Email__c;
                                rec.Mobile_Number__c  = con.MobilePhone;
                            }
                        }
                    }
                }
            }
        }
    }

    public static void populateChairFromEmail(List<Honour_Code_Committee__c> newList, Map<Id, Honour_Code_Committee__c> oldMap) {
        Boolean isNew = (oldMap == null);

        Set<String> chairEmails = new Set<String>();

        for (Honour_Code_Committee__c rec : newList) {
            if (!String.isBlank(rec.HCC_Chair_Email__c)) {
                Boolean changed = isNew || rec.HCC_Chair_Email__c != oldMap.get(rec.Id).HCC_Chair_Email__c;
                if (changed) chairEmails.add(rec.HCC_Chair_Email__c.trim().toLowerCase());
            }
        }

        if (chairEmails.isEmpty()) return;

        // Search Faculty contacts by VF_Email_ID__c
        Map<String, Id> emailToContactId = new Map<String, Id>();
        for (Contact c : [
            SELECT Id, VF_Email_ID__c
            FROM Contact
            WHERE RecordType.Name = 'Faculty'
            AND VF_Email_ID__c IN :chairEmails
        ]) {
            if (!String.isBlank(c.VF_Email_ID__c)) {
                emailToContactId.put(c.VF_Email_ID__c.toLowerCase(), c.Id);
            }
        }

        for (Honour_Code_Committee__c rec : newList) {
            if (!String.isBlank(rec.HCC_Chair_Email__c)) {
                Boolean changed = isNew || rec.HCC_Chair_Email__c != oldMap.get(rec.Id).HCC_Chair_Email__c;
                if (changed) {
                    Id contactId = emailToContactId.get(rec.HCC_Chair_Email__c.trim().toLowerCase());
                    if (contactId != null) {
                        rec.Chair__c = contactId;
                    } else {
                        rec.Chair__c = null;
                    }
                }
            }
        }
    }

    public static void populateStudentDetails(List<Honour_Code_Committee__c> newList, Map<Id, Honour_Code_Committee__c> oldMap) {
        Boolean isNew = (oldMap == null);

        Set<Id> peIds          = new Set<Id>();
        Set<Id> courseOfferIds = new Set<Id>();

        for (Honour_Code_Committee__c rec : newList) {
            if (rec.Student_PE_ID__c != null) {
                Boolean changed = isNew || rec.Student_PE_ID__c != oldMap.get(rec.Id).Student_PE_ID__c;
                if (changed) peIds.add(rec.Student_PE_ID__c);
            }
            if (rec.Course__c != null) {
                Boolean changed = isNew || rec.Course__c != oldMap.get(rec.Id).Course__c;
                if (changed) courseOfferIds.add(rec.Course__c);
            }
        }

        // --- Student PE ID → Student Name, Email, Mobile ---
        Map<Id, ProgramEnrollment> peMap = new Map<Id, ProgramEnrollment>();
        Map<Id, Contact> contactMap      = new Map<Id, Contact>();

        if (!peIds.isEmpty()) {
            peMap = new Map<Id, ProgramEnrollment>(
                [SELECT Id, ContactId FROM ProgramEnrollment WHERE Id IN :peIds]
            );
            Set<Id> contactIds = new Set<Id>();
            for (ProgramEnrollment pe : peMap.values()) {
                if (pe.ContactId != null) contactIds.add(pe.ContactId);
            }
            if (!contactIds.isEmpty()) {
                contactMap = new Map<Id, Contact>(
                    [SELECT Id, New_Admit_Email__c, MobilePhone FROM Contact WHERE Id IN :contactIds]
                );
            }
        }

        // --- Course Offering → Academic Year + Programme ---
        Map<Id, CourseOffering> courseOfferMap = new Map<Id, CourseOffering>();
        if (!courseOfferIds.isEmpty()) {
            courseOfferMap = new Map<Id, CourseOffering>(
                [SELECT Id, Academic_Year__c, Program__c, AcademicSessionId FROM CourseOffering WHERE Id IN :courseOfferIds]
            );
        }

        // --- Apply values ---
        for (Honour_Code_Committee__c rec : newList) {

            if (rec.Student_PE_ID__c != null) {
                Boolean changed = isNew || rec.Student_PE_ID__c != oldMap.get(rec.Id).Student_PE_ID__c;
                if (changed) {
                    ProgramEnrollment pe = peMap.get(rec.Student_PE_ID__c);
                    if (pe != null && pe.ContactId != null) {
                        rec.Student__c = pe.ContactId;
                        Contact con = contactMap.get(pe.ContactId);
                        if (con != null) {
                            rec.Student_Email__c = con.New_Admit_Email__c;
                            rec.Mobile_Number__c = con.MobilePhone;
                        }
                    }
                }
            }

            if (rec.Course__c != null) {
                Boolean changed = isNew || rec.Course__c != oldMap.get(rec.Id).Course__c;
                if (changed) {
                    CourseOffering co = courseOfferMap.get(rec.Course__c);
                    if (co != null) {
                        rec.Academic_Year__c          = co.Academic_Year__c;
                        rec.Programme__c              = co.Program__c;
                        rec.Academic_Terms_Session__c = co.AcademicSessionId;
                    }
                }
            }
        }
    }
}