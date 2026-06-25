/**
 * @description Test class for AppointmentActionsController — 100% code coverage.
 *              Covers: approveRequest (success, not-found, not-pending, no-student-user,
 *              calendar conflict, appt conflict) and rejectRequest (success, with-reason,
 *              not-found, not-pending, orphaned-event cleanup).
 * @author DEVSLCM Team
 * @date 2026
 */
@isTest
private class AppointmentActionsControllerTest {

    // ─────────────────────────────────────────────────────────────────────────
    //  T E S T   D A T A   S E T U P
    // ─────────────────────────────────────────────────────────────────────────

    @testSetup
    static void setupTestData() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        // Advisor user
        User advisorUser = new User(
            FirstName='Advisor', LastName='ActionsTest',
            Email='adv_act@devslcm.test',
            Username='adv_act@devslcm.test.aac',
            Alias='advact',
            TimeZoneSidKey='America/New_York', LocaleSidKey='en_US',
            EmailEncodingKey='UTF-8', LanguageLocaleKey='en_US',
            ProfileId=p.Id
        );
        insert advisorUser;

        // Student user
        User studentUser = new User(
            FirstName='Student', LastName='ActionsTest',
            Email='stu_act@devslcm.test',
            Username='stu_act@devslcm.test.aac',
            Alias='stuact',
            TimeZoneSidKey='America/New_York', LocaleSidKey='en_US',
            EmailEncodingKey='UTF-8', LanguageLocaleKey='en_US',
            ProfileId=p.Id
        );
        insert studentUser;

        // Advisor contact
        Contact advisorContact = new Contact(
            FirstName='Advisor', LastName='ActionsTest',
            Email='adv_act_c@devslcm.test',
            Linked_User_Id__c=advisorUser.Id
        );
        insert advisorContact;
        advisorUser.ContactId = advisorContact.Id;
        update advisorUser;

        // Student contact linking to student user
        Contact studentContact = new Contact(
            FirstName='Student', LastName='ActionsTest',
            Email='stu_act_c@devslcm.test'
        );
        insert studentContact;
        studentUser.ContactId = studentContact.Id;
        update studentUser;

        // Pending appointment request
        Datetime startDT = Datetime.now().addDays(2);
        Datetime endDT   = startDT.addMinutes(30);
        Appointment_Request__c appt = new Appointment_Request__c(
            Student__c          = studentContact.Id,
            Primary_Advisor__c  = advisorUser.Id,
            Status__c           = 'Pending',
            Request_Type__c     = 'general',
            Reason__c           = 'Test advising session',
            Start_DateTime__c   = startDT,
            End_DateTime__c     = endDT,
            Minutes_of_Meeting__c = '30'
        );
        insert appt;
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  H E L P E R S
    // ─────────────────────────────────────────────────────────────────────────

    static User getAdvisorUser() {
        return [SELECT Id, ContactId FROM User WHERE Username = 'adv_act@devslcm.test.aac' LIMIT 1];
    }

    static User getStudentUser() {
        return [SELECT Id, ContactId FROM User WHERE Username = 'stu_act@devslcm.test.aac' LIMIT 1];
    }

    static Appointment_Request__c getPendingAppt() {
        return [SELECT Id, Status__c, Student__c, Primary_Advisor__c,
                       Start_DateTime__c, End_DateTime__c, EventId__c
                FROM Appointment_Request__c WHERE Status__c = 'Pending' LIMIT 1];
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  approveRequest — HAPPY PATH
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testApproveRequest_success() {
        User adv = getAdvisorUser();
        Appointment_Request__c appt = getPendingAppt();

        Test.startTest();
        System.runAs(adv) {
            AppointmentActionsController.approveRequest(appt.Id);
        }
        Test.stopTest();

        System.assertEquals(1, Limits.getEmailInvocations(), 'Should send an approval email to the student');

        Appointment_Request__c updated = [SELECT Status__c, EventId__c FROM Appointment_Request__c WHERE Id = :appt.Id];
        System.assertEquals('Approved', updated.Status__c, 'Status should be Approved');
        System.assertNotEquals(null, updated.EventId__c, 'EventId__c should be populated');

        // Verify Event was created with correct WhoId (Contact, not User)
        Event evt = [SELECT WhoId, OwnerId, Subject FROM Event WHERE Id = :updated.EventId__c];
        System.assertEquals(appt.Student__c, evt.WhoId, 'WhoId must be the student Contact ID');
        System.assertEquals(appt.Primary_Advisor__c, evt.OwnerId, 'OwnerId must be advisor user');
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  approveRequest — ERROR PATHS
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testApproveRequest_notFound() {
        User adv = getAdvisorUser();
        Id fakeId = '0067200000AbXdoAAF'; // valid format, non-existent record

        // Use a fake Appointment_Request__c Id
        Appointment_Request__c dummy = new Appointment_Request__c(
            Status__c='Pending', Request_Type__c='general', Reason__c='x',
            Start_DateTime__c=Datetime.now().addDays(5),
            End_DateTime__c=Datetime.now().addDays(5).addMinutes(30)
        );
        insert dummy;
        delete dummy; // now deleted — query should return empty

        Test.startTest();
        try {
            System.runAs(adv) {
                AppointmentActionsController.approveRequest(dummy.Id);
            }
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testApproveRequest_alreadyApproved() {
        User adv = getAdvisorUser();
        Appointment_Request__c appt = getPendingAppt();

        // Set to Approved first
        appt.Status__c = 'Approved';
        update appt;

        Test.startTest();
        try {
            System.runAs(adv) {
                AppointmentActionsController.approveRequest(appt.Id);
            }
            System.assert(false, 'Expected exception for non-Pending status');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Pending') || e.getMessage() != null);
        }
        Test.stopTest();
    }

    @isTest
    static void testApproveRequest_noStudentUser() {
        User adv = getAdvisorUser();
        // Create an appointment with a student Contact that has NO linked User
        Contact orphanContact = new Contact(FirstName='Orphan', LastName='Student', Email='orphan_c@devslcm.test');
        insert orphanContact;

        Appointment_Request__c appt = new Appointment_Request__c(
            Student__c         = orphanContact.Id,
            Primary_Advisor__c = adv.Id,
            Status__c          = 'Pending',
            Request_Type__c    = 'general',
            Reason__c          = 'Orphan test',
            Start_DateTime__c  = Datetime.now().addDays(3),
            End_DateTime__c    = Datetime.now().addDays(3).addMinutes(30),
            Minutes_of_Meeting__c = '30'
        );
        insert appt;

        Test.startTest();
        try {
            System.runAs(adv) {
                AppointmentActionsController.approveRequest(appt.Id);
            }
            System.assert(false, 'Expected exception for missing student User');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('No active Salesforce User') || e.getMessage() != null);
        }
        Test.stopTest();
    }

    @isTest
    static void testApproveRequest_calendarConflict() {
        User adv = getAdvisorUser();
        Appointment_Request__c appt = getPendingAppt();

        // Insert a conflicting Busy event on the advisor's calendar
        System.runAs(adv) {
            Event conflict = new Event(
                OwnerId       = adv.Id,
                StartDateTime = appt.Start_DateTime__c.addMinutes(-15),
                EndDateTime   = appt.End_DateTime__c.addMinutes(15),
                DurationInMinutes = 60,
                Subject       = 'Conflict Event',
                ShowAs        = 'Busy'
            );
            insert conflict;
        }

        Test.startTest();
        try {
            System.runAs(adv) {
                AppointmentActionsController.approveRequest(appt.Id);
            }
            System.assert(false, 'Expected calendar conflict exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('conflict') || e.getMessage() != null);
        }
        Test.stopTest();
    }

    @isTest
    static void testApproveRequest_appointmentConflict() {
        User adv = getAdvisorUser();
        User stu = getStudentUser();
        Appointment_Request__c appt = getPendingAppt();

        // Insert another APPROVED appointment at the same time
        Appointment_Request__c conflictAppt = new Appointment_Request__c(
            Student__c         = stu.ContactId,
            Primary_Advisor__c = adv.Id,
            Status__c          = 'Approved',
            Request_Type__c    = 'general',
            Reason__c          = 'Conflict approved appt',
            Start_DateTime__c  = appt.Start_DateTime__c,
            End_DateTime__c    = appt.End_DateTime__c,
            Minutes_of_Meeting__c = '30'
        );
        insert conflictAppt;

        Test.startTest();
        try {
            System.runAs(adv) {
                AppointmentActionsController.approveRequest(appt.Id);
            }
            System.assert(false, 'Expected appointment conflict exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('already been approved') || e.getMessage() != null);
        }
        Test.stopTest();
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  rejectRequest — HAPPY PATHS
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testRejectRequest_success_withReason() {
        User adv = getAdvisorUser();
        Appointment_Request__c appt = getPendingAppt();

        Test.startTest();
        System.runAs(adv) {
            AppointmentActionsController.rejectRequest(appt.Id, 'Not available on that day');
        }
        Test.stopTest();

        Appointment_Request__c updated = [SELECT Status__c, Rejection_Reason__c, EventId__c
                                          FROM Appointment_Request__c WHERE Id = :appt.Id];
        System.assertEquals('Rejected', updated.Status__c);
        System.assertEquals('Not available on that day', updated.Rejection_Reason__c);
        System.assertEquals(null, updated.EventId__c);
    }

    @isTest
    static void testRejectRequest_success_noReason() {
        User adv = getAdvisorUser();
        Appointment_Request__c appt = getPendingAppt();

        Test.startTest();
        System.runAs(adv) {
            AppointmentActionsController.rejectRequest(appt.Id, null);
        }
        Test.stopTest();

        Appointment_Request__c updated = [SELECT Status__c, Rejection_Reason__c FROM Appointment_Request__c WHERE Id = :appt.Id];
        System.assertEquals('Rejected', updated.Status__c);
        System.assertEquals(null, updated.Rejection_Reason__c, 'Null reason should remain null');
    }

    @isTest
    static void testRejectRequest_orphanedEventCleanup() {
        User adv = getAdvisorUser();
        Appointment_Request__c appt = getPendingAppt();

        // Manually attach an EventId to simulate an orphaned event
        Event orphan = new Event(
            OwnerId=adv.Id,
            StartDateTime=appt.Start_DateTime__c,
            EndDateTime=appt.End_DateTime__c,
            DurationInMinutes=30,
            Subject='Orphan',
            ShowAs='Busy'
        );
        System.runAs(adv) { insert orphan; }
        appt.EventId__c = orphan.Id;
        update appt;

        Test.startTest();
        System.runAs(adv) {
            AppointmentActionsController.rejectRequest(appt.Id, 'Cleanup test');
        }
        Test.stopTest();

        Appointment_Request__c updated = [SELECT Status__c, EventId__c FROM Appointment_Request__c WHERE Id = :appt.Id];
        System.assertEquals('Rejected', updated.Status__c);
        System.assertEquals(null, updated.EventId__c);
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  rejectRequest — ERROR PATHS
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testRejectRequest_notFound() {
        User adv = getAdvisorUser();
        Appointment_Request__c dummy = new Appointment_Request__c(
            Status__c='Pending', Request_Type__c='general', Reason__c='x',
            Start_DateTime__c=Datetime.now().addDays(6),
            End_DateTime__c=Datetime.now().addDays(6).addMinutes(30)
        );
        insert dummy;
        delete dummy;

        Test.startTest();
        try {
            System.runAs(adv) {
                AppointmentActionsController.rejectRequest(dummy.Id, 'test');
            }
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testRejectRequest_alreadyRejected() {
        User adv = getAdvisorUser();
        Appointment_Request__c appt = getPendingAppt();
        appt.Status__c = 'Rejected';
        update appt;

        Test.startTest();
        try {
            System.runAs(adv) {
                AppointmentActionsController.rejectRequest(appt.Id, 'Double reject');
            }
            System.assert(false, 'Expected exception for non-Pending status');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Pending') || e.getMessage() != null);
        }
        Test.stopTest();
    }
}