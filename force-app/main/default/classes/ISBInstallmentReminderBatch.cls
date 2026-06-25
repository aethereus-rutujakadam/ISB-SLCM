global without sharing class ISBInstallmentReminderBatch 
implements Database.Batchable<SObject>, Schedulable {

    // ===========================
    // BATCH START
    // ===========================
    global Database.QueryLocator start(Database.BatchableContext bc) {

        Integer reminderDays = Integer.valueOf(System.Label.ISB_Installment_Reminder_Days);
        Date reminderDate = System.today().addDays(reminderDays);

        return Database.getQueryLocator([
            SELECT Id,
                   Name,
                   Contact__c,
                   Contact__r.Name,
                   Contact__r.New_Admit_Email__c,
                   Program__c,
                   Program__r.Name,
                   Program_Enrollment__c,
                   Program_Enrollment__r.Name,
                   Actual_Amount__c,
                   Pending_Amount__c,
                   Due_Date__c,
                   Extended_Due_Date__c,
                   Installment_Number__c
            FROM ISB_Installment__c
            WHERE Pending_Amount__c > 0
              AND (
                       (Extended_Due_Date__c != null AND Extended_Due_Date__c = :reminderDate)
                    OR (Extended_Due_Date__c = null AND Due_Date__c = :reminderDate)
                  )
              AND Contact__c != null
              AND Contact__r.New_Admit_Email__c!= null
        ]);
    }

    // ===========================
    // BATCH EXECUTE
    // ===========================
    global void execute(Database.BatchableContext bc, List<ISB_Installment__c> scope) {

        if (scope.isEmpty()) {
            System.debug('No records found in scope. Exiting.');
            return;
        }

        // ✅ Fetch Email Templates
        Map<String, Id> templateMap = new Map<String, Id>();

        for (EmailTemplate et : [
            SELECT Id, DeveloperName
            FROM EmailTemplate
            WHERE DeveloperName = 'AMP_Installment_Reminder'
        ]) {
            templateMap.put(et.DeveloperName, et.Id);
        }

        // ✅ Fetch Org-Wide Email Address
        OrgWideEmailAddress orgWide = [
            SELECT Id, DisplayName 
            FROM OrgWideEmailAddress 
            WHERE Address != null 
              AND DisplayName = 'ISB Finance'
            LIMIT 1
        ];

        // ✅ Group Installments by Contact
        Map<Id, List<ISB_Installment__c>> contactToInstMap = new Map<Id, List<ISB_Installment__c>>();

        for (ISB_Installment__c inst : scope) {

            if (inst.Contact__c == null) {
                System.debug('Skipping - Contact is NULL');
                continue;
            }

            if (!contactToInstMap.containsKey(inst.Contact__c)) {
                contactToInstMap.put(inst.Contact__c, new List<ISB_Installment__c>());
            }

            contactToInstMap.get(inst.Contact__c).add(inst);
        }

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        // ✅ Prepare Emails
        for (Id contactId : contactToInstMap.keySet()) {

            List<ISB_Installment__c> installments = contactToInstMap.get(contactId);

            if (installments.isEmpty()) {
                System.debug('Skipping contact ' + contactId + ' - No installments');
                continue;
            }

            ISB_Installment__c inst = installments[0];
            Contact con = inst.Contact__r;

            if (con == null) {
                System.debug('Skipping - Contact record NULL');
                continue;
            }

            if (String.isBlank(con.New_Admit_Email__c)) {
                System.debug('Skipping - Email is blank for Contact: ' + con.Id);
                continue;
            }

            // ✅ Template Decision
            String templateName = 'AMP_Installment_Reminder';

            if (inst.Program__r != null && 
                inst.Program__r.Name != null && 
                inst.Program__r.Name.startsWith('Advanced Management Programme')) {

                templateName = 'AMP_Installment_Reminder';
            }

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setTargetObjectId(con.Id);
            mail.setTemplateId(templateMap.get(templateName));
            mail.setOrgWideEmailAddressId(orgWide.Id);
            mail.setSaveAsActivity(false);
            mail.setToAddresses(new String[] { con.New_Admit_Email__c });

            emails.add(mail);
        }

        // ✅ Send Emails
        if (!emails.isEmpty()) {

            Messaging.SendEmailResult[] results = Messaging.sendEmail(emails, false);

            for (Integer i = 0; i < results.size(); i++) {
                if (results[i].isSuccess()) {
                    System.debug('Email Sent Successfully to index: ' + i);
                } else {
                    System.debug('Email Failed at index: ' + i);
                    for (Messaging.SendEmailError err : results[i].getErrors()) {
                        System.debug('Error Message: ' + err.getMessage());
                    }
                }
            }
        } else {
            System.debug('No emails to send.');
        }

        System.debug('=== EXECUTE METHOD END ===');
    }

    // ===========================
    // FINISH
    // ===========================
    global void finish(Database.BatchableContext bc) {
        System.debug('=== FINISH METHOD ===');
        System.debug('ISB Installment Reminder Batch Completed Successfully.');
    }

    // ===========================
    // SCHEDULER
    // ===========================
    global void execute(SchedulableContext sc) {
        Database.executeBatch(new ISBInstallmentReminderBatch(), 200);
    }
}