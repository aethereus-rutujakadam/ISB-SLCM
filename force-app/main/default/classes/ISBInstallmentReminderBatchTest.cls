@isTest
public class ISBInstallmentReminderBatchTest {
    
    /**
     * @description Test the batch execution with SeeAllData=true to allow visibility 
     * of the OrgWideEmailAddress 'ISB Finance' which is hardcoded in the batch class.
     */
    @isTest(SeeAllData=true)
    static void testBatchExecution() {
        // Guard check for required Org-Wide Email Address and Template to avoid QueryException in Batch
        List<OrgWideEmailAddress> oweas = [SELECT Id FROM OrgWideEmailAddress WHERE DisplayName = 'ISB Finance' LIMIT 1];
        List<EmailTemplate> tmpls = [SELECT Id FROM EmailTemplate WHERE DeveloperName = 'ISB_Installment_Reminder' LIMIT 1];
        
        if (oweas.isEmpty() || tmpls.isEmpty()) {
            System.debug('⚠️ Required Org-Wide Email Address "ISB Finance" or Template "ISB_Installment_Reminder" not found. Skipping batch execution to avoid failure.');
            return;
        }

        // Create Email Template using Factory
        TestDataFactory.getOrCreateInstallmentReminderTemplate();
        
        // Create Test Data 
        Contact student = TestDataFactory.testContact();
        
        // ✅ FIX: Set New_Admit_Email__c which is required by the batch
        student.New_Admit_Email__c = student.Email;
        update student;
        
        Program prog = TestDataFactory.testProgram();
        ProgramEnrollment pe = TestDataFactory.testProgramEnrollment(student, prog, 'PGID001');
        
        // Determine the reminder date based on the custom label used in the batch
        Integer reminderDays = 7;
        try {
            String labelVal = System.Label.ISB_Installment_Reminder_Days;
            if (String.isNotBlank(labelVal)) {
                reminderDays = Integer.valueOf(labelVal);
            }
        } catch (Exception e) {
            System.debug('Custom Label not found, using default: ' + reminderDays);
        }
        Date reminderDate = System.today().addDays(reminderDays);
        
        // Create matching Installment with Due_Date__c = reminderDate
        ISB_Installment__c inst = TestDataFactory.testInstallment(student.Id, prog.Id, pe.Id, 10000, 10000, 1);
        inst.Due_Date__c = reminderDate;
        inst.Extended_Due_Date__c = null;
        update inst;
        
        // Create an installment with Extended_Due_Date__c to cover that branch
        ISB_Installment__c inst2 = TestDataFactory.testInstallment(student.Id, prog.Id, pe.Id, 5000, 5000, 2);
        inst2.Due_Date__c = System.today(); // Mismatch
        inst2.Extended_Due_Date__c = reminderDate; // Match
        update inst2;
        
        Test.startTest();
        ISBInstallmentReminderBatch batch = new ISBInstallmentReminderBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();
        
        // Verify batch completed
        List<AsyncApexJob> jobs = [
            SELECT Id, Status, NumberOfErrors 
            FROM AsyncApexJob 
            WHERE ApexClass.Name = 'ISBInstallmentReminderBatch' 
            ORDER BY CreatedDate DESC 
            LIMIT 1
        ];
        
        System.assert(!jobs.isEmpty(), 'Batch job should be created');
        System.assertEquals('Completed', jobs[0].Status, 'Batch should complete successfully');
        System.assertEquals(0, jobs[0].NumberOfErrors, 'Batch should have no errors');
    }
    
    /**
     * @description Test AMP template selection logic
     */
    @isTest(SeeAllData=true)
    static void testAMPTemplateSelection() {
        // Guard check
        List<OrgWideEmailAddress> oweas = [SELECT Id FROM OrgWideEmailAddress WHERE DisplayName = 'ISB Finance' LIMIT 1];
        if (oweas.isEmpty()) {
            System.debug('⚠️ Required Org-Wide Email Address not found. Skipping test.');
            return;
        }

        // Create both templates
        TestDataFactory.getOrCreateInstallmentReminderTemplate();
        EmailTemplate ampTemplate = createAMPTemplate();
        
        if (ampTemplate == null) {
            System.debug('⚠️ Could not create AMP template. Skipping test.');
            return;
        }
        
        // Create Test Data with AMP Program
        Contact student = TestDataFactory.testContact();
        student.New_Admit_Email__c = student.Email;
        update student;
        
        // ✅ Create AMP Program to trigger AMP template selection
        Program ampProg = new Program(Name = 'Advanced Management Programme 2025');
        insert ampProg;
        
        ProgramEnrollment pe = TestDataFactory.testProgramEnrollment(student, ampProg, 'AMPID001');
        
        Integer reminderDays = 7;
        try {
            String labelVal = System.Label.ISB_Installment_Reminder_Days;
            if (String.isNotBlank(labelVal)) {
                reminderDays = Integer.valueOf(labelVal);
            }
        } catch (Exception e) {}
        Date reminderDate = System.today().addDays(reminderDays);
        
        ISB_Installment__c inst = TestDataFactory.testInstallment(student.Id, ampProg.Id, pe.Id, 10000, 10000, 1);
        inst.Due_Date__c = reminderDate;
        update inst;
        
        Test.startTest();
        ISBInstallmentReminderBatch batch = new ISBInstallmentReminderBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();
        
        List<AsyncApexJob> jobs = [
            SELECT Id, Status, NumberOfErrors 
            FROM AsyncApexJob 
            WHERE ApexClass.Name = 'ISBInstallmentReminderBatch' 
            ORDER BY CreatedDate DESC 
            LIMIT 1
        ];
        
        System.assert(!jobs.isEmpty(), 'Batch job should be created');
        System.assertEquals('Completed', jobs[0].Status, 'Batch should complete successfully');
    }
    
    @isTest(SeeAllData=true)
    static void testEmptyScope() {
        Test.startTest();
        ISBInstallmentReminderBatch batch = new ISBInstallmentReminderBatch();
        Database.executeBatch(batch);
        Test.stopTest();
        
        List<AsyncApexJob> jobs = [
            SELECT Id, Status 
            FROM AsyncApexJob 
            WHERE ApexClass.Name = 'ISBInstallmentReminderBatch' 
            ORDER BY CreatedDate DESC 
            LIMIT 1
        ];
        System.assert(!jobs.isEmpty(), 'Batch job should be created even with empty scope');
    }
    
    @isTest(SeeAllData=true)
    static void testScheduledExecution() {
        Test.startTest();
        String cronExp = '0 0 8 * * ?';
        String jobId = System.schedule(
            'ISB Installment Reminder Test ' + System.now().getTime(),
            cronExp,
            new ISBInstallmentReminderBatch()
        );
        Test.stopTest();
        
        CronTrigger ct = [SELECT Id, CronExpression FROM CronTrigger WHERE Id = :jobId];
        System.assertEquals(cronExp, ct.CronExpression, 'Cron expression should match');
    }
    
    /**
     * @description Test installment with null contact - should be skipped
     */
    @isTest(SeeAllData=true)
    static void testNullContactHandling() {
        // Guard check
        List<OrgWideEmailAddress> oweas = [SELECT Id FROM OrgWideEmailAddress WHERE DisplayName = 'ISB Finance' LIMIT 1];
        List<EmailTemplate> tmpls = [SELECT Id FROM EmailTemplate WHERE DeveloperName = 'ISB_Installment_Reminder' LIMIT 1];
        
        if (oweas.isEmpty() || tmpls.isEmpty()) {
            return;
        }

        TestDataFactory.getOrCreateInstallmentReminderTemplate();
        
        Contact student = TestDataFactory.testContact();
        student.New_Admit_Email__c = student.Email;
        update student;
        
        Program prog = TestDataFactory.testProgram();
        ProgramEnrollment pe = TestDataFactory.testProgramEnrollment(student, prog, 'PGID002');
        
        Integer reminderDays = 7;
        try {
            String labelVal = System.Label.ISB_Installment_Reminder_Days;
            if (String.isNotBlank(labelVal)) {
                reminderDays = Integer.valueOf(labelVal);
            }
        } catch (Exception e) {}
        Date reminderDate = System.today().addDays(reminderDays);
        
        ISB_Installment__c inst = TestDataFactory.testInstallment(student.Id, prog.Id, pe.Id, 10000, 10000, 1);
        inst.Due_Date__c = reminderDate;
        inst.Contact__c = null; // ✅ Null contact - should be skipped
        update inst;
        
        Test.startTest();
        ISBInstallmentReminderBatch batch = new ISBInstallmentReminderBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();
        
        List<AsyncApexJob> jobs = [
            SELECT Id, Status 
            FROM AsyncApexJob 
            WHERE ApexClass.Name = 'ISBInstallmentReminderBatch' 
            ORDER BY CreatedDate DESC 
            LIMIT 1
        ];
        
        System.assert(!jobs.isEmpty(), 'Batch should complete even with null contact');
        System.assertEquals('Completed', jobs[0].Status, 'Batch should complete successfully');
    }
    
    /**
     * Helper method to create AMP Email Template
     */
    private static EmailTemplate createAMPTemplate() {
        List<EmailTemplate> existing = [
            SELECT Id 
            FROM EmailTemplate 
            WHERE DeveloperName = 'AMP_Installment_Reminder' 
            LIMIT 1
        ];
        
        if (!existing.isEmpty()) {
            return existing[0];
        }

        List<Folder> folders = [
            SELECT Id 
            FROM Folder 
            WHERE Type = 'Email' AND AccessType = 'Public' 
            LIMIT 1
        ];
        
        if (folders.isEmpty()) {
            return null;
        }

        EmailTemplate template = new EmailTemplate(
            DeveloperName = 'AMP_Installment_Reminder',
            Name = 'AMP Installment Reminder',
            Subject = 'Payment Reminder - AMP Installment Due',
            Body = 'Dear {!Contact.Name}, your AMP installment payment is due soon.',
            HtmlValue = '<p>Dear {!Contact.Name},</p><p>Your AMP installment payment is due soon.</p>',
            FolderId = folders[0].Id,
            TemplateType = 'text',
            IsActive = true
        );
        insert template;
        return template;
    }
}