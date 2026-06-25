/**
 * @description Test class for WorkshopController (advisor-facing)
 * @author DEVSLCM Team
 * @date 2026
 */
@isTest
private class WorkshopControllerTest {

    @TestSetup
    static void setup() {
        Account programAccount = new Account(Name = 'Test Program Account');
        insert programAccount;

        Program program = new Program(Name = 'Controller Program');
        insert program;

        AcademicTerm term = new AcademicTerm(Name = 'Controller Cohort');
        insert term;

        AcademicSession session = new AcademicSession(
            Name = 'Controller Session',
            AcademicTermId = term.Id
        );
        insert session;

        Workshop__c w = new Workshop__c(
            Name = 'Controller Test Workshop',
            Status__c = 'Draft',
            Program__c = program.Id,
            Cohort__c = term.Id,
            Eligible_Term__c = session.Id,
            Total_Sessions__c = 1,
            Description__c = 'Test workshop description for controller tests'
        );
        insert w;

        Workshop_Session__c ws = [
            SELECT Id
            FROM Workshop_Session__c
            WHERE Workshop__c = :w.Id
            LIMIT 1
        ];

        Workshop_Batch__c b = new Workshop_Batch__c(
            Workshop_Session__c = ws.Id,
            Batch_Label__c      = 'Batch A',
            Start_DateTime__c   = DateTime.now().addDays(1),
            End_DateTime__c     = DateTime.now().addDays(1).addHours(2),
            Capacity__c         = 10
        );
        insert b;

        Contact student = new Contact(FirstName = 'Controller', LastName = 'Student');
        insert student;
    }

    @isTest
    static void testGetWorkshops() {
        Test.startTest();
        List<Workshop__c> result = WorkshopController.getWorkshops('Draft');
        Test.stopTest();
        System.assert(!result.isEmpty(), 'Should return at least one Draft workshop');
    }

    @isTest
    static void testGetWorkshopDetail() {
        Workshop__c w = [SELECT Id FROM Workshop__c LIMIT 1];
        Test.startTest();
        WorkshopController.WorkshopWrapper detail = WorkshopController.getWorkshopDetail(w.Id);
        Test.stopTest();
        System.assertNotEquals(null, detail.workshop);
        System.assertEquals(1, detail.sessions.size());
    }

    @isTest
    static void testSaveNewWorkshop() {
        Program program = [SELECT Id FROM Program WHERE Name = 'Controller Program' LIMIT 1];
        AcademicTerm term = [SELECT Id FROM AcademicTerm WHERE Name = 'Controller Cohort' LIMIT 1];
        AcademicSession session = [SELECT Id FROM AcademicSession WHERE Name = 'Controller Session' LIMIT 1];

        Workshop__c newW = new Workshop__c(
            Name = 'New Workshop',
            Status__c = 'Draft',
            Program__c = program.Id,
            Cohort__c = term.Id,
            Eligible_Term__c = session.Id,
            Total_Sessions__c = 1
        );
        Test.startTest();
        Workshop__c saved = WorkshopController.saveWorkshop(newW);
        Test.stopTest();
        System.assertNotEquals(null, saved.Id);
    }

    @isTest
    static void testSaveExistingDraftWorkshop() {
        Workshop__c w = [
            SELECT Id, Name, Status__c, Program__c, Cohort__c, Eligible_Term__c, Total_Sessions__c
            FROM Workshop__c
            LIMIT 1
        ];
        w.Name = 'Updated Name';
        Test.startTest();
        WorkshopController.saveWorkshop(w);
        Test.stopTest();
        Workshop__c updated = [SELECT Name FROM Workshop__c WHERE Id = :w.Id];
        System.assertEquals('Updated Name', updated.Name);
    }

    @isTest
    static void testSaveActiveWorkshopThrowsError() {
        Workshop__c w = [SELECT Id, Status__c FROM Workshop__c LIMIT 1];
        w.Status__c = 'Published';
        update w;

        w.Name = 'Trying to edit Published';
        Boolean didThrow = false;
        Test.startTest();
        try {
            WorkshopController.saveWorkshop(w);
        } catch (AuraHandledException ex) {
            didThrow = true;
        }
        Test.stopTest();
        System.assertEquals(true, didThrow, 'Editing a published workshop should throw an exception');
    }

    @isTest
    static void testActivateWorkshop() {
        Workshop__c w = [SELECT Id FROM Workshop__c LIMIT 1];
        Test.startTest();
        WorkshopController.activateWorkshop(w.Id);
        Test.stopTest();
        w = [SELECT Status__c FROM Workshop__c WHERE Id = :w.Id];
        System.assertEquals('Published', w.Status__c);
    }

    @isTest
    static void testCancelWorkshop() {
        Workshop__c w = [SELECT Id FROM Workshop__c LIMIT 1];
        Test.startTest();
        WorkshopController.cancelWorkshop(w.Id);
        Test.stopTest();
        w = [SELECT Status__c FROM Workshop__c WHERE Id = :w.Id];
        System.assertEquals('Cancelled', w.Status__c);
    }

    @isTest
    static void testSaveSession() {
        Workshop__c w = [SELECT Id FROM Workshop__c LIMIT 1];
        Workshop_Session__c ws = new Workshop_Session__c(
            Name        = 'New Session',
            Workshop__c = w.Id,
            Status__c   = 'Scheduled'
        );
        Test.startTest();
        Workshop_Session__c saved = WorkshopController.saveSession(ws);
        Test.stopTest();
        System.assertNotEquals(null, saved.Id);
    }

    @isTest
    static void testSaveBatch() {
        Workshop_Session__c ws = [SELECT Id FROM Workshop_Session__c LIMIT 1];
        Workshop_Batch__c b = new Workshop_Batch__c(
            Workshop_Session__c = ws.Id,
            Batch_Label__c      = 'Batch B',
            Start_DateTime__c   = DateTime.now().addDays(2),
            End_DateTime__c     = DateTime.now().addDays(2).addHours(2),
            Capacity__c         = 5
        );
        Test.startTest();
        Workshop_Batch__c saved = WorkshopController.saveBatch(b);
        Test.stopTest();
        System.assertNotEquals(null, saved.Id);
    }

    @isTest
    static void testGetBatchDetail() {
        Workshop_Batch__c b = [SELECT Id FROM Workshop_Batch__c LIMIT 1];
        Test.startTest();
        WorkshopController.BatchWrapper detail = WorkshopController.getBatchDetail(b.Id);
        Test.stopTest();
        System.assertNotEquals(null, detail.batch);
    }

    @isTest
    static void testGetWorkshopDashboard() {
        Workshop__c workshop = [SELECT Id, Status__c FROM Workshop__c LIMIT 1];
        workshop.Status__c = 'Published';
        update workshop;

        Workshop_Batch__c batch = [SELECT Id, Batch_Label__c FROM Workshop_Batch__c LIMIT 1];
        Contact waitlistedStudent = new Contact(FirstName = 'Waitlisted', LastName = 'Student');
        insert waitlistedStudent;

        insert new List<Workshop_Registration__c>{
            new Workshop_Registration__c(
                Student__c = waitlistedStudent.Id,
                Batch_Label__c = batch.Batch_Label__c,
                Workshop__c = workshop.Id,
                Status__c = 'Waitlisted',
                Registration_Date__c = Date.today()
            )
        };

        Test.startTest();
        List<WorkshopController.WorkshopDashboardWrapper> dashboard =
            WorkshopController.getWorkshopDashboard(null);
        Test.stopTest();

        System.assertEquals(1, dashboard.size(), 'Expected one workshop in dashboard test data');
        System.assertEquals('Controller Test Workshop', dashboard[0].workshopName);
        System.assertEquals('Published', dashboard[0].status, 'Published status should flow to the dashboard');
        System.assertEquals(true, dashboard[0].canDeactivate, 'Published workshops should be deactivatable');
        System.assertEquals(1, dashboard[0].sessions.size(), 'Expected one session in dashboard data');
        System.assertEquals(1, dashboard[0].sessions[0].batches.size(), 'Expected one batch in dashboard data');
        System.assertEquals(
            batch.Batch_Label__c,
            dashboard[0].sessions[0].batches[0].batchLabel,
            'Batch label should match the batch hierarchy data'
        );
    }

    @isTest
    static void testDeactivateWorkshop() {
        Workshop__c workshop = [SELECT Id FROM Workshop__c LIMIT 1];

        Test.startTest();
        WorkshopController.activateWorkshop(workshop.Id);
        WorkshopController.deactivateWorkshop(workshop.Id);
        Test.stopTest();

        workshop = [SELECT Status__c FROM Workshop__c WHERE Id = :workshop.Id];
        System.assertEquals('Inactive', workshop.Status__c);
    }

    @isTest
    static void testGetBatchAttendanceEmpty() {
        Workshop_Batch__c b = [SELECT Id FROM Workshop_Batch__c LIMIT 1];
        Test.startTest();
        List<Workshop_Attendance__c> att = WorkshopController.getBatchAttendance(b.Id);
        Test.stopTest();
        System.assertEquals(0, att.size(), 'No attendance records initially');
    }

    @isTest
    static void testPublishWorkshopWithEmail() {
        Workshop__c workshop = [SELECT Id, Status__c FROM Workshop__c LIMIT 1];
        Program program = [SELECT Id FROM Program WHERE Name = 'Controller Program' LIMIT 1];

        // Create a student contact and enroll in program
        Contact student = new Contact(
            FirstName = 'Publish',
            LastName = 'Test',
            Email = 'publish.test@test.devslcm'
        );
        insert student;

        Account programAccount = new Account(Name = 'Test Program');
        insert programAccount;

        ProgramEnrollment pe = new ProgramEnrollment(
            ContactId = student.Id,
            AccountId = programAccount.Id,
            IsActive = true
        );
        insert pe;

        Test.startTest();
        WorkshopController.publishWorkshopWithEmail(
            workshop.Id,
            'New Workshop Available',
            'This is a test workshop notification.'
        );
        Test.stopTest();

        workshop = [SELECT Status__c, Published_Via_Quick_Action__c FROM Workshop__c WHERE Id = :workshop.Id];
        System.assertEquals('Published', workshop.Status__c, 'Workshop should be published');
        System.assertEquals(true, workshop.Published_Via_Quick_Action__c, 'Published_Via_Quick_Action flag should be set');
    }

    @isTest
    static void testPublishWorkshopWithEmail_NullWorkshopId_Throws() {
        Boolean threwException = false;
        Test.startTest();
        try {
            WorkshopController.publishWorkshopWithEmail(null, 'Subject', 'Body');
        } catch (AuraHandledException ex) {
            threwException = true;
        }
        Test.stopTest();
        System.assert(threwException, 'Null workshop ID should throw exception');
    }

    @isTest
    static void testPublishWorkshopWithEmail_BlankSubject_Throws() {
        Workshop__c workshop = [SELECT Id FROM Workshop__c LIMIT 1];
        Boolean threwException = false;
        Test.startTest();
        try {
            WorkshopController.publishWorkshopWithEmail(workshop.Id, '', 'Body');
        } catch (AuraHandledException ex) {
            threwException = true;
        }
        Test.stopTest();
        System.assert(threwException, 'Blank subject should throw exception');
    }

    @isTest
    static void testGetPublishRecipientCount() {
        Workshop__c workshop = [SELECT Id FROM Workshop__c LIMIT 1];
        Program program = [SELECT Id FROM Program WHERE Name = 'Controller Program' LIMIT 1];

        // Create enrolled students
        List<Contact> students = new List<Contact>();
        for (Integer i = 0; i < 3; i++) {
            students.add(new Contact(
                FirstName = 'Student' + i,
                LastName = 'Recipient',
                Email = 'student' + i + '@test.devslcm'
            ));
        }
        insert students;

        Account programAccount = new Account(Name = 'Test Program');
        insert programAccount;

        List<ProgramEnrollment> enrollments = new List<ProgramEnrollment>();
        for (Contact c : students) {
            enrollments.add(new ProgramEnrollment(
                ContactId = c.Id,
                AccountId = programAccount.Id,
                IsActive = true
            ));
        }
        insert enrollments;

        Test.startTest();
        Integer count = WorkshopController.getPublishRecipientCount(workshop.Id);
        Test.stopTest();

        System.assertEquals(3, count, 'Should return 3 eligible recipients');
    }

    @isTest
    static void testGetPublishRecipientCount_NullWorkshopId() {
        Test.startTest();
        Integer count = WorkshopController.getPublishRecipientCount(null);
        Test.stopTest();
        System.assertEquals(0, count, 'Null workshop ID should return 0');
    }

    @isTest
    static void testGetPublishRecipientCount_NoEnrollments() {
        Workshop__c workshop = [SELECT Id FROM Workshop__c LIMIT 1];
        Test.startTest();
        Integer count = WorkshopController.getPublishRecipientCount(workshop.Id);
        Test.stopTest();
        System.assertEquals(0, count, 'No enrollments should return 0');
    }
}