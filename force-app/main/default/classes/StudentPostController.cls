public without sharing class StudentPostController {
    public class FileDTO {
        @AuraEnabled public Id ContentDocumentId;
        @AuraEnabled public Id ContentVersionId;
        @AuraEnabled public String Title;
    }

    public class PostDTO {
        @AuraEnabled public Id Id;
        @AuraEnabled public String Title;
        @AuraEnabled public String Body;
        @AuraEnabled public String Status;
        @AuraEnabled public Datetime CreatedDate;
        @AuraEnabled public Datetime PublishedOn;
        @AuraEnabled public String ReviewerComments;
        @AuraEnabled public String CreatedByName;
        @AuraEnabled public List<FileDTO> Files;
    }

    @AuraEnabled(cacheable=true)
    public static List<PostDTO> getPublishedPosts() {
        List<PostDTO> results = new List<PostDTO>();
        try {
            List<Student_Post__c> posts = [
                SELECT Id, Title__c, 
                Post_Body__c, 
                Status__c, CreatedDate, Published_on__c, Reviewer_s_Comments__c, CreatedBy.Name
                FROM Student_Post__c
                WHERE Status__c = 'Published'
                AND (Expiry_Date__c = null OR Expiry_Date__c >= :Date.today())
                ORDER BY Published_on__c DESC, CreatedDate DESC
                LIMIT 50
            ];

            Set<Id> postIds = new Set<Id>();
            for (Student_Post__c p : posts) {
                postIds.add(p.Id);
            }

            Map<Id, List<FileDTO>> postToFiles = new Map<Id, List<FileDTO>>();
            if (!postIds.isEmpty()) {
                for (ContentDocumentLink cdl : [
                    SELECT LinkedEntityId, ContentDocumentId, ContentDocument.Title, ContentDocument.LatestPublishedVersionId 
                    FROM ContentDocumentLink 
                    WHERE LinkedEntityId IN :postIds
                ]) {
                    if (!postToFiles.containsKey(cdl.LinkedEntityId)) {
                        postToFiles.put(cdl.LinkedEntityId, new List<FileDTO>());
                    }
                    FileDTO f = new FileDTO();
                    f.ContentDocumentId = cdl.ContentDocumentId;
                    f.ContentVersionId = cdl.ContentDocument.LatestPublishedVersionId;
                    f.Title = cdl.ContentDocument.Title;
                    postToFiles.get(cdl.LinkedEntityId).add(f);
                }
            }

            for (Student_Post__c p : posts) {
                PostDTO dto = new PostDTO();
                dto.Id = p.Id;
                dto.Title = p.Title__c;
                dto.Body = p.Post_Body__c;
                dto.Status = p.Status__c;
                dto.CreatedDate = p.CreatedDate;
                dto.PublishedOn = p.Published_on__c != null ? p.Published_on__c : p.CreatedDate;
                dto.ReviewerComments = p.Reviewer_s_Comments__c;
                dto.CreatedByName = p.CreatedBy.Name;
                dto.Files = postToFiles.containsKey(p.Id) ? postToFiles.get(p.Id) : new List<FileDTO>();
                results.add(dto);
            }
        } catch (Exception e) {
            System.debug('Error in getPublishedPosts: ' + e.getMessage());
        }
        return results;
    }

    // cacheable=true is intentionally NOT used here.
    // getMyPosts returns user-specific data; Salesforce caches @AuraEnabled(cacheable=true)
    // results by method signature only — not by running user — so every user would receive
    // the same stale result. Removing cacheable ensures a fresh query every time.
    @AuraEnabled
    public static List<PostDTO> getMyPosts() {
        List<PostDTO> results = new List<PostDTO>();
        try {
            Id currentUserId = UserInfo.getUserId();
            // Match on OwnerId OR CreatedById:
            // - CreatedById catches posts created directly by the student.
            // - OwnerId catches posts created via a Flow/automation running as
            //   a system user but owned by (transferred to) the student.
            List<Student_Post__c> posts = [
                SELECT Id, Title__c,
                 Post_Body__c, 
                 Status__c, CreatedDate, Published_on__c, Reviewer_s_Comments__c, CreatedBy.Name
                FROM Student_Post__c
                WHERE CreatedById = :currentUserId
                OR OwnerId = :currentUserId
                ORDER BY CreatedDate DESC
                LIMIT 100
            ];

            Set<Id> postIds = new Set<Id>();
            for (Student_Post__c p : posts) {
                postIds.add(p.Id);
            }

            Map<Id, List<FileDTO>> postToFiles = new Map<Id, List<FileDTO>>();
            if (!postIds.isEmpty()) {
                for (ContentDocumentLink cdl : [
                    SELECT LinkedEntityId, ContentDocumentId, ContentDocument.Title, ContentDocument.LatestPublishedVersionId 
                    FROM ContentDocumentLink 
                    WHERE LinkedEntityId IN :postIds
                ]) {
                    if (!postToFiles.containsKey(cdl.LinkedEntityId)) {
                        postToFiles.put(cdl.LinkedEntityId, new List<FileDTO>());
                    }
                    FileDTO f = new FileDTO();
                    f.ContentDocumentId = cdl.ContentDocumentId;
                    f.ContentVersionId = cdl.ContentDocument.LatestPublishedVersionId;
                    f.Title = cdl.ContentDocument.Title;
                    postToFiles.get(cdl.LinkedEntityId).add(f);
                }
            }

            for (Student_Post__c p : posts) {
                PostDTO dto = new PostDTO();
                dto.Id = p.Id;
                dto.Title = p.Title__c;
                dto.Body = p.Post_Body__c;
                dto.Status = p.Status__c;
                dto.CreatedDate = p.CreatedDate;
                dto.PublishedOn = p.Published_on__c != null ? p.Published_on__c : null;
                dto.ReviewerComments = p.Reviewer_s_Comments__c;
                dto.CreatedByName = p.CreatedBy.Name;
                dto.Files = postToFiles.containsKey(p.Id) ? postToFiles.get(p.Id) : new List<FileDTO>();
                results.add(dto);
            }
        } catch (Exception e) {
            System.debug('Error in getMyPosts: ' + e.getMessage());
            throw new AuraHandledException(e.getMessage());
        }
        return results;
    }
}