@isTest
private class CreateThreadContactsActionTest {
    @TestSetup
    static void setupData() {
        Id facultyRecordTypeId = Schema.SObjectType.Contact.getRecordTypeInfosByDeveloperName().containsKey('Faculty')
            ? Schema.SObjectType.Contact.getRecordTypeInfosByDeveloperName().get('Faculty').getRecordTypeId()
            : null;

        Contact c1 = new Contact(
            FirstName = 'Faculty',
            LastName = 'One',
            Email = 'faculty1@test.edu',
            RecordTypeId = facultyRecordTypeId,
            hed__Preferred_Email__c = 'VF Email ID',
            VF_Email_ID__c = 'faculty1@test.edu'
        );
        Contact c2 = new Contact(
            FirstName = 'Faculty',
            LastName = 'Two',
            Email = 'faculty2@test.edu',
            RecordTypeId = facultyRecordTypeId,
            hed__Preferred_Email__c = 'VF Email ID',
            VF_Email_ID__c = 'faculty2@test.edu'
        );
        Contact c3 = new Contact(
            FirstName = 'Faculty',
            LastName = 'Three',
            Email = 'faculty3@test.edu',
            RecordTypeId = facultyRecordTypeId,
            hed__Preferred_Email__c = 'VF Email ID',
            VF_Email_ID__c = 'faculty3@test.edu'
        );
        insert new List<Contact>{ c1, c2, c3 };

        Program program = new Program(Name = 'Test Program');
        insert program;

        AcademicYear academicYear = new AcademicYear(Name = '2026-2027');
        insert academicYear;

        AcademicTerm term = new AcademicTerm(Name = 'Term 1 2026');
        insert term;

        Learning learning = new Learning(Name = 'Thread Mapping Learning');
        insert learning;

        LearningCourse course = new LearningCourse(
            Name = 'Test Learning Course',
            LearningId = learning.Id
        );
        insert course;

        CourseOffering offering = new CourseOffering(
            Name = 'Thread Mapping Offering',
            LearningCourseId = course.Id,
            Academic_Term__c = term.Id,
            Program__c = program.Id,
            Academic_Year__c = academicYear.Id,
            StartDate = Date.today(),
            EndDate = Date.today().addDays(30)
        );
        insert offering;

        insert new List<Payment_Information__c>{
            new Payment_Information__c(
                Subject__c = 'PI Faculty One',
                Faculty__c = c1.Id,
                Course_Offering__c = offering.Id
            ),
            new Payment_Information__c(
                Subject__c = 'PI Faculty Two',
                Faculty__c = c2.Id,
                Course_Offering__c = offering.Id
            )
        };

        Communication_Thread__c thread = new Communication_Thread__c(
            Subject__c = 'Test Thread',
            Status__c = 'Open',
            Course_Offering__c = offering.Id
        );
        insert thread;

        Communication_Thread__c noOfferingThread = new Communication_Thread__c(
            Subject__c = 'No Offering Thread',
            Status__c = 'Open'
        );
        insert noOfferingThread;
    }

    @isTest
    static void createsJunctionRecordsWithoutDuplicates() {
        Communication_Thread__c thread = [SELECT Id, Course_Offering__c FROM Communication_Thread__c WHERE Subject__c = 'Test Thread' LIMIT 1];
        List<Contact> contacts = [SELECT Id FROM Contact WHERE Email IN ('faculty1@test.edu', 'faculty2@test.edu') ORDER BY Email ASC];

        CreateThreadContactsAction.Request req = new CreateThreadContactsAction.Request();
        req.threadId = thread.Id;
        req.selectedFacultyIds = contacts[0].Id + ';' + contacts[1].Id;
        req.primaryFacultyId = contacts[0].Id;

        Test.startTest();
        List<CreateThreadContactsAction.Result> firstResults = CreateThreadContactsAction.createThreadContacts(
            new List<CreateThreadContactsAction.Request>{ req }
        );
        List<CreateThreadContactsAction.Result> secondResults = CreateThreadContactsAction.createThreadContacts(
            new List<CreateThreadContactsAction.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(true, firstResults[0].success);
        System.assertEquals(2, firstResults[0].recordsCreated);
        System.assertEquals(true, secondResults[0].success);
        System.assertEquals(0, secondResults[0].recordsCreated);

        List<Communication_Thread_Contact__c> created = [
            SELECT Id, Contact__c, Is_Primary__c, Payment_Information__c
            FROM Communication_Thread_Contact__c
            WHERE Communication_Thread__c = :thread.Id
        ];

        System.assertEquals(2, created.size());
        Map<Id, Payment_Information__c> paymentByFaculty = new Map<Id, Payment_Information__c>([
            SELECT Id, Faculty__c
            FROM Payment_Information__c
            WHERE Course_Offering__c = :thread.Course_Offering__c
            AND Faculty__c IN :new Set<Id>{ contacts[0].Id, contacts[1].Id }
        ]);

        Map<Id, Id> paymentIdByFaculty = new Map<Id, Id>();
        for (Payment_Information__c payment : paymentByFaculty.values()) {
            paymentIdByFaculty.put(payment.Faculty__c, payment.Id);
        }

        for (Communication_Thread_Contact__c row : created) {
            System.assertEquals(
                paymentIdByFaculty.get(row.Contact__c),
                row.Payment_Information__c,
                'Unique offering+faculty mapping should auto-link Payment Information.'
            );
        }
    }

    @isTest
    static void handlesAmbiguousAndMissingPaymentMappingsNonBlocking() {
        Communication_Thread__c thread = [SELECT Id, Course_Offering__c FROM Communication_Thread__c WHERE Subject__c = 'Test Thread' LIMIT 1];
        Contact ambiguousContact = [SELECT Id FROM Contact WHERE Email = 'faculty2@test.edu' LIMIT 1];
        Contact missingContact = [SELECT Id FROM Contact WHERE Email = 'faculty3@test.edu' LIMIT 1];

        insert new Payment_Information__c(
            Subject__c = 'PI Faculty Two Duplicate',
            Faculty__c = ambiguousContact.Id,
            Course_Offering__c = thread.Course_Offering__c
        );

        CreateThreadContactsAction.Request req = new CreateThreadContactsAction.Request();
        req.threadId = thread.Id;
        req.selectedFacultyIds = ambiguousContact.Id + ';' + missingContact.Id;

        Test.startTest();
        List<CreateThreadContactsAction.Result> results = CreateThreadContactsAction.createThreadContacts(
            new List<CreateThreadContactsAction.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(true, results[0].success, 'Junction creation should remain non-blocking.');
        System.assertEquals(2, results[0].recordsCreated);
        System.assertEquals(null, results[0].errorMessage);

        List<Communication_Thread_Contact__c> created = [
            SELECT Id, Contact__c, Payment_Information__c
            FROM Communication_Thread_Contact__c
            WHERE Communication_Thread__c = :thread.Id
            AND Contact__c IN :new Set<Id>{ ambiguousContact.Id, missingContact.Id }
        ];

        System.assertEquals(2, created.size());
        for (Communication_Thread_Contact__c row : created) {
            System.assertEquals(null, row.Payment_Information__c, 'Ambiguous/missing mappings should not auto-link a payment.');
        }
    }

    @isTest
    static void handlesThreadWithoutOfferingNonBlocking() {
        Communication_Thread__c noOfferingThread = [SELECT Id FROM Communication_Thread__c WHERE Subject__c = 'No Offering Thread' LIMIT 1];
        Contact contact = [SELECT Id FROM Contact WHERE Email = 'faculty1@test.edu' LIMIT 1];

        CreateThreadContactsAction.Request req = new CreateThreadContactsAction.Request();
        req.threadId = noOfferingThread.Id;
        req.selectedFacultyIds = String.valueOf(contact.Id);

        Test.startTest();
        List<CreateThreadContactsAction.Result> results = CreateThreadContactsAction.createThreadContacts(
            new List<CreateThreadContactsAction.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(true, results[0].success);
        System.assertEquals(1, results[0].recordsCreated);
        System.assertEquals(null, results[0].errorMessage);

        Communication_Thread_Contact__c created = [
            SELECT Id, Payment_Information__c
            FROM Communication_Thread_Contact__c
            WHERE Communication_Thread__c = :noOfferingThread.Id
            AND Contact__c = :contact.Id
            LIMIT 1
        ];
        System.assertEquals(null, created.Payment_Information__c);
    }

    @isTest
    static void handlesInvalidInput() {
        CreateThreadContactsAction.Request req = new CreateThreadContactsAction.Request();
        req.threadId = null;
        req.selectedFacultyIds = null;

        Test.startTest();
        List<CreateThreadContactsAction.Result> results = CreateThreadContactsAction.createThreadContacts(
            new List<CreateThreadContactsAction.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(false, results[0].success);
        System.assertNotEquals(null, results[0].errorMessage);
    }
}