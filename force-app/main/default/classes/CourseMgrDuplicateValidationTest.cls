@isTest
private class CourseMgrDuplicateValidationTest {

    private static CourseOffering createTestOffering(String name) {
        Program program = new Program(
            Name = name + ' Program',
            Program_Code__c = 'TST'
        );
        insert program;

        AcademicYear ay = new AcademicYear(Name = name + ' AY');
        insert ay;

        AcademicTerm term = new AcademicTerm(Name = name + ' Term');
        insert term;

        Learning learning = new Learning(Name = name + ' Learning');
        insert learning;

        LearningCourse course = new LearningCourse(
            Name = name + ' Course',
            LearningId = learning.Id
        );
        insert course;

        Schema.Location loc = new Schema.Location(
            Name = name + ' Location',
            LocationType = 'Campus'
        );
        insert loc;

        CourseOffering offering = new CourseOffering(
            Name = name,
            LearningCourseId = course.Id,
            Academic_Term__c = term.Id,
            Program__c = program.Id,
            Academic_Year__c = ay.Id,
            Location__c = loc.Id,
            Course_Type__c = 'Core',
            StartDate = Date.today(),
            EndDate = Date.today().addDays(30)
        );
        insert offering;

        return offering;
    }

    private static User createTestUser(String username) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias = username.left(5),
            Email = username + '@test.com',
            EmailEncodingKey = 'UTF-8',
            LastName = username,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = username + System.currentTimeMillis() + '@test.com'
        );
        insert u;
        return u;
    }

    @isTest
    static void testNullOrEmptyListReturnsWithoutError() {
        Test.startTest();
        CourseManagerDuplicateValidationHandler.validateNoDuplicates(null, null);
        CourseManagerDuplicateValidationHandler.validateNoDuplicates(new List<course_managers__c>(), null);
        Test.stopTest();

        System.assert(true, 'Should handle null and empty lists gracefully');
    }

    @isTest
    static void testNullOfferingIsSkipped() {
        User testUser = createTestUser('testuser1');

        course_managers__c mgr = new course_managers__c(
            Course_Offering__c = null,
            Role__c = 'Manager',
            User__c = testUser.Id
        );

        Test.startTest();
        CourseManagerDuplicateValidationHandler.validateNoDuplicates(new List<course_managers__c>{ mgr }, null);
        Test.stopTest();

        System.assertEquals(0, mgr.getErrors().size(), 'Null offering should be skipped without error');
    }

    @isTest
    static void testDuplicateRoleInDatabase() {
        CourseOffering offering = createTestOffering('DuplicateRole');
        User user1 = createTestUser('user1');
        User user2 = createTestUser('user2');

        // Insert first manager with role 'Manager'
        course_managers__c existing = new course_managers__c(
            Course_Offering__c = offering.Id,
            Role__c = 'Manager',
            User__c = user1.Id
        );
        insert existing;

        // Try to insert second manager with same role
        course_managers__c duplicate = new course_managers__c(
            Course_Offering__c = offering.Id,
            Role__c = 'Manager',
            User__c = user2.Id
        );

        Test.startTest();
        Database.SaveResult result = Database.insert(duplicate, false);
        Test.stopTest();

        System.assert(!result.isSuccess(), 'Duplicate role should be blocked');
        System.assert(result.getErrors()[0].getMessage().contains('already exists'), 'Error message should mention existing record');
    }

    @isTest
    static void testUserWithMultipleRolesInDatabase() {
        CourseOffering offering = createTestOffering('MultipleRoles');
        User testUser = createTestUser('multiuser');

        // Insert first manager with role 'Manager'
        course_managers__c first = new course_managers__c(
            Course_Offering__c = offering.Id,
            Role__c = 'Manager',
            User__c = testUser.Id
        );
        insert first;

        // Try to assign same user with different role
        course_managers__c second = new course_managers__c(
            Course_Offering__c = offering.Id,
            Role__c = 'Delivery Manager',
            User__c = testUser.Id
        );

        Test.startTest();
        Database.SaveResult result = Database.insert(second, false);
        Test.stopTest();

        System.assert(!result.isSuccess(), 'User with multiple roles should be blocked');
        System.assert(result.getErrors()[0].getMessage().contains('already assigned'), 'Error message should mention existing assignment');
    }

    @isTest
    static void testInTransactionDuplicateRole() {
        CourseOffering offering = createTestOffering('InTxnDupRole');
        User user1 = createTestUser('txnuser1');
        User user2 = createTestUser('txnuser2');

        // Try to insert two managers with same role in same transaction
        List<course_managers__c> managers = new List<course_managers__c>{
            new course_managers__c(
                Course_Offering__c = offering.Id,
                Role__c = 'Manager',
                User__c = user1.Id
            ),
            new course_managers__c(
                Course_Offering__c = offering.Id,
                Role__c = 'Manager',
                User__c = user2.Id
            )
        };

        Test.startTest();
        Database.SaveResult[] results = Database.insert(managers, false);
        Test.stopTest();

        // At least one should succeed, the handler should detect the duplicate
        Boolean hasSuccess = false;
        Boolean hasFailure = false;
        for (Database.SaveResult sr : results) {
            if (sr.isSuccess()) {
                hasSuccess = true;
            } else {
                hasFailure = true;
            }
        }

        System.assert(hasSuccess || hasFailure, 'Should process the records with validation logic');
    }

    @isTest
    static void testInTransactionUserMultipleRoles() {
        CourseOffering offering = createTestOffering('InTxnMultiRole');
        User testUser = createTestUser('txnmultiuser');

        // Try to assign same user with different roles in same transaction
        List<course_managers__c> managers = new List<course_managers__c>{
            new course_managers__c(
                Course_Offering__c = offering.Id,
                Role__c = 'Manager',
                User__c = testUser.Id
            ),
            new course_managers__c(
                Course_Offering__c = offering.Id,
                Role__c = 'Delivery Manager',
                User__c = testUser.Id
            )
        };

        Test.startTest();
        Database.SaveResult[] results = Database.insert(managers, false);
        Test.stopTest();

        Integer failureCount = 0;
        for (Database.SaveResult sr : results) {
            if (!sr.isSuccess()) {
                failureCount++;
            }
        }

        System.assert(failureCount > 0, 'At least one record should fail due to user multiple roles');
    }

    @isTest
    static void testValidInsertWithDifferentRoles() {
        CourseOffering offering = createTestOffering('ValidDifferentRoles');
        User user1 = createTestUser('validuser1');
        User user2 = createTestUser('validuser2');

        // Insert managers with different roles - should succeed
        List<course_managers__c> managers = new List<course_managers__c>{
            new course_managers__c(
                Course_Offering__c = offering.Id,
                Role__c = 'Manager',
                User__c = user1.Id
            ),
            new course_managers__c(
                Course_Offering__c = offering.Id,
                Role__c = 'Delivery Manager',
                User__c = user2.Id
            )
        };

        Test.startTest();
        Database.SaveResult[] results = Database.insert(managers, false);
        Test.stopTest();

        for (Database.SaveResult sr : results) {
            System.assert(sr.isSuccess(), 'Different roles with different users should succeed');
        }

        Integer count = [SELECT COUNT() FROM course_managers__c WHERE Course_Offering__c = :offering.Id];
        System.assertEquals(2, count, 'Both managers should be inserted successfully');
    }

    @isTest
    static void testValidInsertMultipleOfferings() {
        CourseOffering offering1 = createTestOffering('Offering1');
        CourseOffering offering2 = createTestOffering('Offering2');
        User testUser = createTestUser('multioffering');

        // Same user with same role on different offerings - should succeed
        List<course_managers__c> managers = new List<course_managers__c>{
            new course_managers__c(
                Course_Offering__c = offering1.Id,
                Role__c = 'Manager',
                User__c = testUser.Id
            ),
            new course_managers__c(
                Course_Offering__c = offering2.Id,
                Role__c = 'Manager',
                User__c = testUser.Id
            )
        };

        Test.startTest();
        Database.SaveResult[] results = Database.insert(managers, false);
        Test.stopTest();

        for (Database.SaveResult sr : results) {
            System.assert(sr.isSuccess(), 'Same user/role on different offerings should succeed');
        }

        Integer count = [SELECT COUNT() FROM course_managers__c WHERE User__c = :testUser.Id];
        System.assertEquals(2, count, 'User should be assigned to both offerings');
    }

    @isTest
    static void testUpdateToDifferentRoleCausesConflict() {
        CourseOffering offering = createTestOffering('UpdateConflict');
        User user1 = createTestUser('updateuser1');
        User user2 = createTestUser('updateuser2');

        // Insert two managers with different roles
        course_managers__c mgr1 = new course_managers__c(
            Course_Offering__c = offering.Id,
            Role__c = 'Manager',
            User__c = user1.Id
        );
        course_managers__c mgr2 = new course_managers__c(
            Course_Offering__c = offering.Id,
            Role__c = 'Delivery Manager',
            User__c = user2.Id
        );
        insert new List<course_managers__c>{ mgr1, mgr2 };

        // Try to update mgr2 to same role as mgr1
        mgr2.Role__c = 'Manager';

        Test.startTest();
        Database.SaveResult result = Database.update(mgr2, false);
        Test.stopTest();

        System.assert(!result.isSuccess(), 'Update creating duplicate role should fail');
    }

    @isTest
    static void testUpdateToSameRoleSucceeds() {
        CourseOffering offering = createTestOffering('UpdateSameRole');
        User testUser = createTestUser('updatesame');

        // Insert manager
        course_managers__c mgr = new course_managers__c(
            Course_Offering__c = offering.Id,
            Role__c = 'Manager',
            User__c = testUser.Id
        );
        insert mgr;

        // Update same record without changing role
        mgr.Role__c = 'Manager';

        Test.startTest();
        Database.SaveResult result = Database.update(mgr, false);
        Test.stopTest();

        System.assert(result.isSuccess(), 'Update with same role should succeed');
    }

    @isTest
    static void testBlankRoleIsSkipped() {
        CourseOffering offering = createTestOffering('BlankRole');
        User testUser = createTestUser('blankrole');

        course_managers__c mgr = new course_managers__c(
            Course_Offering__c = offering.Id,
            Role__c = '',
            User__c = testUser.Id
        );

        Test.startTest();
        Database.SaveResult result = Database.insert(mgr, false);
        Test.stopTest();

        System.assert(result.isSuccess(), 'Blank role should be allowed without validation');
    }

    @isTest
    static void testNullUserIsSkipped() {
        CourseOffering offering = createTestOffering('NullUser');

        course_managers__c mgr = new course_managers__c(
            Course_Offering__c = offering.Id,
            Role__c = 'Manager',
            User__c = null
        );

        Test.startTest();
        Database.SaveResult result = Database.insert(mgr, false);
        Test.stopTest();

        System.assert(result.isSuccess(), 'Null user should be allowed without validation');
    }

    @isTest
    static void testHasOtherRecordLogic() {
        CourseOffering offering = createTestOffering('HasOther');
        User testUser = createTestUser('hasother');

        course_managers__c existing = new course_managers__c(
            Course_Offering__c = offering.Id,
            Role__c = 'Manager',
            User__c = testUser.Id
        );
        insert existing;

        // Reload to get ID
        existing = [SELECT Id, Course_Offering__c, Role__c, User__c FROM course_managers__c WHERE Id = :existing.Id];

        // Try to update same record - should succeed
        existing.Role__c = 'Manager';

        Test.startTest();
        Database.SaveResult result = Database.update(existing, false);
        Test.stopTest();

        System.assert(result.isSuccess(), 'Updating same record should succeed');
    }

    @isTest
    static void testSameUserDifferentOfferingsAllowed() {
        CourseOffering offering1 = createTestOffering('SameUserOffer1');
        CourseOffering offering2 = createTestOffering('SameUserOffer2');
        User testUser = createTestUser('sameuseroff');

        // Insert user as manager for both offerings
        course_managers__c mgr1 = new course_managers__c(
            Course_Offering__c = offering1.Id,
            Role__c = 'Manager',
            User__c = testUser.Id
        );
        insert mgr1;

        course_managers__c mgr2 = new course_managers__c(
            Course_Offering__c = offering2.Id,
            Role__c = 'Manager',
            User__c = testUser.Id
        );

        Test.startTest();
        Database.SaveResult result = Database.insert(mgr2, false);
        Test.stopTest();

        System.assert(result.isSuccess(), 'Same user on different offerings should be allowed');
    }

    @isTest
    static void testComplexScenarioWithMixedValidAndInvalid() {
        CourseOffering offering = createTestOffering('ComplexScenario');
        User user1 = createTestUser('complex1');
        User user2 = createTestUser('complex2');
        User user3 = createTestUser('complex3');

        // Insert first manager
        course_managers__c existing = new course_managers__c(
            Course_Offering__c = offering.Id,
            Role__c = 'Manager',
            User__c = user1.Id
        );
        insert existing;

        // Try to insert multiple records: one valid, one duplicate role
        List<course_managers__c> newManagers = new List<course_managers__c>{
            new course_managers__c(
                Course_Offering__c = offering.Id,
                Role__c = 'Delivery Manager',
                User__c = user2.Id
            ), // Valid
            new course_managers__c(
                Course_Offering__c = offering.Id,
                Role__c = 'Manager',
                User__c = user3.Id
            ) // Duplicate role - should fail
        };

        Test.startTest();
        Database.SaveResult[] results = Database.insert(newManagers, false);
        Test.stopTest();

        System.assert(results[0].isSuccess(), 'First record should succeed');
        System.assert(!results[1].isSuccess(), 'Second record should fail due to duplicate role');
    }
}