public class OutgoingExchangeCaseHandler {
    private static final Id OUTGOING_EXCHANGE_RT_ID = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName().containsKey('Outgoing_Exchange')
        ? Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName().get('Outgoing_Exchange').getRecordTypeId()
        : null;
    private static final String OUTGOING_CHECKLIST_RT_DEV_NAME = 'Outgoing_Exchange_Checklist';

    // This handler owns outgoing exchange clearance stamps, stage auto-transitions, and auto-closure.
    // Closed_Date__c is stamped here because the Outgoing_Case_Closure_Flow fires after this trigger
    // and cannot see the Status = Closed set below.
    public static void handleBeforeUpdate(List<Case> newCases, Map<Id, Case> oldMap) {
        if (OUTGOING_EXCHANGE_RT_ID == null || newCases == null || newCases.isEmpty() || oldMap == null) {
            return;
        }

        for (Case c : newCases) {
            Case old = oldMap.get(c.Id);

            if (c.RecordTypeId != OUTGOING_EXCHANGE_RT_ID) {
                continue;
            }

            stampOutgoingDepartmentClearance(c, old);

            // Step 1: ASA In Progress → RO Review
            // Gate: Finance Cleared + all 5 department clearance flags
            if (c.Status == 'ASA In Progress'
                    && c.Finance_Cleared__c == 'Cleared'
                    && c.ASA_SA_Cleared__c == true
                    && c.Operations_Cleared__c == true
                    && c.IT_Cleared__c == true
                    && c.LRC_Cleared__c == true) {
                c.Status = 'RO Review';
            }

            // Step 2: RO Review → Transcript Check
            // Gate: Partner Transcript Received flips to true
            if (c.Status == 'RO Review'
                    && c.Partner_Transcript_Received__c == true
                    && old.Partner_Transcript_Received__c == false) {
                c.Status = 'Transcript Check';
            }

            // Step 3: Transcript Check → Student Credit Check
            // Gate: Grading Scale Uploaded AND Course Confirmation Form both checked
            if (c.Status == 'Transcript Check'
                    && c.Grading_Scale_Uploaded__c == true
                    && c.Course_Confirmation_Form__c == true) {
                c.Status = 'Student Credit Check';
            }

            // Step 4: Student Credit Check → Closed
            // Gate: Ready for Graduation Audit flips to true
            if (c.Status == 'Student Credit Check'
                    && c.Ready_for_Graduation_Audit__c == true
                    && old.Ready_for_Graduation_Audit__c == false) {
                c.Status = 'Closed';
                c.Closed_Date__c = System.now();
            }
        }
    }

    private static void stampOutgoingDepartmentClearance(Case c, Case oldCase) {
        Datetime stampTime = System.now();
        Id currentUserId = UserInfo.getUserId();

        if (c.Operations_Cleared__c == true && oldCase.Operations_Cleared__c != true) {
            c.Operations_Cleared_By__c = currentUserId;
            c.Operations_Cleared_Date__c = stampTime;
        }
        if (c.IT_Cleared__c == true && oldCase.IT_Cleared__c != true) {
            c.IT_Cleared_By__c = currentUserId;
            c.IT_Cleared_Date__c = stampTime;
        }
        if (c.LRC_Cleared__c == true && oldCase.LRC_Cleared__c != true) {
            c.LRC_Cleared_By__c = currentUserId;
            c.LRC_Cleared_Date__c = stampTime;
        }
        if (c.ASA_SA_Cleared__c == true && oldCase.ASA_SA_Cleared__c != true) {
            c.ASA_SA_Cleared_By__c = currentUserId;
            c.ASA_SA_Cleared_Date__c = stampTime;
        }
        if (c.Finance_Cleared__c == 'Cleared' && oldCase.Finance_Cleared__c != 'Cleared') {
            c.Finance_Cleared_Date__c = stampTime;
        }
        if (c.Transcript_Dispatched__c == true && oldCase.Transcript_Dispatched__c != true) {
            c.Dispatched_By_User__c = currentUserId;
            c.Dispatch_Date__c = stampTime;
        }
    }

    public static void handleAfterUpdate(List<Case> newCases, Map<Id, Case> oldMap) {
        if (OUTGOING_EXCHANGE_RT_ID == null || newCases == null || newCases.isEmpty() || oldMap == null) {
            return;
        }

        Map<Id, ProgramEnrollment> peToUpdate = new Map<Id, ProgramEnrollment>();
        
        for (Case c : newCases) {
            Case oldC = oldMap.get(c.Id);
            
            if (c.RecordTypeId == OUTGOING_EXCHANGE_RT_ID && c.Program_Enrollment__c != null && (
                c.Transcript_Dispatched__c != oldC.Transcript_Dispatched__c ||
                c.Dispatch_Date__c != oldC.Dispatch_Date__c ||
                c.Dispatched_By_User__c != oldC.Dispatched_By_User__c ||
                c.Partner_Transcript_Received__c != oldC.Partner_Transcript_Received__c ||
                c.Partner_Transcript_Upload_Date__c != oldC.Partner_Transcript_Upload_Date__c ||
                c.Transcript_Notes__c != oldC.Transcript_Notes__c ||
                c.Transcripts_Received__c != oldC.Transcripts_Received__c ||
                c.Tracking_Number__c != oldC.Tracking_Number__c
            )) {
                ProgramEnrollment pe = new ProgramEnrollment(Id = c.Program_Enrollment__c);
                pe.Transcript_Dispatched__c = c.Transcript_Dispatched__c;
                pe.Dispatch_Date__c = c.Dispatch_Date__c;
                pe.Dispatched_By_User__c = c.Dispatched_By_User__c;
                pe.Partner_Transcript_Received__c = c.Partner_Transcript_Received__c;
                pe.Partner_Transcript_Upload_Date__c = c.Partner_Transcript_Upload_Date__c;
                pe.Transcript_Notes__c = c.Transcript_Notes__c;
                pe.Transcripts_Received__c = c.Transcripts_Received__c;
                pe.Tracking_Number__c = c.Tracking_Number__c;
                
                peToUpdate.put(pe.Id, pe);
            }
        }
        
        if (!peToUpdate.isEmpty()) {
            update peToUpdate.values();
        }
    }

    public static void handleAfterInsert(List<Case> newCases) {
        if (OUTGOING_EXCHANGE_RT_ID == null || newCases == null || newCases.isEmpty()) {
            return;
        }

        Id checklistRtId = getRecordTypeId(Course_Checklist__c.SObjectType, OUTGOING_CHECKLIST_RT_DEV_NAME);
        Id checklistItemRtId = getRecordTypeId(Course_Checklist_Item__c.SObjectType, OUTGOING_CHECKLIST_RT_DEV_NAME);
        Id templateRtId = getRecordTypeId(Course_Checklist_Item_Template__c.SObjectType, OUTGOING_CHECKLIST_RT_DEV_NAME);

        if (checklistRtId == null) {
            return;
        }

        Set<Id> outgoingCaseIds = new Set<Id>();
        for (Case c : newCases) {
            if (c.RecordTypeId == OUTGOING_EXCHANGE_RT_ID) {
                outgoingCaseIds.add(c.Id);
            }
        }

        if (outgoingCaseIds.isEmpty()) {
            return;
        }

        Map<Id, Case> outgoingCaseMap = new Map<Id, Case>([
            SELECT Id, CaseNumber, OwnerId, ContactId, Program__c
            FROM Case
            WHERE Id IN :outgoingCaseIds
        ]);

        if (outgoingCaseMap.isEmpty()) {
            return;
        }

        Set<Id> existingChecklistCaseIds = new Set<Id>();
        for (Course_Checklist__c existingChecklist : [
            SELECT Id, Case__c
            FROM Course_Checklist__c
            WHERE Case__c IN :outgoingCaseIds
              AND RecordTypeId = :checklistRtId
        ]) {
            existingChecklistCaseIds.add(existingChecklist.Case__c);
        }

        List<Course_Checklist__c> checklistsToInsert = new List<Course_Checklist__c>();
        Map<Id, Course_Checklist__c> checklistByCaseId = new Map<Id, Course_Checklist__c>();

        for (Case c : outgoingCaseMap.values()) {
            if (existingChecklistCaseIds.contains(c.Id)) {
                continue;
            }

            String caseRef = String.isBlank(c.CaseNumber) ? String.valueOf(c.Id) : c.CaseNumber;
            Course_Checklist__c checklist = new Course_Checklist__c(
                RecordTypeId = checklistRtId,
                Name = 'Outgoing Exchange Checklist - ' + caseRef,
                Case__c = c.Id,
                Student__c = c.ContactId,
                Program__c = c.Program__c,
                Status__c = 'Active',
                OwnerId = c.OwnerId,
                Source_Object__c = 'Case',
                Source_Record_Id__c = c.Id
            );

            checklistsToInsert.add(checklist);
            checklistByCaseId.put(c.Id, checklist);
        }

        if (checklistsToInsert.isEmpty()) {
            return;
        }

        insert checklistsToInsert;

        if (checklistItemRtId == null || templateRtId == null) {
            return;
        }

        List<Course_Checklist_Item_Template__c> templates = [
            SELECT Id,
                   Subject__c,
                   Description__c,
                   Priority__c,
                   Owner_Roles__c,
                   Activity_Type__c,
                   Course_Type__c,
                   Start_Date__c,
                   End_Date__c,
                   Reminder_Logic_Calculation__c,
                   Reminder_Reference_Days__c
            FROM Course_Checklist_Item_Template__c
                        WHERE RecordTypeId = :templateRtId
                            AND RecordType.DeveloperName = :OUTGOING_CHECKLIST_RT_DEV_NAME
        ];

        if (templates.isEmpty()) {
            return;
        }

        List<Course_Checklist_Item__c> itemsToInsert = new List<Course_Checklist_Item__c>();
        for (Case c : outgoingCaseMap.values()) {
            Course_Checklist__c parentChecklist = checklistByCaseId.get(c.Id);
            if (parentChecklist == null) {
                continue;
            }

            for (Course_Checklist_Item_Template__c template : templates) {
                itemsToInsert.add(new Course_Checklist_Item__c(
                    RecordTypeId = checklistItemRtId,
                    Course_Checklist__c = parentChecklist.Id,
                    Course_Checklist_Item_Template__c = template.Id,
                    Subject__c = template.Subject__c,
                    Description__c = template.Description__c,
                    Priority__c = template.Priority__c,
                    Activity_Type__c = template.Activity_Type__c,
                    Course_Type__c = template.Course_Type__c,
                    Role__c = mapTemplateRoleToItemRole(template.Owner_Roles__c),
                    Start_Date__c = template.Start_Date__c,
                    End_Date__c = template.End_Date__c,
                    Reminder_Logic_Calculation__c = template.Reminder_Logic_Calculation__c,
                    Reminder_Reference_Days__c = template.Reminder_Reference_Days__c,
                    Status__c = 'Not Started'
                ));
            }
        }

        if (!itemsToInsert.isEmpty()) {
            insert itemsToInsert;
        }
    }

    private static String mapTemplateRoleToItemRole(String templateRole) {
        return templateRole == 'Associate' ? 'Associate' : 'Student';
    }

    private static Id getRecordTypeId(Schema.SObjectType sObjectType, String developerName) {
        Map<String, Schema.RecordTypeInfo> recordTypeInfoByName = sObjectType.getDescribe().getRecordTypeInfosByDeveloperName();
        if (recordTypeInfoByName == null || !recordTypeInfoByName.containsKey(developerName)) {
            return null;
        }
        return recordTypeInfoByName.get(developerName).getRecordTypeId();
    }
}