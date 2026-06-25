public without sharing class EnrollmentSessionHandler {
    
    /**
     * Handles the after insert and after update events for Enrollment_Session__c.
     * Assigns 'O-Week Student Tasks' Action Plan when status changes to 'Registered'
     * and Academic Term includes '1' or is 'term 1'.
     */
    public static void handleAfterInsertUpdate(List<Enrollment_Session__c> newList, Map<Id, Enrollment_Session__c> oldMap) {
        System.debug('>>> EnrollmentSessionHandler.handleAfterInsertUpdate started with ' + newList.size() + ' records.');
        Set<Id> sessionIds = new Set<Id>();
        
        for (Enrollment_Session__c es : newList) {
            Boolean isNew = (oldMap == null);
            Boolean isRegistered = (es.Status__c == 'Registered');
            Boolean statusChanged = !isNew && oldMap.get(es.Id).Status__c != es.Status__c;
            Boolean sessionChanged = !isNew && oldMap.get(es.Id).Academic_Session__c != es.Academic_Session__c;
            Boolean enrollmentChanged = !isNew && oldMap.get(es.Id).Program_Enrollment__c != es.Program_Enrollment__c;
            Boolean activeChanged = !isNew && oldMap.get(es.Id).Active__c != es.Active__c;
            
            // Qualify if it's new and registered, or if status changed to registered, 
            // or if it was already registered but the related session/enrollment just got populated (common in automation)
            Boolean shouldProcess = (isNew && isRegistered) || 
                                    (isRegistered && (statusChanged || sessionChanged || enrollmentChanged || activeChanged));
            
            System.debug('Processing ES ID: ' + es.Id + ' | Status: ' + es.Status__c + ' | Should Process: ' + shouldProcess);
            
            if (shouldProcess && es.Program_Enrollment__c != null && es.Academic_Session__c != null) {
                sessionIds.add(es.Id);
            } else if (shouldProcess) {
                System.debug('ES ID ' + es.Id + ' should process but missing lookup: PE=' + es.Program_Enrollment__c + ', AS=' + es.Academic_Session__c);
            }
        }
        
        if (sessionIds.isEmpty()) {
            System.debug('<<< No sessions qualified for status transition. Exiting.');
            return;
        }
        
        System.debug('Sessions to query for formula fields: ' + sessionIds);
        
        // Re-query records to get the formula field value for Academic_Term__c, Academic Session Name, and Session_Start__c
        List<Enrollment_Session__c> sessionsWithFormula = [
            SELECT Id, Program_Enrollment__r.ContactId, Academic_Term__c, Academic_Session__r.Name, Session_Start__c 
            FROM Enrollment_Session__c 
            WHERE Id IN :sessionIds
        ];
        
        List<Enrollment_Session__c> qualifiedSessions = new List<Enrollment_Session__c>();
        for (Enrollment_Session__c es : sessionsWithFormula) {
            String sessionName = es.Academic_Session__r.Name != null ? es.Academic_Session__r.Name.toLowerCase() : '';
            String termName = es.Academic_Term__c != null ? es.Academic_Term__c.toLowerCase() : '';
            
            System.debug('ES ID: ' + es.Id + ' | Session Name: ' + sessionName + ' | Term Name: ' + termName);
            
            if (sessionName.contains('term 1') || sessionName.contains('1') || 
                termName.contains('term 1') || termName.contains('1')) {
                System.debug('ES ID ' + es.Id + ' QUALIFIED for Action Plan creation.');
                qualifiedSessions.add(es);
            } else {
                System.debug('ES ID ' + es.Id + ' REJECTED - Term condition not met.');
            }
        }
        
        if (qualifiedSessions.isEmpty()) {
            System.debug('<<< No sessions met the "Term 1" condition. Exiting.');
            return;
        }
        
        // Find the published version of the 'O-Week Student Tasks' Action Plan Template
        List<ActionPlanTemplateVersion> templates = [
            SELECT Id, Status 
            FROM ActionPlanTemplateVersion 
            WHERE Name = 'O-Week Student Tasks' 
            AND Status = 'Final' 
            ORDER BY Version DESC 
            LIMIT 1
        ];
        
        System.debug('Template query found ' + templates.size() + ' templates.');
        
        if (templates.isEmpty()) {
            System.debug(LoggingLevel.ERROR, '### Error: ActionPlanTemplateVersion "O-Week Student Tasks" with Status "Final" not found.');
            return;
        }
        
        Id templateVersionId = templates[0].Id;
        List<ActionPlan> actionPlansToCreate = new List<ActionPlan>();
        
        for (Enrollment_Session__c es : qualifiedSessions) {
            Id targetContactId = es.Program_Enrollment__r.ContactId;
            
            if (targetContactId == null) {
                System.debug(LoggingLevel.WARN, 'ES ID ' + es.Id + ' has no Program Enrollment Contact ID. Skipping Action Plan.');
                continue;
            }

            ActionPlan newAp = new ActionPlan();
            newAp.Name = 'O-Week Student Tasks';
            newAp.ActionPlanTemplateVersionId = templateVersionId;
            newAp.TargetId = targetContactId;
            newAp.StartDate = es.Session_Start__c != null ? es.Session_Start__c.date() : Date.today();
            newAp.ActionPlanState = 'NotStarted';
            newAp.ActionPlanType = 'Industries';
            actionPlansToCreate.add(newAp);
        }
        
        if (!actionPlansToCreate.isEmpty()) {
            System.debug('Attempting to insert ' + actionPlansToCreate.size() + ' Action Plans.');
            try {
                insert actionPlansToCreate;
                System.debug('Successfully created Action Plans: ' + actionPlansToCreate);
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, '### Error creating Action Plans: ' + e.getMessage() + '\nStack Trace: ' + e.getStackTraceString());
            }
        }
        
        // Create baseline checklists for active enrollment sessions
        handleBaselineChecklistCreation(newList, oldMap);
        
        System.debug('<<< EnrollmentSessionHandler.handleAfterInsertUpdate finished.');
    }
    
    /**
     * @description Handles baseline checklist creation for active enrollment sessions
     * Delegates to ChecklistEngineService for automated baseline checklist generation
     * @param newList List of Enrollment_Session__c records
     * @param oldMap Map of old Enrollment_Session__c records (null on insert)
     */
    public static void handleBaselineChecklistCreation(
        List<Enrollment_Session__c> newList,
        Map<Id, Enrollment_Session__c> oldMap
    ) {
        if (newList == null || newList.isEmpty()) {
            return;
        }
        
        // Filter for enrollment sessions where Active__c is true or became true
        Set<Id> eligibleEnrollmentSessionIds = new Set<Id>();
        
        for (Enrollment_Session__c es : newList) {
            Boolean isInsert = (oldMap == null);
            Enrollment_Session__c oldEs = isInsert ? null : oldMap.get(es.Id);
            
            // Check if Active__c is true and (new record OR just changed to true)
            Boolean isActive = es.Active__c == true;
            Boolean wasInactive = !isInsert && (oldEs.Active__c == false || oldEs.Active__c == null);
            Boolean shouldProcess = isActive && (isInsert || wasInactive);
            
            if (shouldProcess && es.Assigned_Contact__c != null) {
                eligibleEnrollmentSessionIds.add(es.Id);
            }
        }
        
        // Call service to create baseline checklists
        if (!eligibleEnrollmentSessionIds.isEmpty()) {
            ChecklistEngineService.createBaselineChecklists(eligibleEnrollmentSessionIds);
        }
    }
}