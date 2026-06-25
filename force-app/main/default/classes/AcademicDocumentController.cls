public with sharing class AcademicDocumentController {
    
    // Wrapper for file data
    public class FileWrapper {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String title { get; set; }
        @AuraEnabled public String fileType { get; set; }
        @AuraEnabled public String fileExtension { get; set; }
        @AuraEnabled public Integer contentSize { get; set; }
        @AuraEnabled public String uploadedBy { get; set; }
        @AuraEnabled public DateTime uploadedDate { get; set; }
        @AuraEnabled public String versionNumber { get; set; }
        @AuraEnabled public Integer versionCount { get; set; }
        @AuraEnabled public Boolean isLatest { get; set; }
        @AuraEnabled public String documentType { get; set; }
    }
    
    // Wrapper for user permissions and AA Profile info
    public class UserPermissions {
        @AuraEnabled public Boolean canUpload { get; set; }
        @AuraEnabled public Boolean canView { get; set; }
        @AuraEnabled public Boolean canViewVersions { get; set; }
        @AuraEnabled public String userRole { get; set; }
        @AuraEnabled public String contactId { get; set; }
        @AuraEnabled public Boolean isContactActive { get; set; }
        @AuraEnabled public String contactName { get; set; }
        @AuraEnabled public String aaProfileId { get; set; }
    }
    
    // Wrapper for AA Profile info
    public class AAProfileInfo {
        @AuraEnabled public String aaProfileId { get; set; }
        @AuraEnabled public String aaProfileName { get; set; }
        @AuraEnabled public String contactId { get; set; }
        @AuraEnabled public String contactName { get; set; }
        @AuraEnabled public Boolean isContactActive { get; set; }
        @AuraEnabled public String activeStatus { get; set; }
    }
    
    // Wrapper for file upload
    public class FileUploadWrapper {
        @AuraEnabled public String fileName { get; set; }
        @AuraEnabled public String base64Data { get; set; }
        @AuraEnabled public String contentType { get; set; }
        @AuraEnabled public Boolean isNewVersion { get; set; }
        @AuraEnabled public String existingDocumentId { get; set; }
        @AuraEnabled public String documentType { get; set; }
    }
    
    /**
     * Get current user's permissions
     */
    @AuraEnabled
    public static UserPermissions getUserPermissions() {
        try {
            UserPermissions permissions = new UserPermissions();
            User currentUser = [
                SELECT Id, Profile.Name, ContactId, 
                    Contact.Name, Contact.Active_Status__c 
                FROM User 
                WHERE Id = :UserInfo.getUserId() 
                LIMIT 1
            ];
            
            String profileName = currentUser.Profile.Name != null ? currentUser.Profile.Name.toLowerCase() : '';
            System.debug('⚙️ Current User: ' + currentUser.Id + ' | Profile: ' + profileName);

            // Determine role context
            Boolean isAdmin = profileName.contains('system administrator');
            Boolean isSeniorManager = profileName.contains('asa');
            Boolean isAcademicAssociate = false;
            Contact aaContact;

            // Try to resolve AA Contact using Linked_User_Id__c linkage
            try {
                aaContact = [
                    SELECT Id, Name, Active_Status__c 
                    FROM Contact 
                    WHERE Linked_User_Id__c = :currentUser.Id
                    LIMIT 1
                ];
                if (aaContact != null) {
                    isAcademicAssociate = true;
                    System.debug('🎓 Found linked AA Contact: ' + aaContact.Id);
                }
            } catch (Exception ex) {
                System.debug('⚠️ No linked AA Contact found: ' + ex.getMessage());
            }

            // Assign role and permissions
            permissions.userRole = 
                isAdmin ? 'System Administrator' :
                isSeniorManager ? 'Senior Manager' :
                isAcademicAssociate ? 'Academic Associate' :
                'Other';

            // Access logic per role
            if (isAdmin) {
                permissions.canUpload = true;
                permissions.canView = true;
                permissions.canViewVersions = true;
            } else if (isSeniorManager) {
                permissions.canUpload = true;
                permissions.canView = true;
                permissions.canViewVersions = true;
            } else if (isAcademicAssociate) {
                permissions.canUpload = false;
                permissions.canViewVersions = false; // read-only; can’t view prior versions
                permissions.contactId = aaContact.Id;
                permissions.contactName = aaContact.Name;
                permissions.isContactActive = aaContact.Active_Status__c == 'Active';
                permissions.canView = permissions.isContactActive;
            } else {
                permissions.canUpload = false;
                permissions.canView = false;
                permissions.canViewVersions = false;
            }

            System.debug('🧩 User Role: ' + permissions.userRole + 
                        ' | canUpload=' + permissions.canUpload + 
                        ' | canView=' + permissions.canView +
                        ' | isContactActive=' + permissions.isContactActive);

            return permissions;

        } catch (Exception e) {
            System.debug('❌ Error in getUserPermissions: ' + e.getMessage());
            throw new AuraHandledException('Error getting user permissions: ' + e.getMessage());
        }
    }
    
    /**
     * Get AA Profile information including related Contact
     * Replace 'AA_Profile__c' and 'AA_Contact__c' with your actual API names
     */
    @AuraEnabled
    public static AAProfileInfo getAAProfileInfo(String aaProfileId) {
        try {
            AAProfileInfo profileInfo = new AAProfileInfo();

            if (String.isBlank(aaProfileId)) {
                System.debug('⚠️ No aaProfileId provided - attempting to derive from user context');
                
                User currentUser = [
                    SELECT Id FROM User WHERE Id = :UserInfo.getUserId()
                ];
                
                List<Contact> aaContacts = [
                    SELECT Id FROM Contact WHERE Linked_User_Id__c = :currentUser.Id LIMIT 1
                ];
                
                if (aaContacts.isEmpty()) {
                    System.debug('❌ No AA Contact found for current user');
                    throw new AuraHandledException('No AA Contact found for current user. Please contact your administrator.');
                }
                
                List<AA_Profile__c> activeProfiles = [
                    SELECT Id, Name, Academic_Associate__c, Academic_Associate__r.Name, Academic_Associate__r.Active_Status__c
                    FROM AA_Profile__c
                    WHERE Academic_Associate__c = :aaContacts[0].Id
                    ORDER BY CreatedDate DESC
                    LIMIT 1
                ];
                
                if (activeProfiles.isEmpty()) {
                    System.debug('❌ No AA Profile found for contact');
                    throw new AuraHandledException('No AA Profile found. Please contact your administrator.');
                }
                
                aaProfileId = activeProfiles[0].Id;
                System.debug('✅ Derived AA Profile from workspace tab context: ' + aaProfileId);
            }

            AA_Profile__c aaProfile = [
                SELECT Id, Name, Academic_Associate__c, Academic_Associate__r.Name, Academic_Associate__r.Active_Status__c
                FROM AA_Profile__c
                WHERE Id = :aaProfileId
                LIMIT 1
            ];

            profileInfo.aaProfileId = aaProfile.Id;
            profileInfo.aaProfileName = aaProfile.Name;
            profileInfo.contactId = aaProfile.Academic_Associate__c;
            profileInfo.contactName = aaProfile.Academic_Associate__r.Name;
            profileInfo.activeStatus = aaProfile.Academic_Associate__r.Active_Status__c;
            profileInfo.isContactActive = aaProfile.Academic_Associate__r.Active_Status__c == 'Active';
            
            System.debug('📊 AA Profile Info - Name: ' + profileInfo.aaProfileName + ' | Contact Active: ' + profileInfo.isContactActive);

            return profileInfo;
        } catch (Exception e) {
            System.debug('❌ Error in getAAProfileInfo: ' + e.getMessage() + ' | Stack: ' + e.getStackTraceString());
            throw new AuraHandledException('Error getting AA Profile info: ' + e.getMessage());
        }
    }

    
    /**
     * Upload files to AA Profile
     */
    @AuraEnabled
    public static Map<String, String> uploadFiles(String aaProfileId, List<FileUploadWrapper> files) {
        try {
            if (String.isBlank(aaProfileId) || files == null || files.isEmpty()) {
                throw new AuraHandledException('Invalid parameters');
            }
            
            // Verify user has upload permission
            UserPermissions permissions = getUserPermissions();
            if (!permissions.canUpload) {
                throw new AuraHandledException('You do not have permission to upload files');
            }
            
            // Verify AA Profile exists and contact is active
            AAProfileInfo profileInfo = getAAProfileInfo(aaProfileId);
            if (!profileInfo.isContactActive) {
                throw new AuraHandledException('Cannot upload files. AA Contact is not active (Status: ' + profileInfo.activeStatus + ')');
            }
            
            List<ContentVersion> contentVersions = new List<ContentVersion>();
            Map<String, String> results = new Map<String, String>();
            
            for (FileUploadWrapper file : files) {
                if (String.isBlank(file.base64Data)) {
                    continue;
                }
                
                ContentVersion cv = new ContentVersion();
                cv.Title = file.fileName;
                cv.PathOnClient = file.fileName;
                cv.VersionData = EncodingUtil.base64Decode(file.base64Data);
                // Store documentType in Description field for retrieval later
                if (String.isNotBlank(file.documentType)) {
                    cv.Description = file.documentType;
                }
                
                // If it's a new version, link to existing document
                if (file.isNewVersion && String.isNotBlank(file.existingDocumentId)) {
                    cv.ContentDocumentId = file.existingDocumentId;
                }
                
                contentVersions.add(cv);
            }
            
            if (!contentVersions.isEmpty()) {
                insert contentVersions;
                
                // Create links for new documents (not new versions)
                List<ContentDocumentLink> links = new List<ContentDocumentLink>();
                
                for (Integer i = 0; i < contentVersions.size(); i++) {
                    ContentVersion cv = contentVersions[i];
                    FileUploadWrapper file = files[i];
                    
                    // Only create link if it's NOT a new version
                    if (!file.isNewVersion) {
                        // Query to get ContentDocumentId after insert
                        ContentVersion insertedCv = [
                            SELECT ContentDocumentId 
                            FROM ContentVersion 
                            WHERE Id = :cv.Id 
                            LIMIT 1
                        ];
                        
                        ContentDocumentLink cdl = new ContentDocumentLink();
                        cdl.ContentDocumentId = insertedCv.ContentDocumentId;
                        cdl.LinkedEntityId = aaProfileId; // Link to AA Profile
                        cdl.ShareType = 'V';
                        cdl.Visibility = 'AllUsers';
                        links.add(cdl);
                    }
                }
                
                if (!links.isEmpty()) {
                    insert links;
                }
                
                results.put('success', 'true');
                results.put('message', contentVersions.size() + ' file(s) uploaded successfully');
            }
            
            return results;
        } catch (Exception e) {
            throw new AuraHandledException('Error uploading files: ' + e.getMessage());
        }
    }
    
    /**
     * Get all files for AA Profile
     */
    @AuraEnabled(cacheable=true)
    public static List<FileWrapper> getAAProfileFiles(String aaProfileId) {
        try {
            if (String.isBlank(aaProfileId)) {
                throw new AuraHandledException('AA Profile ID is required');
            }
            
            // Verify user has view permission
            UserPermissions permissions = getUserPermissions();
            if (!permissions.canView) {
                throw new AuraHandledException('You do not have permission to view files');
            }
            
            // Verify AA Profile contact is active
            AAProfileInfo profileInfo = getAAProfileInfo(aaProfileId);
            if (!profileInfo.isContactActive && permissions.userRole == 'Academic Associate') {
                throw new AuraHandledException('Cannot view files. AA Contact is not active (Status: ' + profileInfo.activeStatus + ')');
            }
            
            List<FileWrapper> files = new List<FileWrapper>();
            
            // Get all ContentDocumentLinks for this AA Profile
            List<ContentDocumentLink> cdLinks = [
                SELECT ContentDocumentId 
                FROM ContentDocumentLink 
                WHERE LinkedEntityId = :aaProfileId
            ];
            
            if (cdLinks.isEmpty()) {
                return files;
            }
            
            Set<Id> documentIds = new Set<Id>();
            for (ContentDocumentLink cdl : cdLinks) {
                documentIds.add(cdl.ContentDocumentId);
            }
            
            // Get latest version of each document with version count
            Map<Id, Integer> versionCounts = new Map<Id, Integer>();
            for (AggregateResult ar : [
                SELECT ContentDocumentId, COUNT(Id) versionCount
                FROM ContentVersion
                WHERE ContentDocumentId IN :documentIds
                GROUP BY ContentDocumentId
            ]) {
                versionCounts.put(
                    (Id)ar.get('ContentDocumentId'), 
                    (Integer)ar.get('versionCount')
                );
            }
            
            List<ContentVersion> contentVersions = [
                SELECT Id, ContentDocumentId, Title, FileType, FileExtension, 
                       ContentSize, CreatedBy.Name, CreatedDate, VersionNumber, IsLatest, Description
                FROM ContentVersion
                WHERE ContentDocumentId IN :documentIds
                AND IsLatest = true
                ORDER BY CreatedDate DESC
            ];
            
            for (ContentVersion cv : contentVersions) {
                FileWrapper fw = new FileWrapper();
                fw.id = cv.ContentDocumentId;
                fw.title = cv.Title;
                fw.fileType = cv.FileType;
                fw.fileExtension = cv.FileExtension;
                fw.contentSize = cv.ContentSize != null ? cv.ContentSize : 0;
                fw.uploadedBy = cv.CreatedBy.Name;
                fw.uploadedDate = cv.CreatedDate;
                fw.versionNumber = cv.VersionNumber;
                fw.versionCount = versionCounts.get(cv.ContentDocumentId);
                fw.isLatest = cv.IsLatest;
                fw.documentType = cv.Description;
                files.add(fw);
            }
            
            return files;
        } catch (Exception e) {
            throw new AuraHandledException('Error getting files: ' + e.getMessage());
        }
    }
    
    /**
    * Get ONLY the latest version of a document (for users who can't view version history)
    */
    @AuraEnabled
    public static FileWrapper getLatestFileVersion(String contentDocumentId) {
        try {
            if (String.isBlank(contentDocumentId)) {
                throw new AuraHandledException('Document ID is required');
            }
            
            // Verify user has view permission (but don't require canViewVersions)
            UserPermissions permissions = getUserPermissions();
            if (!permissions.canView) {
                throw new AuraHandledException('You do not have permission to view files');
            }
            
            System.debug('📄 Getting latest version for document: ' + contentDocumentId);
            
            // Get ONLY the latest version
            List<ContentVersion> contentVersions = [
                SELECT Id, ContentDocumentId, Title, FileType, FileExtension,
                    ContentSize, CreatedBy.Name, CreatedDate, VersionNumber, IsLatest, Description
                FROM ContentVersion
                WHERE ContentDocumentId = :contentDocumentId
                AND IsLatest = true
                LIMIT 1
            ];
            
            if (contentVersions.isEmpty()) {
                throw new AuraHandledException('File not found');
            }
            
            ContentVersion cv = contentVersions[0];
            FileWrapper fw = new FileWrapper();
            fw.id = cv.Id;
            fw.title = cv.Title;
            fw.fileType = cv.FileType;
            fw.fileExtension = cv.FileExtension;
            fw.contentSize = cv.ContentSize != null ? cv.ContentSize : 0;
            fw.uploadedBy = cv.CreatedBy.Name;
            fw.uploadedDate = cv.CreatedDate;
            fw.versionNumber = cv.VersionNumber;
            fw.isLatest = cv.IsLatest;
            fw.documentType = cv.Description;
            
            System.debug('✅ Latest version found: v' + fw.versionNumber);
            
            return fw;
        } catch (Exception e) {
            System.debug('❌ Error getting latest file version: ' + e.getMessage());
            throw new AuraHandledException('Error getting file: ' + e.getMessage());
        }
    }

    /**
     * Get all versions of a document
     */
    @AuraEnabled
    public static List<FileWrapper> getFileVersions(String contentDocumentId) {
        try {
            if (String.isBlank(contentDocumentId)) {
                throw new AuraHandledException('Document ID is required');
            }
            
            // Verify user has permission to view versions
            UserPermissions permissions = getUserPermissions();
            if (!permissions.canViewVersions) {
                throw new AuraHandledException('You do not have permission to view version history');
            }
            
            List<FileWrapper> versions = new List<FileWrapper>();
            
            List<ContentVersion> contentVersions = [
                SELECT Id, ContentDocumentId, Title, FileType, FileExtension,
                       ContentSize, CreatedBy.Name, CreatedDate, VersionNumber, IsLatest, Description
                FROM ContentVersion
                WHERE ContentDocumentId = :contentDocumentId
                ORDER BY VersionNumber DESC
            ];
            
            for (ContentVersion cv : contentVersions) {
                FileWrapper fw = new FileWrapper();
                fw.id = cv.Id;
                fw.title = cv.Title;
                fw.fileType = cv.FileType;
                fw.fileExtension = cv.FileExtension;
                fw.contentSize = cv.ContentSize != null ? cv.ContentSize : 0;
                fw.uploadedBy = cv.CreatedBy.Name;
                fw.uploadedDate = cv.CreatedDate;
                fw.versionNumber = cv.VersionNumber;
                fw.isLatest = cv.IsLatest;
                fw.documentType = cv.Description;
                versions.add(fw);
            }
            
            return versions;
        } catch (Exception e) {
            throw new AuraHandledException('Error getting file versions: ' + e.getMessage());
        }
    }
    
    /**
     * Download file
     */
    @AuraEnabled
    public static String downloadFile(String contentVersionId) {
        try {
            if (String.isBlank(contentVersionId)) {
                throw new AuraHandledException('Version ID is required');
            }
            
            ContentVersion cv = [
                SELECT VersionData 
                FROM ContentVersion 
                WHERE Id = :contentVersionId 
                LIMIT 1
            ];
            
            return EncodingUtil.base64Encode(cv.VersionData);
        } catch (Exception e) {
            throw new AuraHandledException('Error downloading file: ' + e.getMessage());
        }
    }
    
    /**
     * Get file preview URL
     */
    @AuraEnabled
    public static String getFilePreviewUrl(String contentVersionId) {
        try {
            if (String.isBlank(contentVersionId)) {
                throw new AuraHandledException('Version ID is required');
            }
            
            ContentVersion cv = [
                SELECT ContentDocumentId 
                FROM ContentVersion 
                WHERE Id = :contentVersionId 
                LIMIT 1
            ];
            
            ContentDistribution cd = new ContentDistribution();
            cd.Name = 'Preview Distribution';
            cd.ContentVersionId = contentVersionId;
            cd.PreferencesAllowViewInBrowser = true;
            cd.PreferencesLinkLatestVersion = true;
            cd.PreferencesNotifyOnVisit = false;
            cd.PreferencesPasswordRequired = false;
            cd.PreferencesAllowOriginalDownload = false;
            cd.PreferencesAllowPDFDownload = false;
            insert cd;
            
            cd = [
                SELECT DistributionPublicUrl 
                FROM ContentDistribution 
                WHERE Id = :cd.Id 
                LIMIT 1
            ];
            
            return cd.DistributionPublicUrl;
        } catch (Exception e) {
            throw new AuraHandledException('Error getting preview URL: ' + e.getMessage());
        }
    }
    
    /**
     * Delete file (optional - only for admins)
     */
    @AuraEnabled
    public static void deleteFile(String contentDocumentId) {
        try {
            if (String.isBlank(contentDocumentId)) {
                throw new AuraHandledException('Document ID is required');
            }
            
            // Verify user is admin
            UserPermissions permissions = getUserPermissions();
            if (!permissions.canUpload || permissions.userRole != 'System Administrator') {
                throw new AuraHandledException('Only System Administrators can delete files');
            }
            
            ContentDocument cd = [
                SELECT Id 
                FROM ContentDocument 
                WHERE Id = :contentDocumentId 
                LIMIT 1
            ];
            
            delete cd;
        } catch (Exception e) {
            throw new AuraHandledException('Error deleting file: ' + e.getMessage());
        }
    }
}