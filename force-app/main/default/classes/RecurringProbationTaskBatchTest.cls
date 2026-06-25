/**
 * @description Test class for RecurringProbationTaskBatch and RecurringProbationTaskBatchScheduler
 *
 * Coverage target: 85%+
 * Ticket: ISB-4511
 */
@IsTest
private class RecurringProbationTaskBatchTest {

    // ─── Test Setup ───────────────────────────────────────────────────────────
    @TestSetup
    static void setupTestData() {
        // Create Academic_Probation RecordType (if not exists)
        RecordType probationRT = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Case'
            AND DeveloperName = 'Academic_Probation'
            LIMIT 1
        ];

        // Create test Contact
        Contact testContact = new Contact(
            FirstName = 'Test',
            LastName = 'Student',
            Email = 'test.student@example.com'
        );
        insert testContact;

        // Create test User (portal user)
        Profile portalProfile = [
            SELECT Id FROM Profile
            WHERE Name = 'Customer Community Plus User'
            LIMIT 1
        ];

        User testUser = new User(
            FirstName = 'Test',
            LastName = 'Student',
            Email = 'test.student@example.com',
            Username = 'test.student.' + System.currentTimeMillis() + '@example.com.test',
            Alias = 'tstud',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = portalProfile.Id,
            LanguageLocaleKey = 'en_US',
            ContactId = testContact.Id,
            IsActive = true
        );
        insert testUser;
    }

    // ─── Test 1: Create new task after 14 days when previous completed ────────
    @IsTest
    static void testBatch_createNewTask_after14Days_whenPreviousCompleted() {
        // Setup
        Contact testContact = [SELECT Id FROM Contact LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];
        RecordType probationRT = [SELECT Id FROM RecordType WHERE SObjectType = 'Case' AND DeveloperName = 'Academic_Probation' LIMIT 1];

        Case probationCase = new Case(
            ContactId = testContact.Id,
            RecordTypeId = probationRT.Id,
            Status = 'New',
            Origin = 'Internal',
            Subject = 'Academic Probation Case'
        );
        insert probationCase;

        Task oldTask = new Task(
            Subject = 'Meet Primary Advisor',
            Status = 'Completed',
            Priority = 'High',
            WhatId = probationCase.Id,
            WhoId = testContact.Id,
            OwnerId = testUser.Id,
            ActivityDate = Date.today().addDays(-15)
        );
        insert oldTask;

        // Backdate the task CreatedDate to 15 days ago
        Test.setCreatedDate(oldTask.Id, DateTime.now().addDays(-15));

        // Execute
        Test.startTest();
        Database.executeBatch(new RecurringProbationTaskBatch(), 50);
        Test.stopTest();

        // Assert
        List<Task> allTasks = [
            SELECT Id, Subject, Status, Priority, ActivityDate, OwnerId
            FROM Task
            WHERE WhatId = :probationCase.Id
            AND Subject = 'Meet Primary Advisor'
            ORDER BY CreatedDate DESC
        ];

        System.assertEquals(2, allTasks.size(), 'Should have 2 tasks: original + new recurring task');
        
        Task newTask = allTasks[0]; // Most recent
        System.assertEquals('Not Started', newTask.Status, 'New task should have Status = Not Started');
        System.assertEquals('High', newTask.Priority, 'New task should have Priority = High');
        System.assertEquals(testUser.Id, newTask.OwnerId, 'New task should be owned by student User');
        System.assertEquals(Date.today().addDays(14), newTask.ActivityDate, 'New task ActivityDate should be 14 days from today');
    }

    // ─── Test 2: Skip task when 14 days not passed ────────────────────────────
    @IsTest
    static void testBatch_skipTask_when14DaysNotPassed() {
        // Setup
        Contact testContact = [SELECT Id FROM Contact LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];
        RecordType probationRT = [SELECT Id FROM RecordType WHERE SObjectType = 'Case' AND DeveloperName = 'Academic_Probation' LIMIT 1];

        Case probationCase = new Case(
            ContactId = testContact.Id,
            RecordTypeId = probationRT.Id,
            Status = 'New',
            Origin = 'Internal',
            Subject = 'Academic Probation Case'
        );
        insert probationCase;

        Task recentTask = new Task(
            Subject = 'Meet Primary Advisor',
            Status = 'Completed',
            Priority = 'High',
            WhatId = probationCase.Id,
            WhoId = testContact.Id,
            OwnerId = testUser.Id,
            ActivityDate = Date.today().addDays(-10)
        );
        insert recentTask;

        // Backdate to 10 days ago (less than 14)
        Test.setCreatedDate(recentTask.Id, DateTime.now().addDays(-10));

        // Execute
        Test.startTest();
        Database.executeBatch(new RecurringProbationTaskBatch(), 50);
        Test.stopTest();

        // Assert
        List<Task> allTasks = [
            SELECT Id
            FROM Task
            WHERE WhatId = :probationCase.Id
            AND Subject = 'Meet Primary Advisor'
        ];

        System.assertEquals(1, allTasks.size(), 'Should NOT create new task when 14 days have not passed');
    }

    // ─── Test 3: Skip task when previous not completed ────────────────────────
    @IsTest
    static void testBatch_skipTask_whenPreviousNotCompleted() {
        // Setup
        Contact testContact = [SELECT Id FROM Contact LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];
        RecordType probationRT = [SELECT Id FROM RecordType WHERE SObjectType = 'Case' AND DeveloperName = 'Academic_Probation' LIMIT 1];

        Case probationCase = new Case(
            ContactId = testContact.Id,
            RecordTypeId = probationRT.Id,
            Status = 'New',
            Origin = 'Internal',
            Subject = 'Academic Probation Case'
        );
        insert probationCase;

        Task incompleteTask = new Task(
            Subject = 'Meet Primary Advisor',
            Status = 'Not Started',
            Priority = 'High',
            WhatId = probationCase.Id,
            WhoId = testContact.Id,
            OwnerId = testUser.Id,
            ActivityDate = Date.today().addDays(-20)
        );
        insert incompleteTask;

        // Backdate to 20 days ago
        Test.setCreatedDate(incompleteTask.Id, DateTime.now().addDays(-20));

        // Execute
        Test.startTest();
        Database.executeBatch(new RecurringProbationTaskBatch(), 50);
        Test.stopTest();

        // Assert
        List<Task> allTasks = [
            SELECT Id
            FROM Task
            WHERE WhatId = :probationCase.Id
            AND Subject = 'Meet Primary Advisor'
        ];

        System.assertEquals(1, allTasks.size(), 'Should NOT create new task when previous task is not completed');
    }

    // ─── Test 4: Skip task when Case is closed ────────────────────────────────
    @IsTest
    static void testBatch_skipTask_whenCaseIsClosed() {
        // Setup
        Contact testContact = [SELECT Id FROM Contact LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];
        RecordType probationRT = [SELECT Id FROM RecordType WHERE SObjectType = 'Case' AND DeveloperName = 'Academic_Probation' LIMIT 1];

        Case probationCase = new Case(
            ContactId = testContact.Id,
            RecordTypeId = probationRT.Id,
            Status = 'Closed',
            Origin = 'Internal',
            Subject = 'Academic Probation Case'
        );
        insert probationCase;

        // Close the case
        probationCase.Status = 'Closed';
        update probationCase;

        Task completedTask = new Task(
            Subject = 'Meet Primary Advisor',
            Status = 'Completed',
            Priority = 'High',
            WhatId = probationCase.Id,
            WhoId = testContact.Id,
            OwnerId = testUser.Id,
            ActivityDate = Date.today().addDays(-20)
        );
        insert completedTask;

        Test.setCreatedDate(completedTask.Id, DateTime.now().addDays(-20));

        // Execute
        Test.startTest();
        Database.executeBatch(new RecurringProbationTaskBatch(), 50);
        Test.stopTest();

        // Assert
        List<Task> allTasks = [
            SELECT Id
            FROM Task
            WHERE WhatId = :probationCase.Id
            AND Subject = 'Meet Primary Advisor'
        ];

        System.assertEquals(1, allTasks.size(), 'Should NOT create new task when Case is closed');
    }

    // ─── Test 5: Bulk 50 Cases ────────────────────────────────────────────────
    @IsTest
    static void testBatch_bulk50Cases() {
        // Setup
        Contact testContact = [SELECT Id FROM Contact LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];
        RecordType probationRT = [SELECT Id FROM RecordType WHERE SObjectType = 'Case' AND DeveloperName = 'Academic_Probation' LIMIT 1];

        List<Case> casesToInsert = new List<Case>();
        for (Integer i = 0; i < 50; i++) {
            casesToInsert.add(new Case(
                ContactId = testContact.Id,
                RecordTypeId = probationRT.Id,
                Status = 'New',
                Origin = 'Internal',
                Subject = 'Bulk Probation Case ' + i
            ));
        }
        insert casesToInsert;

        // Create completed tasks for each case (15 days old)
        List<Task> tasksToInsert = new List<Task>();
        for (Case c : casesToInsert) {
            tasksToInsert.add(new Task(
                Subject = 'Meet Primary Advisor',
                Status = 'Completed',
                Priority = 'High',
                WhatId = c.Id,
                WhoId = testContact.Id,
                OwnerId = testUser.Id,
                ActivityDate = Date.today().addDays(-15)
            ));
        }
        insert tasksToInsert;

        // Backdate all tasks
        for (Task t : tasksToInsert) {
            Test.setCreatedDate(t.Id, DateTime.now().addDays(-15));
        }

        // Execute
        Test.startTest();
        Database.executeBatch(new RecurringProbationTaskBatch(), 50);
        Test.stopTest();

        // Assert
        List<Task> allTasks = [
            SELECT Id
            FROM Task
            WHERE Subject = 'Meet Primary Advisor'
        ];

        System.assertEquals(100, allTasks.size(), 'Should have 100 tasks: 50 original + 50 recurring');
    }

    // ─── Test 6: Scheduler schedules without exception ────────────────────────
    @IsTest
    static void testScheduler_schedulesWithoutException() {
        // Execute
        Test.startTest();
        String jobId = System.schedule(
            'Test Recurring Probation Task Job',
            '0 0 2 * * ?',
            new RecurringProbationTaskBatchScheduler()
        );
        Test.stopTest();

        // Assert
        System.assertNotEquals(null, jobId, 'Scheduled job ID should not be null');

        CronTrigger ct = [
            SELECT Id, CronExpression, TimesTriggered, NextFireTime
            FROM CronTrigger
            WHERE Id = :jobId
        ];

        System.assertEquals('0 0 2 * * ?', ct.CronExpression, 'Cron expression should match');
    }

    // ─── Test 7: Scheduler with custom batch size ─────────────────────────────
    @IsTest
    static void testScheduler_withCustomBatchSize() {
        Test.startTest();
        RecurringProbationTaskBatchScheduler scheduler = new RecurringProbationTaskBatchScheduler(100);
        String jobId = System.schedule(
            'Test Probation Scheduler Custom Batch Size',
            '0 0 3 * * ?',
            scheduler
        );
        Test.stopTest();
        
        System.assertNotEquals(null, jobId, 'Scheduler job ID should not be null');
        
        CronTrigger ct = [SELECT Id, CronExpression, State 
                          FROM CronTrigger 
                          WHERE Id = :jobId LIMIT 1];
        System.assertEquals('0 0 3 * * ?', ct.CronExpression, 'Cron expression should match');
    }
}