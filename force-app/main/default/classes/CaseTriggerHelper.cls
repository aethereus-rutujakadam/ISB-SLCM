public without sharing class CaseTriggerHelper {
    
    // ========== FILTERING METHODS ==========
    
    // Filter for LOA cases that just closed
    public static List<Case> filterClosedLOACases(List<Case> newCases, Map<Id, Case> oldMap) {
        List<Case> loaCases = new List<Case>();
        Set<Id> recordTypeIds = new Set<Id>();

        // First, collect all record type IDs that changed to Closed
        for (Case c : newCases) {
            Case oldC = oldMap.get(c.Id);
            if (c.Status == 'Closed' && oldC.Status != 'Closed' && c.RecordTypeId != null && c.TermsCondition__c != false) {
                recordTypeIds.add(c.RecordTypeId);
            }
        }

        if (recordTypeIds.isEmpty()) {
            return loaCases;
        }

        // Fetch record types
        Map<Id, RecordType> rtMap = new Map<Id, RecordType>(
            [SELECT Id, DeveloperName FROM RecordType WHERE Id IN :recordTypeIds]
        );

        // Filter only LOA record type cases
        for (Case c : newCases) {
            Case oldC = oldMap.get(c.Id);
            
            if (rtMap.containsKey(c.RecordTypeId) &&
                rtMap.get(c.RecordTypeId).DeveloperName == 'LOA' &&
                c.Status == 'Closed' && oldC.Status != 'Closed') {
                
                loaCases.add(c);
            }
        }
        
        System.debug('Filtered ' + loaCases.size() + ' closed LOA cases');
        return loaCases;
    }

    // Filter for Withdrawal cases that just closed
    public static List<Case> filterClosedWithdrawalCases(List<Case> newCases, Map<Id, Case> oldMap) {
        List<Case> withdrawalCases = new List<Case>();
        Set<Id> recordTypeIds = new Set<Id>();

        // First, collect all record type IDs that changed to Closed
        for (Case c : newCases) {
            Case oldC = oldMap.get(c.Id);
            if (c.Status == 'Closed' && oldC.Status != 'Closed' && c.RecordTypeId != null && c.TermsCondition__c != false) {
                recordTypeIds.add(c.RecordTypeId);
            }
        }

        if (recordTypeIds.isEmpty()) {
            return withdrawalCases;
        }

        // Fetch record types
        Map<Id, RecordType> rtMap = new Map<Id, RecordType>(
            [SELECT Id, DeveloperName FROM RecordType WHERE Id IN :recordTypeIds]
        );

        // Filter only Withdrawal record type cases
        for (Case c : newCases) {
            Case oldC = oldMap.get(c.Id);
            
            if (rtMap.containsKey(c.RecordTypeId) &&
                rtMap.get(c.RecordTypeId).DeveloperName == 'Withdrawal' &&
                c.Status == 'Closed' && oldC.Status != 'Closed') {
                
                withdrawalCases.add(c);
            }
        }

        System.debug('Filtered ' + withdrawalCases.size() + ' closed Withdrawal cases');
        return withdrawalCases;
    }

    // Filter for Rejoin cases that just closed
    public static List<Case> filterClosedRejoinCases(List<Case> newCases, Map<Id, Case> oldMap) {
        List<Case> rejoinCases = new List<Case>();
        Set<Id> recordTypeIds = new Set<Id>();

        // First, collect all record type IDs that changed to Closed
        for (Case c : newCases) {
            Case oldC = oldMap.get(c.Id);
            if (c.Status == 'Closed' && oldC.Status != 'Closed' && c.RecordTypeId != null ) {
                recordTypeIds.add(c.RecordTypeId);
            }
        }

        if (recordTypeIds.isEmpty()) {
            return rejoinCases;
        }

        // Fetch record types
        Map<Id, RecordType> rtMap = new Map<Id, RecordType>(
            [SELECT Id, DeveloperName FROM RecordType WHERE Id IN :recordTypeIds]
        );

        // Filter only Rejoin record type cases
        for (Case c : newCases) {
            Case oldC = oldMap.get(c.Id);
            
            if (rtMap.containsKey(c.RecordTypeId) &&
                rtMap.get(c.RecordTypeId).DeveloperName == 'Rejoin' &&
                c.Status == 'Closed' && oldC.Status != 'Closed') {
                
                rejoinCases.add(c);
            }
        }

        System.debug('Filtered ' + rejoinCases.size() + ' closed Rejoin cases');
        return rejoinCases;
    }
        //sid
    // Filter for Rejoin cases that just changed to Payment Successful
    public static List<Case> filterPaymentApprovedRejoinCases(List<Case> newCases, Map<Id, Case> oldMap) {
        List<Case> rejoinCases = new List<Case>();
        Set<Id> recordTypeIds = new Set<Id>();

        // First, collect all record type IDs that changed to Payment Successful
        for (Case c : newCases) {
            Case oldC = oldMap.get(c.Id);
            if (c.Status == 'Payment Successful' && oldC.Status != 'Payment Successful' && c.RecordTypeId != null) {
                recordTypeIds.add(c.RecordTypeId);
            }
        }

        if (recordTypeIds.isEmpty()) {
            return rejoinCases;
        }

        // Fetch record types
        Map<Id, RecordType> rtMap = new Map<Id, RecordType>(
            [SELECT Id, DeveloperName FROM RecordType WHERE Id IN :recordTypeIds]
        );

        // Filter only Rejoin record type cases
        for (Case c : newCases) {
            Case oldC = oldMap.get(c.Id);
            
            if (rtMap.containsKey(c.RecordTypeId) &&
                rtMap.get(c.RecordTypeId).DeveloperName == 'Rejoin' &&
                c.Status == 'Payment Successful' && oldC.Status != 'Payment Successful') {
                
                rejoinCases.add(c);
            }
        }

        System.debug('Filtered ' + rejoinCases.size() + ' Payment Successful Rejoin cases');
        return rejoinCases;
    }
    
    // Filter for Academic Probation cases that just closed
    public static List<Case> filterClosedAcademicProbationCases(List<Case> newCases, Map<Id, Case> oldMap) {
        List<Case> probationCases = new List<Case>();
        
        Id academicProbationRtId = getCaseRecordTypeId('Academic_Probation');
        if (academicProbationRtId == null) {
            System.debug('❌ Academic Probation Record Type not found');
            return probationCases;
        }
        
        for (Case c : newCases) {
            Case oldCase = oldMap.get(c.Id);
            
            if (c.IsClosed && !oldCase.IsClosed && 
                c.RecordTypeId == academicProbationRtId && 
                c.ContactId != null) {
                probationCases.add(c);
            }
        }
        
        System.debug('Filtered ' + probationCases.size() + ' closed Academic Probation cases');
        return probationCases;
    }
    
    /* Sid */
    // Filter for Events and Budget cases that just got Approved
    public static List<Case> filterApprovedEventsAndBudgetCases(List<Case> newCases, Map<Id, Case> oldMap) {
        List<Case> approvedCases = new List<Case>();
        
        Id eventsAndBudgetRtId = getCaseRecordTypeId('Event_Budget_Proposal');
        if (eventsAndBudgetRtId == null) {
            System.debug('❌ Events and Budget Record Type not found');
            return approvedCases;
        }
        
        for (Case c : newCases) {
            Case oldCase = oldMap.get(c.Id);
            if (oldCase == null) continue;
            
            if (c.Status == 'Approved' && oldCase.Status != 'Approved' &&
                c.RecordTypeId == eventsAndBudgetRtId &&
                c.Academic_Term__c != null && c.Budget_Ask__c != null && c.Budget_Ask__c > 0) {
                approvedCases.add(c);
            }
        }
        
        System.debug('Filtered ' + approvedCases.size() + ' approved Event & Budget cases');
        return approvedCases;
    }
    /* SId */
    
    // Helper method to get Record Type ID
    private static Id getCaseRecordTypeId(String developerName) {
        if (String.isBlank(developerName)) return null;
        List<RecordType> rts = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Case' AND DeveloperName = :developerName
            LIMIT 1
        ];
        return rts.isEmpty() ? null : rts[0].Id;
    }
    
    // ========== BUSINESS LOGIC METHODS ==========
    
    /* OLD LOGIC PRESERVED 
    // Process LOA Cases - update enrollment sessions
    public static void processLOACases_Old(List<Case> loaCases) {
        System.debug('=== CaseAssignmentHelper.processLOACases started ===');

        // Step 1: Collect Contacts + Programs
        Set<Id> contactIds = new Set<Id>();
        Set<Id> programIds = new Set<Id>();
        Map<Id, Case> caseProgramMap = new Map<Id, Case>();

        for (Case c : loaCases) {
            if (c.ContactId != null && c.Program__c != null) {
                contactIds.add(c.ContactId);
                programIds.add(c.Program__c);
                caseProgramMap.put(c.Id, c);
            }
        }

        if (contactIds.isEmpty() || programIds.isEmpty()) {
            System.debug('No contacts or programs found.');
            return;
        }

        // Step 2: Contact Name mapping
        Map<Id, Contact> contactMap = new Map<Id, Contact>(
            [SELECT Id, Name FROM Contact WHERE Id IN :contactIds]
        );

        Map<Id, String> contactIdToNameMap = new Map<Id, String>();
        for (Contact con : contactMap.values()) {
            contactIdToNameMap.put(con.Id, con.Name);
        }

        // Step 3: Get all academic sessions for the programs to understand ordering
        Map<Id, List<String>> programTermOrderMap = getProgramTermOrderMap_Old(programIds);
        
        if (programTermOrderMap.isEmpty()) {
            System.debug('No academic sessions found for programs.');
            return;
        }

        // Step 4: Query ALL Enrollment Sessions for these programs
        Map<String, Enrollment_Session__c> enrollmentSessionMap = getEnrollmentSessionMap_Old(programIds, contactIdToNameMap);
        
        System.debug('enrollmentSessionMap size: ' + enrollmentSessionMap.size());

        // Step 5: Update session statuses for ALL terms between fromTerm and toTerm
        List<Enrollment_Session__c> sessionsToUpdate = updateEnrollmentSessionStatus_Old(
            loaCases, programTermOrderMap, enrollmentSessionMap, contactIdToNameMap
        );

        // Step 6: Update
        if (!sessionsToUpdate.isEmpty()) {
            update sessionsToUpdate;
            System.debug('Updated ' + sessionsToUpdate.size() + ' enrollment sessions to LOA status');
        } else {
            System.debug('No sessions to update');
        }

        // Step 7: Update Program Enrollment status to 'On Hold' for registered enrollments
        List<ProgramEnrollment> programEnrollmentsToUpdate = updateProgramEnrollmentStatus(contactIds);
        
        if (!programEnrollmentsToUpdate.isEmpty()) {
            update programEnrollmentsToUpdate;
            System.debug('Updated ' + programEnrollmentsToUpdate.size() + ' program enrollments to On Hold status');
        } else {
            System.debug('No program enrollments to update');
        }

        System.debug('=== CaseAssignmentHelper.processLOACases completed ===');
    }
    OLD LOGIC PRESERVED */

    // Process LOA Cases - update enrollment sessions
    public static void processLOACases(List<Case> loaCases) {
        System.debug('=== CaseAssignmentHelper.processLOACases started ===');

        // Step 1: Collect Contacts
        Set<Id> contactIds = new Set<Id>();

        for (Case c : loaCases) {
            if (c.ContactId != null) {
                contactIds.add(c.ContactId);
            }
        }

        if (contactIds.isEmpty()) {
            System.debug('No contacts found.');
            return;
        }

        // Step 2: Query Enrollment sessions ordered by Academic Term Start Date
        List<Enrollment_Session__c> allSessions = [
            SELECT Id, Status__c, Assigned_Contact__c, Academic_Session__r.Name, 
                   Academic_Session__r.AcademicTerm.StartDate
            FROM Enrollment_Session__c
            WHERE Assigned_Contact__c IN :contactIds
            ORDER BY Assigned_Contact__c, Academic_Session__r.AcademicTerm.StartDate ASC, Academic_Session__r.Name ASC
        ];
        
        System.debug('Found ' + allSessions.size() + ' enrollment sessions for contacts');

        // Step 3: Group sessions by ContactId
        Map<Id, List<Enrollment_Session__c>> contactSessionsMap = new Map<Id, List<Enrollment_Session__c>>();
        for (Enrollment_Session__c es : allSessions) {
            if (!contactSessionsMap.containsKey(es.Assigned_Contact__c)) {
                contactSessionsMap.put(es.Assigned_Contact__c, new List<Enrollment_Session__c>());
            }
            contactSessionsMap.get(es.Assigned_Contact__c).add(es);
        }

        // Step 4: Identify sessions between fromTerm and toTerm
        List<Enrollment_Session__c> sessionsToUpdate = new List<Enrollment_Session__c>();

        for (Case c : loaCases) {
            System.debug('--- Processing LOA Case ---');
            System.debug('Case ID: ' + c.Id);
            System.debug('Case ContactId: ' + c.ContactId);
            System.debug('Case From Term: ' + c.From_Term__c);
            System.debug('Case To Term: ' + c.To_Term__c);

            if (c.ContactId == null || c.From_Term__c == null || c.To_Term__c == null) {
                System.debug('⚠️ Case is missing Contact, From Term, or To Term. Skipping...');
                continue;
            }

            List<Enrollment_Session__c> contactSessions = contactSessionsMap.get(c.ContactId);
            if (contactSessions == null || contactSessions.isEmpty()) {
                System.debug('⚠️ No enrollment sessions found for contact: ' + c.ContactId);
                continue;
            }

            System.debug('✅ Found ' + contactSessions.size() + ' sessions for Contact ' + c.ContactId);

            Integer fromIndex = -1;
            Integer toIndex = -1;

            for (Integer i = 0; i < contactSessions.size(); i++) {
                String sessionName = contactSessions[i].Academic_Session__r.Name;
                System.debug('Session [' + i + ']: ' + sessionName);
                if (sessionName == c.From_Term__c) {
                    fromIndex = i;
                    System.debug('👉 matched From Term at index ' + i);
                }
                if (sessionName == c.To_Term__c) {
                    toIndex = i;
                    System.debug('👉 matched To Term at index ' + i);
                }
            }

            System.debug('Final fromIndex: ' + fromIndex + ', toIndex: ' + toIndex);

            // Ensure valid indices and proper ordering
            if (fromIndex != -1 && toIndex != -1) {
                if (fromIndex > toIndex) {
                    System.debug('ℹ️ Swapping indices...');
                    Integer temp = fromIndex;
                    fromIndex = toIndex;
                    toIndex = temp;
                }

                // Add all sessions in range to update list
                for (Integer i = fromIndex; i <= toIndex; i++) {
                    Enrollment_Session__c es = contactSessions[i];
                    System.debug('Checking session in range: ' + es.Academic_Session__r.Name + ' (Status: ' + es.Status__c + ')');
                    if (es.Status__c != 'LOA') {
                        es.Status__c = 'LOA';
                        sessionsToUpdate.add(es);
                        System.debug('✅ Added to update list');
                    } else {
                        System.debug('ℹ️ Already LOA');
                    }
                }
            } else {
                System.debug('❌ ERROR: Could not find fromTerm or toTerm in sessions for case: ' + c.Id);
            }
        }

        // Step 5: Update Enrollment Sessions
        if (!sessionsToUpdate.isEmpty()) {
            update sessionsToUpdate;
            System.debug('Updated ' + sessionsToUpdate.size() + ' enrollment sessions to LOA status');
        } else {
            System.debug('No sessions to update');
        }

        // Step 6: Update Program Enrollment status to 'On Hold' for registered enrollments
        List<ProgramEnrollment> programEnrollmentsToUpdate = updateProgramEnrollmentStatus(contactIds);
        
        if (!programEnrollmentsToUpdate.isEmpty()) {
            update programEnrollmentsToUpdate;
            System.debug('Updated ' + programEnrollmentsToUpdate.size() + ' program enrollments to On Hold status');
        } else {
            System.debug('No program enrollments to update');
        }

        System.debug('=== CaseAssignmentHelper.processLOACases completed ===');
    }

    // Process Withdrawal Cases - update enrollment sessions to Inactive
    public static void processWithdrawalCases(List<Case> withdrawalCases) {
        System.debug('=== CaseAssignmentHelper.processWithdrawalCases started ===');

        // Step 1: Collect Contacts
        Set<Id> contactIds = new Set<Id>();

        for (Case c : withdrawalCases) {
            if (c.ContactId != null) {
                contactIds.add(c.ContactId);
            }
        }

        if (contactIds.isEmpty()) {
            System.debug('No contacts found.');
            return;
        }

        // Step 2: Query Enrollment sessions ordered by Academic Term Start Date
        List<Enrollment_Session__c> allSessions = [
            SELECT Id, Status__c, Assigned_Contact__c, Academic_Session__r.Name, 
                   Academic_Session__r.AcademicTerm.StartDate
            FROM Enrollment_Session__c
            WHERE Assigned_Contact__c IN :contactIds
            ORDER BY Assigned_Contact__c, Academic_Session__r.AcademicTerm.StartDate ASC, Academic_Session__r.Name ASC
        ];
        
        System.debug('Found ' + allSessions.size() + ' enrollment sessions for contacts');

        // Step 3: Group sessions by ContactId
        Map<Id, List<Enrollment_Session__c>> contactSessionsMap = new Map<Id, List<Enrollment_Session__c>>();
        for (Enrollment_Session__c es : allSessions) {
            if (!contactSessionsMap.containsKey(es.Assigned_Contact__c)) {
                contactSessionsMap.put(es.Assigned_Contact__c, new List<Enrollment_Session__c>());
            }
            contactSessionsMap.get(es.Assigned_Contact__c).add(es);
        }

        // Step 4: Identify sessions between fromTerm and toTerm
        List<Enrollment_Session__c> sessionsToUpdate = new List<Enrollment_Session__c>();

        for (Case c : withdrawalCases) {
            System.debug('--- Processing Withdrawal Case ---');
            System.debug('Case ID: ' + c.Id);
            System.debug('Case ContactId: ' + c.ContactId);
            System.debug('Case From Term: ' + c.From_Term__c);
            System.debug('Case To Term: ' + c.To_Term__c);

            if (c.ContactId == null || c.From_Term__c == null || c.To_Term__c == null) {
                System.debug('⚠️ Case is missing Contact, From Term, or To Term. Skipping...');
                continue;
            }

            List<Enrollment_Session__c> contactSessions = contactSessionsMap.get(c.ContactId);
            if (contactSessions == null || contactSessions.isEmpty()) {
                System.debug('⚠️ No enrollment sessions found for contact: ' + c.ContactId);
                continue;
            }

            System.debug('✅ Found ' + contactSessions.size() + ' sessions for Contact ' + c.ContactId);

            Integer fromIndex = -1;
            Integer toIndex = -1;

            for (Integer i = 0; i < contactSessions.size(); i++) {
                String sessionName = contactSessions[i].Academic_Session__r.Name;
                System.debug('Session [' + i + ']: ' + sessionName);
                if (sessionName == c.From_Term__c) {
                    fromIndex = i;
                    System.debug('👉 matched From Term at index ' + i);
                }
                if (sessionName == c.To_Term__c) {
                    toIndex = i;
                    System.debug('👉 matched To Term at index ' + i);
                }
            }

            System.debug('Final fromIndex: ' + fromIndex + ', toIndex: ' + toIndex);

            // Ensure valid indices and proper ordering
            if (fromIndex != -1 && toIndex != -1) {
                if (fromIndex > toIndex) {
                    System.debug('ℹ️ Swapping indices...');
                    Integer temp = fromIndex;
                    fromIndex = toIndex;
                    toIndex = temp;
                }

                // Add all sessions in range to update list
                for (Integer i = fromIndex; i <= toIndex; i++) {
                    Enrollment_Session__c es = contactSessions[i];
                    System.debug('Checking session in range: ' + es.Academic_Session__r.Name + ' (Status: ' + es.Status__c + ')');
                    if (es.Status__c != 'Inactive') {
                        es.Status__c = 'Inactive';
                        sessionsToUpdate.add(es);
                        System.debug('✅ Added to update list');
                    } else {
                        System.debug('ℹ️ Already Inactive');
                    }
                }
            } else {
                System.debug('❌ ERROR: Could not find fromTerm or toTerm in sessions for case: ' + c.Id);
            }
        }

        // Step 5: Update Enrollment Sessions
        if (!sessionsToUpdate.isEmpty()) {
            update sessionsToUpdate;
            System.debug('Updated ' + sessionsToUpdate.size() + ' enrollment sessions to Inactive status');
        } else {
            System.debug('No sessions to update');
        }

        // Step 6: Update Program Enrollment status to 'Withdrawn' for registered enrollments
        List<ProgramEnrollment> programEnrollmentsToUpdate = updateProgramEnrollmentWithdrawalStatus(contactIds);
        
        if (!programEnrollmentsToUpdate.isEmpty()) {
            update programEnrollmentsToUpdate;
            System.debug('Updated ' + programEnrollmentsToUpdate.size() + ' program enrollments to Withdrawn status');
        } else {
            System.debug('No program enrollments to update');
        }

        System.debug('=== CaseAssignmentHelper.processWithdrawalCases completed ===');
    }

    // Process Rejoin Cases - update ProgramEnrollment Status to 'Rejoined'
    public static void processRejoinCases(List<Case> rejoinCases) {
        System.debug('=== CaseAssignmentHelper.processRejoinCases started ===');

        // Step 1: Collect Contacts
        Set<Id> contactIds = new Set<Id>();

        for (Case c : rejoinCases) {
            if (c.ContactId != null) {
                contactIds.add(c.ContactId);
            }
        }

        if (contactIds.isEmpty()) {
            System.debug('No contacts found.');
            return;
        }

        /* COMMENTED OUT - Enrollment Session status update logic no longer needed for Rejoin closure
        // Step 2: Query Enrollment sessions ordered by Academic Term Start Date
        List<Enrollment_Session__c> allSessions = [
            SELECT Id, Status__c, Assigned_Contact__c, Academic_Session__r.Name, 
                   Academic_Session__r.AcademicTerm.StartDate
            FROM Enrollment_Session__c
            WHERE Assigned_Contact__c IN :contactIds
            ORDER BY Assigned_Contact__c, Academic_Session__r.AcademicTerm.StartDate ASC, Academic_Session__r.Name ASC
        ];
        
        // Step 3: Group sessions by ContactId
        Map<Id, List<Enrollment_Session__c>> contactSessionsMap = new Map<Id, List<Enrollment_Session__c>>();
        for (Enrollment_Session__c es : allSessions) {
            if (!contactSessionsMap.containsKey(es.Assigned_Contact__c)) {
                contactSessionsMap.put(es.Assigned_Contact__c, new List<Enrollment_Session__c>());
            }
            contactSessionsMap.get(es.Assigned_Contact__c).add(es);
        }

        // Step 4: Identify sessions between fromTerm and toTerm and mark as Re-Registered
        List<Enrollment_Session__c> sessionsToUpdate = new List<Enrollment_Session__c>();
        for (Case c : rejoinCases) {
            if (c.ContactId == null || c.From_Term__c == null || c.To_Term__c == null) continue;
            List<Enrollment_Session__c> contactSessions = contactSessionsMap.get(c.ContactId);
            if (contactSessions == null || contactSessions.isEmpty()) continue;
            Integer fromIndex = -1;
            Integer toIndex = -1;
            for (Integer i = 0; i < contactSessions.size(); i++) {
                String sessionName = contactSessions[i].Academic_Session__r.Name;
                if (sessionName == c.From_Term__c) fromIndex = i;
                if (sessionName == c.To_Term__c)   toIndex = i;
            }
            if (fromIndex != -1 && toIndex != -1) {
                if (fromIndex > toIndex) { Integer temp = fromIndex; fromIndex = toIndex; toIndex = temp; }
                for (Integer i = fromIndex; i <= toIndex; i++) {
                    Enrollment_Session__c es = contactSessions[i];
                    if (es.Status__c != 'Re-Registered') {
                        es.Status__c = 'Re-Registered';
                        sessionsToUpdate.add(es);
                    }
                }
            }
        }
        // Step 5: Update Enrollment Sessions
        if (!sessionsToUpdate.isEmpty()) {
            update sessionsToUpdate;
            System.debug('Updated ' + sessionsToUpdate.size() + ' enrollment sessions to Re-Registered status');
        }
        END COMMENTED OUT */

        // Step 2: Update ProgramEnrollment Status to 'Rejoined' for all On Hold enrollments
        List<ProgramEnrollment> programEnrollmentsToUpdate = updateProgramEnrollmentRejoinStatus(contactIds);
        
        if (!programEnrollmentsToUpdate.isEmpty()) {
            update programEnrollmentsToUpdate;
            System.debug('Updated ' + programEnrollmentsToUpdate.size() + ' program enrollments to Rejoined status');
        } else {
            System.debug('No program enrollments to update');
        }

        System.debug('=== CaseAssignmentHelper.processRejoinCases completed ===');
    }

    // Process Rejoin Payment Approved Cases - Create new Enrollment Sessions
    //sid
    public static void processRejoinPaymentApproved(List<Case> rejoinCases) {
        System.debug('=== processRejoinPaymentApproved started ===');

        // Step 1: Re-query cases to get relationship fields (Program__c, Academic_Term__c, ContactId)
        Set<Id> caseIds = new Set<Id>();
        for (Case c : rejoinCases) {
            caseIds.add(c.Id);
        }

        List<Case> casesWithDetails = [
            SELECT Id, ContactId, Program__c, Academic_Term__c, From_Term__c, To_Term__c
            FROM Case
            WHERE Id IN :caseIds
        ];

        // Step 2: Collect Contact IDs, Program IDs, and Academic Term IDs
        Set<Id> contactIds = new Set<Id>();
        Set<Id> academicTermIds = new Set<Id>();
        Set<Id> programIds = new Set<Id>();

        for (Case c : casesWithDetails) {
            if (c.ContactId != null) contactIds.add(c.ContactId);
            if (c.Academic_Term__c != null) academicTermIds.add(c.Academic_Term__c);
            if (c.Program__c != null) programIds.add(c.Program__c);
        }

        if (contactIds.isEmpty() || academicTermIds.isEmpty()) {
            System.debug('No contacts or academic terms found. Exiting.');
            return;
        }

        // Step 3: Get ProgramEnrollment for each contact+program combo
        List<ProgramEnrollment> programEnrollments = [
            SELECT Id, ContactId, ProgramId, Academic_Term__c
            FROM ProgramEnrollment
            WHERE ContactId IN :contactIds
            AND ProgramId IN :programIds
        ];

        // Map: ContactId-ProgramId -> ProgramEnrollment Id
        Map<String, Id> contactProgramToPEMap = new Map<String, Id>();
        for (ProgramEnrollment pe : programEnrollments) {
            String key = pe.ContactId + '-' + pe.ProgramId;
            contactProgramToPEMap.put(key, pe.Id);
        }

        System.debug('Found ' + programEnrollments.size() + ' program enrollments');

        // Step 4: Get Academic Sessions for the rejoin academic terms
        List<AcademicSession> acadSessions = [
            SELECT Id, Name, From_Date__c, To_date__c, AcademicTermId
            FROM AcademicSession
            WHERE AcademicTermId IN :academicTermIds
            ORDER BY AcademicTermId, Name
        ];

        // Group sessions by AcademicTermId
        Map<Id, List<AcademicSession>> termToSessionsMap = new Map<Id, List<AcademicSession>>();
        for (AcademicSession s : acadSessions) {
            if (!termToSessionsMap.containsKey(s.AcademicTermId)) {
                termToSessionsMap.put(s.AcademicTermId, new List<AcademicSession>());
            }
            termToSessionsMap.get(s.AcademicTermId).add(s);
        }

        System.debug('Found ' + acadSessions.size() + ' academic sessions across ' + termToSessionsMap.size() + ' terms');

        // Step 5: Get existing Enrollment Sessions to avoid duplicates
        Set<Id> allPEIds = new Set<Id>(contactProgramToPEMap.values());
        Map<String, Id> existingSessionKeys = new Map<String, Id>();

        if (!allPEIds.isEmpty()) {
            for (Enrollment_Session__c existing : [
                SELECT Id, Program_Enrollment__c, Academic_Session__c
                FROM Enrollment_Session__c
                WHERE Program_Enrollment__c IN :allPEIds
            ]) {
                String key = existing.Program_Enrollment__c + '-' + existing.Academic_Session__c;
                existingSessionKeys.put(key, existing.Id);
            }
        }

        System.debug('Found ' + existingSessionKeys.size() + ' existing enrollment sessions');

        // Step 6: Create new Enrollment Sessions only for From_Term to To_Term range
        List<Enrollment_Session__c> sessionsToInsert = new List<Enrollment_Session__c>();

        for (Case c : casesWithDetails) {
            System.debug('--- Processing Rejoin Payment Successful Case ---');
            System.debug('Case ID: ' + c.Id + ', Contact: ' + c.ContactId + ', Program: ' + c.Program__c + ', Academic Term: ' + c.Academic_Term__c);
            System.debug('From Term: ' + c.From_Term__c + ', To Term: ' + c.To_Term__c);

            if (c.ContactId == null || c.Program__c == null || c.Academic_Term__c == null) {
                System.debug('⚠️ Case is missing Contact, Program, or Academic Term. Skipping...');
                continue;
            }

            if (c.From_Term__c == null || c.To_Term__c == null) {
                System.debug('⚠️ Case is missing From Term or To Term. Skipping...');
                continue;
            }

            // Find the ProgramEnrollment
            String peKey = c.ContactId + '-' + c.Program__c;
            Id peId = contactProgramToPEMap.get(peKey);

            if (peId == null) {
                System.debug('⚠️ No ProgramEnrollment found for Contact-Program: ' + peKey);
                continue;
            }

            // Get Academic Sessions for the rejoin term
            List<AcademicSession> sessions = termToSessionsMap.get(c.Academic_Term__c);
            if (sessions == null || sessions.isEmpty()) {
                System.debug('⚠️ No Academic Sessions found for Academic Term: ' + c.Academic_Term__c);
                continue;
            }

            System.debug('✅ Found ' + sessions.size() + ' sessions for Academic Term ' + c.Academic_Term__c);

            // Find from and to indices by matching session names
            Integer fromIndex = -1;
            Integer toIndex = -1;

            for (Integer i = 0; i < sessions.size(); i++) {
                String sessionName = sessions[i].Name;
                System.debug('Session [' + i + ']: ' + sessionName);
                if (sessionName == c.From_Term__c) {
                    fromIndex = i;
                    System.debug('matched From Term at index ' + i);
                }
                if (sessionName == c.To_Term__c) {
                    toIndex = i;
                    System.debug('matched To Term at index ' + i);
                }
            }

            System.debug('Final fromIndex: ' + fromIndex + ', toIndex: ' + toIndex);

            if (fromIndex == -1 || toIndex == -1) {
                System.debug('Could not find From Term or To Term in sessions. Skipping...');
                continue;
            }

            // Ensure proper ordering
            if (fromIndex > toIndex) {
                System.debug('Swapping indices...');
                Integer temp = fromIndex;
                fromIndex = toIndex;
                toIndex = temp;
            }

            // Create enrollment sessions only for sessions in the from-to range
            for (Integer i = fromIndex; i <= toIndex; i++) {
                AcademicSession sessionRec = sessions[i];

                // Check for duplicates
                String dupKey = peId + '-' + sessionRec.Id;
                if (existingSessionKeys.containsKey(dupKey)) {
                    System.debug('⚠️ Skipping duplicate enrollment session for session: ' + sessionRec.Name);
                    continue;
                }

                Enrollment_Session__c rec = new Enrollment_Session__c();
                rec.Program_Enrollment__c = peId;
                rec.Academic_Session__c = sessionRec.Id;
                rec.Active__c = true;
                rec.Assigned_Contact__c = c.ContactId;
                rec.Session_Start__c = sessionRec.From_Date__c;
                rec.Session_End__c = sessionRec.To_date__c;

                sessionsToInsert.add(rec);
                // Track to avoid intra-batch duplicates
                existingSessionKeys.put(dupKey, null);

                System.debug('✅ Prepared Enrollment Session: PE=' + peId + ', Session=' + sessionRec.Name);
            }
        }

        // Step 7: Insert
        if (!sessionsToInsert.isEmpty()) {
            insert sessionsToInsert;
            System.debug('✅ Inserted ' + sessionsToInsert.size() + ' new Enrollment Sessions');
        } else {
            System.debug('No new Enrollment Sessions to insert');
        }

        System.debug('=== processRejoinPaymentApproved completed ===');
    }
    
    /* Sid */
    // Process Approved Events and Budget Cases — subtract Budget_Ask__c from AcademicTerm.Remaining_Budget__c
    // Rejected cases are not passed here; they have no effect on the budget
    public static void processApprovedBudgetCases(List<Case> approvedCases) {
        System.debug('=== processApprovedBudgetCases started ===');
        
        if (approvedCases.isEmpty()) {
            System.debug('No approved budget cases to process');
            return;
        }
        
        // Sum up budget to subtract per academic term
        Map<Id, Decimal> termBudgetMap = new Map<Id, Decimal>();
        for (Case c : approvedCases) {
            Id termId = c.Academic_Term__c;
            Decimal budget = c.Budget_Ask__c;
            if (!termBudgetMap.containsKey(termId)) termBudgetMap.put(termId, 0);
            termBudgetMap.put(termId, termBudgetMap.get(termId) + budget);
            System.debug('Will subtract ' + budget + ' from term ' + termId);
        }
        
        // Query academic terms
        List<AcademicTerm> terms = [
            SELECT Id, Allocated_Budget__c, Remaining_Budget__c 
            FROM AcademicTerm 
            WHERE Id IN :termBudgetMap.keySet()
        ];
        
        List<AcademicTerm> termsToUpdate = new List<AcademicTerm>();
        for (AcademicTerm term : terms) {
            Decimal currentRemaining = term.Remaining_Budget__c != null 
                ? term.Remaining_Budget__c 
                : (term.Allocated_Budget__c != null ? term.Allocated_Budget__c : 0);
            Decimal subtractAmount = termBudgetMap.get(term.Id);
            term.Remaining_Budget__c = currentRemaining - subtractAmount;
            System.debug('Term ' + term.Id + ': ' + currentRemaining + ' - ' + subtractAmount + ' = ' + term.Remaining_Budget__c);
            termsToUpdate.add(term);
        }
        
        if (!termsToUpdate.isEmpty()) {
            update termsToUpdate;
            System.debug('✅ Updated ' + termsToUpdate.size() + ' academic terms remaining budget');
        }
        
        System.debug('=== processApprovedBudgetCases completed ===');
    }
    /* SId */
    
    // Send Probation Cleared Emails
    public static void sendProbationClearedEmails(List<Case> closedCases) {
        System.debug('📧 Preparing probation cleared emails for ' + closedCases.size() + ' cases');
        
        // Get contacts for the closed cases
        Map<Id, Contact> contactsById = getContactsForCases(closedCases);
        
        if (contactsById.isEmpty()) {
            System.debug('No contacts with email addresses found');
            return;
        }
        
        // Prepare emails
        List<Messaging.SingleEmailMessage> emails = prepareProbationClearedEmails(closedCases, contactsById);
        
        // Send emails
        if (!emails.isEmpty()) {
            sendEmailBatch(emails, 'probation cleared');
        }
    }
    
    // ========== PRIVATE HELPER METHODS ==========
    
    /* OLD LOGIC PRESERVED
    // Get ordered term list for each program
    private static Map<Id, List<String>> getProgramTermOrderMap_Old(Set<Id> programIds) {
        Map<Id, List<String>> programTermOrderMap = new Map<Id, List<String>>();
        
        List<AcademicSession> programSessions = [
            SELECT Id, Name, AcademicTerm.Program__c, AcademicTerm.StartDate
            FROM AcademicSession
            WHERE AcademicTerm.Program__c IN :programIds
            ORDER BY AcademicTerm.StartDate, Name
        ];
        
        for (AcademicSession session : programSessions) {
            if (!programTermOrderMap.containsKey(session.AcademicTerm.Program__c)) {
                programTermOrderMap.put(session.AcademicTerm.Program__c, new List<String>());
            }
            programTermOrderMap.get(session.AcademicTerm.Program__c).add(session.Name);
        }
        
        System.debug('Built term order map for ' + programTermOrderMap.size() + ' programs');
        return programTermOrderMap;
    }
    
    // Get Enrollment Session Map
    // Uses Assigned_Contact__c (real Contact lookup) for direct, reliable matching
    private static Map<String, Enrollment_Session__c> getEnrollmentSessionMap_Old(
        Set<Id> programIds, Map<Id, String> contactIdToNameMap
    ) {
        Map<String, Enrollment_Session__c> enrollmentSessionMap = new Map<String, Enrollment_Session__c>();

        Set<Id> contactIds = contactIdToNameMap.keySet();

        // OLD LOGIC (commented out) - used formula text field Contact__c for name matching (unreliable)
        // List<Enrollment_Session__c> allSessions = [
        //     SELECT Id, Status__c, Contact__c, Academic_Session__r.Name,
        //            Academic_Session__r.AcademicTerm.Program__c
        //     FROM Enrollment_Session__c
        //     WHERE Academic_Session__r.AcademicTerm.Program__c IN :programIds
        // ];
        // for (Enrollment_Session__c es : allSessions) {
        //     Id matchingId = null;
        //     for (Id conId : contactIdToNameMap.keySet()) {
        //         if (contactIdToNameMap.get(conId) == es.Contact__c) {
        //             matchingId = conId;
        //             break;
        //         }
        //     }
        //     if (matchingId != null) {
        //         String key = matchingId + '-' + es.Academic_Session__r.AcademicTerm.Program__c + '-' + es.Academic_Session__r.Name;
        //         enrollmentSessionMap.put(key, es);
        //     }
        // }

        // NEW LOGIC - filter directly on Assigned_Contact__c (real lookup) and programIds
        List<Enrollment_Session__c> allSessions = [
            SELECT Id, Status__c, Assigned_Contact__c,
                   Academic_Session__r.Name,
                   Academic_Session__r.AcademicTerm.Program__c
            FROM Enrollment_Session__c
            WHERE Assigned_Contact__c IN :contactIds
            AND Academic_Session__r.AcademicTerm.Program__c IN :programIds
        ];

        System.debug('Found ' + allSessions.size() + ' enrollment sessions for contacts and programs');

        for (Enrollment_Session__c es : allSessions) {
            if (es.Assigned_Contact__c != null) {
                String key = es.Assigned_Contact__c + '-' +
                             es.Academic_Session__r.AcademicTerm.Program__c + '-' +
                             es.Academic_Session__r.Name;
                enrollmentSessionMap.put(key, es);
            }
        }

        return enrollmentSessionMap;
    }
    
    // Update Enrollment Session Status
    private static List<Enrollment_Session__c> updateEnrollmentSessionStatus_Old(
        List<Case> loaCases, 
        Map<Id, List<String>> programTermOrderMap,
        Map<String, Enrollment_Session__c> enrollmentSessionMap,
        Map<Id, String> contactIdToNameMap
    ) {
        List<Enrollment_Session__c> sessionsToUpdate = new List<Enrollment_Session__c>();

        for (Case c : loaCases) {
            if (c.ContactId == null || c.Program__c == null || c.From_Term__c == null || c.To_Term__c == null) {
                continue;
            }

            // Get ordered term list for this program
            List<String> orderedTerms = programTermOrderMap.get(c.Program__c);
            if (orderedTerms == null || orderedTerms.isEmpty()) {
                System.debug('No ordered terms found for program: ' + c.Program__c);
                continue;
            }

            // Find indices of fromTerm and toTerm
            Integer[] indices = findTermIndices_Old(orderedTerms, c.From_Term__c, c.To_Term__c);
            Integer fromTermIndex = indices[0];
            Integer toTermIndex = indices[1];

            if (fromTermIndex == -1 || toTermIndex == -1) {
                System.debug('Could not find fromTerm or toTerm: ' + c.From_Term__c + ' to ' + c.To_Term__c);
                continue;
            }

            // Mark ALL sessions between fromTerm and toTerm (inclusive) as LOA
            for (Integer i = fromTermIndex; i <= toTermIndex; i++) {
                String termName = orderedTerms[i];
                String key = c.ContactId + '-' + c.Program__c + '-' + termName;
                
                if (enrollmentSessionMap.containsKey(key)) {
                    Enrollment_Session__c es = enrollmentSessionMap.get(key);
                    if (es.Status__c != 'LOA') {
                        es.Status__c = 'LOA';
                        sessionsToUpdate.add(es);
                    }
                }
            }
        }
        
        return sessionsToUpdate;
    }
    
    // Find term indices
    private static Integer[] findTermIndices_Old(List<String> orderedTerms, String fromTerm, String toTerm) {
        Integer fromTermIndex = -1;
        Integer toTermIndex = -1;
        
        for (Integer i = 0; i < orderedTerms.size(); i++) {
            if (orderedTerms[i] == fromTerm) {
                fromTermIndex = i;
            }
            if (orderedTerms[i] == toTerm) {
                toTermIndex = i;
            }
        }
        
        // Ensure fromTermIndex is less than or equal to toTermIndex
        if (fromTermIndex > toTermIndex && fromTermIndex != -1 && toTermIndex != -1) {
            Integer temp = fromTermIndex;
            fromTermIndex = toTermIndex;
            toTermIndex = temp;
        }
        
        return new Integer[]{fromTermIndex, toTermIndex};
    }
    OLD LOGIC PRESERVED */

    // Update Program Enrollment Status when LOA Case closes
    // Sets: Status = 'On Hold', Sub_Status__c = 'Student' (Current Student), Sub_Sub_Status__c = 'Leave of Absence'
    private static List<ProgramEnrollment> updateProgramEnrollmentStatus(Set<Id> contactIds) {
        List<ProgramEnrollment> programEnrollmentsToUpdate = new List<ProgramEnrollment>();
        
        // Query ProgramEnrollments with Status = 'Registered' for the given contactIds
        List<ProgramEnrollment> registeredEnrollments = [
            SELECT Id, Status, Sub_Status__c, Sub_Sub_Status__c, ContactId
            FROM ProgramEnrollment
            WHERE ContactId IN :contactIds
            AND Status = 'Registered'
        ];
        
        System.debug('Found ' + registeredEnrollments.size() + ' registered program enrollments to move to On Hold (LOA)');
        
        for (ProgramEnrollment pe : registeredEnrollments) {
            pe.Status          = 'On Hold';
            pe.Sub_Status__c   = 'Student';          // API value for label "Current Student"
            pe.Sub_Sub_Status__c = 'Leave of Absence'; // API value per Sub_Sub_Status__c picklist
            programEnrollmentsToUpdate.add(pe);
        }
        
        return programEnrollmentsToUpdate;
    }

    // Update Program Enrollment Status to 'Withdrawn'
    private static List<ProgramEnrollment> updateProgramEnrollmentWithdrawalStatus(Set<Id> contactIds) {
        List<ProgramEnrollment> programEnrollmentsToUpdate = new List<ProgramEnrollment>();
        
        // Query ProgramEnrollments with status 'Registered' for the given contactIds
        List<ProgramEnrollment> registeredEnrollments = [
            SELECT Id, Status, ContactId
            FROM ProgramEnrollment
            WHERE ContactId IN :contactIds
            AND Status = 'Registered'
        ];
        
        System.debug('Found ' + registeredEnrollments.size() + ' registered program enrollments for contacts');
        
        // Update status to 'Withdrawn'
        for (ProgramEnrollment pe : registeredEnrollments) {
            pe.Status = 'Withdrawn';
            // You can adjust Sub_Status__c here if needed, keeping it out based on LOA pattern for now or add if necessary
            programEnrollmentsToUpdate.add(pe);
        }
        
        return programEnrollmentsToUpdate;
    }

    // Update Program Enrollment Status to 'Rejoined' for Rejoin Cases
    private static List<ProgramEnrollment> updateProgramEnrollmentRejoinStatus(Set<Id> contactIds) {
        List<ProgramEnrollment> programEnrollmentsToUpdate = new List<ProgramEnrollment>();
        
        // Query ProgramEnrollments currently in On Hold / Leave of Absence state
        // (set by the LOA case closure: Status='On Hold', Sub_Status__c='Student', Sub_Sub_Status__c='Leave of Absence')
        List<ProgramEnrollment> enrollments = [
            SELECT Id, Status, Sub_Status__c, Sub_Sub_Status__c, ContactId
            FROM ProgramEnrollment
            WHERE ContactId IN :contactIds
            AND Status = 'On Hold'
            AND Sub_Sub_Status__c = 'Leave of Absence'
        ];
        
        System.debug('Found ' + enrollments.size() + ' On Hold/Leave of Absence program enrollments to transition to Rejoined');
        
        // Update Status to 'Rejoined' — confirmed picklist value on ProgramEnrollment.Status
        // Sub_Status__c and Sub_Sub_Status__c cleared — Rejoined manages its own sub-statuses
        for (ProgramEnrollment pe : enrollments) {
            pe.Status            = 'Rejoined';
            pe.Sub_Status__c     = null;
            pe.Sub_Sub_Status__c = null;
            programEnrollmentsToUpdate.add(pe);
        }
        
        return programEnrollmentsToUpdate;
    }
    
    // ========== EMAIL HELPER METHODS ==========
    
    // Get contacts for cases
    private static Map<Id, Contact> getContactsForCases(List<Case> cases) {
        Set<Id> contactIds = new Set<Id>();
        for (Case c : cases) {
            if (c.ContactId != null) {
                contactIds.add(c.ContactId);
            }
        }
        
        if (contactIds.isEmpty()) {
            return new Map<Id, Contact>();
        }
        
        return new Map<Id, Contact>([
            SELECT Id, Email, FirstName, LastName, Name 
            FROM Contact 
            WHERE Id IN :contactIds AND Email != null
        ]);
    }
    
    // Prepare probation cleared emails
    private static List<Messaging.SingleEmailMessage> prepareProbationClearedEmails(
        List<Case> closedCases, Map<Id, Contact> contactsById
    ) {
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        
        // Get Org Wide Email Address
        OrgWideEmailAddress[] owea = [SELECT Id, Address FROM OrgWideEmailAddress LIMIT 1];
        
        for (Case closedCase : closedCases) {
            Contact contact = contactsById.get(closedCase.ContactId);
            if (contact == null) continue;
            
            System.debug('📧 Preparing probation cleared email for: ' + contact.Name + ' (' + contact.Email + ')');
            
            Messaging.SingleEmailMessage mail = createProbationClearedEmail(contact, owea);
            emails.add(mail);
        }
        
        return emails;
    }
    
    // Create a single probation cleared email
    private static Messaging.SingleEmailMessage createProbationClearedEmail(
        Contact contact, List<OrgWideEmailAddress> owea
    ) {
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        
        if (!owea.isEmpty()) {
            mail.setOrgWideEmailAddressId(owea[0].Id);
        } else {
            mail.setSenderDisplayName('Academic Affairs Office');
        }
        
        mail.setToAddresses(new String[]{contact.Email});
        mail.setSubject('Congratulations: Academic Probation Cleared');
        
        String studentName = contact.FirstName != null ? contact.FirstName : 'Student';
        String plainTextBody = 'Dear ' + studentName + ',\n\n' +
            'We are pleased to inform you that your Academic Probation case has been successfully resolved and closed.\n\n' +
            'CONGRATULATIONS on improving your academic performance!\n\n' +
            'Your dedication and hard work have paid off. You are no longer on academic probation.\n\n' +
            'KEY POINTS:\n' +
            '• Your academic standing has been restored\n' +
            '• Continue to maintain good academic performance\n' +
            '• Academic support services remain available if needed\n\n' +
            'Keep up the excellent work!\n\n' +
            'Best regards,\n' +
            'Academic Affairs Office';
        
        mail.setPlainTextBody(plainTextBody);
        mail.setSaveAsActivity(true);
        
        return mail;
    }
    
    // Send email batch
    private static void sendEmailBatch(List<Messaging.SingleEmailMessage> emails, String emailType) {
        try {
            System.debug('📧 Attempting to send ' + emails.size() + ' ' + emailType + ' emails');
            List<Messaging.SendEmailResult> results = Messaging.sendEmail(emails);
            
            Integer successCount = 0;
            for(Messaging.SendEmailResult result : results) {
                if(result.isSuccess()) {
                    successCount++;
                    System.debug('✅ ' + emailType + ' email sent successfully');
                } else {
                    System.debug('❌ ' + emailType + ' email failed: ' + result.getErrors()[0].getMessage());
                }
            }
            System.debug('✅ Final result: ' + successCount + '/' + emails.size() + ' ' + emailType + ' emails sent successfully');
        } catch (Exception e) {
            System.debug('❌ Error sending ' + emailType + ' emails: ' + e.getMessage());
        }
    }
}