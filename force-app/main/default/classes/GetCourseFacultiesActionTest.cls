@isTest
private class GetCourseFacultiesActionTest {

    @testSetup
    static void setupData() {
        Account acc = new Account(Name = 'GCF Account');
        insert acc;

        Contact c1 = new Contact(
            FirstName = 'A',
            LastName = 'Faculty',
            AccountId = acc.Id,
            FacultyEmail__c = 'a.faculty@test.com'
        );
        Contact c2 = new Contact(
            FirstName = 'B',
            LastName = 'Faculty',
            AccountId = acc.Id,
            FacultyEmail__c = 'b.faculty@test.com'
        );
        Contact c3 = new Contact(
            FirstName = 'C',
            LastName = 'Faculty',
            AccountId = acc.Id
        );
        insert new List<Contact>{ c1, c2, c3 };

        Program program = new Program(Name = 'GCF Program');
        insert program;

        AcademicYear ay = new AcademicYear(Name = '2026-2027');
        insert ay;

        AcademicTerm term = new AcademicTerm(Name = 'GCF Term');
        insert term;

        Learning learning = new Learning(Name = 'GCF Learning');
        insert learning;

        LearningCourse course = new LearningCourse(
            Name = 'GCF Course',
            LearningId = learning.Id
        );
        insert course;

        CourseOffering offering = new CourseOffering(
            Name = 'GCF Offering',
            LearningCourseId = course.Id,
            Academic_Term__c = term.Id,
            Program__c = program.Id,
            Academic_Year__c = ay.Id,
            StartDate = Date.today(),
            EndDate = Date.today().addDays(30)
        );
        insert offering;

        insert new List<Course_Faculty__c>{
            new Course_Faculty__c(Faculty__c = c1.Id, Course_Offering__c = offering.Id),
            new Course_Faculty__c(Faculty__c = c2.Id, Course_Offering__c = offering.Id),
            new Course_Faculty__c(Faculty__c = c3.Id, Course_Offering__c = offering.Id)
        };
    }

    @isTest
    static void testReturnsFacultiesWithCsvSelection() {
        CourseOffering offering = [SELECT Id FROM CourseOffering WHERE Name = 'GCF Offering' LIMIT 1];
        List<Contact> contacts = [
            SELECT Id, FacultyEmail__c
            FROM Contact
            WHERE LastName = 'Faculty'
            ORDER BY FirstName ASC
        ];

        GetCourseFacultiesAction.Request req = new GetCourseFacultiesAction.Request();
        req.courseOfferingId = offering.Id;
        req.selectedFacultyIds = String.valueOf(contacts[0].Id) + '; ' + String.valueOf(contacts[1].Id);

        Test.startTest();
        List<GetCourseFacultiesAction.Result> results =
            GetCourseFacultiesAction.getCourseFaculties(new List<GetCourseFacultiesAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(3, results[0].faculties.size());
        System.assertEquals(contacts[0].Id, results[0].primarySelectedFacultyId);
        System.assertEquals(2, results[0].selectedCount);
        System.assertEquals(2, results[0].selectedFacultyEmails.size());
        System.assertEquals('a.faculty@test.com;b.faculty@test.com', results[0].selectedFacultyEmailsJoined);
    }

    @isTest
    static void testReturnsFacultiesWithListSelection() {
        CourseOffering offering = [SELECT Id FROM CourseOffering WHERE Name = 'GCF Offering' LIMIT 1];
        List<Contact> contacts = [
            SELECT Id, FirstName
            FROM Contact
            WHERE LastName = 'Faculty'
            ORDER BY FirstName ASC
        ];

        GetCourseFacultiesAction.Request req = new GetCourseFacultiesAction.Request();
        req.courseOfferingId = offering.Id;
        req.selectedFacultyIdsList = new List<String>{
            String.valueOf(contacts[1].Id),
            String.valueOf(contacts[2].Id)
        };

        Test.startTest();
        List<GetCourseFacultiesAction.Result> results =
            GetCourseFacultiesAction.getCourseFaculties(new List<GetCourseFacultiesAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(3, results[0].faculties.size());
        System.assertEquals(contacts[1].Id, results[0].primarySelectedFacultyId);
        System.assertEquals(1, results[0].selectedCount, 'One selected faculty has no email and should not be counted.');
        System.assertEquals(1, results[0].selectedFacultyEmails.size());
        System.assertEquals('b.faculty@test.com', results[0].selectedFacultyEmailsJoined);
    }

    @isTest
    static void testNoSelectionAndExceptionBranch() {
        CourseOffering offering = [SELECT Id FROM CourseOffering WHERE Name = 'GCF Offering' LIMIT 1];

        GetCourseFacultiesAction.Request goodReq = new GetCourseFacultiesAction.Request();
        goodReq.courseOfferingId = offering.Id;

        // Null request exercises the catch branch without failing the full invocation.
        GetCourseFacultiesAction.Request nullReq = null;

        Test.startTest();
        List<GetCourseFacultiesAction.Result> results =
            GetCourseFacultiesAction.getCourseFaculties(new List<GetCourseFacultiesAction.Request>{ goodReq, nullReq });
        Test.stopTest();

        System.assertEquals(2, results.size());
        System.assertEquals(3, results[0].faculties.size());
        System.assertEquals(0, results[0].selectedCount);
        System.assertEquals('', results[0].selectedFacultyEmailsJoined);

        System.assertEquals(0, results[1].faculties.size());
        System.assertEquals(0, results[1].selectedCount);
        System.assertEquals(null, results[1].selectedFacultyEmailsJoined);
    }
}