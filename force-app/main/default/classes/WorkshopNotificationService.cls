/**
 * @description Centralized notification service for Workshop communications.
 *
 *  Responsibilities:
 *    1. Send registration confirmation / waitlist / promotion emails to students
 *       (called from WorkshopRegistrationHandler trigger context via @future)
 *    2. Allow advisors to send custom bulk emails with attachments to all
 *       registered students for a workshop (called from workshopEmailComposer LWC)
 *    3. Send in-app (bell) notifications using Messaging.CustomNotification
 *       (requires "Workshop Notification" CustomNotificationType in the org)
 *
 *  Workshop publish sender: ISB ASA Admin (OrgWideEmailAddress — must exist in Setup)
 *  Other workshop emails continue to use the existing configured sender lookup.
 *  Student email field: Contact.New_Admit_Email__c (falls back to Contact.Email if blank)
 *
 * @author DEVSLCM Team
 * @date 2026
 */
public without sharing class WorkshopNotificationService {

    private static final String ORG_WIDE_EMAIL = 'workshops@yopmail.com';
    private static final String WORKSHOP_PUBLISH_OWEA_NAME = 'ISB ASA Admin';
    private static final String NOTIF_TYPE_NAME = 'Workshop Notification';
    private static final String WORKSHOP_NOTIFICATION_DEVELOPER_NAME = 'Workshop_Notification';
    private static final String FALLBACK_NOTIFICATION_DEVELOPER_NAME = 'Advising_Notification';
    private static final String STUDENT_ADVISING_PAGE_REF = '{"type":"standard__webPage","attributes":{"url":"/ISBStudentSuccessPortal/s/advising"}}';

    // ── Workshop publish entry point ──────────────────────────────────────────────

    /**
     * Called from WorkshopHandler.handleAfterUpdate when a workshop's Status__c
     * transitions to 'Published'.  Emails every active student enrolled in the
     * workshop's Program so they know the workshop is now open for registration.
     *
     * @param workshopIds  IDs of Workshop__c records that were just published
     */
    @future
    public static void sendWorkshopPublishedNotifications(Set<Id> workshopIds) {
         // 1. Load published workshops (need program, name, description, campus, cohort)
        List<Workshop__c> workshops = [
             SELECT Id, Name, Description__c, Program__c, Cohort__c,
                 Campus__c, Campus__r.Name
            FROM Workshop__c
            WHERE Id IN :workshopIds
              AND Program__c != null
        ];

        if (workshops.isEmpty()) return;

        // 2. Collect program IDs; allow multiple workshops per program
        Set<Id> programIds = new Set<Id>();
        Map<Id, List<Workshop__c>> workshopsByProgramId = new Map<Id, List<Workshop__c>>();
        for (Workshop__c w : workshops) {
            programIds.add(w.Program__c);
            if (!workshopsByProgramId.containsKey(w.Program__c)) {
                workshopsByProgramId.put(w.Program__c, new List<Workshop__c>());
            }
            workshopsByProgramId.get(w.Program__c).add(w);
        }

         // 3. Find active program enrollments and match Program + Cohort + Location.
         List<ProgramEnrollment> enrollments = [
             SELECT ContactId,
                 ProgramId,
                 Academic_Term__c,
                 Location__c
             FROM ProgramEnrollment
             WHERE ProgramId IN :programIds
            AND IsActive = true
            AND ContactId != null
        ];

         if (enrollments.isEmpty()) return;

        Id owdId = getPublishOrgWideEmailId();

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        Map<Id, Set<Id>> workshopToContactIds = new Map<Id, Set<Id>>();
        for (Workshop__c workshopRec : workshops) {
            workshopToContactIds.put(workshopRec.Id, new Set<Id>());
        }

        for (ProgramEnrollment pe : enrollments) {
            List<Workshop__c> candidateWorkshops = workshopsByProgramId.get(pe.ProgramId);
            if (candidateWorkshops == null || candidateWorkshops.isEmpty()) {
                continue;
            }

            for (Workshop__c w : candidateWorkshops) {
                // Match cohort with ProgramEnrollment Academic_Term__c.
                if (w.Cohort__c != null && pe.Academic_Term__c != w.Cohort__c) {
                    continue;
                }

                // Match location combination from ProgramEnrollment.Location__c with workshop campus.
                if (w.Campus__c != null && pe.Location__c != w.Campus__c) {
                    continue;
                }

                workshopToContactIds.get(w.Id).add(pe.ContactId);
            }
        }

        Set<Id> allRecipientContactIds = new Set<Id>();
        for (Set<Id> contactIds : workshopToContactIds.values()) {
            allRecipientContactIds.addAll(contactIds);
        }
        if (allRecipientContactIds.isEmpty()) {
            return;
        }

        Map<Id, Contact> contactById = new Map<Id, Contact>([
            SELECT Id, FirstName, Email, New_Admit_Email__c
            FROM Contact
            WHERE Id IN :allRecipientContactIds
        ]);

        for (Workshop__c w : workshops) {
            Set<Id> recipientContactIds = workshopToContactIds.get(w.Id);
            if (recipientContactIds == null || recipientContactIds.isEmpty()) {
                continue;
            }

            for (Id contactId : recipientContactIds) {
                Contact studentContact = contactById.get(contactId);
                if (studentContact == null) {
                    continue;
                }

                String toAddress = String.isNotBlank(studentContact.New_Admit_Email__c)
                    ? studentContact.New_Admit_Email__c
                    : studentContact.Email;

                if (String.isBlank(toAddress)) {
                    continue;
                }

                String firstName = studentContact.FirstName != null ? studentContact.FirstName : 'Student';
                String campusLine = String.isNotBlank(w.Campus__r.Name)
                                   ? 'Campus:   ' + w.Campus__r.Name + '\n'
                                   : '';
                String descLine  = String.isNotBlank(w.Description__c)
                                   ? '\n' + w.Description__c + '\n'
                                   : '';

                String body = 'Dear ' + firstName + ',\n\n'
                    + 'A new workshop has been published and is now open for registration.\n'
                    + descLine + '\n'
                    + 'Workshop: ' + w.Name + '\n'
                    + campusLine
                    + '\nLog in to the Advising Portal to view details and register.\n\n'
                    + 'Regards,\nStudent Success Team';

                Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
                msg.setToAddresses(new List<String>{ toAddress });
                msg.setSubject('New Workshop Available: ' + w.Name);
                msg.setPlainTextBody(body);
                msg.setSaveAsActivity(false);
                if (owdId != null) msg.setOrgWideEmailAddressId(owdId);
                emails.add(msg);
            }
        }

        if (!emails.isEmpty()) {
            try {
                Messaging.sendEmail(emails, false);
            } catch (Exception ex) {
                System.debug('WorkshopNotificationService.sendWorkshopPublishedNotifications: '
                    + ex.getMessage());
            }
        }

        // Send in-app notifications to all eligible students (independent of email availability).
        for (Workshop__c workshopRec : workshops) {
            Set<Id> recipientContactIds = workshopToContactIds.get(workshopRec.Id);
            if (recipientContactIds == null || recipientContactIds.isEmpty()) {
                continue;
            }
            sendInAppNotificationForPublish(recipientContactIds, workshopRec);
        }
    }

    /**
     * @description Sends custom email notification when publishing a workshop via Quick Action.
     *              Called from WorkshopController.publishWorkshopWithEmail.
     *              R4: ISB-6020 - Allows advisors to customize subject and body before publish.
     *              Also sends in-app notifications to students.
     * @param workshopId ID of the Workshop__c record being published
     * @param subject Custom email subject
     * @param body Custom email body
     * @param contentDocIds List of ContentDocument IDs to attach (optional)
     */
    @future
    public static void sendCustomPublishEmail(Id workshopId, String subject, String body, List<String> contentDocIds) {
        if (workshopId == null || String.isBlank(subject) || String.isBlank(body)) {
            return;
        }

        try {
            // Check email governor limit before sending
            if (Limits.getEmailInvocations() >= 5000) {
                System.debug('WorkshopNotificationService.sendCustomPublishEmail: Email limit reached');
                return;
            }

            // Load workshop to get Program, Cohort, and Campus
            List<Workshop__c> workshops = [
                SELECT Id, Name, Program__c, Cohort__c, Campus__c
                FROM Workshop__c
                WHERE Id = :workshopId
                LIMIT 1
            ];

            if (workshops.isEmpty() || workshops[0].Program__c == null) {
                return;
            }

            Workshop__c w = workshops[0];

                        // Select audience by Program + Cohort (AcademicTerm) + Location combination.
                        List<ProgramEnrollment> enrollments = [
                                SELECT ContactId,
                                             Academic_Term__c,
                                             Location__c,
                                             Contact.FirstName,
                                             Contact.Email,
                                             Contact.New_Admit_Email__c
                                FROM ProgramEnrollment
                                WHERE ProgramId = :w.Program__c
                                    AND IsActive = true
                                    AND ContactId != null
            ];

                        if (enrollments.isEmpty()) {
                return;
            }

            Id owdId = getPublishOrgWideEmailId();
            List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

            // Query ContentVersion if attachments provided
            List<ContentVersion> attachments = new List<ContentVersion>();
            if (contentDocIds != null && !contentDocIds.isEmpty()) {
                attachments = [
                    SELECT Id, Title, VersionData, FileType, ContentDocumentId
                    FROM ContentVersion
                    WHERE ContentDocumentId IN :contentDocIds
                    AND IsLatest = true
                    LIMIT 10
                ];
            }

            // Collect Contact IDs for in-app notifications
            Set<Id> contactIds = new Set<Id>();

            Set<Id> seenContactIds = new Set<Id>();
            for (ProgramEnrollment pe : enrollments) {
                if (w.Cohort__c != null && pe.Academic_Term__c != w.Cohort__c) {
                    continue;
                }
                if (w.Campus__c != null && pe.Location__c != w.Campus__c) {
                    continue;
                }

                Id contactId = pe.ContactId;
                if (contactId == null || seenContactIds.contains(contactId)) {
                    continue;
                }
                seenContactIds.add(contactId);
                contactIds.add(contactId);

                String toAddress = String.isNotBlank(pe.Contact.New_Admit_Email__c)
                    ? pe.Contact.New_Admit_Email__c
                    : pe.Contact.Email;

                if (String.isBlank(toAddress)) {
                    continue;
                }

                String firstName = pe.Contact.FirstName != null
                    ? pe.Contact.FirstName
                    : 'Student';
                String emailBody = 'Dear ' + firstName + ',\n\n'
                    + body
                    + '\n\nRegards,\nStudent Success Team';

                Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
                msg.setToAddresses(new List<String>{ toAddress });
                msg.setSubject(subject);
                msg.setPlainTextBody(emailBody);
                msg.setSaveAsActivity(false);
                if (owdId != null) msg.setOrgWideEmailAddressId(owdId);

                // Attach files if provided
                if (!attachments.isEmpty()) {
                    List<Messaging.EmailFileAttachment> emailAttachments = new List<Messaging.EmailFileAttachment>();
                    for (ContentVersion cv : attachments) {
                        Messaging.EmailFileAttachment efa = new Messaging.EmailFileAttachment();
                        efa.setFileName(cv.Title + '.' + cv.FileType);
                        efa.setBody(cv.VersionData);
                        emailAttachments.add(efa);
                    }
                    msg.setFileAttachments(emailAttachments);
                }

                emails.add(msg);
            }

            Integer deliveredCount = 0;
            if (!emails.isEmpty()) {
                Set<Integer> failedIndexes = sendEmailsInBatchesCollectFailures(
                    emails,
                    'sendCustomPublishEmail'
                );

                deliveredCount = emails.size() - failedIndexes.size();
            }

            if (deliveredCount <= 0 && !emails.isEmpty()) {
                System.debug('WorkshopNotificationService.sendCustomPublishEmail: All email deliveries failed.');
                return;
            }

            // Send in-app notifications to students
            sendInAppNotificationForPublish(contactIds, w);

        } catch (Exception ex) {
            System.debug('WorkshopNotificationService.sendCustomPublishEmail error: ' + ex.getMessage());
            System.debug('WorkshopNotificationService.sendCustomPublishEmail stack: ' + ex.getStackTraceString());
        }
    }

    // ── Registration trigger entry points ────────────────────────────────────────

    /**
     * Called from WorkshopRegistrationHandler.handleAfterInsert via @future.
     * Sends confirmation email + in-app notification.
     *
     * @param regIds  IDs of Workshop_Registration__c records just inserted
     */
    @future
    public static void sendRegistrationConfirmations(Set<Id> regIds) {
        List<Workshop_Registration__c> regs = queryRegistrations(regIds);
        sendRegistrationEmails(regs, 'CONFIRM');
        sendInAppForRegistrations(regs, 'CONFIRM');
    }

    /**
     * Called from WorkshopRegistrationHandler when a Waitlisted reg is promoted.
     * Sends "you are now confirmed" email + in-app notification.
     *
     * @param regIds  IDs of promoted Workshop_Registration__c records
     */
    @future
    public static void sendPromotionConfirmations(Set<Id> regIds) {
        List<Workshop_Registration__c> regs = queryRegistrations(regIds);
        sendRegistrationEmails(regs, 'PROMOTE');
        sendInAppForRegistrations(regs, 'PROMOTE');
    }

    // ── Advisor bulk email entry point ───────────────────────────────────────────

    /**
     * AuraEnabled method called by workshopEmailComposer LWC.
     * Sends a custom subject/body email to all active registrants of a workshop.
     * Optionally attaches Salesforce ContentDocument files.
     *
     * @param workshopId     ID of the Workshop__c record
     * @param subject        Email subject (entered by advisor)
     * @param body           Email body text (entered by advisor)
     * @param contentDocIds  List of ContentDocument IDs to attach (may be empty)
     */
    @AuraEnabled
    public static void sendAdvisorEmail(
        Id workshopId,
        String subject,
        String body,
        List<String> contentDocIds
    ) {
        sendAdvisorEmailToAudience(workshopId, subject, body, contentDocIds, 'REGISTERED');
    }

    /**
     * Extended advisor bulk-email method.
     * audience = 'REGISTERED' → send to active registrants only (backward-compatible).
     * audience = 'ALL_ENROLLED' → send to all active ProgramEnrollment contacts matching
     *            the workshop's Program__c (and Cohort__c if set).
     */
    @AuraEnabled
    public static void sendAdvisorEmailToAudience(
        Id workshopId,
        String subject,
        String body,
        List<String> contentDocIds,
        String audience
    ) {
        if (workshopId == null) throw new AuraHandledException('Workshop ID is required.');
        if (String.isBlank(subject)) throw new AuraHandledException('Subject is required.');
        if (String.isBlank(body)) throw new AuraHandledException('Email body is required.');

        String audienceMode = String.isBlank(audience) ? 'REGISTERED' : audience.toUpperCase();

        List<String> toAddresses  = new List<String>();
        List<String> firstNames   = new List<String>();

        if (audienceMode == 'ALL_ENROLLED') {
            // Load workshop to get Program__c, Cohort__c and Campus__c
            List<Workshop__c> workshops = [
                SELECT Id, Name, Program__c, Cohort__c, Campus__c
                FROM Workshop__c
                WHERE Id = :workshopId
                LIMIT 1
            ];
            if (workshops.isEmpty()) {
                throw new AuraHandledException('Workshop not found.');
            }
            Workshop__c ws = workshops[0];
            if (ws.Program__c == null) {
                throw new AuraHandledException('Workshop has no Program assigned — cannot resolve audience.');
            }

            // ProgramEnrollment filters: Cohort(Academic_Term__c) + Location(Location__c).
            List<ProgramEnrollment> enrollments = [
                SELECT ContactId, Academic_Term__c, Location__c,
                       Contact.FirstName, Contact.Email, Contact.New_Admit_Email__c
                FROM ProgramEnrollment
                WHERE ProgramId = :ws.Program__c
                  AND IsActive = true
                  AND ContactId != null
            ];
            if (enrollments.isEmpty()) {
                throw new AuraHandledException('No enrolled students found for this workshop\'s program.');
            }
            for (ProgramEnrollment pe : enrollments) {
                if (ws.Cohort__c != null && pe.Academic_Term__c != ws.Cohort__c) continue;
                if (ws.Campus__c != null && pe.Location__c != ws.Campus__c) continue;
                String addr = String.isNotBlank(pe.Contact.New_Admit_Email__c)
                    ? pe.Contact.New_Admit_Email__c
                    : pe.Contact.Email;
                if (String.isBlank(addr)) continue;
                toAddresses.add(addr);
                firstNames.add(pe.Contact.FirstName != null ? pe.Contact.FirstName : 'Student');
            }
        } else {
            // REGISTERED — original behaviour
            List<Workshop_Registration__c> regs = [
                SELECT Id, Workshop__c, Workshop__r.Name, Batch_Label__c, Status__c,
                       Student__c,
                       Student__r.New_Admit_Email__c, Student__r.Email,
                       Student__r.FirstName
                FROM Workshop_Registration__c
                WHERE Workshop__c = :workshopId
                AND Status__c IN ('Registered', 'Waitlisted')
            ];
            if (regs.isEmpty()) {
                throw new AuraHandledException('No active registrations found for this workshop.');
            }
            for (Workshop_Registration__c reg : regs) {
                String addr = String.isNotBlank(reg.Student__r.New_Admit_Email__c)
                    ? reg.Student__r.New_Admit_Email__c
                    : reg.Student__r.Email;
                if (String.isBlank(addr)) continue;
                toAddresses.add(addr);
                firstNames.add(reg.Student__r.FirstName != null ? reg.Student__r.FirstName : 'Student');
            }
        }

        if (toAddresses.isEmpty()) {
            throw new AuraHandledException('No valid email addresses found for the selected audience.');
        }

        Id owdId = getOrgWideEmailId();

        List<Messaging.EmailFileAttachment> attachments = new List<Messaging.EmailFileAttachment>();
        if (contentDocIds != null && !contentDocIds.isEmpty()) {
            Set<Id> docIdSet = new Set<Id>();
            for (String s : contentDocIds) {
                if (String.isNotBlank(s)) docIdSet.add((Id) s);
            }
            attachments = buildAttachments(docIdSet);
        }

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        for (Integer i = 0; i < toAddresses.size(); i++) {
            Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
            msg.setToAddresses(new List<String>{ toAddresses[i] });
            msg.setSubject(subject);
            msg.setPlainTextBody(
                'Dear ' + firstNames[i] + ',\n\n'
                + body
                + '\n\nRegards,\nStudent Success Team'
            );
            if (owdId != null) msg.setOrgWideEmailAddressId(owdId);
            if (!attachments.isEmpty()) msg.setFileAttachments(attachments);
            emails.add(msg);
        }

        if (!emails.isEmpty()) {
            Messaging.sendEmail(emails, false);
        }
    }

    // ── Private: Registration email logic ────────────────────────────────────────

    private static void sendRegistrationEmails(
        List<Workshop_Registration__c> regs,
        String scenario
    ) {
        if (regs == null || regs.isEmpty()) return;

        Id owdId = getOrgWideEmailId();
        System.debug('WorkshopNotificationService: OrgWideEmailAddressId = ' + owdId);

        // Look up the email template
        String templateName = 'Workshop_Registration_Confirmation';
        EmailTemplate tmpl = getEmailTemplate(templateName);
        System.debug('WorkshopNotificationService: Email Template found = ' + (tmpl != null));

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (Workshop_Registration__c reg : regs) {
            String toAddress = String.isNotBlank(reg.Student__r.New_Admit_Email__c)
                ? reg.Student__r.New_Admit_Email__c
                : reg.Student__r.Email;

            System.debug('WorkshopNotificationService: Student email = ' + toAddress + ', Reg ID = ' + reg.Id);

            if (String.isBlank(toAddress)) {
                System.debug('WorkshopNotificationService: SKIPPING - No email address for student: ' + reg.Student__c);
                continue;
            }

            Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
            msg.setToAddresses(new List<String>{ toAddress });

            if (tmpl != null) {
                msg.setTemplateId(tmpl.Id);
                msg.setTargetObjectId(reg.Student__c); // Contact
                msg.setWhatId(reg.Id);                 // Workshop_Registration__c (merge context)
                msg.setSaveAsActivity(false);
            } else {
                // Fallback plain-text if template not found
                System.debug('WorkshopNotificationService: Using fallback email body');
                String subjectLine = scenario == 'PROMOTE'
                    ? 'You Are Now Confirmed - ' + reg.Workshop__r.Name
                    : 'Registration Confirmed - ' + reg.Workshop__r.Name;

                msg.setSubject(subjectLine);
                msg.setPlainTextBody(buildFallbackBody(reg, scenario));
            }

            if (owdId != null) {
                msg.setOrgWideEmailAddressId(owdId);
            } else {
                System.debug('WorkshopNotificationService: WARNING - OrgWideEmailAddress not configured, using default sender');
            }
            
            emails.add(msg);
        }

        if (!emails.isEmpty()) {
            System.debug('WorkshopNotificationService: Attempting to send ' + emails.size() + ' emails');
            try {
                List<Messaging.SendEmailResult> results = Messaging.sendEmail(emails, false);
                for (Integer i = 0; i < results.size(); i++) {
                    if (results[i].isSuccess()) {
                        System.debug('WorkshopNotificationService: Email ' + i + ' sent successfully');
                    } else {
                        System.debug('WorkshopNotificationService: Email ' + i + ' FAILED: ' + results[i].getErrors()[0].getMessage());
                    }
                }
            } catch (Exception ex) {
                System.debug('WorkshopNotificationService: Email sending exception: ' + ex.getMessage());
            }
        } else {
            System.debug('WorkshopNotificationService: No emails to send');
        }
    }

    // ── Private: In-app notification logic ───────────────────────────────────────

    private static void sendInAppForRegistrations(
        List<Workshop_Registration__c> regs,
        String scenario
    ) {
        if (regs == null || regs.isEmpty()) return;

        Id notifTypeId = resolveWorkshopNotificationTypeId('sendInAppForRegistrations');
        if (notifTypeId == null) {
            return;
        }

        // Map Contact → User for in-app delivery
        Set<Id> studentIds = new Set<Id>();
        for (Workshop_Registration__c reg : regs) {
            if (reg.Student__c != null) studentIds.add(reg.Student__c);
        }

        Map<Id, Id> contactToUser = new Map<Id, Id>();
        for (User u : [SELECT Id, ContactId FROM User WHERE ContactId IN :studentIds AND IsActive = TRUE]) {
            contactToUser.put(u.ContactId, u.Id);
        }

        for (Workshop_Registration__c reg : regs) {
            Id userId = contactToUser.get(reg.Student__c);
            if (userId == null) continue;

            String title = scenario == 'PROMOTE'
                ? 'Workshop Registration Confirmed'
                : (reg.Status__c == 'Waitlisted' ? 'Added to Waitlist' : 'Workshop Registration Confirmed');

            String notifBody = reg.Workshop__r.Name + ' — Batch: ' + reg.Batch_Label__c;

            try {
                Messaging.CustomNotification notif = new Messaging.CustomNotification();
                notif.setTitle(title);
                notif.setBody(notifBody);
                notif.setNotificationTypeId(notifTypeId);
                notif.setTargetPageRef(STUDENT_ADVISING_PAGE_REF);
                notif.send(new Set<String>{ (String) userId });
            } catch (Exception ex) {
                // Log and continue — in-app failure should not break email delivery
                System.debug('WorkshopNotificationService: In-app notification failed for user '
                    + userId + ': ' + ex.getMessage());
            }
        }
    }

    /**
     * @description Sends in-app notifications to students when a workshop is published.
     *              Called from sendCustomPublishEmail.
     * @param contactIds Set of Contact IDs (students) to notify
     * @param workshop Workshop__c record that was published
     */
    private static void sendInAppNotificationForPublish(Set<Id> contactIds, Workshop__c workshop) {
        if (contactIds == null || contactIds.isEmpty() || workshop == null) {
            return;
        }

        try {
            Id notifTypeId = resolveWorkshopNotificationTypeId('sendInAppNotificationForPublish');
            if (notifTypeId == null) {
                return;
            }

            // Map Contact → User for in-app delivery
            Map<Id, Id> contactToUser = new Map<Id, Id>();
            for (User u : [SELECT Id, ContactId FROM User WHERE ContactId IN :contactIds AND IsActive = TRUE]) {
                contactToUser.put(u.ContactId, u.Id);
            }

            // Send notification to each student
            for (Id contactId : contactIds) {
                Id userId = contactToUser.get(contactId);
                if (userId == null) continue;

                try {
                    Messaging.CustomNotification notif = new Messaging.CustomNotification();
                    notif.setTitle('New Workshop Available');
                    notif.setBody(workshop.Name + ' is now open for registration. Log in to the Advising Portal to view details.');
                    notif.setNotificationTypeId(notifTypeId);
                    notif.setTargetPageRef(STUDENT_ADVISING_PAGE_REF);
                    notif.send(new Set<String>{ (String) userId });
                } catch (Exception ex) {
                    System.debug('WorkshopNotificationService: In-app notification failed for user '
                        + userId + ': ' + ex.getMessage());
                }
            }
        } catch (Exception ex) {
            System.debug('WorkshopNotificationService.sendInAppNotificationForPublish error: ' + ex.getMessage());
        }
    }

    // ── Private: Helpers ─────────────────────────────────────────────────────────

    private static List<Workshop_Registration__c> queryRegistrations(Set<Id> regIds) {
        return [
            SELECT Id, Status__c, Batch_Label__c,
                   Workshop__c, Workshop__r.Name, Workshop__r.Campus__r.Name,
                   Student__c,
                   Student__r.FirstName, Student__r.Email, Student__r.New_Admit_Email__c
            FROM Workshop_Registration__c
            WHERE Id IN :regIds
        ];
    }

    private static Id getOrgWideEmailId() {
        List<OrgWideEmailAddress> owdList = [
            SELECT Id, Address FROM OrgWideEmailAddress WHERE Address = :ORG_WIDE_EMAIL LIMIT 1
        ];
        if (owdList.isEmpty()) {
            System.debug('WorkshopNotificationService: OrgWideEmailAddress NOT FOUND for: ' + ORG_WIDE_EMAIL);
            System.debug('WorkshopNotificationService: Please configure OrgWideEmailAddress in Setup');
        } else {
            System.debug('WorkshopNotificationService: OrgWideEmailAddress FOUND: ' + owdList[0].Address);
        }
        return owdList.isEmpty() ? null : owdList[0].Id;
    }

    private static Id getPublishOrgWideEmailId() {
        List<OrgWideEmailAddress> owdList = [
            SELECT Id, DisplayName, Address
            FROM OrgWideEmailAddress
            WHERE DisplayName = :WORKSHOP_PUBLISH_OWEA_NAME
            LIMIT 1
        ];

        if (owdList.isEmpty()) {
            System.debug('WorkshopNotificationService: Publish OrgWideEmailAddress NOT FOUND for display name: ' + WORKSHOP_PUBLISH_OWEA_NAME);
            return null;
        }

        System.debug('WorkshopNotificationService: Publish OrgWideEmailAddress FOUND: ' + owdList[0].DisplayName + ' <' + owdList[0].Address + '>');
        return owdList[0].Id;
    }

    private static EmailTemplate getEmailTemplate(String templateName) {
        List<EmailTemplate> templates = [
            SELECT Id, Name FROM EmailTemplate WHERE Name = :templateName LIMIT 1
        ];
        if (templates.isEmpty()) {
            System.debug('WorkshopNotificationService: Email template NOT FOUND with Name: ' + templateName);
        } else {
            System.debug('WorkshopNotificationService: Email template FOUND: ' + templates[0].Name + ', ID: ' + templates[0].Id);
        }
        return templates.isEmpty() ? null : templates[0];
    }

    private static Set<Integer> sendEmailsInBatchesCollectFailures(
        List<Messaging.SingleEmailMessage> emails,
        String contextName
    ) {
        Set<Integer> failedIndexes = new Set<Integer>();
        if (emails == null || emails.isEmpty()) {
            return failedIndexes;
        }

        Integer startIdx = 0;
        while (startIdx < emails.size()) {
            Integer endExclusive = Math.min(startIdx + 100, emails.size());
            List<Messaging.SingleEmailMessage> batch = new List<Messaging.SingleEmailMessage>();
            for (Integer idx = startIdx; idx < endExclusive; idx++) {
                batch.add(emails[idx]);
            }
            List<Messaging.SendEmailResult> results = Messaging.sendEmail(batch, false);

            for (Integer i = 0; i < results.size(); i++) {
                if (results[i].isSuccess()) {
                    continue;
                }

                failedIndexes.add(startIdx + i);
                String errMessage = 'Unknown email error';
                if (results[i].getErrors() != null && !results[i].getErrors().isEmpty()) {
                    errMessage = results[i].getErrors()[0].getStatusCode() + ' - '
                        + results[i].getErrors()[0].getMessage();
                }

                System.debug('WorkshopNotificationService.' + contextName
                    + ': Email failed at index ' + String.valueOf(startIdx + i)
                    + ' with error: ' + errMessage);
            }

            startIdx = endExclusive;
        }

        return failedIndexes;
    }

    private static List<Messaging.EmailFileAttachment> buildAttachments(Set<Id> contentDocIds) {
        List<Messaging.EmailFileAttachment> attachments = new List<Messaging.EmailFileAttachment>();

        List<ContentVersion> versions = [
            SELECT Title, FileExtension, VersionData, ContentDocumentId
            FROM ContentVersion
            WHERE ContentDocumentId IN :contentDocIds
            AND IsLatest = TRUE
        ];

        for (ContentVersion cv : versions) {
            Messaging.EmailFileAttachment efa = new Messaging.EmailFileAttachment();
            efa.setFileName(cv.Title + '.' + cv.FileExtension);
            efa.setBody(cv.VersionData);
            attachments.add(efa);
        }

        return attachments;
    }

    private static String buildFallbackBody(Workshop_Registration__c reg, String scenario) {
        String greeting = 'Dear ' + (reg.Student__r.FirstName != null ? reg.Student__r.FirstName : 'Student') + ',\n\n';

        String statusLine = scenario == 'PROMOTE'
            ? 'Great news! Your registration for the following workshop has been confirmed.'
            : (reg.Status__c == 'Waitlisted'
                ? 'You have been added to the waitlist for the following workshop.'
                : 'You have successfully registered for the following workshop.');

        return greeting
            + statusLine + '\n\n'
            + 'Workshop: ' + reg.Workshop__r.Name + '\n'
            + 'Batch: ' + reg.Batch_Label__c + '\n'
            + 'Status: ' + reg.Status__c + '\n'
            + (String.isNotBlank(reg.Workshop__r.Campus__r.Name) ? 'Campus: ' + reg.Workshop__r.Campus__r.Name + '\n' : '')
            + '\nPlease log in to the Advising Portal for full session details.\n\n'
            + 'Regards,\nStudent Success Team';
    }

    private static Id resolveWorkshopNotificationTypeId(String contextName) {
        List<CustomNotificationType> types = [
            SELECT Id, DeveloperName
            FROM CustomNotificationType
            WHERE DeveloperName IN :new Set<String>{
                WORKSHOP_NOTIFICATION_DEVELOPER_NAME,
                FALLBACK_NOTIFICATION_DEVELOPER_NAME
            }
            LIMIT 10
        ];

        Id fallbackId;
        for (CustomNotificationType typeRecord : types) {
            if (typeRecord.DeveloperName == WORKSHOP_NOTIFICATION_DEVELOPER_NAME) {
                return typeRecord.Id;
            }
            if (typeRecord.DeveloperName == FALLBACK_NOTIFICATION_DEVELOPER_NAME) {
                fallbackId = typeRecord.Id;
            }
        }

        if (fallbackId != null) {
            System.debug('WorkshopNotificationService: ' + contextName
                + ' using fallback notification type ' + FALLBACK_NOTIFICATION_DEVELOPER_NAME
                + ' because ' + WORKSHOP_NOTIFICATION_DEVELOPER_NAME + ' is missing.');
            return fallbackId;
        }

        System.debug('WorkshopNotificationService: ' + contextName
            + ' missing CustomNotificationType dependency. Expected '
            + WORKSHOP_NOTIFICATION_DEVELOPER_NAME + ' (preferred) or '
            + FALLBACK_NOTIFICATION_DEVELOPER_NAME + ' (fallback).');
        return null;
    }
}