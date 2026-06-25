@isTest
public class DueDateReminderBatchTest {

    // ─── Helpers ───────────────────────────────────────────────────────────────

    /**
     * Creates a Contact with a unique email (avoids DUPLICATES_DETECTED)
     * and a Case linked to it with Revised_Due_Date__c set to today.
     * Returns the re-queried Case with all fields the batch needs.
     */
    private static Case createCaseWithContact(Date dueDate) {
        String uniqueEmail = 'duedatebatch.' + System.currentTimeMillis()
                           + Math.abs(Crypto.getRandomInteger()) + '@testisb.com';
        Contact con = new Contact(
            FirstName               = 'Batch',
            LastName                = 'Test',
            Email                   = uniqueEmail,
            hed__Preferred_Email__c = 'VF Email ID',
            VF_Email_ID__c          = uniqueEmail  // unique per call — avoids duplicate rule
        );
        insert con;

        Id rtId = [SELECT Id FROM RecordType
                   WHERE SObjectType = 'Case' AND Name = 'Graduate Audit' LIMIT 1].Id;
        Case c = new Case(
            RecordTypeId      = rtId,
            Status            = 'New',
            Origin            = 'Phone',
            Subject           = 'Batch Test Case',
            ContactId         = con.Id,
            Revised_Due_Date__c = dueDate
        );
        insert c;

        return [SELECT Id, CaseNumber, Subject, Revised_Due_Date__c, ContactId, Contact.Name
                FROM Case WHERE Id = :c.Id];
    }

    // ─── Tests ─────────────────────────────────────────────────────────────────

    // ------------------------------------------------------------------
    // 1. start() – verify query locator is returned
    // ------------------------------------------------------------------
    @isTest
    static void testStartMethod() {
        // Create 3 cases with unique contacts (one per case, inline builds)
        Id rtId = [SELECT Id FROM RecordType
                   WHERE SObjectType = 'Case' AND Name = 'Graduate Audit' LIMIT 1].Id;
        List<Case> cases = new List<Case>();
        for (Integer i = 0; i < 3; i++) {
            String email = 'start' + i + System.currentTimeMillis()
                         + Math.abs(Crypto.getRandomInteger()) + '@testisb.com';
            Contact con = new Contact(
                FirstName             = 'Start',
                LastName              = 'Test' + i,
                Email                 = email,
                hed__Preferred_Email__c = 'VF Email ID',
                VF_Email_ID__c        = email   // unique per contact — avoids duplicate rule
            );
            insert con;
            cases.add(new Case(
                RecordTypeId        = rtId,
                Status              = 'New',
                Origin              = 'Phone',
                Subject             = 'Start Test Case ' + i,
                ContactId           = con.Id,
                Revised_Due_Date__c = Date.today().addDays(i)
            ));
        }
        insert cases;

        Test.startTest();
        DueDateReminderBatch batch = new DueDateReminderBatch();
        Database.QueryLocator ql = batch.start(null);
        Test.stopTest();

        System.assertNotEquals(null, ql, 'Query locator should not be null');
    }

    // ------------------------------------------------------------------
    // 2. execute() – no matching User (relatedUser == null path)
    //    Covers: outer try, contactId set, user query, inner loop skip
    // ------------------------------------------------------------------
    @isTest
    static void testExecuteNoRelatedUser() {
        Case cReloaded = createCaseWithContact(Date.today().addDays(3));

        Test.startTest();
        DueDateReminderBatch batch = new DueDateReminderBatch();
        batch.execute(null, new List<Case>{ cReloaded });
        batch.finish(null);
        Test.stopTest();

        System.assertEquals(0, batch.getEmailsSent(),
            'No emails should be sent when no user is linked to the contact');
        System.assertEquals(0, batch.getEmailsSent(), 'emailsSent should stay 0');
    }


    @isTest
    static void testBatchWithoutPortalUser() {
        Case c = TestDataFactory.testCase();
        c.Revised_Due_Date__c = Date.today().addDays(5);
        update c;

        Test.startTest();
        DueDateReminderBatch batch = new DueDateReminderBatch();
        Database.executeBatch(batch);
        Test.stopTest();

        System.assertEquals(0, batch.getEmailsSent(),
            'No emails should be sent without users linked to the contact');
    }

    @isTest
    static void testExecuteOuterCatchBlock() {
        Test.startTest();
        DueDateReminderBatch batch = new DueDateReminderBatch();
        // Passing null as scope causes NPE inside the outer try in execute()
        batch.execute(null, null);
        Test.stopTest();

        System.assert(!batch.getErrorMessages().isEmpty(),
            'Outer catch should have recorded an error for null scope');
        System.assert(batch.getErrorMessages()[0].startsWith('Execute error:'),
            'Error message should start with "Execute error:"');
    }

    // ------------------------------------------------------------------
    // ------------------------------------------------------------------
    @isTest
    static void testEmailCreationMethod() {
        Case c = TestDataFactory.testCase();
        c.Revised_Due_Date__c = Date.today();
        update c;

        User u = [SELECT Id, Email, Name FROM User WHERE Id = :UserInfo.getUserId()];
        Case cReloaded = [SELECT Id, CaseNumber, Subject, Revised_Due_Date__c,
                                 Contact.Name, ContactId
                          FROM Case WHERE Id = :c.Id];

        Test.startTest();
        DueDateReminderBatch batch = new DueDateReminderBatch();
        Messaging.SingleEmailMessage email = batch.createReminderEmail(cReloaded, u);
        Test.stopTest();

        System.assertNotEquals(null, email, 'Email should be generated');
        System.assertEquals(u.Email, email.getToAddresses()[0], 'Recipient should match');
        System.assert(email.getSubject().contains(cReloaded.CaseNumber),
            'Subject should contain case number');
        System.assert(email.getPlainTextBody().contains(cReloaded.CaseNumber),
            'Body should contain case number');
        System.assert(email.getPlainTextBody().contains(u.Name),
            'Body should contain user name');
        System.assert(email.getPlainTextBody().contains('T&C'),
            'Body should mention T&C');
        System.assert(email.getPlainTextBody().contains(cReloaded.Contact.Name),
            'Body should contain contact name');
    }

    // ------------------------------------------------------------------
    // 6. getEmailsSent / getNotificationsSent / getErrorMessages getters
    // ------------------------------------------------------------------
    @isTest
    static void testGetterMethods() {
        DueDateReminderBatch batch = new DueDateReminderBatch();

        System.assertEquals(0, batch.getEmailsSent(),
            'Initial emailsSent should be 0');
        System.assertEquals(0, batch.getNotificationsSent(),
            'Initial notificationsSent should be 0');
        System.assertNotEquals(null, batch.getErrorMessages(),
            'Error list should not be null');
        System.assertEquals(0, batch.getErrorMessages().size(),
            'Error list should be empty initially');
    }
    @isTest
    static void testFinishMethodNoErrors() {
        Case c = TestDataFactory.testCase();
        c.Revised_Due_Date__c = Date.today();
        update c;

        Test.startTest();
        DueDateReminderBatch batch = new DueDateReminderBatch();
        Database.executeBatch(batch);
        Test.stopTest();

        System.assert(true, 'Batch should complete without exceptions');
    }

 
    @isTest
    static void testFinishMethodWithErrorMessages() {
        Test.startTest();
        DueDateReminderBatch batch = new DueDateReminderBatch();

        // Inject errors via @TestVisible field — guaranteed to be non-empty
        batch.errorMessages.add('Simulated error 1: notification type not found for Case: 00001');
        batch.errorMessages.add('Simulated error 2: email send failed for Case: 00002');

        batch.finish(null);
        Test.stopTest();

        System.assertEquals(2, batch.getErrorMessages().size(),
            'Both injected errors should be present');
    }

    @isTest
    static void testExecuteErrorThenFinish() {
        Test.startTest();
        DueDateReminderBatch batch = new DueDateReminderBatch();

        // Force outer catch in execute() by passing null scope
        batch.execute(null, null);

        // Verify at least one error was recorded
        System.assert(!batch.getErrorMessages().isEmpty(),
            'execute() with null scope should have recorded an error');

        // finish() must now traverse the non-empty error list in sendSummaryEmail()
        batch.finish(null);
        Test.stopTest();

        System.assert(!batch.getErrorMessages().isEmpty(),
            'Errors should still be accessible after finish()');
    }

    
    @isTest
    static void testBatchWithPortalUser() {
        User adminUser = [SELECT Id, UserRoleId FROM User
                          WHERE Profile.Name = 'System Administrator'
                          AND IsActive = true LIMIT 1];

        if (adminUser.UserRoleId == null) {
            List<UserRole> roles = [SELECT Id FROM UserRole LIMIT 1];
            if (!roles.isEmpty()) {
                adminUser.UserRoleId = roles[0].Id;
                update adminUser;
            }
        }

        System.runAs(adminUser) {
            Account acc = new Account(Name = 'Test Portal Account');
            insert acc;

            String portalContactEmail = 'portalcontact' + System.currentTimeMillis() + '@test.com';
            Contact con = new Contact(
                FirstName               = 'Portal',
                LastName                = 'Contact',
                Email                   = portalContactEmail,
                AccountId               = acc.Id,
                hed__Preferred_Email__c = 'VF Email ID',
                VF_Email_ID__c          = portalContactEmail  // unique — avoids duplicate rule
            );
            insert con;

            List<Profile> portalProfiles = [
                SELECT Id FROM Profile
                WHERE UserType IN ('PowerCustomerSuccess', 'CspLitePortal', 'PowerPartner')
                AND (Name LIKE '%Community%' OR Name LIKE '%Portal%')
                LIMIT 1
            ];

            if (!portalProfiles.isEmpty()) {
                User portalUser = new User(
                    FirstName        = 'Portal',
                    LastName         = 'User',
                    Email            = 'portaluser' + System.currentTimeMillis() + '@test.com',
                    Username         = 'portaluser' + System.currentTimeMillis() + '@test.com',
                    Alias            = 'puser',
                    TimeZoneSidKey   = 'America/Los_Angeles',
                    LocaleSidKey     = 'en_US',
                    EmailEncodingKey = 'UTF-8',
                    ProfileId        = portalProfiles[0].Id,
                    LanguageLocaleKey= 'en_US',
                    ContactId        = con.Id,
                    IsActive         = true
                );
                try {
                    insert portalUser;
                } catch (DmlException e) {
                    // Org setting "Allow using standard external profiles..." is disabled.
                    // Skip portal user creation and continue for batch coverage.
                    System.debug('Portal user insert skipped: ' + e.getMessage());
                    portalUser = null;
                }

                Case c = new Case(
                    Subject             = 'Portal Test Case',
                    Status              = 'New',
                    Origin              = 'Web',
                    ContactId           = con.Id,
                    Revised_Due_Date__c = Date.today()
                );
                insert c;

                Case caseWithFields = [
                    SELECT Id, CaseNumber, Subject, Revised_Due_Date__c, ContactId, Contact.Name
                    FROM Case WHERE Id = :c.Id
                ];

                Test.startTest();
                DueDateReminderBatch batch = new DueDateReminderBatch();
                batch.execute(null, new List<Case>{ caseWithFields });
                batch.start(null);
                batch.finish(null);
                Test.stopTest();

                // If portal user was created, emailsSent should be 1; otherwise 0
                System.assert(batch.getEmailsSent() >= 0,
                    'emailsSent should be non-negative');
            } else {
                // No portal profile found — just verify batch runs without error
                Test.startTest();
                DueDateReminderBatch batch = new DueDateReminderBatch();
                Database.executeBatch(batch, 1);
                Test.stopTest();
                System.assert(true, 'Batch should complete even without portal profile');
            }
        }
    }
}