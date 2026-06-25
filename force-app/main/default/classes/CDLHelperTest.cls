@IsTest
public class CDLHelperTest {

    /* ----------------------------------------------------------
       Utility: Create ContentDocument via ContentVersion
       ---------------------------------------------------------- */
    private static Id createContentDocument() {
        ContentVersion cv = new ContentVersion(
            Title = 'Test File',
            PathOnClient = 'TestFile.txt',
            VersionData = Blob.valueOf('Test content')
        );
        insert cv;

        // Fetch ContentDocumentId
        return [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
        ].ContentDocumentId;
    }

    /* ----------------------------------------------------------
       TEST 1: SUCCESSFUL ContentDocumentLink CREATION
       ---------------------------------------------------------- */
    @IsTest
    static void testCreateCDL_success() {

        // Arrange
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Id contentDocId = createContentDocument();

        CDLHelper.Request req = new CDLHelper.Request();
        req.contentDocumentId = contentDocId;
        req.linkedEntityId = acc.Id;

        List<CDLHelper.Request> requests =
            new List<CDLHelper.Request>{ req };

        // Act
        Test.startTest();
        CDLHelper.createCDL(requests);
        Test.stopTest();

        // Assert
        List<ContentDocumentLink> cdls = [
            SELECT Id, ContentDocumentId, LinkedEntityId, ShareType, Visibility
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :acc.Id
        ];

        System.assertEquals(1, cdls.size());
        System.assertEquals(contentDocId, cdls[0].ContentDocumentId);
        System.assertEquals('V', cdls[0].ShareType);
        System.assertEquals('AllUsers', cdls[0].Visibility);
    }

    /* ----------------------------------------------------------
       TEST 2: NULL REQUEST OBJECT HANDLING
       ---------------------------------------------------------- */
    @IsTest
    static void testCreateCDL_nullRequest() {

        List<CDLHelper.Request> requests =
            new List<CDLHelper.Request>{ null };

        Test.startTest();
        CDLHelper.createCDL(requests);
        Test.stopTest();

        // No exception = PASS
        System.assert(true);
    }

    /* ----------------------------------------------------------
       TEST 3: NULL FIELD VALUES HANDLING
       ---------------------------------------------------------- */
    @IsTest
    static void testCreateCDL_nullFields() {

        CDLHelper.Request req = new CDLHelper.Request();
        req.contentDocumentId = null;
        req.linkedEntityId = null;

        Test.startTest();
        CDLHelper.createCDL(new List<CDLHelper.Request>{ req });
        Test.stopTest();

        // No exception = PASS
        System.assert(true);
    }

    /* ----------------------------------------------------------
       TEST 4: EMPTY LIST
       ---------------------------------------------------------- */
    @IsTest
    static void testCreateCDL_emptyList() {

        Test.startTest();
        CDLHelper.createCDL(new List<CDLHelper.Request>());
        Test.stopTest();

        System.assert(true);
    }

    /* ----------------------------------------------------------
       TEST 5: NULL LIST
       ---------------------------------------------------------- */
    @IsTest
    static void testCreateCDL_nullList() {

        Test.startTest();
        CDLHelper.createCDL(null);
        Test.stopTest();

        System.assert(true);
    }
}