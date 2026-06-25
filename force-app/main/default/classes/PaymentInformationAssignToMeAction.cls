public with sharing class PaymentInformationAssignToMeAction {

    public class AssignResult {
        @AuraEnabled public Integer selectedCount;
        @AuraEnabled public Integer updatedCount;
        @AuraEnabled public Integer skippedCount;
        @AuraEnabled public String message;
    }

    public class InvocableRequest {
        @InvocableVariable(required=true)
        public List<Id> recordIds;
    }

    public class InvocableResponse {
        @InvocableVariable
        public Integer selectedCount;
        @InvocableVariable
        public Integer updatedCount;
        @InvocableVariable
        public Integer skippedCount;
        @InvocableVariable
        public String message;
    }

    @AuraEnabled
    public static AssignResult assignToMe(List<Id> recordIds) {
        return processAssignment(recordIds);
    }

    @InvocableMethod(label='Assign Payment Information To Me' description='Assign selected queue-owned Payment Information records to current user')
    public static List<InvocableResponse> assignToMeFromFlow(List<InvocableRequest> requests) {
        List<InvocableResponse> responses = new List<InvocableResponse>();

        if (requests == null || requests.isEmpty()) {
            responses.add(toInvocableResponse(buildResult(0, 0, 0, 'No records provided.')));
            return responses;
        }

        for (InvocableRequest req : requests) {
            AssignResult r = processAssignment(req != null ? req.recordIds : null);
            responses.add(toInvocableResponse(r));
        }

        return responses;
    }

    private static AssignResult processAssignment(List<Id> recordIds) {
        if (recordIds == null || recordIds.isEmpty()) {
            return buildResult(0, 0, 0, 'No records selected.');
        }

        Id currentUserId = UserInfo.getUserId();
        Set<Id> selectedIds = new Set<Id>(recordIds);

        Set<Id> memberQueueIds = new Set<Id>();
        for (GroupMember gm : [
            SELECT GroupId
            FROM GroupMember
            WHERE UserOrGroupId = :currentUserId
        ]) {
            memberQueueIds.add(gm.GroupId);
        }

        if (memberQueueIds.isEmpty()) {
            return buildResult(selectedIds.size(), 0, selectedIds.size(), 'You are not a member of any queue.');
        }

        Set<Id> allowedQueueIds = new Set<Id>();
        for (QueueSobject qs : [
            SELECT QueueId
            FROM QueueSobject
            WHERE SobjectType = 'Payment_Information__c'
              AND QueueId IN :memberQueueIds
        ]) {
            allowedQueueIds.add(qs.QueueId);
        }

        if (allowedQueueIds.isEmpty()) {
            return buildResult(selectedIds.size(), 0, selectedIds.size(), 'You are not a member of a queue that owns Payment Information records.');
        }

        List<Payment_Information__c> toUpdate = new List<Payment_Information__c>();
        Integer skipped = 0;

        for (Payment_Information__c rec : [
            SELECT Id, OwnerId, Status__c, Payment_Status__c
            FROM Payment_Information__c
            WHERE Id IN :selectedIds
            FOR UPDATE
        ]) {
            if (allowedQueueIds.contains(rec.OwnerId)) {
                rec.OwnerId = currentUserId;
                rec.Status__c = 'Finance Processing';
                rec.Payment_Status__c = 'In Progress';
                toUpdate.add(rec);
            } else {
                skipped++;
            }
        }

        if (!toUpdate.isEmpty()) {
            try {
                update toUpdate;
            } catch (DmlException e) {
                return buildResult(
                    selectedIds.size(),
                    0,
                    selectedIds.size(),
                    e.getDmlMessage(0)
                );
            }
        }

        Integer selectedCount = selectedIds.size();
        Integer updatedCount = toUpdate.size();
        Integer skippedCount = selectedCount - updatedCount;

        return buildResult(
            selectedCount,
            updatedCount,
            skippedCount,
            'Assigned ' + updatedCount + ' of ' + selectedCount + ' selected record(s) to you.'
        );
    }

    private static AssignResult buildResult(Integer selectedCount, Integer updatedCount, Integer skippedCount, String message) {
        AssignResult r = new AssignResult();
        r.selectedCount = selectedCount;
        r.updatedCount = updatedCount;
        r.skippedCount = skippedCount;
        r.message = message;
        return r;
    }

    private static InvocableResponse toInvocableResponse(AssignResult source) {
        InvocableResponse r = new InvocableResponse();
        r.selectedCount = source.selectedCount;
        r.updatedCount = source.updatedCount;
        r.skippedCount = source.skippedCount;
        r.message = source.message;
        return r;
    }
}