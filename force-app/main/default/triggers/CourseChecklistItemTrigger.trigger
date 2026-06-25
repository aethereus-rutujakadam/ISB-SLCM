trigger CourseChecklistItemTrigger on Course_Checklist_Item__c (before update) {
    for (Course_Checklist_Item__c item : Trigger.new) {
        Course_Checklist_Item__c oldItem = Trigger.oldMap.get(item.Id);
        
        // Check if Status changed to "Complete" (or similar completion status)
        // Common status values: 'Not Started', 'In Progress', 'Complete', 'Submitted', 'Completed'
        String newStatus = item.Status__c;
        String oldStatus = oldItem?.Status__c;
        
        // If status is now "Complete" or "Completed" and wasn't before, auto-populate Submission_Date__c
        if ((newStatus == 'Complete' || newStatus == 'Completed' || newStatus == 'Submitted') 
            && (oldStatus == null || (oldStatus != 'Complete' && oldStatus != 'Completed' && oldStatus != 'Submitted'))) {
            
            // Only populate if not already set
            if (item.Submission_Date__c == null) {
                item.Submission_Date__c = System.today();
            }
        }
    }
}