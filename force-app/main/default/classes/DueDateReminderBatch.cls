public class DueDateReminderBatch implements Database.Batchable<SObject>, Database.Stateful {
    
    private Integer emailsSent = 0;
    private Integer notificationsSent = 0;
    @TestVisible private List<String> errorMessages = new List<String>();
    
    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, CaseNumber, Subject, Revised_Due_Date__c, 
                   ContactId, Contact.Name 
            FROM Case 
            WHERE Revised_Due_Date__c != null 
            AND ContactId != null
        ]);
    }
    
    public void execute(Database.BatchableContext bc, List<Case> scope) {
        try {
            // Get related Users who have lookup to these Contacts
            Set<Id> contactIds = new Set<Id>();
            for (Case caseRecord : scope) {
                contactIds.add(caseRecord.ContactId);
            }
            
            // Query Users that have lookup to these Contacts
            Map<Id, User> contactIdToUserMap = new Map<Id, User>();
            for (User usr : [
                SELECT Id, Email, Name, ContactId
                FROM User 
                WHERE ContactId IN :contactIds
                AND IsActive = true
            ]) {
                contactIdToUserMap.put(usr.ContactId, usr);
            }
            
            List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
            
            // Get Custom Notification Type if it exists
            List<CustomNotificationType> notificationTypes = [
                SELECT Id FROM CustomNotificationType 
                WHERE DeveloperName = 'Student_Notification' 
                LIMIT 1
            ];
            
            CustomNotificationType notificationType = notificationTypes.isEmpty() ? null : notificationTypes[0];
            
            for (Case caseRecord : scope) {
                User relatedUser = contactIdToUserMap.get(caseRecord.ContactId);
                
                if (relatedUser != null) {
                    // Send Email
                    emails.add(createReminderEmail(caseRecord, relatedUser));
                    
                    // Send Custom Notification if type exists
                    if (notificationType != null) {
                        try {
                            Messaging.CustomNotification notification = new Messaging.CustomNotification();
                            notification.setBody('T&C acceptance is pending for Case: ' + caseRecord.CaseNumber + '. Due date: ' + caseRecord.Revised_Due_Date__c.format());
                            notification.setTitle('T&C Acceptance Reminder');
                            notification.setSenderId(relatedUser.Id);
                            notification.setNotificationTypeId(notificationType.Id);
                            notification.setTargetId(caseRecord.Id);
                            notification.send(new Set<String>{ relatedUser.Id });
                            notificationsSent++;
                        } catch (Exception e) {
                            errorMessages.add('Error sending notification for Case: ' + caseRecord.CaseNumber + '. Error: ' + e.getMessage());
                        }
                    } else {
                        errorMessages.add('Custom Notification Type not found for Case: ' + caseRecord.CaseNumber);
                    }
                                       
                    emailsSent++;
                }
            }
            
            // Send emails
            if (!emails.isEmpty()) {
                Messaging.SendEmailResult[] results = Messaging.sendEmail(emails);
                
                // Log any failures
                for (Integer i = 0; i < results.size(); i++) {
                    if (!results[i].isSuccess()) {
                        errorMessages.add('Failed to send email for case: ' + scope[i].CaseNumber + 
                                        ' - ' + results[i].getErrors()[0].getMessage());
                    }
                }
            }
            
        } catch (Exception e) {
            errorMessages.add('Execute error: ' + e.getMessage() + ' - ' + e.getStackTraceString());
        }
    }
    
    public void finish(Database.BatchableContext bc) {
        // Send summary email to admin
        sendSummaryEmail();
        
        // Optional: Log results
        System.debug('Batch completed: ' + emailsSent + ' emails sent, ' + 
                    notificationsSent + ' notifications sent');
    }
    
    // Getter methods for testing
    public Integer getEmailsSent() {
        return emailsSent;
    }
    
    public Integer getNotificationsSent() {
        return notificationsSent;
    }
    
    public List<String> getErrorMessages() {
        return errorMessages;
    }
    
    // Public method for creating reminder email (can be tested)
    public Messaging.SingleEmailMessage createReminderEmail(Case caseRecord, User recipientUser) {
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        
        email.setToAddresses(new String[]{recipientUser.Email});
        email.setSubject('Reminder: Case ' + caseRecord.CaseNumber + ' Due Today');
        
        String emailBody = 
            'Hello ' + recipientUser.Name + ',\n\n' +
            'This is a friendly reminder that the T&C is till pending for acceptance:\n\n' +
            'Case Number: ' + caseRecord.CaseNumber + '\n' +
            'Subject: ' + caseRecord.Subject + '\n' +
            'Contact: ' + caseRecord.Contact.Name + '\n' +
            'Due Date: ' + caseRecord.Revised_Due_Date__c.format() + '\n\n' +
            'Please review and take appropriate action.\n\n' +
            'View Case: ' + URL.getOrgDomainUrl().toExternalForm() + '/' + caseRecord.Id + '\n\n' +
            'Thank you!\n';
        
        email.setPlainTextBody(emailBody);
        
        return email;
    }
    
    private void sendSummaryEmail() {
        String subject = 'Revised Due Date Reminders - Batch Completion Summary';
        String body = 
            'The Revised Due Date Reminder batch job has completed.\n\n' +
            'Summary:\n' +
            '- Emails Sent: ' + emailsSent + '\n' +
            '- Notifications Sent: ' + notificationsSent + '\n\n';
        
        if (!errorMessages.isEmpty()) {
            body += 'Errors encountered:\n';
            for (String error : errorMessages) {
                body += '- ' + error + '\n';
            }
        }
        
        // Send to system admin or specific user
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new String[]{UserInfo.getUserEmail()});
        mail.setSubject(subject);
        mail.setPlainTextBody(body);
        
        try {
            Messaging.sendEmail(new Messaging.SingleEmailMessage[]{mail});
        } catch (Exception e) {
            System.debug('Error sending summary email: ' + e.getMessage());
        }
    }
}