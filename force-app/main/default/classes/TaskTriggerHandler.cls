public without sharing class TaskTriggerHandler {

    /**
     * @description Handle after insert to sync Task Owner with Action Plan Owner
     * for specific Action Plan types: Exam Management Plan, Course Management Plan, Bidding Management Plan.
     */
    public static void afterInsert(List<Task> newTasks) {
        Set<Id> taskIds = new Set<Id>();
        for (Task t : newTasks) {
            taskIds.add(t.Id);
        }

        // ActionPlanItem links Tasks created by Action Plans back to the ActionPlan record.
        List<ActionPlanItem> planItems = [
            SELECT ActionPlanId, ActionPlan.OwnerId, ActionPlan.Action_Plan_Type__c, ItemId 
            FROM ActionPlanItem 
            WHERE ItemId IN :taskIds
        ];

        if (planItems.isEmpty()) {
            return;
        }

        List<Task> tasksToUpdate = new List<Task>();
        Set<String> targetPlanTypes = new Set<String>{
            'Exam Management Plan',
            'Course Management Plan',
            'Bidding Management Plan'
        };

        for (ActionPlanItem item : planItems) {
            if (item.ActionPlanId != null && targetPlanTypes.contains(item.ActionPlan.Action_Plan_Type__c)) {
                tasksToUpdate.add(new Task(
                    Id = item.ItemId,
                    OwnerId = item.ActionPlan.OwnerId
                ));
            }
        }

        if (!tasksToUpdate.isEmpty()) {
            Database.update(tasksToUpdate, false);
        }
    }

    public static void beforeInsert(List<Task> newTasks) {
        // Current logic removed.
    }

    public static void beforeUpdate(List<Task> newList, Map<Id, Task> oldMap) {
        Set<Id> tasksToCheck = new Set<Id>();
        Id currentUserId = UserInfo.getUserId();
        
        // Get all fields for Task to check for changes
        Map<String, Schema.SObjectField> taskFields = Schema.SObjectType.Task.fields.getMap();

        for (Task t : newList) {
            Task oldTask = oldMap.get(t.Id);
            
            // Task creators have full edit permissions on their own tasks - skip all restrictions
            Boolean isCreator = (t.CreatedById == currentUserId);

            // Prevent updates to the Assigned To (OwnerId) field after task creation (applies to everyone)
            if (t.OwnerId != oldTask.OwnerId) {
                t.addError('The Assigned To field cannot be updated after the task is created.');
            }

            // If the current user is not the creator, check if any field other than Status has changed
            if (!isCreator) {
                Boolean restrictedFieldChanged = false;
                for (String fieldName : taskFields.keySet()) {
                    // Skip Status, Description, and system fields that might change
                    Set<String> allowedFields = new Set<String>{
                                'status',
                                'description',
                                'notes__c',
                                'lastmodifieddate',
                                'lastmodifiedbyid'
                            };

                            if (allowedFields.contains(fieldName.toLowerCase())) {
                                continue;
                            }
                    
                    try {
                        if (t.get(fieldName) != oldTask.get(fieldName)) {
                            restrictedFieldChanged = true;
                            break;
                        }
                    } catch (Exception e) {
                        // Some fields might not be accessible or queryable, skip them
                        continue;
                    }
                }

                if (restrictedFieldChanged) {
                    t.addError('You can only update the Status and Description/Comments fields for Tasks you did not create.');
                }
            }

            // Evidence requirement check (applies to everyone including creators)
            if (t.Status == 'Completed' && oldTask.Status != 'Completed' && t.Evidence_Required__c == true) {
                tasksToCheck.add(t.Id);
            }
        }

        if (tasksToCheck.isEmpty()) {
            return;
        }

        Set<Id> taskWithAttachments = new Set<Id>();
        for (Attachment att : [SELECT ParentId FROM Attachment WHERE ParentId IN :tasksToCheck]) {
            taskWithAttachments.add(att.ParentId);
        }

        Set<Id> taskWithFiles = new Set<Id>();
        for (ContentDocumentLink cdl : [SELECT LinkedEntityId FROM ContentDocumentLink WHERE LinkedEntityId IN :tasksToCheck]) {
            taskWithFiles.add(cdl.LinkedEntityId);
        }

        for (Task t : newList) {
            if (tasksToCheck.contains(t.Id)) {
                if (!taskWithAttachments.contains(t.Id) && !taskWithFiles.contains(t.Id)) {
                    t.addError('This task requires evidence. Please upload at least one file before marking it as completed.');
                }
            }
        }
    }

    public static void beforeDelete(List<Task> oldTasks) {
        for (Task t : oldTasks) {
            if (t.CreatedById != UserInfo.getUserId()) {
                t.addError('You can only delete Tasks you created.');
            }
        }
    }
}