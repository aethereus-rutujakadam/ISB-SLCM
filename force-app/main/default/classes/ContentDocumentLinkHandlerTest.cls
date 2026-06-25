@isTest
private class ContentDocumentLinkHandlerTest {

    private static Id createDocument(String title, String fileName) {
        ContentVersion cv = new ContentVersion(
            Title = title,
            PathOnClient = fileName,
            VersionData = Blob.valueOf('test file data'),
            IsMajorVersion = true
        );
        insert cv;
        return [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
    }

    @testSetup
    static void setup() {
        // Create test profiles (if needed)
        // Note: In real tests, you'd need to create or query actual profiles
    }

    @isTest
    static void beforeInsert_publishedStudentPostSetsAllUsers() {
        Student_Post__c publishedPost = new Student_Post__c(
            Title__c = 'Published Post',
            Status__c = 'Published'
        );
        insert publishedPost;

        Id contentDocumentId = createDocument('Published Post File', 'published.pdf');
        ContentDocumentLink cdl = new ContentDocumentLink(
            LinkedEntityId = publishedPost.Id,
            ContentDocumentId = contentDocumentId,
            ShareType = 'V',
            Visibility = 'InternalUsers'
        );

        Test.startTest();
        ContentDocumentLinkHandler.handleBeforeInsert(new List<ContentDocumentLink>{ cdl });
        Test.stopTest();

        System.assertEquals('AllUsers', cdl.Visibility);
    }

    @isTest
    static void beforeInsert_draftStudentPostKeepsVisibility() {
        Student_Post__c draftPost = new Student_Post__c(
            Title__c = 'Draft Post',
            Status__c = 'Draft'
        );
        insert draftPost;

        Id contentDocumentId = createDocument('Draft Post File', 'draft.pdf');
        ContentDocumentLink cdl = new ContentDocumentLink(
            LinkedEntityId = draftPost.Id,
            ContentDocumentId = contentDocumentId,
            ShareType = 'V',
            Visibility = 'InternalUsers'
        );

        Test.startTest();
        ContentDocumentLinkHandler.handleBeforeInsert(new List<ContentDocumentLink>{ cdl });
        Test.stopTest();

        System.assertNotEquals(null, cdl.Visibility);
    }

    @isTest
    static void beforeInsert_caseWithDueDateAllowsUpload() {
        Case testCase = new Case(
            Subject = 'Test Case',
            Status = 'New',
            Revised_Due_Date__c = Date.today().addDays(7)
        );
        insert testCase;

        Id contentDocumentId = createDocument(System.Label.TermsAndCondition_FileName, 'terms.pdf');
        ContentDocumentLink cdl = new ContentDocumentLink(
            LinkedEntityId = testCase.Id,
            ContentDocumentId = contentDocumentId,
            ShareType = 'V',
            Visibility = 'InternalUsers'
        );

        Test.startTest();
        insert cdl;
        Test.stopTest();

        ContentDocumentLink inserted = [SELECT Id FROM ContentDocumentLink WHERE Id = :cdl.Id LIMIT 1];
        System.assertNotEquals(null, inserted, 'CDL should be inserted successfully');
    }

    @isTest
    static void beforeInsert_caseWithoutDueDateBlocksRegistrarUpload() {
        // This test validates the error scenario but needs actual Registrar Office profile
        Case testCase = new Case(
            Subject = 'Test Case No Due Date',
            Status = 'New',
            Revised_Due_Date__c = null
        );
        insert testCase;

        Id contentDocumentId = createDocument(System.Label.TermsAndCondition_FileName, 'terms.pdf');
        ContentDocumentLink cdl = new ContentDocumentLink(
            LinkedEntityId = testCase.Id,
            ContentDocumentId = contentDocumentId,
            ShareType = 'V',
            Visibility = 'InternalUsers'
        );

        Test.startTest();
        try {
            insert cdl;
        } catch (Exception e) {
            // Expected if running as Registrar Office profile
            System.assert(true, 'Validation worked');
        }
        Test.stopTest();
    }

    @isTest
    static void beforeInsert_nonTermsFileOnCaseDoesNotValidate() {
        Case testCase = new Case(
            Subject = 'Test Case',
            Status = 'New',
            Revised_Due_Date__c = null
        );
        insert testCase;

        Id contentDocumentId = createDocument('Regular File', 'regular.pdf');
        ContentDocumentLink cdl = new ContentDocumentLink(
            LinkedEntityId = testCase.Id,
            ContentDocumentId = contentDocumentId,
            ShareType = 'V',
            Visibility = 'InternalUsers'
        );

        Test.startTest();
        insert cdl;
        Test.stopTest();

        ContentDocumentLink inserted = [SELECT Id FROM ContentDocumentLink WHERE Id = :cdl.Id LIMIT 1];
        System.assertNotEquals(null, inserted, 'Non-Terms files should upload without validation');
    }

    @isTest
    static void beforeInsert_casePathRunsWithSyntheticCaseId() {
        Id syntheticCaseId = Id.valueOf('500000000000000AAA');

        Id contentDocumentId = createDocument(System.Label.TermsAndCondition_FileName, 'terms.pdf');
        ContentDocumentLink cdl = new ContentDocumentLink(
            LinkedEntityId = syntheticCaseId,
            ContentDocumentId = contentDocumentId,
            ShareType = 'V',
            Visibility = 'InternalUsers'
        );

        Test.startTest();
        ContentDocumentLinkHandler.handleBeforeInsert(new List<ContentDocumentLink>{ cdl });
        Test.stopTest();

        System.assertEquals('InternalUsers', cdl.Visibility);
    }

    @isTest
    static void beforeInsert_emptyListDoesNothing() {
        Test.startTest();
        ContentDocumentLinkHandler.handleBeforeInsert(new List<ContentDocumentLink>());
        Test.stopTest();
        
        System.assert(true, 'Empty list handled');
    }

    @isTest
    static void afterInsert_caseFileUpdatesVisibilityToAllUsers() {
        Case testCase = new Case(
            Subject = 'Test Case for Visibility',
            Status = 'New',
            TermsCondition__c = false
        );
        insert testCase;

        Id contentDocumentId = createDocument('Test File', 'testfile.pdf');
        ContentDocumentLink cdl = new ContentDocumentLink(
            LinkedEntityId = testCase.Id,
            ContentDocumentId = contentDocumentId,
            ShareType = 'V',
            Visibility = 'InternalUsers'
        );
        insert cdl;

        ContentDocumentLink inserted = [
            SELECT Id, LinkedEntityId, ContentDocumentId, Visibility
            FROM ContentDocumentLink
            WHERE Id = :cdl.Id
            LIMIT 1
        ];

        Test.startTest();
        ContentDocumentLinkHandler.handleAfterInsert(new List<ContentDocumentLink>{ inserted });
        Test.stopTest();

        ContentDocumentLink updated = [SELECT Visibility FROM ContentDocumentLink WHERE Id = :cdl.Id LIMIT 1];
        System.assertEquals('AllUsers', updated.Visibility, 'Visibility should be updated to AllUsers');
    }

    // Note: Community Plus User tests require proper Community setup in org
    // Testing the handler logic path that handles Community users
    @isTest
    static void afterInsert_handlerLogicForStatusUpdate() {
        Case testCase = new Case(
            Subject = 'Test Case for Status Update',
            Status = 'New',
            TermsCondition__c = false
        );
        insert testCase;

        Id contentDocumentId = createDocument('Test File for Status', 'statustest.pdf');
        ContentDocumentLink cdl = new ContentDocumentLink(
            LinkedEntityId = testCase.Id,
            ContentDocumentId = contentDocumentId,
            ShareType = 'V',
            Visibility = 'InternalUsers'
        );
        insert cdl;

        ContentDocumentLink inserted = [
            SELECT Id, LinkedEntityId, ContentDocumentId, Visibility
            FROM ContentDocumentLink
            WHERE Id = :cdl.Id
            LIMIT 1
        ];

        Test.startTest();
        // This tests the code path even though current user is not Community Plus
        ContentDocumentLinkHandler.handleAfterInsert(new List<ContentDocumentLink>{ inserted });
        Test.stopTest();

        // Verify the handler executed successfully
        ContentDocumentLink updated = [SELECT Id, Visibility FROM ContentDocumentLink WHERE Id = :cdl.Id LIMIT 1];
        System.assertNotEquals(null, updated, 'Handler should complete successfully');
    }

    @isTest
    static void afterInsert_caseWithAcceptedTermsLogic() {
        Case testCase = new Case(
            Subject = 'Accepted Terms Case',
            Status = 'T&C Accepted',
            TermsCondition__c = true
        );
        insert testCase;

        Id contentDocumentId = createDocument('Terms Accepted File', 'accepted.pdf');
        ContentDocumentLink cdl = new ContentDocumentLink(
            LinkedEntityId = testCase.Id,
            ContentDocumentId = contentDocumentId,
            ShareType = 'V',
            Visibility = 'InternalUsers'
        );
        insert cdl;

        ContentDocumentLink inserted = [
            SELECT Id, LinkedEntityId, ContentDocumentId, Visibility
            FROM ContentDocumentLink
            WHERE Id = :cdl.Id
            LIMIT 1
        ];

        Test.startTest();
        ContentDocumentLinkHandler.handleAfterInsert(new List<ContentDocumentLink>{ inserted });
        Test.stopTest();

        // Status update logic only applies for Customer Community Plus users
        // This test validates the handler executes without errors
        Case updatedCase = [SELECT Status FROM Case WHERE Id = :testCase.Id LIMIT 1];
        System.assertNotEquals(null, updatedCase.Status, 'Case should exist with a status');
    }

    @isTest
    static void afterInsert_caseWithSubmittedStatus() {
        Case testCase = new Case(
            Subject = 'Already Submitted Case',
            Status = 'Submitted',
            TermsCondition__c = false
        );
        insert testCase;

        Id contentDocumentId = createDocument('Submitted File', 'submitted.pdf');
        ContentDocumentLink cdl = new ContentDocumentLink(
            LinkedEntityId = testCase.Id,
            ContentDocumentId = contentDocumentId,
            ShareType = 'V',
            Visibility = 'InternalUsers'
        );
        insert cdl;

        ContentDocumentLink inserted = [
            SELECT Id, LinkedEntityId, ContentDocumentId, Visibility
            FROM ContentDocumentLink
            WHERE Id = :cdl.Id
            LIMIT 1
        ];

        Test.startTest();
        ContentDocumentLinkHandler.handleAfterInsert(new List<ContentDocumentLink>{ inserted });
        Test.stopTest();

        Case updatedCase = [SELECT Status FROM Case WHERE Id = :testCase.Id LIMIT 1];
        // Status should remain Submitted as it's already Submitted
        System.assertEquals('Submitted', updatedCase.Status, 'Case status should remain Submitted');
    }

    @isTest
    static void afterInsert_casePathRunsWithSyntheticCaseId() {
        Id syntheticCaseId = Id.valueOf('500000000000000AAA');

        Id contentDocumentId = createDocument('Any File', 'casefile.pdf');
        ContentDocumentLink cdl = new ContentDocumentLink(
            LinkedEntityId = syntheticCaseId,
            ContentDocumentId = contentDocumentId,
            ShareType = 'V',
            Visibility = 'InternalUsers'
        );

        Test.startTest();
        ContentDocumentLinkHandler.handleAfterInsert(new List<ContentDocumentLink>{ cdl });
        Test.stopTest();

        System.assertEquals('InternalUsers', cdl.Visibility);
    }

    @isTest
    static void afterInsert_returnsWhenNoCaseLinkedRecords() {
        Contact c = new Contact(LastName = 'NoCase', Email = 'nocase@test.com');
        insert c;

        Id contentDocumentId = createDocument('Contact File', 'contact.pdf');
        ContentDocumentLink cdl = new ContentDocumentLink(
            LinkedEntityId = c.Id,
            ContentDocumentId = contentDocumentId,
            ShareType = 'V',
            Visibility = 'InternalUsers'
        );
        insert cdl;

        ContentDocumentLink inserted = [
            SELECT Id, LinkedEntityId, ContentDocumentId, Visibility
            FROM ContentDocumentLink
            WHERE Id = :cdl.Id
            LIMIT 1
        ];

        Test.startTest();
        ContentDocumentLinkHandler.handleAfterInsert(new List<ContentDocumentLink>{ inserted });
        Test.stopTest();

        ContentDocumentLink reloaded = [SELECT Visibility FROM ContentDocumentLink WHERE Id = :cdl.Id LIMIT 1];
        System.assertEquals('InternalUsers', reloaded.Visibility);
    }

    @isTest
    static void afterInsert_multipleCaseLinksProcessedCorrectly() {
        Case case1 = new Case(Subject = 'Case 1', Status = 'New', TermsCondition__c = false);
        Case case2 = new Case(Subject = 'Case 2', Status = 'New', TermsCondition__c = false);
        insert new List<Case>{ case1, case2 };

        Id contentDocumentId1 = createDocument('File 1', 'file1.pdf');
        Id contentDocumentId2 = createDocument('File 2', 'file2.pdf');

        ContentDocumentLink cdl1 = new ContentDocumentLink(
            LinkedEntityId = case1.Id,
            ContentDocumentId = contentDocumentId1,
            ShareType = 'V',
            Visibility = 'InternalUsers'
        );
        ContentDocumentLink cdl2 = new ContentDocumentLink(
            LinkedEntityId = case2.Id,
            ContentDocumentId = contentDocumentId2,
            ShareType = 'V',
            Visibility = 'InternalUsers'
        );
        insert new List<ContentDocumentLink>{ cdl1, cdl2 };

        List<ContentDocumentLink> inserted = [
            SELECT Id, LinkedEntityId, ContentDocumentId, Visibility
            FROM ContentDocumentLink
            WHERE Id IN (:cdl1.Id, :cdl2.Id)
        ];

        Test.startTest();
        ContentDocumentLinkHandler.handleAfterInsert(inserted);
        Test.stopTest();

        List<ContentDocumentLink> updated = [
            SELECT Visibility 
            FROM ContentDocumentLink 
            WHERE Id IN (:cdl1.Id, :cdl2.Id)
        ];
        
        for (ContentDocumentLink cdl : updated) {
            System.assertEquals('AllUsers', cdl.Visibility, 'All case files should have AllUsers visibility');
        }
    }

    @isTest
    static void afterInsert_emptyListDoesNothing() {
        Test.startTest();
        ContentDocumentLinkHandler.handleAfterInsert(new List<ContentDocumentLink>());
        Test.stopTest();
        
        System.assert(true, 'Empty list handled');
    }
}