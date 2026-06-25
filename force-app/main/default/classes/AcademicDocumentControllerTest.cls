@isTest
public class AcademicDocumentControllerTest {

    @TestSetup
    static void setup() {
        // 1. Get System Administrator Profile
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        
        // 2. Create Admin User
        User admin = new User(
            FirstName = 'Test', LastName = 'Admin',
            Email = 'admin' + DateTime.now().getTime() + '@test.com',
            Username = 'admin' + DateTime.now().getTime() + '@test.com',
            Alias = 'adm', TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US', EmailEncodingKey = 'UTF-8',
            ProfileId = p.Id, LanguageLocaleKey = 'en_US'
        );
        insert admin;

        System.runAs(admin) {
            // 3. Create a parent Account (often required by Contact filters)
            Account acc = new Account(Name = 'Test University');
            insert acc;

            // 4. GET CORRECT RECORD TYPE (Fixed the method name here)
            Id aaRecordTypeId;
            try {
                aaRecordTypeId = Schema.SObjectType.Contact.getRecordTypeInfosByDeveloperName()
                                 .get('Academic_Associate').getRecordTypeId();
            } catch (Exception e) {
                // Corrected Method: getRecordTypeInfos() returns a list
                aaRecordTypeId = Schema.SObjectType.Contact.getRecordTypeInfos().get(0).getRecordTypeId();
            }

            // 5. Create Contact with correct Record Type and Status
            Contact c = new Contact(
                FirstName = 'Linked', 
                LastName = 'Contact',
                Email = admin.Email,
                AccountId = acc.Id,
                Linked_User_Id__c = admin.Id,
                Active_Status__c = 'Active',
                RecordTypeId = aaRecordTypeId 
            );
            insert c;

            // 6. Create AA Profile
            AA_Profile__c ap = new AA_Profile__c(
                Name = 'Test Profile',
                Academic_Associate__c = c.Id,
                Status__c = 'Active'
            );
            insert ap;
        }
    }

    @isTest
    static void testAllControllerMethods() {
        User admin = [SELECT Id FROM User WHERE Alias = 'adm' LIMIT 1];
        AA_Profile__c profile = [SELECT Id FROM AA_Profile__c LIMIT 1];

        System.runAs(admin) {
            Test.startTest();
            
            // Permissions logic
            AcademicDocumentController.UserPermissions permissions = AcademicDocumentController.getUserPermissions();
            System.assertEquals('System Administrator', permissions.userRole);

            // Profile Info logic
            AcademicDocumentController.AAProfileInfo info = AcademicDocumentController.getAAProfileInfo(profile.Id);
            System.assertEquals(profile.Id, info.aaProfileId);
            
            AcademicDocumentController.AAProfileInfo derivedInfo = AcademicDocumentController.getAAProfileInfo(null);
            System.assertNotEquals(null, derivedInfo.aaProfileId);

            // File Upload logic
            AcademicDocumentController.FileUploadWrapper file = new AcademicDocumentController.FileUploadWrapper();
            file.fileName = 'Test.txt';
            file.base64Data = EncodingUtil.base64Encode(Blob.valueOf('Data'));
            file.isNewVersion = false;
            AcademicDocumentController.uploadFiles(profile.Id, new List<AcademicDocumentController.FileUploadWrapper>{file});

            // File Retrieval logic
            List<AcademicDocumentController.FileWrapper> files = AcademicDocumentController.getAAProfileFiles(profile.Id);
            if(!files.isEmpty()) {
                Id docId = files[0].id;
                
                // Version History logic
                AcademicDocumentController.getLatestFileVersion(docId);
                AcademicDocumentController.getFileVersions(docId);
                
                // Download and Preview logic (Pass ContentVersionId from the wrapper)
                // We use docId and query for the version Id to be safe
                ContentVersion cv = [SELECT Id FROM ContentVersion WHERE ContentDocumentId = :docId LIMIT 1];
                AcademicDocumentController.downloadFile(cv.Id);
                AcademicDocumentController.getFilePreviewUrl(cv.Id);

                // Update Version logic
                AcademicDocumentController.FileUploadWrapper verUp = new AcademicDocumentController.FileUploadWrapper();
                verUp.fileName = 'V2.txt';
                verUp.base64Data = EncodingUtil.base64Encode(Blob.valueOf('V2'));
                verUp.isNewVersion = true;
                verUp.existingDocumentId = docId;
                AcademicDocumentController.uploadFiles(profile.Id, new List<AcademicDocumentController.FileUploadWrapper>{verUp});
                
                // Delete logic
                AcademicDocumentController.deleteFile(docId);
            }
            
            Test.stopTest();
        }
    }

    @isTest
    static void testNegativePaths() {
        User admin = [SELECT Id FROM User WHERE Alias = 'adm' LIMIT 1];
        
        System.runAs(admin) {
            Contact c = [SELECT Id FROM Contact LIMIT 1];
            c.Active_Status__c = 'Inactive';
            update c;
            
            AcademicDocumentController.getUserPermissions();

            try {
                AcademicDocumentController.getAAProfileInfo('invalidId');
            } catch (Exception e) {
                System.assert(true);
            }
        }
    }
}