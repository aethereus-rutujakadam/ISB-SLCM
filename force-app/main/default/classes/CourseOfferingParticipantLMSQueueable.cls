public without sharing class CourseOfferingParticipantLMSQueueable implements Queueable, Database.AllowsCallouts {
    
    private List<CourseOfferingParticipantLMSService.COPContext> contexts;
    private Boolean isDelete;

    public CourseOfferingParticipantLMSQueueable(List<CourseOfferingParticipantLMSService.COPContext> ctxs, Boolean isDelete) {
        this.contexts = ctxs;
        this.isDelete = isDelete;
    }

    public void execute(QueueableContext context) {
        if (contexts == null || contexts.isEmpty()) return;
        CourseOfferingParticipantLMSService.processQueueableSync(contexts, isDelete);
    }
}