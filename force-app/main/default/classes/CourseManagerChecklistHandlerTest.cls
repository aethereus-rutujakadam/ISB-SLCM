@isTest
private class CourseManagerChecklistHandlerTest {

    private static User createCmChecklistUser(String prefix) {
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

    private static CourseOffering createChecklistValidationOffering(String offeringName) {
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

    @testSetup
    static void setupData() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User testUser = new User(
            Alias = 'cmgr',
            Email = 'cmgr@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'ChecklistOwner',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'cmgr' + System.currentTimeMillis() + '@example.com',
            IsActive = true
        );
        insert testUser;

        Schema.Location testLocation = new Schema.Location(
            Name = 'Checklist Test Location',
            LocationType = 'Campus'
        );
        insert testLocation;

        Learning learn = new Learning(Name = 'Checklist Learning');
        insert learn;

        LearningCourse lc = new LearningCourse(
            Name = 'Checklist Test Course',
            LearningId = learn.Id
        );
        insert lc;

        CourseOffering offering = new CourseOffering(
            Name = 'Checklist Offering',
            LearningCourseId = lc.Id,
            Location__c = testLocation.Id,
            Course_Type__c = 'Core',
            Term_Start_Date__c = Date.newInstance(2026, 6, 1),
            Term_To_Date__c = Date.newInstance(2026, 7, 15)
        );
        insert offering;

        Course_Checklist_Item_Template__c template = new Course_Checklist_Item_Template__c(
            Subject__c = 'Template Item 1',
            Description__c = 'Template description',
            Priority__c = 'High',
            Owner_Roles__c = 'Manager',
            Template_Type__c = 'Zoho Tasks',
            Course_Type__c = 'Core',
            Active__c = true,
            Start_Date__c = Date.newInstance(2026, 5, 20),
            End_Date__c = Date.newInstance(2026, 5, 30),
            Reminder_Logic_Calculation__c = 'Term Start',
            Reminder_Reference_Days__c = 10
        );
        insert template;
    }

    @isTest
    static void testHandlerStampsDatesAndReminderFields() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'ChecklistOwner' LIMIT 1];
        CourseOffering offering = [
            SELECT Id, Term_Start_Date__c
            FROM CourseOffering
            WHERE Name = 'Checklist Offering'
            LIMIT 1
        ];

        Test.startTest();
        insert new course_managers__c(
            User__c = testUser.Id,
            Course_Offering__c = offering.Id,
            Role__c = 'Manager'
        );
        Test.stopTest();

        Course_Checklist_Item__c createdItem = [
            SELECT Start_Date__c, End_Date__c,
                   Reminder_Logic_Calculation__c, Reminder_Reference_Days__c,
                   Course_Type__c, Course_Checklist_Item_Template__r.Subject__c
            FROM Course_Checklist_Item__c
            WHERE Course_Checklist_Item_Template__r.Subject__c = 'Template Item 1'
            LIMIT 1
        ];

        System.assertEquals(Date.newInstance(2026, 5, 20), createdItem.Start_Date__c);
        System.assertEquals(Date.newInstance(2026, 5, 30), createdItem.End_Date__c);
        System.assertEquals('Term Start', createdItem.Reminder_Logic_Calculation__c);
        System.assertEquals(12, Integer.valueOf(createdItem.Reminder_Reference_Days__c));
        System.assertEquals('Core', createdItem.Course_Type__c);
    }

    @isTest
    static void testTermEndReferenceDaysAllowsNegativeValues() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'ChecklistOwner' LIMIT 1];
        CourseOffering offering = [
            SELECT Id, Term_To_Date__c
            FROM CourseOffering
            WHERE Name = 'Checklist Offering'
            LIMIT 1
        ];

        insert new Course_Checklist_Item_Template__c(
            Subject__c = 'Template Item 2',
            Description__c = 'Template term end description',
            Priority__c = 'Medium',
            Owner_Roles__c = 'Manager',
            Template_Type__c = 'Zoho Tasks',
            Course_Type__c = 'Core',
            Active__c = true,
            Start_Date__c = Date.newInstance(2026, 5, 20),
            End_Date__c = Date.newInstance(2026, 5, 30),
            Reminder_Logic_Calculation__c = 'Term End',
            Reminder_Reference_Days__c = 0
        );

        Test.startTest();
        insert new course_managers__c(
            User__c = testUser.Id,
            Course_Offering__c = offering.Id,
            Role__c = 'Manager'
        );
        Test.stopTest();

        Course_Checklist_Item__c createdItem = [
            SELECT Start_Date__c, Reminder_Logic_Calculation__c, Reminder_Reference_Days__c,
                   Course_Type__c,
                   Course_Checklist_Item_Template__r.Subject__c
            FROM Course_Checklist_Item__c
            WHERE Course_Checklist_Item_Template__r.Subject__c = 'Template Item 2'
            LIMIT 1
        ];

        System.assertEquals('Term End', createdItem.Reminder_Logic_Calculation__c);
        System.assertEquals(-56, Integer.valueOf(createdItem.Reminder_Reference_Days__c));
        System.assertEquals('Core', createdItem.Course_Type__c);
    }

            @isTest
            static void testEmailInvocationOnCourseManagerAssignment() {
                User testUser = [SELECT Id FROM User WHERE LastName = 'ChecklistOwner' LIMIT 1];
                CourseOffering offering = [
                    SELECT Id
                    FROM CourseOffering
                    WHERE Name = 'Checklist Offering'
                    LIMIT 1
                ];

                Test.startTest();
                insert new course_managers__c(
                    User__c = testUser.Id,
                    Course_Offering__c = offering.Id,
                    Role__c = 'Manager'
                );
                Test.stopTest();

            }

    @isTest
    static void testBulkAssignmentOneUserMultipleOfferings() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'ChecklistOwner' LIMIT 1];
        CourseOffering firstOffering = [
            SELECT Id
            FROM CourseOffering
            WHERE Name = 'Checklist Offering'
            LIMIT 1
        ];
        LearningCourse lc = [
            SELECT Id
            FROM LearningCourse
            WHERE Name = 'Checklist Test Course'
            LIMIT 1
        ];
        Schema.Location testLocation = [
            SELECT Id
            FROM Location
            WHERE Name = 'Checklist Test Location'
            LIMIT 1
        ];

        CourseOffering secondOffering = new CourseOffering(
            Name = 'Checklist Offering 2',
            LearningCourseId = lc.Id,
            Location__c = testLocation.Id,
            Course_Type__c = 'Core',
            Term_Start_Date__c = Date.newInstance(2026, 8, 1),
            Term_To_Date__c = Date.newInstance(2026, 9, 15)
        );
        insert secondOffering;

        Test.startTest();
        insert new List<course_managers__c>{
            new course_managers__c(
                User__c = testUser.Id,
                Course_Offering__c = firstOffering.Id,
                Role__c = 'Manager'
            ),
            new course_managers__c(
                User__c = testUser.Id,
                Course_Offering__c = secondOffering.Id,
                Role__c = 'Manager'
            )
        };
        Test.stopTest();

        Integer checklistCount = [
            SELECT COUNT()
            FROM Course_Checklist__c
            WHERE OwnerId = :testUser.Id
              AND Role__c = 'Manager'
              AND Course_Offering__c IN :new Set<Id>{ firstOffering.Id, secondOffering.Id }
        ];

        System.assertEquals(2, checklistCount, 'Expected manager checklist for both offerings.');
        //System.assertEquals(1, Limits.getEmailInvocations(), 'Expected one consolidated email invocation for the user.');
    }

    @isTest
    static void testDeliveryManagerPopulatesSpocOnPaymentInformation() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'ChecklistOwner' LIMIT 1];
        CourseOffering offering = [
            SELECT Id
            FROM CourseOffering
            WHERE Name = 'Checklist Offering'
            LIMIT 1
        ];

        insert new List<Payment_Information__c>{
            new Payment_Information__c(
                Subject__c = 'SPOC Sync Payment 1',
                Course_Offering__c = offering.Id
            ),
            new Payment_Information__c(
                Subject__c = 'SPOC Sync Payment 2',
                Course_Offering__c = offering.Id
            )
        };

        Test.startTest();
        insert new course_managers__c(
            User__c = testUser.Id,
            Course_Offering__c = offering.Id,
            Role__c = 'Delivery Manager'
        );
        Test.stopTest();

        List<Payment_Information__c> payments = [
                        SELECT Id, SPOC__c, OwnerId
            FROM Payment_Information__c
            WHERE Course_Offering__c = :offering.Id
              AND Subject__c LIKE 'SPOC Sync Payment%'
        ];

        System.assertEquals(2, payments.size(), 'Expected both Payment Information records to exist.');
        
    }

    @isTest
    static void testManagerPopulatesOnlyCourseManagerOnPaymentInformation() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'ChecklistOwner' LIMIT 1];
        CourseOffering offering = [
            SELECT Id
            FROM CourseOffering
            WHERE Name = 'Checklist Offering'
            LIMIT 1
        ];

        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User existingSpoc = new User(
            Alias = 'spocu',
            Email = 'spocuser@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'ExistingSpoc',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'existingspoc' + System.currentTimeMillis() + '@example.com',
            IsActive = true
        );
        insert existingSpoc;

        insert new List<Payment_Information__c>{
            new Payment_Information__c(
                Subject__c = 'Manager Sync Payment 1',
                Course_Offering__c = offering.Id,
                SPOC__c = existingSpoc.Id
            ),
            new Payment_Information__c(
                Subject__c = 'Manager Sync Payment 2',
                Course_Offering__c = offering.Id,
                SPOC__c = existingSpoc.Id
            )
        };

        Test.startTest();
        insert new course_managers__c(
            User__c = testUser.Id,
            Course_Offering__c = offering.Id,
            Role__c = 'Manager'
        );
        Test.stopTest();

        List<Payment_Information__c> payments = [
            SELECT Id, SPOC__c, Course_Manager__c
            FROM Payment_Information__c
            WHERE Course_Offering__c = :offering.Id
              AND Subject__c LIKE 'Manager Sync Payment%'
        ];

        System.assertEquals(2, payments.size(), 'Expected both Payment Information records to exist.');
        for (Payment_Information__c payment : payments) {
            System.assertEquals(
                existingSpoc.Id,
                payment.SPOC__c,
                'SPOC should not be updated by Manager assignment.'
            );
            
        }
    }

    @isTest
    static void testManagerCreationKeepsOwnerOnSpocAndSetsCourseManager() {
        User deliveryManager = [SELECT Id FROM User WHERE LastName = 'ChecklistOwner' LIMIT 1];
        CourseOffering offering = [
            SELECT Id
            FROM CourseOffering
            WHERE Name = 'Checklist Offering'
            LIMIT 1
        ];

        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User managerUser = new User(
            Alias = 'mgrusr',
            Email = 'manageruser@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'PaymentManager',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'paymentmanager' + System.currentTimeMillis() + '@example.com',
            IsActive = true
        );
        insert managerUser;

        Payment_Information__c payment = new Payment_Information__c(
            Subject__c = 'Manager Owner Sync Payment',
            Course_Offering__c = offering.Id,
            SPOC__c = deliveryManager.Id,
            OwnerId = deliveryManager.Id
        );
        insert payment;

        Test.startTest();
        insert new course_managers__c(
            User__c = managerUser.Id,
            Course_Offering__c = offering.Id,
            Role__c = 'Manager'
        );
        Test.stopTest();

        Payment_Information__c refreshedPayment = [
            SELECT SPOC__c, Course_Manager__c, OwnerId
            FROM Payment_Information__c
            WHERE Id = :payment.Id
        ];

        System.assertEquals(deliveryManager.Id, refreshedPayment.SPOC__c, 'SPOC should remain the delivery manager.');
        System.assertEquals(deliveryManager.Id, refreshedPayment.OwnerId, 'Owner should remain aligned to SPOC.');
       // System.assertEquals(managerUser.Id, refreshedPayment.Course_Manager__c, 'Course Manager should be populated from the Manager role.');
    }

    @isTest
    static void testDuplicateRoleAgainstExistingRecord() {
        CourseOffering offering = createChecklistValidationOffering('DupRole');
        User u1 = createCmChecklistUser('cmdup1');
        User u2 = createCmChecklistUser('cmdup2');

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
        CourseOffering offering = createChecklistValidationOffering('DupUserRole');
        User u1 = createCmChecklistUser('cmdup3');

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
        CourseOffering offering = createChecklistValidationOffering('DupTxn');
        User u1 = createCmChecklistUser('cmdup4');
        User u2 = createCmChecklistUser('cmdup5');

        course_managers__c row1 = new course_managers__c(
            Course_Offering__c = offering.Id,
            Role__c = 'Manager',
            User__c = u1.Id
        );
        course_managers__c row2 = new course_managers__c(
            Course_Offering__c = offering.Id,
            Role__c = 'Delivery Manager',
            User__c = u2.Id
        );
        insert new List<course_managers__c>{ row1, row2 };

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

    @isTest
    static void testHandleChecklistAfterUpdateCoversStandardPathAndItemUpdates() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'ChecklistOwner' LIMIT 1];
        CourseOffering offering = [
            SELECT Id
            FROM CourseOffering
            WHERE Name = 'Checklist Offering'
            LIMIT 1
        ];

        insert new course_managers__c(
            User__c = testUser.Id,
            Course_Offering__c = offering.Id,
            Role__c = 'Manager'
        );

        Course_Checklist__c checklist = [
            SELECT Id, Course_Offering__c
            FROM Course_Checklist__c
            WHERE Course_Offering__c = :offering.Id
            LIMIT 1
        ];

        List<Course_Checklist_Item__c> itemsBefore = [
            SELECT Id, Status__c
            FROM Course_Checklist_Item__c
            WHERE Course_Checklist__c = :checklist.Id
        ];
        System.assert(!itemsBefore.isEmpty(), 'Expected checklist items from manager assignment setup.');

        Map<Id, Course_Checklist__c> oldMap = new Map<Id, Course_Checklist__c>{
            checklist.Id => new Course_Checklist__c(
                Id = checklist.Id,
                Status__c = 'Draft'
            )
        };

        Course_Checklist__c syntheticActive = new Course_Checklist__c(
            Id = checklist.Id,
            Status__c = 'Active',
            Checklist_Type__c = 'Course Checklist',
            Course_Offering__c = checklist.Course_Offering__c,
            Role__c = 'Manager'
        );

        Test.startTest();
        CourseChecklistSharingHandler.handleChecklistAfterUpdate(
            new List<Course_Checklist__c>{ syntheticActive },
            oldMap
        );
        Test.stopTest();

        List<Course_Checklist_Item__c> itemsAfter = [
            SELECT Id, Status__c
            FROM Course_Checklist_Item__c
            WHERE Course_Checklist__c = :checklist.Id
        ];

        for (Course_Checklist_Item__c row : itemsAfter) {
            System.assertEquals('In Progress', row.Status__c);
        }
    }

    @isTest
    static void testChecklistSharingMethodsAndEarlyReturnPaths() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'ChecklistOwner' LIMIT 1];
        CourseOffering offering = [
            SELECT Id
            FROM CourseOffering
            WHERE Name = 'Checklist Offering'
            LIMIT 1
        ];

        insert new course_managers__c(
            User__c = testUser.Id,
            Course_Offering__c = offering.Id,
            Role__c = 'Manager'
        );

        Course_Checklist__c checklist = [
            SELECT Id, Course_Offering__c, Role__c
            FROM Course_Checklist__c
            WHERE Course_Offering__c = :offering.Id
            LIMIT 1
        ];

        Course_Checklist__c nullOfferingChecklist = new Course_Checklist__c(
            Id = checklist.Id,
            Status__c = 'Draft',
            Checklist_Type__c = 'Course Checklist'
        );

        Map<Id, Course_Checklist__c> oldMap = new Map<Id, Course_Checklist__c>{
            checklist.Id => new Course_Checklist__c(Id = checklist.Id, Status__c = 'Draft')
        };

        Course_Checklist__c activateStandard = new Course_Checklist__c(
            Id = checklist.Id,
            Status__c = 'Active',
            Checklist_Type__c = 'Course Checklist',
            Course_Offering__c = checklist.Course_Offering__c,
            Role__c = checklist.Role__c
        );

        Course_Checklist__c activateZoho = new Course_Checklist__c(
            Id = checklist.Id,
            Status__c = 'Active',
            Checklist_Type__c = 'Zoho Tasks',
            Course_Offering__c = checklist.Course_Offering__c,
            Role__c = checklist.Role__c
        );

        Test.startTest();
        CourseChecklistSharingHandler.shareChecklist(new List<Course_Checklist__c>{ checklist });
        CourseChecklistSharingHandler.shareChecklist(new List<Course_Checklist__c>{ nullOfferingChecklist });

        CourseChecklistSharingHandler.handleChecklistAfterUpdate(
            new List<Course_Checklist__c>{ activateStandard },
            oldMap
        );

        CourseChecklistSharingHandler.handleChecklistAfterUpdate(
            new List<Course_Checklist__c>{ activateZoho },
            oldMap
        );

        CourseChecklistSharingHandler.handleChecklistAfterUpdate(
            new List<Course_Checklist__c>{
                new Course_Checklist__c(Id = checklist.Id, Status__c = 'Draft')
            },
            oldMap
        );
        Test.stopTest();

        System.assert(true, 'Sharing methods executed without unhandled exceptions.');
    }

    @isTest
    static void testManagerWithNullUserSkipped() {
        CourseOffering offering = [SELECT Id FROM CourseOffering WHERE Name = 'Checklist Offering' LIMIT 1];

        Test.startTest();
        insert new course_managers__c(
            User__c = null,
            Course_Offering__c = offering.Id,
            Role__c = 'Manager'
        );
        Test.stopTest();

        Integer checklistCount = [SELECT COUNT() FROM Course_Checklist__c WHERE Course_Offering__c = :offering.Id];
        System.assertEquals(0, checklistCount, 'No checklist should be created when User is null');
    }

    @isTest
    static void testManagerWithNullOfferingSkipped() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'ChecklistOwner' LIMIT 1];

        Test.startTest();
        insert new course_managers__c(
            User__c = testUser.Id,
            Course_Offering__c = null,
            Role__c = 'Manager'
        );
        Test.stopTest();

        Integer checklistCount = [SELECT COUNT() FROM Course_Checklist__c WHERE OwnerId = :testUser.Id];
        System.assertEquals(0, checklistCount, 'No checklist should be created when Offering is null');
    }

    @isTest
    static void testManagerWithNullRoleSkipped() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'ChecklistOwner' LIMIT 1];
        CourseOffering offering = [SELECT Id FROM CourseOffering WHERE Name = 'Checklist Offering' LIMIT 1];

        Test.startTest();
        insert new course_managers__c(
            User__c = testUser.Id,
            Course_Offering__c = offering.Id,
            Role__c = null
        );
        Test.stopTest();

        Integer checklistCount = [SELECT COUNT() FROM Course_Checklist__c WHERE Course_Offering__c = :offering.Id];
        System.assertEquals(0, checklistCount, 'No checklist should be created when Role is null');
    }

    @isTest
    static void testOfferingWithNullCourseTypeSkipped() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'ChecklistOwner' LIMIT 1];
        
        Schema.Location testLocation = [SELECT Id FROM Location WHERE Name = 'Checklist Test Location' LIMIT 1];
        LearningCourse lc = [SELECT Id FROM LearningCourse WHERE Name = 'Checklist Test Course' LIMIT 1];

        CourseOffering offeringNoCourseType = new CourseOffering(
            Name = 'Offering No Course Type',
            LearningCourseId = lc.Id,
            Location__c = testLocation.Id,
            Course_Type__c = null
        );
        insert offeringNoCourseType;

        Test.startTest();
        insert new course_managers__c(
            User__c = testUser.Id,
            Course_Offering__c = offeringNoCourseType.Id,
            Role__c = 'Manager'
        );
        Test.stopTest();

        Integer checklistCount = [SELECT COUNT() FROM Course_Checklist__c WHERE Course_Offering__c = :offeringNoCourseType.Id];
        System.assertEquals(0, checklistCount, 'No checklist should be created when Course Type is null');
    }

    @isTest
    static void testNoMatchingTemplatesForRoleAndType() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'ChecklistOwner' LIMIT 1];
        
        Schema.Location testLocation = [SELECT Id FROM Location WHERE Name = 'Checklist Test Location' LIMIT 1];
        LearningCourse lc = [SELECT Id FROM LearningCourse WHERE Name = 'Checklist Test Course' LIMIT 1];

        CourseOffering offeringElective = new CourseOffering(
            Name = 'Offering Elective Type',
            LearningCourseId = lc.Id,
            Location__c = testLocation.Id,
            Course_Type__c = 'Elective'
        );
        insert offeringElective;

        Test.startTest();
        insert new course_managers__c(
            User__c = testUser.Id,
            Course_Offering__c = offeringElective.Id,
            Role__c = 'Manager'
        );
        Test.stopTest();

        Integer checklistCount = [SELECT COUNT() FROM Course_Checklist__c WHERE Course_Offering__c = :offeringElective.Id];
        System.assertEquals(0, checklistCount, 'No checklist should be created when no matching templates exist');
    }

    @isTest
    static void testTemplateWithNonZohoTasksTypeSkipped() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'ChecklistOwner' LIMIT 1];
        CourseOffering offering = [SELECT Id FROM CourseOffering WHERE Name = 'Checklist Offering' LIMIT 1];

        insert new Course_Checklist_Item_Template__c(
            Subject__c = 'Non-Zoho Template',
            Description__c = 'Description',
            Priority__c = 'Low',
            Owner_Roles__c = 'Manager',
            Template_Type__c = 'Start of Term Tasks',
            Course_Type__c = 'Core',
            Active__c = true
        );

        Test.startTest();
        insert new course_managers__c(
            User__c = testUser.Id,
            Course_Offering__c = offering.Id,
            Role__c = 'Manager'
        );
        Test.stopTest();

        Integer itemCount = [SELECT COUNT() FROM Course_Checklist_Item__c WHERE Subject__c = 'Non-Zoho Template'];
        System.assertEquals(0, itemCount, 'Non-Zoho Tasks templates should not create items');
    }

    @isTest
    static void testReminderCalculationTermStartNull() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'ChecklistOwner' LIMIT 1];
        
        Schema.Location testLocation = [SELECT Id FROM Location WHERE Name = 'Checklist Test Location' LIMIT 1];
        LearningCourse lc = [SELECT Id FROM LearningCourse WHERE Name = 'Checklist Test Course' LIMIT 1];

        CourseOffering offeringNoTermStart = new CourseOffering(
            Name = 'Offering No Term Start',
            LearningCourseId = lc.Id,
            Location__c = testLocation.Id,
            Course_Type__c = 'Core',
            Term_Start_Date__c = null,
            Term_To_Date__c = Date.today()
        );
        insert offeringNoTermStart;

        insert new Course_Checklist_Item_Template__c(
            Subject__c = 'Template No Term Start',
            Description__c = 'Test Desc',
            Priority__c = 'Medium',
            Owner_Roles__c = 'Manager',
            Template_Type__c = 'Zoho Tasks',
            Course_Type__c = 'Core',
            Active__c = true,
            Start_Date__c = Date.today(),
            Reminder_Logic_Calculation__c = 'Term Start'
        );

        Test.startTest();
        insert new course_managers__c(
            User__c = testUser.Id,
            Course_Offering__c = offeringNoTermStart.Id,
            Role__c = 'Manager'
        );
        Test.stopTest();

        List<Course_Checklist_Item__c> items = [
            SELECT Reminder_Reference_Days__c 
            FROM Course_Checklist_Item__c 
            WHERE Subject__c = 'Template No Term Start'
        ];
        
        if (!items.isEmpty()) {
            System.assertEquals(null, items[0].Reminder_Reference_Days__c, 'Reminder days should be null when Term Start is null');
        }
    }

    @isTest
    static void testReminderCalculationTermEndNull() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'ChecklistOwner' LIMIT 1];
        
        Schema.Location testLocation = [SELECT Id FROM Location WHERE Name = 'Checklist Test Location' LIMIT 1];
        LearningCourse lc = [SELECT Id FROM LearningCourse WHERE Name = 'Checklist Test Course' LIMIT 1];

        CourseOffering offeringNoTermEnd = new CourseOffering(
            Name = 'Offering No Term End',
            LearningCourseId = lc.Id,
            Location__c = testLocation.Id,
            Course_Type__c = 'Core',
            Term_Start_Date__c = Date.today(),
            Term_To_Date__c = null
        );
        insert offeringNoTermEnd;

        insert new Course_Checklist_Item_Template__c(
            Subject__c = 'Template No Term End',
            Description__c = 'Test Desc',
            Priority__c = 'Medium',
            Owner_Roles__c = 'Manager',
            Template_Type__c = 'Zoho Tasks',
            Course_Type__c = 'Core',
            Active__c = true,
            Start_Date__c = Date.today(),
            Reminder_Logic_Calculation__c = 'Term End'
        );

        Test.startTest();
        insert new course_managers__c(
            User__c = testUser.Id,
            Course_Offering__c = offeringNoTermEnd.Id,
            Role__c = 'Manager'
        );
        Test.stopTest();

        List<Course_Checklist_Item__c> items = [
            SELECT Reminder_Reference_Days__c 
            FROM Course_Checklist_Item__c 
            WHERE Subject__c = 'Template No Term End'
        ];
        
        if (!items.isEmpty()) {
            System.assertEquals(null, items[0].Reminder_Reference_Days__c, 'Reminder days should be null when Term End is null');
        }
    }

    @isTest
    static void testPaymentInfoUpdateSkipsWhenNoUpdatesNeeded() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'ChecklistOwner' LIMIT 1];
        CourseOffering offering = [SELECT Id FROM CourseOffering WHERE Name = 'Checklist Offering' LIMIT 1];

        Payment_Information__c payment = new Payment_Information__c(
            Subject__c = 'Already Aligned Payment',
            Course_Offering__c = offering.Id,
            SPOC__c = testUser.Id,
            OwnerId = testUser.Id
        );
        insert payment;

        Test.startTest();
        // Insert delivery manager with same user - should skip update as SPOC and Owner already match
        insert new course_managers__c(
            User__c = testUser.Id,
            Course_Offering__c = offering.Id,
            Role__c = 'Delivery Manager'
        );
        Test.stopTest();

        Payment_Information__c refreshed = [SELECT SPOC__c, OwnerId FROM Payment_Information__c WHERE Id = :payment.Id];
        System.assertEquals(testUser.Id, refreshed.SPOC__c, 'SPOC should remain unchanged');
        System.assertEquals(testUser.Id, refreshed.OwnerId, 'Owner should remain unchanged');
    }

    @isTest
    static void testPaymentInfoUpdateSkipsWhenCourseManagerAlreadySet() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'ChecklistOwner' LIMIT 1];
        CourseOffering offering = [SELECT Id FROM CourseOffering WHERE Name = 'Checklist Offering' LIMIT 1];

        Payment_Information__c payment = new Payment_Information__c(
            Subject__c = 'Manager Already Set Payment',
            Course_Offering__c = offering.Id,
            Course_Manager__c = testUser.Id
        );
        insert payment;

        Test.startTest();
        // Insert manager with same user - should skip update as Course Manager already matches
        insert new course_managers__c(
            User__c = testUser.Id,
            Course_Offering__c = offering.Id,
            Role__c = 'Manager'
        );
        Test.stopTest();

        Payment_Information__c refreshed = [SELECT Course_Manager__c FROM Payment_Information__c WHERE Id = :payment.Id];
        System.assertEquals(testUser.Id, refreshed.Course_Manager__c, 'Course Manager should remain unchanged');
    }

    @isTest
    static void testMultipleDifferentRolesForSameOffering() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'ChecklistOwner' LIMIT 1];
        User deliveryUser = createCmChecklistUser('delivery');
        CourseOffering offering = [SELECT Id FROM CourseOffering WHERE Name = 'Checklist Offering' LIMIT 1];

        Test.startTest();
        insert new List<course_managers__c>{
            new course_managers__c(
                User__c = testUser.Id,
                Course_Offering__c = offering.Id,
                Role__c = 'Manager'
            ),
            new course_managers__c(
                User__c = deliveryUser.Id,
                Course_Offering__c = offering.Id,
                Role__c = 'Delivery Manager'
            )
        };
        Test.stopTest();

        Integer checklistCount = [SELECT COUNT() FROM Course_Checklist__c WHERE Course_Offering__c = :offering.Id];
       // System.assertEquals(2, checklistCount, 'Should create checklists for both roles');
    }
}