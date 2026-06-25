public class ContentDocumentLinkHandler {

    /**
     * BEFORE INSERT
     * Validate Terms and Condition upload requirements
     */
    public static void handleBeforeInsert(List<ContentDocumentLink> newLinks) {
        Set<Id> contentDocIds = new Set<Id>();
        Set<Id> caseIds = new Set<Id>();
        
        // Collect IDs for links related to Cases or set visibility for Student Posts
        for (ContentDocumentLink cdl : newLinks) {
            if (cdl.LinkedEntityId != null) {
                SObjectType linkedType = cdl.LinkedEntityId.getSObjectType();
                if (linkedType == Case.sObjectType) {
                    contentDocIds.add(cdl.ContentDocumentId);
                    caseIds.add(cdl.LinkedEntityId);
                } else if (linkedType == Student_Post__c.sObjectType) {
                    cdl.Visibility = 'AllUsers';
                }
            }
        }

        if (contentDocIds.isEmpty()) return;

        // Query ContentDocuments
        Map<Id, ContentDocument> docMap = new Map<Id, ContentDocument>(
            [SELECT Id, Title, LatestPublishedVersionId 
             FROM ContentDocument 
             WHERE Id IN :contentDocIds]
        );

        // Collect version IDs
        Set<Id> versionIds = new Set<Id>();
        for (ContentDocument doc : docMap.values()) {
            if (doc.LatestPublishedVersionId != null)
                versionIds.add(doc.LatestPublishedVersionId);
        }

        if (versionIds.isEmpty()) return;

        // Query ContentVersions to get uploader info
        Map<Id, ContentVersion> versionMap = new Map<Id, ContentVersion>(
            [SELECT Id, ContentDocumentId, CreatedById 
             FROM ContentVersion 
             WHERE Id IN :versionIds]
        );

        // Collect uploader user IDs
        Set<Id> uploaderIds = new Set<Id>();
        for (ContentVersion cv : versionMap.values()) {
            uploaderIds.add(cv.CreatedById);
        }

        // Query uploader profiles
        Map<Id, User> userMap = new Map<Id, User>(
            [SELECT Id, Profile.Name FROM User WHERE Id IN :uploaderIds]
        );

        // Query related Cases for Due Date validation
        Map<Id, Case> caseMap = new Map<Id, Case>(
            [SELECT Id, Revised_Due_Date__c FROM Case WHERE Id IN :caseIds]
        );

        String requiredFileName = System.Label.TermsAndCondition_FileName;

        // Loop through and validate
        for (ContentDocumentLink cdl : newLinks) {
            if (cdl.LinkedEntityId == null || cdl.LinkedEntityId.getSObjectType() != Case.sObjectType) continue;

            ContentDocument doc = docMap.get(cdl.ContentDocumentId);
            if (doc == null) continue;

            ContentVersion cv = versionMap.get(doc.LatestPublishedVersionId);
            if (cv == null) continue;

            User uploader = userMap.get(cv.CreatedById);
            if (uploader == null) continue;

            // Only Registrar Office uploads are validated
            if (uploader.Profile.Name == 'Registrar Office' && doc.Title == requiredFileName) {
                Case relatedCase = caseMap.get(cdl.LinkedEntityId);
                
                if (relatedCase == null || relatedCase.Revised_Due_Date__c == null) {
                    // 🚫 Block upload and show message
                    cdl.addError('Cannot upload Terms and Condition file. Please set the Due Date on the case before uploading this document.');
                }
            }
        }
    }

    /**
     * AFTER INSERT
     * Update visibility for valid Terms and Condition uploads
     */
   public static void handleAfterInsert(List<ContentDocumentLink> newLinks) {
    Set<Id> contentDocIds = new Set<Id>();
    Set<Id> caseIds = new Set<Id>();

    for (ContentDocumentLink cdl : newLinks) {
        if (cdl.LinkedEntityId != null && cdl.LinkedEntityId.getSObjectType() == Case.sObjectType) {
            contentDocIds.add(cdl.ContentDocumentId);
            caseIds.add(cdl.LinkedEntityId);
        }
    }

    if (contentDocIds.isEmpty()) return;

    // Get current user profile name
    String currentUserProfileName = [
        SELECT Name FROM Profile 
        WHERE Id = :UserInfo.getProfileId()
    ].Name;

    Boolean isCustomerCommunityPlus = currentUserProfileName == 'Customer Community Plus User';

    // Query ContentDocuments
    Map<Id, ContentDocument> docMap = new Map<Id, ContentDocument>(
        [SELECT Id, Title, LatestPublishedVersionId FROM ContentDocument WHERE Id IN :contentDocIds]
    );

    // Query Cases to check current status and TermsCondition field
    Map<Id, Case> caseMap = new Map<Id, Case>(
        [SELECT Id, Status, TermsCondition__c FROM Case WHERE Id IN :caseIds]
    );

    String requiredFileName = System.Label.TermsAndCondition_FileName;

    List<ContentDocumentLink> linksToUpdate = new List<ContentDocumentLink>();
    List<Case> casesToUpdate = new List<Case>();

    // Process each ContentDocumentLink
    for (ContentDocumentLink cdl : newLinks) {
        ContentDocument doc = docMap.get(cdl.ContentDocumentId);
        if (doc == null) continue;

        Case relatedCase = caseMap.get(cdl.LinkedEntityId);
        if (relatedCase == null) continue;

        // Update visibility for Terms & Condition files only
        if (cdl.Visibility != 'AllUsers') {
            linksToUpdate.add(new ContentDocumentLink(
                Id = cdl.Id,
                Visibility = 'AllUsers'
            ));
        }

        // Update Case status logic - Only for Customer Community Plus users
        if (isCustomerCommunityPlus) {
            // Skip if TermsCondition is true AND status is 'T&C Accepted'
            if (relatedCase.TermsCondition__c == true && relatedCase.Status == 'T&C Accepted') {
                continue; // Do nothing for this case
            }

            // Update status to 'Submitted' if it's not already 'Submitted'
            if (relatedCase.Status != 'Submitted' && relatedCase.TermsCondition__c == false) {
                casesToUpdate.add(new Case(
                    Id = relatedCase.Id,
                    Status = 'Submitted'
                ));
            }
        }
    }

    // Perform updates
    if (!linksToUpdate.isEmpty()) {
        update linksToUpdate;
    }

    if (!casesToUpdate.isEmpty()) {
        update casesToUpdate;
    }
}
}