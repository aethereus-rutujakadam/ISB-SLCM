@isTest
private class InternshipControllerTest {

    @TestSetup
    static void setup() {
        Account acct = new Account(Name = 'Test University');
        insert acct;

  Program prog = new Program(Name = 'MBA');
        insert prog;
        
        AcademicYear ay = TestDataFactory.testAcademicYear();
        Contact con = TestDataFactory.testContact();
        ProgramEnrollment pe = TestDataFactory.testProgramEnrollment(con, prog);

        Internship_Details__c internship = new Internship_Details__c(
            Company_Name__c       = 'Test Company',
            Designation__c        = 'Analyst',
            Start_Date__c         = Date.today(),
            End_Date__c           = Date.today().addMonths(3),
            Job_Location__c       = 'Hyderabad',
            Industry__c           = 'Education',
            Total_Stipend__c      = 10000,
            Stipend_Currency__c   = 'INR',
            Program_Enrollment__c = pe.Id
        );
        insert internship;
    }

    // ─── getDocuments ──────────────────────────────────────────────────────────

    @isTest
    static void testGetDocuments_returnsRecordsForInternship() {
        Internship_Details__c intern = [SELECT Id FROM Internship_Details__c LIMIT 1];
        insert new Internship_Documents__c(
            Internship_Details__c = intern.Id,
            Document_Type__c      = 'Other',
            Document_Title__c     = 'Other Doc',
            Upload_Date__c        = Date.today()
        );

        Test.startTest();
        List<Internship_Documents__c> docs = InternshipController.getDocuments(intern.Id);
        Test.stopTest();

        System.assertEquals(1, docs.size(), 'Expected one document');
        System.assertEquals('Other', docs[0].Document_Type__c, 'Wrong document type');
    }

    // ─── createDocumentRecord ─────────────────────────────────────────────────

    @isTest
    static void testCreateDocumentRecord_setsUploadedByAndDate() {
        Internship_Details__c intern = [
            SELECT Id, Program_Enrollment__c, Program_Enrollment__r.ContactId
            FROM Internship_Details__c
            LIMIT 1
        ];

        Internship_Documents__c doc = new Internship_Documents__c(
            Internship_Details__c = intern.Id,
            Document_Type__c      = 'Other',
            Document_Title__c     = 'Test Upload'
        );

        Test.startTest();
        Id newId = InternshipController.createDocumentRecord(doc);
        Test.stopTest();

        System.assertNotEquals(null, newId, 'Should return a new record Id');
        Internship_Documents__c created = [
            SELECT Uploaded_By__c, Upload_Date__c, Program_Enrollment__c, Contact__c
            FROM Internship_Documents__c
            WHERE Id = :newId
        ];
        System.assertEquals(UserInfo.getUserId(), created.Uploaded_By__c, 'Uploaded_By should be the running user');
        System.assertEquals(Date.today(), created.Upload_Date__c, 'Upload_Date should be today');
        System.assertEquals(intern.Program_Enrollment__c, created.Program_Enrollment__c,
            'Program Enrollment should be populated from Internship Details');
        System.assertEquals(intern.Program_Enrollment__r.ContactId, created.Contact__c,
            'Contact should be populated from Internship Details -> Program Enrollment');
    }

    // ─── Single-upload validation — Offer Letter ──────────────────────────────

    @isTest
    static void testSingleUpload_blocksSecondOfferLetter() {
        Internship_Details__c intern = [SELECT Id FROM Internship_Details__c LIMIT 1];
        insert new Internship_Documents__c(
            Internship_Details__c = intern.Id,
            Document_Type__c      = 'Summer Internship Offer Letter',
            Document_Title__c     = 'First Offer',
            Upload_Date__c        = Date.today()
        );

        Internship_Documents__c second = new Internship_Documents__c(
            Internship_Details__c = intern.Id,
            Document_Type__c      = 'Summer Internship Offer Letter',
            Document_Title__c     = 'Second Offer'
        );

        Test.startTest();
        try {
            InternshipController.createDocumentRecord(second);
            System.assert(false, 'Expected AuraHandledException to be thrown');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage(), 'Exception should have a message');
        }
        Test.stopTest();
    }

    // ─── Single-upload validation — Completion Certificate ───────────────────

    @isTest
    static void testSingleUpload_blocksSecondCertificate() {
        Internship_Details__c intern = [SELECT Id FROM Internship_Details__c LIMIT 1];
        insert new Internship_Documents__c(
            Internship_Details__c = intern.Id,
            Document_Type__c      = 'Internship Completion Certificate',
            Document_Title__c     = 'First Certificate',
            Upload_Date__c        = Date.today()
        );

        Internship_Documents__c second = new Internship_Documents__c(
            Internship_Details__c = intern.Id,
            Document_Type__c      = 'Internship Completion Certificate',
            Document_Title__c     = 'Second Certificate'
        );

        Test.startTest();
        try {
            InternshipController.createDocumentRecord(second);
            System.assert(false, 'Expected AuraHandledException to be thrown');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage(), 'Exception should have a message');
        }
        Test.stopTest();
    }

    // ─── Multiple Other docs allowed ─────────────────────────────────────────

    @isTest
    static void testMultipleOtherDocuments_areAllowed() {
        Internship_Details__c intern = [SELECT Id FROM Internship_Details__c LIMIT 1];

        Test.startTest();
        InternshipController.createDocumentRecord(new Internship_Documents__c(
            Internship_Details__c = intern.Id,
            Document_Type__c      = 'Other',
            Document_Title__c     = 'Other 1'
        ));
        InternshipController.createDocumentRecord(new Internship_Documents__c(
            Internship_Details__c = intern.Id,
            Document_Type__c      = 'Other',
            Document_Title__c     = 'Other 2'
        ));
        Test.stopTest();

        Integer count = [
            SELECT COUNT()
            FROM Internship_Documents__c
            WHERE Internship_Details__c = :intern.Id
              AND Document_Type__c = 'Other'
        ];
        System.assertEquals(2, count, 'Two Other-type documents should be allowed');
    }

    // ─── saveInternship — insert ──────────────────────────────────────────────

    @isTest
    static void testSaveInternship_insert() {
        Internship_Details__c rec = new Internship_Details__c(
            Company_Name__c     = 'New Company',
            Designation__c      = 'Intern',
            Start_Date__c       = Date.today(),
            End_Date__c         = Date.today().addMonths(2),
            Job_Location__c     = 'Mumbai',
            Industry__c         = 'Education',
            Total_Stipend__c    = 5000,
            Stipend_Currency__c = 'INR'
        );

        Test.startTest();
        Id newId = InternshipController.saveInternship(rec);
        Test.stopTest();

        System.assertNotEquals(null, newId, 'Should return the new record Id');
        Internship_Details__c created = [SELECT Company_Name__c FROM Internship_Details__c WHERE Id = :newId];
        System.assertEquals('New Company', created.Company_Name__c, 'Company name should match');
    }

    // ─── saveInternship — update ──────────────────────────────────────────────

    @isTest
    static void testSaveInternship_update() {
        Internship_Details__c intern = [SELECT Id, Company_Name__c FROM Internship_Details__c LIMIT 1];
        intern.Company_Name__c = 'Updated Company';

        Test.startTest();
        Id returnedId = InternshipController.saveInternship(intern);
        Test.stopTest();

        System.assertEquals(intern.Id, returnedId, 'Should return the same record Id on update');
        Internship_Details__c updated = [SELECT Company_Name__c FROM Internship_Details__c WHERE Id = :intern.Id];
        System.assertEquals('Updated Company', updated.Company_Name__c, 'Company name should be updated');
    }

    // ─── checkDocumentTypeExists ──────────────────────────────────────────────

    @isTest
    static void testCheckDocumentTypeExists() {
        Internship_Details__c intern = [SELECT Id FROM Internship_Details__c LIMIT 1];

        Test.startTest();
        Boolean existsBefore = InternshipController.checkDocumentTypeExists(
            intern.Id, 'Summer Internship Offer Letter'
        );
        System.assertEquals(false, existsBefore, 'Should be false before any doc is added');

        insert new Internship_Documents__c(
            Internship_Details__c = intern.Id,
            Document_Type__c      = 'Summer Internship Offer Letter',
            Document_Title__c     = 'Offer',
            Upload_Date__c        = Date.today()
        );

        Boolean existsAfter = InternshipController.checkDocumentTypeExists(
            intern.Id, 'Summer Internship Offer Letter'
        );
        System.assertEquals(true, existsAfter, 'Should be true after the doc is added');

        Boolean otherType = InternshipController.checkDocumentTypeExists(intern.Id, 'Other');
        System.assertEquals(false, otherType, 'Other type should always return false');
        Test.stopTest();
    }

    // ─── createDocumentRecord — missing internship reference ─────────────────

    @isTest
    static void testCreateDocumentRecord_missingParent_throwsException() {
        Internship_Documents__c doc = new Internship_Documents__c(
            Document_Type__c  = 'Other',
            Document_Title__c = 'Orphan Doc'
        );

        Test.startTest();
        try {
            InternshipController.createDocumentRecord(doc);
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage(), 'Exception should have a message');
        }
        Test.stopTest();
    }

    // ─── createInternshipWithDocuments populates lookups ─────────────────────

    @isTest
    static void testCreateInternshipWithDocuments_populatesDocumentLookups() {
        ProgramEnrollment pe = [SELECT Id, ContactId FROM ProgramEnrollment LIMIT 1];

        Internship_Details__c newInternship = new Internship_Details__c(
            Company_Name__c       = 'Txn Company',
            Designation__c        = 'Intern',
            Start_Date__c         = Date.today(),
            End_Date__c           = Date.today().addMonths(1),
            Job_Location__c       = 'Hyderabad',
            Industry__c           = 'Education',
            Total_Stipend__c      = 1000,
            Stipend_Currency__c   = 'INR',
            Program_Enrollment__c = pe.Id,
            Contact__c            = pe.ContactId
        );

        InternshipController.DocumentMetadata meta = new InternshipController.DocumentMetadata();
        meta.documentType = 'Other';
        meta.documentTitle = 'Txn Doc';
        meta.notes = 'Created in transaction';

        Test.startTest();
        InternshipController.CreationResult result = InternshipController.createInternshipWithDocuments(
            newInternship,
            new List<InternshipController.DocumentMetadata>{ meta }
        );
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should be returned');
        System.assertEquals(1, result.documentIds.size(), 'Exactly one document should be created');

        Internship_Documents__c createdDoc = [
            SELECT Program_Enrollment__c, Contact__c, Internship_Details__c
            FROM Internship_Documents__c
            WHERE Id = :result.documentIds[0]
        ];
        System.assertEquals(pe.Id, createdDoc.Program_Enrollment__c,
            'Program Enrollment should be copied to the document');
        System.assertEquals(pe.ContactId, createdDoc.Contact__c,
            'Contact should be copied to the document');
        System.assertEquals(result.internshipId, createdDoc.Internship_Details__c,
            'Document should reference the newly created internship');
    }

// ─── deleteInternship ────────────────────────────────────────────────────

    @isTest
    static void testDeleteInternship() {
        Internship_Details__c intern = [SELECT Id FROM Internship_Details__c LIMIT 1];

        Test.startTest();
        InternshipController.deleteInternship(intern.Id);
        Test.stopTest();

        System.assertEquals(0,
            [SELECT COUNT() FROM Internship_Details__c WHERE Id = :intern.Id],
            'Internship should be deleted');
    }

    // ─── uploadFileToDocument ─────────────────────────────────────────────────

    @isTest
    static void testUploadFileToDocument() {
        Internship_Details__c intern = [SELECT Id FROM Internship_Details__c LIMIT 1];
        Internship_Documents__c doc = new Internship_Documents__c(
            Internship_Details__c = intern.Id,
            Document_Type__c      = 'Other',
            Document_Title__c     = 'Upload Target'
        );
        insert doc;

        Test.startTest();
        InternshipController.uploadFileToDocument(
            doc.Id, 'upload.pdf', EncodingUtil.base64Encode(Blob.valueOf('file-data'))
        );
        Test.stopTest();

        List<ContentDocumentLink> links = [
            SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :doc.Id
        ];
        System.assertEquals(1, links.size(), 'A file should be linked to the document');
    }

    // ─── getDocumentContentId (file + no file) ────────────────────────────────

    @isTest
    static void testGetDocumentContentId() {
        Internship_Details__c intern = [SELECT Id FROM Internship_Details__c LIMIT 1];
        Internship_Documents__c doc = new Internship_Documents__c(
            Internship_Details__c = intern.Id,
            Document_Type__c      = 'Other',
            Document_Title__c     = 'Content Id Doc'
        );
        insert doc;

        Test.startTest();
        Id beforeFile = InternshipController.getDocumentContentId(doc.Id);
        InternshipController.uploadFileToDocument(
            doc.Id, 'c.txt', EncodingUtil.base64Encode(Blob.valueOf('x'))
        );
        Id afterFile = InternshipController.getDocumentContentId(doc.Id);
        Test.stopTest();

        System.assertEquals(null, beforeFile, 'Should be null when no file attached');
        System.assertNotEquals(null, afterFile, 'Should return ContentDocumentId once a file exists');
    }

    // ─── getDocumentPreviewData (file + no file) ──────────────────────────────

    @isTest
    static void testGetDocumentPreviewData() {
        Internship_Details__c intern = [SELECT Id FROM Internship_Details__c LIMIT 1];
        Internship_Documents__c doc = new Internship_Documents__c(
            Internship_Details__c = intern.Id,
            Document_Type__c      = 'Other',
            Document_Title__c     = 'Preview Doc'
        );
        insert doc;

        Test.startTest();
        Map<String, String> beforeFile = InternshipController.getDocumentPreviewData(doc.Id);
        InternshipController.uploadFileToDocument(
            doc.Id, 'preview.pdf', EncodingUtil.base64Encode(Blob.valueOf('y'))
        );
        Map<String, String> afterFile = InternshipController.getDocumentPreviewData(doc.Id);
        Test.stopTest();

        System.assertEquals(null, beforeFile, 'Should return null when no file attached');
        System.assertNotEquals(null, afterFile, 'Should return a map once a file exists');
        System.assert(afterFile.containsKey('contentDocumentId'), 'Map should contain contentDocumentId');
        System.assert(afterFile.containsKey('contentVersionId'), 'Map should contain contentVersionId');
    }

    // ─── deleteDocument (with file + without file) ────────────────────────────

    @isTest
    static void testDeleteDocument_withFile() {
        Internship_Details__c intern = [SELECT Id FROM Internship_Details__c LIMIT 1];
        Internship_Documents__c doc = new Internship_Documents__c(
            Internship_Details__c = intern.Id,
            Document_Type__c      = 'Other',
            Document_Title__c     = 'Delete With File'
        );
        insert doc;
        InternshipController.uploadFileToDocument(
            doc.Id, 'del.txt', EncodingUtil.base64Encode(Blob.valueOf('z'))
        );
        Id contentDocId = InternshipController.getDocumentContentId(doc.Id);

        Test.startTest();
        InternshipController.deleteDocument(doc.Id);
        Test.stopTest();

        System.assertEquals(0,
            [SELECT COUNT() FROM Internship_Documents__c WHERE Id = :doc.Id],
            'Document record should be deleted');
        System.assertEquals(0,
            [SELECT COUNT() FROM ContentDocument WHERE Id = :contentDocId],
            'Underlying file should be deleted');
    }

    @isTest
    static void testDeleteDocument_withoutFile() {
        Internship_Details__c intern = [SELECT Id FROM Internship_Details__c LIMIT 1];
        Internship_Documents__c doc = new Internship_Documents__c(
            Internship_Details__c = intern.Id,
            Document_Type__c      = 'Other',
            Document_Title__c     = 'Delete No File'
        );
        insert doc;

        Test.startTest();
        InternshipController.deleteDocument(doc.Id); // exercises the empty-links branch
        Test.stopTest();

        System.assertEquals(0,
            [SELECT COUNT() FROM Internship_Documents__c WHERE Id = :doc.Id],
            'Document record should be deleted');
    }

    // ─── getProgramEnrollmentId / getStudentInternships — null-ContactId branch ─

    @isTest
    static void testGetMethods_noContactOnUser() {
        // The default test-running user has no ContactId -> early-return branches
        Test.startTest();
        Id peId = InternshipController.getProgramEnrollmentId();
        List<Internship_Details__c> interns = InternshipController.getStudentInternships();
        Test.stopTest();

        System.assertEquals(null, peId, 'No ContactId should yield null enrollment');
        System.assertEquals(0, interns.size(), 'No ContactId should yield empty internship list');
    }

    // ─── getProgramEnrollmentId / getStudentInternships — community-user path ──

    @isTest
    static void testGetMethods_asCommunityUser() {
        // Role'd owner (setup DML isolated in runAs to avoid MIXED_DML)
        User acctOwner;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            UserRole role = new UserRole(Name = 'InternTestRole');
            insert role;
            acctOwner = new User(
                Alias = 'iown', Email = 'internowner@test.com',
                EmailEncodingKey = 'UTF-8', LastName = 'Owner',
                LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US',
                ProfileId = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1].Id,
                TimeZoneSidKey = 'America/Los_Angeles',
                UserName = 'internowner' + System.currentTimeMillis() + '@test.com',
                UserRoleId = role.Id
            );
            insert acctOwner;
        }

        // Data DML — account owned by the role'd user so a portal user can be enabled
        Account acc = new Account(Name = 'Portal Account', OwnerId = acctOwner.Id);
        insert acc;
  
        Program prog = new Program(Name = 'MBA');
        insert prog;
        
        AcademicYear ay = TestDataFactory.testAcademicYear();
        Contact c = TestDataFactory.testContact();
        ProgramEnrollment pe = TestDataFactory.testProgramEnrollment(c, prog);

        Internship_Details__c intern = new Internship_Details__c(
            Company_Name__c       = 'Portal Co',
            Designation__c        = 'Intern',
            Start_Date__c         = Date.today(),
            End_Date__c           = Date.today().addMonths(2),
            Job_Location__c       = 'Hyderabad',
            Industry__c           = 'Education',
            Total_Stipend__c      = 5000,
            Stipend_Currency__c   = 'INR',
            Program_Enrollment__c = pe.Id,
            Contact__c            = c.Id
        );
        insert intern;

        // Community user (setup DML isolated again)
        User portalUser;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Profile pp = [
                SELECT Id FROM Profile
                WHERE UserType IN ('CspLitePortal','PowerCustomerSuccess','PowerPartner','CustomerSuccess')
                LIMIT 1
            ];
            portalUser = new User(
                Alias = 'iprt', Email = 'internportal@test.com',
                EmailEncodingKey = 'UTF-8', LastName = 'Portal',
                LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US',
                ProfileId = pp.Id, TimeZoneSidKey = 'America/Los_Angeles',
                UserName = 'internportal' + System.currentTimeMillis() + '@test.com',
                ContactId = c.Id
            );
            insert portalUser;
        }

        System.runAs(portalUser) {
            Test.startTest();
            Id resultPeId = InternshipController.getProgramEnrollmentId();
            List<Internship_Details__c> interns = InternshipController.getStudentInternships();
            Test.stopTest();
        }
    }
}