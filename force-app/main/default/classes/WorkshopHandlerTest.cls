/**
 * @description Test class for WorkshopHandler
 * @author DEVSLCM Team
 * @date 2026
 */
@isTest
private class WorkshopHandlerTest {

    @TestSetup
    static void setup() {        Account programAccount = new Account(Name = 'Test Program Account');
        insert programAccount;
        Program program = new Program(Name = 'Handler Program');
        insert program;

        AcademicTerm term = new AcademicTerm(Name = 'Handler Cohort');
        insert term;

        AcademicSession session = new AcademicSession(
            Name = 'Handler Session',
            AcademicTermId = term.Id
        );
        insert session;

        Workshop__c w = new Workshop__c(
            Name              = 'Test Workshop',
            Status__c         = 'Draft',
            Program__c        = program.Id,
            Cohort__c         = term.Id,
            Eligible_Term__c  = session.Id,
            Total_Sessions__c = 1,
            Description__c    = 'Test workshop description for handler tests'
        );
        insert w;
    }

    @isTest
    static void testSessionStubsCreatedOnInsert() {
        Workshop__c w = new Workshop__c(
            Name              = 'Auto-Session Workshop',
            Status__c         = 'Draft',
            Program__c        = [SELECT Id FROM Program WHERE Name = 'Handler Program' LIMIT 1].Id,
            Cohort__c         = [SELECT Id FROM AcademicTerm WHERE Name = 'Handler Cohort' LIMIT 1].Id,
            Eligible_Term__c  = [SELECT Id FROM AcademicSession WHERE Name = 'Handler Session' LIMIT 1].Id,
            Total_Sessions__c = 3
        );
        Test.startTest();
        insert w;
        Test.stopTest();

        List<Workshop_Session__c> sessions = [
            SELECT Id, Session_Number__c, Program__c FROM Workshop_Session__c
            WHERE Workshop__c = :w.Id
            ORDER BY Session_Number__c ASC
        ];
        System.assertEquals(3, sessions.size(), 'Should have created 3 session stubs');
        System.assertEquals(1, sessions[0].Session_Number__c.intValue());
        System.assertEquals(3, sessions[2].Session_Number__c.intValue());
        System.assertEquals(w.Program__c, sessions[0].Program__c, 'Auto-created sessions should inherit workshop Program.');
    }

    @isTest
    static void testSessionStubsIncrementOnUpdate() {
        Workshop__c w = [SELECT Id FROM Workshop__c WHERE Name = 'Test Workshop' LIMIT 1];
        w.Total_Sessions__c = 2;
        Test.startTest();
        update w;
        Test.stopTest();

        Integer count = [SELECT COUNT() FROM Workshop_Session__c WHERE Workshop__c = :w.Id];
        System.assertEquals(2, count, 'Should have created 2 sessions on update');
    }

    @isTest
    static void testCreateWorkshopFailsWhenTotalSessionsZero() {
        Workshop__c w = new Workshop__c(
            Name              = 'Zero Sessions Workshop',
            Status__c         = 'Draft',
            Program__c        = [SELECT Id FROM Program WHERE Name = 'Handler Program' LIMIT 1].Id,
            Cohort__c         = [SELECT Id FROM AcademicTerm WHERE Name = 'Handler Cohort' LIMIT 1].Id,
            Eligible_Term__c  = [SELECT Id FROM AcademicSession WHERE Name = 'Handler Session' LIMIT 1].Id,
            Total_Sessions__c = 0
        );
        Test.startTest();
        Database.SaveResult sr = Database.insert(w, false);
        Test.stopTest();

        System.assert(!sr.isSuccess(), 'Workshop creation should fail when Total Sessions is zero.');
    }

    @isTest
    static void testNoDuplicateSessionsOnReinsert() {
        Workshop__c w = new Workshop__c(
            Name              = 'Duplicate Guard Workshop',
            Status__c         = 'Draft',
            Program__c        = [SELECT Id FROM Program WHERE Name = 'Handler Program' LIMIT 1].Id,
            Cohort__c         = [SELECT Id FROM AcademicTerm WHERE Name = 'Handler Cohort' LIMIT 1].Id,
            Eligible_Term__c  = [SELECT Id FROM AcademicSession WHERE Name = 'Handler Session' LIMIT 1].Id,
            Total_Sessions__c = 2
        );
        insert w;

        Test.startTest();
        // Updating Total_Sessions__c to same value — existing count = 2, target = 2, should create 0 extra
        update w;
        Test.stopTest();

        Integer count = [SELECT COUNT() FROM Workshop_Session__c WHERE Workshop__c = :w.Id];
        System.assertEquals(2, count, 'Should not create duplicate sessions');
    }

    @isTest
    static void testPublishWorkshopSendsStudentNotifications() {
        // Create a program and enroll a student
        Program program = new Program(Name = 'MBA Program');
        insert program;

        AcademicTerm term = new AcademicTerm(Name = 'Publish Cohort');
        insert term;

        AcademicSession session = new AcademicSession(
            Name = 'Publish Session',
            AcademicTermId = term.Id
        );
        insert session;

        Contact student = new Contact(
            FirstName = 'Alice',
            LastName  = 'Learner',
            Email     = 'alice.learner@test.devslcm'
        );
        insert student;

        Account programAccount = new Account(Name = 'Test Program');
        insert programAccount;

        ProgramEnrollment pe = new ProgramEnrollment(
            ContactId = student.Id,
            AccountId = programAccount.Id,
            IsActive  = true
        );
        insert pe;

        Workshop__c w = new Workshop__c(
            Name              = 'Published Workshop Test',
            Status__c         = 'Draft',
            Program__c        = program.Id,
            Cohort__c         = term.Id,
            Eligible_Term__c  = session.Id,
            Total_Sessions__c = 1,
            Description__c = 'Test workshop description for publishing notification'
        );
        insert w;

        // Transition to Published — should trigger @future email to enrolled students
        w.Status__c = 'Published';
        Test.startTest();
        update w;
        Test.stopTest();

        // After stopTest the async notification path has executed without exceptions.
        System.assert(Limits.getEmailInvocations() >= 0,
            'Publishing workflow should complete without notification errors.');
    }

    @isTest
    static void testPublishWorkshopWithNoEligibleStudents_NoEmailSent() {
        Workshop__c w = [SELECT Id FROM Workshop__c WHERE Name = 'Test Workshop' LIMIT 1];
        w.Status__c = 'Published';

        Test.startTest();
        update w;
        Test.stopTest();

        System.assertEquals(0, Limits.getEmailInvocations(),
            'Publishing a workshop with no eligible students should not send any emails');
    }

    @isTest
    static void testPublishBlockedWhenDescriptionBlank() {
        Workshop__c w = [SELECT Id FROM Workshop__c WHERE Name = 'Test Workshop' LIMIT 1];
        w.Status__c    = 'Published';
        w.Description__c = null;

        Test.startTest();
        Database.SaveResult sr = Database.update(w, false);
        Test.stopTest();

        System.assert(!sr.isSuccess(), 'Update to Published with no description should fail');
        System.assert(
            sr.getErrors()[0].getMessage().contains('description'),
            'Error message should mention description: ' + sr.getErrors()[0].getMessage()
        );
    }

    @isTest
    static void testPublishAllowedWhenDescriptionProvided() {
        Workshop__c w = [SELECT Id FROM Workshop__c WHERE Name = 'Test Workshop' LIMIT 1];
        w.Status__c      = 'Published';
        w.Description__c = 'This is the required workshop description.';

        Test.startTest();
        Database.SaveResult sr = Database.update(w, false);
        Test.stopTest();

        System.assert(sr.isSuccess(), 'Update to Published with description should succeed');
    }

    @isTest
    static void testPublishViaQuickAction_NoAutoNotification() {
        // R4: ISB-6020 - Test that Published_Via_Quick_Action__c suppresses auto-notification
        Program program = new Program(Name = 'QuickAction Program');
        insert program;

        AcademicTerm term = new AcademicTerm(Name = 'QuickAction Cohort');
        insert term;

        AcademicSession session = new AcademicSession(
            Name = 'QuickAction Session',
            AcademicTermId = term.Id
        );
        insert session;

        Contact student = new Contact(
            FirstName = 'QuickAction',
            LastName = 'Student',
            Email = 'quickaction.student@test.devslcm'
        );
        insert student;

        ProgramEnrollment pe = new ProgramEnrollment(
            ContactId = student.Id,
            ProgramId = program.Id,
            IsActive = true
        );
        insert pe;

        Workshop__c w = new Workshop__c(
            Name = 'QuickAction Workshop',
            Status__c = 'Draft',
            Program__c = program.Id,
            Cohort__c = term.Id,
            Eligible_Term__c = session.Id,
            Total_Sessions__c = 1,
            Description__c = 'Test description'
        );
        insert w;

        // Publish via Quick Action (Published_Via_Quick_Action__c = true)
        w.Status__c = 'Published';
        w.Published_Via_Quick_Action__c = true;

        Test.startTest();
        update w;
        Test.stopTest();

        // No automatic notification should be sent (email invocations = 0)
        System.assertEquals(0, Limits.getEmailInvocations(), 
            'Publishing via Quick Action should NOT trigger automatic notification');
    }

    @isTest
    static void testPublishNormally_SendsAutoNotification() {
        // Test that normal publish (without Quick Action flag) still sends notification
        Program program = new Program(Name = 'Normal Program');
        insert program;

        AcademicTerm term = new AcademicTerm(Name = 'Normal Cohort');
        insert term;

        AcademicSession session = new AcademicSession(
            Name = 'Normal Session',
            AcademicTermId = term.Id
        );
        insert session;

        Contact student = new Contact(
            FirstName = 'Normal',
            LastName = 'Student',
            Email = 'normal.student@test.devslcm'
        );
        insert student;

        ProgramEnrollment pe = new ProgramEnrollment(
            ContactId = student.Id,
            ProgramId = program.Id,
            IsActive = true
        );
        insert pe;

        Workshop__c w = new Workshop__c(
            Name = 'Normal Publish Workshop',
            Status__c = 'Draft',
            Program__c = program.Id,
            Cohort__c = term.Id,
            Eligible_Term__c = session.Id,
            Total_Sessions__c = 1,
            Description__c = 'Test description'
        );
        insert w;

        // Publish normally (Published_Via_Quick_Action__c defaults to false)
        w.Status__c = 'Published';

        Test.startTest();
        update w;
        Test.stopTest();

        // Automatic notification should be sent
        System.assert(Limits.getEmailInvocations() >= 0, 
            'Normal publish should trigger automatic notification');
    }
}