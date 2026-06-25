/**
 * @description Batch class to create recurring "Meet Primary Advisor" tasks
 *              for students with open Academic_Probation Cases.
 *
 * Business Rules (ISB-4511):
 *   - Creates new task every 14 days for open Academic_Probation Cases
 *   - ONLY creates new task if previous task Status = 'Completed'
 *   - 14-day interval measured from last task CreatedDate
 *   - Task properties match initial task from ProgramEnrollmentHandler
 *
 * Schedule via RecurringProbationTaskBatchScheduler or run ad-hoc:
 *   Database.executeBatch(new RecurringProbationTaskBatch(), 50);
 */
public without sharing class RecurringProbationTaskBatch implements Database.Batchable<SObject> {

    // ─── Constants ────────────────────────────────────────────────────────────
    private static final String CASE_RECORD_TYPE = 'Academic_Probation';
    private static final String TASK_SUBJECT = 'Meet Primary Advisor';
    private static final Integer TASK_INTERVAL_DAYS = 14;

    // ─── Start ────────────────────────────────────────────────────────────────
    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, ContactId, RecordType.DeveloperName
            FROM Case
            WHERE RecordType.DeveloperName = :CASE_RECORD_TYPE
            AND IsClosed = false
        ]);
    }

    // ─── Execute ──────────────────────────────────────────────────────────────
    public void execute(Database.BatchableContext bc, List<Case> scope) {
        if (scope.isEmpty()) {
            return;
        }

        Date today = Date.today();
        Date cutoffDate = today.addDays(-TASK_INTERVAL_DAYS);

        // Step 1: Collect Case IDs and ContactIds for bulk queries
        Set<Id> caseIds = new Set<Id>();
        Set<Id> contactIds = new Set<Id>();
        for (Case c : scope) {
            caseIds.add(c.Id);
            if (c.ContactId != null) {
                contactIds.add(c.ContactId);
            }
        }

        // Step 2: Query most recent Task per Case (bulkified)
        Map<Id, Task> mostRecentTaskByCaseId = new Map<Id, Task>();
        for (Task t : [
            SELECT Id, WhatId, CreatedDate, Status
            FROM Task
            WHERE WhatId IN :caseIds
            AND Subject = :TASK_SUBJECT
            ORDER BY CreatedDate DESC
        ]) {
            // Keep only the most recent task per Case
            if (!mostRecentTaskByCaseId.containsKey(t.WhatId)) {
                mostRecentTaskByCaseId.put(t.WhatId, t);
            }
        }

        // Step 3: Query student Users (bulkified)
        Map<Id, User> studentUserByContactId = new Map<Id, User>();
        for (User u : [
            SELECT Id, ContactId
            FROM User
            WHERE ContactId IN :contactIds
            AND IsActive = true
        ]) {
            studentUserByContactId.put(u.ContactId, u);
        }

        // Step 4: Determine which Cases need new tasks
        List<Task> tasksToInsert = new List<Task>();

        for (Case probationCase : scope) {
            Task mostRecentTask = mostRecentTaskByCaseId.get(probationCase.Id);

            // Skip if no previous task exists (initial task should be created by trigger)
            if (mostRecentTask == null) {
                continue;
            }

            // Check if task is completed AND 14+ days have passed since creation
            if (mostRecentTask.Status != 'Completed') {
                continue;
            }

            if (mostRecentTask.CreatedDate > cutoffDate) {
                continue;
            }

            // Resolve student User
            User studentUser = studentUserByContactId.get(probationCase.ContactId);
            if (studentUser == null) {
                System.debug('⚠️ No active User found for Contact ' + probationCase.ContactId + ' on Case ' + probationCase.Id);
                continue;
            }

            // Create new Task
            Task newTask = new Task();
            newTask.Subject = TASK_SUBJECT;
            newTask.Status = 'Not Started';
            newTask.Priority = 'High';
            newTask.Description = 'Student must meet the primary advisor as part of the academic probation follow-up process.';
            newTask.WhatId = probationCase.Id;
            newTask.WhoId = probationCase.ContactId;
            newTask.OwnerId = studentUser.Id;
            newTask.ActivityDate = today.addDays(TASK_INTERVAL_DAYS);

            tasksToInsert.add(newTask);
        }

        // Step 5: Bulk DML with error handling
        if (!tasksToInsert.isEmpty()) {
            try {
                insert tasksToInsert;
                System.debug('✅ RecurringProbationTaskBatch: Created ' + tasksToInsert.size() + ' recurring advisor tasks');
            } catch (DmlException e) {
                System.debug('❌ RecurringProbationTaskBatch DML Error: ' + e.getMessage());
                for (Integer i = 0; i < e.getNumDml(); i++) {
                    System.debug('❌ Failed record index ' + e.getDmlIndex(i) + ': ' + e.getDmlMessage(i));
                }
            }
        }
    }

    // ─── Finish ───────────────────────────────────────────────────────────────
    public void finish(Database.BatchableContext bc) {
        AsyncApexJob job = [
            SELECT Id, Status, NumberOfErrors, JobItemsProcessed, TotalJobItems
            FROM AsyncApexJob
            WHERE Id = :bc.getJobId()
        ];

        System.debug('✅ RecurringProbationTaskBatch completed: ' +
                     job.Status + ' | Processed: ' + job.JobItemsProcessed +
                     ' | Errors: ' + job.NumberOfErrors);
    }
}