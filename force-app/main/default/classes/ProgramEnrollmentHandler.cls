/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 05-29-2026
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
public with sharing class ProgramEnrollmentHandler {
    
    public static Boolean hasRun = false;
    // F-05 FIX: set true during bulk incoming upload to suppress probation/stamp handlers per row
    public static Boolean isIncomingUpload = false;
    private static Boolean isExecuting = false;
    
    public static void handleBeforeInsert(List<ProgramEnrollment> newList) {
        Set<Id> termIds = new Set<Id>();
        for (ProgramEnrollment pe : newList) {
            if (pe.Academic_Term__c != null && pe.Academic_Year__c == null) {
                termIds.add(pe.Academic_Term__c);
            }
        }
        
        if (!termIds.isEmpty()) {
            Map<Id, AcademicTerm> termMap = new Map<Id, AcademicTerm>([
                SELECT Id, AcademicYearId 
                FROM AcademicTerm 
                WHERE Id IN :termIds
            ]);
            
            for (ProgramEnrollment pe : newList) {
                if (pe.Academic_Term__c != null && pe.Academic_Year__c == null) {
                    AcademicTerm term = termMap.get(pe.Academic_Term__c);
                    if (term != null && term.AcademicYearId != null) {
                        pe.Academic_Year__c = term.AcademicYearId;
                    }
                }
            }
        }
    }
    
    public static void handleAfterInsert(List<ProgramEnrollment> newList) {
        // 1) Collect new enrollments where Status = 'Registered'
        List<ProgramEnrollment> toProcess = new List<ProgramEnrollment>();
        List<ProgramEnrollment> incomingStudents = new List<ProgramEnrollment>();
		Set<Id> programEnrollmentIds =new Set<Id>();
        for (ProgramEnrollment pe : newList) {
            if (pe.Status != null && String.valueOf(pe.Status).equalsIgnoreCase('Registered')) {
                toProcess.add(pe);
            }
            System.debug('Size Of list '+pe.Status);
              System.debug('Size Of list '+pe.Sub_Status__c);
            if (pe.Status == 'Exchange Student' && pe.Sub_Status__c == 'Incoming Exchange' && String.isBlank(pe.PGID__c)) {
                incomingStudents.add(pe);
                programEnrollmentIds.add(pe.Id);
            }
            System.debug('Size Of list '+incomingStudents.size());
        }
        if (!incomingStudents.isEmpty()) {
            System.debug('Size Of incomingStudents.isEmpty()');
            PGIDGeneratorService.generatePGIDs(incomingStudents,programEnrollmentIds);
        }
        
        if (toProcess.isEmpty()) return;
        // 2) Collect student IDs (Contacts)
        Set<Id> studentIds = new Set<Id>();
        for (ProgramEnrollment pe : toProcess) {
            if (pe.ContactId != null) studentIds.add(pe.ContactId);
        }
        if (studentIds.isEmpty()) return;
        
        // 3) Find Clubs of RecordType 'Social_Club' (fallback: Name contains 'Social')
        Id socialRtId;
        try {
            RecordType rt = [
                SELECT Id FROM RecordType
                WHERE SObjectType = 'Club__c'
                AND DeveloperName = 'Social_Club'
                LIMIT 1
            ];
            socialRtId = rt.Id;
        } catch (Exception e) {
            socialRtId = null;
        }
        
        // NOTE: assuming the Club object has a boolean checkbox field Active__c.
        // If your org uses a different field name, change Active__c to the correct API name.
        List<Club__c> socialClubs = new List<Club__c>();
        if (socialRtId != null) {
            socialClubs = [
                SELECT Id, Name, Active__c
                FROM Club__c
                WHERE RecordTypeId = :socialRtId
                AND Active__c = TRUE
            ];
        } else {
            // fallback (useful in lower environments/tests)
            socialClubs = [
                SELECT Id, Name, Active__c
                FROM Club__c
                WHERE Name LIKE '%Social%'
                AND Active__c = TRUE
            ];
        }
        
        if (socialClubs.isEmpty()) return;
        
        Set<Id> clubIds = new Set<Id>();
        for (Club__c c : socialClubs) clubIds.add(c.Id);
        
        // 4) Prevent duplicates: existing memberships for these students & clubs
        Map<String, Club_Membership__c> existingMap = new Map<String, Club_Membership__c>();
        for (Club_Membership__c cm : [
            SELECT Id, Contact__c, Club__c
            FROM Club_Membership__c
            WHERE Contact__c IN :studentIds
            AND Club__c IN :clubIds
        ]) {
            existingMap.put(cm.Contact__c + '|' + cm.Club__c, cm);
        }
        
        // 5) Create new Club_Membership__c records only for active social clubs
        List<Club_Membership__c> toInsert = new List<Club_Membership__c>();
        for (ProgramEnrollment pe : toProcess) {
            if (pe.ContactId == null) continue;            
            
            for (Club__c club : socialClubs) {
                // club.Active__c should be TRUE due to the SOQL filter above,
                // but extra safe-check here (in case someone changes queries later).
                if (club.Active__c == null || club.Active__c == false) continue;
                
                String key = pe.ContactId + '|' + club.Id;
                if (!existingMap.containsKey(key)) {
                    Club_Membership__c cm = new Club_Membership__c();
                    cm.Contact__c = pe.ContactId;
                    cm.Club__c = club.Id;
                    cm.Status__c = 'Active';                    
                    toInsert.add(cm);
                    // keep map updated to prevent duplicates within same transaction
                    existingMap.put(key, cm);
                }
            }
        }
        
        if (!toInsert.isEmpty()) {
            insert toInsert;
        }
    }
 public static void createAcademicProbationCases(
    List<ProgramEnrollment> newList,
    Map<Id, ProgramEnrollment> oldMap
) {
    // ==== CONFIG: tweak as per your org ====
    final Decimal CONTINUANCE_THRESHOLD = 2.0;  // Below 2.0 = Continuance
    final Decimal PROBATION_THRESHOLD = 2.5;  // 2.0 to < 2.5 = Probation
    final Decimal AT_RISK_MAX         = 2.74; // 2.50 to 2.74 = At Risk
    final Decimal MEETS_THRESHOLD     = 2.74; // Above 2.74 = Meets Threshold
    final String  CGPA_FIELD_API      = 'CGPA__c';
    final String  CGPA_STATUS_FIELD   = 'CGPA_Status__c'; // NEW: CGPA Status field
    final String  CASE_RT_DEV_NAME    = 'Academic_Probation';
    final String  PO_QUEUE_DEV_NAME   = 'ASA_Queue';
    final String  CASE_PE_LOOKUP_API  = '';
    final String  CASE_CHECKBOX_FIELD_API = 'ProgramEnrollment__c';
    final String  CASE_CGPA_FIELD_API = 'CGPA__c';
    // =======================================
    
    if (newList == null || newList.isEmpty()) return;
    
    // Separate students into categories
    List<ProgramEnrollment> continuanceStudents = new List<ProgramEnrollment>();
    List<ProgramEnrollment> probationStudents = new List<ProgramEnrollment>();
    List<ProgramEnrollment> atRiskStudents = new List<ProgramEnrollment>();
    List<ProgramEnrollment> improvedStudents = new List<ProgramEnrollment>(); // NEW
    
    for (ProgramEnrollment pe : newList) {
        Decimal newCgpa = getCgpa(pe, CGPA_FIELD_API);
        Decimal oldCgpa = (oldMap != null && oldMap.containsKey(pe.Id))
            ? getCgpa(oldMap.get(pe.Id), CGPA_FIELD_API)
            : null;
        
        // Skip if no CGPA value
        if (newCgpa == null) {
            continue;
        }
        
        // NEW CONDITION: Check if CGPA improved to > 2.74
        if (oldCgpa != null && oldCgpa <= AT_RISK_MAX && newCgpa > MEETS_THRESHOLD) {
            improvedStudents.add(pe);
        }
        // SCENARIO 0: Continuance (CGPA < 2.0)
        else if (newCgpa < CONTINUANCE_THRESHOLD) {
            continuanceStudents.add(pe);
        }
        // SCENARIO 1: Probation (CGPA 2.0 to < 2.5) - SEND PROBATION EMAIL
        else if (newCgpa >= CONTINUANCE_THRESHOLD && newCgpa < PROBATION_THRESHOLD) {
            probationStudents.add(pe);
        }
        // SCENARIO 2: At Risk (CGPA between 2.50-2.74) - SEND AT-RISK EMAIL
        else if (newCgpa >= PROBATION_THRESHOLD && newCgpa <= AT_RISK_MAX) {
            atRiskStudents.add(pe);
        }
    }
    
    // NEW: Process improved students (update CGPA Status to "Meets Threshold")
    if (!improvedStudents.isEmpty()) {
        updateCGPAStatusToMeetsThreshold(improvedStudents, CGPA_STATUS_FIELD);
    }
    
    // Process Probation and Continuance Students (Create Cases + Send Emails)
    List<ProgramEnrollment> casesToCreate = new List<ProgramEnrollment>();
    casesToCreate.addAll(continuanceStudents);
    casesToCreate.addAll(probationStudents);

    if (!casesToCreate.isEmpty()) {
        processProbationCases(casesToCreate, PROBATION_THRESHOLD, CASE_RT_DEV_NAME, 
            PO_QUEUE_DEV_NAME, CASE_PE_LOOKUP_API, CASE_CHECKBOX_FIELD_API, CASE_CGPA_FIELD_API);
    }
    
    if (!continuanceStudents.isEmpty()) {
        sendContinuanceNotificationsAndEmails(continuanceStudents);
    }
    
    if (!probationStudents.isEmpty()) {
        sendProbationNotificationsAndEmails(probationStudents);
    }
    
    // Send notifications for At-Risk Students
    if (!atRiskStudents.isEmpty()) {
        sendAtRiskNotificationsAndEmails(atRiskStudents);
    }
}

// NEW METHOD: Update CGPA Status to "Meets Threshold"
private static void updateCGPAStatusToMeetsThreshold(
    List<ProgramEnrollment> improvedStudents, 
    String cgpaStatusField
) {
    System.debug('✅ Processing ' + improvedStudents.size() + ' students who improved to >2.74');
    
    List<ProgramEnrollment> peToUpdate = new List<ProgramEnrollment>();
    
    for (ProgramEnrollment pe : improvedStudents) {
        ProgramEnrollment peUpdate = new ProgramEnrollment(Id = pe.Id);
        peUpdate.put(cgpaStatusField, 'Meets Threshold');
        peToUpdate.add(peUpdate);
        
        System.debug('✅ Updating PE ' + pe.Id + ' CGPA Status to "Meets Threshold"');
    }
    
    if (!peToUpdate.isEmpty()) {
        try {
            update peToUpdate;
            System.debug('✅ Updated ' + peToUpdate.size() + ' Program Enrollments to "Meets Threshold"');
        } catch (Exception e) {
            System.debug('❌ Error updating CGPA Status: ' + e.getMessage());
        }
    }
}

// UPDATED METHOD: Process probation cases with dynamic field mapping
private static void processProbationCases(
    List<ProgramEnrollment> violators, 
    Decimal threshold, 
    String recordTypeName, 
    String queueName, 
    String lookupApi,
    String checkboxFieldApi,
    String caseCgpaFieldApi
) {
    System.debug('🎯 Processing ' + violators.size() + ' probation students');
    
    if (violators.isEmpty()) return;
    
    // Resolve metadata once
    Id academicProbationRtId = getCaseRecordTypeId(recordTypeName);
    Id poQueueId = getQueueId(queueName);
    // Collect Contacts & PE Ids
    Set<Id> contactIds = new Set<Id>();
    
    for (ProgramEnrollment pe : violators) {
        if (pe.ContactId != null) {
            contactIds.add(pe.ContactId);
        }
    }
    
    // Contacts (for AccountId)
    Map<Id, Contact> contactsById = new Map<Id, Contact>();
    if (!contactIds.isEmpty()) {
        for (Contact c : [
            SELECT Id, AccountId, Name
            FROM Contact
            WHERE Id IN :contactIds
        ]) contactsById.put(c.Id, c);
    }

    // Student users (matched by User.ContactId)
    Map<Id, User> studentUserByContactId = new Map<Id, User>();
    if (!contactIds.isEmpty()) {
        for (User u : [
            SELECT Id, ContactId
            FROM User
            WHERE ContactId IN :contactIds
            AND IsActive = true
            LIMIT 10000
        ]) studentUserByContactId.put(u.ContactId, u);
    }

    Set<Id> violatorIds = new Set<Id>();
    Set<Id> advisorContactIds = new Set<Id>();
    for (ProgramEnrollment pe : violators) {
        violatorIds.add(pe.Id);
        if (pe.Primary_Advisor__c != null) {
            advisorContactIds.add(pe.Primary_Advisor__c);
        }
    }

    Map<Id, Contact> advisorContactsById = advisorContactIds.isEmpty()
        ? new Map<Id, Contact>()
        : new Map<Id, Contact>([
            SELECT Id, Linked_User_Id__c
            FROM Contact
            WHERE Id IN :advisorContactIds
        ]);

    Map<Id, ProgramEnrollment> violatorsById = violatorIds.isEmpty()
        ? new Map<Id, ProgramEnrollment>()
        : new Map<Id, ProgramEnrollment>([
            SELECT Id, Name, ContactId, ProgramId, Primary_Advisor__c, CGPA__c
            FROM ProgramEnrollment
            WHERE Id IN :violatorIds
        ]);
    
    // Avoid duplicates: fetch existing OPEN AP cases by Contact
    Map<Id, Case> openApCaseByContact = new Map<Id, Case>();
    if (!contactIds.isEmpty() && academicProbationRtId != null) {
        for (Case c : [
            SELECT Id, ContactId, IsClosed, RecordTypeId, ProgramEnrollment__c
            FROM Case
            WHERE ContactId IN :contactIds
            AND RecordTypeId = :academicProbationRtId
            AND IsClosed = false
            LIMIT 10000
        ]) {
            if (!openApCaseByContact.containsKey(c.ContactId)) {
                openApCaseByContact.put(c.ContactId, c);
            }
        }
    }
    
    // Build cases to insert (skip if an open AP case already exists for that Contact)
    List<Case> toInsert = new List<Case>();
    List<Id> insertedProgramEnrollmentIds = new List<Id>();
    for (ProgramEnrollment pe : violators) {
        Contact con = contactsById.get(pe.ContactId);
        if (con != null && openApCaseByContact.containsKey(con.Id)) {
            System.debug('⚠️ Skipping case creation - open case exists for contact: ' + con.Name);
            continue;
        }
        
        Case c = new Case();
        c.Subject       = 'Academic Probation - Low CGPA';
        c.Description   = 'CGPA below ' + String.valueOf(threshold) + ' for Program Enrollment ' + (pe.Name);
        c.Origin        = 'Automation';
        c.Status        = 'Submitted';
        if (academicProbationRtId != null) c.RecordTypeId = academicProbationRtId;
        if (poQueueId != null) c.OwnerId = poQueueId;
        
        if (!String.isBlank(checkboxFieldApi)) {
            c.put(checkboxFieldApi, true);
        }
        
        Decimal currentCGPA = getCgpa(pe, 'CGPA__c');
        if (currentCGPA != null && !String.isBlank(caseCgpaFieldApi)) {
            c.put(caseCgpaFieldApi, currentCGPA);
            System.debug('✅ Populated CGPA ' + currentCGPA + ' on new case for contact: ' + con?.Name);
        }
        
        if (pe.ProgramId != null) {
            c.Program__c = pe.ProgramId;
            System.debug('✅ Mapped ProgramId ' + pe.ProgramId + ' from ProgramEnrollment to Case Program__c field');
        }
        
        if (con != null) {
            c.ContactId = con.Id;
            c.AccountId = con.AccountId;
        }

        Contact advisorContact = advisorContactsById.get(pe.Primary_Advisor__c);
        Id advisorUserId = (advisorContact != null && !String.isBlank(advisorContact.Linked_User_Id__c))
            ? (Id) advisorContact.Linked_User_Id__c
            : null;

        if (advisorUserId != null) {
            c.OwnerId = advisorUserId;
        } else if (poQueueId != null) {
            c.OwnerId = poQueueId;
        }
        
        if (!String.isBlank(lookupApi)) {
            c.put(lookupApi, pe.Id);
        }
        
        toInsert.add(c);
        insertedProgramEnrollmentIds.add(pe.Id);
    }
    
    if (!toInsert.isEmpty()) {
        insert toInsert;
        System.debug('✅ Created ' + toInsert.size() + ' probation cases');

        createAdvisorFollowUpTasksAndNotifications(
            toInsert,
            insertedProgramEnrollmentIds,
            violatorsById,
            advisorContactsById,
            studentUserByContactId
        );
    }
}

private static void createAdvisorFollowUpTasksAndNotifications(
    List<Case> insertedCases,
    List<Id> programEnrollmentIds,
    Map<Id, ProgramEnrollment> enrollmentsById,
    Map<Id, Contact> advisorContactsById,
    Map<Id, User> studentUserByContactId
) {
    if (insertedCases.isEmpty() || programEnrollmentIds.isEmpty()) {
        return;
    }

    List<Task> tasksToInsert = new List<Task>();
    Map<Id, Id> caseIdToAdvisorUserId = new Map<Id, Id>();

    Integer limitSize = Math.min(insertedCases.size(), programEnrollmentIds.size());
    for (Integer index = 0; index < limitSize; index++) {
        Case probationCase = insertedCases[index];
        ProgramEnrollment pe = enrollmentsById.get(programEnrollmentIds[index]);
        if (pe == null) {
            continue;
        }

        Task advisorMeetingTask = new Task();
        advisorMeetingTask.Subject = 'Meet Primary Advisor';
        advisorMeetingTask.Status = 'Open';
        advisorMeetingTask.Priority = 'High';
        advisorMeetingTask.Description = 'Student must meet the primary advisor as part of the academic probation follow-up process.';
        advisorMeetingTask.WhatId = probationCase.Id;
        advisorMeetingTask.WhoId = pe.ContactId;
        advisorMeetingTask.ActivityDate = Date.today().addDays(14);
        User studentUser = studentUserByContactId.get(pe.ContactId);
        if (studentUser != null) {
            advisorMeetingTask.OwnerId = studentUser.Id;
        }
        tasksToInsert.add(advisorMeetingTask);

        Contact advisorContact = advisorContactsById.get(pe.Primary_Advisor__c);

        Id advisorUserId = (advisorContact != null && !String.isBlank(advisorContact.Linked_User_Id__c))
            ? (Id) advisorContact.Linked_User_Id__c
            : null;

        if (advisorUserId != null) {
            caseIdToAdvisorUserId.put(probationCase.Id, advisorUserId);
        }
    }

    if (!tasksToInsert.isEmpty()) {
        insert tasksToInsert;
        System.debug('✅ Created ' + tasksToInsert.size() + ' advisor follow-up tasks');
    }

    if (!caseIdToAdvisorUserId.isEmpty()) {
        Map<Id, Case> casesWithNumber = new Map<Id, Case>([
            SELECT Id, CaseNumber FROM Case WHERE Id IN :caseIdToAdvisorUserId.keySet()
        ]);
        List<CustomNotificationType> notifTypes = [
            SELECT Id FROM CustomNotificationType WHERE DeveloperName = 'AA_notification' LIMIT 1
        ];
        if (!notifTypes.isEmpty()) {
            Id notifTypeId = notifTypes[0].Id;
            for (Id caseId : caseIdToAdvisorUserId.keySet()) {
                Case c = casesWithNumber.get(caseId);
                String caseNum = c != null ? c.CaseNumber : '';
                try {
                    Messaging.CustomNotification notif = new Messaging.CustomNotification();
                    notif.setTitle('Academic Probation Case Assigned');
                    notif.setBody('You have been assigned as advisor on Academic Probation case #' + caseNum + '. Please review at the earliest.');
                    notif.setNotificationTypeId(notifTypeId);
                    notif.setTargetId(caseId);
                    notif.send(new Set<String>{ caseIdToAdvisorUserId.get(caseId) });
                } catch (Exception e) {
                    System.debug('⚠️ Advisor notification failed for case ' + caseNum + ': ' + e.getMessage());
                }
            }
        }
    }
}


// EXISTING METHOD: Send Probation Emails
private static void sendProbationNotificationsAndEmails(List<ProgramEnrollment> probationStudents) {
    System.debug('⚠️ Processing ' + probationStudents.size() + ' probation students for emails');
    
    Set<Id> contactIds = new Set<Id>();
    Map<Id, ProgramEnrollment> peByContactId = new Map<Id, ProgramEnrollment>();
    
    for (ProgramEnrollment pe : probationStudents) {
        if (pe.ContactId != null) {
            contactIds.add(pe.ContactId);
            peByContactId.put(pe.ContactId, pe);
        }
    }
    
    if (contactIds.isEmpty()) {
        System.debug('❌ No valid ContactIds for probation students');
        return;
    }
    
    Map<Id, Contact> contactsWithDetails = new Map<Id, Contact>([
        SELECT Id, Email, FirstName, LastName, Name, New_Admit_Email__c 
        FROM Contact 
        WHERE Id IN :contactIds
    ]);
    
    System.debug('⚠️ Found ' + contactsWithDetails.size() + ' contacts with email for probation');
    
    if (contactsWithDetails.isEmpty()) {
        System.debug('❌ No contacts with valid email for probation');
        return;
    }
    
    sendProbationEmails(contactsWithDetails, peByContactId);
    sendProbationPlatformNotifications(contactsWithDetails, peByContactId);
}

// EXISTING METHOD: Send actual Probation Emails
private static void sendProbationEmails(Map<Id, Contact> contactsWithDetails, Map<Id, ProgramEnrollment> peByContactId) {
    List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
    
    OrgWideEmailAddress[] owea = [SELECT Id, Address FROM OrgWideEmailAddress LIMIT 1];
    System.debug('⚠️ Org-Wide Email found for probation: ' + !owea.isEmpty());
    
    List<EmailTemplate> templates = [SELECT Id FROM EmailTemplate WHERE DeveloperName = 'Academic_Progress_Update_Advisory_Meeting_Required' LIMIT 1];
    if (templates.isEmpty()) {
        System.debug('❌ Email Template Academic_Progress_Update_Advisory_Meeting_Required not found');
        return;
    }
    
    Map<Id, ProgramEnrollment> peDetailsMap = new Map<Id, ProgramEnrollment>([
        SELECT Id, Primary_Advisor__r.Name FROM ProgramEnrollment WHERE Id IN :peByContactId.values()
    ]);
    
    for (Contact contact : contactsWithDetails.values()) {
        ProgramEnrollment pe = peByContactId.get(contact.Id);
        
        System.debug('⚠️ Preparing PROBATION email for: ' + contact.Name + ' (' + contact.Email + ')');
        
        Messaging.SingleEmailMessage renderedMail = Messaging.renderStoredEmailTemplate(templates[0].Id, contact.Id, pe.Id);
        String advisorName = peDetailsMap.get(pe.Id)?.Primary_Advisor__r?.Name;
        if (String.isBlank(advisorName)) advisorName = 'Your Academic Advisor';
        
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        
        String htmlBody = renderedMail.getHtmlBody();
        if (htmlBody != null) {
            mail.setHtmlBody(htmlBody.replace('[ADVISOR_NAME]', advisorName));
        }
        
        String textBody = renderedMail.getPlainTextBody();
        if (textBody != null) {
            mail.setPlainTextBody(textBody.replace('[ADVISOR_NAME]', advisorName));
        }
        
        mail.setSubject(renderedMail.getSubject());
        
        if (!owea.isEmpty()) {
            mail.setOrgWideEmailAddressId(owea[0].Id);
        } else {
            mail.setSenderDisplayName('Academic Affairs Office');
        }
        
        mail.setTargetObjectId(contact.Id);
        mail.setWhatId(pe.Id);
        mail.setSaveAsActivity(true);
        if (String.isNotBlank(contact.New_Admit_Email__c)) {
            mail.setToAddresses(new List<String>{ contact.New_Admit_Email__c });
        }
        
        emails.add(mail);
    }
    
    if (!emails.isEmpty()) {
        try {
            System.debug('⚠️ Attempting to send ' + emails.size() + ' PROBATION emails');
            List<Messaging.SendEmailResult> results = Messaging.sendEmail(emails);
            
            Integer successCount = 0;
            for(Messaging.SendEmailResult result : results) {
                if(result.isSuccess()) {
                    successCount++;
                    System.debug('✅ Probation email sent successfully');
                } else {
                    System.debug('❌ Probation email failed: ' + result.getErrors()[0].getMessage());
                }
            }
            System.debug('⚠️ Final result: ' + successCount + '/' + emails.size() + ' probation emails sent successfully');
        } catch (Exception e) {
            System.debug('❌ Error sending probation emails: ' + e.getMessage());
        }
    }
}

// EXISTING METHOD: Send platform notifications for probation
private static void sendProbationPlatformNotifications(Map<Id, Contact> contactsWithDetails, Map<Id, ProgramEnrollment> peByContactId) {
    try {
        List<Task> probationTasks = new List<Task>();
        
        for (Contact contact : contactsWithDetails.values()) {
            ProgramEnrollment pe = peByContactId.get(contact.Id);
            Decimal currentCGPA = getCgpa(pe, 'CGPA__c');
            
            Task task = new Task();
            task.Subject = 'Academic Probation Notification Sent';
            task.Status = 'Completed';
            task.Priority = 'High';
            task.Description = 'Automated PROBATION notification sent to student ' + contact.Name + 
                ' regarding academic probation status. Current CGPA: ' + currentCGPA;
            task.WhoId = contact.Id;
            task.WhatId = pe?.Id;
            task.ActivityDate = Date.today();
            
            probationTasks.add(task);
        }
        
        if (!probationTasks.isEmpty()) {
            insert probationTasks;
            System.debug('✅ Created ' + probationTasks.size() + ' probation notification tasks');
        }
    } catch (Exception e) {
        System.debug('❌ Error creating probation platform notifications: ' + e.getMessage());
    }
}

// EXISTING METHOD: Send both platform notifications AND emails for At-Risk students
private static void sendAtRiskNotificationsAndEmails(List<ProgramEnrollment> atRiskStudents) {
    System.debug('🎯 Processing ' + atRiskStudents.size() + ' at-risk students');
    
    Set<Id> contactIds = new Set<Id>();
    Map<Id, ProgramEnrollment> peByContactId = new Map<Id, ProgramEnrollment>();
    
    for (ProgramEnrollment pe : atRiskStudents) {
        if (pe.ContactId != null) {
            contactIds.add(pe.ContactId);
            peByContactId.put(pe.ContactId, pe);
        }
    }
    
    if (contactIds.isEmpty()) return;
    
    Map<Id, Contact> contactsWithDetails = new Map<Id, Contact>([
        SELECT Id, Email, FirstName, LastName, Name, New_Admit_Email__c 
        FROM Contact 
        WHERE Id IN :contactIds
    ]);
    
    System.debug('📧 Found ' + contactsWithDetails.size() + ' contacts with email addresses');
    
    if (contactsWithDetails.isEmpty()) return;
    
    sendAtRiskEmails(contactsWithDetails, peByContactId);
    sendPlatformNotifications(contactsWithDetails, peByContactId);
}

// EXISTING METHOD: Send email notifications for At-Risk
private static void sendAtRiskEmails(Map<Id, Contact> contactsWithDetails, Map<Id, ProgramEnrollment> peByContactId) {
    List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
    
    OrgWideEmailAddress[] owea = [SELECT Id, Address FROM OrgWideEmailAddress LIMIT 1];
    System.debug('📧 Org-Wide Email found: ' + !owea.isEmpty());
    
    List<EmailTemplate> templates = [SELECT Id FROM EmailTemplate WHERE DeveloperName = 'Academic_Intervention_Advisory_Support' LIMIT 1];
    if (templates.isEmpty()) {
        System.debug('❌ Email Template Academic_Intervention_Advisory_Support not found');
        return;
    }
    
    Map<Id, ProgramEnrollment> peDetailsMap = new Map<Id, ProgramEnrollment>([
        SELECT Id, Primary_Advisor__r.Name FROM ProgramEnrollment WHERE Id IN :peByContactId.values()
    ]);
    
    for (Contact contact : contactsWithDetails.values()) {
        ProgramEnrollment pe = peByContactId.get(contact.Id);
        
        System.debug('📧 Preparing email for: ' + contact.Name + ' (' + contact.Email + ')');
        
        Messaging.SingleEmailMessage renderedMail = Messaging.renderStoredEmailTemplate(templates[0].Id, contact.Id, pe.Id);
        String advisorName = peDetailsMap.get(pe.Id)?.Primary_Advisor__r?.Name;
        if (String.isBlank(advisorName)) advisorName = 'Your Academic Advisor';
        
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        
        String htmlBody = renderedMail.getHtmlBody();
        if (htmlBody != null) {
            mail.setHtmlBody(htmlBody.replace('[ADVISOR_NAME]', advisorName));
        }
        
        String textBody = renderedMail.getPlainTextBody();
        if (textBody != null) {
            mail.setPlainTextBody(textBody.replace('[ADVISOR_NAME]', advisorName));
        }
        
        mail.setSubject(renderedMail.getSubject());
        
        if (!owea.isEmpty()) {
            mail.setOrgWideEmailAddressId(owea[0].Id);
        } else {
            mail.setSenderDisplayName('Academic Affairs Office');
        }
        
        mail.setTargetObjectId(contact.Id);
        mail.setWhatId(pe.Id);
        mail.setSaveAsActivity(true);
        if (String.isNotBlank(contact.New_Admit_Email__c)) {
            mail.setToAddresses(new List<String>{ contact.New_Admit_Email__c });
        }
        
        emails.add(mail);
    }
    
    if (!emails.isEmpty()) {
        try {
            System.debug('📧 Attempting to send ' + emails.size() + ' emails');
            List<Messaging.SendEmailResult> results = Messaging.sendEmail(emails);
            
            Integer successCount = 0;
            for(Messaging.SendEmailResult result : results) {
                if(result.isSuccess()) {
                    successCount++;
                } else {
                    System.debug('❌ Email send failed: ' + result.getErrors()[0].getMessage());
                }
            }
            System.debug('✅ Successfully sent ' + successCount + ' out of ' + emails.size() + ' at-risk notifications');
        } catch (Exception e) {
            System.debug('❌ Error sending at-risk email notifications: ' + e.getMessage());
        }
    }
}

// EXISTING METHOD: Send platform notifications for At-Risk
private static void sendPlatformNotifications(Map<Id, Contact> contactsWithDetails, Map<Id, ProgramEnrollment> peByContactId) {
    try {
        List<Task> notificationTasks = new List<Task>();
        
        for (Contact contact : contactsWithDetails.values()) {
            ProgramEnrollment pe = peByContactId.get(contact.Id);
            Decimal currentCGPA = getCgpa(pe, 'CGPA__c');
            
            Task task = new Task();
            task.Subject = 'At Risk of Probation Notification Sent';
            task.Status = 'Completed';
            task.Priority = 'High';
            task.Description = 'Automated notification sent to student ' + contact.Name + 
                ' regarding at-risk academic status. Current CGPA: ' + currentCGPA;
            task.WhoId = contact.Id;
            task.WhatId = pe?.Id;
            task.ActivityDate = Date.today();
            
            notificationTasks.add(task);
        }
        
        if (!notificationTasks.isEmpty()) {
            insert notificationTasks;
            System.debug('✅ Created ' + notificationTasks.size() + ' notification tasks');
        }
    } catch (Exception e) {
        System.debug('❌ Error creating platform notifications: ' + e.getMessage());
    }
}

// NEW METHOD: Send Continuance Emails and Notifications
private static void sendContinuanceNotificationsAndEmails(List<ProgramEnrollment> continuanceStudents) {
    System.debug('⚠️ Processing ' + continuanceStudents.size() + ' continuance students for emails');
    
    Set<Id> contactIds = new Set<Id>();
    Map<Id, ProgramEnrollment> peByContactId = new Map<Id, ProgramEnrollment>();
    
    for (ProgramEnrollment pe : continuanceStudents) {
        if (pe.ContactId != null) {
            contactIds.add(pe.ContactId);
            peByContactId.put(pe.ContactId, pe);
        }
    }
    
    if (contactIds.isEmpty()) {
        return;
    }
    
    Map<Id, Contact> contactsWithDetails = new Map<Id, Contact>([
        SELECT Id, Email, FirstName, LastName, Name, New_Admit_Email__c 
        FROM Contact 
        WHERE Id IN :contactIds
    ]);
    
    if (contactsWithDetails.isEmpty()) {
        return;
    }
    
    sendContinuanceEmails(contactsWithDetails, peByContactId);
    sendContinuancePlatformNotifications(contactsWithDetails, peByContactId);
}

private static void sendContinuanceEmails(Map<Id, Contact> contactsWithDetails, Map<Id, ProgramEnrollment> peByContactId) {
    List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
    
    OrgWideEmailAddress[] owea = [SELECT Id, Address FROM OrgWideEmailAddress LIMIT 1];
    
    List<EmailTemplate> templates = [SELECT Id FROM EmailTemplate WHERE DeveloperName = 'Academic_Standing_Update_Programme_Continuance' LIMIT 1];
    if (templates.isEmpty()) {
        System.debug('❌ Email Template Academic_Standing_Update_Programme_Continuance not found');
        return;
    }
    
    Map<Id, ProgramEnrollment> peDetailsMap = new Map<Id, ProgramEnrollment>([
        SELECT Id, Primary_Advisor__r.Name FROM ProgramEnrollment WHERE Id IN :peByContactId.values()
    ]);
    
    for (Contact contact : contactsWithDetails.values()) {
        ProgramEnrollment pe = peByContactId.get(contact.Id);
        
        System.debug('⚠️ Preparing CONTINUANCE email for: ' + contact.Name + ' (' + contact.Email + ')');
        
        Messaging.SingleEmailMessage renderedMail = Messaging.renderStoredEmailTemplate(templates[0].Id, contact.Id, pe.Id);
        String advisorName = peDetailsMap.get(pe.Id)?.Primary_Advisor__r?.Name;
        if (String.isBlank(advisorName)) advisorName = 'Your Academic Advisor';
        
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        
        String htmlBody = renderedMail.getHtmlBody();
        if (htmlBody != null) {
            mail.setHtmlBody(htmlBody.replace('[ADVISOR_NAME]', advisorName));
        }
        
        String textBody = renderedMail.getPlainTextBody();
        if (textBody != null) {
            mail.setPlainTextBody(textBody.replace('[ADVISOR_NAME]', advisorName));
        }
        
        mail.setSubject(renderedMail.getSubject());
        
        if (!owea.isEmpty()) {
            mail.setOrgWideEmailAddressId(owea[0].Id);
        } else {
            mail.setSenderDisplayName('Academic Affairs Office');
        }
        
        mail.setTargetObjectId(contact.Id);
        mail.setWhatId(pe.Id);
        mail.setSaveAsActivity(true);
        if (String.isNotBlank(contact.New_Admit_Email__c)) {
            mail.setToAddresses(new List<String>{ contact.New_Admit_Email__c });
        }
        
        emails.add(mail);
    }
    
    if (!emails.isEmpty()) {
        try {
            Messaging.sendEmail(emails);
            System.debug('✅ Continuance emails sent successfully');
        } catch (Exception e) {
            System.debug('❌ Error sending continuance emails: ' + e.getMessage());
        }
    }
}

private static void sendContinuancePlatformNotifications(Map<Id, Contact> contactsWithDetails, Map<Id, ProgramEnrollment> peByContactId) {
    try {
        List<Task> notifTasks = new List<Task>();
        for (Contact contact : contactsWithDetails.values()) {
            ProgramEnrollment pe = peByContactId.get(contact.Id);
            Task task = new Task();
            task.Subject = 'Programme Continuance Notification Sent';
            task.Status = 'Completed';
            task.Priority = 'High';
            task.Description = 'Automated Continuance notification sent to student ' + contact.Name;
            task.WhoId = contact.Id;
            task.WhatId = pe?.Id;
            task.ActivityDate = Date.today();
            notifTasks.add(task);
        }
        if (!notifTasks.isEmpty()) insert notifTasks;
    } catch (Exception e) {}
}

// EXISTING METHOD: Find cases by Contact ID only
public static List<Case> findOpenCasesByContact(Set<Id> contactIds) {
    if (contactIds == null || contactIds.isEmpty()) {
        return new List<Case>();
    }
    
    return [
        SELECT Id, ContactId, ProgramEnrollment__c, CGPA__c, Subject, Status, IsClosed
        FROM Case
        WHERE ContactId IN :contactIds
        AND IsClosed = false
        AND RecordType.DeveloperName = 'Academic_Probation'
        ORDER BY CreatedDate DESC
    ];
}

// EXISTING HELPER METHOD: Get CGPA
private static Decimal getCgpa(SObject pe, String fieldApi) {
    Object v = pe.get(fieldApi);
    return (v instanceof Decimal) ? (Decimal)v : null;
}

// EXISTING HELPER METHOD: Get Case Record Type ID
private static Id getCaseRecordTypeId(String developerName) {
    if (String.isBlank(developerName)) return null;
    List<RecordType> rts = [
        SELECT Id FROM RecordType
        WHERE SObjectType = 'Case' AND DeveloperName = :developerName
        LIMIT 1
    ];
    return rts.isEmpty() ? null : rts[0].Id;
}

// EXISTING HELPER METHOD: Get Queue ID
private static Id getQueueId(String developerName) {
    if (String.isBlank(developerName)) return null;
    List<Group> gs = [
        SELECT Id FROM Group
        WHERE Type = 'Queue' AND DeveloperName = :developerName
        LIMIT 1
    ];
    if (gs.isEmpty()) return null;
    
    List<QueueSobject> qss = [
        SELECT Id FROM QueueSobject
        WHERE QueueId = :gs[0].Id AND SObjectType = 'Case'
        LIMIT 1
    ];
    return qss.isEmpty() ? null : gs[0].Id;
}

    public static void stampCurrentProgramOnContact(
        List<ProgramEnrollment> newList,
        Map<Id, ProgramEnrollment> oldMap
    ) {
        if (newList == null || newList.isEmpty()) {
            return;
        }

        Set<Id> enrollmentIds = new Set<Id>();
        for (ProgramEnrollment pe : newList) {
            if (pe.Id != null) {
                enrollmentIds.add(pe.Id);
            }
        }
        if (enrollmentIds.isEmpty()) {
            return;
        }

        Map<Id, ProgramEnrollment> enrollmentDetailsById = new Map<Id, ProgramEnrollment>([
            SELECT Id, ContactId, Status, ProgramId, Program.Program_Code__c
            FROM ProgramEnrollment
            WHERE Id IN :enrollmentIds
        ]);

        Map<Id, String> contactProgramMap = new Map<Id, String>();
        Boolean isInsertContext = Trigger.isInsert;
        Boolean isUpdateContext = Trigger.isUpdate;

        for (ProgramEnrollment incomingPe : newList) {
            ProgramEnrollment pe = enrollmentDetailsById.get(incomingPe.Id);
            if (pe == null || pe.ContactId == null) {
                continue;
            }

            String programCode = pe.Program != null ? pe.Program.Program_Code__c : null;

            if (isInsertContext && pe.Status == 'Active') {
                contactProgramMap.put(pe.ContactId, programCode);
            }

            if (!isUpdateContext || oldMap == null) {
                continue;
            }

            ProgramEnrollment oldPe = oldMap.get(pe.Id);
            if (oldPe == null) {
                continue;
            }

            Boolean statusChanged = pe.Status != oldPe.Status;
            Boolean programChanged = pe.ProgramId != oldPe.ProgramId;
            Boolean contactChanged = pe.ContactId != oldPe.ContactId;

            if (oldPe.ContactId != null && contactChanged && oldPe.Status == 'Active') {
                contactProgramMap.put(oldPe.ContactId, null);
            }

            if (pe.Status == 'Active' && (statusChanged || programChanged || contactChanged)) {
                contactProgramMap.put(pe.ContactId, programCode);
            } else if (oldPe.Status == 'Active' && pe.Status != 'Active') {
                contactProgramMap.put(pe.ContactId, null);
            }
        }

        if (contactProgramMap.isEmpty()) {
            return;
        }

        List<Contact> contactsToUpdate = new List<Contact>();
        for (Contact existingContact : [
            SELECT Id, Current_Program__c
            FROM Contact
            WHERE Id IN :contactProgramMap.keySet()
        ]) {
            String nextProgram = contactProgramMap.get(existingContact.Id);
            if (existingContact.Current_Program__c == nextProgram) {
                continue;
            }
            existingContact.Current_Program__c = nextProgram;
            contactsToUpdate.add(existingContact);
        }

        if (!contactsToUpdate.isEmpty()) {
            update contactsToUpdate;
        }
    }

   // Static guard so each enrollment's session logic runs at most once per transaction
private static Set<Id> processedSessionUpdates = new Set<Id>();

public static void updateEnrollmentSessionsOnEnrollmentUpdate(List<ProgramEnrollment> updatedEnrollments) {
    // This method currently applies NO field changes (the only mutation is commented out).
    // Running its SOQL on every trigger re-entry during bulk SAP uploads was the source of
    // "Too many SOQL queries: 101". Short-circuit until real logic is re-enabled.
    if (true) {
        return;
    }

    // ---- Re-enable below when session status updates are actually needed ----
    Set<Id> enrollmentIds = new Set<Id>();
    for (ProgramEnrollment pe : updatedEnrollments) {
        if (pe.Id != null && !processedSessionUpdates.contains(pe.Id)) {
            enrollmentIds.add(pe.Id);
            processedSessionUpdates.add(pe.Id);
        }
    }
    if (enrollmentIds.isEmpty()) return;

    List<Enrollment_Session__c> sessionsToConsider = [
        SELECT Id, Status__c, Program_Enrollment__c
        FROM Enrollment_Session__c
        WHERE Program_Enrollment__c IN :enrollmentIds
        AND Status__c != 'LOA'
    ];
    if (sessionsToConsider.isEmpty()) return;

    Map<Id, ProgramEnrollment> enrollmentMap = new Map<Id, ProgramEnrollment>(updatedEnrollments);

    List<Enrollment_Session__c> sessionsToUpdate = new List<Enrollment_Session__c>();
    for (Enrollment_Session__c session : sessionsToConsider) {
        ProgramEnrollment pe = enrollmentMap.get(session.Program_Enrollment__c);
        Boolean isDirty = false;
        if (pe != null) {
            // session.Status__c = 'Completed';
            // isDirty = true;
        }
        if (isDirty) sessionsToUpdate.add(session);
    }

    if (sessionsToUpdate.isEmpty()) return;

    try {
        update sessionsToUpdate;
    } catch (Exception e) {
        System.debug('@@@ updateEnrollmentSessionsOnEnrollmentUpdate ERROR: ' + e.getMessage());
    }
}    
    
    public static void sendGraduationEmails(List<ProgramEnrollment> newList, Map<Id, ProgramEnrollment> oldMap) {

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (ProgramEnrollment pe : newList) {

            ProgramEnrollment oldPe = oldMap.get(pe.Id);

            // Only send when status changes to graduated
            if (oldPe.Status != 'Graduated' && pe.Status == 'Graduated') {

                // Build and send email here only
                Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();

                mail.setTargetObjectId(pe.ContactId);
                mail.setTemplateId('XXXX'); // template
                mail.setSaveAsActivity(false);

                emails.add(mail);
            }
        }

        if (!emails.isEmpty()) {
            Messaging.sendEmail(emails);
        }
    }
    
/*public static void generateInstallments(List<ProgramEnrollment> enrollments) {
    
    //  READ CUSTOM LABEL - Fee types only for Installment 1
    String firstInstallmentOnlyFeesLabel = System.Label.First_Installment_Only_Fee_Types;
    Set<String> firstInstallmentOnlyFees = new Set<String>();
    
    if (String.isNotBlank(firstInstallmentOnlyFeesLabel)) {
        for (String feeType : firstInstallmentOnlyFeesLabel.split(';')) {
            firstInstallmentOnlyFees.add(feeType.trim());
        }
    }
    System.debug(' First Installment Only Fee Types: ' + firstInstallmentOnlyFees);
    
    // Query full Program Enrollment details including Program Name
    Map<Id, ProgramEnrollment> peMap = new Map<Id, ProgramEnrollment>(
        [
            SELECT Id, ContactId, ProgramId,
                   Academic_Term__c,
                   Academic_Term__r.Name,
                   ISB_Fee_Payment_Installments__c,
                   Program.Name,Process_Round_Formula__c 
            FROM ProgramEnrollment
            WHERE Id IN :enrollments
        ]
    );
    enrollments = peMap.values();
    
     Set<Id> contactIds = new Set<Id>();
    for (ProgramEnrollment pe : enrollments) {
        if (pe.ContactId != null) {
            contactIds.add(pe.ContactId);
        }
    }
    
     Map<Id, Contact> contactMap = new Map<Id, Contact>();
    if (!contactIds.isEmpty()) {
        for (Contact c : [
            SELECT Id, Nationality__c
            FROM Contact
            WHERE Id IN :contactIds
        ]) {
            contactMap.put(c.Id, c);
        }
    }

    // Picklist to Number Mapping (for PGP/PGPYL)
    Map<String, Integer> picklistToNumber = new Map<String, Integer>{
        'One Installment' => 1,
        'Two Installments' => 2,
        'Three Installments' => 3,
        'Four Installments' => 4,
        'Five Installments' => 5
    };

    // Query Custom Metadata for Non-PGP/PGPYL Programs
    Map<String, Integer> programInstallmentMap = new Map<String, Integer>();
    for (Program_Installment__mdt meta : [
        SELECT Program__c, No_of_Installments__c
        FROM Program_Installment__mdt
    ]) {
        programInstallmentMap.put(meta.Program__c, Integer.valueOf(meta.No_of_Installments__c));
    }

    List<ISB_Installment__c> installmentList = new List<ISB_Installment__c>();
    List<ISB_Student_Fee_Breakage__c> breakageList = new List<ISB_Student_Fee_Breakage__c>();

    // Collect all Program–Term keys for Fee Master
    Set<String> feeKeys = new Set<String>();
    for (ProgramEnrollment pe : enrollments) {
        feeKeys.add(pe.ProgramId + '-' + pe.Academic_Term__c);
    }

    // Fetch Fee Master Records
    Map<String, List<ISB_Fees_Master__c>> feeMasterMap = new Map<String, List<ISB_Fees_Master__c>>();

    for (ISB_Fees_Master__c fee : [
        SELECT Id, Program__c, Academic_Term__c, Installments__c, Fee_Type__c, Fee_Amount__c
        FROM ISB_Fees_Master__c
        WHERE Program__c != null
    ]) {
        String key = fee.Program__c + '-' + fee.Academic_Term__c;
        if (!feeMasterMap.containsKey(key)) {
            feeMasterMap.put(key, new List<ISB_Fees_Master__c>());
        }
        feeMasterMap.get(key).add(fee);
    }

    // Fetch Installment Master for Due Dates
    Map<String, List<ISB_Installment_Master__c>> installmentMasterMap = new Map<String, List<ISB_Installment_Master__c>>();

    for (ISB_Installment_Master__c im : [
        SELECT Installment_Number__c,Installment_Due_Date_Round_1__c,Installment_Due_Date_Round_2__c,
       Installment_Due_Date_Round_3__c FROM ISB_Installment_Master__c
    ]) {
       // String key = im.Installment_Number__c;
        if (!installmentMasterMap.containsKey(key)) {
            installmentMasterMap.put(key, new List<ISB_Installment_Master__c>());
        }
        //installmentMasterMap.get(key).add(im);
    }

    // MAIN LOOP - CREATE INSTALLMENTS
    for (ProgramEnrollment pe : enrollments) {

        Integer installmentCount;
        String programName = pe.Program.Name;
        String processRound = pe.Process_Round_Formula__c != null? pe.Process_Round_Formula__c.toLowerCase(): '';

        // STEP 1: Determine Installment Count
        if (programName == 'PGP' || programName == 'PGPYL' || programName =='Post Graduate Programme in Management' || programName =='Post Graduate Programme in Management for Young Leaders') {
            installmentCount = picklistToNumber.get(pe.ISB_Fee_Payment_Installments__c);
        } else {
            installmentCount = programInstallmentMap.get(programName);
        }

        if (installmentCount == null || installmentCount <= 0) {
            System.debug('️ No installment count found for PE: ' + pe.Id + ', Program: ' + programName);
            continue;
        }

        System.debug(' Creating ' + installmentCount + ' installments for PE: ' + pe.Id);

        String feeKey = pe.ProgramId + '-' + pe.Academic_Term__c;
        List<ISB_Fees_Master__c> feeList = feeMasterMap.get(feeKey);

        // STEP 2: Calculate amounts separately for first-installment-only and split fees
        Decimal firstInstallmentOnlyTotal = 0;
        Decimal splitAcrossAllTotal = 0;

        if (feeList != null) {
            for (ISB_Fees_Master__c fm : feeList) {
                if (fm.Fee_Amount__c != null) {
                    if (firstInstallmentOnlyFees.contains(fm.Fee_Type__c)) {
                        firstInstallmentOnlyTotal += fm.Fee_Amount__c;
                    } else {
                        splitAcrossAllTotal += fm.Fee_Amount__c;
                    }
                }
            }
        }

        System.debug(' First Installment Only Total: ' + firstInstallmentOnlyTotal);
        System.debug(' Split Across All Total: ' + splitAcrossAllTotal);

        List<ISB_Installment_Master__c> masterList = installmentMasterMap.get(pe.Academic_Term__c);

        // STEP 3: Create Installment Records
        for (Integer i = 1; i <= installmentCount; i++) {

         
            
            Date dueDate;

if (masterList != null) {
    for (ISB_Installment_Master__c m : masterList) {
        if (m.Installment_Number__c == i) {

            if (processRound.contains('round 1') && m.Installment_Due_Date_Round_1__c != null) {
                dueDate = m.Installment_Due_Date_Round_1__c;
            }
            else if (processRound.contains('round 2') && m.Installment_Due_Date_Round_2__c != null) {
                dueDate = m.Installment_Due_Date_Round_2__c;
            }
            else if (processRound.contains('round 3') && m.Installment_Due_Date_Round_3__c != null) {
                dueDate = m.Installment_Due_Date_Round_3__c;
            }
         

            break;
        }
    }
}


            Decimal installmentAmount;
            
            if (i == 1) {
                // First installment = Split fees + First-installment-only fees
                installmentAmount = (splitAcrossAllTotal / installmentCount) + firstInstallmentOnlyTotal;
            } else {
                // Other installments = Only split fees
                installmentAmount = splitAcrossAllTotal / installmentCount;
            }

            ISB_Installment__c inst = new ISB_Installment__c();
            inst.Program_Enrollment__c = pe.Id;
            inst.Contact__c = pe.ContactId;
            inst.Program__c = pe.ProgramId;
            inst.Name = pe.Academic_Term__r.Name + ' - Installment ' + i;
            inst.Installment_Number__c = i;
            inst.Actual_Amount__c = installmentAmount;
            inst.Pending_Amount__c = installmentAmount;
            inst.Due_Date__c = dueDate;
            inst.Last_Installment__c = (i == installmentCount);

            installmentList.add(inst);
        }
    }

    if (!installmentList.isEmpty()) {
        insert installmentList;
        System.debug(' Inserted ' + installmentList.size() + ' installments');
    }

    // STEP 4: Create Fee Breakage Records
    for (ISB_Installment__c inst : installmentList) {

        // Find matching Program Enrollment
        ProgramEnrollment matchedPE;
        for (ProgramEnrollment pe : enrollments) {
            if (pe.Id == inst.Program_Enrollment__c) {
                matchedPE = pe;
                break;
            }
        }
        if (matchedPE == null) continue;
        
        Contact relatedContact = contactMap.get(matchedPE.ContactId);
        Boolean isIndianNationality = false;
        if (relatedContact != null && relatedContact.Nationality__c != null) {
            isIndianNationality = relatedContact.Nationality__c.equalsIgnoreCase('India');
        }

        // Determine installment count for this PE
        Integer installmentCount;
        String programName = matchedPE.Program.Name;
        
        if (programName == 'PGP' || programName == 'PGPYL' || programName == 'Post Graduate Programme in Management' || programName == 'Post Graduate Programme in Management for Young Leaders') {
            installmentCount = picklistToNumber.get(matchedPE.ISB_Fee_Payment_Installments__c);
        } else {
            installmentCount = programInstallmentMap.get(programName);
        }

        if (installmentCount == null || installmentCount <= 0) continue;

        String feeKey = matchedPE.ProgramId + '-' + matchedPE.Academic_Term__c;
        List<ISB_Fees_Master__c> feeList = feeMasterMap.get(feeKey);
System.debug('feeList '+ feeList);
        if (feeList != null) {
            for (ISB_Fees_Master__c fm : feeList) {
                
                Decimal breakageAmount;
                
                //  Check if this fee type is first-installment-only
                if (firstInstallmentOnlyFees.contains(fm.Fee_Type__c)) {
                    
                    // Only add to Installment 1
                    if (inst.Installment_Number__c == 1) {
                        breakageAmount = fm.Fee_Amount__c;  
                    } else {
                        continue;  
                    }
                    
                } else {
                    // Split fee amount across all installments
                    breakageAmount = fm.Fee_Amount__c / installmentCount;
                }

                ISB_Student_Fee_Breakage__c breakage = new ISB_Student_Fee_Breakage__c();
                breakage.ISB_Installment__c = inst.Id;
                breakage.Fee_Type__c = fm.Fee_Type__c;
                breakage.Amount__c = breakageAmount;
                
                breakageList.add(breakage);
            }
        }
        system.debug('breakageList '+breakageList);
       /* if (isIndianNationality) {
            
            // Create CGST Record
            ISB_Student_Fee_Breakage__c cgstBreakage = new ISB_Student_Fee_Breakage__c();
            cgstBreakage.ISB_Installment__c = inst.Id;
            cgstBreakage.Fee_Type__c = 'CGST';
            cgstBreakage.Amount__c = 0;
            breakageList.add(cgstBreakage);
            
            // Create SGST Record
            ISB_Student_Fee_Breakage__c sgstBreakage = new ISB_Student_Fee_Breakage__c();
            sgstBreakage.ISB_Installment__c = inst.Id;
            sgstBreakage.Fee_Type__c = 'SGST';
            sgstBreakage.Amount__c = 0;
            breakageList.add(sgstBreakage);
            
            System.debug(' Created CGST and SGST records for Indian national - Installment: ' + inst.Name);
        }
        
        else {
            
            // IGST for Non-Indian students
            ISB_Student_Fee_Breakage__c igstBreakage = new ISB_Student_Fee_Breakage__c();
            igstBreakage.ISB_Installment__c = inst.Id;
            igstBreakage.Fee_Type__c = 'IGST';
            igstBreakage.Amount__c = 0;
            breakageList.add(igstBreakage);
            
            System.debug('Created IGST for Non-Indian student - ' + inst.Name);
        }
    }

    if (!breakageList.isEmpty()) {
        insert breakageList;
        System.debug(' Inserted ' + breakageList.size() + ' fee breakage records');
    }
}*/

  /*  public static void validateStatusMovement(List<ProgramEnrollment> newList, Map<Id, ProgramEnrollment> oldMap) {
        List<String> errorIds = new List<String>();
        
        try {
            // 1. Fetch rules from the newly named Metadata object
            Map<String, String> movementMap = new Map<String, String>();
            for (Program_Enrollment_Stage_Movement__mdt mdt : [SELECT Previous_Stage__c, Next_Stage__c FROM Program_Enrollment_Stage_Movement__mdt]) {
                movementMap.put(mdt.Previous_Stage__c, mdt.Next_Stage__c);
            }

            for (ProgramEnrollment newProg : newList) {
                String oldStatus = oldMap.get(newProg.Id).Status;
                String newStatus = newProg.Status;

                // Only validate if status has changed and isn't null
                if (newStatus != oldStatus && oldStatus != null) {
                    if (movementMap.containsKey(oldStatus)) {
                        String allowedString = movementMap.get(oldStatus);
                        
                        // Professional approach: Split string into a Set for exact matching
                        Set<String> allowedSet = new Set<String>();
                        if(String.isNotBlank(allowedString)) {
                            for(String s : allowedString.split(',')) {
                                allowedSet.add(s.trim());
                            }
                        }

                        // Check if the new status is in the allowed set
                        if (!allowedSet.contains(newStatus)) {
                            errorIds.add(newProg.Id);
                            newProg.Status.addError('Invalid Movement: You cannot change status from ' + oldStatus + ' to ' + newStatus);
                        }
                    }
                }
            }
        } catch (Exception e) {
            // Using your existing ErrorLogHandler pattern
            // ErrorLogHandler.createLog('ProgramEnrollmentHandler.validateStatusMovement', 'Apex Class', e, String.join(errorIds, ', '), null, null);
            System.debug('Error in Status Validation: ' + e.getMessage());
        }
    }*/


}