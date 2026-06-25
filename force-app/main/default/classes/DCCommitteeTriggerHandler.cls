/**
 * @description       :
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             :
 * @last modified on  : 05-12-2026
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
public without sharing class DCCommitteeTriggerHandler {

    public static void populateFromPGID(List<Disciplinary_Committee__c> newList, Map<Id, Disciplinary_Committee__c> oldMap) {
        Boolean isNew = (oldMap == null);

        Set<String> pgIds = new Set<String>();

        for (Disciplinary_Committee__c rec : newList) {
            if (!String.isBlank(rec.Student_PG_ID__c)) {
                Boolean changed = isNew || rec.Student_PG_ID__c != oldMap.get(rec.Id).Student_PG_ID__c;
                if (changed) pgIds.add(rec.Student_PG_ID__c.trim());
            }
        }

        if (pgIds.isEmpty()) return;

        Map<String, ProgramEnrollment> pgIdToPE = new Map<String, ProgramEnrollment>();
        for (ProgramEnrollment pe : [
            SELECT Id, ContactId, PGID__c, IsActive, ProgramId, Academic_Term__c
            FROM ProgramEnrollment
            WHERE PGID__c IN :pgIds
        ]) {
            if (pe.PGID__c != null) pgIdToPE.put(pe.PGID__c, pe);
        }

        for (Disciplinary_Committee__c rec : newList) {
            if (!String.isBlank(rec.Student_PG_ID__c)) {
                Boolean changed = isNew || rec.Student_PG_ID__c != oldMap.get(rec.Id).Student_PG_ID__c;
                if (changed) {
                    ProgramEnrollment pe = pgIdToPE.get(rec.Student_PG_ID__c.trim());
                    if (pe == null) {
                        rec.Student_PG_ID__c.addError('Incorrect PG ID. No student found with PG ID: ' + rec.Student_PG_ID__c);
                    } else if (!pe.IsActive) {
                        rec.Student_PG_ID__c.addError('Student is not active. The Program Enrollment for PG ID ' + rec.Student_PG_ID__c + ' is not active.');
                    } else {
                        rec.ProgramEnrollment__c = pe.Id;
                        if (pe.ContactId != null) {
                            rec.Student_Staff_Name__c = pe.ContactId;
                        }
                        rec.Programme__c = pe.ProgramId;
                        rec.Cohort__c    = pe.Academic_Term__c;
                    }
                }
            }
        }
    }

    public static void populateStudentDetails(List<Disciplinary_Committee__c> newList, Map<Id, Disciplinary_Committee__c> oldMap) {
        Boolean isNew = (oldMap == null);

        Set<Id> peIds = new Set<Id>();

        for (Disciplinary_Committee__c rec : newList) {
            if (rec.ProgramEnrollment__c != null) {
                Boolean changed = isNew || rec.ProgramEnrollment__c != oldMap.get(rec.Id).ProgramEnrollment__c;
                if (changed) peIds.add(rec.ProgramEnrollment__c);
            }
        }

        if (peIds.isEmpty()) return;

        Map<Id, ProgramEnrollment> peMap = new Map<Id, ProgramEnrollment>(
            [SELECT Id, ContactId, ProgramId, Academic_Term__c FROM ProgramEnrollment WHERE Id IN :peIds]
        );

        for (Disciplinary_Committee__c rec : newList) {
            if (rec.ProgramEnrollment__c != null) {
                Boolean changed = isNew || rec.ProgramEnrollment__c != oldMap.get(rec.Id).ProgramEnrollment__c;
                if (changed) {
                    ProgramEnrollment pe = peMap.get(rec.ProgramEnrollment__c);
                    if (pe != null && pe.ContactId != null) {
                        rec.Student_Staff_Name__c = pe.ContactId;
                    }
                    if (pe != null) {
                        rec.Programme__c = pe.ProgramId;
                        rec.Cohort__c    = pe.Academic_Term__c;
                    }
                }
            }
        }
    }

    public static void populateComplaintDetails(List<Disciplinary_Committee__c> newList, Map<Id, Disciplinary_Committee__c> oldMap) {
        Boolean isNew = (oldMap == null);

        Set<String> studentPgIds = new Set<String>();
        Set<String> staffEmails  = new Set<String>();

        for (Disciplinary_Committee__c rec : newList) {
            if (!String.isBlank(rec.Complaint_raised_by_Student_ID__c)) {
                Boolean changed = isNew || rec.Complaint_raised_by_Student_ID__c != oldMap.get(rec.Id).Complaint_raised_by_Student_ID__c;
                if (changed) studentPgIds.add(rec.Complaint_raised_by_Student_ID__c.trim());
            }
            if (!String.isBlank(rec.Complaint_raised_by_Staff_ID__c)) {
                Boolean changed = isNew || rec.Complaint_raised_by_Staff_ID__c != oldMap.get(rec.Id).Complaint_raised_by_Staff_ID__c;
                if (changed) staffEmails.add(rec.Complaint_raised_by_Staff_ID__c.trim());
            }
        }

        // --- Student: ProgramEnrollment.PGID__c → ContactId + MobilePhone ---
        Map<String, Id>     pgIdToContactId = new Map<String, Id>();
        Map<String, String> pgIdToMobile    = new Map<String, String>();

        if (!studentPgIds.isEmpty()) {
            for (ProgramEnrollment pe : [
                SELECT Id, ContactId, PGID__c, Contact.MobilePhone
                FROM ProgramEnrollment
                WHERE PGID__c IN :studentPgIds
            ]) {
                if (pe.PGID__c != null) {
                    pgIdToContactId.put(pe.PGID__c, pe.ContactId);
                    pgIdToMobile.put(pe.PGID__c, pe.Contact != null ? pe.Contact.MobilePhone : null);
                }
            }
        }

        // --- Staff: search Faculty contacts by ISB_Email_ID__c or VF_Email_ID__c ---
        Map<String, Contact> emailToFacultyContact = new Map<String, Contact>();

        if (!staffEmails.isEmpty()) {
            for (Contact c : [
                SELECT Id, ISB_Email_ID__c, VF_Email_ID__c, MobilePhone
                FROM Contact
                WHERE RecordType.Name = 'Faculty'
                AND (ISB_Email_ID__c IN :staffEmails OR VF_Email_ID__c IN :staffEmails)
            ]) {
                if (c.ISB_Email_ID__c != null && staffEmails.contains(c.ISB_Email_ID__c)) {
                    emailToFacultyContact.put(c.ISB_Email_ID__c, c);
                }
                if (c.VF_Email_ID__c != null && staffEmails.contains(c.VF_Email_ID__c)) {
                    emailToFacultyContact.put(c.VF_Email_ID__c, c);
                }
            }
        }

        // --- Apply ---
        for (Disciplinary_Committee__c rec : newList) {

            // Student ID → Contact + Mobile
            if (!String.isBlank(rec.Complaint_raised_by_Student_ID__c)) {
                Boolean changed = isNew || rec.Complaint_raised_by_Student_ID__c != oldMap.get(rec.Id).Complaint_raised_by_Student_ID__c;
                if (changed) {
                    String pgId = rec.Complaint_raised_by_Student_ID__c.trim();
                    Id contactId = pgIdToContactId.get(pgId);
                    if (contactId != null) {
                        rec.Student_Complaint__c = contactId;
                        String mobile = pgIdToMobile.get(pgId);
                        if (!String.isBlank(mobile)) {
                            rec.Mobile_Number_Student__c = mobile;
                        }
                    } else {
                        rec.Student_Complaint__c     = null;
                        rec.Mobile_Number_Student__c = null;
                    }
                    // Student side entered — clear staff fields
                    rec.Complaint_raised_by_Staff_ID__c = null;
                    rec.Complaint_raised_by_Staff__c    = null;
                    rec.Mobile_Number_Staff__c          = null;
                }
            }

            // Staff Email ID → Faculty Contact
            if (!String.isBlank(rec.Complaint_raised_by_Staff_ID__c)) {
                Boolean changed = isNew || rec.Complaint_raised_by_Staff_ID__c != oldMap.get(rec.Id).Complaint_raised_by_Staff_ID__c;
                if (changed) {
                    String email = rec.Complaint_raised_by_Staff_ID__c.trim();
                    Contact faculty = emailToFacultyContact.get(email);
                    if (faculty != null) {
                        rec.Complaint_raised_by_Staff__c = faculty.Id;
                        if (!String.isBlank(faculty.MobilePhone)) {
                            rec.Mobile_Number_Staff__c = faculty.MobilePhone;
                        }
                    } else {
                        rec.Complaint_raised_by_Staff__c = null;
                        rec.Mobile_Number_Staff__c        = null;
                    }
                    // Staff side entered — clear student fields
                    rec.Complaint_raised_by_Student_ID__c = null;
                    rec.Student_Complaint__c              = null;
                    rec.Mobile_Number_Student__c          = null;
                }
            }
        }
    }
}