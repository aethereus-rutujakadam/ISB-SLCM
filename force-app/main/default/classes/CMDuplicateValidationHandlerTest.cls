@isTest
private class CMDuplicateValidationHandlerTest {

    private static CourseOffering createOffering(String offeringName) {
        Program program = new Program(
            Name = offeringName + ' Program',
            Program_Code__c = 'PGP'
        );
        insert program;

        AcademicYear ay = new AcademicYear(Name = offeringName + ' AY');
        insert ay;

        AcademicTerm term = new AcademicTerm(Name = offeringName + ' Term');
        insert term;

        Learning learning = new Learning(Name = offeringName + ' Learning');
        insert learning;

        LearningCourse course = new LearningCourse(
            Name = offeringName + ' Course',
            LearningId = learning.Id
        );
        insert course;

        Schema.Location loc = new Schema.Location(
            Name = offeringName + ' Location',
            LocationType = 'Campus'
        );
        insert loc;

        CourseOffering offering = new CourseOffering(
            Name = offeringName,
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

    private static User createUser(String prefix) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias = prefix.left(5),
            Email = prefix + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = prefix,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = prefix + DateTime.now().getTime() + '@example.com'
        );
        insert u;
        return u;
    }

    @isTest
    static void testDuplicateRoleAgainstExistingRecord() {
        CourseOffering offering = createOffering('DupRole');
        User u1 = createUser('cmdup1');
        User u2 = createUser('cmdup2');

        insert new course_managers__c(
            Course_Offering__c = offering.Id,
            Role__c = 'Manager',
            User__c = u1.Id
        );

        course_managers__c incoming = new course_managers__c(
            Course_Offering__c = offering.Id,
            Role__c = 'Manager',
            User__c = u2.Id
        );

        CourseManagerDuplicateValidationHandler.validateNoDuplicates(
            new List<course_managers__c>{ incoming },
            null
        );

        System.assert(incoming.getErrors().size() > 0, 'Expected duplicate role validation error.');
    }

    @isTest
    static void testUserCannotHoldMultipleRolesSameOffering() {
        CourseOffering offering = createOffering('DupUserRole');
        User u1 = createUser('cmdup3');

        insert new course_managers__c(
            Course_Offering__c = offering.Id,
            Role__c = 'Manager',
            User__c = u1.Id
        );

        course_managers__c incoming = new course_managers__c(
            Course_Offering__c = offering.Id,
            Role__c = 'Delivery Manager',
            User__c = u1.Id
        );

        CourseManagerDuplicateValidationHandler.validateNoDuplicates(
            new List<course_managers__c>{ incoming },
            null
        );

        System.assert(incoming.getErrors().size() > 0, 'Expected user-multiple-roles validation error.');
    }

    @isTest
    static void testInTransactionDuplicateRoleDetected() {
        CourseOffering offering = createOffering('DupTxn');
        User u1 = createUser('cmdup4');
        User u2 = createUser('cmdup5');

        course_managers__c row1 = new course_managers__c(
            Course_Offering__c = offering.Id,
            Role__c = 'Manager',
            User__c = u1.Id
        );
        course_managers__c row2 = new course_managers__c(
            Course_Offering__c = offering.Id,
            Role__c = 'Associate',
            User__c = u2.Id
        );
        insert new List<course_managers__c>{ row1, row2 };

        // Updating both rows in one transaction to same role exercises in-transaction dedupe branch.
        row1.Role__c = 'Manager';
        row2.Role__c = 'Manager';

        Database.SaveResult[] results = Database.update(new List<course_managers__c>{ row1, row2 }, false);

        Integer failureCount = 0;
        for (Database.SaveResult sr : results) {
            if (!sr.isSuccess()) {
                failureCount++;
            }
        }
        System.assert(failureCount > 0, 'At least one update row should fail duplicate role validation.');
    }

    @isTest
    static void testGuardsForEmptyAndNullOffering() {
        CourseManagerDuplicateValidationHandler.validateNoDuplicates(new List<course_managers__c>(), null);

        course_managers__c incoming = new course_managers__c(
            Role__c = 'Manager'
        );
        CourseManagerDuplicateValidationHandler.validateNoDuplicates(
            new List<course_managers__c>{ incoming },
            null
        );

        System.assertEquals(0, incoming.getErrors().size(), 'Null offering should be skipped.');
    }
}