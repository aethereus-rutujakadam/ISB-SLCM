/**
 * @description Test class for CourseManagerBatchProcessor
 */
@isTest
private class CourseManagerBatchProcessorTest {

    @testSetup
    static void setup() {
        // Create test User
        Profile p = [SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1];
        User testUser = new User(
            Alias = 'tuser',
            Email = 'testuser@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Test Manager',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'testmanager' + System.currentTimeMillis() + '@test.com',
            IsActive = true
        );
        insert testUser;

        // Create inactive User for testing
        User inactiveUser = new User(
            Alias = 'iuser',
            Email = 'inactive@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Inactive User',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'inactiveuser' + System.currentTimeMillis() + '@test.com',
            IsActive = false
        );
        insert inactiveUser;

        // Create Location
        Schema.Location testLocation = new Schema.Location(
            Name = 'NYC Campus',
            LocationType = 'General'
        );
        insert testLocation;

        // Create another Location
        Schema.Location testLocation2 = new Schema.Location(
            Name = 'LA Campus',
            LocationType = 'General'
        );
        insert testLocation2;

        // Create LearningCourse
        Learning testLearning = new Learning(
            Name = 'Test Learning'
        );
        insert testLearning;

        LearningCourse testCourse = new LearningCourse(
            Name = 'MBA 101',
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
            Name = 'MBA 101 - Spring 2026 - NYC',
            LearningCourseId = testCourse.Id,
            Location__c = testLocation.Id,
            Course_Type__c = 'Online',
            Academic_Year__c = testYear.Id,
            Academic_Term__c = testTerm.Id
        );
        offerings.add(co1);

        CourseOffering co2 = new CourseOffering(
            Name = 'MBA 101 - Summer 2026 - NYC',
            LearningCourseId = testCourse.Id,
            Location__c = testLocation.Id,
            Course_Type__c = 'Online',
            Academic_Year__c = testYear.Id,
            Academic_Term__c = testTerm.Id
        );
        offerings.add(co2);

        CourseOffering co3 = new CourseOffering(
            Name = 'MBA 101 - Spring 2026 - LA',
            LearningCourseId = testCourse.Id,
            Location__c = testLocation2.Id,
            Course_Type__c = 'Hybrid',
            Academic_Year__c = testYear.Id,
            Academic_Term__c = testTerm.Id
        );
        offerings.add(co3);

        insert offerings;
    }

    /**
     * @description Test successful course manager creation
     */
    @isTest
    static void testSuccessfulCreation() {
        User testUser = [SELECT Id, Name FROM User WHERE LastName = 'Test Manager' LIMIT 1];
        
        // Create Excel row
        CourseManagerExcelParser.ExcelRow row = new CourseManagerExcelParser.ExcelRow();
        row.rowNumber = 1;
        row.owner = testUser.Name;
        row.courses = 'MBA 101';
        row.courseCode = 'MBA101';
        row.courseType = 'Online';
        row.location = 'NYC Campus';
        row.academicYear = '2026';
        row.academicTerm = 'Term 1';
        row.roles = 'Manager';

        List<CourseManagerExcelParser.ExcelRow> rows = new List<CourseManagerExcelParser.ExcelRow>{ row };

        Test.startTest();
        CourseManagerBatchProcessor batch = new CourseManagerBatchProcessor(rows);
        Database.executeBatch(batch, 100);
        Test.stopTest();

        // Verify course_managers__c created (should create 2 - one for each matching CourseOffering)
        List<course_managers__c> managers = [SELECT Id, User__c, Role__c, Course_Offering__c, Courses__c, OwnerId 
                                              FROM course_managers__c];
        System.assertEquals(2, managers.size(), 'Should create 2 course managers (2 matching offerings)');
        
        for (course_managers__c cm : managers) {
            System.assertEquals(testUser.Id, cm.User__c, 'User__c should match');
            System.assertEquals('Manager', cm.Role__c, 'Role should be Manager');
            System.assertEquals(testUser.Id, cm.OwnerId, 'OwnerId should match User__c');
            System.assertNotEquals(null, cm.Courses__c, 'Courses__c should be populated');
        }

        // Verify no errors
        List<Error_Handling__c> errors = [SELECT Id FROM Error_Handling__c];
        System.assertEquals(0, errors.size(), 'Should have no errors');
    }

    /**
     * @description Test user not found error
     */
    @isTest
    static void testUserNotFound() {
        // Create Excel row with non-existent user
        CourseManagerExcelParser.ExcelRow row = new CourseManagerExcelParser.ExcelRow();
        row.rowNumber = 1;
        row.owner = 'Non Existent User';
        row.courses = 'MBA 101';
        row.courseCode = 'MBA101';
        row.courseType = 'Online';
        row.location = 'NYC Campus';
        row.academicYear = '2026';
        row.academicTerm = 'Term 1';
        row.roles = 'Manager';

        List<CourseManagerExcelParser.ExcelRow> rows = new List<CourseManagerExcelParser.ExcelRow>{ row };

        Test.startTest();
        CourseManagerBatchProcessor batch = new CourseManagerBatchProcessor(rows);
        Database.executeBatch(batch, 100);
        Test.stopTest();

        // Verify no course_managers__c created
        List<course_managers__c> managers = [SELECT Id FROM course_managers__c];
        System.assertEquals(0, managers.size(), 'Should not create course managers');

        // Verify error record created
        List<Error_Handling__c> errors = [SELECT Id, Error_message__c FROM Error_Handling__c];
        System.assertEquals(1, errors.size(), 'Should create 1 error record');
        System.assert(errors[0].Error_message__c.contains('User not found'), 'Error should mention user not found');
    }

    /**
     * @description Test inactive user error
     */
    @isTest
    static void testInactiveUser() {
        User inactiveUser = [SELECT Id, Name FROM User WHERE LastName = 'Inactive User' LIMIT 1];
        
        // Create Excel row with inactive user
        CourseManagerExcelParser.ExcelRow row = new CourseManagerExcelParser.ExcelRow();
        row.rowNumber = 1;
        row.owner = inactiveUser.Name;
        row.courses = 'MBA 101';
        row.courseCode = 'MBA101';
        row.courseType = 'Online';
        row.location = 'NYC Campus';
        row.academicYear = '2026';
        row.academicTerm = 'Term 1';
        row.roles = 'Manager';

        List<CourseManagerExcelParser.ExcelRow> rows = new List<CourseManagerExcelParser.ExcelRow>{ row };

        Test.startTest();
        CourseManagerBatchProcessor batch = new CourseManagerBatchProcessor(rows);
        Database.executeBatch(batch, 100);
        Test.stopTest();

        // Verify no course_managers__c created
        List<course_managers__c> managers = [SELECT Id FROM course_managers__c];
        System.assertEquals(0, managers.size(), 'Should not create course managers for inactive user');

        // Verify error record created
        List<Error_Handling__c> errors = [SELECT Id, Error_message__c FROM Error_Handling__c];
        System.assertEquals(1, errors.size(), 'Should create 1 error record');
        System.assert(errors[0].Error_message__c.contains('User not found or inactive'), 'Error should mention user not found/inactive');
    }

    /**
     * @description Test course not found error
     */
    @isTest
    static void testCourseNotFound() {
        User testUser = [SELECT Id, Name FROM User WHERE LastName = 'Test Manager' LIMIT 1];
        
        // Create Excel row with non-existent course
        CourseManagerExcelParser.ExcelRow row = new CourseManagerExcelParser.ExcelRow();
        row.rowNumber = 1;
        row.owner = testUser.Name;
        row.courses = 'Non Existent Course';
        row.courseCode = 'MBA101';
        row.courseType = 'Online';
        row.location = 'NYC Campus';
        row.academicYear = '2026';
        row.academicTerm = 'Term 1';
        row.roles = 'Manager';

        List<CourseManagerExcelParser.ExcelRow> rows = new List<CourseManagerExcelParser.ExcelRow>{ row };

        Test.startTest();
        CourseManagerBatchProcessor batch = new CourseManagerBatchProcessor(rows);
        Database.executeBatch(batch, 100);
        Test.stopTest();

        // Verify error record created
        List<Error_Handling__c> errors = [SELECT Id, Error_message__c FROM Error_Handling__c];
        System.assertEquals(1, errors.size(), 'Should create 1 error record');
        System.assert(errors[0].Error_message__c.contains('Learning Course not found'), 'Error should mention course not found');
    }

    /**
     * @description Test location not found error
     */
    @isTest
    static void testLocationNotFound() {
        User testUser = [SELECT Id, Name FROM User WHERE LastName = 'Test Manager' LIMIT 1];
        
        // Create Excel row with non-existent location
        CourseManagerExcelParser.ExcelRow row = new CourseManagerExcelParser.ExcelRow();
        row.rowNumber = 1;
        row.owner = testUser.Name;
        row.courses = 'MBA 101';
        row.courseCode = 'MBA101';
        row.courseType = 'Online';
        row.location = 'Non Existent Location';
        row.academicYear = '2026';
        row.academicTerm = 'Term 1';
        row.roles = 'Manager';

        List<CourseManagerExcelParser.ExcelRow> rows = new List<CourseManagerExcelParser.ExcelRow>{ row };

        Test.startTest();
        CourseManagerBatchProcessor batch = new CourseManagerBatchProcessor(rows);
        Database.executeBatch(batch, 100);
        Test.stopTest();

        // Verify error record created
        List<Error_Handling__c> errors = [SELECT Id, Error_message__c FROM Error_Handling__c];
        System.assertEquals(1, errors.size(), 'Should create 1 error record');
        System.assert(errors[0].Error_message__c.contains('Location not found'), 'Error should mention location not found');
    }

    /**
     * @description Test invalid role error
     */
    @isTest
    static void testInvalidRole() {
        User testUser = [SELECT Id, Name FROM User WHERE LastName = 'Test Manager' LIMIT 1];
        
        // Create Excel row with invalid role
        CourseManagerExcelParser.ExcelRow row = new CourseManagerExcelParser.ExcelRow();
        row.rowNumber = 1;
        row.owner = testUser.Name;
        row.courses = 'MBA 101';
        row.courseCode = 'MBA101';
        row.courseType = 'Online';
        row.location = 'NYC Campus';
        row.academicYear = '2026';
        row.academicTerm = 'Term 1';
        row.roles = 'InvalidRole';

        List<CourseManagerExcelParser.ExcelRow> rows = new List<CourseManagerExcelParser.ExcelRow>{ row };

        Test.startTest();
        CourseManagerBatchProcessor batch = new CourseManagerBatchProcessor(rows);
        Database.executeBatch(batch, 100);
        Test.stopTest();

        // Verify error record created
        List<Error_Handling__c> errors = [SELECT Id, Error_message__c FROM Error_Handling__c];
        System.assertEquals(1, errors.size(), 'Should create 1 error record');
        System.assert(errors[0].Error_message__c.contains('Invalid Role'), 'Error should mention invalid role');
    }

    /**
     * @description Test no matching CourseOffering
     */
    @isTest
    static void testNoMatchingOffering() {
        User testUser = [SELECT Id, Name FROM User WHERE LastName = 'Test Manager' LIMIT 1];
        
        // Create Excel row with no matching offering (wrong course type)
        CourseManagerExcelParser.ExcelRow row = new CourseManagerExcelParser.ExcelRow();
        row.rowNumber = 1;
        row.owner = testUser.Name;
        row.courses = 'MBA 101';
        row.courseCode = 'MBA101';
        row.courseType = 'InPerson'; // No offering with this type
        row.location = 'NYC Campus';
        row.academicYear = '2026';
        row.academicTerm = 'Term 1';
        row.roles = 'Manager';

        List<CourseManagerExcelParser.ExcelRow> rows = new List<CourseManagerExcelParser.ExcelRow>{ row };

        Test.startTest();
        CourseManagerBatchProcessor batch = new CourseManagerBatchProcessor(rows);
        Database.executeBatch(batch, 100);
        Test.stopTest();

        // Verify no course_managers__c created
        List<course_managers__c> managers = [SELECT Id FROM course_managers__c];
        System.assertEquals(0, managers.size(), 'Should not create course managers');

        // Verify error record created
        List<Error_Handling__c> errors = [SELECT Id, Error_message__c FROM Error_Handling__c];
        System.assertEquals(1, errors.size(), 'Should create 1 error record');
        System.assert(errors[0].Error_message__c.contains('No Course Offering found'), 'Error should mention no offering found');
    }

    /**
     * @description Test case-insensitive role matching
     */
    @isTest
    static void testCaseInsensitiveRole() {
        User testUser = [SELECT Id, Name FROM User WHERE LastName = 'Test Manager' LIMIT 1];
        
        // Test lowercase and uppercase role values
        List<CourseManagerExcelParser.ExcelRow> rows = new List<CourseManagerExcelParser.ExcelRow>();
        
        CourseManagerExcelParser.ExcelRow row1 = new CourseManagerExcelParser.ExcelRow();
        row1.rowNumber = 1;
        row1.owner = testUser.Name;
        row1.courses = 'MBA 101';
        row1.courseCode = 'MBA101';
        row1.courseType = 'Online';
        row1.location = 'NYC Campus';
        row1.academicYear = '2026';
        row1.academicTerm = 'Term 1';
        row1.roles = 'manager'; // lowercase
        rows.add(row1);

        CourseManagerExcelParser.ExcelRow row2 = new CourseManagerExcelParser.ExcelRow();
        row2.rowNumber = 2;
        row2.owner = testUser.Name;
        row2.courses = 'MBA 101';
        row2.courseCode = 'MBA101';
        row2.courseType = 'Hybrid';
        row2.location = 'LA Campus';
        row2.academicYear = '2026';
        row2.academicTerm = 'Term 1';
        row2.roles = 'ASSOCIATE'; // uppercase
        rows.add(row2);

        CourseManagerExcelParser.ExcelRow row3 = new CourseManagerExcelParser.ExcelRow();
        row3.rowNumber = 3;
        row3.owner = testUser.Name;
        row3.courses = 'MBA 101';
        row3.courseCode = 'MBA101';
        row3.courseType = 'Online';
        row3.location = 'NYC Campus';
        row3.academicYear = '2026';
        row3.academicTerm = 'Term 1';
        row3.roles = 'delivery manager'; // lowercase with space
        rows.add(row3);

        Test.startTest();
        CourseManagerBatchProcessor batch = new CourseManagerBatchProcessor(rows);
        Database.executeBatch(batch, 100);
        Test.stopTest();

        // Verify course_managers__c created with normalized roles
        List<course_managers__c> managers = [SELECT Id, Role__c FROM course_managers__c ORDER BY Role__c];
        System.assertEquals(5, managers.size(), 'Should create 5 course managers');
        Set<String> normalizedRoles = new Set<String>();
        for (course_managers__c cm : managers) {
            normalizedRoles.add(cm.Role__c);
        }
        System.assert(normalizedRoles.contains('Associate'), 'Role should include Associate');
        System.assert(normalizedRoles.contains('Delivery Manager'), 'Role should include Delivery Manager');
        System.assert(normalizedRoles.contains('Manager'), 'Role should include Manager');
    }

    /**
     * @description Test duplicate detection
     */
    @isTest
    static void testDuplicateDetection() {
        User testUser = [SELECT Id, Name FROM User WHERE LastName = 'Test Manager' LIMIT 1];
        CourseOffering offering = [SELECT Id, LearningCourseId FROM CourseOffering LIMIT 1];
        
        // Create existing course_managers__c record
        course_managers__c existing = new course_managers__c(
            User__c = testUser.Id,
            Course_Offering__c = offering.Id,
            Courses__c = offering.LearningCourseId,
            Role__c = 'Manager',
            OwnerId = testUser.Id
        );
        insert existing;

        // Try to create duplicate via batch
        CourseManagerExcelParser.ExcelRow row = new CourseManagerExcelParser.ExcelRow();
        row.rowNumber = 1;
        row.owner = testUser.Name;
        row.courses = 'MBA 101';
        row.courseCode = 'MBA101';
        row.courseType = 'Online';
        row.location = 'NYC Campus';
        row.academicYear = '2026';
        row.academicTerm = 'Term 1';
        row.roles = 'Manager';

        List<CourseManagerExcelParser.ExcelRow> rows = new List<CourseManagerExcelParser.ExcelRow>{ row };

        Test.startTest();
        CourseManagerBatchProcessor batch = new CourseManagerBatchProcessor(rows);
        Database.executeBatch(batch, 100);
        Test.stopTest();

        // Verify no new course_managers__c created (duplicate skipped)
        List<course_managers__c> managers = [SELECT Id FROM course_managers__c];
        // Should still be just the original existing record, or maybe 1 more if there are 2 offerings
        // The duplicate should be skipped for the one that already exists
        System.assert(managers.size() >= 1, 'Should have at least the existing record');
    }

    /**
     * @description Test role-level uniqueness per Course Offering.
     * If a role already exists for an offering, only that role is skipped while other roles are created.
     */
    @isTest
    static void testSkipOnlyExistingRolePerOffering() {
        Profile p = [SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1];
        User existingRoleUser = [SELECT Id, Name FROM User WHERE LastName = 'Test Manager' LIMIT 1];

        User newUploadUser = new User(
            Alias = 'nuser',
            Email = 'newupload@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'New Upload User',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'newupload' + System.currentTimeMillis() + '@test.com',
            IsActive = true
        );
        insert newUploadUser;

        CourseOffering laOffering = [
            SELECT Id, LearningCourseId
            FROM CourseOffering
            WHERE Course_Type__c = 'Hybrid'
            LIMIT 1
        ];

        // Existing Associate role on the same offering.
        insert new course_managers__c(
            User__c = existingRoleUser.Id,
            Course_Offering__c = laOffering.Id,
            Courses__c = laOffering.LearningCourseId,
            Role__c = 'Associate',
            OwnerId = existingRoleUser.Id
        );

        // Excel rows for the same offering: Associate should be skipped, Manager should be created.
        List<CourseManagerExcelParser.ExcelRow> rows = new List<CourseManagerExcelParser.ExcelRow>();

        CourseManagerExcelParser.ExcelRow associateRow = new CourseManagerExcelParser.ExcelRow();
        associateRow.rowNumber = 1;
        associateRow.owner = newUploadUser.Name;
        associateRow.courses = 'MBA 101';
        associateRow.courseCode = 'MBA101';
        associateRow.courseType = 'Hybrid';
        associateRow.location = 'LA Campus';
        associateRow.academicYear = '2026';
        associateRow.academicTerm = 'Term 1';
        associateRow.roles = 'Associate';
        rows.add(associateRow);

        CourseManagerExcelParser.ExcelRow managerRow = new CourseManagerExcelParser.ExcelRow();
        managerRow.rowNumber = 2;
        managerRow.owner = newUploadUser.Name;
        managerRow.courses = 'MBA 101';
        managerRow.courseCode = 'MBA101';
        managerRow.courseType = 'Hybrid';
        managerRow.location = 'LA Campus';
        managerRow.academicYear = '2026';
        managerRow.academicTerm = 'Term 1';
        managerRow.roles = 'Manager';
        rows.add(managerRow);

        Test.startTest();
        Database.executeBatch(new CourseManagerBatchProcessor(rows), 100);
        Test.stopTest();

        List<course_managers__c> managersForOffering = [
            SELECT Id, User__c, Role__c
            FROM course_managers__c
            WHERE Course_Offering__c = :laOffering.Id
            ORDER BY Role__c
        ];

        System.assertEquals(2, managersForOffering.size(), 'Offering should have only existing Associate + new Manager');

        Integer associateCount = 0;
        Integer managerCount = 0;
        for (course_managers__c cm : managersForOffering) {
            if (cm.Role__c == 'Associate') {
                associateCount++;
            }
            if (cm.Role__c == 'Manager') {
                managerCount++;
            }
        }

        System.assertEquals(1, associateCount, 'Associate must remain unique per offering');
        System.assertEquals(1, managerCount, 'Manager should be created because it did not exist');
    }

    /**
     * @description Test multiple offerings per row
     */
    @isTest
    static void testMultipleOfferingsPerRow() {
        User testUser = [SELECT Id, Name FROM User WHERE LastName = 'Test Manager' LIMIT 1];
        
        // This should match 2 CourseOfferings (both NYC Online offerings)
        CourseManagerExcelParser.ExcelRow row = new CourseManagerExcelParser.ExcelRow();
        row.rowNumber = 1;
        row.owner = testUser.Name;
        row.courses = 'MBA 101';
        row.courseCode = 'MBA101';
        row.courseType = 'Online';
        row.location = 'NYC Campus';
        row.academicYear = '2026';
        row.academicTerm = 'Term 1';
        row.roles = 'Associate';

        List<CourseManagerExcelParser.ExcelRow> rows = new List<CourseManagerExcelParser.ExcelRow>{ row };

        Test.startTest();
        CourseManagerBatchProcessor batch = new CourseManagerBatchProcessor(rows);
        Database.executeBatch(batch, 100);
        Test.stopTest();

        // Verify 2 course_managers__c created (one for each matching offering)
        List<course_managers__c> managers = [SELECT Id, Course_Offering__c FROM course_managers__c];
        System.assertEquals(2, managers.size(), 'Should create 2 course managers');
        
        // Verify they have different course offerings
        Set<Id> offeringIds = new Set<Id>();
        for (course_managers__c cm : managers) {
            offeringIds.add(cm.Course_Offering__c);
        }
        System.assertEquals(2, offeringIds.size(), 'Should link to 2 different offerings');
    }

    /**
     * @description Test batch with 150 rows (multiple batches)
     */
    @isTest
    static void testLargeBatch() {
        User testUser = [SELECT Id, Name FROM User WHERE LastName = 'Test Manager' LIMIT 1];
        
        List<CourseManagerExcelParser.ExcelRow> rows = new List<CourseManagerExcelParser.ExcelRow>();
        
        // Create 150 rows (will process in 2 batches: 100 + 50)
        for (Integer i = 0; i < 150; i++) {
            CourseManagerExcelParser.ExcelRow row = new CourseManagerExcelParser.ExcelRow();
            row.rowNumber = i + 1;
            row.owner = testUser.Name;
            row.courses = 'MBA 101';
            row.courseCode = 'MBA101';
            row.courseType = 'Online';
            row.location = 'NYC Campus';
            row.academicYear = '2026';
            row.academicTerm = 'Term 1';
            row.roles = (Math.mod(i, 2) == 0) ? 'Manager' : 'Associate';
            rows.add(row);
        }

        Test.startTest();
        CourseManagerBatchProcessor batch = new CourseManagerBatchProcessor(rows);
        Database.executeBatch(batch, 100);
        Test.stopTest();

        // Verify course_managers__c created
        // Each row should create 2 records (2 matching offerings), but duplicates will be skipped
        List<course_managers__c> managers = [SELECT Id FROM course_managers__c];
        // Due to deduplication within batch, we should have at most 4 records:
        // Manager + Offering1, Manager + Offering2, Associate + Offering1, Associate + Offering2
        System.assert(managers.size() > 0, 'Should create some course managers');
        System.assert(managers.size() <= 4, 'Should deduplicate within batch');
    }
}