public with sharing class ExamAAController {

    @AuraEnabled(cacheable=true)
    public static List<ExamAAWrapper> getUpcomingInvigilations() {

        Id userId = UserInfo.getUserId();
        Date today = Date.today();

        // 🔹 Fetch current User
        User currentUser = [
            SELECT Id, ContactId 
            FROM User 
            WHERE Id = :userId 
            LIMIT 1
        ];

        // 🔹 Check if user has Exam Management Permission Set
        Boolean hasExamMgmtPermission = [
            SELECT Id 
            FROM PermissionSetAssignment
            WHERE AssigneeId = :userId
            AND PermissionSet.Name = 'Exam_management_permission_set'
            LIMIT 1
        ].size() > 0;

        Id contactId;
        List<Exam_AA__c> eaaList = new List<Exam_AA__c>();

        // 🔹 Derive Contact Id (for Academic Associates)
        if (currentUser.ContactId != null) {
            contactId = currentUser.ContactId;
        } else {
            List<Contact> linkedContacts = [
                SELECT Id 
                FROM Contact 
                WHERE Linked_User_Id__c = :userId 
                LIMIT 1
            ];
            if (!linkedContacts.isEmpty()) {
                contactId = linkedContacts[0].Id;
            }
        }

        // ======================================================
        // 🔹 CASE 1 — Academic Associate (External User)
        // ======================================================
        if (contactId != null) {
            try {
                eaaList = [
                    SELECT Id, Special_Instructions__c, Assigned_On__c,
                           Exam__r.Id, Exam__r.Name, Exam__r.Course_Catalog__r.Name,
                           Exam__r.Program__r.Name, Exam__r.Academic_Term__r.Name,
                           Exam__r.Date_of_Exam__c, Exam__r.Time_of_Exam__c, Exam__r.End_Time__c,
                           Exam__r.Slot__c, Exam__r.Mode__c, Exam__r.Venue__r.Name
                    FROM Exam_AA__c
                    WHERE Academic_Associate__c = :contactId
                    AND Academic_Associate__r.Linked_User_Id__c = :userId
                    AND Exam__r.Date_of_Exam__c >= :today
                    AND (Exam__r.Visible_To_AA__c = true OR Exam__r.Visible_To_AA__c = null)
                    ORDER BY Exam__r.Date_of_Exam__c ASC
                ];
            } catch (Exception ex) {
                throw new AuraHandledException('Error fetching upcoming invigilations: ' + ex.getMessage());
            }
        }

        // ======================================================
        // 🔹 CASE 2 — Internal user WITH Exam Management Permission Set
        // ======================================================
        else if (hasExamMgmtPermission) {
            eaaList = [
                SELECT Id, Special_Instructions__c, Assigned_On__c,
                       Academic_Associate__r.Name,
                       Exam__r.Id, Exam__r.Name, Exam__r.Course_Catalog__r.Name,
                       Exam__r.Program__r.Name, Exam__r.Academic_Term__r.Name,
                       Exam__r.Date_of_Exam__c, Exam__r.Time_of_Exam__c, Exam__r.End_Time__c,
                       Exam__r.Slot__c, Exam__r.Mode__c, Exam__r.Venue__r.Name
                FROM Exam_AA__c
                WHERE Exam__r.Date_of_Exam__c >= :today
                ORDER BY Exam__r.Date_of_Exam__c ASC
            ];
        }

        // ======================================================
        // 🔹 CASE 3 — No Access
        // ======================================================
        else {
            eaaList = new List<Exam_AA__c>();
        }

        // ======================================================
        // 🔹 Convert Records to Wrapper
        // ======================================================
        List<ExamAAWrapper> output = new List<ExamAAWrapper>();
        
        // Get all exam IDs to fetch all assigned AAs
        Set<Id> examIds = new Set<Id>();
        for (Exam_AA__c eaa : eaaList) {
            if (eaa.Exam__r?.Id != null) {
                examIds.add(eaa.Exam__r.Id);
            }
        }
        
        // Fetch all Exam_AA__c records for these exams to get all assigned AAs
        Map<Id, List<String>> examToAAsMap = new Map<Id, List<String>>();
        if (!examIds.isEmpty()) {
            List<Exam_AA__c> allExamAAs = [
                SELECT Exam__c, Academic_Associate__r.Name
                FROM Exam_AA__c
                WHERE Exam__c IN :examIds
                ORDER BY Academic_Associate__r.Name ASC
            ];
            
            for (Exam_AA__c eaa : allExamAAs) {
                if (!examToAAsMap.containsKey(eaa.Exam__c)) {
                    examToAAsMap.put(eaa.Exam__c, new List<String>());
                }
                if (eaa.Academic_Associate__r != null && eaa.Academic_Associate__r.Name != null) {
                    examToAAsMap.get(eaa.Exam__c).add(eaa.Academic_Associate__r.Name);
                }
            }
        }

        for (Exam_AA__c eaa : eaaList) {
            ExamAAWrapper w = new ExamAAWrapper();
            w.examAAId = eaa.Id;
            w.examId = eaa.Exam__r?.Id;
            w.examName = eaa.Exam__r?.Name;
            w.course = eaa.Exam__r?.Course_Catalog__r?.Name;
            w.program = eaa.Exam__r?.Program__r?.Name;
            w.term = eaa.Exam__r?.Academic_Term__r?.Name;
            w.examDate = eaa.Exam__r?.Date_of_Exam__c;
            w.startTime = eaa.Exam__r?.Time_of_Exam__c;
            w.endTime = eaa.Exam__r?.End_Time__c;
            w.slot = eaa.Exam__r?.Slot__c;
            w.venue = eaa.Exam__r?.Venue__r?.Name;
            w.mode = eaa.Exam__r?.Mode__c;
            w.specialInstructions = eaa.Special_Instructions__c;

            if (hasExamMgmtPermission) {
                w.academicAssociate = eaa.Academic_Associate__r != null 
                    ? eaa.Academic_Associate__r.Name 
                    : null;
            }
            
            // Add all assigned AAs for this exam
            if (w.examId != null && examToAAsMap.containsKey(w.examId)) {
                w.allAssignedAAs = String.join(examToAAsMap.get(w.examId), ', ');
            } else {
                w.allAssignedAAs = '';
            }

            output.add(w);
        }

        return output;
    }

    // Wrapper Class
    public class ExamAAWrapper {
        @AuraEnabled public Id examAAId;
        @AuraEnabled public Id examId;
        @AuraEnabled public String examName;
        @AuraEnabled public String course;
        @AuraEnabled public String program;
        @AuraEnabled public String term;
        @AuraEnabled public Date examDate;
        @AuraEnabled public Time startTime;
        @AuraEnabled public Time endTime;
        @AuraEnabled public String slot;
        @AuraEnabled public String venue;
        @AuraEnabled public String mode;
        @AuraEnabled public String specialInstructions;
        @AuraEnabled public String academicAssociate;
        @AuraEnabled public String allAssignedAAs; // All AAs assigned to this exam
    }
}