/**
 * @description       :
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             :
 * @last modified on  : 05-12-2026
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
public without sharing class CASHDCommitteeTriggerHandler {

    public static void populateFromPGID(List<CASHD_Committee__c> newList, Map<Id, CASHD_Committee__c> oldMap) {
        Boolean isNew = (oldMap == null);

        Set<String> pgIds = new Set<String>();

        for (CASHD_Committee__c rec : newList) {
            if (!String.isBlank(rec.Student_PG_ID_Text__c)) {
                Boolean changed = isNew || rec.Student_PG_ID_Text__c != oldMap.get(rec.Id).Student_PG_ID_Text__c;
                if (changed) pgIds.add(rec.Student_PG_ID_Text__c.trim());
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
        for (CASHD_Committee__c rec : newList) {
            if (!String.isBlank(rec.Student_PG_ID_Text__c)) {
                Boolean changed = isNew || rec.Student_PG_ID_Text__c != oldMap.get(rec.Id).Student_PG_ID_Text__c;
                if (changed) {
                    ProgramEnrollment pe = pgIdToPE.get(rec.Student_PG_ID_Text__c.trim());
                    if (pe == null) {
                        rec.Student_PG_ID_Text__c.addError('Incorrect PG ID. No student found with PG ID: ' + rec.Student_PG_ID_Text__c);
                    } else if (!pe.IsActive) {
                        rec.Student_PG_ID_Text__c.addError('Student is not active. The Program Enrollment for PG ID ' + rec.Student_PG_ID_Text__c + ' is not active.');
                    } else {
                        rec.Student_PG_ID__c = pe.Id;
                        if (pe.ContactId != null) {
                            rec.Student_Name__c = pe.ContactId;
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

    public static void populateComplainantRespondentDetails(List<CASHD_Committee__c> newList, Map<Id, CASHD_Committee__c> oldMap) {
        Boolean isNew = (oldMap == null);

        Set<String> staffEmails  = new Set<String>();
        Set<String> studentPgIds = new Set<String>();

        for (CASHD_Committee__c rec : newList) {
            // Complainant
            if (rec.Complainant_Type__c == 'Staff' && !String.isBlank(rec.Complainant_Email__c)) {
                Boolean changed = isNew || rec.Complainant_Email__c != oldMap.get(rec.Id).Complainant_Email__c
                                        || rec.Complainant_Type__c != oldMap.get(rec.Id).Complainant_Type__c;
                if (changed) staffEmails.add(rec.Complainant_Email__c.trim().toLowerCase());
            }
            if (rec.Complainant_Type__c == 'Student' && !String.isBlank(rec.Complainant_Student_Id__c)) {
                Boolean changed = isNew || rec.Complainant_Student_Id__c != oldMap.get(rec.Id).Complainant_Student_Id__c
                                        || rec.Complainant_Type__c != oldMap.get(rec.Id).Complainant_Type__c;
                if (changed) studentPgIds.add(rec.Complainant_Student_Id__c.trim());
            }
            // Respondent
            if (rec.Respondent_Type__c == 'Staff' && !String.isBlank(rec.Respondent_Email__c)) {
                Boolean changed = isNew || rec.Respondent_Email__c != oldMap.get(rec.Id).Respondent_Email__c
                                        || rec.Respondent_Type__c != oldMap.get(rec.Id).Respondent_Type__c;
                if (changed) staffEmails.add(rec.Respondent_Email__c.trim().toLowerCase());
            }
            if (rec.Respondent_Type__c == 'Student' && !String.isBlank(rec.Respondent_Student_Id__c)) {
                Boolean changed = isNew || rec.Respondent_Student_Id__c != oldMap.get(rec.Id).Respondent_Student_Id__c
                                        || rec.Respondent_Type__c != oldMap.get(rec.Id).Respondent_Type__c;
                if (changed) studentPgIds.add(rec.Respondent_Student_Id__c.trim());
            }
        }

        // --- Faculty contacts by VF_Email_ID__c ---
        Map<String, Id> emailToFacultyId = new Map<String, Id>();
        if (!staffEmails.isEmpty()) {
            for (Contact c : [
                SELECT Id, VF_Email_ID__c
                FROM Contact
                WHERE RecordType.Name = 'Faculty'
                AND VF_Email_ID__c IN :staffEmails
            ]) {
                if (!String.isBlank(c.VF_Email_ID__c)) {
                    emailToFacultyId.put(c.VF_Email_ID__c.toLowerCase(), c.Id);
                }
            }
        }

        // --- Student contacts by ProgramEnrollment.PGID__c ---
        Map<String, Id> pgIdToContactId = new Map<String, Id>();
        if (!studentPgIds.isEmpty()) {
            for (ProgramEnrollment pe : [
                SELECT Id, ContactId, PGID__c
                FROM ProgramEnrollment
                WHERE PGID__c IN :studentPgIds
            ]) {
                if (pe.PGID__c != null && pe.ContactId != null) {
                    pgIdToContactId.put(pe.PGID__c, pe.ContactId);
                }
            }
        }

        // --- Apply ---
        for (CASHD_Committee__c rec : newList) {

            // --- Complainant ---
            if (rec.Complainant_Type__c == 'Staff' && !String.isBlank(rec.Complainant_Email__c)) {
                Boolean changed = isNew || rec.Complainant_Email__c != oldMap.get(rec.Id).Complainant_Email__c
                                        || rec.Complainant_Type__c != oldMap.get(rec.Id).Complainant_Type__c;
                if (changed) {
                    Id facultyId = emailToFacultyId.get(rec.Complainant_Email__c.trim().toLowerCase());
                    if (facultyId != null) {
                        rec.Name_of_the_Complainant__c = facultyId;
                    } else {
                        rec.Name_of_the_Complainant__c = null;
                    }
                }
            }
            if (rec.Complainant_Type__c == 'Student' && !String.isBlank(rec.Complainant_Student_Id__c)) {
                Boolean changed = isNew || rec.Complainant_Student_Id__c != oldMap.get(rec.Id).Complainant_Student_Id__c
                                        || rec.Complainant_Type__c != oldMap.get(rec.Id).Complainant_Type__c;
                if (changed) {
                    Id contactId = pgIdToContactId.get(rec.Complainant_Student_Id__c.trim());
                    if (contactId != null) {
                        rec.Name_of_the_Complainant__c = contactId;
                    } else {
                        rec.Complainant_Student_Id__c.addError('Student ID not found. No student exists with ID: ' + rec.Complainant_Student_Id__c);
                    }
                }
            }

            // --- Respondent ---
            if (rec.Respondent_Type__c == 'Staff' && !String.isBlank(rec.Respondent_Email__c)) {
                Boolean changed = isNew || rec.Respondent_Email__c != oldMap.get(rec.Id).Respondent_Email__c
                                        || rec.Respondent_Type__c != oldMap.get(rec.Id).Respondent_Type__c;
                if (changed) {
                    Id facultyId = emailToFacultyId.get(rec.Respondent_Email__c.trim().toLowerCase());
                    if (facultyId != null) {
                        rec.Name_of_the_Respondent__c = facultyId;
                    } else {
                        rec.Name_of_the_Respondent__c = null;
                    }
                }
            }
            if (rec.Respondent_Type__c == 'Student' && !String.isBlank(rec.Respondent_Student_Id__c)) {
                Boolean changed = isNew || rec.Respondent_Student_Id__c != oldMap.get(rec.Id).Respondent_Student_Id__c
                                        || rec.Respondent_Type__c != oldMap.get(rec.Id).Respondent_Type__c;
                if (changed) {
                    Id contactId = pgIdToContactId.get(rec.Respondent_Student_Id__c.trim());
                    if (contactId != null) {
                        rec.Name_of_the_Respondent__c = contactId;
                    } else {
                        rec.Respondent_Student_Id__c.addError('Student ID not found. No student exists with ID: ' + rec.Respondent_Student_Id__c);
                    }
                }
            }
        }
    }

    public static void populateStudentStaffName(List<CASHD_Committee__c> newList, Map<Id, CASHD_Committee__c> oldMap) {
        Boolean isNew = (oldMap == null);

        Set<String> staffEmails  = new Set<String>();
        Set<String> studentPgIds = new Set<String>();

        for (CASHD_Committee__c rec : newList) {
            if (rec.Student_Staff_Type__c == 'Staff' && !String.isBlank(rec.Staff_Email__c)) {
                Boolean changed = isNew || rec.Staff_Email__c != oldMap.get(rec.Id).Staff_Email__c
                                        || rec.Student_Staff_Type__c != oldMap.get(rec.Id).Student_Staff_Type__c;
                if (changed) staffEmails.add(rec.Staff_Email__c.trim().toLowerCase());
            }
            if (rec.Student_Staff_Type__c == 'Student' && !String.isBlank(rec.Student_Id__c)) {
                Boolean changed = isNew || rec.Student_Id__c != oldMap.get(rec.Id).Student_Id__c
                                        || rec.Student_Staff_Type__c != oldMap.get(rec.Id).Student_Staff_Type__c;
                if (changed) studentPgIds.add(rec.Student_Id__c.trim());
            }
        }

        Map<String, Id> emailToFacultyId = new Map<String, Id>();
        if (!staffEmails.isEmpty()) {
            for (Contact c : [
                SELECT Id, VF_Email_ID__c
                FROM Contact
                WHERE RecordType.Name = 'Faculty'
                AND VF_Email_ID__c IN :staffEmails
            ]) {
                if (!String.isBlank(c.VF_Email_ID__c)) {
                    emailToFacultyId.put(c.VF_Email_ID__c.toLowerCase(), c.Id);
                }
            }
        }

        Map<String, Id> pgIdToContactId = new Map<String, Id>();
        if (!studentPgIds.isEmpty()) {
            for (ProgramEnrollment pe : [
                SELECT Id, ContactId, PGID__c
                FROM ProgramEnrollment
                WHERE PGID__c IN :studentPgIds
            ]) {
                if (pe.PGID__c != null && pe.ContactId != null) {
                    pgIdToContactId.put(pe.PGID__c, pe.ContactId);
                }
            }
        }

        for (CASHD_Committee__c rec : newList) {
            if (rec.Student_Staff_Type__c == 'Staff' && !String.isBlank(rec.Staff_Email__c)) {
                Boolean changed = isNew || rec.Staff_Email__c != oldMap.get(rec.Id).Staff_Email__c
                                        || rec.Student_Staff_Type__c != oldMap.get(rec.Id).Student_Staff_Type__c;
                if (changed) {
                    Id facultyId = emailToFacultyId.get(rec.Staff_Email__c.trim().toLowerCase());
                    if (facultyId != null) {
                        rec.Student_Staff_Name__c = facultyId;
                    } else {
                        rec.Student_Staff_Name__c = null;
                    }
                }
            }
            if (rec.Student_Staff_Type__c == 'Student' && !String.isBlank(rec.Student_Id__c)) {
                Boolean changed = isNew || rec.Student_Id__c != oldMap.get(rec.Id).Student_Id__c
                                        || rec.Student_Staff_Type__c != oldMap.get(rec.Id).Student_Staff_Type__c;
                if (changed) {
                    Id contactId = pgIdToContactId.get(rec.Student_Id__c.trim());
                    if (contactId != null) {
                        rec.Student_Staff_Name__c = contactId;
                    } else {
                        rec.Student_Id__c.addError('Student ID not found. No student exists with ID: ' + rec.Student_Id__c);
                    }
                }
            }
        }
    }

    public static void populateStudentDetails(List<CASHD_Committee__c> newList, Map<Id, CASHD_Committee__c> oldMap) {
        Boolean isNew = (oldMap == null);

        Set<Id> peIds          = new Set<Id>();
        Set<Id> courseOfferIds = new Set<Id>();

        for (CASHD_Committee__c rec : newList) {
            if (rec.Student_PG_ID__c != null) {
                Boolean changed = isNew || rec.Student_PG_ID__c != oldMap.get(rec.Id).Student_PG_ID__c;
                if (changed) peIds.add(rec.Student_PG_ID__c);
            }
            if (rec.Course__c != null) {
                Boolean changed = isNew || rec.Course__c != oldMap.get(rec.Id).Course__c;
                if (changed) courseOfferIds.add(rec.Course__c);
            }
        }

        // --- Student PG ID → Student Name, Email, Mobile ---
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

        // --- Course Offering → Academic Year ---
        Map<Id, CourseOffering> courseOfferMap = new Map<Id, CourseOffering>();
        if (!courseOfferIds.isEmpty()) {
            courseOfferMap = new Map<Id, CourseOffering>(
                [SELECT Id, Academic_Year__c FROM CourseOffering WHERE Id IN :courseOfferIds]
            );
        }

        // --- Enrollment validation: ContactId + CourseOfferingId ---
        Set<Id> contactIdsForValidation = new Set<Id>();
        for (ProgramEnrollment pe : peMap.values()) {
            if (pe.ContactId != null) contactIdsForValidation.add(pe.ContactId);
        }

        Set<String> enrolledKeys = new Set<String>();
        if (!contactIdsForValidation.isEmpty() && !courseOfferIds.isEmpty()) {
            for (CourseOfferingParticipant cop : [
                SELECT ParticipantContactId, CourseOfferingId
                FROM CourseOfferingParticipant
                WHERE ParticipantContactId IN :contactIdsForValidation
                AND CourseOfferingId IN :courseOfferIds
            ]) {
                enrolledKeys.add(cop.ParticipantContactId + '_' + cop.CourseOfferingId);
            }
        }

        // --- Apply values ---
        for (CASHD_Committee__c rec : newList) {

            if (rec.Student_PG_ID__c != null && rec.Course__c != null) {
                ProgramEnrollment pe = peMap.get(rec.Student_PG_ID__c);
                if (pe != null) {
                    String key = pe.ContactId + '_' + rec.Course__c;
                    if (!enrolledKeys.contains(key)) {
                        rec.addError('This student is not enrolled to the selected course.');
                    }
                }
            }

            if (rec.Student_PG_ID__c != null) {
                Boolean changed = isNew || rec.Student_PG_ID__c != oldMap.get(rec.Id).Student_PG_ID__c;
                if (changed) {
                    ProgramEnrollment pe = peMap.get(rec.Student_PG_ID__c);
                    if (pe != null && pe.ContactId != null) {
                        rec.Student_Name__c  = pe.ContactId;
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
                        rec.Academic_Year__c = co.Academic_Year__c;
                    }
                }
            }
        }
    }
}