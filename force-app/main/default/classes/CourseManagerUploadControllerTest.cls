@isTest
private class CourseManagerUploadControllerTest {

    @isTest
    static void testUploadCourseManagersInvalidJsonReturnsErrorResult() {
        Test.startTest();
        CourseManagerExcelParser.ParseResult result =
            CourseManagerUploadController.uploadCourseManagers('{invalid json');
        Test.stopTest();

        System.assertNotEquals(null, result, 'Controller should return a parse result for malformed payload.');
        System.assertEquals(false, result.isSuccess, 'Malformed payload should not be treated as successful upload.');
        System.assert(result.errors != null && !result.errors.isEmpty(), 'Expected parsing error list for malformed payload.');
    }

    @isTest
    static void testUploadCourseManagersEmptyArrayReturnsResult() {
        Test.startTest();
        CourseManagerExcelParser.ParseResult result =
            CourseManagerUploadController.uploadCourseManagers('[]');
        Test.stopTest();

        System.assertNotEquals(null, result, 'Controller should return a parse result for empty payload.');
        System.assertEquals(false, result.isSuccess, 'Empty payload should not be treated as successful upload.');
        System.assert(result.errors != null && !result.errors.isEmpty(), 'Expected validation error list for empty payload.');
    }
}