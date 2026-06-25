public without sharing class StudentPostTriggerHandler {
    
    /**
     * @description Handle after update to capture approval comments.
     * We use a Queueable job to ensure the ProcessInstanceStep has been committed.
     */
    public static void afterUpdate(List<Student_Post__c> newList, Map<Id, Student_Post__c> oldMap) {
        Set<Id> postsToProcess = new Set<Id>();
        
        for (Student_Post__c post : newList) {
            Student_Post__c oldPost = oldMap.get(post.Id);
            
            // Check if status changed to a terminal state (Approved/Rejected)
            // Adjust these values to match your picklist API names if they differ
            Boolean statusChanged = post.Status__c != oldPost.Status__c;
            
            // Checking for common approval status values
            Boolean isTerminalStatus = (
                post.Status__c == 'Approved' || 
                post.Status__c == 'Rejected' || 
                post.Status__c == 'Published' ||
                post.Status__c == 'Archived'
            );
            
            if (statusChanged && isTerminalStatus) {
                postsToProcess.add(post.Id);
            }
        }
        
        if (!postsToProcess.isEmpty()) {
            // Check if already in an async context to avoid nested queueable errors if called from elsewhere
            if (!System.isQueueable() && !System.isFuture()) {
                System.enqueueJob(new StudentPostCommentQueueable(postsToProcess));
            }
        }
    }
}