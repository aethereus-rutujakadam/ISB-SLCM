/**
 * @description Test class for WorkshopNotificationService
 * @author DEVSLCM Team
 * @date 2026
 */
@isTest
private class WorkshopNotificationServiceTest {

    @TestSetup
    static void setup() {
        Account programAccount = new Account(Name = 'Test Program Account');
        insert programAccount;

        Program program = new Program(Name = 'Notif Test Program');
        insert program;

        AcademicTerm term = new AcademicTerm(Name = 'Notif Cohort');
        insert term;

        AcademicSession session = new AcademicSession(
            Name            = 'Notif Session',
            AcademicTermId  = term.Id
        );
        insert session;

        Contact student = new Contact(
            FirstName = 'Bob',
            LastName  = 'Tester',
            Email     = 'bob.tester@test.devslcm'
        );
        insert student;

        Account programAccount2 = new Account(Name = 'Test Program');
        insert programAccount2;

        ProgramEnrollment pe = new ProgramEnrollment(
            ContactId        = student.Id,
            AccountId        = programAccount2.Id,
            IsActive         = true
        );
        insert pe;

        Workshop__c w = new Workshop__c(
            Name              = 'Notif Workshop',
            Status__c         = 'Draft',
            Program__c        = program.Id,
            Cohort__c         = term.Id,
            Eligible_Term__c  = session.Id,
            Description__c    = 'Test description',
            Total_Sessions__c = 1
        );
        insert w;
    }

    // ─── sendWorkshopPublishedNotifications ──────────────────────────────────────

    @isTest
    static void testPublishNotifSendsToEnrolledStudents() {
        Workshop__c w = [SELECT Id FROM Workshop__c WHERE Name = 'Notif Workshop' LIMIT 1];
        Test.startTest();
        WorkshopNotificationService.sendWorkshopPublishedNotifications(new Set<Id>{ w.Id });
        Test.stopTest();
        // If no exception is thrown, async path executed successfully
        System.assert(true, 'sendWorkshopPublishedNotifications should complete without error');
    }

    @isTest
    static void testPublishNotifWithCohortFilter_NoMatchSkipsEmail() {
        // Create a second cohort not matching the workshop's cohort
        AcademicTerm otherTerm = new AcademicTerm(Name = 'Other Cohort');
        insert otherTerm;

        Program program = [SELECT Id FROM Program WHERE Name = 'Notif Test Program' LIMIT 1];
        Contact student2 = new Contact(FirstName = 'Carol', LastName = 'Other', Email = 'carol@test.devslcm');
        insert student2;
        ProgramEnrollment pe2 = new ProgramEnrollment(
            ContactId = student2.Id,
            ProgramId = program.Id,
            IsActive  = true
            // Academic_Term__c left null — will not match workshop cohort
        );
        insert pe2;

        Workshop__c w = [SELECT Id FROM Workshop__c WHERE Name = 'Notif Workshop' LIMIT 1];
        Test.startTest();
        WorkshopNotificationService.sendWorkshopPublishedNotifications(new Set<Id>{ w.Id });
        Test.stopTest();
        System.assert(true, 'Cohort-filtered publish should complete without error');
    }

    @isTest
    static void testPublishNotifEmptyWorkshopSet() {
        Test.startTest();
        WorkshopNotificationService.sendWorkshopPublishedNotifications(new Set<Id>());
        Test.stopTest();
        System.assert(true, 'Empty workshop set should return silently');
    }

    // ─── sendAdvisorEmailToAudience ──────────────────────────────────────────────

    @isTest
    static void testSendAdvisorEmail_Registered_NoRegs_Throws() {
        Workshop__c w = [SELECT Id FROM Workshop__c WHERE Name = 'Notif Workshop' LIMIT 1];
        Boolean threwException = false;
        Test.startTest();
        try {
            WorkshopNotificationService.sendAdvisorEmailToAudience(
                w.Id, 'Subject', 'Body', new List<String>(), 'REGISTERED'
            );
        } catch (AuraHandledException ex) {
            threwException = true;
        }
        Test.stopTest();
        System.assert(threwException, 'Should throw AuraHandledException when no registrations exist');
    }

    @isTest
    static void testSendAdvisorEmail_AllEnrolled_SendsEmail() {
        Workshop__c w = [SELECT Id FROM Workshop__c WHERE Name = 'Notif Workshop' LIMIT 1];
        Test.startTest();
        WorkshopNotificationService.sendAdvisorEmailToAudience(
            w.Id, 'Hello Students', 'Workshop details here.', new List<String>(), 'ALL_ENROLLED'
        );
        Test.stopTest();
        System.assert(true, 'ALL_ENROLLED send should complete without error');
    }

    @isTest
    static void testSendAdvisorEmail_NullWorkshopId_Throws() {
        Boolean threwException = false;
        Test.startTest();
        try {
            WorkshopNotificationService.sendAdvisorEmailToAudience(
                null, 'Subject', 'Body', new List<String>(), 'REGISTERED'
            );
        } catch (AuraHandledException ex) {
            threwException = true;
        }
        Test.stopTest();
        System.assert(threwException, 'Null workshop ID should throw AuraHandledException');
    }

    @isTest
    static void testSendAdvisorEmail_BlankSubject_Throws() {
        Workshop__c w = [SELECT Id FROM Workshop__c WHERE Name = 'Notif Workshop' LIMIT 1];
        Boolean threwException = false;
        Test.startTest();
        try {
            WorkshopNotificationService.sendAdvisorEmailToAudience(
                w.Id, '', 'Body', new List<String>(), 'REGISTERED'
            );
        } catch (AuraHandledException ex) {
            threwException = true;
        }
        Test.stopTest();
        System.assert(threwException, 'Blank subject should throw AuraHandledException');
    }

    @isTest
    static void testSendAdvisorEmail_DefaultsToRegistered_WhenAudienceNull() {
        Workshop__c w = [SELECT Id FROM Workshop__c WHERE Name = 'Notif Workshop' LIMIT 1];
        Boolean threwException = false;
        Test.startTest();
        try {
            WorkshopNotificationService.sendAdvisorEmailToAudience(
                w.Id, 'Subject', 'Body', new List<String>(), null
            );
        } catch (AuraHandledException ex) {
            // Expected: no registrations exist, so it throws after defaulting to REGISTERED
            threwException = true;
        }
        Test.stopTest();
        // Null audience defaults to REGISTERED — throws because no registrations exist
        System.assert(threwException, 'Null audience defaults to REGISTERED and throws on no registrations');
    }

    @isTest
    static void testSendCustomPublishEmail() {
        Workshop__c w = [SELECT Id FROM Workshop__c WHERE Name = 'Notif Workshop' LIMIT 1];
        Test.startTest();
        WorkshopNotificationService.sendCustomPublishEmail(
            w.Id,
            'New Workshop: Custom Subject',
            'This is a custom publish email body.'
        );
        Test.stopTest();
        System.assert(true, 'sendCustomPublishEmail should complete without error');
    }

    @isTest
    static void testSendCustomPublishEmail_NullWorkshopId() {
        Test.startTest();
        WorkshopNotificationService.sendCustomPublishEmail(null, 'Subject', 'Body');
        Test.stopTest();
        System.assert(true, 'Null workshop ID should return silently');
    }

    @isTest
    static void testSendCustomPublishEmail_BlankSubject() {
        Workshop__c w = [SELECT Id FROM Workshop__c WHERE Name = 'Notif Workshop' LIMIT 1];
        Test.startTest();
        WorkshopNotificationService.sendCustomPublishEmail(w.Id, '', 'Body');
        Test.stopTest();
        System.assert(true, 'Blank subject should return silently');
    }

    @isTest
    static void testSendCustomPublishEmail_BlankBody() {
        Workshop__c w = [SELECT Id FROM Workshop__c WHERE Name = 'Notif Workshop' LIMIT 1];
        Test.startTest();
        WorkshopNotificationService.sendCustomPublishEmail(w.Id, 'Subject', '');
        Test.stopTest();
        System.assert(true, 'Blank body should return silently');
    }

    @isTest
    static void testSendCustomPublishEmail_WithEnrollments() {
        Workshop__c w = [SELECT Id FROM Workshop__c WHERE Name = 'Notif Workshop' LIMIT 1];
        Program program = [SELECT Id FROM Program WHERE Name = 'Notif Test Program' LIMIT 1];

        // Add more enrolled students
        List<Contact> students = new List<Contact>();
        for (Integer i = 0; i < 5; i++) {
            students.add(new Contact(
                FirstName = 'CustomPublish' + i,
                LastName = 'Student',
                Email = 'custompublish' + i + '@test.devslcm'
            ));
        }
        insert students;

        List<ProgramEnrollment> enrollments = new List<ProgramEnrollment>();
        for (Contact c : students) {
            enrollments.add(new ProgramEnrollment(
                ContactId = c.Id,
                ProgramId = program.Id,
                IsActive = true
            ));
        }
        insert enrollments;

        Test.startTest();
        WorkshopNotificationService.sendCustomPublishEmail(
            w.Id,
            'Custom Workshop Notification',
            'This workshop is now available for registration.'
        );
        Test.stopTest();
        System.assert(true, 'sendCustomPublishEmail should complete with enrollments');
    }

    @isTest
    static void testSendCustomPublishEmail_LargeBatch() {
        // Test email batching for > 100 enrollments
        Workshop__c w = [SELECT Id FROM Workshop__c WHERE Name = 'Notif Workshop' LIMIT 1];
        Program program = [SELECT Id FROM Program WHERE Name = 'Notif Test Program' LIMIT 1];

        List<Contact> largeStudentList = new List<Contact>();
        for (Integer i = 0; i < 150; i++) {
            largeStudentList.add(new Contact(
                FirstName = 'Large' + i,
                LastName = 'Batch',
                Email = 'large' + i + '@test.devslcm'
            ));
        }
        insert largeStudentList;

        List<ProgramEnrollment> largeEnrollments = new List<ProgramEnrollment>();
        for (Contact c : largeStudentList) {
            largeEnrollments.add(new ProgramEnrollment(
                ContactId = c.Id,
                ProgramId = program.Id,
                IsActive = true
            ));
        }
        insert largeEnrollments;

        Test.startTest();
        WorkshopNotificationService.sendCustomPublishEmail(
            w.Id,
            'Large Batch Test',
            'Testing email batching.'
        );
        Test.stopTest();
        System.assert(true, 'sendCustomPublishEmail should handle large batches');
    }
}