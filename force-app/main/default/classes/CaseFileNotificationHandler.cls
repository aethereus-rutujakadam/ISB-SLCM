public class CaseFileNotificationHandler {
    private static final String GENERAL_SUPPORT_RT_DEVELOPER_NAME = 'General_Support';

    public static void handleAfterInsert(List<ContentDocumentLink> newLinks) {
        if (newLinks == null || newLinks.isEmpty()) {
            return;
        }

        Set<Id> caseIds = new Set<Id>();
        for (ContentDocumentLink linkRecord : newLinks) {
            if (linkRecord.LinkedEntityId != null && String.valueOf(linkRecord.LinkedEntityId).startsWith('500')) {
                caseIds.add(linkRecord.LinkedEntityId);
            }
        }

        if (caseIds.isEmpty()) {
            return;
        }

        Map<Id, Case> caseById = new Map<Id, Case>([
            SELECT Id, RecordType.DeveloperName
            FROM Case
            WHERE Id IN :caseIds
        ]);

        List<ContentDocumentLink> generalSupportLinks = new List<ContentDocumentLink>();
        for (ContentDocumentLink linkRecord : newLinks) {
            Case relatedCase = caseById.get(linkRecord.LinkedEntityId);
            if (relatedCase != null
                && relatedCase.RecordType != null
                && relatedCase.RecordType.DeveloperName == GENERAL_SUPPORT_RT_DEVELOPER_NAME) {
                generalSupportLinks.add(linkRecord);
            }
        }

        if (generalSupportLinks.isEmpty()) {
            return;
        }

        AdvisingNotificationService.notifyGeneralSupportAttachmentAdded(generalSupportLinks);
    }
}