@isTest
private class FacultyPaymentHandlerExtraTest {

    private static CourseOffering createOffering(String nameValue) {
        Program program = new Program(
            Name = nameValue + ' Program',
            Program_Code__c = 'PGP'
        );
        insert program;

        AcademicYear ay = new AcademicYear(Name = nameValue + ' AY');
        insert ay;

        AcademicTerm term = new AcademicTerm(Name = nameValue + ' Term');
        insert term;

        Learning learning = new Learning(Name = nameValue + ' Learning');
        insert learning;

        LearningCourse course = new LearningCourse(
            Name = nameValue + ' Course',
            LearningId = learning.Id
        );
        insert course;

        CourseOffering offering = new CourseOffering(
            Name = nameValue,
            LearningCourseId = course.Id,
            Academic_Term__c = term.Id,
            Program__c = program.Id,
            Academic_Year__c = ay.Id,
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
    static void testHandleAfterInsertAssignsSpoc() {
        CourseOffering offering = createOffering('FPH SPOC');
        Id dmUserId = UserInfo.getUserId();

        Payment_Information__c payment = new Payment_Information__c(
            Subject__c = 'FPH SPOC Payment',
            Course_Offering__c = offering.Id,
            Remuneration_Type__c = '50'
        );
        insert payment;

        course_managers__c manager = new course_managers__c(
            Course_Offering__c = offering.Id,
            Role__c = 'Delivery Manager',
            User__c = dmUserId
        );

        Test.startTest();
        FacultyPaymentChecklistHandler.handleAfterInsert(new List<course_managers__c>{ manager });
        Test.stopTest();

        Payment_Information__c refreshed = [
            SELECT Id, SPOC__c
            FROM Payment_Information__c
            WHERE Id = :payment.Id
        ];
        System.assertEquals(dmUserId, refreshed.SPOC__c);
    }

    @isTest
    static void testHandleGradesReleasedLogicTransitions() {
        CourseOffering offering = createOffering('FPH Grades');
        User spocUser = createUser('fphspoc1');

        Payment_Information__c p1 = new Payment_Information__c(
            Subject__c = 'P1',
            Course_Offering__c = offering.Id,
            Status__c = 'Draft',
            Remuneration_Type__c = '50'
        );
        Payment_Information__c p2 = new Payment_Information__c(
            Subject__c = 'P2',
            Course_Offering__c = offering.Id,
            Status__c = 'Draft',
            Remuneration_Type__c = '100'
        );
        Payment_Information__c p3 = new Payment_Information__c(
            Subject__c = 'P3',
            Course_Offering__c = offering.Id,
            Status__c = 'ASA Processing',
            SPOC__c = spocUser.Id,
            Remuneration_Type__c = '50'
        );
        Payment_Information__c p4 = new Payment_Information__c(
            Subject__c = 'P4',
            Course_Offering__c = offering.Id,
            Status__c = 'Draft',
            SPOC__c = spocUser.Id,
            Remuneration_Type__c = '50'
        );
        insert new List<Payment_Information__c>{ p1, p2, p3, p4 };

        Map<Id, Payment_Information__c> oldMap = new Map<Id, Payment_Information__c>([
            SELECT Id, Status__c, SPOC__c, Grades_Released__c, ASA_Ready_for_Finance__c,
                   Submitted_to_Finance__c, Sent_to_Finance_Date__c, Payment_Status__c,
                   Closure_Status__c, Course_Manager__c, OwnerId
            FROM Payment_Information__c
            WHERE Id IN :new Set<Id>{ p1.Id, p2.Id, p3.Id, p4.Id }
        ]);
        oldMap.put(p4.Id, new Payment_Information__c(
            Id = p4.Id,
            Status__c = 'Finance Processing',
            SPOC__c = spocUser.Id,
            Payment_Status__c = 'In Progress'
        ));

        Payment_Information__c u1 = new Payment_Information__c(
            Id = p1.Id,
            Grade_Release_Date__c = DateTime.now(),
            Status__c = 'Draft',
            Remuneration_Type__c = '50'
        );

        Payment_Information__c u2 = new Payment_Information__c(
            Id = p2.Id,
            SPOC__c = spocUser.Id,
            Grade_Release_Date__c = DateTime.now(),
            Status__c = 'Draft',
            Remuneration_Type__c = '100'
        );

        Payment_Information__c u3 = new Payment_Information__c(
            Id = p3.Id,
            SPOC__c = spocUser.Id,
            ASA_Ready_for_Finance__c = true,
            Status__c = 'ASA Processing',
            Remuneration_Type__c = '50'
        );

        Payment_Information__c u4 = new Payment_Information__c(
            Id = p4.Id,
            SPOC__c = spocUser.Id,
            Status__c = 'Finance Processing',
            Payment_Status__c = 'Completed',
            Remuneration_Type__c = '50'
        );

        List<Payment_Information__c> updates = new List<Payment_Information__c>{ u1, u2, u3, u4 };

        Test.startTest();
        FacultyPaymentChecklistHandler.handleGradesReleasedLogic(updates, oldMap);
        Test.stopTest();

        System.assert(u1.getErrors().size() > 0, 'Missing SPOC during grade release should add error.');

        System.assertEquals(true, u2.Grades_Released__c);
        System.assertEquals('Grades Released', u2.Status__c);
        System.assertEquals(spocUser.Id, u2.OwnerId);

        System.assertEquals(true, u3.Submitted_to_Finance__c);
        System.assertEquals('Submitted to Finance', u3.Status__c);
        System.assertNotEquals(null, u3.Sent_to_Finance_Date__c);

        System.assertEquals('Completed', u4.Status__c);
        System.assertEquals('Closed', u4.Closure_Status__c);
        System.assertEquals(true, u4.Payment_Done__c);
    }

    @isTest
    static void testHandleOwnerChangeNotificationsNoException() {
        CourseOffering offering = createOffering('FPH Notify');
        User owner1 = createUser('fphown1');
        User owner2 = createUser('fphown2');

        Payment_Information__c payment = new Payment_Information__c(
            Subject__c = 'Notify Payment',
            Course_Offering__c = offering.Id,
            Remuneration_Type__c = '50',
            OwnerId = owner1.Id
        );
        insert payment;

        List<Payment_Information__c> insertContext = [
            SELECT Id, Name, OwnerId
            FROM Payment_Information__c
            WHERE Id = :payment.Id
        ];

        Test.startTest();
        FacultyPaymentChecklistHandler.handleOwnerChangeNotifications(insertContext, null);

        Map<Id, Payment_Information__c> oldMap = new Map<Id, Payment_Information__c>(insertContext);
        Payment_Information__c updateContext = new Payment_Information__c(
            Id = payment.Id,
            OwnerId = owner2.Id
        );
        FacultyPaymentChecklistHandler.handleOwnerChangeNotifications(
            new List<Payment_Information__c>{ updateContext },
            oldMap
        );
        Test.stopTest();

        System.assertEquals(owner2.Id, updateContext.OwnerId);
    }
}