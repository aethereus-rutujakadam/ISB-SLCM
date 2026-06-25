public without sharing class CASHDCommitteePartyTriggerHandler {
    public static void clearStaleFields(List<CASHD_Committee_Party__c> newList, Map<Id, CASHD_Committee_Party__c> oldMap) {
        Boolean isInsertContext = oldMap == null;
        Set<String> studentPgIds = new Set<String>();
        Set<String> vfEmails = new Set<String>();

        for (CASHD_Committee_Party__c rec : newList) {
            if (String.isBlank(rec.Party_Type__c)) {
                continue;
            }

            Boolean typeChanged = isInsertContext
                || !oldMap.containsKey(rec.Id)
                || rec.Party_Type__c != oldMap.get(rec.Id).Party_Type__c;

            if (typeChanged) {
                rec.Contact__c = null;

                if (rec.Party_Type__c == 'Student') {
                    rec.Email__c = null;
                } else {
                    rec.Student_Id__c = null;
                }
            }

            if (rec.Party_Type__c == 'Student') {
                if (!String.isBlank(rec.Student_Id__c)) {
                    studentPgIds.add(rec.Student_Id__c.trim());
                }
            } else if (!String.isBlank(rec.Email__c)) {
                vfEmails.add(rec.Email__c.trim().toLowerCase());
            }
        }

        Map<String, Id> pgIdToContactId = getContactByProgramEnrollment(studentPgIds);
        Map<String, Id> vfEmailToContactId = getContactByVfEmail(vfEmails);

        for (CASHD_Committee_Party__c rec : newList) {
            if (String.isBlank(rec.Party_Type__c)) {
                continue;
            }

            if (rec.Party_Type__c == 'Student') {
                if (String.isBlank(rec.Student_Id__c)) {
                    rec.Contact__c = null;
                    continue;
                }
                rec.Contact__c = pgIdToContactId.get(rec.Student_Id__c.trim());
                continue;
            }

            if (String.isBlank(rec.Email__c)) {
                rec.Contact__c = null;
                continue;
            }
            rec.Contact__c = vfEmailToContactId.get(rec.Email__c.trim().toLowerCase());
        }
    }

    private static Map<String, Id> getContactByProgramEnrollment(Set<String> studentPgIds) {
        Map<String, Id> results = new Map<String, Id>();
        if (studentPgIds == null || studentPgIds.isEmpty()) {
            return results;
        }

        for (ProgramEnrollment pe : [
            SELECT ContactId, PGID__c
            FROM ProgramEnrollment
            WHERE PGID__c IN :studentPgIds
            AND ContactId != null
            ORDER BY LastModifiedDate DESC
        ]) {
            String key = pe.PGID__c == null ? null : pe.PGID__c.trim();
            if (String.isBlank(key) || results.containsKey(key)) {
                continue;
            }
            results.put(key, pe.ContactId);
        }

        return results;
    }

    private static Map<String, Id> getContactByVfEmail(Set<String> vfEmails) {
        Map<String, Id> results = new Map<String, Id>();
        if (vfEmails == null || vfEmails.isEmpty()) {
            return results;
        }

        for (Contact c : [
            SELECT Id, VF_Email_ID__c
            FROM Contact
            WHERE VF_Email_ID__c IN :vfEmails
            ORDER BY LastModifiedDate DESC
        ]) {
            if (String.isBlank(c.VF_Email_ID__c)) {
                continue;
            }
            String key = c.VF_Email_ID__c.trim().toLowerCase();
            if (!results.containsKey(key)) {
                results.put(key, c.Id);
            }
        }

        return results;
    }
}