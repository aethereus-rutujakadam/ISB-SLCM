/**
 * @description Batch job for sending feedback reminders
 * Reminder 1: After 14 days from trigger date for pending feedback
 * Reminder 2: After 21 days from trigger date for pending feedback
 * Also marks expired feedback past due date
 * Schedule daily: System.schedule('Feedback Reminder Daily', '0 0 8 * * ?', new FeedbackReminderBatch());
 * @author ISB Team
 * @date 2026
 */
global class FeedbackReminderBatch implements Database.Batchable<SObject>, Schedulable {
    
    private static final Integer REMINDER_1_DAYS = 14;
    private static final Integer REMINDER_2_DAYS = 21;
    private static final Integer BATCH_SIZE = 50;
    
    /**
     * @description Schedulable execute - invokes batch
     */
    global void execute(SchedulableContext sc) {
        Database.executeBatch(new FeedbackReminderBatch(), BATCH_SIZE);
    }
    
    /**
     * @description Batch start - query pending feedback needing reminders or expiration
     */
    global Database.QueryLocator start(Database.BatchableContext bc) {
        Date today = Date.today();
        Date reminder1Date = today.addDays(-REMINDER_1_DAYS);
        Date reminder2Date = today.addDays(-REMINDER_2_DAYS);
        
        // Query pending feedback that:
        // 1. Needs Reminder 1 (triggered >= 14 days ago, Reminder1_Sent__c = false)
        // 2. Needs Reminder 2 (triggered >= 21 days ago, Reminder2_Sent__c = false)
        // 3. Past due date (need to mark as Expired)
        return Database.getQueryLocator([
            SELECT Id, Name, Status__c, Feedback_Link_Token__c,
                   Submitter_Contact__c, Submitter_Contact__r.Name, Submitter_Contact__r.Email,
                   Academic_Associate__r.Academic_Associate__r.Name,
                   Course_Offering__r.LearningCourse.Name, Course_Offering__r.Name,
                   Feedback_Template__r.Name,
                   Triggered_Date__c, Due_Date__c,
                   Reminder1_Sent__c, Reminder2_Sent__c
            FROM Feedback__c
            WHERE Status__c = 'Pending'
            AND (
                (Triggered_Date__c <= :reminder1Date AND Reminder1_Sent__c = false)
                OR (Triggered_Date__c <= :reminder2Date AND Reminder2_Sent__c = false)
                OR (Due_Date__c < :today)
            )
        ]);
    }
    
    /**
     * @description Batch execute - process each batch of feedback records
     */
    global void execute(Database.BatchableContext bc, List<Feedback__c> scope) {
        Date today = Date.today();
        Date reminder1Date = today.addDays(-REMINDER_1_DAYS);
        Date reminder2Date = today.addDays(-REMINDER_2_DAYS);
        
        List<Feedback__c> toUpdate = new List<Feedback__c>();
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        String baseUrl = getExperienceCloudBaseUrl();
        
        for (Feedback__c fb : scope) {
            Boolean needsUpdate = false;
            
            // Check if expired
            if (fb.Due_Date__c != null && fb.Due_Date__c < today) {
                fb.Status__c = 'Expired';
                needsUpdate = true;
                // Don't send reminder for expired
                continue;
            }
            
            // Check for Reminder 2 first (takes precedence)
            if (fb.Triggered_Date__c != null && 
                fb.Triggered_Date__c <= reminder2Date && 
                fb.Reminder2_Sent__c != true) {
                
                // Send final reminder
                Messaging.SingleEmailMessage email = buildReminderEmail(fb, baseUrl, 2);
                if (email != null) {
                    emails.add(email);
                }
                fb.Reminder2_Sent__c = true;
                needsUpdate = true;
            }
            // Check for Reminder 1
            else if (fb.Triggered_Date__c != null && 
                     fb.Triggered_Date__c <= reminder1Date && 
                     fb.Reminder1_Sent__c != true) {
                
                // Send first reminder
                Messaging.SingleEmailMessage email = buildReminderEmail(fb, baseUrl, 1);
                if (email != null) {
                    emails.add(email);
                }
                fb.Reminder1_Sent__c = true;
                needsUpdate = true;
            }
            
            if (needsUpdate) {
                toUpdate.add(fb);
            }
        }
        
        // Send emails
        if (!emails.isEmpty()) {
            try {
                Messaging.sendEmail(emails);
            } catch (Exception e) {
                System.debug('Error sending reminder emails: ' + e.getMessage());
            }
        }
        
        // Update records
        if (!toUpdate.isEmpty()) {
            try {
                update toUpdate;
            } catch (Exception e) {
                System.debug('Error updating feedback records: ' + e.getMessage());
            }
        }
    }
    
    /**
     * @description Batch finish - log completion
     */
    global void finish(Database.BatchableContext bc) {
        System.debug('FeedbackReminderBatch completed at ' + DateTime.now());
    }
    
    /**
     * @description Build reminder email
     * @param fb Feedback record
     * @param baseUrl Experience Cloud base URL
     * @param reminderNumber 1 for first reminder, 2 for final reminder
     * @return Email message or null if no valid recipient
     */
    private Messaging.SingleEmailMessage buildReminderEmail(
        Feedback__c fb, 
        String baseUrl, 
        Integer reminderNumber
    ) {
        String recipientEmail = fb.Submitter_Contact__r?.Email;
        if (String.isBlank(recipientEmail)) {
            return null;
        }
        
        String recipientName = fb.Submitter_Contact__r?.Name;
        String aaName = fb.Academic_Associate__r?.Academic_Associate__r?.Name;
        if (String.isBlank(aaName)) {
            aaName = 'Academic Associate';
        }
        
        // Use LearningCourse.Name for course name
        String courseName = '';
        if (fb.Course_Offering__r != null) {
            courseName = fb.Course_Offering__r.LearningCourse != null 
                ? fb.Course_Offering__r.LearningCourse.Name 
                : fb.Course_Offering__r.Name;
        }
        
        String feedbackUrl = baseUrl + '/feedback-form?token=' + fb.Feedback_Link_Token__c;
        
        // Build email body
        String urgencyText = reminderNumber == 2 ? 'FINAL REMINDER: ' : 'Reminder: ';
        String body = '<p>Dear ' + (recipientName != null ? recipientName : 'Respondent') + ',</p>';
        
        if (reminderNumber == 2) {
            body += '<p><strong>This is your final reminder.</strong></p>';
        }
        
        body += '<p>We noticed you have not yet submitted your feedback';
        if (String.isNotBlank(aaName)) {
            body += ' for <strong>' + aaName + '</strong>';
        }
        if (String.isNotBlank(courseName)) {
            body += ' regarding the course <strong>' + courseName + '</strong>';
        }
        body += '.</p>';
        
        body += '<p>Please take a moment to complete your feedback using the link below:</p>';
        body += '<p><a href="' + feedbackUrl + '">Submit Feedback</a></p>';
        
        if (fb.Due_Date__c != null) {
            body += '<p>Please submit your feedback by <strong>' + fb.Due_Date__c.format() + '</strong>.</p>';
        }
        
        body += '<br/>';
        body += '<p>Your feedback is valuable and helps us improve our services.</p>';
        body += '<br/>';
        body += '<p>Best regards,<br/>Office of Academic Services<br/>Indian School of Business</p>';
        
        // Build email
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new List<String>{ recipientEmail });
        email.setSubject(urgencyText + 'Feedback Request' + 
                        (String.isNotBlank(courseName) ? ' - ' + courseName : ''));
        email.setHtmlBody(body);
        email.setSaveAsActivity(false);
        
        return email;
    }
    
    /**
     * @description Get Experience Cloud site base URL
     */
    private String getExperienceCloudBaseUrl() {
        try {
            List<Site> sites = [SELECT Id FROM Site WHERE Status = 'Active' LIMIT 1];
            if (!sites.isEmpty()) {
                SiteDetail sd = [SELECT SecureUrl FROM SiteDetail WHERE DurableId = :sites[0].Id];
                if (sd != null && String.isNotBlank(sd.SecureUrl)) {
                    return sd.SecureUrl;
                }
            }
        } catch (Exception e) {
            System.debug('Could not get Site URL: ' + e.getMessage());
        }
        
        return URL.getOrgDomainUrl().toExternalForm();
    }
    
    /**
     * @description Schedule the batch job for daily execution
     * @param cronExp Cron expression (default: daily at 8 AM)
     * @return Job ID
     */
    public static String scheduleDaily(String cronExp) {
        if (String.isBlank(cronExp)) {
            cronExp = '0 0 8 * * ?'; // 8 AM daily
        }
        return System.schedule('Feedback Reminder Daily', cronExp, new FeedbackReminderBatch());
    }
}