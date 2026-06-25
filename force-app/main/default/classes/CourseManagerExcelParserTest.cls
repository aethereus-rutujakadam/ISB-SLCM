/**
 * @description Test class for CourseManagerExcelParser
 */
@isTest
private class CourseManagerExcelParserTest {

    @testSetup
    static void setup() {
        // Create test data
        
        // Create User
        Profile p = [SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1];
        User testUser = new User(
            Alias = 'tuser',
            Email = 'testuser@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Test User',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'testcoursemanager' + System.currentTimeMillis() + '@test.com',
            IsActive = true
        );
        insert testUser;

        // Create Location
        Schema.Location testLocation = new Schema.Location(
            Name = 'Test Location',
            LocationType = 'General'
        );
        insert testLocation;

        Learning testLearning = new Learning(
            Name = 'Test Learning'
        );
        insert testLearning;

        // Create LearningCourse
        LearningCourse testCourse = new LearningCourse(
            Name = 'Test Course MBA 101',
            LearningId = testLearning.Id,
            SubjectAbbreviation = 'MBA101'
        );
        insert testCourse;

        AcademicYear testYear = new AcademicYear(Name = '2026');
        insert testYear;

        AcademicTerm testTerm = new AcademicTerm(Name = 'Term 1');
        insert testTerm;

        // Create CourseOfferings
        List<CourseOffering> offerings = new List<CourseOffering>();
        
        CourseOffering co1 = new CourseOffering(
            Name = 'MBA 101 - Spring 2026 - Test Location',
            LearningCourseId = testCourse.Id,
            Location__c = testLocation.Id,
            Course_Type__c = 'Online',
            Academic_Year__c = testYear.Id,
            Academic_Term__c = testTerm.Id
        );
        offerings.add(co1);

        CourseOffering co2 = new CourseOffering(
            Name = 'MBA 101 - Summer 2026 - Test Location',
            LearningCourseId = testCourse.Id,
            Location__c = testLocation.Id,
            Course_Type__c = 'Online',
            Academic_Year__c = testYear.Id,
            Academic_Term__c = testTerm.Id
        );
        offerings.add(co2);

        insert offerings;
    }

    /**
     * @description Test valid upload with matching CourseOfferings
     */
    @isTest
    static void testValidUpload() {
        User testUser = [SELECT Id, Name FROM User WHERE LastName = 'Test User' LIMIT 1];
        
        // Build JSON with valid data
        String jsonData = '[{' +
            '"Owner": "' + testUser.Name + '",' +
            '"Courses": "Test Course MBA 101",' +
            '"CourseCode": "MBA101",' +
            '"CourseType": "Online",' +
            '"Location": "Test Location",' +
            '"AcademicYear": "2026",' +
            '"AcademicTerm": "Term 1",' +
            '"Roles": "Manager"' +
        '}]';

        Test.startTest();
        CourseManagerExcelParser.ParseResult result = CourseManagerExcelParser.parseFromJson(jsonData);
        Test.stopTest();

        System.assertEquals(true, result.isSuccess, 'Upload should succeed');
        System.assertEquals(1, result.totalRowsSubmitted, 'Should have 1 row submitted');
        System.assertNotEquals(null, result.batchJobId, 'Batch job ID should be set');
        System.assertEquals(0, result.errors.size(), 'Should have no errors');
    }

    /**
     * @description Test empty JSON
     */
    @isTest
    static void testEmptyJson() {
        Test.startTest();
        CourseManagerExcelParser.ParseResult result = CourseManagerExcelParser.parseFromJson('');
        Test.stopTest();

        System.assertEquals(false, result.isSuccess, 'Should fail with empty JSON');
        System.assertEquals(1, result.errors.size(), 'Should have 1 error');
        System.assert(result.errors[0].contains('No data received'), 'Error message should mention no data');
    }

    /**
     * @description Test missing required fields
     */
    @isTest
    static void testMissingRequiredFields() {
        String jsonData = '[{' +
            '"Owner": "Test User",' +
            '"Courses": "",' + // Missing Courses
            '"CourseCode": "MBA101",' +
            '"CourseType": "Online",' +
            '"Location": "Test Location",' +
            '"AcademicYear": "2026",' +
            '"AcademicTerm": "Term 1",' +
            '"Roles": "Manager"' +
        '}]';

        Test.startTest();
        CourseManagerExcelParser.ParseResult result = CourseManagerExcelParser.parseFromJson(jsonData);
        Test.stopTest();

        System.assertEquals(false, result.isSuccess, 'Should fail with missing required fields');
        System.assertEquals(1, result.warnings.size(), 'Should have 1 warning');
        System.assert(result.warnings[0].contains('Courses is required'), 'Warning should mention Courses');
    }

    /**
     * @description Test case-insensitive column names
     */
    @isTest
    static void testCaseInsensitiveColumns() {
        User testUser = [SELECT Id, Name FROM User WHERE LastName = 'Test User' LIMIT 1];
        
        // Use lowercase column names
        String jsonData = '[{' +
            '"owner": "' + testUser.Name + '",' +
            '"courses": "Test Course MBA 101",' +
            '"coursecode": "MBA101",' +
            '"coursetype": "Online",' +
            '"location": "Test Location",' +
            '"academicyear": "2026",' +
            '"academicterm": "Term 1",' +
            '"roles": "manager"' + // lowercase role value
        '}]';

        Test.startTest();
        CourseManagerExcelParser.ParseResult result = CourseManagerExcelParser.parseFromJson(jsonData);
        Test.stopTest();

        System.assertEquals(true, result.isSuccess, 'Should succeed with lowercase columns');
        System.assertEquals(1, result.totalRowsSubmitted, 'Should have 1 row submitted');
    }

    /**
     * @description Test duplicate rows within file
     */
    @isTest
    static void testDuplicateRowsInFile() {
        User testUser = [SELECT Id, Name FROM User WHERE LastName = 'Test User' LIMIT 1];
        
        // Two identical rows
        String jsonData = '[' +
            '{' +
                '"Owner": "' + testUser.Name + '",' +
                '"Courses": "Test Course MBA 101",' +
                '"CourseCode": "MBA101",' +
                '"CourseType": "Online",' +
                '"Location": "Test Location",' +
                '"AcademicYear": "2026",' +
                '"AcademicTerm": "Term 1",' +
                '"Roles": "Manager"' +
            '},' +
            '{' +
                '"Owner": "' + testUser.Name + '",' +
                '"Courses": "Test Course MBA 101",' +
                '"CourseCode": "MBA101",' +
                '"CourseType": "Online",' +
                '"Location": "Test Location",' +
                '"AcademicYear": "2026",' +
                '"AcademicTerm": "Term 1",' +
                '"Roles": "Manager"' +
            '}' +
        ']';

        Test.startTest();
        CourseManagerExcelParser.ParseResult result = CourseManagerExcelParser.parseFromJson(jsonData);
        Test.stopTest();

        System.assertEquals(true, result.isSuccess, 'Should succeed');
        System.assertEquals(1, result.totalRowsSubmitted, 'Should only submit 1 row (duplicate removed)');
        System.assertEquals(1, result.warnings.size(), 'Should have 1 warning for duplicate');
        System.assert(result.warnings[0].contains('Duplicate row detected'), 'Warning should mention duplicate');
    }

    /**
     * @description Test controller method
     */
    @isTest
    static void testControllerMethod() {
        User testUser = [SELECT Id, Name FROM User WHERE LastName = 'Test User' LIMIT 1];
        
        String jsonData = '[{' +
            '"Owner": "' + testUser.Name + '",' +
            '"Courses": "Test Course MBA 101",' +
            '"CourseCode": "MBA101",' +
            '"CourseType": "Online",' +
            '"Location": "Test Location",' +
            '"AcademicYear": "2026",' +
            '"AcademicTerm": "Term 1",' +
            '"Roles": "Manager"' +
        '}]';

        Test.startTest();
        CourseManagerExcelParser.ParseResult result = CourseManagerUploadController.uploadCourseManagers(jsonData);
        Test.stopTest();

        System.assertEquals(true, result.isSuccess, 'Controller should succeed');
        System.assertNotEquals(null, result.batchJobId, 'Batch job should be started');
    }

    /**
     * @description Test with null JSON
     */
    @isTest
    static void testNullJson() {
        Test.startTest();
        CourseManagerExcelParser.ParseResult result = CourseManagerExcelParser.parseFromJson(null);
        Test.stopTest();

        System.assertEquals(false, result.isSuccess, 'Should fail with null JSON');
        System.assertEquals(1, result.errors.size(), 'Should have 1 error');
    }

    /**
     * @description Test with all fields blank
     */
    @isTest
    static void testAllFieldsBlank() {
        String jsonData = '[{' +
            '"Owner": "",' +
            '"Courses": "",' +
            '"CourseCode": "",' +
            '"CourseType": "",' +
            '"Location": "",' +
            '"AcademicYear": "",' +
            '"AcademicTerm": "",' +
            '"Roles": ""' +
        '}]';

        Test.startTest();
        CourseManagerExcelParser.ParseResult result = CourseManagerExcelParser.parseFromJson(jsonData);
        Test.stopTest();

        System.assertEquals(false, result.isSuccess, 'Should fail with all blank fields');
        System.assert(result.warnings.size() > 0, 'Should have warnings');
    }
}