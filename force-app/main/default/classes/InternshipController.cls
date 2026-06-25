public with sharing class InternshipController {

    // ─── Program Enrollment ────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static Id getProgramEnrollmentId() {
        User u = [SELECT ContactId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        if (u.ContactId == null) {
            return null;
        }
        List<ProgramEnrollment> enrollments = [
            SELECT Id
            FROM ProgramEnrollment
            WHERE ContactId = :u.ContactId
            AND IsActive = true
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return enrollments.isEmpty() ? null : enrollments[0].Id;
    }

    // ─── Internship Details ────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<Internship_Details__c> getStudentInternships() {
        User u = [SELECT ContactId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        if (u.ContactId == null) {
            return new List<Internship_Details__c>();
        }
        List<ProgramEnrollment> enrollments = [
            SELECT Id
            FROM ProgramEnrollment
            WHERE ContactId = :u.ContactId
        ];
        if (enrollments.isEmpty()) {
            return new List<Internship_Details__c>();
        }
        Set<Id> enrollmentIds = new Set<Id>();
        for (ProgramEnrollment pe : enrollments) {
            enrollmentIds.add(pe.Id);
        }
        return [
            SELECT Id, Name, Company_Name__c, Designation__c, Start_Date__c,
                   End_Date__c, Job_Location__c, Industry__c, Sub_Industry__c,
                   Job_Function__c, Stipend_Currency__c, Total_Stipend__c,
                   Date_Range__c, Program_Enrollment__c, Read_Only__c
            FROM Internship_Details__c
            WHERE Program_Enrollment__c IN :enrollmentIds
            ORDER BY CreatedDate DESC
        ];
    }

    @AuraEnabled
    public static Id saveInternship(Internship_Details__c record) {
        // On insert, auto-derive Contact__c and Program_Enrollment__c from the running user
        if (record.Id == null) {
            User u = [SELECT ContactId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
            if (u.ContactId != null) {
                record.Contact__c = u.ContactId;
                if (record.Program_Enrollment__c == null) {
                    List<ProgramEnrollment> enrollments = [
                        SELECT Id
                        FROM ProgramEnrollment
                        WHERE ContactId = :u.ContactId
                        AND IsActive = true
                        ORDER BY CreatedDate DESC
                        LIMIT 1
                    ];
                    if (!enrollments.isEmpty()) {
                        record.Program_Enrollment__c = enrollments[0].Id;
                    }
                }
            }
        }
        upsert record;
        return record.Id;
    }

    // ─── Internship Documents ──────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<Internship_Documents__c> getDocuments(Id internshipId) {
        return [
            SELECT Id, Name, Document_Type__c, Document_Title__c, Notes__c,
                   Upload_Date__c, Uploaded_By__c, Internship_Details__c,
                   Program_Enrollment__c, Contact__c
            FROM Internship_Documents__c
            WHERE Internship_Details__c = :internshipId
            ORDER BY Upload_Date__c DESC NULLS LAST, CreatedDate DESC
        ];
    }

    /**
     * Creates an Internship_Documents__c metadata record.
     * Enforces single-upload rule for 'Summer Internship Offer Letter'
     * and 'Internship Completion Certificate'.
     * Returns the new record Id — the caller then attaches the file to this Id
     * via lightning-file-upload.
     */
    @AuraEnabled
    public static Id createDocumentRecord(Internship_Documents__c doc) {
        if (doc.Internship_Details__c == null) {
            throw new AuraHandledException('Internship reference is required.');
        }

        // Single-upload enforcement
        if (doc.Document_Type__c != null && doc.Document_Type__c != 'Other') {
            List<Internship_Documents__c> existing = [
                SELECT Id
                FROM Internship_Documents__c
                WHERE Internship_Details__c = :doc.Internship_Details__c
                  AND Document_Type__c = :doc.Document_Type__c
                LIMIT 1
            ];
            if (!existing.isEmpty()) {
                throw new AuraHandledException(
                    'A "' + doc.Document_Type__c + '" has already been uploaded for this internship. ' +
                    'Only one document of this type is allowed.'
                );
            }
        }

        Internship_Details__c internship = [
            SELECT Program_Enrollment__c, Program_Enrollment__r.ContactId
            FROM Internship_Details__c
            WHERE Id = :doc.Internship_Details__c
            LIMIT 1
        ];

        doc.Program_Enrollment__c = internship.Program_Enrollment__c;
        doc.Contact__c = internship.Program_Enrollment__r != null
            ? internship.Program_Enrollment__r.ContactId
            : null;
        doc.Uploaded_By__c = UserInfo.getUserId();
        doc.Upload_Date__c = Date.today();
        insert doc;
        return doc.Id;
    }

    @AuraEnabled
    public static void deleteInternship(Id internshipId) {
        Internship_Details__c record = [
            SELECT Id FROM Internship_Details__c WHERE Id = :internshipId LIMIT 1
        ];
        delete record;
    }

    /**
     * Deletes an Internship_Documents__c record and its associated ContentDocument.
     */
    @AuraEnabled
    public static void deleteDocument(Id documentRecordId) {
        // Get the ContentDocumentId first
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :documentRecordId
            LIMIT 1
        ];
        
        // Delete the Internship_Documents__c record
        Internship_Documents__c doc = [
            SELECT Id FROM Internship_Documents__c WHERE Id = :documentRecordId LIMIT 1
        ];
        delete doc;
        
        // Delete the associated ContentDocument (this deletes the file)
        if (!links.isEmpty()) {
            ContentDocument cd = [
                SELECT Id FROM ContentDocument WHERE Id = :links[0].ContentDocumentId LIMIT 1
            ];
            delete cd;
        }
    }

    /**
     * Returns true if a document of the given type already exists for the internship.
     * Always returns false for 'Other' since that type allows multiple uploads.
     */
    @AuraEnabled(cacheable=false)
    public static Boolean checkDocumentTypeExists(Id internshipId, String docType) {
        if (String.isBlank(docType) || docType == 'Other') {
            return false;
        }
        return ![
            SELECT Id
            FROM Internship_Documents__c
            WHERE Internship_Details__c = :internshipId
              AND Document_Type__c = :docType
            LIMIT 1
        ].isEmpty();
    }

    /**
     * Gets the ContentDocument ID for a given document record (for file preview).
     * Returns the first attached file's ContentDocument ID, or null if no file attached.
     */
    @AuraEnabled(cacheable=false)
    public static Id getDocumentContentId(Id documentRecordId) {
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :documentRecordId
            ORDER BY ContentDocument.CreatedDate DESC
            LIMIT 1
        ];
        return links.isEmpty() ? null : links[0].ContentDocumentId;
    }

    /**
     * Gets file metadata for preview modal.
     * Returns ContentDocumentId, ContentVersionId, FileExtension, and Title.
     */
    @AuraEnabled(cacheable=false)
    public static Map<String, String> getDocumentPreviewData(Id documentRecordId) {
        List<ContentDocumentLink> links = [
            SELECT ContentDocument.Id, 
                   ContentDocument.LatestPublishedVersionId,
                   ContentDocument.FileExtension,
                   ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :documentRecordId
            ORDER BY ContentDocument.CreatedDate DESC
            LIMIT 1
        ];
        
        if (links.isEmpty()) {
            return null;
        }
        
        ContentDocumentLink link = links[0];
        Map<String, String> result = new Map<String, String>();
        result.put('contentDocumentId', link.ContentDocument.Id);
        result.put('contentVersionId', link.ContentDocument.LatestPublishedVersionId);
        result.put('fileExtension', link.ContentDocument.FileExtension);
        result.put('title', link.ContentDocument.Title);
        
        return result;
    }

    /**
     * Wrapper class for document metadata during creation wizard
     */
    public class DocumentMetadata {
        @AuraEnabled public String documentType { get; set; }
        @AuraEnabled public String documentTitle { get; set; }
        @AuraEnabled public String notes { get; set; }
    }

    /**
     * Wrapper to return both internship ID and document IDs
     */
    public class CreationResult {
        @AuraEnabled public Id internshipId { get; set; }
        @AuraEnabled public List<Id> documentIds { get; set; }
    }

    /**
     * Creates internship with multiple documents in a single transaction.
     * Marks as Read_Only = true immediately.
     * Returns the internship ID and document IDs for file uploads.
     */
    @AuraEnabled
    public static CreationResult createInternshipWithDocuments(
        Internship_Details__c internshipRecord,
        List<DocumentMetadata> documentMetadataList
    ) {
        // Step 1: Derive Contact__c and Program_Enrollment__c from the running user
        User u = [SELECT ContactId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        if (u.ContactId != null) {
            internshipRecord.Contact__c = u.ContactId;
            if (internshipRecord.Program_Enrollment__c == null) {
                List<ProgramEnrollment> enrollments = [
                    SELECT Id
                    FROM ProgramEnrollment
                    WHERE ContactId = :u.ContactId
                    AND IsActive = true
                    ORDER BY CreatedDate DESC
                    LIMIT 1
                ];
                if (!enrollments.isEmpty()) {
                    internshipRecord.Program_Enrollment__c = enrollments[0].Id;
                }
            }
        }

        // Step 2: Create the internship record and mark as Read_Only immediately
        internshipRecord.Read_Only__c = true;
        insert internshipRecord;
        Id internshipId = internshipRecord.Id;

        // Step 3: Create document metadata records (if any)
        List<Id> documentIds = new List<Id>();
        if (documentMetadataList != null && !documentMetadataList.isEmpty()) {
            List<Internship_Documents__c> docsToInsert = new List<Internship_Documents__c>();
            Date today = Date.today();
            Id currentUserId = UserInfo.getUserId();

            for (DocumentMetadata meta : documentMetadataList) {
                Internship_Documents__c doc = new Internship_Documents__c();
                doc.Internship_Details__c = internshipId;
                doc.Program_Enrollment__c = internshipRecord.Program_Enrollment__c;
                doc.Contact__c = internshipRecord.Contact__c;
                doc.Document_Type__c = meta.documentType;
                doc.Document_Title__c = meta.documentTitle;
                doc.Notes__c = meta.notes;
                doc.Upload_Date__c = today;
                doc.Uploaded_By__c = currentUserId;
                docsToInsert.add(doc);
            }

            insert docsToInsert;
            
            for (Internship_Documents__c doc : docsToInsert) {
                documentIds.add(doc.Id);
            }
        }

        CreationResult result = new CreationResult();
        result.internshipId = internshipId;
        result.documentIds = documentIds;
        return result;
    }

    /**
     * Uploads a file to a document record using base64 data
     */
    @AuraEnabled
    public static void uploadFileToDocument(Id documentId, String fileName, String base64Data) {
        ContentVersion cv = new ContentVersion();
        cv.Title = fileName;
        cv.PathOnClient = fileName;
        cv.VersionData = EncodingUtil.base64Decode(base64Data);
        cv.FirstPublishLocationId = documentId;
        insert cv;
    }
}