public without sharing class WorkshopAttendanceHandler {

    public static void handleBeforeUpsert(List<Workshop_Attendance__c> records) {
        if (records == null || records.isEmpty()) {
            return;
        }

        Set<Id> registrationIds = new Set<Id>();
        Set<Id> workshopIds = new Set<Id>();
        Set<Id> studentIds = new Set<Id>();

        for (Workshop_Attendance__c att : records) {
            if (att.Program_Enrollment__c != null) {
                continue;
            }
            if (att.Workshop_Registration__c != null) {
                registrationIds.add(att.Workshop_Registration__c);
            }
            if (att.Workshop__c != null) {
                workshopIds.add(att.Workshop__c);
            }
            if (att.Student__c != null) {
                studentIds.add(att.Student__c);
            }
        }

        Map<Id, Workshop_Registration__c> registrationsById = registrationIds.isEmpty()
            ? new Map<Id, Workshop_Registration__c>()
            : new Map<Id, Workshop_Registration__c>([
                SELECT Id, Program_Enrollment__c
                FROM Workshop_Registration__c
                WHERE Id IN :registrationIds
            ]);

        Map<Id, Workshop__c> workshopsById = workshopIds.isEmpty()
            ? new Map<Id, Workshop__c>()
            : new Map<Id, Workshop__c>([
                SELECT Id, Program__c
                FROM Workshop__c
                WHERE Id IN :workshopIds
            ]);

        Map<String, Id> studentProgramToEnrollmentId = new Map<String, Id>();
        Map<Id, Id> studentToEnrollmentId = new Map<Id, Id>();

        if (!studentIds.isEmpty()) {
            for (ProgramEnrollment pe : [
                SELECT Id, ContactId, AccountId
                FROM ProgramEnrollment
                WHERE ContactId IN :studentIds
                AND IsActive = true
                ORDER BY CreatedDate DESC
            ]) {
                if (!studentToEnrollmentId.containsKey(pe.ContactId)) {
                    studentToEnrollmentId.put(pe.ContactId, pe.Id);
                }
                if (pe.AccountId != null) {
                    studentProgramToEnrollmentId.put(pe.ContactId + '_' + pe.AccountId, pe.Id);
                }
            }
        }

        for (Workshop_Attendance__c att : records) {
            if (att.Program_Enrollment__c != null) {
                continue;
            }

            Id resolvedEnrollmentId;

            if (att.Workshop_Registration__c != null && registrationsById.containsKey(att.Workshop_Registration__c)) {
                resolvedEnrollmentId = registrationsById.get(att.Workshop_Registration__c).Program_Enrollment__c;
            }

            if (resolvedEnrollmentId == null && att.Student__c != null) {
                Workshop__c workshop = workshopsById.get(att.Workshop__c);
                if (workshop != null && workshop.Program__c != null) {
                    resolvedEnrollmentId = studentProgramToEnrollmentId.get(att.Student__c + '_' + workshop.Program__c);
                }
                if (resolvedEnrollmentId == null) {
                    resolvedEnrollmentId = studentToEnrollmentId.get(att.Student__c);
                }
            }

            if (resolvedEnrollmentId != null) {
                att.Program_Enrollment__c = resolvedEnrollmentId;
            }
        }
    }
}