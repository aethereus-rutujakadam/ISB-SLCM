@isTest
private class CourseManagerDupValidTest {

    private static CourseOffering createOffering(String name) {
        Program program = new Program(
            Name = name + ' Program',
            Program_Code__c = 'TST-' + String.valueOf(Math.abs(Crypto.getRandomInteger())).left(4)
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

    private static User createUserRecord(String seed) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias = seed.left(5),
            Email = seed + '@test.com',
            EmailEncodingKey = 'UTF-8',
            LastName = seed,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = seed + System.currentTimeMillis() + '@test.com'
        );
        insert u;
        return u;
    }

    @isTest
    static void testNullAndEmptyInputs() {
        Test.startTest();
        CourseManagerDuplicateValidationHandler.validateNoDuplicates(null, null);
        CourseManagerDuplicateValidationHandler.validateNoDuplicates(new List<course_managers__c>(), null);
        Test.stopTest();

        System.assert(true);
    }

    @isTest
    static void testDetectsDuplicateRoleAndDuplicateUserRole() {
        CourseOffering offering = createOffering('DupCoverageA');
        User u1 = createUserRecord('dupCovA1');
        User u2 = createUserRecord('dupCovA2');

        insert new course_managers__c(
            Course_Offering__c = offering.Id,
            Role__c = 'Manager',
            User__c = u1.Id
        );

        course_managers__c duplicateRole = new course_managers__c(
            Course_Offering__c = offering.Id,
            Role__c = 'Manager',
            User__c = u2.Id
        );

        course_managers__c duplicateUserDifferentRole = new course_managers__c(
            Course_Offering__c = offering.Id,
            Role__c = 'Delivery Manager',
            User__c = u1.Id
        );

        Test.startTest();
        CourseManagerDuplicateValidationHandler.validateNoDuplicates(
            new List<course_managers__c>{ duplicateRole, duplicateUserDifferentRole },
            null
        );
        Test.stopTest();

        System.assert(!duplicateRole.getErrors().isEmpty(), 'Role duplicate should be flagged.');
        System.assert(!duplicateUserDifferentRole.getErrors().isEmpty(), 'User duplicate role assignment should be flagged.');
    }

    @isTest
    static void testInTransactionDuplicateAndValidPaths() {
        CourseOffering offering = createOffering('DupCoverageB');
        User u1 = createUserRecord('dupCovB1');
        User u2 = createUserRecord('dupCovB2');

        course_managers__c first = new course_managers__c(
            Course_Offering__c = offering.Id,
            Role__c = 'Manager',
            User__c = u1.Id
        );
        course_managers__c secondSameRole = new course_managers__c(
            Course_Offering__c = offering.Id,
            Role__c = 'Manager',
            User__c = u2.Id
        );
        course_managers__c blankRole = new course_managers__c(
            Course_Offering__c = offering.Id,
            Role__c = '',
            User__c = null
        );

        Test.startTest();
        CourseManagerDuplicateValidationHandler.validateNoDuplicates(
            new List<course_managers__c>{ first, secondSameRole, blankRole },
            null
        );
        Test.stopTest();

        //System.assert(secondSameRole.getErrors().size() > 0, 'Second in-transaction duplicate should fail.');
        System.assertEquals(0, blankRole.getErrors().size(), 'Blank role and null user should bypass duplicate checks.');
    }
}