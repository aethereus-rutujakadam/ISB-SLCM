@isTest
public class MyTasksControllerTest {

    @isTest
    static void testGetTasksForUserSuccess() {
        // Setup: Create test user and tasks
        User testUser = TestDataFactory.testUser('testtask', 'testtask' + Datetime.now().getTime() + '@example.com');
        
        List<Task> testTasks = new List<Task>();
        System.runAs(testUser) {
            testTasks.add(new Task(
                Subject = 'Test Task 1',
                Status = 'Not Started',
                Priority = 'High',
                ActivityDate = Date.today().addDays(1),
                OwnerId = testUser.Id
            ));
            testTasks.add(new Task(
                Subject = 'Test Task 2',
                Status = 'In Progress',
                Priority = 'Normal',
                ActivityDate = Date.today().addDays(2),
                OwnerId = testUser.Id
            ));
            insert testTasks;
        }
        
        Test.startTest();
        System.runAs(testUser) {
            List<Task> results = MyTasksController.getTasksForUser();
            
            System.assertNotEquals(null, results, 'Results should not be null');
            System.assertEquals(2, results.size(), 'Should return 2 tasks');
            System.assertEquals('Test Task 1', results[0].Subject, 'First task should be Test Task 1');
            System.assertEquals('Test Task 2', results[1].Subject, 'Second task should be Test Task 2');
        }
        Test.stopTest();
    }

    @isTest
    static void testGetTasksForUserNoTasks() {
        // Setup: Create test user with no tasks
        User testUser = TestDataFactory.testUser('tempty', 'testempty' + Datetime.now().getTime() + '@example.com');
        
        Test.startTest();
        System.runAs(testUser) {
            List<Task> results = MyTasksController.getTasksForUser();
            
            System.assertNotEquals(null, results, 'Results should not be null');
            System.assertEquals(0, results.size(), 'Should return empty list');
        }
        Test.stopTest();
    }

    @isTest
    static void testGetTasksForUserOrderedByDate() {
        // Setup: Create tasks with different dates
        User testUser = TestDataFactory.testUser('torder', 'testorder' + Datetime.now().getTime() + '@example.com');
        
        List<Task> testTasks = new List<Task>();
        System.runAs(testUser) {
            testTasks.add(new Task(
                Subject = 'Task Due Later',
                Status = 'Not Started',
                ActivityDate = Date.today().addDays(10),
                OwnerId = testUser.Id
            ));
            testTasks.add(new Task(
                Subject = 'Task Due Soon',
                Status = 'Not Started',
                ActivityDate = Date.today().addDays(1),
                OwnerId = testUser.Id
            ));
            testTasks.add(new Task(
                Subject = 'Task Due Medium',
                Status = 'Not Started',
                ActivityDate = Date.today().addDays(5),
                OwnerId = testUser.Id
            ));
            insert testTasks;
        }
        
        Test.startTest();
        System.runAs(testUser) {
            List<Task> results = MyTasksController.getTasksForUser();
            
            System.assertEquals(3, results.size(), 'Should return 3 tasks');
            System.assertEquals('Task Due Soon', results[0].Subject, 'First task should be due soonest');
            System.assertEquals('Task Due Medium', results[1].Subject, 'Second task should be due medium');
            System.assertEquals('Task Due Later', results[2].Subject, 'Third task should be due latest');
        }
        Test.stopTest();
    }

    @isTest
    static void testCompleteTaskWithComment() {
        // Setup: Create task
        User testUser = TestDataFactory.testUser('testcomp', 'testcomp' + Datetime.now().getTime() + '@example.com');
        
        Task testTask;
        System.runAs(testUser) {
            testTask = new Task(
                Subject = 'Test Task',
                Status = 'Not Started',
                Priority = 'High',
                OwnerId = testUser.Id
            );
            insert testTask;
        }
        
        Test.startTest();
        System.runAs(testUser) {
            MyTasksController.completeTask(testTask.Id, 'This is a test comment', false);
        }
        Test.stopTest();
        
        Task updatedTask = [SELECT Id, Description, Status FROM Task WHERE Id = :testTask.Id];
        System.assertNotEquals(null, updatedTask.Description, 'Description should not be null');
        System.assert(updatedTask.Description.contains('This is a test comment'), 'Description should contain comment');
        System.assertEquals('Not Started', updatedTask.Status, 'Status should still be Not Started');
    }

    @isTest
    static void testCompleteTaskMarkCompleted() {
        // Setup: Create task
        User testUser = TestDataFactory.testUser('testmark', 'testmark' + Datetime.now().getTime() + '@example.com');
        
        Task testTask;
        System.runAs(testUser) {
            testTask = new Task(
                Subject = 'Test Task',
                Status = 'In Progress',
                Priority = 'High',
                OwnerId = testUser.Id
            );
            insert testTask;
        }
        
        Test.startTest();
        System.runAs(testUser) {
            MyTasksController.completeTask(testTask.Id, 'Task completed', true);
        }
        Test.stopTest();
        
        Task updatedTask = [SELECT Id, Description, Status FROM Task WHERE Id = :testTask.Id];
        System.assertNotEquals(null, updatedTask.Description, 'Description should not be null');
        System.assert(updatedTask.Description.contains('Task completed'), 'Description should contain comment');
        System.assertEquals('Completed', updatedTask.Status, 'Status should be Completed');
    }

    @isTest
    static void testCompleteTaskAppendComment() {
        // Setup: Create task with existing description
        User testUser = TestDataFactory.testUser('tappend', 'testappend' + Datetime.now().getTime() + '@example.com');
        
        Task testTask;
        System.runAs(testUser) {
            testTask = new Task(
                Subject = 'Test Task',
                Status = 'In Progress',
                Description = 'Initial description',
                OwnerId = testUser.Id
            );
            insert testTask;
        }
        
        Test.startTest();
        System.runAs(testUser) {
            MyTasksController.completeTask(testTask.Id, 'Additional comment', false);
        }
        Test.stopTest();
        
        Task updatedTask = [SELECT Id, Description, Status FROM Task WHERE Id = :testTask.Id];
        System.assert(updatedTask.Description.contains('Initial description'), 'Should contain initial description');
        System.assert(updatedTask.Description.contains('Additional comment'), 'Should contain new comment');
    }

    @isTest
    static void testCompleteTaskInvalidId() {
        Test.startTest();
        try {
            MyTasksController.completeTask('00T000000000000AAA', 'Test comment', false);
            System.assert(false, 'Should have thrown exception');
        } catch (Exception e) {
            System.assert(true, 'Exception was thrown as expected');
        }
        Test.stopTest();
    }

    @isTest
    static void testUploadAttachmentSuccess() {
        // Setup: Create task
        User testUser = TestDataFactory.testUser('tupload', 'testupload' + Datetime.now().getTime() + '@example.com');
        
        Task testTask;
        System.runAs(testUser) {
            testTask = new Task(
                Subject = 'Test Task',
                Status = 'Not Started',
                OwnerId = testUser.Id
            );
            insert testTask;
        }
        
        // Create base64 encoded test data
        String testContent = 'This is test file content';
        String base64Data = EncodingUtil.base64Encode(Blob.valueOf(testContent));
        
        Test.startTest();
        Id attachmentId;
        System.runAs(testUser) {
            attachmentId = MyTasksController.uploadAttachment(testTask.Id, 'test.txt', base64Data);
        }
        Test.stopTest();
        
        System.assertNotEquals(null, attachmentId, 'Attachment ID should not be null');
        
        Attachment att = [SELECT Id, Name, ParentId, Body FROM Attachment WHERE Id = :attachmentId];
        System.assertEquals('test.txt', att.Name, 'Attachment name should match');
        System.assertEquals(testTask.Id, att.ParentId, 'Parent ID should match task ID');
        System.assertEquals(testContent, att.Body.toString(), 'Content should match');
    }

    @isTest
    static void testUploadAttachmentLargeFile() {
        // Setup: Create task
        User testUser = TestDataFactory.testUser('tlarge', 'testlarge' + Datetime.now().getTime() + '@example.com');
        
        Task testTask;
        System.runAs(testUser) {
            testTask = new Task(
                Subject = 'Test Task',
                Status = 'Not Started',
                OwnerId = testUser.Id
            );
            insert testTask;
        }
        
        // Create larger base64 encoded test data
        String testContent = 'A'.repeat(1000); // 1000 characters
        String base64Data = EncodingUtil.base64Encode(Blob.valueOf(testContent));
        
        Test.startTest();
        Id attachmentId;
        System.runAs(testUser) {
            attachmentId = MyTasksController.uploadAttachment(testTask.Id, 'large_file.txt', base64Data);
        }
        Test.stopTest();
        
        System.assertNotEquals(null, attachmentId, 'Attachment ID should not be null');
        
        Attachment att = [SELECT Id, Name, Body FROM Attachment WHERE Id = :attachmentId];
        System.assertEquals('large_file.txt', att.Name, 'Attachment name should match');
        System.assertEquals(1000, att.Body.size(), 'File size should be 1000 bytes');
    }

    @isTest
    static void testUploadAttachmentInvalidTaskId() {
        String base64Data = EncodingUtil.base64Encode(Blob.valueOf('test'));
        
        Test.startTest();
        try {
            MyTasksController.uploadAttachment('00T000000000000AAA', 'test.txt', base64Data);
            System.assert(false, 'Should have thrown exception');
        } catch (Exception e) {
            System.assert(true, 'Exception was thrown as expected');
        }
        Test.stopTest();
    }

    @isTest
    static void testUploadAttachmentNullData() {
        // Setup: Create task
        User testUser = TestDataFactory.testUser('testnull', 'testnull' + Datetime.now().getTime() + '@example.com');
        
        Task testTask;
        System.runAs(testUser) {
            testTask = new Task(
                Subject = 'Test Task',
                Status = 'Not Started',
                OwnerId = testUser.Id
            );
            insert testTask;
        }
        
        Test.startTest();
        try {
            System.runAs(testUser) {
                MyTasksController.uploadAttachment(testTask.Id, 'test.txt', null);
            }
            System.assert(false, 'Should have thrown exception');
        } catch (Exception e) {
            System.assert(true, 'Exception was thrown as expected');
        }
        Test.stopTest();
    }
}