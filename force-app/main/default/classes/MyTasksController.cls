// MyTasksController.cls
public with sharing class MyTasksController {

    @AuraEnabled(cacheable=true)
    public static List<Task> getTasksForUser() {
        System.debug('=== getTasksForUser START ===');
        System.debug('Current UserId: ' + UserInfo.getUserId());
        System.debug('Current Username: ' + UserInfo.getUserName());
        
        try {
            List<Task> tasks = [
                SELECT Id, Subject, Status, Priority, ActivityDate, ReminderDateTime, 
                       Description, Evidence_Required__c
                FROM Task
                WHERE OwnerId = :UserInfo.getUserId()
                ORDER BY ActivityDate ASC
            ];
            
            System.debug('Number of tasks found: ' + tasks.size());
            for(Task t : tasks) {
                System.debug('Task ID: ' + t.Id + ', Subject: ' + t.Subject + ', Status: ' + t.Status);
            }
            
            System.debug('=== getTasksForUser END ===');
            return tasks;
            
        } catch(Exception e) {
            System.debug('ERROR in getTasksForUser: ' + e.getMessage());
            System.debug('Stack Trace: ' + e.getStackTraceString());
            throw new AuraHandledException('Error fetching tasks: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void completeTask(Id taskId, String comment, Boolean markCompleted) {
        System.debug('=== completeTask START ===');
        System.debug('TaskId: ' + taskId);
        System.debug('Comment: ' + comment);
        System.debug('Mark Completed: ' + markCompleted);
        
        try {
            Task t = [SELECT Id, Description, Status FROM Task WHERE Id = :taskId LIMIT 1];
            System.debug('Task found - Current Status: ' + t.Status);
            System.debug('Task found - Current Description: ' + t.Description);

            // Append comment with timestamp
            String timestamp = Datetime.now().format('yyyy-MM-dd HH:mm');
            String newComment = (t.Description != null ? t.Description + '\n' : '') 
                + timestamp + ': ' + comment;

            System.debug('New Description to be saved: ' + newComment);
            t.Description = newComment;

            // If requested, mark task completed
            if(markCompleted) {
                t.Status = 'Completed';
                System.debug('Marking task as Completed');
            }

            update t;
            System.debug('Task updated successfully');
            System.debug('=== completeTask END ===');
            
        } catch(Exception e) {
            System.debug('ERROR in completeTask: ' + e.getMessage());
            System.debug('Stack Trace: ' + e.getStackTraceString());
            throw new AuraHandledException('Error completing task: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Id uploadAttachment(Id taskId, String fileName, String base64Data) {
        System.debug('=== uploadAttachment START ===');
        System.debug('TaskId: ' + taskId);
        System.debug('FileName: ' + fileName);
        System.debug('Base64 Data Length: ' + (base64Data != null ? base64Data.length() : 0));
        
        try {
            Attachment att = new Attachment();
            att.ParentId = taskId;
            att.Name = fileName;
            att.Body = EncodingUtil.base64Decode(base64Data);
            
            System.debug('Attachment size in bytes: ' + att.Body.size());
            
            insert att;
            
            System.debug('Attachment created with ID: ' + att.Id);
            System.debug('=== uploadAttachment END ===');
            
            return att.Id;
            
        } catch(Exception e) {
            System.debug('ERROR in uploadAttachment: ' + e.getMessage());
            System.debug('Stack Trace: ' + e.getStackTraceString());
            throw new AuraHandledException('Error uploading attachment: ' + e.getMessage());
        }
    }
}