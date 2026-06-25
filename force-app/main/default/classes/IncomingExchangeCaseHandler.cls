public class IncomingExchangeCaseHandler {
    private static final Id INCOMING_EXCHANGE_RT_ID = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName().containsKey('Incoming_Exchange_Exit_Clearance')
        ? Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName().get('Incoming_Exchange_Exit_Clearance').getRecordTypeId()
        : null;

    // This handler owns incoming exchange clearance stamps, stage auto-transitions, and auto-closure.
    // Closed_Date__c is stamped here because the Incoming_Case_Closure_Flow fires before
    // this trigger and cannot see the Status = Closed set below.
    public static void handleBeforeUpdate(List<Case> newCases, Map<Id, Case> oldMap) {
        if (INCOMING_EXCHANGE_RT_ID == null || newCases == null || newCases.isEmpty() || oldMap == null) {
            return;
        }

        for (Case c : newCases) {
            Case old = oldMap.get(c.Id);

            if (c.RecordTypeId != INCOMING_EXCHANGE_RT_ID) {
                continue;
            }

            stampIncomingDepartmentClearance(c, old);

            // Step 1: Exit Case Initiated → Finance Processing.
            if (c.Status == 'Exit Case Initiated' &&
                c.Operations_Cleared__c == true &&
                c.IT_Cleared__c == true &&
                c.LRC_Cleared__c == true) {
                c.Status = 'Finance Processing';
            }

            // Step 2: Finance Processing → ASA Processing.
            else if (c.Status == 'Finance Processing' && c.Finance_Cleared__c == 'Cleared') {
                c.Status = 'ASA Processing';
            }

            // Step 3: ASA Processing → Grades Awaited.
                else if (c.Status == 'ASA Processing'
                    && c.ASA_SA_Cleared__c == true
                    && old.ASA_SA_Cleared__c == false) {
                c.Status = 'Grades Awaited';
            }

            // Step 4: Grades Awaited → Transcript Processing.
            else if (c.Status == 'Grades Awaited' && c.CGPA__c != null && old.CGPA__c == null) {
                c.Status = 'Transcript Processing';
            }

            // Step 5: Auto-close when Transcript dispatched.
            if (c.Transcript_Dispatched__c == true && old.Transcript_Dispatched__c == false) {
                if (c.Status == 'Transcript Processing' || c.Status == 'Grades Awaited') {
                    c.Status = 'Closed';
                    c.Closed_Date__c = System.now();
                }
            }
        }
    }

    private static void stampIncomingDepartmentClearance(Case c, Case oldCase) {
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
    }

    public static void handleAfterUpdate(List<Case> newCases, Map<Id, Case> oldMap) {
        if (INCOMING_EXCHANGE_RT_ID == null || newCases == null || newCases.isEmpty() || oldMap == null) {
            return;
        }

        Map<Id, ProgramEnrollment> peToUpdate = new Map<Id, ProgramEnrollment>();
        
        for (Case c : newCases) {
            Case oldC = oldMap.get(c.Id);
            
            if (c.RecordTypeId == INCOMING_EXCHANGE_RT_ID && c.Program_Enrollment__c != null && (
                c.Transcript_Dispatched__c != oldC.Transcript_Dispatched__c ||
                c.Dispatch_Date__c != oldC.Dispatch_Date__c ||
                c.Dispatched_By__c != oldC.Dispatched_By__c ||
                c.Partner_Transcript_Received__c != oldC.Partner_Transcript_Received__c ||
                c.Partner_Transcript_Upload_Date__c != oldC.Partner_Transcript_Upload_Date__c ||
                c.Transcript_Notes__c != oldC.Transcript_Notes__c ||
                c.Transcripts_Received__c != oldC.Transcripts_Received__c ||
                c.Tracking_Number__c != oldC.Tracking_Number__c
            )) {
                ProgramEnrollment pe = new ProgramEnrollment(Id = c.Program_Enrollment__c);
                pe.Transcript_Dispatched__c = c.Transcript_Dispatched__c;
                pe.Dispatch_Date__c = c.Dispatch_Date__c;
                pe.Dispatched_By__c = c.Dispatched_By__c;
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
}