@IsTest
private class GetThreadFacultyEmailsActionTest {

    private static Id getFacultyRecordTypeId() {
        return Schema.SObjectType.Contact.getRecordTypeInfosByDeveloperName().containsKey('Faculty')
            ? Schema.SObjectType.Contact.getRecordTypeInfosByDeveloperName().get('Faculty').getRecordTypeId()
            : null;
    }

    private static Contact buildFacultyContact(String firstName, String lastName, Id accountId, String facultyEmail) {
        String uniqueEmail = String.isNotBlank(facultyEmail)
            ? facultyEmail
            : (lastName.toLowerCase().replaceAll('[^a-z0-9]', '') + '.' + String.valueOf(Math.mod(Crypto.getRandomInteger(), 1000000)) + '@test.edu');
        Contact contactRecord = new Contact(
            FirstName = firstName,
            LastName = lastName,
            AccountId = accountId,
            RecordTypeId = getFacultyRecordTypeId(),
            Email = uniqueEmail,
            hed__Preferred_Email__c = 'VF Email ID',
            VF_Email_ID__c = uniqueEmail
        );
        if (String.isNotBlank(facultyEmail)) {
            contactRecord.FacultyEmail__c = facultyEmail;
        }
        return contactRecord;
    }

    private static CourseOffering createFacultiesTestOffering(String nameValue) {
        Program program = new Program(Name = nameValue + ' Program');
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
            Name = nameValue + ' Offering',
            LearningCourseId = course.Id,
            Academic_Term__c = term.Id,
            Program__c = program.Id,
            Academic_Year__c = ay.Id,
            StartDate = Date.today(),
            EndDate = Date.today().addDays(30)
        );
        insert offering;
        return offering;
    }

    @TestSetup
    static void setupData() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Contact c1 = buildFacultyContact(null, 'Faculty1', acc.Id, 'faculty1@test.com');
        Contact c2 = buildFacultyContact(null, 'Faculty2', acc.Id, 'faculty2@test.com');
        insert new List<Contact>{ c1, c2 };

        Communication_Thread__c thread = new Communication_Thread__c(Subject__c = 'Test Thread');
        insert thread;

        insert new List<Communication_Thread_Contact__c>{
            new Communication_Thread_Contact__c(
                Communication_Thread__c = thread.Id,
                Contact__c = c1.Id,
                Is_Primary__c = true
            ),
            new Communication_Thread_Contact__c(
                Communication_Thread__c = thread.Id,
                Contact__c = c2.Id,
                Is_Primary__c = false
            )
        };
    }

    @IsTest
    static void testGetEmails_returnsAllEmails() {
        Communication_Thread__c thread = [SELECT Id FROM Communication_Thread__c LIMIT 1];

        GetThreadFacultyEmailsAction.Request req = new GetThreadFacultyEmailsAction.Request();
        req.threadId = thread.Id;

        Test.startTest();
        List<GetThreadFacultyEmailsAction.Result> results = GetThreadFacultyEmailsAction.getEmails(
            new List<GetThreadFacultyEmailsAction.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(2, results[0].emailAddresses.size());
        System.assertEquals('faculty1@test.com', results[0].primaryEmail);
        System.assert(results[0].emailAddresses.contains('faculty1@test.com'));
        System.assert(results[0].emailAddresses.contains('faculty2@test.com'));
    }

    @IsTest
    static void testGetEmails_fallsBackToFirstIfNoPrimary() {
        Communication_Thread__c thread = [SELECT Id FROM Communication_Thread__c LIMIT 1];
        // Clear Is_Primary from all
        List<Communication_Thread_Contact__c> junctions = [
            SELECT Id, Is_Primary__c FROM Communication_Thread_Contact__c WHERE Communication_Thread__c = :thread.Id
        ];
        for (Communication_Thread_Contact__c j : junctions) j.Is_Primary__c = false;
        update junctions;

        GetThreadFacultyEmailsAction.Request req = new GetThreadFacultyEmailsAction.Request();
        req.threadId = thread.Id;

        Test.startTest();
        List<GetThreadFacultyEmailsAction.Result> results = GetThreadFacultyEmailsAction.getEmails(
            new List<GetThreadFacultyEmailsAction.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(2, results[0].emailAddresses.size());
        System.assertNotEquals('', results[0].primaryEmail, 'Should fall back to first email');
    }

    @IsTest
    static void testGetEmails_emptyThread() {
        Communication_Thread__c emptyThread = new Communication_Thread__c(Subject__c = 'Empty');
        insert emptyThread;

        GetThreadFacultyEmailsAction.Request req = new GetThreadFacultyEmailsAction.Request();
        req.threadId = emptyThread.Id;

        Test.startTest();
        List<GetThreadFacultyEmailsAction.Result> results = GetThreadFacultyEmailsAction.getEmails(
            new List<GetThreadFacultyEmailsAction.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(0, results[0].emailAddresses.size());
        System.assertEquals('', results[0].primaryEmail);
    }

    @IsTest
    static void testGetEmails_selectedFacultyFilterAndMalformedIds() {
        Communication_Thread__c thread = [SELECT Id FROM Communication_Thread__c LIMIT 1];
        Contact c2 = [SELECT Id FROM Contact WHERE FacultyEmail__c = 'faculty2@test.com' LIMIT 1];

        GetThreadFacultyEmailsAction.Request req = new GetThreadFacultyEmailsAction.Request();
        req.threadId = thread.Id;
        req.selectedFacultyIds = String.valueOf(c2.Id) + ';not-an-id,   ;';

        Test.startTest();
        List<GetThreadFacultyEmailsAction.Result> results = GetThreadFacultyEmailsAction.getEmails(
            new List<GetThreadFacultyEmailsAction.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(1, results[0].emailAddresses.size());
        System.assertEquals('faculty2@test.com', results[0].emailAddresses[0]);
        System.assertEquals('faculty2@test.com', results[0].primaryEmail);
        System.assertEquals('faculty2@test.com', results[0].allEmailsJoined);
    }

    @IsTest
    static void testGetEmails_multipleRequestsInSingleCall() {
        Communication_Thread__c thread = [SELECT Id FROM Communication_Thread__c LIMIT 1];
        Communication_Thread__c emptyThread = new Communication_Thread__c(Subject__c = 'Another Empty');
        insert emptyThread;

        GetThreadFacultyEmailsAction.Request req1 = new GetThreadFacultyEmailsAction.Request();
        req1.threadId = thread.Id;

        GetThreadFacultyEmailsAction.Request req2 = new GetThreadFacultyEmailsAction.Request();
        req2.threadId = emptyThread.Id;

        Test.startTest();
        List<GetThreadFacultyEmailsAction.Result> results = GetThreadFacultyEmailsAction.getEmails(
            new List<GetThreadFacultyEmailsAction.Request>{ req1, req2 }
        );
        Test.stopTest();

        System.assertEquals(2, results.size());
        System.assertEquals(2, results[0].emailAddresses.size());
        System.assertEquals(0, results[1].emailAddresses.size());
    }

    @isTest
    static void testGetCourseFacultiesReturnsWithCsvSelection() {
        Account acc = new Account(Name = 'GCF Account CSV');
        insert acc;

        Contact c1 = buildFacultyContact('A', 'Faculty', acc.Id, 'a.faculty@test.com');
        Contact c2 = buildFacultyContact('B', 'Faculty', acc.Id, 'b.faculty@test.com');
        Contact c3 = buildFacultyContact('C', 'Faculty', acc.Id, null);
        insert new List<Contact>{ c1, c2, c3 };

        CourseOffering offering = createFacultiesTestOffering('GCF CSV');

        insert new List<Course_Faculty__c>{
            new Course_Faculty__c(Faculty__c = c1.Id, Course_Offering__c = offering.Id),
            new Course_Faculty__c(Faculty__c = c2.Id, Course_Offering__c = offering.Id),
            new Course_Faculty__c(Faculty__c = c3.Id, Course_Offering__c = offering.Id)
        };

        GetCourseFacultiesAction.Request req = new GetCourseFacultiesAction.Request();
        req.courseOfferingId = offering.Id;
        req.selectedFacultyIds = String.valueOf(c1.Id) + '; ' + String.valueOf(c2.Id);

        Test.startTest();
        List<GetCourseFacultiesAction.Result> results =
            GetCourseFacultiesAction.getCourseFaculties(new List<GetCourseFacultiesAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(3, results[0].faculties.size());
        System.assertEquals(c1.Id, results[0].primarySelectedFacultyId);
        System.assertEquals(2, results[0].selectedCount);
        System.assertEquals(2, results[0].selectedFacultyEmails.size());
        System.assertEquals('a.faculty@test.com;b.faculty@test.com', results[0].selectedFacultyEmailsJoined);
    }

    @isTest
    static void testGetCourseFacultiesReturnsWithListSelection() {
        Account acc = new Account(Name = 'GCF Account LIST');
        insert acc;

        Contact c1 = buildFacultyContact('L1', 'FacultyL', acc.Id, 'l1.faculty@test.com');
        Contact c2 = buildFacultyContact('L2', 'FacultyL', acc.Id, 'l2.faculty@test.com');
        Contact c3 = buildFacultyContact('L3', 'FacultyL', acc.Id, null);
        insert new List<Contact>{ c1, c2, c3 };

        CourseOffering offering = createFacultiesTestOffering('GCF LIST');

        insert new List<Course_Faculty__c>{
            new Course_Faculty__c(Faculty__c = c1.Id, Course_Offering__c = offering.Id),
            new Course_Faculty__c(Faculty__c = c2.Id, Course_Offering__c = offering.Id),
            new Course_Faculty__c(Faculty__c = c3.Id, Course_Offering__c = offering.Id)
        };

        GetCourseFacultiesAction.Request req = new GetCourseFacultiesAction.Request();
        req.courseOfferingId = offering.Id;
        req.selectedFacultyIdsList = new List<String>{ String.valueOf(c2.Id), String.valueOf(c3.Id) };

        Test.startTest();
        List<GetCourseFacultiesAction.Result> results =
            GetCourseFacultiesAction.getCourseFaculties(new List<GetCourseFacultiesAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(3, results[0].faculties.size());
        System.assertEquals(c2.Id, results[0].primarySelectedFacultyId);
        System.assertEquals(1, results[0].selectedCount, 'One selected faculty has no email and should not be counted.');
        System.assertEquals(1, results[0].selectedFacultyEmails.size());
        System.assertEquals('l2.faculty@test.com', results[0].selectedFacultyEmailsJoined);
    }

    @isTest
    static void testGetCourseFacultiesNoSelectionAndExceptionBranch() {
        Account acc = new Account(Name = 'GCF Account EX');
        insert acc;

        Contact c1 = buildFacultyContact('E1', 'FacultyE', acc.Id, 'e1.faculty@test.com');
        insert c1;

        CourseOffering offering = createFacultiesTestOffering('GCF EX');
        insert new Course_Faculty__c(Faculty__c = c1.Id, Course_Offering__c = offering.Id);

        GetCourseFacultiesAction.Request goodReq = new GetCourseFacultiesAction.Request();
        goodReq.courseOfferingId = offering.Id;

        GetCourseFacultiesAction.Request nullReq = null;

        Test.startTest();
        List<GetCourseFacultiesAction.Result> results =
            GetCourseFacultiesAction.getCourseFaculties(new List<GetCourseFacultiesAction.Request>{ goodReq, nullReq });
        Test.stopTest();

        System.assertEquals(2, results.size());
        System.assertEquals(1, results[0].faculties.size());
        System.assertEquals(0, results[0].selectedCount);
        System.assertEquals('', results[0].selectedFacultyEmailsJoined);

        System.assertEquals(0, results[1].faculties.size());
        System.assertEquals(0, results[1].selectedCount);
        System.assertEquals(null, results[1].selectedFacultyEmailsJoined);
    }
}