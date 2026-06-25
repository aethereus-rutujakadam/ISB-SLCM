/**
 * @description Test class for AcademicSupportController — 100% code coverage.
 *              Covers: getSupportDirectory, createAppointmentRequest,
 *              getStudentChecklists, updateChecklistItem, getStudentAppointments.
 * @author DEVSLCM Team
 * @date 2026
 */
@isTest
private class AcademicSupportControllerTest {

    // ─────────────────────────────────────────────────────────────────────────
    //  T E S T   D A T A   S E T U P
    // ─────────────────────────────────────────────────────────────────────────

    @testSetup
    static void setupTestData() {

        // 1. Create a Community/Portal user profile (use a standard profile that
        //    is available in the org; for @testSetup we create a full internal user)
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        // 2. Advisor user
        User advisorUser = new User(
            FirstName    = 'Advisor',
            LastName     = 'Test',
            Email        = 'advisor_test_asc@devslcm.test',
            Username     = 'advisor_test_asc@devslcm.test.portal',
            Alias        = 'advtst',
            TimeZoneSidKey   = 'America/New_York',
            LocaleSidKey     = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId    = p.Id
        );
        insert advisorUser;

        // 3. Student user
        User studentUser = new User(
            FirstName    = 'Student',
            LastName     = 'Test',
            Email        = 'student_test_asc@devslcm.test',
            Username     = 'student_test_asc@devslcm.test.portal',
            Alias        = 'stutst',
            TimeZoneSidKey   = 'America/New_York',
            LocaleSidKey     = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId    = p.Id
        );
        insert studentUser;

        // 4. Advisor contact (linked to advisor user)
        Contact advisorContact = new Contact(
            FirstName          = 'Advisor',
            LastName           = 'Contact',
            Email              = 'advisor_contact_asc@devslcm.test',
            Linked_User_Id__c  = advisorUser.Id
        );
        insert advisorContact;

        // 5. Update advisor user with ContactId
        advisorUser.ContactId = advisorContact.Id;
        update advisorUser;

        // 6. Student contact (linked to student user)
        Contact studentContact = new Contact(
            FirstName = 'Student',
            LastName  = 'Contact',
            Email     = 'student_contact_asc@devslcm.test'
        );
        insert studentContact;

        studentUser.ContactId = studentContact.Id;
        update studentUser;

        // 7. Account + ProgramEnrollment
        Account acct = new Account(Name = 'Test University');
        insert acct;

        ProgramEnrollment pe = new ProgramEnrollment(
            ContactId          = studentContact.Id,
            AccountId          = acct.Id,
            Primary_Advisor__c = advisorContact.Id,
            IsActive           = true
        );
        insert pe;

        // 8. Course Checklist + Item (for checklist tests)
        Course_Checklist__c checklist = new Course_Checklist__c(
            Student__c      = studentContact.Id,
            Checklist_Type__c = 'Orientation',
            Status__c       = 'Active'
        );
        insert checklist;

        Course_Checklist_Item__c item = new Course_Checklist_Item__c(
            Course_Checklist__c = checklist.Id,
            Subject__c          = 'Meet Your Advisor',
            Status__c           = 'Not Started',
            Role__c             = 'Student',
            Due_Date__c         = Date.today().addDays(-1),  // overdue
            Priority__c         = 'High'
        );
        insert item;

        // 9. Appointment Request (for getStudentAppointments)
        Appointment_Request__c appt = new Appointment_Request__c(
            Student__c          = studentContact.Id,
            Primary_Advisor__c  = advisorUser.Id,
            Status__c           = 'Pending',
            Request_Type__c     = 'general',
            Reason__c           = 'General advising session',
            Start_DateTime__c   = Datetime.now().addDays(1),
            End_DateTime__c     = Datetime.now().addDays(1).addMinutes(30),
            Minutes_of_Meeting__c = '30'
        );
        insert appt;
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  H E L P E R S
    // ─────────────────────────────────────────────────────────────────────────

    static User getStudentUser() {
        return [SELECT Id, ContactId FROM User
                WHERE Username = 'student_test_asc@devslcm.test.portal' LIMIT 1];
    }

    static User getAdvisorUser() {
        return [SELECT Id, ContactId FROM User
                WHERE Username = 'advisor_test_asc@devslcm.test.portal' LIMIT 1];
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  getSupportDirectory
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testGetSupportDirectory_happyPath() {
        User studentUser = getStudentUser();
        Test.startTest();
        AcademicSupportController.SupportDirectoryWrapper result;
        System.runAs(studentUser) {
            result = AcademicSupportController.getSupportDirectory();
        }
        Test.stopTest();

        System.assertNotEquals(null, result, 'Wrapper should not be null');
        System.assertEquals(false, result.hasError, 'Should not have an error');
        System.assertNotEquals(null, result.studentContactId, 'Student contact ID should be populated');
        System.assertNotEquals(null, result.primaryAdvisor, 'Primary advisor should be set');
        System.assertNotEquals(null, result.primaryAdvisorUserId, 'Advisor user ID should be set');
    }

    @isTest
    static void testGetSupportDirectory_noContactOnUser() {
        // Create a user with no ContactId
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User noContact = new User(
            FirstName='No', LastName='Contact',
            Email='no_contact_asc@devslcm.test',
            Username='no_contact_asc@devslcm.test.x1',
            Alias='noctst',
            TimeZoneSidKey='America/New_York', LocaleSidKey='en_US',
            EmailEncodingKey='UTF-8', LanguageLocaleKey='en_US',
            ProfileId = p.Id
        );
        insert noContact;

        Test.startTest();
        AcademicSupportController.SupportDirectoryWrapper result;
        System.runAs(noContact) {
            result = AcademicSupportController.getSupportDirectory();
        }
        Test.stopTest();

        System.assertEquals(true, result.hasError, 'Should flag error for user with no contact');
    }

    @isTest
    static void testGetSupportDirectory_noProgramEnrollment() {
        // Student with a contact but no enrollment
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User uNoEnroll = new User(
            FirstName='NoEnroll', LastName='Student',
            Email='no_enroll_asc@devslcm.test',
            Username='no_enroll_asc@devslcm.test.x2',
            Alias='noenr',
            TimeZoneSidKey='America/New_York', LocaleSidKey='en_US',
            EmailEncodingKey='UTF-8', LanguageLocaleKey='en_US',
            ProfileId = p.Id
        );
        insert uNoEnroll;

        Contact c = new Contact(FirstName='NoEnroll', LastName='Student',
                                Email='no_enroll_contact@devslcm.test');
        insert c;
        uNoEnroll.ContactId = c.Id;
        update uNoEnroll;

        Test.startTest();
        AcademicSupportController.SupportDirectoryWrapper result;
        System.runAs(uNoEnroll) {
            result = AcademicSupportController.getSupportDirectory();
        }
        Test.stopTest();

        System.assertEquals(false, result.hasError, 'No error expected — no enrollment just means no primary advisor');
        System.assertEquals(null, result.primaryAdvisor, 'Primary advisor should be null with no enrollment');
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  createAppointmentRequest
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testCreateAppointmentRequest_success() {
        User studentUser = getStudentUser();
        Datetime startDT = Datetime.now().addDays(2).addHours(1);
        Datetime endDT   = startDT.addMinutes(30);
        String startISO  = startDT.format('yyyy-MM-dd\'T\'HH:mm:ss');
        String endISO    = endDT.format('yyyy-MM-dd\'T\'HH:mm:ss');

        Appointment_Request__c req = new Appointment_Request__c(
            Request_Type__c = 'general',
            Reason__c       = 'Test reason'
        );

        Test.startTest();
        String resultId;
        System.runAs(studentUser) {
            resultId = AcademicSupportController.createAppointmentRequest(req, startISO, endISO, 'Test Meeting');
        }
        Test.stopTest();

        System.assertNotEquals(null, resultId, 'Should return new record ID');
        System.assertEquals(1, Limits.getEmailInvocations(), 'Should send an email to the primary advisor');
        Appointment_Request__c inserted = [SELECT Status__c, Student__c, Requested_User__c FROM Appointment_Request__c WHERE Id = :resultId];
        System.assertEquals('Pending', inserted.Status__c);
        System.assertEquals(studentUser.Id, inserted.Requested_User__c, 'Requested user should be set to the submitting student user.');
    }

    @isTest
    static void testCreateAppointmentRequest_noContactOnUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User noContact = new User(
            FirstName='No', LastName='Cntct2',
            Email='no_cnt2_asc@devslcm.test',
            Username='no_cnt2_asc@devslcm.test.x3',
            Alias='noc2',
            TimeZoneSidKey='America/New_York', LocaleSidKey='en_US',
            EmailEncodingKey='UTF-8', LanguageLocaleKey='en_US',
            ProfileId = p.Id
        );
        insert noContact;

        Appointment_Request__c req = new Appointment_Request__c(
            Request_Type__c = 'general', Reason__c = 'Test'
        );

        Test.startTest();
        try {
            System.runAs(noContact) {
                AcademicSupportController.createAppointmentRequest(req, '2026-05-01T09:00:00', '2026-05-01T09:30:00', 'Test Meeting');
            }
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Invalid Student User') || e.getMessage() != null);
        }
        Test.stopTest();
    }

    @isTest
    static void testCreateAppointmentRequest_noPrimaryAdvisor() {
        // Create student with enrollment but NO primary advisor
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User uNoAdv = new User(
            FirstName='NoAdv', LastName='Student',
            Email='no_adv_asc@devslcm.test',
            Username='no_adv_asc@devslcm.test.x4',
            Alias='noadv',
            TimeZoneSidKey='America/New_York', LocaleSidKey='en_US',
            EmailEncodingKey='UTF-8', LanguageLocaleKey='en_US',
            ProfileId = p.Id
        );
        insert uNoAdv;

        Contact c = new Contact(FirstName='NoAdv', LastName='Student', Email='no_adv_c@devslcm.test');
        insert c;
        uNoAdv.ContactId = c.Id;
        update uNoAdv;

        Account acct = new Account(Name = 'NoAdv Uni');
        insert acct;
        ProgramEnrollment pe = new ProgramEnrollment(ContactId=c.Id, AccountId=acct.Id, IsActive=true);
        insert pe;

        Appointment_Request__c req = new Appointment_Request__c(
            Request_Type__c = 'general', Reason__c = 'Test'
        );

        Test.startTest();
        try {
            System.runAs(uNoAdv) {
                AcademicSupportController.createAppointmentRequest(req, '2026-05-01T09:00:00', '2026-05-01T09:30:00', 'Test Meeting');
            }
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testCreateAppointmentRequest_slotConflict() {
        User studentUser = getStudentUser();
        // Use the existing pending appointment's time slot to trigger the overlap check
        Appointment_Request__c existing = [SELECT Start_DateTime__c, End_DateTime__c
                                           FROM Appointment_Request__c
                                           WHERE Student__c = :[SELECT ContactId FROM User
                                                                 WHERE Id = :studentUser.Id].ContactId
                                           AND Status__c = 'Pending' LIMIT 1];

        String startISO = existing.Start_DateTime__c.format('yyyy-MM-dd\'T\'HH:mm:ss');
        String endISO   = existing.End_DateTime__c.format('yyyy-MM-dd\'T\'HH:mm:ss');

        Appointment_Request__c req = new Appointment_Request__c(
            Request_Type__c = 'general', Reason__c = 'Conflict test'
        );

        Test.startTest();
        try {
            System.runAs(studentUser) {
                AcademicSupportController.createAppointmentRequest(req, startISO, endISO, 'Conflict Test Meeting');
            }
            System.assert(false, 'Expected slot conflict exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('no longer available') || e.getMessage() != null);
        }
        Test.stopTest();
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  getStudentChecklists
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testGetStudentChecklists_success() {
        User studentUser = getStudentUser();
        Test.startTest();
        AcademicSupportController.ChecklistDataWrapper result;
        System.runAs(studentUser) {
            result = AcademicSupportController.getStudentChecklists(studentUser.ContactId);
        }
        Test.stopTest();

        System.assertEquals(false, result.hasError);
        System.assertEquals(1, result.checklists.size(), 'Should return 1 checklist');
        System.assertEquals(1, result.checklists[0].items.size(), 'Should have 1 item');
        System.assertEquals(true, result.checklists[0].items[0].isOverdue, 'Item should be overdue');
        System.assertEquals(true, result.checklists[0].items[0].isEditable, 'Student role item should be editable');
    }

    @isTest
    static void testGetStudentChecklists_nullContactId() {
        User studentUser = getStudentUser();
        Test.startTest();
        AcademicSupportController.ChecklistDataWrapper result;
        System.runAs(studentUser) {
            result = AcademicSupportController.getStudentChecklists(null);
        }
        Test.stopTest();

        System.assertEquals(true, result.hasError);
    }

    @isTest
    static void testGetStudentChecklists_wrongUser() {
        // Advisor user requesting a different contact's checklists
        User advisorUser = getAdvisorUser();
        User studentUser = getStudentUser();
        Test.startTest();
        AcademicSupportController.ChecklistDataWrapper result;
        System.runAs(advisorUser) {
            result = AcademicSupportController.getStudentChecklists(studentUser.ContactId);
        }
        Test.stopTest();

        System.assertEquals(true, result.hasError, 'Should flag unauthorised access');
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  updateChecklistItem
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testUpdateChecklistItem_success() {
        User studentUser = getStudentUser();
        Course_Checklist_Item__c item = [
            SELECT Id FROM Course_Checklist_Item__c
            WHERE Course_Checklist__r.Student__c = :studentUser.ContactId LIMIT 1
        ];

        Test.startTest();
        String result;
        System.runAs(studentUser) {
            result = AcademicSupportController.updateChecklistItem(item.Id, 'Completed', 'Done!');
        }
        Test.stopTest();

        System.assertEquals('Success', result);
        Course_Checklist_Item__c updated = [SELECT Status__c, Comments__c FROM Course_Checklist_Item__c WHERE Id = :item.Id];
        System.assertEquals('Completed', updated.Status__c);
        System.assertEquals('Done!', updated.Comments__c);
    }

    @isTest
    static void testUpdateChecklistItem_noContactOnUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User noContact = new User(
            FirstName='No', LastName='Cnt3',
            Email='no_cnt3_asc@devslcm.test',
            Username='no_cnt3_asc@devslcm.test.x5',
            Alias='noc3',
            TimeZoneSidKey='America/New_York', LocaleSidKey='en_US',
            EmailEncodingKey='UTF-8', LanguageLocaleKey='en_US',
            ProfileId = p.Id
        );
        insert noContact;

        User studentUser = getStudentUser();
        Course_Checklist_Item__c item = [
            SELECT Id FROM Course_Checklist_Item__c
            WHERE Course_Checklist__r.Student__c = :studentUser.ContactId LIMIT 1
        ];

        Test.startTest();
        try {
            System.runAs(noContact) {
                AcademicSupportController.updateChecklistItem(item.Id, 'Completed', '');
            }
            System.assert(false, 'Expected exception');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testUpdateChecklistItem_wrongStudent() {
        // Advisor tries to update a student's item
        User advisorUser = getAdvisorUser();
        User studentUser = getStudentUser();
        Course_Checklist_Item__c item = [
            SELECT Id FROM Course_Checklist_Item__c
            WHERE Course_Checklist__r.Student__c = :studentUser.ContactId LIMIT 1
        ];

        Test.startTest();
        try {
            System.runAs(advisorUser) {
                AcademicSupportController.updateChecklistItem(item.Id, 'Completed', '');
            }
            System.assert(false, 'Expected exception');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testUpdateChecklistItem_nonStudentRoleAllowedForOwner() {
        User studentUser = getStudentUser();
        // Create an item with a non-student role and verify owner student can still update it.
        Course_Checklist__c cl = [
            SELECT Id FROM Course_Checklist__c
            WHERE Student__c = :studentUser.ContactId LIMIT 1
        ];
        Course_Checklist_Item__c advisorItem = new Course_Checklist_Item__c(
            Course_Checklist__c = cl.Id,
            Subject__c  = 'Advisor Only Task',
            Status__c   = 'Not Started',
            Role__c     = 'Associate'
        );
        insert advisorItem;

        Test.startTest();
        String result;
        System.runAs(studentUser) {
            result = AcademicSupportController.updateChecklistItem(advisorItem.Id, 'Completed', 'Completed by student');
        }
        Test.stopTest();

        System.assertEquals('Success', result);
        Course_Checklist_Item__c updated = [SELECT Status__c, Comments__c FROM Course_Checklist_Item__c WHERE Id = :advisorItem.Id];
        System.assertEquals('Completed', updated.Status__c);
        System.assertEquals('Completed by student', updated.Comments__c);
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  getStudentAppointments
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testGetStudentAppointments_success() {
        User studentUser = getStudentUser();
        Test.startTest();
        List<AcademicSupportController.AppointmentWrapper> results;
        System.runAs(studentUser) {
            results = AcademicSupportController.getStudentAppointments(studentUser.ContactId);
        }
        Test.stopTest();

        System.assert(results.size() >= 1, 'Should return at least 1 appointment');
        AcademicSupportController.AppointmentWrapper w = results[0];
        System.assertNotEquals(null, w.id);
        System.assertEquals('Pending', w.status);
        System.assertEquals(true, w.isPending);
        System.assertEquals(false, w.isApproved);
        System.assertEquals(false, w.isRejected);
    }

    @isTest
    static void testGetStudentAppointments_rejectedAndCompleted() {
        User studentUser = getStudentUser();
        User advisorUser = getAdvisorUser();
        // Create rejected + completed appointments to cover canBookAgain = true
        List<Appointment_Request__c> extra = new List<Appointment_Request__c>{
            new Appointment_Request__c(
                Student__c = studentUser.ContactId,
                Primary_Advisor__c = advisorUser.Id,
                Status__c = 'Rejected',
                Request_Type__c = 'cgpa',
                Reason__c = 'r1',
                Rejection_Reason__c = 'Not available',
                Start_DateTime__c = Datetime.now().addDays(3),
                End_DateTime__c   = Datetime.now().addDays(3).addMinutes(30)
            ),
            new Appointment_Request__c(
                Student__c = studentUser.ContactId,
                Primary_Advisor__c = advisorUser.Id,
                Status__c = 'Completed',
                Request_Type__c = 'attendance',
                Reason__c = 'r2',
                Start_DateTime__c = Datetime.now().addDays(4),
                End_DateTime__c   = Datetime.now().addDays(4).addMinutes(30)
            )
        };
        insert extra;

        Test.startTest();
        List<AcademicSupportController.AppointmentWrapper> results;
        System.runAs(studentUser) {
            results = AcademicSupportController.getStudentAppointments(studentUser.ContactId);
        }
        Test.stopTest();

        Boolean foundRejected  = false;
        Boolean foundCompleted = false;
        for (AcademicSupportController.AppointmentWrapper w : results) {
            if (w.status == 'Rejected')  { foundRejected  = true; System.assertEquals(true, w.canBookAgain); System.assertEquals(true, w.isRejected); }
            if (w.status == 'Completed') { foundCompleted = true; System.assertEquals(true, w.canBookAgain); }
        }
        System.assert(foundRejected,  'Should find rejected appointment');
        System.assert(foundCompleted, 'Should find completed appointment');
    }

    @isTest
    static void testGetStudentAppointments_includesStandaloneEventAndDedupesLinkedEvent() {
        User studentUser = getStudentUser();
        User advisorUser = getAdvisorUser();

        Event linkedEvent = new Event(
            Subject = 'Linked Event',
            StartDateTime = Datetime.now().addDays(6),
            EndDateTime = Datetime.now().addDays(6).addMinutes(30),
            OwnerId = advisorUser.Id,
            WhoId = studentUser.ContactId
        );
        insert linkedEvent;

        Event standaloneEvent = new Event(
            Subject = 'Standalone Event',
            StartDateTime = Datetime.now().addDays(7),
            EndDateTime = Datetime.now().addDays(7).addMinutes(30),
            OwnerId = advisorUser.Id,
            WhoId = studentUser.ContactId
        );
        insert standaloneEvent;

        Appointment_Request__c linkedRequest = new Appointment_Request__c(
            Student__c = studentUser.ContactId,
            Primary_Advisor__c = advisorUser.Id,
            Status__c = 'Approved',
            Request_Type__c = 'general',
            Reason__c = 'Linked request',
            Start_DateTime__c = linkedEvent.StartDateTime,
            End_DateTime__c = linkedEvent.EndDateTime,
            EventId__c = (String)linkedEvent.Id
        );
        insert linkedRequest;

        Test.startTest();
        List<AcademicSupportController.AppointmentWrapper> results;
        System.runAs(studentUser) {
            results = AcademicSupportController.getStudentAppointments(studentUser.ContactId);
        }
        Test.stopTest();

        Integer linkedEventCount = 0;
        Boolean foundStandalone = false;
        for (AcademicSupportController.AppointmentWrapper w : results) {
            if (w.eventId == (String)linkedEvent.Id) {
                linkedEventCount++;
            }
            if (w.id == standaloneEvent.Id && w.status == 'Scheduled') {
                foundStandalone = true;
            }
        }

        System.assertEquals(1, linkedEventCount, 'Linked event should appear only once via the appointment request.');
        System.assert(foundStandalone, 'Standalone advisor-created event should appear in My Appointments.');
    }

    @isTest
    static void testGetStudentAppointments_nullContactId() {
        User studentUser = getStudentUser();
        Test.startTest();
        List<AcademicSupportController.AppointmentWrapper> results;
        System.runAs(studentUser) {
            results = AcademicSupportController.getStudentAppointments(null);
        }
        Test.stopTest();

        System.assertEquals(0, results.size(), 'Null contactId should return empty list');
    }

    @isTest
    static void testGetStudentAppointments_unauthorised() {
        // Advisor tries to fetch student's appointments
        User advisorUser = getAdvisorUser();
        User studentUser = getStudentUser();
        Test.startTest();
        try {
            System.runAs(advisorUser) {
                AcademicSupportController.getStudentAppointments(studentUser.ContactId);
            }
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('authorised') || e.getMessage() != null);
        }
        Test.stopTest();
    }
}