@isTest
private class CommunicationThreadEscalationServiceTest {
    private static User createUser(String aliasPrefix) {
        String unique = String.valueOf(DateTime.now().getTime()) + String.valueOf(Math.mod(Crypto.getRandomInteger(), 1000000));
        return new User(
            LastName = aliasPrefix + 'User',
            Alias = aliasPrefix.left(5),
            Email = aliasPrefix + '+' + unique + '@test.com',
            Username = aliasPrefix + '.' + unique + '@test.com',
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = UserInfo.getProfileId()
        );
    }

    @testSetup
    static void setupData() {
        User cmUser = createUser('cm');
        User l3User = createUser('l3');
        User l4User = createUser('l4');
        insert new List<User>{ cmUser, l3User, l4User };

        Id facultyRecordTypeId = Schema.SObjectType.Contact.getRecordTypeInfosByDeveloperName().containsKey('Faculty')
            ? Schema.SObjectType.Contact.getRecordTypeInfosByDeveloperName().get('Faculty').getRecordTypeId()
            : null;

        Contact faculty = new Contact(
            FirstName = 'Esc',
            LastName = 'Faculty',
            Email = 'esc.faculty@test.com',
            RecordTypeId = facultyRecordTypeId,
            hed__Preferred_Email__c = 'VF Email ID',
            VF_Email_ID__c = 'bodhtree.admin@isb.com'
        );
        insert faculty;

        Program program = new Program(Name = 'Esc Program');
        insert program;

        AcademicYear academicYear = new AcademicYear(Name = '2026-2027 Esc');
        insert academicYear;

        AcademicTerm term = new AcademicTerm(Name = 'Esc Term 1');
        insert term;

        Learning learning = new Learning(Name = 'Esc Learning');
        insert learning;

        LearningCourse course = new LearningCourse(
            Name = 'Esc Learning Course',
            LearningId = learning.Id
        );
        insert course;

        CourseOffering offering = new CourseOffering(
            Name = 'Esc Offering',
            LearningCourseId = course.Id,
            Academic_Term__c = term.Id,
            Program__c = program.Id,
            Academic_Year__c = academicYear.Id,
            StartDate = Date.today().addDays(-15),
            EndDate = Date.today().addDays(15),
            Term_Start_Date__c = Date.today().addDays(-10)
        );
        insert offering;

        insert new List<course_managers__c>{
            new course_managers__c(
                Course_Offering__c = offering.Id,
                Role__c = 'Manager',
                User__c = cmUser.Id
            ),
            new course_managers__c(
                Course_Offering__c = offering.Id,
                Role__c = 'Delivery Manager',
                User__c = l3User.Id
            ),
            new course_managers__c(
                Course_Offering__c = offering.Id,
                Role__c = 'Associate',
                User__c = l4User.Id
            )
        };

        Payment_Information__c pi = new Payment_Information__c(
            Subject__c = 'Esc PI',
            Faculty__c = faculty.Id,
            Course_Offering__c = offering.Id,
            Course_Manager__c = cmUser.Id
        );
        insert pi;

        Communication_Thread__c threadL1 = new Communication_Thread__c(
            Subject__c = 'Esc Thread L1',
            Status__c = 'Open',
            Course_Offering__c = offering.Id,
            Escalation_Stage__c = 'Level 1'
        );
        insert threadL1;

        Communication_Thread_Contact__c j1 = new Communication_Thread_Contact__c(
            Communication_Thread__c = threadL1.Id,
            Contact__c = faculty.Id,
            Is_Primary__c = true,
            Escalation_Target__c = true,
            Payment_Information__c = pi.Id
        );
        insert j1;

        Communication_Thread__c threadL2 = new Communication_Thread__c(
            Subject__c = 'Esc Thread L2',
            Status__c = 'Open',
            Course_Offering__c = offering.Id,
            Escalation_Stage__c = 'Level 2',
            Escalation_Anchor_Date__c = System.now().addDays(-4)
        );
        insert threadL2;

        Communication_Thread_Contact__c j2 = new Communication_Thread_Contact__c(
            Communication_Thread__c = threadL2.Id,
            Contact__c = faculty.Id,
            Is_Primary__c = true,
            Escalation_Target__c = true,
            Payment_Information__c = pi.Id
        );
        insert j2;

        Communication_Thread__c threadL3 = new Communication_Thread__c(
            Subject__c = 'Esc Thread L3',
            Status__c = 'Open',
            Course_Offering__c = offering.Id,
            Escalation_Stage__c = 'Level 3',
            Escalation_Anchor_Date__c = System.now().addDays(-4)
        );
        insert threadL3;

        Communication_Thread_Contact__c j3 = new Communication_Thread_Contact__c(
            Communication_Thread__c = threadL3.Id,
            Contact__c = faculty.Id,
            Is_Primary__c = true,
            Escalation_Target__c = true,
            Payment_Information__c = pi.Id
        );
        insert j3;

    }

    @isTest
    static void movesFromLevel1ToLevel2UsingCourseManager() {
        Communication_Thread__c thread = [SELECT Id FROM Communication_Thread__c WHERE Subject__c = 'Esc Thread L1' LIMIT 1];
        Id expectedOwner = [SELECT User__c FROM course_managers__c WHERE Role__c = 'Manager' LIMIT 1].User__c;

        Test.startTest();
        CommunicationThreadEscalationService.EscalationResult result =
            CommunicationThreadEscalationService.processScope(new List<Communication_Thread__c>{ thread });
        Test.stopTest();

        Communication_Thread__c updated = [
            SELECT OwnerId, Escalation_Stage__c, Escalation_Anchor_Date__c, Escalation_Next_Due_On__c
            FROM Communication_Thread__c
            WHERE Id = :thread.Id
        ];

        System.assertEquals(expectedOwner, updated.OwnerId);
        System.assertEquals('Level 2', updated.Escalation_Stage__c);
        System.assertNotEquals(null, updated.Escalation_Anchor_Date__c);
        System.assertNotEquals(null, updated.Escalation_Next_Due_On__c);
        System.assert(result.updated > 0);
    }

    @isTest
    static void movesFromLevel2ToLevel3AndLevel3ToLevel4() {
        Communication_Thread__c level2Thread = [SELECT Id FROM Communication_Thread__c WHERE Subject__c = 'Esc Thread L2' LIMIT 1];
        Communication_Thread__c level3Thread = [SELECT Id FROM Communication_Thread__c WHERE Subject__c = 'Esc Thread L3' LIMIT 1];

        User l3User = [SELECT Id, Username FROM User WHERE Alias = 'l3' LIMIT 1];
        User l4User = [SELECT Id, Username FROM User WHERE Alias = 'l4' LIMIT 1];

        CommunicationThreadEscalationService.TEST_ROLE_TO_USERNAME = new Map<String, String>{
            'L3_PULKIT' => l3User.Username,
            'L4_PHANIBALA' => l4User.Username
        };
        CommunicationThreadEscalationService.TEST_ROLE_TO_DAYS = new Map<String, Integer>{
            'L3_PULKIT' => 3,
            'L4_PHANIBALA' => 3
        };

        Id expectedL3Owner = l3User.Id;
        Id expectedL4Owner = l4User.Id;

        Test.startTest();
        CommunicationThreadEscalationService.processScope(new List<Communication_Thread__c>{ level2Thread, level3Thread });
        Test.stopTest();

        Communication_Thread__c updatedL2 = [SELECT OwnerId, Escalation_Stage__c FROM Communication_Thread__c WHERE Id = :level2Thread.Id];
        Communication_Thread__c updatedL3 = [SELECT OwnerId, Escalation_Stage__c FROM Communication_Thread__c WHERE Id = :level3Thread.Id];

        System.assertEquals(expectedL3Owner, updatedL2.OwnerId);
        System.assertEquals('Level 3', updatedL2.Escalation_Stage__c);
        System.assertEquals(expectedL4Owner, updatedL3.OwnerId);
        System.assertEquals('Level 4', updatedL3.Escalation_Stage__c);

        CommunicationThreadEscalationService.TEST_ROLE_TO_USERNAME = null;
        CommunicationThreadEscalationService.TEST_ROLE_TO_DAYS = null;
    }

    @isTest
    static void schedulerSchedulesAndExecutesBatch() {
        Test.startTest();
        String jobId = CommunicationThreadEscalationScheduler.scheduleJob(
            'Escalation Test Job',
            '0 0 2 * * ?'
        );
        System.assertNotEquals(null, jobId);
        new CommunicationThreadEscalationScheduler().execute(null);
        Test.stopTest();
    }

    @isTest
    static void processScopeHandlesClosedAndSkippedStatuses() {
        CourseOffering offering = [SELECT Id FROM CourseOffering WHERE Name = 'Esc Offering' LIMIT 1];

        Communication_Thread__c closedThread = new Communication_Thread__c(
            Subject__c = 'Esc Closed Thread',
            Status__c = 'Closed',
            Course_Offering__c = offering.Id,
            Escalation_Stage__c = 'Level 2',
            Escalation_Anchor_Date__c = System.now().addDays(-1),
            Escalation_Next_Due_On__c = System.now().addDays(2)
        );
        insert closedThread;

        Communication_Thread__c skippedThread = new Communication_Thread__c(
            Subject__c = 'Esc Skipped Thread',
            Status__c = 'On Hold',
            Course_Offering__c = offering.Id,
            Comment__c = 'Temporarily on hold for test scenario',
            Escalation_Stage__c = 'Level 1'
        );
        insert skippedThread;

        Test.startTest();
        CommunicationThreadEscalationService.EscalationResult result =
            CommunicationThreadEscalationService.processScope(
                new List<Communication_Thread__c>{ closedThread, skippedThread }
            );
        Test.stopTest();

        Communication_Thread__c refreshedClosed = [
            SELECT Escalation_Stage__c, Escalation_Anchor_Date__c, Escalation_Next_Due_On__c
            FROM Communication_Thread__c
            WHERE Id = :closedThread.Id
        ];

        System.assertEquals('Closed', refreshedClosed.Escalation_Stage__c);
        System.assertEquals(null, refreshedClosed.Escalation_Anchor_Date__c);
        System.assertEquals(null, refreshedClosed.Escalation_Next_Due_On__c);
        System.assert(result.skipped > 0, 'Expected skipped count to increase for unsupported status records.');
    }

    @isTest
    static void processScopeReturnsForNullAndEmptyInputs() {
        CommunicationThreadEscalationService.EscalationResult fromNull =
            CommunicationThreadEscalationService.processScope(null);
        CommunicationThreadEscalationService.EscalationResult fromEmpty =
            CommunicationThreadEscalationService.processScope(new List<Communication_Thread__c>());

        System.assertEquals(0, fromNull.processed);
        System.assertEquals(0, fromEmpty.processed);
        System.assertEquals(0, fromNull.updated);
        System.assertEquals(0, fromEmpty.updated);
    }
}