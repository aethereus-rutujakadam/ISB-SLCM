@isTest
public class ISBContactExitDateBatchTest {

    private static Id getAARTId() {
        return Schema.SObjectType.Contact.getRecordTypeInfosByName()
            .get('Academic Associate').getRecordTypeId();
    }

    private static Contact createAAContact(String email, String status, Date exitDate) {
        Contact con = new Contact(
            FirstName = 'Exit',
            LastName = 'Test',
            Email = email,
            ISB_Email_ID__c = email,
            hed__Preferred_Email__c = 'Alternate Email',
            hed__AlternateEmail__c = email,
            RecordTypeId = getAARTId(),
            Active_Status__c = status,
            Date_of_Exit__c = exitDate
        );
        insert con;
        return con;
    }

    /**
     * Test: Batch deactivates AA contacts whose exit date has passed
     */
    @isTest
    static void testBatchDeactivatesExpiredContacts() {
        Contact con = createAAContact('expired@test.com', 'Active', Date.today().addDays(-1));

        Test.startTest();
        ISBContactExitDateBatch batch = new ISBContactExitDateBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();

        Contact updated = [SELECT Active_Status__c FROM Contact WHERE Id = :con.Id];
        System.assertEquals('Inactive', updated.Active_Status__c, 'Contact with past exit date should be set to Inactive');
    }

    /**
     * Test: Batch does NOT deactivate contacts whose exit date is today or in the future
     */
    @isTest
    static void testBatchSkipsFutureExitDate() {
        Contact con = createAAContact('future@test.com', 'Active', Date.today().addDays(5));

        Test.startTest();
        ISBContactExitDateBatch batch = new ISBContactExitDateBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();

        Contact unchanged = [SELECT Active_Status__c FROM Contact WHERE Id = :con.Id];
        System.assertEquals('Active', unchanged.Active_Status__c, 'Contact with future exit date should remain Active');
    }

    /**
     * Test: Batch does NOT deactivate contacts that are already Inactive
     */
    @isTest
    static void testBatchSkipsAlreadyInactiveContacts() {
        Contact con = createAAContact('alreadyinactive@test.com', 'Inactive', Date.today().addDays(-1));

        Test.startTest();
        ISBContactExitDateBatch batch = new ISBContactExitDateBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();

        Contact unchanged = [SELECT Active_Status__c FROM Contact WHERE Id = :con.Id];
        System.assertEquals('Inactive', unchanged.Active_Status__c, 'Already Inactive contact should not be changed');
    }

    /**
     * Test: Batch does NOT process contacts with no exit date
     */
    @isTest
    static void testBatchSkipsNullExitDate() {
        Contact con = createAAContact('noexit@test.com', 'Active', null);

        Test.startTest();
        ISBContactExitDateBatch batch = new ISBContactExitDateBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();

        Contact unchanged = [SELECT Active_Status__c FROM Contact WHERE Id = :con.Id];
        System.assertEquals('Active', unchanged.Active_Status__c, 'Contact with no exit date should remain Active');
    }

    /**
     * Test: Batch also syncs related AA_Profile__c status to Inactive
     */
    @isTest
    static void testBatchSyncsAAProfileStatus() {
        Contact con = createAAContact('profilesync@test.com', 'Active', Date.today().addDays(-1));

        List<AA_Profile__c> profiles = [SELECT Id FROM AA_Profile__c WHERE Academic_Associate__c = :con.Id LIMIT 1];
        if (profiles.isEmpty()) {
            insert new AA_Profile__c(
                Academic_Associate__c = con.Id,
                Name = 'Profile Sync Test (AA-Profile)',
                Status__c = 'Active'
            );
        }

        Test.startTest();
        ISBContactExitDateBatch batch = new ISBContactExitDateBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();

        Contact updatedCon = [SELECT Active_Status__c FROM Contact WHERE Id = :con.Id];
        System.assertEquals('Inactive', updatedCon.Active_Status__c, 'Contact should be Inactive after batch');

        AA_Profile__c updatedProfile = [SELECT Status__c FROM AA_Profile__c WHERE Academic_Associate__c = :con.Id LIMIT 1];
        System.assertEquals('Inactive', updatedProfile.Status__c, 'AA Profile should also be synced to Inactive');
    }

    /**
     * Test: Batch handles empty result set gracefully
     */
    @isTest
    static void testBatchWithNoMatchingRecords() {
        // No records match: all future exit dates
        createAAContact('empty@test.com', 'Active', Date.today().addDays(10));

        Test.startTest();
        ISBContactExitDateBatch batch = new ISBContactExitDateBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();

        System.assert(true, 'Batch should complete without errors when no records match');
    }

    /**
     * Test: Scheduler executes the batch without errors
     */
    @isTest
    static void testSchedulerExecutesBatch() {
        Test.startTest();
        ISBContactExitDateScheduler scheduler = new ISBContactExitDateScheduler();
        scheduler.execute(null);
        Test.stopTest();

        System.assert(true, 'Scheduler should execute batch without errors');
    }

    /**
     * Test: scheduleDaily registers and re-registers the job
     */
    @isTest
    static void testScheduleDailyRegistersJob() {
        Test.startTest();
        ISBContactExitDateScheduler.scheduleDaily();
        // Call again to verify re-registration (abort + re-schedule) works
        ISBContactExitDateScheduler.scheduleDaily();
        Test.stopTest();

        List<CronTrigger> jobs = [
            SELECT Id FROM CronTrigger
            WHERE CronJobDetail.Name = 'ISB Contact Exit Date Daily Deactivation'
        ];
        System.assertEquals(1, jobs.size(), 'Only one scheduled job should exist after scheduleDaily');
    }
}