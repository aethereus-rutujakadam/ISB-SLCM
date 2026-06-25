@isTest
private class TaskReminderBatchSchedulerTest {

    /**
     * Test default constructor (batch size = 200)
     */
    @isTest
    static void testDefaultConstructor() {
        Test.startTest();
        
        TaskReminderBatchScheduler scheduler = new TaskReminderBatchScheduler();
        
        // Schedule the job
        String cronExp = '0 0 8 * * ?';
        String jobId = System.schedule('Test Task Reminder Default', cronExp, scheduler);
        
        Test.stopTest();

        // Verify job was scheduled
        CronTrigger ct = [SELECT Id, CronJobDetail.Name 
                          FROM CronTrigger 
                          WHERE Id = :jobId];
        System.assertEquals('Test Task Reminder Default', ct.CronJobDetail.Name);
    }

    /**
     * Test parameterized constructor (custom batch size)
     */
    @isTest
    static void testParameterizedConstructor() {
        Test.startTest();
        
        TaskReminderBatchScheduler scheduler = new TaskReminderBatchScheduler(50);
        
        String cronExp = '0 0 8 * * ?';
        String jobId = System.schedule('Test Task Reminder Custom', cronExp, scheduler);
        
        Test.stopTest();

        CronTrigger ct = [SELECT Id, CronJobDetail.Name 
                          FROM CronTrigger 
                          WHERE Id = :jobId];
        System.assertEquals('Test Task Reminder Custom', ct.CronJobDetail.Name);
    }

    /**
     * Direct execute() method test
     */
    @isTest
    static void testExecuteMethod() {
        Test.startTest();
        
        TaskReminderBatchScheduler scheduler = new TaskReminderBatchScheduler(100);
        
        // Manually invoke execute
        scheduler.execute(null);
        
        Test.stopTest();

        // If no exception occurs, test passes
        System.assert(true, 'Execute method ran successfully');
    }
}