public without sharing class WorkshopFileManagerController {
    private static final String ACCESS_REGISTERED_ONLY = 'REGISTERED_ONLY';
    private static final String ACCESS_ALL_ELIGIBLE = 'ALL_ELIGIBLE';
    private static final Set<String> REGISTERED_STATUSES = new Set<String>{'Registered', 'Waitlisted'};

    @TestVisible
    private static Id testStudentContactId;

    public class FileWrapper {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String contentVersionId { get; set; }
        @AuraEnabled public String title { get; set; }
        @AuraEnabled public String fileType { get; set; }
        @AuraEnabled public String fileExtension { get; set; }
        @AuraEnabled public Integer contentSize { get; set; }
        @AuraEnabled public String uploadedBy { get; set; }
        @AuraEnabled public DateTime uploadedDate { get; set; }
        @AuraEnabled public String versionNumber { get; set; }
        @AuraEnabled public Integer versionCount { get; set; }
        @AuraEnabled public Integer downloadCount { get; set; }
        @AuraEnabled public Boolean isLatest { get; set; }
        @AuraEnabled public String accessScope { get; set; }
    }

    public class FileUploadWrapper {
        @AuraEnabled public String fileName { get; set; }
        @AuraEnabled public String base64Data { get; set; }
        @AuraEnabled public Boolean isNewVersion { get; set; }
        @AuraEnabled public String existingDocumentId { get; set; }
        @AuraEnabled public String accessScope { get; set; }
    }

    public class StudentFileResponse {
        @AuraEnabled public List<FileWrapper> files { get; set; }
        @AuraEnabled public Boolean hasRestrictedFiles { get; set; }
    }

    private class StudentAccessContext {
        Id studentContactId;
        Id workshopId;
        Boolean isEligible;
        Boolean isRegistered;
        Id programEnrollmentId;
        String studentPgid;
    }

    @AuraEnabled(cacheable=true)
    public static List<FileWrapper> getWorkshopFiles(Id workshopId) {
        try {
            validateWorkshopAccess(workshopId);
            Set<Id> documentIds = getWorkshopDocumentIds(workshopId);
            if (documentIds.isEmpty()) {
                return new List<FileWrapper>();
            }

            Map<Id, Integer> versionCounts = getVersionCountByDocument(documentIds);
            Map<Id, Integer> downloadCounts = getDownloadCountByDocument(workshopId);
            return getLatestFileWrappers(documentIds, versionCounts, downloadCounts);
        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new AuraHandledException('Error loading workshop files: ' + ex.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String, String> uploadFiles(Id workshopId, List<FileUploadWrapper> files) {
        try {
            validateWorkshopAccess(workshopId);
            if (files == null || files.isEmpty()) {
                throw new AuraHandledException('At least one file is required.');
            }

            List<ContentVersion> versionsToInsert = new List<ContentVersion>();
            List<Boolean> createLinks = new List<Boolean>();
            for (FileUploadWrapper inputFile : files) {
                if (inputFile == null || String.isBlank(inputFile.base64Data) || String.isBlank(inputFile.fileName)) {
                    continue;
                }

                Id existingDocumentId;
                if (inputFile.isNewVersion == true) {
                    existingDocumentId = validateWorkshopDocumentLink(workshopId, inputFile.existingDocumentId);
                }

                ContentVersion versionRecord = new ContentVersion();
                versionRecord.Title = inputFile.fileName;
                versionRecord.PathOnClient = inputFile.fileName;
                versionRecord.VersionData = EncodingUtil.base64Decode(inputFile.base64Data);
                versionRecord.Workshop_File_Access__c = resolveAccessScope(inputFile, existingDocumentId);
                if (existingDocumentId != null) {
                    versionRecord.ContentDocumentId = existingDocumentId;
                }

                versionsToInsert.add(versionRecord);
                createLinks.add(existingDocumentId == null);
            }

            if (versionsToInsert.isEmpty()) {
                throw new AuraHandledException('No valid files were provided.');
            }

            insert versionsToInsert;

            Set<Id> insertedVersionIds = new Set<Id>();
            for (ContentVersion versionRecord : versionsToInsert) {
                insertedVersionIds.add(versionRecord.Id);
            }

            Map<Id, ContentVersion> insertedVersionMap = new Map<Id, ContentVersion>([
                SELECT Id, ContentDocumentId
                FROM ContentVersion
                WHERE Id IN :insertedVersionIds
            ]);

            List<ContentDocumentLink> linksToInsert = new List<ContentDocumentLink>();
            for (Integer indexValue = 0; indexValue < versionsToInsert.size(); indexValue++) {
                if (!createLinks[indexValue]) {
                    continue;
                }

                ContentDocumentLink linkRecord = new ContentDocumentLink();
                linkRecord.ContentDocumentId = insertedVersionMap.get(versionsToInsert[indexValue].Id).ContentDocumentId;
                linkRecord.LinkedEntityId = workshopId;
                linkRecord.ShareType = 'V';
                linkRecord.Visibility = 'AllUsers';
                linksToInsert.add(linkRecord);
            }

            if (!linksToInsert.isEmpty()) {
                insert linksToInsert;
            }

            return new Map<String, String>{
                'success' => 'true',
                'message' => String.valueOf(versionsToInsert.size()) + ' file(s) uploaded successfully.'
            };
        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new AuraHandledException('Error uploading workshop files: ' + ex.getMessage());
        }
    }

    @AuraEnabled
    public static void updateFileAccessScope(Id workshopId, Id contentDocumentId, String accessScope) {
        try {
            validateWorkshopAccess(workshopId);
            Id validDocumentId = validateWorkshopDocumentLink(workshopId, contentDocumentId);
            String normalizedAccess = normalizeAccessScope(accessScope);

            ContentVersion latestVersion = [
                SELECT Id, Workshop_File_Access__c
                FROM ContentVersion
                WHERE ContentDocumentId = :validDocumentId
                AND IsLatest = true
                LIMIT 1
            ];
            latestVersion.Workshop_File_Access__c = normalizedAccess;
            update latestVersion;
        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new AuraHandledException('Error updating access scope: ' + ex.getMessage());
        }
    }

    @AuraEnabled
    public static void deleteFile(Id workshopId, Id contentDocumentId) {
        try {
            validateWorkshopAccess(workshopId);
            Id validDocumentId = validateWorkshopDocumentLink(workshopId, contentDocumentId);
            delete [
                SELECT Id
                FROM ContentDocument
                WHERE Id = :validDocumentId
                LIMIT 1
            ];
        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new AuraHandledException('Error deleting workshop file: ' + ex.getMessage());
        }
    }

    @AuraEnabled
    public static FileWrapper getLatestFileVersion(Id workshopId, Id contentDocumentId) {
        try {
            validateWorkshopAccess(workshopId);
            Id validDocumentId = validateWorkshopDocumentLink(workshopId, contentDocumentId);

            List<ContentVersion> versions = [
                SELECT Id, ContentDocumentId, Title, FileType, FileExtension, ContentSize,
                       CreatedBy.Name, CreatedDate, VersionNumber, IsLatest, Workshop_File_Access__c
                FROM ContentVersion
                WHERE ContentDocumentId = :validDocumentId
                AND IsLatest = true
                LIMIT 1
            ];

            if (versions.isEmpty()) {
                throw new AuraHandledException('File not found.');
            }

            Map<Id, Integer> downloadCounts = getDownloadCountByDocument(workshopId);
            return toFileWrapper(versions[0], versions[0].Id, 1, downloadCounts.get(versions[0].ContentDocumentId));
        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new AuraHandledException('Error loading file version: ' + ex.getMessage());
        }
    }

    @AuraEnabled
    public static List<FileWrapper> getFileVersions(Id workshopId, Id contentDocumentId) {
        try {
            validateWorkshopAccess(workshopId);
            Id validDocumentId = validateWorkshopDocumentLink(workshopId, contentDocumentId);

            List<FileWrapper> versions = new List<FileWrapper>();
            Integer versionCount = 0;
            Integer downloadCount = getDownloadCountByDocument(workshopId).get(validDocumentId);
            for (ContentVersion versionRecord : [
                SELECT Id, ContentDocumentId, Title, FileType, FileExtension, ContentSize,
                       CreatedBy.Name, CreatedDate, VersionNumber, IsLatest, Workshop_File_Access__c
                FROM ContentVersion
                WHERE ContentDocumentId = :validDocumentId
                ORDER BY VersionNumber DESC
            ]) {
                versionCount++;
                versions.add(toFileWrapper(versionRecord, versionRecord.Id, versionCount, downloadCount));
            }

            return versions;
        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new AuraHandledException('Error loading file versions: ' + ex.getMessage());
        }
    }

    @AuraEnabled
    public static String downloadFile(Id workshopId, Id contentVersionId) {
        try {
            validateWorkshopAccess(workshopId);
            ContentVersion versionRecord = [
                SELECT Id, VersionData, ContentDocumentId
                FROM ContentVersion
                WHERE Id = :contentVersionId
                LIMIT 1
            ];
            validateWorkshopDocumentLink(workshopId, versionRecord.ContentDocumentId);

            return EncodingUtil.base64Encode(versionRecord.VersionData);
        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new AuraHandledException('Error downloading workshop file: ' + ex.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static StudentFileResponse getStudentWorkshopFiles(Id workshopId) {
        try {
            StudentAccessContext accessContext = buildStudentAccessContext(workshopId);
            Set<Id> documentIds = getWorkshopDocumentIds(workshopId);
            StudentFileResponse response = new StudentFileResponse();
            response.files = new List<FileWrapper>();
            response.hasRestrictedFiles = false;

            if (documentIds.isEmpty()) {
                return response;
            }

            Map<Id, Integer> versionCounts = getVersionCountByDocument(documentIds);
            Map<Id, Integer> downloadCounts = getDownloadCountByDocument(workshopId);
            List<FileWrapper> latestFiles = getLatestFileWrappers(documentIds, versionCounts, downloadCounts);
            for (FileWrapper fileRecord : latestFiles) {
                if (isAccessAllowed(fileRecord.accessScope, accessContext.isRegistered)) {
                    response.files.add(fileRecord);
                } else {
                    response.hasRestrictedFiles = true;
                }
            }

            return response;
        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new AuraHandledException('Error loading student workshop files: ' + ex.getMessage());
        }
    }

    @AuraEnabled
    public static String downloadWorkshopFile(Id workshopId, Id contentVersionId) {
        StudentAccessContext accessContext = buildStudentAccessContext(workshopId);
        try {
            ContentVersion versionRecord = [
                SELECT Id, ContentDocumentId, VersionData, Workshop_File_Access__c
                FROM ContentVersion
                WHERE Id = :contentVersionId
                LIMIT 1
            ];

            validateWorkshopDocumentLink(workshopId, versionRecord.ContentDocumentId);
            Boolean allowed = isAccessAllowed(versionRecord.Workshop_File_Access__c, accessContext.isRegistered);
            logDownloadAttempt(accessContext, versionRecord.ContentDocumentId, allowed);
            if (!allowed) {
                throw new AuraHandledException('You are not authorized to download this workshop file.');
            }

            return EncodingUtil.base64Encode(versionRecord.VersionData);
        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new AuraHandledException('Error downloading workshop file: ' + ex.getMessage());
        }
    }

    private static Workshop__c validateWorkshopAccess(Id workshopId) {
        if (workshopId == null) {
            throw new AuraHandledException('Workshop ID is required.');
        }

        List<Workshop__c> workshops = [
            SELECT Id, Name
            FROM Workshop__c
            WHERE Id = :workshopId
            LIMIT 1
        ];
        if (workshops.isEmpty()) {
            throw new AuraHandledException('Workshop not found or inaccessible.');
        }

        return workshops[0];
    }

    private static Id validateWorkshopDocumentLink(Id workshopId, Id contentDocumentId) {
        if (contentDocumentId == null) {
            throw new AuraHandledException('Document ID is required.');
        }

        List<ContentDocumentLink> documentLinks = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :workshopId
            AND ContentDocumentId = :contentDocumentId
            LIMIT 1
        ];
        if (documentLinks.isEmpty()) {
            throw new AuraHandledException('The selected file is not linked to this workshop.');
        }

        return contentDocumentId;
    }

    private static Set<Id> getWorkshopDocumentIds(Id workshopId) {
        Set<Id> documentIds = new Set<Id>();
        for (ContentDocumentLink linkRecord : [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :workshopId
        ]) {
            documentIds.add(linkRecord.ContentDocumentId);
        }
        return documentIds;
    }

    private static Map<Id, Integer> getVersionCountByDocument(Set<Id> documentIds) {
        Map<Id, Integer> versionCounts = new Map<Id, Integer>();
        if (documentIds.isEmpty()) {
            return versionCounts;
        }

        for (AggregateResult result : [
            SELECT ContentDocumentId, COUNT(Id) versionCount
            FROM ContentVersion
            WHERE ContentDocumentId IN :documentIds
            GROUP BY ContentDocumentId
        ]) {
            versionCounts.put((Id) result.get('ContentDocumentId'), (Integer) result.get('versionCount'));
        }
        return versionCounts;
    }

    private static Map<Id, Integer> getDownloadCountByDocument(Id workshopId) {
        Map<Id, Integer> downloadCounts = new Map<Id, Integer>();
        for (AggregateResult result : [
            SELECT Content_Document_Id__c documentId, SUM(Download_Count__c) totalCount
            FROM Workshop_File_Log__c
            WHERE Workshop__c = :workshopId
            AND Content_Document_Id__c != null
            GROUP BY Content_Document_Id__c
        ]) {
            downloadCounts.put((Id) result.get('documentId'), Integer.valueOf(String.valueOf(result.get('totalCount'))));
        }
        return downloadCounts;
    }

    private static List<FileWrapper> getLatestFileWrappers(
        Set<Id> documentIds,
        Map<Id, Integer> versionCounts,
        Map<Id, Integer> downloadCounts
    ) {
        List<FileWrapper> files = new List<FileWrapper>();
        for (ContentVersion versionRecord : [
            SELECT Id, ContentDocumentId, Title, FileType, FileExtension, ContentSize,
                   CreatedBy.Name, CreatedDate, VersionNumber, IsLatest, Workshop_File_Access__c
            FROM ContentVersion
            WHERE ContentDocumentId IN :documentIds
            AND IsLatest = true
            ORDER BY CreatedDate DESC
        ]) {
            files.add(
                toFileWrapper(
                    versionRecord,
                    versionRecord.ContentDocumentId,
                    versionCounts.get(versionRecord.ContentDocumentId),
                    downloadCounts.get(versionRecord.ContentDocumentId)
                )
            );
        }
        return files;
    }

    private static String resolveAccessScope(FileUploadWrapper inputFile, Id existingDocumentId) {
        if (!String.isBlank(inputFile.accessScope)) {
            return normalizeAccessScope(inputFile.accessScope);
        }

        if (existingDocumentId != null) {
            List<ContentVersion> latestVersion = [
                SELECT Workshop_File_Access__c
                FROM ContentVersion
                WHERE ContentDocumentId = :existingDocumentId
                AND IsLatest = true
                LIMIT 1
            ];
            if (!latestVersion.isEmpty() && !String.isBlank(latestVersion[0].Workshop_File_Access__c)) {
                return normalizeAccessScope(latestVersion[0].Workshop_File_Access__c);
            }
        }

        return ACCESS_REGISTERED_ONLY;
    }

    private static String normalizeAccessScope(String accessScope) {
        if (accessScope == ACCESS_ALL_ELIGIBLE) {
            return ACCESS_ALL_ELIGIBLE;
        }
        return ACCESS_REGISTERED_ONLY;
    }

    private static FileWrapper toFileWrapper(
        ContentVersion versionRecord,
        Id wrapperId,
        Integer versionCount,
        Integer downloadCount
    ) {
        FileWrapper fileRecord = new FileWrapper();
        fileRecord.id = String.valueOf(wrapperId);
        fileRecord.contentVersionId = String.valueOf(versionRecord.Id);
        fileRecord.title = versionRecord.Title;
        fileRecord.fileType = versionRecord.FileType;
        fileRecord.fileExtension = versionRecord.FileExtension;
        fileRecord.contentSize = versionRecord.ContentSize == null ? 0 : versionRecord.ContentSize;
        fileRecord.uploadedBy = versionRecord.CreatedBy.Name;
        fileRecord.uploadedDate = versionRecord.CreatedDate;
        fileRecord.versionNumber = versionRecord.VersionNumber;
        fileRecord.versionCount = versionCount == null ? 1 : versionCount;
        fileRecord.downloadCount = downloadCount == null ? 0 : downloadCount;
        fileRecord.accessScope = normalizeAccessScope(versionRecord.Workshop_File_Access__c);
        fileRecord.isLatest = versionRecord.IsLatest;
        return fileRecord;
    }

    private static StudentAccessContext buildStudentAccessContext(Id workshopId) {
        StudentAccessContext accessContext = new StudentAccessContext();
        accessContext.studentContactId = getStudentContactId();
        accessContext.workshopId = workshopId;

        List<Workshop__c> workshops = [
            SELECT Id, Status__c, Program__c, Cohort__c, Eligible_Term__c, Campus__c
            FROM Workshop__c
            WHERE Id = :workshopId
            LIMIT 1
        ];
        if (workshops.isEmpty()) {
            throw new AuraHandledException('Workshop is not available for file access.');
        }

        Workshop__c workshopRecord = workshops[0];
        if (workshopRecord.Status__c != 'Published') {
            throw new AuraHandledException('Workshop is not available for file access.');
        }

        accessContext.isRegistered = ![
            SELECT Id
            FROM Workshop_Registration__c
            WHERE Student__c = :accessContext.studentContactId
            AND Workshop__c = :workshopId
            AND Status__c IN :REGISTERED_STATUSES
            LIMIT 1
        ].isEmpty();

        List<Contact> studentContacts = [
            SELECT Id, Primary_Campus__c
            FROM Contact
            WHERE Id = :accessContext.studentContactId
            LIMIT 1
        ];
        if (studentContacts.isEmpty()) {
            throw new AuraHandledException('You are not authorized to access files for this workshop.');
        }

        Contact studentContact = studentContacts[0];
        if (!accessContext.isRegistered && workshopRecord.Campus__c != null && studentContact.Primary_Campus__c != workshopRecord.Campus__c) {
            throw new AuraHandledException('You are not authorized to access files for this workshop.');
        }

        List<Enrollment_Session__c> enrollments = [
            SELECT Program_Enrollment__c, Program_Enrollment__r.PGID__c
            FROM Enrollment_Session__c
            WHERE Program_Enrollment__r.ContactId = :accessContext.studentContactId
            AND Program_Enrollment__r.ProgramId = :workshopRecord.Program__c
            AND Academic_Session__c = :workshopRecord.Eligible_Term__c
            AND Academic_Session__r.AcademicTermId = :workshopRecord.Cohort__c
            AND Status__c = 'Registered'
            LIMIT 1
        ];

        if (!enrollments.isEmpty()) {
            accessContext.isEligible = true;
            accessContext.programEnrollmentId = enrollments[0].Program_Enrollment__c;
            accessContext.studentPgid = enrollments[0].Program_Enrollment__r.PGID__c;
        }

        if (!accessContext.isRegistered && enrollments.isEmpty()) {
            throw new AuraHandledException('You are not authorized to access files for this workshop.');
        }

        if (accessContext.isRegistered && !accessContext.isEligible) {
            accessContext.isEligible = true;
        }

        return accessContext;
    }

    private static Id getStudentContactId() {
        if (Test.isRunningTest() && testStudentContactId != null) {
            return testStudentContactId;
        }

        List<User> currentUsers = [
            SELECT ContactId
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];
        if (currentUsers.isEmpty() || currentUsers[0].ContactId == null) {
            throw new AuraHandledException('No student contact found for the current user.');
        }

        User currentUser = currentUsers[0];
        if (currentUser.ContactId == null) {
            throw new AuraHandledException('No student contact found for the current user.');
        }
        return currentUser.ContactId;
    }

    private static Boolean isAccessAllowed(String accessScope, Boolean isRegistered) {
        String normalizedScope = normalizeAccessScope(accessScope);
        if (isRegistered) {
            return true;
        }
        return normalizedScope == ACCESS_ALL_ELIGIBLE;
    }

    private static void logDownloadAttempt(StudentAccessContext accessContext, Id contentDocumentId, Boolean allowed) {
        String uniqueKey = String.valueOf(accessContext.studentContactId)
            + '|' + String.valueOf(accessContext.workshopId)
            + '|' + String.valueOf(contentDocumentId);

        List<Workshop_File_Log__c> existingLogs = [
            SELECT Id, Download_Count__c
            FROM Workshop_File_Log__c
            WHERE Unique_Key__c = :uniqueKey
            LIMIT 1
            FOR UPDATE
        ];

        Workshop_File_Log__c logRecord = existingLogs.isEmpty() ? new Workshop_File_Log__c() : existingLogs[0];
        logRecord.Unique_Key__c = uniqueKey;
        logRecord.Student__c = accessContext.studentContactId;
        logRecord.Student_PGID__c = accessContext.studentPgid;
        logRecord.Program_Enrollment__c = accessContext.programEnrollmentId;
        logRecord.Workshop__c = accessContext.workshopId;
        logRecord.Content_Document_Id__c = String.valueOf(contentDocumentId);
        logRecord.Access_Outcome__c = allowed ? 'Allowed' : 'Denied';
        logRecord.Last_Downloaded_At__c = System.now();
        if (allowed) {
            Integer currentCount = logRecord.Download_Count__c == null ? 0 : Integer.valueOf(logRecord.Download_Count__c);
            logRecord.Download_Count__c = currentCount + 1;
        } else if (logRecord.Download_Count__c == null) {
            logRecord.Download_Count__c = 0;
        }

        upsert logRecord Unique_Key__c;
    }
}