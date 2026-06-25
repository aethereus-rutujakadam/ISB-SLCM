public with sharing class FilePreviewController {

    @AuraEnabled(cacheable=true)
    public static Id getContentDocumentId(Id contentVersionId) {
        return [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :contentVersionId
            LIMIT 1
        ].ContentDocumentId;
    }
}