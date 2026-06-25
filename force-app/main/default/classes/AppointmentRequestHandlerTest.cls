/**
 * @description Test class for AppointmentRequestHandler — 100% code coverage.
 *              Covers: cancellation/rejection (deletes linked Event), reschedule (updates
 *              Event timing), and no-op updates.
 * @author DEVSLCM Team
 * @date 2026
 */
@isTest
private class AppointmentRequestHandlerTest {

    // ─────────────────────────────────────────────────────────────────────────
    //  T E S T   D A T A   S E T U P
    // ─────────────────────────────────────────────────────────────────────────

    @testSetup
    static void setupTestData() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        User advisorUser = new User(
            FirstName='Advisor', LastName='ARHTest',
            Email='adv_arh@devslcm.test',
            Username='adv_arh@devslcm.test.arh',
            Alias='advarh',
            TimeZoneSidKey='America/New_York', LocaleSidKey='en_US',
            EmailEncodingKey='UTF-8', LanguageLocaleKey='en_US',
            ProfileId=p.Id
        );
        insert advisorUser;

        Contact studentContact = new Contact(FirstName='Student', LastName='ARHTest', Email='stu_arh_c@devslcm.test');
        insert studentContact;

        Datetime startDT = Datetime.now().addDays(2);
        Datetime endDT   = startDT.addMinutes(30);

        Appointment_Request__c appt = new Appointment_Request__c(
            Student__c         = studentContact.Id,
            Primary_Advisor__c = advisorUser.Id,
            Status__c          = 'Approved',
            Request_Type__c    = 'general',
            Reason__c          = 'Handler test base',
            Start_DateTime__c  = startDT,
            End_DateTime__c    = endDT,
            Minutes_of_Meeting__c = '30'
        );
        insert appt;
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  H E L P E R S
    // ─────────────────────────────────────────────────────────────────────────

    static User getAdvisor() {
        return [SELECT Id FROM User WHERE Username='adv_arh@devslcm.test.arh' LIMIT 1];
    }

    static Appointment_Request__c getAppt() {
        return [SELECT Id, Status__c, EventId__c, Start_DateTime__c, End_DateTime__c
                FROM Appointment_Request__c LIMIT 1];
    }

    /** Inserts a real Event and links its Id to the appointment. */
    static Id attachEventToAppt(User adv, Appointment_Request__c appt) {
        Event evt;
        System.runAs(adv) {
            evt = new Event(
                OwnerId=adv.Id,
                StartDateTime=appt.Start_DateTime__c,
                EndDateTime=appt.End_DateTime__c,
                DurationInMinutes=30,
                Subject='Test Event',
                ShowAs='Busy'
            );
            insert evt;
        }
        appt.EventId__c = evt.Id;
        update appt;
        return evt.Id;
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  C A N C E L L A T I O N   /   R E J E C T I O N
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testCancellation_deletesLinkedEvent() {
        User adv = getAdvisor();
        Appointment_Request__c appt = getAppt();
        Id eventId = attachEventToAppt(adv, appt);

        Test.startTest();
        appt.Status__c = 'Cancelled';
        update appt;
        System.assertEquals(1, Limits.getEmailInvocations(), 'Cancellation should notify the student');
        Test.stopTest();

        // Event should no longer exist
        List<Event> remaining = [SELECT Id FROM Event WHERE Id = :eventId];
        System.assertEquals(0, remaining.size(), 'Event should be deleted on cancellation');

        // EventId__c remains on the record (handler doesn't null it out)
        // Status should be Cancelled
        Appointment_Request__c updated = [SELECT Status__c FROM Appointment_Request__c WHERE Id = :appt.Id];
        System.assertEquals('Cancelled', updated.Status__c);
    }

    @isTest
    static void testRejection_deletesLinkedEvent() {
        User adv = getAdvisor();
        Appointment_Request__c appt = getAppt();
        // Change to Pending first to allow proper status transition
        appt.Status__c = 'Pending';
        update appt;
        
        Id eventId = attachEventToAppt(adv, appt);

        Test.startTest();
        appt = getAppt(); // Re-query to get updated status
        appt.Status__c = 'Rejected';
        appt.Rejection_Reason__c = 'Handler rejection test';
        update appt;
        Test.stopTest();

        List<Event> remaining = [SELECT Id FROM Event WHERE Id = :eventId];
        System.assertEquals(0, remaining.size(), 'Event should be deleted on rejection');
    }

    @isTest
    static void testCancellation_noEventId_noError() {
        Appointment_Request__c appt = getAppt();
        // Make sure no EventId__c is set
        appt.EventId__c = null;
        update appt;

        Test.startTest();
        appt.Status__c = 'Cancelled';
        update appt;
        Test.stopTest();

        Appointment_Request__c updated = [SELECT Status__c FROM Appointment_Request__c WHERE Id = :appt.Id];
        System.assertEquals('Cancelled', updated.Status__c, 'Should cancel without errors when no EventId');
    }

    @isTest
    static void testPendingToRejected_deletesLinkedEvent() {
        // Also covers wasActive (Pending) && nowInactive (Rejected) branch
        User adv = getAdvisor();
        Appointment_Request__c appt = getAppt();
        // Change to Pending first
        appt.Status__c = 'Pending';
        update appt;

        Id eventId = attachEventToAppt(adv, appt);

        Test.startTest();
        appt = getAppt();
        appt.Status__c = 'Rejected';
        update appt;
        Test.stopTest();

        List<Event> remaining = [SELECT Id FROM Event WHERE Id = :eventId];
        System.assertEquals(0, remaining.size(), 'Event deleted on Pending→Rejected');
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  R E S C H E D U L E
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testReschedule_updatesEventTiming() {
        User adv = getAdvisor();
        Appointment_Request__c appt = getAppt();
        Id eventId = attachEventToAppt(adv, appt);

        Datetime newStart = appt.Start_DateTime__c.addDays(1);
        Datetime newEnd   = appt.End_DateTime__c.addDays(1);

        Test.startTest();
        appt = getAppt(); // re-query with EventId__c populated
        appt.Start_DateTime__c = newStart;
        appt.End_DateTime__c   = newEnd;
        update appt;
        System.assertEquals(1, Limits.getEmailInvocations(), 'Reschedule should notify the student');
        Test.stopTest();

        Event updatedEvt = [SELECT StartDateTime, EndDateTime FROM Event WHERE Id = :eventId];
        System.assertEquals(newStart, updatedEvt.StartDateTime, 'Event StartDateTime should be rescheduled');
        System.assertEquals(newEnd,   updatedEvt.EndDateTime,   'Event EndDateTime should be rescheduled');
    }

    @isTest
    static void testInitialEventLink_syncsEventFieldsFromAppointment() {
        User adv = getAdvisor();
        Appointment_Request__c appt = getAppt();
        appt.Name = 'My Meeting Title';
        appt.Request_Type__c = 'attendance';
        appt.Reason__c = 'Need attendance review';
        update appt;

        Id eventId = attachEventToAppt(adv, appt);

        Event syncedEvt = [
            SELECT Subject, Type, Description, StartDateTime, EndDateTime, WhoId, ShowAs
            FROM Event
            WHERE Id = :eventId
        ];

        Appointment_Request__c refreshedAppt = [
            SELECT Name, Request_Type__c, Reason__c, Student__c, Start_DateTime__c, End_DateTime__c
            FROM Appointment_Request__c
            WHERE Id = :appt.Id
        ];

        System.assertEquals(refreshedAppt.Name, syncedEvt.Subject, 'Event subject should sync from appointment name');
        System.assertEquals('Attendance Flag', syncedEvt.Type, 'Event type should sync from request type');
        System.assert(syncedEvt.Description.contains(refreshedAppt.Reason__c), 'Event description should include request reason');
        System.assertEquals(refreshedAppt.Start_DateTime__c, syncedEvt.StartDateTime, 'Event start should sync from appointment');
        System.assertEquals(refreshedAppt.End_DateTime__c, syncedEvt.EndDateTime, 'Event end should sync from appointment');
        System.assertEquals(refreshedAppt.Student__c, syncedEvt.WhoId, 'Event attendee should remain the student contact');
        System.assertEquals('Busy', syncedEvt.ShowAs, 'Event should remain busy on the calendar');
    }

    @isTest
    static void testReschedule_noMinutes_calculatesFromDates() {
        User adv = getAdvisor();
        Appointment_Request__c appt = getAppt();
        // Clear Minutes_of_Meeting__c to exercise the computed duration branch
        appt.Minutes_of_Meeting__c = null;
        update appt;
        Id eventId = attachEventToAppt(adv, appt);

        Datetime newStart = appt.Start_DateTime__c.addDays(2);
        Datetime newEnd   = newStart.addMinutes(45);

        Test.startTest();
        appt = getAppt();
        appt.Start_DateTime__c = newStart;
        appt.End_DateTime__c   = newEnd;
        update appt;
        Test.stopTest();

        Event updatedEvt = [SELECT StartDateTime, EndDateTime, DurationInMinutes FROM Event WHERE Id = :eventId];
        System.assertEquals(newStart, updatedEvt.StartDateTime);
        System.assertEquals(45, updatedEvt.DurationInMinutes, 'Duration should be computed from date diff');
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  N O - O P
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testNoOp_reasonUpdateOnly() {
        User adv = getAdvisor();
        Appointment_Request__c appt = getAppt();
        Id eventId = attachEventToAppt(adv, appt);

        Test.startTest();
        appt = getAppt();
        appt.Reason__c = 'Updated reason only — times unchanged';
        update appt;
        Test.stopTest();

        // Event must still exist
        List<Event> events = [SELECT Id FROM Event WHERE Id = :eventId];
        System.assertEquals(1, events.size(), 'Event should not be deleted on a no-op update');

        Appointment_Request__c updated = [SELECT Status__c FROM Appointment_Request__c WHERE Id = :appt.Id];
        System.assertEquals('Approved', updated.Status__c);
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  A F T E R   I N S E R T   -   N O T I F I C A T I O N S
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testAfterInsert_advisorCreated_sendsNotification() {
        // Setup: Advisor creates an appointment for a student
        User adv = getAdvisor();
        Contact studentContact = [SELECT Id FROM Contact WHERE LastName='ARHTest' LIMIT 1];
        
        // Create a student user linked to contact via User.ContactId
        Profile studentProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User studentUser = new User(
            FirstName='StudentUser', LastName='ARHTest',
            Email='student_arh@devslcm.test',
            Username='student_arh@devslcm.test.arh',
            Alias='stuarh',
            TimeZoneSidKey='America/New_York', LocaleSidKey='en_US',
            EmailEncodingKey='UTF-8', LanguageLocaleKey='en_US',
            ProfileId=studentProfile.Id,
            ContactId=studentContact.Id
        );
        insert studentUser;

        Datetime startDT = Datetime.now().addDays(5);
        Datetime endDT = startDT.addMinutes(45);

        Test.startTest();
        // Advisor creates appointment for student
        System.runAs(adv) {
            Appointment_Request__c newAppt = new Appointment_Request__c(
                Student__c = studentContact.Id,
                Primary_Advisor__c = adv.Id,
                Status__c = 'Approved',
                Request_Type__c = 'general',
                Reason__c = 'Follow-up meeting',
                Start_DateTime__c = startDT,
                End_DateTime__c = endDT,
                Minutes_of_Meeting__c = '45'
            );
            insert newAppt;
        }
        // Notification should be sent because CreatedById (advisor) != Student user resolved from User.ContactId
        System.assertEquals(1, Limits.getEmailInvocations(), 'Email notification should be sent for advisor-created appointment');
        Test.stopTest();

        // Verify appointment was created
        List<Appointment_Request__c> newAppts = [
            SELECT Id, Student__c, Status__c, CreatedById
            FROM Appointment_Request__c
            WHERE Student__c = :studentContact.Id
        ];
        // Filter in Apex since Reason__c is not queryable in target org
        List<Appointment_Request__c> filteredAppts = new List<Appointment_Request__c>();
        for (Appointment_Request__c appt : newAppts) {
            if (appt.CreatedById == adv.Id) {
                filteredAppts.add(appt);
            }
        }
        System.assertEquals(1, filteredAppts.size(), 'Appointment should be created');
        System.assertEquals(adv.Id, filteredAppts[0].CreatedById, 'Appointment should be created by advisor');
    }

    @isTest
    static void testAfterInsert_studentCreated_noNotification() {
        // Setup: Student creates their own appointment
        Contact studentContact = [SELECT Id FROM Contact WHERE LastName='ARHTest' LIMIT 1];
        
        // Create a student user linked to contact via User.ContactId
        Profile studentProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User studentUser = new User(
            FirstName='StudentUser2', LastName='ARHTest',
            Email='student2_arh@devslcm.test',
            Username='student2_arh@devslcm.test.arh',
            Alias='stu2arh',
            TimeZoneSidKey='America/New_York', LocaleSidKey='en_US',
            EmailEncodingKey='UTF-8', LanguageLocaleKey='en_US',
            ProfileId=studentProfile.Id,
            ContactId=studentContact.Id
        );
        insert studentUser;

        User adv = getAdvisor();
        Datetime startDT = Datetime.now().addDays(6);
        Datetime endDT = startDT.addMinutes(30);

        Test.startTest();
        // Student creates their own appointment
        System.runAs(studentUser) {
            Appointment_Request__c studentAppt = new Appointment_Request__c(
                Student__c = studentContact.Id,
                Primary_Advisor__c = adv.Id,
                Status__c = 'Pending',
                Request_Type__c = 'cgpa',
                Reason__c = 'Self-requested appointment',
                Start_DateTime__c = startDT,
                End_DateTime__c = endDT,
                Minutes_of_Meeting__c = '30'
            );
            insert studentAppt;
        }
        // No notification should be sent because CreatedById == student user resolved from User.ContactId
        System.assertEquals(0, Limits.getEmailInvocations(), 'No email should be sent for student-created appointment');
        Test.stopTest();

        // Verify appointment was created
        List<Appointment_Request__c> studentAppts = [
            SELECT Id, Student__c, Status__c, CreatedById
            FROM Appointment_Request__c
            WHERE Student__c = :studentContact.Id
        ];
        // Filter in Apex since Reason__c is not queryable in target org
        List<Appointment_Request__c> filteredStudentAppts = new List<Appointment_Request__c>();
        for (Appointment_Request__c appt : studentAppts) {
            if (appt.CreatedById == studentUser.Id) {
                filteredStudentAppts.add(appt);
            }
        }
        System.assertEquals(1, filteredStudentAppts.size(), 'Appointment should be created');
        System.assertEquals(studentUser.Id, filteredStudentAppts[0].CreatedById, 'Appointment should be created by student');
    }

    @isTest
    static void testAfterInsert_requestedUserMatchesStudent_noNotification() {
        User adv = getAdvisor();
        Contact studentContact = [SELECT Id FROM Contact WHERE LastName='ARHTest' LIMIT 1];

        Profile studentProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User studentUser = new User(
            FirstName='StudentUser3', LastName='ARHTest',
            Email='student3_arh@devslcm.test',
            Username='student3_arh@devslcm.test.arh',
            Alias='stu3arh',
            TimeZoneSidKey='America/New_York', LocaleSidKey='en_US',
            EmailEncodingKey='UTF-8', LanguageLocaleKey='en_US',
            ProfileId=studentProfile.Id,
            ContactId=studentContact.Id
        );
        insert studentUser;

        Datetime startDT = Datetime.now().addDays(8);
        Datetime endDT = startDT.addMinutes(30);

        Test.startTest();
        System.runAs(adv) {
            Appointment_Request__c requestRecord = new Appointment_Request__c(
                Student__c = studentContact.Id,
                Primary_Advisor__c = adv.Id,
                Requested_User__c = studentUser.Id,
                Status__c = 'Pending',
                Request_Type__c = 'other',
                Reason__c = 'Submitted by student but inserted by advisor user context',
                Start_DateTime__c = startDT,
                End_DateTime__c = endDT,
                Minutes_of_Meeting__c = '30'
            );
            insert requestRecord;
        }
        System.assertEquals(0, Limits.getEmailInvocations(), 'No student new-appointment email should be sent for student-submitted requests.');
        Test.stopTest();
    }

    @isTest
    static void testAfterInsert_bulkInsert_handlesCorrectly() {
        // Test bulk insert scenario with 200 records
        User adv = getAdvisor();
        Contact studentContact = [SELECT Id FROM Contact WHERE LastName='ARHTest' LIMIT 1];
        
        // Create a student user linked to contact via User.ContactId
        Profile studentProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User studentUser = new User(
            FirstName='StudentBulk', LastName='ARHTest',
            Email='student_bulk@devslcm.test',
            Username='student_bulk@devslcm.test.arh',
            Alias='stubulk',
            TimeZoneSidKey='America/New_York', LocaleSidKey='en_US',
            EmailEncodingKey='UTF-8', LanguageLocaleKey='en_US',
            ProfileId=studentProfile.Id,
            ContactId=studentContact.Id
        );
        insert studentUser;

        List<Appointment_Request__c> bulkAppts = new List<Appointment_Request__c>();
        Datetime baseStart = Datetime.now().addDays(10);
        
        for (Integer i = 0; i < 200; i++) {
            bulkAppts.add(new Appointment_Request__c(
                Student__c = studentContact.Id,
                Primary_Advisor__c = adv.Id,
                Status__c = 'Approved',
                Request_Type__c = 'other',
                Reason__c = 'Bulk test appointment ' + i,
                Start_DateTime__c = baseStart.addHours(i),
                End_DateTime__c = baseStart.addHours(i).addMinutes(30),
                Minutes_of_Meeting__c = '30'
            ));
        }

        Test.startTest();
        System.runAs(adv) {
            insert bulkAppts;
        }
        // Email batching should handle large lists
        System.assert(Limits.getEmailInvocations() <= 2, 'Email invocations should be batched for 200 records');
        Test.stopTest();

        // Verify all appointments were created
        List<Appointment_Request__c> inserted = [
            SELECT Id, Reason__c
            FROM Appointment_Request__c
            WHERE Student__c = :studentContact.Id
        ];
        // Filter in Apex since Reason__c is not queryable in WHERE clause in target org
        List<Appointment_Request__c> bulkInserted = new List<Appointment_Request__c>();
        for (Appointment_Request__c appt : inserted) {
            if (appt.Reason__c != null && appt.Reason__c.startsWith('Bulk test appointment')) {
                bulkInserted.add(appt);
            }
        }
        System.assertEquals(200, bulkInserted.size(), 'All 200 appointments should be created');
    }

    @isTest
    static void testAfterInsert_noLinkedUser_noError() {
        // Test scenario where student contact has no linked user
        User adv = getAdvisor();
        
        Datetime startDT = Datetime.now().addDays(7);
        Datetime endDT = startDT.addMinutes(30);

        Test.startTest();
        System.runAs(adv) {
            // Create contact within System.runAs to avoid permission issues
            Contact studentNoUser = new Contact(
                FirstName='StudentNoUser', 
                LastName='ARHTest',
                Email='no_user@devslcm.test'
            );
            insert studentNoUser;
            
            Appointment_Request__c appt = new Appointment_Request__c(
                Student__c = studentNoUser.Id,
                Primary_Advisor__c = adv.Id,
                Status__c = 'Approved',
                Request_Type__c = 'general',
                Reason__c = 'Test no linked user',
                Start_DateTime__c = startDT,
                End_DateTime__c = endDT,
                Minutes_of_Meeting__c = '30'
            );
            insert appt;
            
            // Verify appointment was created
            List<Appointment_Request__c> appts = [
                SELECT Id
                FROM Appointment_Request__c
                WHERE Student__c = :studentNoUser.Id
            ];
            System.assertEquals(1, appts.size(), 'Appointment should be created even without linked user');
        }
        // Should handle gracefully without error
        Test.stopTest();
    }
}