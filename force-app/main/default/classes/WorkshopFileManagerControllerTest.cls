@isTest
private class WorkshopFileManagerControllerTest {
    @TestSetup
    static void setup() {
        Program programRecord = new Program(Name = 'File Manager Program');
        insert programRecord;

        AcademicTerm termRecord = new AcademicTerm(Name = 'File Manager Cohort');
        insert termRecord;

        AcademicSession sessionRecord = new AcademicSession(
            Name = 'File Manager Session',
            AcademicTermId = termRecord.Id
        );
        insert sessionRecord;

        Workshop__c workshopRecord = new Workshop__c(
            Name = 'File Manager Workshop',
            Status__c = 'Draft',
            Program__c = programRecord.Id,
            Cohort__c = termRecord.Id,
            Eligible_Term__c = sessionRecord.Id,
            Total_Sessions__c = 1
        );
        insert workshopRecord;
    }

    @isTest
    static void testUploadAndListWorkshopFiles() {
        Workshop__c workshopRecord = [SELECT Id FROM Workshop__c LIMIT 1];

        WorkshopFileManagerController.FileUploadWrapper uploadRequest =
            new WorkshopFileManagerController.FileUploadWrapper();
        uploadRequest.fileName = 'Advisor Guide.pdf';
        uploadRequest.base64Data = EncodingUtil.base64Encode(Blob.valueOf('version-one'));
        uploadRequest.isNewVersion = false;

        Test.startTest();
        Map<String, String> uploadResult = WorkshopFileManagerController.uploadFiles(
            workshopRecord.Id,
            new List<WorkshopFileManagerController.FileUploadWrapper>{ uploadRequest }
        );
        List<WorkshopFileManagerController.FileWrapper> workshopFiles =
            WorkshopFileManagerController.getWorkshopFiles(workshopRecord.Id);
        Test.stopTest();

        System.assertEquals('true', uploadResult.get('success'));
        System.assertEquals(1, workshopFiles.size(), 'Expected one workshop file.');
        System.assertEquals('Advisor Guide.pdf', workshopFiles[0].title);
        System.assertEquals(1, workshopFiles[0].versionCount);
    }

    @isTest
    static void testUploadNewVersionAndReadHistory() {
        Workshop__c workshopRecord = [SELECT Id FROM Workshop__c LIMIT 1];

        WorkshopFileManagerController.FileUploadWrapper initialUpload =
            new WorkshopFileManagerController.FileUploadWrapper();
        initialUpload.fileName = 'Deck.pdf';
        initialUpload.base64Data = EncodingUtil.base64Encode(Blob.valueOf('deck-v1'));
        initialUpload.isNewVersion = false;

        WorkshopFileManagerController.uploadFiles(
            workshopRecord.Id,
            new List<WorkshopFileManagerController.FileUploadWrapper>{ initialUpload }
        );

        String documentId = WorkshopFileManagerController.getWorkshopFiles(workshopRecord.Id)[0].id;

        WorkshopFileManagerController.FileUploadWrapper secondUpload =
            new WorkshopFileManagerController.FileUploadWrapper();
        secondUpload.fileName = 'Deck.pdf';
        secondUpload.base64Data = EncodingUtil.base64Encode(Blob.valueOf('deck-v2'));
        secondUpload.isNewVersion = true;
        secondUpload.existingDocumentId = documentId;

        Test.startTest();
        WorkshopFileManagerController.uploadFiles(
            workshopRecord.Id,
            new List<WorkshopFileManagerController.FileUploadWrapper>{ secondUpload }
        );
        List<WorkshopFileManagerController.FileWrapper> versions =
            WorkshopFileManagerController.getFileVersions(workshopRecord.Id, documentId);
        WorkshopFileManagerController.FileWrapper latestVersion =
            WorkshopFileManagerController.getLatestFileVersion(workshopRecord.Id, documentId);
        String downloadedFile = WorkshopFileManagerController.downloadFile(workshopRecord.Id, (Id) latestVersion.id);
        Test.stopTest();

        System.assertEquals(2, versions.size(), 'Expected two versions after version upload.');
        System.assertEquals('2', latestVersion.versionNumber, 'Expected latest version number to be 2.');
        System.assertEquals(
            EncodingUtil.base64Encode(Blob.valueOf('deck-v2')),
            downloadedFile,
            'Expected latest file payload to be returned.'
        );
    }

    @isTest
    static void testRejectUnlinkedDocumentAccess() {
        Workshop__c workshopRecord = [SELECT Id FROM Workshop__c LIMIT 1];

        ContentVersion unrelatedVersion = new ContentVersion(
            Title = 'Unrelated.pdf',
            PathOnClient = 'Unrelated.pdf',
            VersionData = Blob.valueOf('external')
        );
        insert unrelatedVersion;

        unrelatedVersion = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :unrelatedVersion.Id
            LIMIT 1
        ];

        Boolean didThrow = false;
        Test.startTest();
        try {
            WorkshopFileManagerController.getLatestFileVersion(workshopRecord.Id, unrelatedVersion.ContentDocumentId);
        } catch (AuraHandledException ex) {
            didThrow = true;
        }
        Test.stopTest();

        System.assertEquals(true, didThrow, 'Expected access to unlinked document to be blocked.');
    }
}