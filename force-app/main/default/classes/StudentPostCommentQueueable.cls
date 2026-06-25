public class StudentPostCommentQueueable implements Queueable {

    private Set<Id> postIds;

    
    @TestVisible
    public static List<ProcessInstance> testInstances;

    public StudentPostCommentQueueable(Set<Id> postIds) {
        this.postIds = postIds;
    }

    public void execute(QueueableContext context) {

        if (postIds == null || postIds.isEmpty()) {
            return;
        }

        Map<Id, String> postToComment = new Map<Id, String>();

        List<ProcessInstance> instances;

        if (Test.isRunningTest() && testInstances != null) {
            instances = testInstances;
        } else {
            instances = [
                SELECT TargetObjectId, (
                    SELECT Comments 
                    FROM Steps 
                    WHERE Comments != null 
                    ORDER BY CreatedDate DESC 
                    LIMIT 1
                )
                FROM ProcessInstance 
                WHERE TargetObjectId IN :postIds 
                ORDER BY CreatedDate DESC
            ];
        }

        for (ProcessInstance pi : instances) {
            if (!pi.Steps.isEmpty() && !postToComment.containsKey(pi.TargetObjectId)) {
                postToComment.put(pi.TargetObjectId, pi.Steps[0].Comments);
            }
        }

        if (postToComment.isEmpty()) {
            return;
        }

        List<Student_Post__c> postsToUpdate = new List<Student_Post__c>();
        for (Id postId : postToComment.keySet()) {
            postsToUpdate.add(new Student_Post__c(
                Id = postId,
                Reviewer_s_Comments__c = postToComment.get(postId)
            ));
        }

        if (!postsToUpdate.isEmpty()) {
            Database.update(postsToUpdate, false);
        }
    }
}