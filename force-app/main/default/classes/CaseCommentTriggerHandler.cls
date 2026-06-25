public class CaseCommentTriggerHandler {
    private static final String GENERAL_SUPPORT_RT_DEVELOPER_NAME = 'General_Support';
    
    public static void handleAfterInsert(List<CaseComment> newComments) {
        // Filter valid comments
        List<CaseComment> validComments = new List<CaseComment>();
        Set<Id> caseIds = new Set<Id>();
        
        for (CaseComment comment : newComments) {
            if (comment.ParentId != null) {
                validComments.add(comment);
                caseIds.add(comment.ParentId);
            }
        }
        
        if (validComments.isEmpty()) return;
        
        try {
            Map<Id, Case> caseById = new Map<Id, Case>([
                SELECT Id, RecordType.DeveloperName
                FROM Case
                WHERE Id IN :caseIds
            ]);

            List<CaseComment> generalSupportComments = new List<CaseComment>();
            List<CaseComment> otherComments = new List<CaseComment>();
            Set<Id> otherCaseIds = new Set<Id>();

            for (CaseComment comment : validComments) {
                Case relatedCase = caseById.get(comment.ParentId);
                if (relatedCase != null
                    && relatedCase.RecordType != null
                    && relatedCase.RecordType.DeveloperName == GENERAL_SUPPORT_RT_DEVELOPER_NAME) {
                    generalSupportComments.add(comment);
                } else {
                    otherComments.add(comment);
                    otherCaseIds.add(comment.ParentId);
                }
            }

            if (!otherComments.isEmpty()) {
                CaseCommentTriggerHelper.processNotifications(otherComments, otherCaseIds);
            }

            if (!generalSupportComments.isEmpty()) {
                AdvisingNotificationService.notifyGeneralSupportCaseComments(generalSupportComments);
            }
        } catch (Exception e) {
            System.debug('Error in CaseCommentNotificationHandler: ' + e.getMessage() + 
                        ' Stack Trace: ' + e.getStackTraceString());
            // Consider logging this to a custom object or sending an email alert
        }
    }

}