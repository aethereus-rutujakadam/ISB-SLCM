@isTest
public class AllotmentCourseOfferingSchedulerTest {

    // ──────────────────────────────────────────────────────
    // Test 1: Schedule via System.schedule (CRON)
    // ──────────────────────────────────────────────────────
    @isTest
    static void testScheduleViaCron() {
        Test.startTest();
        String cronExp = '0 0 18 * * ?';
        String jobId = System.schedule(
            'Test Allotment Sync Scheduled',
            cronExp,
            new AllotmentCourseOfferingScheduler()
        );
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Scheduled job should return a valid Job ID');

        // Verify job was actually created
        List<CronTrigger> jobs = [
            SELECT Id, State
            FROM CronTrigger
            WHERE Id = :jobId
        ];
        System.assertEquals(1, jobs.size(), 'Job should exist in CronTrigger');
    }

    // ──────────────────────────────────────────────────────
    // Test 2: Direct execute call
    // ──────────────────────────────────────────────────────
    @isTest
    static void testDirectExecute() {
        Test.startTest();
        AllotmentCourseOfferingScheduler sched = new AllotmentCourseOfferingScheduler();
        sched.execute(null);
        Test.stopTest();
        // No assertion needed — this simply proves the execute method
        // does not throw any exceptions when called directly
    }
}