@isTest
public class FilePreviewControllerTest {

    @isTest
    static void testGetContentDocumentId() {
        // 1. Create content data
        ContentVersion cv = new ContentVersion(
            Title = 'Test Document',
            PathOnClient = 'TestDocument.pdf',
            VersionData = Blob.valueOf('Test Content Data'),
            IsMajorVersion = true
        );
        insert cv;
        
        // 2. Retrieve ContentDocumentId that was automatically created
        Id expectedContentDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
        
        // 3. Call current controller functionality
        Test.startTest();
        Id actualContentDocId = FilePreviewController.getContentDocumentId(cv.Id);
        Test.stopTest();
        
        // 4. Assertions
        System.assertEquals(expectedContentDocId, actualContentDocId, 'The retrieved ContentDocumentId should match the one from ContentVersion');
    }
    
    @isTest
    static void testGetContentDocumentIdWithInvalidId() {
        // Test error handling for non-existent ID
        Boolean exceptionThrown = false;
        try {
            FilePreviewController.getContentDocumentId(null);
        } catch (Exception e) {
            exceptionThrown = true;
        }
        
        // Depending on valid API inputs, null might cause QueryException or invalid ID error
        // Current implementation does [SELECT ...] WHERE Id = :param
        // If param is null, it returns 0 rows -> List has no rows for assignment
        System.assert(exceptionThrown, 'Should throw an exception when ID is null or invalid');
    }
}