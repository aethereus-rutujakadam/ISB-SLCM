global without sharing class ISBFeeReminderBatch
implements Database.Batchable<SObject>, Schedulable {

    // ===========================
    // BATCH START
    // ===========================
    global Database.QueryLocator start(Database.BatchableContext bc) {

        Date reminderDate = System.today().addDays(3);
        System.debug('reminderDate '+reminderDate);

        return Database.getQueryLocator([
            SELECT Id,
                   Due_Date__c,
                   Extended_Due_Date__c,
                   Pending_Amount__c,
                   Fee_Type__c,
                   Program_Enrollment__r.Contact.Name,
                   Program_Enrollment__r.Contact.Email,
                   Program_Enrollment__r.ContactId
            FROM ISB_Fee__c
            WHERE Pending_Amount__c > 0
              AND (
                       (Extended_Due_Date__c != null AND Extended_Due_Date__c = :reminderDate)
                    OR (Extended_Due_Date__c = null AND Due_Date__c = :reminderDate)
                  )
              AND Program_Enrollment__r.ContactId != null
              AND Program_Enrollment__r.Contact.Email != null
        ]);
    }

    // ===========================
    // BATCH EXECUTE
    // ===========================
    global void execute(Database.BatchableContext bc, List<ISB_Fee__c> scope) {

        if (scope.isEmpty()) return;

        // ✅ Fetch Email Template
        EmailTemplate tmpl = [
            SELECT Id
            FROM EmailTemplate
            WHERE DeveloperName = 'ISB_Installment_Reminder'
            LIMIT 1
        ];

        // ✅ Fetch Org-Wide Email Address
        OrgWideEmailAddress orgWide = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE Address != null AND DisplayName = 'ISB Finance'
            LIMIT 1
        ];

        // ✅ Group Fees by ContactId
        Map<Id, List<ISB_Fee__c>> contactToFeeMap = new Map<Id, List<ISB_Fee__c>>();

        for (ISB_Fee__c fee : scope) {
            Id contactId = (fee.Program_Enrollment__r != null) ? fee.Program_Enrollment__r.ContactId : null;
            if (contactId == null) continue;

            if (!contactToFeeMap.containsKey(contactId)) {
                contactToFeeMap.put(contactId, new List<ISB_Fee__c>());
            }
            contactToFeeMap.get(contactId).add(fee);
        }

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        // ✅ Prepare Emails (1 per Contact)
        for (Id contactId : contactToFeeMap.keySet()) {

            List<ISB_Fee__c> fees = contactToFeeMap.get(contactId);
            if (fees == null || fees.isEmpty()) continue;

            // Use first record's relationship to get Contact details
            Contact con = fees[0].Program_Enrollment__r.Contact;
            if (con == null || String.isBlank(con.Email)) continue;

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setTargetObjectId(contactId);
            mail.setTemplateId(tmpl.Id);
            mail.setOrgWideEmailAddressId(orgWide.Id);
            mail.setSaveAsActivity(false);
            // Not required when TargetObjectId is set:
            // mail.setToAddresses(new String[] { con.Email });

            emails.add(mail);
        }

        if (!emails.isEmpty()) {
            Messaging.sendEmail(emails, false);
            system.debug('Email Sent ');
        }
    }

    // ===========================
    // FINISH
    // ===========================
    global void finish(Database.BatchableContext bc) {
        System.debug('✅ ISB Fee Reminder Batch Completed Successfully.');
    }

    // ===========================
    // SCHEDULER
    // ===========================
    global void execute(SchedulableContext sc) {
        Database.executeBatch(new ISBFeeReminderBatch(), 200);
    }
}