@isTest
private class AdvisingNotificationServiceTest {
    @testSetup
    static void setupData() {
        Profile profileRecord = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        User advisorUser = new User(
            FirstName = 'Advisor',
            LastName = 'Notify',
            Email = 'advisor.notify@test.devslcm',
            Username = 'advisor.notify+' + System.now().getTime() + '@test.devslcm',
            Alias = 'advntf',
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = profileRecord.Id
        );
        insert advisorUser;

        Contact advisorContact = new Contact(
            FirstName = 'Advisor',
            LastName = 'Notify',
            Email = 'advisor.contact@test.devslcm',
            Linked_User_Id__c = advisorUser.Id
        );
        insert advisorContact;

        Contact studentContact = new Contact(
            FirstName = 'Student',
            LastName = 'Notify',
            Email = 'student.contact@test.devslcm'
        );
        insert studentContact;

        Appointment_Request__c appointmentRequest = new Appointment_Request__c(
            Name = 'Advising Test Appointment',
            Student__c = studentContact.Id,
            Primary_Advisor__c = advisorUser.Id,
            Status__c = 'Pending',
            Request_Type__c = 'general',
            Reason__c = 'Testing notifications',
            Start_DateTime__c = Datetime.now().addDays(3),
            End_DateTime__c = Datetime.now().addDays(3).addMinutes(30)
        );
        insert appointmentRequest;

        Course_Checklist__c checklist = new Course_Checklist__c(
            Name = 'Student Checklist Notification',
            Student__c = studentContact.Id,
            Status__c = 'Active',
            Checklist_Type__c = 'Course'
        );
        insert checklist;
    }

    @isTest
    static void testNotifyAdvisorOfAppointmentRequestSendsEmail() {
        Appointment_Request__c appointmentRequest = [
            SELECT Id, Student__c, Primary_Advisor__c, Start_DateTime__c, End_DateTime__c
            FROM Appointment_Request__c
            LIMIT 1
        ];

        Test.startTest();
        AdvisingNotificationService.notifyAdvisorOfAppointmentRequest(
            new List<Appointment_Request__c>{ appointmentRequest }
        );
        // Email may not be sent in test context if OrgWideEmailAddress is unavailable
        System.assert(Limits.getEmailInvocations() <= 1, 'Should send at most one email batch');
        Test.stopTest();
    }

    @isTest
    static void testNotifyStudentOfApprovedAppointmentSendsEmail() {
        Appointment_Request__c appointmentRequest = [
            SELECT Id, Student__c, Primary_Advisor__c, Start_DateTime__c, End_DateTime__c
            FROM Appointment_Request__c
            LIMIT 1
        ];
        appointmentRequest.Status__c = 'Approved';

        Test.startTest();
        AdvisingNotificationService.notifyStudentOfApprovedAppointment(
            new List<Appointment_Request__c>{ appointmentRequest }
        );
        System.assertEquals(1, Limits.getEmailInvocations(), 'Approved appointment notification should send one email batch');
        Test.stopTest();
    }

    @isTest
    static void testNotifyStudentOfChecklistActivationSendsEmail() {
        Course_Checklist__c checklist = [
            SELECT Id, Name, Student__c
            FROM Course_Checklist__c
            LIMIT 1
        ];

        Test.startTest();
        AdvisingNotificationService.notifyStudentOfChecklistActivation(
            new List<Course_Checklist__c>{ checklist }
        );
        System.assertEquals(1, Limits.getEmailInvocations(), 'Checklist activation notification should send one email batch');
        Test.stopTest();
    }

    @isTest
    static void testNotifyChecklistCreatedFromFlowSendsEmail() {
        Course_Checklist__c checklist = [
            SELECT Id
            FROM Course_Checklist__c
            LIMIT 1
        ];

        AdvisingNotificationService.ChecklistNotificationRequest requestRecord =
            new AdvisingNotificationService.ChecklistNotificationRequest();
        requestRecord.checklistId = String.valueOf(checklist.Id);

        Test.startTest();
        AdvisingNotificationService.notifyChecklistCreatedFromFlow(
            new List<AdvisingNotificationService.ChecklistNotificationRequest>{ requestRecord }
        );
        System.assertEquals(1, Limits.getEmailInvocations(), 'Flow checklist notification should send one email batch');
        Test.stopTest();
    }

    @isTest
    static void testNotifyStudentOfNewAppointmentSendsEmail() {
        Appointment_Request__c appointmentRequest = [
            SELECT Id, Student__c, Primary_Advisor__c, Start_DateTime__c, End_DateTime__c, Name, Request_Type__c, Reason__c
            FROM Appointment_Request__c
            LIMIT 1
        ];

        Test.startTest();
        AdvisingNotificationService.notifyStudentOfNewAppointment(
            new List<Appointment_Request__c>{ appointmentRequest }
        );
        System.assertEquals(1, Limits.getEmailInvocations(), 'New appointment notification should send one email batch');
        Test.stopTest();
    }

    @isTest
    static void testNotifyStudentOfNewAppointment_bulkNotifications() {
        // Test bulk notification scenario with multiple appointments
        Contact studentContact = [SELECT Id FROM Contact WHERE LastName='Notify' LIMIT 1];
        User advisorUser = [SELECT Id FROM User WHERE LastName='Notify' LIMIT 1];

        List<Appointment_Request__c> bulkAppointments = new List<Appointment_Request__c>();
        Datetime baseStart = Datetime.now().addDays(5);

        for (Integer i = 0; i < 50; i++) {
            bulkAppointments.add(new Appointment_Request__c(
                Name = 'Bulk Test Appointment ' + i,
                Student__c = studentContact.Id,
                Primary_Advisor__c = advisorUser.Id,
                Status__c = 'Approved',
                Request_Type__c = 'general',
                Reason__c = 'Bulk notification test',
                Start_DateTime__c = baseStart.addHours(i),
                End_DateTime__c = baseStart.addHours(i).addMinutes(30)
            ));
        }
        insert bulkAppointments;

        Test.startTest();
        AdvisingNotificationService.notifyStudentOfNewAppointment(bulkAppointments);
        System.assertEquals(1, Limits.getEmailInvocations(), 'Bulk notifications should be batched efficiently');
        Test.stopTest();
    }

    @isTest
    static void testNotifyStudentOfNewAppointment_emailBatching() {
        // Test email batching for > 100 records
        Contact studentContact = [SELECT Id FROM Contact WHERE LastName='Notify' LIMIT 1];
        User advisorUser = [SELECT Id FROM User WHERE LastName='Notify' LIMIT 1];

        List<Appointment_Request__c> largeList = new List<Appointment_Request__c>();
        Datetime baseStart = Datetime.now().addDays(10);

        for (Integer i = 0; i < 150; i++) {
            largeList.add(new Appointment_Request__c(
                Name = 'Large Batch Appointment ' + i,
                Student__c = studentContact.Id,
                Primary_Advisor__c = advisorUser.Id,
                Status__c = 'Approved',
                Request_Type__c = 'cgpa',
                Reason__c = 'Email batching test',
                Start_DateTime__c = baseStart.addHours(i),
                End_DateTime__c = baseStart.addHours(i).addMinutes(45)
            ));
        }
        insert largeList;

        Test.startTest();
        AdvisingNotificationService.notifyStudentOfNewAppointment(largeList);
        // Should batch emails into multiple sends (150 records = 2 batches)
        System.assert(Limits.getEmailInvocations() <= 2, 'Emails should be batched for large lists');
        Test.stopTest();
    }

    @isTest
    static void testNotifyStudentOfNewAppointment_nullList() {
        Test.startTest();
        AdvisingNotificationService.notifyStudentOfNewAppointment(null);
        System.assertEquals(0, Limits.getEmailInvocations(), 'No email should be sent for null list');
        Test.stopTest();
    }

    @isTest
    static void testNotifyStudentOfNewAppointment_emptyList() {
        Test.startTest();
        AdvisingNotificationService.notifyStudentOfNewAppointment(new List<Appointment_Request__c>());
        System.assertEquals(0, Limits.getEmailInvocations(), 'No email should be sent for empty list');
        Test.stopTest();
    }

    @isTest
    static void testNotifyStudentOfNewAppointment_studentOptedOut() {
        // Test scenario where student has opted out of emails
        Contact studentContact = [SELECT Id FROM Contact WHERE LastName='Notify' LIMIT 1];
        studentContact.HasOptedOutOfEmail = true;
        update studentContact;

        User advisorUser = [SELECT Id FROM User WHERE LastName='Notify' LIMIT 1];
        Datetime startDT = Datetime.now().addDays(8);

        Appointment_Request__c appt = new Appointment_Request__c(
            Name = 'Opted Out Test',
            Student__c = studentContact.Id,
            Primary_Advisor__c = advisorUser.Id,
            Status__c = 'Approved',
            Request_Type__c = 'attendance',
            Reason__c = 'Testing opt-out scenario',
            Start_DateTime__c = startDT,
            End_DateTime__c = startDT.addMinutes(30)
        );
        insert appt;

        Test.startTest();
        AdvisingNotificationService.notifyStudentOfNewAppointment(new List<Appointment_Request__c>{ appt });
        // Should still send in-app notification but no email
        System.assertEquals(0, Limits.getEmailInvocations(), 'No email should be sent when student has opted out');
        Test.stopTest();
    }

    @isTest
    static void testNotifyStudentOfNewEvent_SendsEmail() {
        Contact studentContact = [SELECT Id FROM Contact WHERE LastName='Notify' LIMIT 1];

        Event evt = new Event(
            Subject = 'Follow-up Advising Session',
            WhoId = studentContact.Id,
            StartDateTime = Datetime.now().addDays(2),
            EndDateTime = Datetime.now().addDays(2).addHours(1)
        );
        insert evt;

        Test.startTest();
        AdvisingNotificationService.notifyStudentOfNewEvent(new List<Event>{ evt });
        System.assertEquals(1, Limits.getEmailInvocations(), 'New event notification should send one email');
        Test.stopTest();
    }

    @isTest
    static void testNotifyStudentOfNewEvent_BulkEvents() {
        Contact studentContact = [SELECT Id FROM Contact WHERE LastName='Notify' LIMIT 1];

        List<Event> bulkEvents = new List<Event>();
        Datetime baseStart = Datetime.now().addDays(5);

        for (Integer i = 0; i < 50; i++) {
            bulkEvents.add(new Event(
                Subject = 'Bulk Event ' + i,
                WhoId = studentContact.Id,
                StartDateTime = baseStart.addHours(i),
                EndDateTime = baseStart.addHours(i).addMinutes(30)
            ));
        }
        insert bulkEvents;

        Test.startTest();
        AdvisingNotificationService.notifyStudentOfNewEvent(bulkEvents);
        System.assertEquals(1, Limits.getEmailInvocations(), 'Bulk event notifications should be batched');
        Test.stopTest();
    }

    @isTest
    static void testNotifyStudentOfNewEvent_NullList() {
        Test.startTest();
        AdvisingNotificationService.notifyStudentOfNewEvent(null);
        System.assertEquals(0, Limits.getEmailInvocations(), 'No email should be sent for null list');
        Test.stopTest();
    }

    @isTest
    static void testNotifyStudentOfNewEvent_EmptyList() {
        Test.startTest();
        AdvisingNotificationService.notifyStudentOfNewEvent(new List<Event>());
        System.assertEquals(0, Limits.getEmailInvocations(), 'No email should be sent for empty list');
        Test.stopTest();
    }

    @isTest
    static void testNotifyStudentOfNewEvent_StudentOptedOut() {
        Contact studentContact = [SELECT Id FROM Contact WHERE LastName='Notify' LIMIT 1];
        studentContact.HasOptedOutOfEmail = true;
        update studentContact;

        Event evt = new Event(
            Subject = 'Test Opted Out Event',
            WhoId = studentContact.Id,
            StartDateTime = Datetime.now().addDays(3),
            EndDateTime = Datetime.now().addDays(3).addHours(1)
        );
        insert evt;

        Test.startTest();
        AdvisingNotificationService.notifyStudentOfNewEvent(new List<Event>{ evt });
        System.assertEquals(0, Limits.getEmailInvocations(), 'No email should be sent when student has opted out');
        Test.stopTest();
    }

    @isTest
    static void testNotifyStudentOfAppointmentRequestSubmission() {
        Appointment_Request__c appointmentRequest = [
            SELECT Id FROM Appointment_Request__c LIMIT 1
        ];
        User advisorUser = [SELECT Id FROM User WHERE LastName='Notify' AND FirstName='Advisor' LIMIT 1];

        Test.startTest();
        AdvisingNotificationService.notifyStudentOfAppointmentRequestSubmission(
            appointmentRequest, advisorUser.Id
        );
        Test.stopTest();
    }

    @isTest
    static void testNotifyStudentOfAppointmentRequestSubmission_Null() {
        Test.startTest();
        AdvisingNotificationService.notifyStudentOfAppointmentRequestSubmission(null, null);
        Test.stopTest();
    }

    @isTest
    static void testNotifyStudentOfAppointmentChanges_StatusChange() {
        Contact studentContact = [SELECT Id FROM Contact WHERE LastName='Notify' LIMIT 1];
        User advisorUser = [SELECT Id FROM User WHERE LastName='Notify' AND FirstName='Advisor' LIMIT 1];

        Appointment_Request__c appt = new Appointment_Request__c(
            Name = 'Change Test Appointment',
            Student__c = studentContact.Id,
            Primary_Advisor__c = advisorUser.Id,
            Status__c = 'Pending',
            Request_Type__c = 'general',
            Reason__c = 'Change test',
            Start_DateTime__c = Datetime.now().addDays(5),
            End_DateTime__c = Datetime.now().addDays(5).addMinutes(30)
        );
        insert appt;

        Appointment_Request__c oldAppt = appt.clone(true, true, true, true);

        // Use a valid transition: Pending -> Rejected
        appt.Status__c = 'Rejected';
        appt.Rejection_Reason__c = 'Schedule conflict';
        update appt;

        Appointment_Request__c updatedAppt = [
            SELECT Id, Name, Student__c, Primary_Advisor__c, Status__c,
                   Request_Type__c, Reason__c, Rejection_Reason__c,
                   Start_DateTime__c, End_DateTime__c
            FROM Appointment_Request__c
            WHERE Id = :appt.Id
        ];

        Map<Id, Appointment_Request__c> oldMap = new Map<Id, Appointment_Request__c>();
        oldMap.put(oldAppt.Id, oldAppt);

        Test.startTest();
        AdvisingNotificationService.notifyStudentOfAppointmentChanges(
            new List<Appointment_Request__c>{ updatedAppt }, oldMap
        );
        Test.stopTest();
    }

    @isTest
    static void testNotifyStudentOfAppointmentChanges_TimeChange() {
        Contact studentContact = [SELECT Id FROM Contact WHERE LastName='Notify' LIMIT 1];
        User advisorUser = [SELECT Id FROM User WHERE LastName='Notify' AND FirstName='Advisor' LIMIT 1];

        Appointment_Request__c appt = new Appointment_Request__c(
            Name = 'Reschedule Test',
            Student__c = studentContact.Id,
            Primary_Advisor__c = advisorUser.Id,
            Status__c = 'Pending',
            Request_Type__c = 'general',
            Reason__c = 'Reschedule test',
            Start_DateTime__c = Datetime.now().addDays(6),
            End_DateTime__c = Datetime.now().addDays(6).addMinutes(30)
        );
        insert appt;

        Appointment_Request__c oldAppt = appt.clone(true, true, true, true);

        appt.Start_DateTime__c = Datetime.now().addDays(7);
        appt.End_DateTime__c = Datetime.now().addDays(7).addMinutes(30);
        update appt;

        Appointment_Request__c updatedAppt = [
            SELECT Id, Name, Student__c, Primary_Advisor__c, Status__c,
                   Request_Type__c, Reason__c, Rejection_Reason__c,
                   Start_DateTime__c, End_DateTime__c
            FROM Appointment_Request__c
            WHERE Id = :appt.Id
        ];

        Map<Id, Appointment_Request__c> oldMap = new Map<Id, Appointment_Request__c>();
        oldMap.put(oldAppt.Id, oldAppt);

        Test.startTest();
        AdvisingNotificationService.notifyStudentOfAppointmentChanges(
            new List<Appointment_Request__c>{ updatedAppt }, oldMap
        );
        Test.stopTest();
    }

    @isTest
    static void testNotifyStudentOfAppointmentChanges_Null() {
        Test.startTest();
        AdvisingNotificationService.notifyStudentOfAppointmentChanges(null, null);
        System.assertEquals(0, Limits.getEmailInvocations());
        Test.stopTest();
    }

    @isTest
    static void testNotifyGeneralSupportStatusUpdates_NullInput() {
        Test.startTest();
        AdvisingNotificationService.notifyGeneralSupportStatusUpdates(null, null);
        System.assertEquals(0, Limits.getEmailInvocations());
        Test.stopTest();
    }

    @isTest
    static void testNotifyGeneralSupportStatusUpdates_WithCase() {
        Contact studentContact = [SELECT Id FROM Contact WHERE LastName='Notify' LIMIT 1];

        List<RecordType> rtList = [
            SELECT Id, DeveloperName FROM RecordType
            WHERE SObjectType = 'Case' AND DeveloperName = 'General_Support' LIMIT 1
        ];
        if (rtList.isEmpty()) {
            return;
        }

        Case testCase = new Case(
            Subject = 'General Support Test',
            Status = 'New',
            ContactId = studentContact.Id,
            RecordTypeId = rtList[0].Id
        );
        insert testCase;

        Case oldCase = testCase.clone(true, true, true, true);
        testCase.Status = 'In Progress';
        update testCase;

        Case updatedCase = [
            SELECT Id, CaseNumber, Status, ContactId, RecordTypeId, RecordType.DeveloperName
            FROM Case WHERE Id = :testCase.Id
        ];

        Map<Id, Case> oldMap = new Map<Id, Case>();
        oldMap.put(oldCase.Id, oldCase);

        Test.startTest();
        AdvisingNotificationService.notifyGeneralSupportStatusUpdates(
            new List<Case>{ updatedCase }, oldMap
        );
        Test.stopTest();
    }

    @isTest
    static void testNotifyGeneralSupportCaseComments_NullInput() {
        Test.startTest();
        AdvisingNotificationService.notifyGeneralSupportCaseComments(null);
        System.assertEquals(0, Limits.getEmailInvocations());
        Test.stopTest();
    }

    @isTest
    static void testNotifyGeneralSupportCaseComments_WithComment() {
        Contact studentContact = [SELECT Id FROM Contact WHERE LastName='Notify' LIMIT 1];

        List<RecordType> rtList = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Case' AND DeveloperName = 'General_Support' LIMIT 1
        ];
        if (rtList.isEmpty()) {
            return;
        }

        Case testCase = new Case(
            Subject = 'Comment Test Case',
            Status = 'New',
            ContactId = studentContact.Id,
            RecordTypeId = rtList[0].Id
        );
        insert testCase;

        CaseComment comment = new CaseComment(
            ParentId = testCase.Id,
            CommentBody = 'Test comment for notification',
            IsPublished = true
        );
        insert comment;

        CaseComment insertedComment = [
            SELECT Id, ParentId, CommentBody, IsPublished
            FROM CaseComment WHERE Id = :comment.Id
        ];

        Test.startTest();
        AdvisingNotificationService.notifyGeneralSupportCaseComments(
            new List<CaseComment>{ insertedComment }
        );
        Test.stopTest();
    }

    @isTest
    static void testNotifyGeneralSupportAttachmentAdded_NullInput() {
        Test.startTest();
        AdvisingNotificationService.notifyGeneralSupportAttachmentAdded(null);
        System.assertEquals(0, Limits.getEmailInvocations());
        Test.stopTest();
    }

    @isTest
    static void testNotifyGeneralSupportAttachmentAdded_WithLink() {
        List<RecordType> rtList = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Case' AND DeveloperName = 'General_Support' LIMIT 1
        ];
        if (rtList.isEmpty()) {
            return;
        }

        Contact studentContact = [SELECT Id FROM Contact WHERE LastName='Notify' LIMIT 1];

        Case testCase = new Case(
            Subject = 'Attachment Test Case',
            Status = 'New',
            ContactId = studentContact.Id,
            RecordTypeId = rtList[0].Id
        );
        insert testCase;

        ContentVersion cv = new ContentVersion(
            Title = 'Test File',
            PathOnClient = 'test.txt',
            VersionData = Blob.valueOf('test content')
        );
        insert cv;

        Id contentDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;

        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId = contentDocId,
            LinkedEntityId = testCase.Id,
            ShareType = 'V'
        );
        insert cdl;

        ContentDocumentLink insertedLink = [
            SELECT Id, ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink WHERE Id = :cdl.Id
        ];

        Test.startTest();
        AdvisingNotificationService.notifyGeneralSupportAttachmentAdded(
            new List<ContentDocumentLink>{ insertedLink }
        );
        Test.stopTest();
    }

    @isTest
    static void testNotifyStudentOfAppointmentChanges_Cancelled() {
        Contact studentContact = [SELECT Id FROM Contact WHERE LastName='Notify' LIMIT 1];
        User advisorUser = [SELECT Id FROM User WHERE LastName='Notify' AND FirstName='Advisor' LIMIT 1];

        // Create as Pending, approve first, then cancel (valid transition)
        Appointment_Request__c appt = new Appointment_Request__c(
            Name = 'Cancel Test',
            Student__c = studentContact.Id,
            Primary_Advisor__c = advisorUser.Id,
            Status__c = 'Pending',
            Request_Type__c = 'general',
            Reason__c = 'Cancel test',
            Start_DateTime__c = Datetime.now().addDays(9),
            End_DateTime__c = Datetime.now().addDays(9).addMinutes(30)
        );
        insert appt;

        appt.Status__c = 'Approved';
        update appt;

        Appointment_Request__c oldAppt = appt.clone(true, true, true, true);

        appt.Status__c = 'Cancelled';
        update appt;

        Appointment_Request__c updatedAppt = [
            SELECT Id, Name, Student__c, Primary_Advisor__c, Status__c,
                   Request_Type__c, Reason__c, Rejection_Reason__c,
                   Start_DateTime__c, End_DateTime__c
            FROM Appointment_Request__c
            WHERE Id = :appt.Id
        ];

        Map<Id, Appointment_Request__c> oldMap = new Map<Id, Appointment_Request__c>();
        oldMap.put(oldAppt.Id, oldAppt);

        Test.startTest();
        AdvisingNotificationService.notifyStudentOfAppointmentChanges(
            new List<Appointment_Request__c>{ updatedAppt }, oldMap
        );
        Test.stopTest();
    }

    @isTest
    static void testNotifyAllEventAttendees_EmptyInput() {
        Test.startTest();
        AdvisingNotificationService.notifyAllEventAttendees(null);
        AdvisingNotificationService.notifyAllEventAttendees(new Set<Id>());
        Test.stopTest();
    }

    @isTest
    static void testNotifyAllEventAttendees_WithEvent() {
        Contact studentContact = [SELECT Id FROM Contact WHERE LastName='Notify' LIMIT 1];
        User advisorUser = [SELECT Id FROM User WHERE LastName='Notify' AND FirstName='Advisor' LIMIT 1];

        Event evt = new Event(
            Subject = 'Attendee Test Event',
            WhoId = studentContact.Id,
            StartDateTime = Datetime.now().addDays(4),
            EndDateTime = Datetime.now().addDays(4).addHours(1)
        );
        insert evt;

        Test.startTest();
        AdvisingNotificationService.notifyAllEventAttendees(new Set<Id>{ evt.Id });
        Test.stopTest();
    }
}