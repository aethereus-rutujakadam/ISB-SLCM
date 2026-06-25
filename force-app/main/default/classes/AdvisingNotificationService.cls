public without sharing class AdvisingNotificationService {
    private static final String NOTIFICATION_TYPE_DEVELOPER_NAME = 'Advising_Notification';
    private static final String GENERAL_SUPPORT_RT_DEVELOPER_NAME = 'General_Support';
    private static final String APPOINTMENT_REQUEST_SENDER_OWEA_NAME = 'ISB ASA Admin';
    private static final String STUDENT_ADVISING_PAGE_REF = '{"type":"standard__webPage","attributes":{"url":"/ISBStudentSuccessPortal/s/advising"}}';
    private static Id appointmentRequestSenderOweaId;

    @InvocableMethod(label='Send Checklist Created Notification' description='Sends checklist-created notification/email to the assigned student.')
    public static void notifyChecklistCreatedFromFlow(List<ChecklistNotificationRequest> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }

        Set<Id> checklistIds = new Set<Id>();
        for (ChecklistNotificationRequest requestRecord : requests) {
            if (requestRecord == null || String.isBlank(requestRecord.checklistId)) {
                continue;
            }
            try {
                checklistIds.add((Id) requestRecord.checklistId);
            } catch (Exception ex) {
                System.debug('AdvisingNotificationService.notifyChecklistCreatedFromFlow invalid Id: ' + requestRecord.checklistId);
            }
        }

        if (checklistIds.isEmpty()) {
            return;
        }

        List<Course_Checklist__c> checklists = [
            SELECT Id, Name, Student__c
            FROM Course_Checklist__c
            WHERE Id IN :checklistIds
        ];

        notifyStudentOfChecklistActivation(checklists);
    }

    public static void notifyAdvisorOfAppointmentRequest(List<Appointment_Request__c> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }

        try {
            Set<Id> advisorUserIds = new Set<Id>();
            Set<Id> studentContactIds = new Set<Id>();
            for (Appointment_Request__c requestRecord : requests) {
                if (requestRecord.Primary_Advisor__c != null) {
                    advisorUserIds.add(requestRecord.Primary_Advisor__c);
                }
                if (requestRecord.Student__c != null) {
                    studentContactIds.add(requestRecord.Student__c);
                }
            }
            if (advisorUserIds.isEmpty()) {
                return;
            }

            Map<Id, User> advisorById = new Map<Id, User>([
                SELECT Id, Name, Email, IsActive
                FROM User
                WHERE Id IN :advisorUserIds
            ]);
            Map<Id, Contact> studentById = studentContactIds.isEmpty()
                ? new Map<Id, Contact>()
                : new Map<Id, Contact>([
                    SELECT Id, Name
                    FROM Contact
                    WHERE Id IN :studentContactIds
                ]);

            List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
            Map<Id, Set<String>> bodiesByAdvisor = new Map<Id, Set<String>>();
            Id senderOrgWideEmailId = getAppointmentRequestSenderOweaId();

            for (Appointment_Request__c requestRecord : requests) {
                User advisor = advisorById.get(requestRecord.Primary_Advisor__c);
                if (advisor == null || !advisor.IsActive) {
                    continue;
                }

                String studentName = studentById.containsKey(requestRecord.Student__c)
                    ? studentById.get(requestRecord.Student__c).Name
                    : 'A student';

                String notifBody = studentName + ' has requested an appointment for '
                    + formatDateTimeRange(requestRecord.Start_DateTime__c, requestRecord.End_DateTime__c) + '.';

                String meetingTitle = String.isNotBlank(requestRecord.Name) ? requestRecord.Name : null;
                String emailBody = studentName + ' has requested an appointment.\n\n'
                    + (meetingTitle != null ? 'Title: ' + meetingTitle + '\n' : '')
                    + 'When: ' + formatDateTimeRange(requestRecord.Start_DateTime__c, requestRecord.End_DateTime__c)
                    + (String.isNotBlank(requestRecord.Request_Type__c) ? '\nType: ' + requestRecord.Request_Type__c : '')
                    + (String.isNotBlank(requestRecord.Reason__c) ? '\nReason: ' + requestRecord.Reason__c : '')
                    + '\n\nPlease log in to review and respond to this request.';

                if (!bodiesByAdvisor.containsKey(advisor.Id)) {
                    bodiesByAdvisor.put(advisor.Id, new Set<String>());
                }
                bodiesByAdvisor.get(advisor.Id).add(emailBody);

                sendCustomNotification(
                    'New Appointment Request',
                    notifBody,
                    requestRecord.Id,
                    new Set<Id>{ advisor.Id }
                );
            }

            for (Id advisorId : bodiesByAdvisor.keySet()) {
                User advisor = advisorById.get(advisorId);
                if (advisor == null || String.isBlank(advisor.Email)) {
                    continue;
                }

                Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                email.setToAddresses(new String[]{ advisor.Email });
                email.setSubject('New Appointment Request');
                email.setPlainTextBody(String.join(new List<String>(bodiesByAdvisor.get(advisorId)), '\n\n' + '---' + '\n\n'));
                email.setSaveAsActivity(false);
                if (senderOrgWideEmailId != null) {
                    email.setOrgWideEmailAddressId(senderOrgWideEmailId);
                }
                emails.add(email);
            }

            sendEmails(emails);
        } catch (Exception ex) {
            System.debug('AdvisingNotificationService.notifyAdvisorOfAppointmentRequest error: ' + ex.getMessage());
        }
    }

    public static void notifyStudentOfAppointmentRequestSubmission(
        Appointment_Request__c requestRecord,
        Id studentUserId
    ) {
        if (requestRecord == null || studentUserId == null) {
            return;
        }

        try {
            String body = 'Your appointment request has been sent to the advisor.';
            sendCustomNotificationWithPageRef(
                'Appointment Request Submitted',
                body,
                STUDENT_ADVISING_PAGE_REF,
                new Set<Id>{ studentUserId }
            );
        } catch (Exception ex) {
            System.debug('AdvisingNotificationService.notifyStudentOfAppointmentRequestSubmission error: ' + ex.getMessage());
        }
    }

    public static void notifyStudentOfApprovedAppointment(List<Appointment_Request__c> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }

        try {
            Set<Id> studentContactIds = new Set<Id>();
            Set<Id> advisorUserIds = new Set<Id>();
            for (Appointment_Request__c requestRecord : requests) {
                if (requestRecord.Student__c != null) {
                    studentContactIds.add(requestRecord.Student__c);
                }
                if (requestRecord.Primary_Advisor__c != null) {
                    advisorUserIds.add(requestRecord.Primary_Advisor__c);
                }
            }
            if (studentContactIds.isEmpty()) {
                return;
            }

            Map<Id, Contact> studentById = new Map<Id, Contact>([
                SELECT Id, Name, Email, HasOptedOutOfEmail
                FROM Contact
                WHERE Id IN :studentContactIds
            ]);
            Map<Id, User> studentUserByContactId = new Map<Id, User>();
            for (User userRecord : [
                SELECT Id, ContactId, IsActive
                FROM User
                WHERE ContactId IN :studentContactIds
            ]) {
                if (userRecord.IsActive) {
                    studentUserByContactId.put(userRecord.ContactId, userRecord);
                }
            }
            Map<Id, User> advisorById = advisorUserIds.isEmpty()
                ? new Map<Id, User>()
                : new Map<Id, User>([
                    SELECT Id, Name
                    FROM User
                    WHERE Id IN :advisorUserIds
                ]);

            List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
            for (Appointment_Request__c requestRecord : requests) {
                Contact student = studentById.get(requestRecord.Student__c);
                if (student == null) {
                    continue;
                }

                User studentUser = studentUserByContactId.get(student.Id);
                String advisorName = advisorById.containsKey(requestRecord.Primary_Advisor__c)
                    ? advisorById.get(requestRecord.Primary_Advisor__c).Name
                    : 'your advisor';
                String body = 'Your appointment with ' + advisorName
                    + ' has been approved for '
                    + formatDateTimeRange(requestRecord.Start_DateTime__c, requestRecord.End_DateTime__c)
                    + '.';

                if (studentUser != null) {
                    sendCustomNotificationWithPageRef(
                        'Appointment Approved',
                        body,
                        STUDENT_ADVISING_PAGE_REF,
                        new Set<Id>{ studentUser.Id }
                    );
                }

                if (String.isBlank(student.Email) || student.HasOptedOutOfEmail) {
                    continue;
                }

                Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                email.setToAddresses(new String[]{ student.Email });
                email.setSubject('Your appointment has been approved');
                email.setPlainTextBody(body);
                email.setSaveAsActivity(false);
                emails.add(email);
            }

            sendEmails(emails);
        } catch (Exception ex) {
            System.debug('AdvisingNotificationService.notifyStudentOfApprovedAppointment error: ' + ex.getMessage());
        }
    }

    /**
     * @description Notifies students when an advisor creates a new appointment for them.
     *              This method is called from the after-insert handler to notify students
     *              about follow-up meetings or appointments created by advisors.
     *              Bulkified to handle up to 200 records.
     * @param requests List of newly inserted appointment requests created by advisors
     */
    public static void notifyStudentOfNewAppointment(List<Appointment_Request__c> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }

        try {
            // Deduplicate student and advisor IDs to minimize SOQL queries
            Set<Id> studentContactIds = new Set<Id>();
            Set<Id> advisorUserIds = new Set<Id>();
            
            for (Appointment_Request__c requestRecord : requests) {
                if (requestRecord.Student__c != null) {
                    studentContactIds.add(requestRecord.Student__c);
                }
                if (requestRecord.Primary_Advisor__c != null) {
                    advisorUserIds.add(requestRecord.Primary_Advisor__c);
                }
            }

            if (studentContactIds.isEmpty()) {
                return;
            }

            // Query student contacts with email information
            Map<Id, Contact> studentById = new Map<Id, Contact>([
                SELECT Id, Name, Email, HasOptedOutOfEmail
                FROM Contact
                WHERE Id IN :studentContactIds
            ]);

            // Query active student users for in-app notifications
            Map<Id, User> studentUserByContactId = new Map<Id, User>();
            for (User userRecord : [
                SELECT Id, ContactId, IsActive
                FROM User
                WHERE ContactId IN :studentContactIds
            ]) {
                if (userRecord.IsActive) {
                    studentUserByContactId.put(userRecord.ContactId, userRecord);
                }
            }

            // Query advisor information for notification message
            Map<Id, User> advisorById = advisorUserIds.isEmpty()
                ? new Map<Id, User>()
                : new Map<Id, User>([
                    SELECT Id, Name
                    FROM User
                    WHERE Id IN :advisorUserIds
                ]);

            List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

            for (Appointment_Request__c requestRecord : requests) {
                Contact student = studentById.get(requestRecord.Student__c);
                if (student == null) {
                    continue;
                }

                User studentUser = studentUserByContactId.get(student.Id);
                String advisorName = advisorById.containsKey(requestRecord.Primary_Advisor__c)
                    ? advisorById.get(requestRecord.Primary_Advisor__c).Name
                    : 'your advisor';

                // Build notification body
                String body = advisorName + ' has scheduled a new appointment for you on '
                    + formatDateTimeRange(requestRecord.Start_DateTime__c, requestRecord.End_DateTime__c)
                    + '.';

                // Send in-app notification if student user exists
                if (studentUser != null) {
                    sendCustomNotificationWithPageRef(
                        'New Appointment Scheduled',
                        body,
                        STUDENT_ADVISING_PAGE_REF,
                        new Set<Id>{ studentUser.Id }
                    );
                }

                // Prepare email if student has a valid email address and hasn't opted out
                if (String.isBlank(student.Email) || student.HasOptedOutOfEmail) {
                    continue;
                }

                String meetingTitle = String.isNotBlank(requestRecord.Name) ? requestRecord.Name : 'Advising Session';
                String emailBody = advisorName + ' has scheduled a new appointment for you.\n\n'
                    + 'Title: ' + meetingTitle + '\n'
                    + 'When: ' + formatDateTimeRange(requestRecord.Start_DateTime__c, requestRecord.End_DateTime__c)
                    + (String.isNotBlank(requestRecord.Request_Type__c) ? '\nType: ' + requestRecord.Request_Type__c : '')
                    + (String.isNotBlank(requestRecord.Reason__c) ? '\nReason: ' + requestRecord.Reason__c : '')
                    + '\n\nPlease log in to view this appointment in your schedule.';

                Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                email.setToAddresses(new String[]{ student.Email });
                email.setSubject('New appointment scheduled');
                email.setPlainTextBody(emailBody);
                email.setSaveAsActivity(false);
                emails.add(email);
            }

            // Batch email sending if list size exceeds 100
            if (emails.size() > 100) {
                List<Messaging.SingleEmailMessage> batch = new List<Messaging.SingleEmailMessage>();
                for (Integer i = 0; i < emails.size(); i++) {
                    batch.add(emails[i]);
                    if (batch.size() == 100 || i == emails.size() - 1) {
                        sendEmails(batch);
                        batch.clear();
                    }
                }
            } else {
                sendEmails(emails);
            }
        } catch (Exception ex) {
            System.debug('AdvisingNotificationService.notifyStudentOfNewAppointment error: ' + ex.getMessage());
        }
    }

    public static void notifyStudentOfAppointmentChanges(
        List<Appointment_Request__c> newList,
        Map<Id, Appointment_Request__c> oldMap
    ) {
        if (newList == null || newList.isEmpty() || oldMap == null) {
            return;
        }

        try {
            Set<Id> studentContactIds = new Set<Id>();
            Set<Id> advisorUserIds = new Set<Id>();
            List<Appointment_Request__c> changedRequests = new List<Appointment_Request__c>();

            for (Appointment_Request__c requestRecord : newList) {
                Appointment_Request__c oldRecord = oldMap.get(requestRecord.Id);
                if (oldRecord == null || requestRecord.Student__c == null) {
                    continue;
                }

                if (!isStudentNotifiableChange(requestRecord, oldRecord)) {
                    continue;
                }

                changedRequests.add(requestRecord);
                studentContactIds.add(requestRecord.Student__c);
                if (requestRecord.Primary_Advisor__c != null) {
                    advisorUserIds.add(requestRecord.Primary_Advisor__c);
                }
            }

            if (changedRequests.isEmpty()) {
                return;
            }

            Map<Id, Contact> studentById = new Map<Id, Contact>([
                SELECT Id, Name, Email, HasOptedOutOfEmail
                FROM Contact
                WHERE Id IN :studentContactIds
            ]);
            Map<Id, User> studentUserByContactId = new Map<Id, User>();
            for (User userRecord : [
                SELECT Id, ContactId, IsActive
                FROM User
                WHERE ContactId IN :studentContactIds
            ]) {
                if (userRecord.IsActive) {
                    studentUserByContactId.put(userRecord.ContactId, userRecord);
                }
            }
            Map<Id, User> advisorById = advisorUserIds.isEmpty()
                ? new Map<Id, User>()
                : new Map<Id, User>([
                    SELECT Id, Name
                    FROM User
                    WHERE Id IN :advisorUserIds
                ]);

            List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
            for (Appointment_Request__c requestRecord : changedRequests) {
                Appointment_Request__c oldRecord = oldMap.get(requestRecord.Id);
                Contact student = studentById.get(requestRecord.Student__c);
                if (student == null) {
                    continue;
                }

                String body = buildAppointmentChangeMessage(
                    requestRecord,
                    oldRecord,
                    advisorById.get(requestRecord.Primary_Advisor__c)
                );
                if (String.isBlank(body)) {
                    continue;
                }

                User studentUser = studentUserByContactId.get(student.Id);
                if (studentUser != null) {
                    sendCustomNotificationWithPageRef(
                        'Appointment Updated',
                        body,
                        STUDENT_ADVISING_PAGE_REF,
                        new Set<Id>{ studentUser.Id }
                    );
                }

                if (String.isBlank(student.Email) || student.HasOptedOutOfEmail) {
                    continue;
                }

                Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                email.setToAddresses(new String[]{ student.Email });
                email.setSubject('Your appointment has been updated');
                email.setPlainTextBody(body);
                email.setSaveAsActivity(false);
                emails.add(email);
            }

            sendEmails(emails);
        } catch (Exception ex) {
            System.debug('AdvisingNotificationService.notifyStudentOfAppointmentChanges error: ' + ex.getMessage());
        }
    }

    public static void notifyStudentOfChecklistActivation(List<Course_Checklist__c> checklists) {
        if (checklists == null || checklists.isEmpty()) {
            return;
        }

        try {
            Set<Id> studentContactIds = new Set<Id>();
            for (Course_Checklist__c checklist : checklists) {
                if (checklist.Student__c != null) {
                    studentContactIds.add(checklist.Student__c);
                }
            }
            if (studentContactIds.isEmpty()) {
                return;
            }

            Map<Id, Contact> studentById = new Map<Id, Contact>([
                SELECT Id, Name, Email, HasOptedOutOfEmail
                FROM Contact
                WHERE Id IN :studentContactIds
            ]);
            Map<Id, User> studentUserByContactId = new Map<Id, User>();
            for (User userRecord : [
                SELECT Id, ContactId, IsActive
                FROM User
                WHERE ContactId IN :studentContactIds
            ]) {
                if (userRecord.IsActive) {
                    studentUserByContactId.put(userRecord.ContactId, userRecord);
                }
            }

            List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
            for (Course_Checklist__c checklist : checklists) {
                Contact student = studentById.get(checklist.Student__c);
                if (student == null) {
                    continue;
                }

                String body = 'A new checklist has been created for you: ' + checklist.Name + '.';
                User studentUser = studentUserByContactId.get(student.Id);
                if (studentUser != null) {
                    sendCustomNotificationWithPageRef(
                        'New Course Checklist',
                        body,
                        STUDENT_ADVISING_PAGE_REF,
                        new Set<Id>{ studentUser.Id }
                    );
                }

                if (String.isBlank(student.Email) || student.HasOptedOutOfEmail) {
                    continue;
                }

                Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                email.setToAddresses(new String[]{ student.Email });
                email.setSubject('A new course checklist has been assigned');
                email.setPlainTextBody(body);
                email.setSaveAsActivity(false);
                emails.add(email);
            }

            sendEmails(emails);
        } catch (Exception ex) {
            System.debug('AdvisingNotificationService.notifyStudentOfChecklistActivation error: ' + ex.getMessage());
        }
    }

    /**
     * @description Notifies students when an advisor creates a new Event (appointment) for them.
     *              Called from EventHandler.handleAfterInsert for advisor-created events.
     *              Bulkified to handle up to 200 events.
     * @param events List of newly inserted Event records created by advisors
     */
    public static void notifyStudentOfNewEvent(List<Event> events) {
        if (events == null || events.isEmpty()) {
            return;
        }

        try {
            // Collect WhoIds (Contact IDs) from events
            Set<Id> contactIds = new Set<Id>();
            for (Event evt : events) {
                if (evt.WhoId != null) {
                    contactIds.add(evt.WhoId);
                }
            }

            if (contactIds.isEmpty()) {
                return;
            }

            // Query Contact records with email and user information
            Map<Id, Contact> contactById = new Map<Id, Contact>([
                SELECT Id, FirstName, Email, HasOptedOutOfEmail, Linked_User_Id__c
                FROM Contact
                WHERE Id IN :contactIds
            ]);

            // Query User records for in-app notifications
            Map<Id, User> userById = new Map<Id, User>([
                SELECT Id, IsActive
                FROM User
                WHERE Id IN (SELECT Linked_User_Id__c FROM Contact WHERE Id IN :contactIds AND Linked_User_Id__c != null)
                AND IsActive = true
            ]);

            List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

            for (Event evt : events) {
                Contact contact = contactById.get(evt.WhoId);
                if (contact == null) {
                    continue;
                }

                String firstName = contact.FirstName != null ? contact.FirstName : 'Student';
                String timeRange = formatDateTimeRange(evt.StartDateTime, evt.EndDateTime);
                String subject = String.isNotBlank(evt.Subject) ? evt.Subject : 'Appointment';

                // Build notification message
                String notifBody = 'Your advisor has created a new appointment for ' + timeRange + '. Subject: ' + subject + '.';

                // Send in-app notification if user exists
                if (contact.Linked_User_Id__c != null && userById.containsKey(contact.Linked_User_Id__c)) {
                    sendCustomNotificationWithPageRef(
                        'New Appointment Scheduled',
                        notifBody,
                        STUDENT_ADVISING_PAGE_REF,
                        new Set<Id>{ contact.Linked_User_Id__c }
                    );
                }

                // Prepare email if contact has valid email and hasn't opted out
                if (String.isBlank(contact.Email) || contact.HasOptedOutOfEmail) {
                    continue;
                }

                String emailBody = 'Dear ' + firstName + ',\n\n'
                    + 'Your advisor has created a new appointment for you.\n\n'
                    + 'Subject: ' + subject + '\n'
                    + 'When: ' + timeRange + '\n'
                    + (String.isNotBlank(evt.Description) ? 'Description: ' + evt.Description + '\n' : '')
                    + '\nPlease log in to view this appointment in your schedule.\n\n'
                    + 'Regards,\nStudent Success Team';

                Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                email.setToAddresses(new String[]{ contact.Email });
                email.setSubject('New appointment scheduled by your advisor');
                email.setPlainTextBody(emailBody);
                email.setSaveAsActivity(false);
                emails.add(email);
            }

            // Batch email sending if list size exceeds 100
            if (emails.size() > 100) {
                List<Messaging.SingleEmailMessage> batch = new List<Messaging.SingleEmailMessage>();
                for (Integer i = 0; i < emails.size(); i++) {
                    batch.add(emails[i]);
                    if (batch.size() == 100 || i == emails.size() - 1) {
                        sendEmails(batch);
                        batch.clear();
                    }
                }
            } else {
                sendEmails(emails);
            }
        } catch (Exception ex) {
            System.debug('AdvisingNotificationService.notifyStudentOfNewEvent error: ' + ex.getMessage());
        }
    }

    /**
     * @description Sends email notifications to all event attendees (EventRelation records)
     *              Handles both User and Contact attendees
     * @param eventIds Set of Event IDs to notify attendees for
     */
    @future
    public static void notifyAllEventAttendees(Set<Id> eventIds) {
        if (eventIds == null || eventIds.isEmpty()) {
            return;
        }

        try {
            // Query Events with creator information
            Map<Id, Event> eventMap = new Map<Id, Event>([
                SELECT Id, Subject, StartDateTime, EndDateTime, Location, 
                       Description, CreatedById, CreatedBy.Name
                FROM Event
                WHERE Id IN :eventIds
                WITH SECURITY_ENFORCED
            ]);

            // Query EventRelation records to get all attendees
            List<EventRelation> attendees = [
                SELECT Id, EventId, RelationId, IsWhat, Status
                FROM EventRelation
                WHERE EventId IN :eventIds
                AND IsWhat = false
                WITH SECURITY_ENFORCED
            ];

            if (attendees.isEmpty()) {
                return;
            }

            // Separate User IDs and Contact IDs
            Set<Id> userIds = new Set<Id>();
            Set<Id> contactIds = new Set<Id>();

            for (EventRelation rel : attendees) {
                String relIdStr = String.valueOf(rel.RelationId);
                if (relIdStr.startsWith('005')) {
                    userIds.add(rel.RelationId); // User
                } else if (relIdStr.startsWith('003')) {
                    contactIds.add(rel.RelationId); // Contact
                }
            }

            // Query User information
            Map<Id, User> userById = new Map<Id, User>([
                SELECT Id, Email, Name, IsActive
                FROM User
                WHERE Id IN :userIds
            ]);

            // Query Contact information
            Map<Id, Contact> contactById = new Map<Id, Contact>([
                SELECT Id, Email, Name, HasOptedOutOfEmail
                FROM Contact
                WHERE Id IN :contactIds
                WITH SECURITY_ENFORCED
            ]);

            // Build email list
            List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

            for (EventRelation rel : attendees) {
                Event evt = eventMap.get(rel.EventId);
                if (evt == null) {
                    continue;
                }

                String recipientEmail;
                String recipientName;

                // Determine recipient based on RelationId type
                String relIdStr = String.valueOf(rel.RelationId);
                if (relIdStr.startsWith('005')) {
                    // User attendee
                    User u = userById.get(rel.RelationId);
                    if (u == null || !u.IsActive || String.isBlank(u.Email)) {
                        continue;
                    }
                    // Skip if this is the event creator (they don't need a notification)
                    if (u.Id == evt.CreatedById) {
                        continue;
                    }
                    recipientEmail = u.Email;
                    recipientName = u.Name;
                } else if (relIdStr.startsWith('003')) {
                    // Contact attendee
                    Contact c = contactById.get(rel.RelationId);
                    if (c == null || c.HasOptedOutOfEmail || String.isBlank(c.Email)) {
                        continue;
                    }
                    recipientEmail = c.Email;
                    recipientName = c.Name;
                } else {
                    continue;
                }

                // Create email message
                Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                email.setToAddresses(new List<String>{ recipientEmail });
                email.setSubject('Event Invitation: ' + evt.Subject);

                // Format date/time
                String startTime = evt.StartDateTime != null ? 
                    evt.StartDateTime.format('MMMM d, yyyy h:mm a') : 'Not specified';
                String endTime = evt.EndDateTime != null ? 
                    evt.EndDateTime.format('h:mm a') : 'Not specified';

                // Build email body
                String emailBody = 'Dear ' + recipientName + ',\n\n';
                emailBody += 'You have been invited to the following event:\n\n';
                emailBody += 'Event: ' + evt.Subject + '\n';
                emailBody += 'Organized by: ' + evt.CreatedBy.Name + '\n';
                emailBody += 'Start: ' + startTime + '\n';
                emailBody += 'End: ' + endTime + '\n';
                
                if (String.isNotBlank(evt.Location)) {
                    emailBody += 'Location: ' + evt.Location + '\n';
                }
                
                if (String.isNotBlank(evt.Description)) {
                    emailBody += '\nDescription:\n' + evt.Description + '\n';
                }
                
                emailBody += '\nPlease mark your calendar accordingly.\n\n';
                emailBody += 'Best regards,\n';
                emailBody += 'Academic Advising Team';

                email.setPlainTextBody(emailBody);
                emails.add(email);
            }

            // Send emails in batches (max 10 per send)
            if (!emails.isEmpty()) {
                Integer batchSize = 10;
                for (Integer i = 0; i < emails.size(); i += batchSize) {
                    Integer endIndex = Math.min(i + batchSize, emails.size());
                    List<Messaging.SingleEmailMessage> batch = new List<Messaging.SingleEmailMessage>();
                    for (Integer j = i; j < endIndex; j++) {
                        batch.add(emails[j]);
                    }
                    Messaging.sendEmail(batch, false);
                }
            }

        } catch (Exception ex) {
            System.debug('AdvisingNotificationService.notifyAllEventAttendees error: ' + ex.getMessage());
        }
    }

    public static void notifyGeneralSupportStatusUpdates(List<Case> newCases, Map<Id, Case> oldMap) {
        if (newCases == null || newCases.isEmpty() || oldMap == null) {
            return;
        }

        try {
            Set<Id> studentContactIds = new Set<Id>();
            List<Case> targetCases = new List<Case>();

            for (Case caseRecord : newCases) {
                Case oldCase = oldMap.get(caseRecord.Id);
                if (oldCase == null) {
                    continue;
                }

                if (caseRecord.RecordTypeId == null
                    || caseRecord.RecordType == null
                    || caseRecord.RecordType.DeveloperName != GENERAL_SUPPORT_RT_DEVELOPER_NAME
                    || caseRecord.Status == oldCase.Status
                    || caseRecord.ContactId == null) {
                    continue;
                }

                targetCases.add(caseRecord);
                studentContactIds.add(caseRecord.ContactId);
            }

            if (targetCases.isEmpty() || studentContactIds.isEmpty()) {
                return;
            }

            Map<Id, Contact> studentById = new Map<Id, Contact>([
                SELECT Id, New_Admit_Email__c
                FROM Contact
                WHERE Id IN :studentContactIds
            ]);

            Map<Id, User> activeStudentUserByContactId = new Map<Id, User>();
            for (User userRecord : [
                SELECT Id, ContactId, IsActive
                FROM User
                WHERE ContactId IN :studentContactIds
            ]) {
                if (userRecord.IsActive) {
                    activeStudentUserByContactId.put(userRecord.ContactId, userRecord);
                }
            }

            List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
            for (Case caseRecord : targetCases) {
                Contact student = studentById.get(caseRecord.ContactId);
                if (student == null) {
                    continue;
                }

                String messageBody = 'Your case ' + caseRecord.CaseNumber + ' status has been updated to ' + caseRecord.Status + '.';
                User studentUser = activeStudentUserByContactId.get(caseRecord.ContactId);

                if (studentUser != null) {
                    sendCustomNotification('Case Status Updated', messageBody, caseRecord.Id, new Set<Id>{ studentUser.Id });
                }

                if (String.isNotBlank(student.New_Admit_Email__c)) {
                    Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                    email.setToAddresses(new String[]{ student.New_Admit_Email__c });
                    email.setSubject('Case status updated');
                    email.setPlainTextBody(messageBody);
                    email.setSaveAsActivity(false);
                    emails.add(email);
                }
            }

            sendEmails(emails);
        } catch (Exception ex) {
            System.debug('AdvisingNotificationService.notifyGeneralSupportStatusUpdates error: ' + ex.getMessage());
        }
    }

    public static void notifyGeneralSupportCaseComments(List<CaseComment> comments) {
        if (comments == null || comments.isEmpty()) {
            return;
        }

        try {
            Set<Id> caseIds = new Set<Id>();
            for (CaseComment commentRecord : comments) {
                if (commentRecord.ParentId != null) {
                    caseIds.add(commentRecord.ParentId);
                }
            }

            if (caseIds.isEmpty()) {
                return;
            }

            Map<Id, Case> caseById = new Map<Id, Case>([
                SELECT Id, CaseNumber, ContactId, OwnerId, RecordType.DeveloperName
                FROM Case
                WHERE Id IN :caseIds
            ]);

            Set<Id> studentContactIds = new Set<Id>();
            Set<Id> ownerUserIds = new Set<Id>();
            for (Case caseRecord : caseById.values()) {
                if (caseRecord.RecordType != null && caseRecord.RecordType.DeveloperName == GENERAL_SUPPORT_RT_DEVELOPER_NAME) {
                    if (caseRecord.ContactId != null) {
                        studentContactIds.add(caseRecord.ContactId);
                    }
                    if (caseRecord.OwnerId != null && String.valueOf(caseRecord.OwnerId).startsWith('005')) {
                        ownerUserIds.add(caseRecord.OwnerId);
                    }
                }
            }

            Map<Id, Contact> studentById = studentContactIds.isEmpty()
                ? new Map<Id, Contact>()
                : new Map<Id, Contact>([
                    SELECT Id, New_Admit_Email__c
                    FROM Contact
                    WHERE Id IN :studentContactIds
                ]);

            Map<Id, User> activeStudentUserByContactId = new Map<Id, User>();
            if (!studentContactIds.isEmpty()) {
                for (User userRecord : [
                    SELECT Id, ContactId, IsActive
                    FROM User
                    WHERE ContactId IN :studentContactIds
                ]) {
                    if (userRecord.IsActive) {
                        activeStudentUserByContactId.put(userRecord.ContactId, userRecord);
                    }
                }
            }

            Map<Id, User> ownerUserById = ownerUserIds.isEmpty()
                ? new Map<Id, User>()
                : new Map<Id, User>([
                    SELECT Id, Email, IsActive
                    FROM User
                    WHERE Id IN :ownerUserIds
                ]);

            List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
            for (CaseComment commentRecord : comments) {
                Case caseRecord = caseById.get(commentRecord.ParentId);
                if (caseRecord == null
                    || caseRecord.RecordType == null
                    || caseRecord.RecordType.DeveloperName != GENERAL_SUPPORT_RT_DEVELOPER_NAME) {
                    continue;
                }

                if (caseRecord.ContactId != null && commentRecord.IsPublished == true) {
                    Contact student = studentById.get(caseRecord.ContactId);
                    if (student != null) {
                        String studentBody = 'A new public comment has been added to your case ' + caseRecord.CaseNumber + '.';
                        User studentUser = activeStudentUserByContactId.get(caseRecord.ContactId);
                        if (studentUser != null) {
                            sendCustomNotification('Case Comment Added', studentBody, caseRecord.Id, new Set<Id>{ studentUser.Id });
                        }

                        if (String.isNotBlank(student.New_Admit_Email__c)) {
                            Messaging.SingleEmailMessage studentEmail = new Messaging.SingleEmailMessage();
                            studentEmail.setToAddresses(new String[]{ student.New_Admit_Email__c });
                            studentEmail.setSubject('New comment on your case');
                            studentEmail.setPlainTextBody(studentBody);
                            studentEmail.setSaveAsActivity(false);
                            emails.add(studentEmail);
                        }
                    }
                }

                if (caseRecord.OwnerId != null && String.valueOf(caseRecord.OwnerId).startsWith('005')) {
                    User ownerUser = ownerUserById.get(caseRecord.OwnerId);
                    String adminBody = 'A new comment has been added on General Support case ' + caseRecord.CaseNumber + '.';

                    if (ownerUser != null && ownerUser.IsActive) {
                        sendCustomNotification('General Support Comment Added', adminBody, caseRecord.Id, new Set<Id>{ ownerUser.Id });
                    }

                    if (ownerUser != null && String.isNotBlank(ownerUser.Email)) {
                        Messaging.SingleEmailMessage ownerEmail = new Messaging.SingleEmailMessage();
                        ownerEmail.setToAddresses(new String[]{ ownerUser.Email });
                        ownerEmail.setSubject('New comment on General Support case');
                        ownerEmail.setPlainTextBody(adminBody);
                        ownerEmail.setSaveAsActivity(false);
                        emails.add(ownerEmail);
                    }
                }
            }

            sendEmails(emails);
        } catch (Exception ex) {
            System.debug('AdvisingNotificationService.notifyGeneralSupportCaseComments error: ' + ex.getMessage());
        }
    }

    public static void notifyGeneralSupportAttachmentAdded(List<ContentDocumentLink> links) {
        if (links == null || links.isEmpty()) {
            return;
        }

        try {
            Set<Id> caseIds = new Set<Id>();
            for (ContentDocumentLink linkRecord : links) {
                if (linkRecord.LinkedEntityId != null && String.valueOf(linkRecord.LinkedEntityId).startsWith('500')) {
                    caseIds.add(linkRecord.LinkedEntityId);
                }
            }

            if (caseIds.isEmpty()) {
                return;
            }

            Map<Id, Case> caseById = new Map<Id, Case>([
                SELECT Id, CaseNumber, OwnerId, RecordType.DeveloperName
                FROM Case
                WHERE Id IN :caseIds
            ]);

            Set<Id> ownerUserIds = new Set<Id>();
            for (Case caseRecord : caseById.values()) {
                if (caseRecord.RecordType != null
                    && caseRecord.RecordType.DeveloperName == GENERAL_SUPPORT_RT_DEVELOPER_NAME
                    && caseRecord.OwnerId != null
                    && String.valueOf(caseRecord.OwnerId).startsWith('005')) {
                    ownerUserIds.add(caseRecord.OwnerId);
                }
            }

            if (ownerUserIds.isEmpty()) {
                return;
            }

            Map<Id, User> ownerUserById = new Map<Id, User>([
                SELECT Id, Email, IsActive
                FROM User
                WHERE Id IN :ownerUserIds
            ]);

            List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
            for (ContentDocumentLink linkRecord : links) {
                Case caseRecord = caseById.get(linkRecord.LinkedEntityId);
                if (caseRecord == null
                    || caseRecord.RecordType == null
                    || caseRecord.RecordType.DeveloperName != GENERAL_SUPPORT_RT_DEVELOPER_NAME
                    || caseRecord.OwnerId == null
                    || !String.valueOf(caseRecord.OwnerId).startsWith('005')) {
                    continue;
                }

                User ownerUser = ownerUserById.get(caseRecord.OwnerId);
                String body = 'A new file has been attached to General Support case ' + caseRecord.CaseNumber + '.';

                if (ownerUser != null && ownerUser.IsActive) {
                    sendCustomNotification('General Support Attachment Added', body, caseRecord.Id, new Set<Id>{ ownerUser.Id });
                }

                if (ownerUser != null && String.isNotBlank(ownerUser.Email)) {
                    Messaging.SingleEmailMessage ownerEmail = new Messaging.SingleEmailMessage();
                    ownerEmail.setToAddresses(new String[]{ ownerUser.Email });
                    ownerEmail.setSubject('New file on General Support case');
                    ownerEmail.setPlainTextBody(body);
                    ownerEmail.setSaveAsActivity(false);
                    emails.add(ownerEmail);
                }
            }

            sendEmails(emails);
        } catch (Exception ex) {
            System.debug('AdvisingNotificationService.notifyGeneralSupportAttachmentAdded error: ' + ex.getMessage());
        }
    }

    private static void sendEmails(List<Messaging.SingleEmailMessage> emails) {
        if (emails == null || emails.isEmpty()) {
            return;
        }

        try {
            Messaging.sendEmail(emails, false);
        } catch (Exception ex) {
            System.debug('AdvisingNotificationService.sendEmails error: ' + ex.getMessage());
        }
    }

    private static void sendCustomNotification(String title, String body, Id targetId, Set<Id> recipientUserIds) {
        if (recipientUserIds == null || recipientUserIds.isEmpty()) {
            return;
        }

        List<CustomNotificationType> notificationTypes = [
            SELECT Id
            FROM CustomNotificationType
            WHERE DeveloperName = :NOTIFICATION_TYPE_DEVELOPER_NAME
            LIMIT 1
        ];
        if (notificationTypes.isEmpty()) {
            return;
        }

        Messaging.CustomNotification notification = new Messaging.CustomNotification();
        notification.setTitle(title);
        notification.setBody(body);
        notification.setNotificationTypeId(notificationTypes[0].Id);
        notification.setTargetId(targetId);
        notification.setSenderId(UserInfo.getUserId());
        Set<String> recipients = new Set<String>();
        for (Id recipientUserId : recipientUserIds) {
            recipients.add(String.valueOf(recipientUserId));
        }
        try {
            notification.send(recipients);
        } catch (Exception ex) {
            System.debug('sendCustomNotification send error: ' + ex.getMessage());
        }
    }

    private static void sendCustomNotificationWithPageRef(
        String title,
        String body,
        String targetPageRef,
        Set<Id> recipientUserIds
    ) {
        if (recipientUserIds == null || recipientUserIds.isEmpty() || String.isBlank(targetPageRef)) {
            return;
        }

        List<CustomNotificationType> notificationTypes = [
            SELECT Id
            FROM CustomNotificationType
            WHERE DeveloperName = :NOTIFICATION_TYPE_DEVELOPER_NAME
            LIMIT 1
        ];
        if (notificationTypes.isEmpty()) {
            return;
        }

        Messaging.CustomNotification notification = new Messaging.CustomNotification();
        notification.setTitle(title);
        notification.setBody(body);
        notification.setNotificationTypeId(notificationTypes[0].Id);
        notification.setTargetPageRef(targetPageRef);
        notification.setSenderId(UserInfo.getUserId());

        Set<String> recipients = new Set<String>();
        for (Id recipientUserId : recipientUserIds) {
            recipients.add(String.valueOf(recipientUserId));
        }
        try {
            notification.send(recipients);
        } catch (Exception ex) {
            System.debug('sendCustomNotificationWithPageRef send error: ' + ex.getMessage());
        }
    }

    private static Id getAppointmentRequestSenderOweaId() {
        if (appointmentRequestSenderOweaId != null) {
            return appointmentRequestSenderOweaId;
        }

        List<OrgWideEmailAddress> oweaList = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE DisplayName = :APPOINTMENT_REQUEST_SENDER_OWEA_NAME
            LIMIT 1
        ];

        if (!oweaList.isEmpty()) {
            appointmentRequestSenderOweaId = oweaList[0].Id;
        }

        return appointmentRequestSenderOweaId;
    }

    private static String formatDateTimeRange(Datetime startDateTime, Datetime endDateTime) {
        if (startDateTime == null || endDateTime == null) {
            return 'the scheduled time';
        }

        return startDateTime.format('MMM d, yyyy h:mm a') + ' to ' + endDateTime.format('h:mm a');
    }

    private static Boolean isStudentNotifiableChange(
        Appointment_Request__c newRecord,
        Appointment_Request__c oldRecord
    ) {
        Boolean statusChanged = newRecord.Status__c != oldRecord.Status__c;
        Boolean timeChanged = newRecord.Start_DateTime__c != oldRecord.Start_DateTime__c
            || newRecord.End_DateTime__c != oldRecord.End_DateTime__c;
        Boolean detailChanged = newRecord.Name != oldRecord.Name
            || newRecord.Request_Type__c != oldRecord.Request_Type__c
            || newRecord.Reason__c != oldRecord.Reason__c
            || newRecord.Rejection_Reason__c != oldRecord.Rejection_Reason__c;

        if (statusChanged && newRecord.Status__c == 'Approved') {
            return false;
        }

        return statusChanged || timeChanged || detailChanged;
    }

    private static String buildAppointmentChangeMessage(
        Appointment_Request__c newRecord,
        Appointment_Request__c oldRecord,
        User advisor
    ) {
        String advisorName = advisor != null ? advisor.Name : 'your advisor';
        Boolean statusChanged = newRecord.Status__c != oldRecord.Status__c;
        Boolean timeChanged = newRecord.Start_DateTime__c != oldRecord.Start_DateTime__c
            || newRecord.End_DateTime__c != oldRecord.End_DateTime__c;

        if (newRecord.Status__c == 'Cancelled' && statusChanged) {
            return 'Your appointment with ' + advisorName
                + ' scheduled for ' + formatDateTimeRange(oldRecord.Start_DateTime__c, oldRecord.End_DateTime__c)
                + ' has been cancelled. The related calendar event has been removed.';
        }

        if (newRecord.Status__c == 'Rejected' && statusChanged) {
            String body = 'Your appointment request with ' + advisorName + ' has been rejected.';
            if (String.isNotBlank(newRecord.Rejection_Reason__c)) {
                body += '\nReason: ' + newRecord.Rejection_Reason__c;
            }
            return body;
        }

        if (timeChanged) {
            return 'Your appointment with ' + advisorName
                + ' has been rescheduled to '
                + formatDateTimeRange(newRecord.Start_DateTime__c, newRecord.End_DateTime__c)
                + '. Your calendar event has been updated.';
        }

        return 'Your appointment request with ' + advisorName + ' has been updated.';
    }

    public class ChecklistNotificationRequest {
        @InvocableVariable(required=true label='Checklist Id')
        public String checklistId;
    }
}