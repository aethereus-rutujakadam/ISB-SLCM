@IsTest
private class ArchiveClubMembershipBatchTest {

    /* =====================================================
       TEST SETUP
       ===================================================== */
    @TestSetup
    static void setupData() {
        // 1. Create parent data
        Contact student = TestDataFactory.testContact();
        
        // 2. Create actual Custom Object Club (prefix 11W)
        Club__c actualClub = new Club__c(Name = 'Strategic Management Club');
        insert actualClub;

        List<Club_Membership__c> memberships = new List<Club_Membership__c>();

        // 3. Active memberships (Lead role required for Validation Rule)
        for (Integer i = 0; i < 10; i++) {
            memberships.add(new Club_Membership__c(
                Contact__c = student.Id,
                Club__c = actualClub.Id,
                Role__c = 'Lead', 
                Status__c = 'Active'
            ));
        }

        // 4. Archived memberships
        for (Integer i = 0; i < 5; i++) {
            memberships.add(new Club_Membership__c(
                Contact__c = student.Id,
                Club__c = actualClub.Id,
                Role__c = 'Lead',
                Status__c = 'Archived'
            ));
        }

        // 5. Inactive memberships
        for (Integer i = 0; i < 3; i++) {
            memberships.add(new Club_Membership__c(
                Contact__c = student.Id,
                Club__c = actualClub.Id,
                Role__c = 'Lead',
                Status__c = 'Inactive'
            ));
        }

        insert memberships;
    }

    @IsTest
    static void testBatchArchivesActiveMemberships() {
        Test.startTest();
        Database.executeBatch(new ArchiveClubMembershipBatch(), 200);
        Test.stopTest();

        Integer activeCount = [SELECT COUNT() FROM Club_Membership__c WHERE Status__c = 'Active'];
        System.assertEquals(0, activeCount);

        Integer archivedCount = [SELECT COUNT() FROM Club_Membership__c WHERE Status__c = 'Archived'];
        System.assertEquals(15, archivedCount);
    }

    /* =====================================================
       TEST: LARGE DATASET (Handles Duplicate Rules)
       ===================================================== */
    @IsTest
static void testBatchProcessesLargeDataset() {
    Contact student = [SELECT Id FROM Contact LIMIT 1];
    Club__c club = [SELECT Id FROM Club__c LIMIT 1]; 

    // 1. Clear existing active records from setup to ensure we start fresh
    delete [SELECT Id FROM Club_Membership__c WHERE Status__c = 'Active'];

    List<Club_Membership__c> bulkData = new List<Club_Membership__c>();
    // 2. Insert exactly 200 records (one full batch execution)
    for (Integer i = 0; i < 200; i++) {
        bulkData.add(new Club_Membership__c(
            Contact__c = student.Id,
            Club__c = club.Id,
            Role__c = 'Lead',
            Status__c = 'Active'
        ));
    }

    Database.DMLOptions dml = new Database.DMLOptions();
    dml.DuplicateRuleHeader.allowSave = true;
    Database.insert(bulkData, dml);

    // 3. Run the Batch with a size of 200
    Test.startTest();
    ArchiveClubMembershipBatch batchJob = new ArchiveClubMembershipBatch();
    Database.executeBatch(batchJob, 200); 
    Test.stopTest(); // This triggers the execution

    // 4. Assert all 200 records were archived
    Integer remaining = [SELECT COUNT() FROM Club_Membership__c WHERE Status__c = 'Active'];
    System.assertEquals(0, remaining, 'All active records in the large dataset should be archived');
}

    @IsTest
    static void testSchedulableExecution() {
        Test.startTest();
        String jobId = System.schedule('Archive Memberships Job', '0 0 12 * * ?', new ArchiveClubMembershipBatch());
        Test.stopTest();

        CronTrigger ct = [SELECT CronExpression FROM CronTrigger WHERE Id = :jobId];
        System.assertEquals('0 0 12 * * ?', ct.CronExpression);
    }

    @IsTest
    static void testBatchHandlesEmptyQuery() {
        delete [SELECT Id FROM Club_Membership__c WHERE Status__c = 'Active'];

        Test.startTest();
        Database.executeBatch(new ArchiveClubMembershipBatch(), 200);
        Test.stopTest();

        Integer archivedCount = [SELECT COUNT() FROM Club_Membership__c WHERE Status__c = 'Archived'];
        System.assertEquals(5, archivedCount);
    }

    @IsTest
    static void testBatchDoesNotModifyInactive() {
        Test.startTest();
        Database.executeBatch(new ArchiveClubMembershipBatch(), 200);
        Test.stopTest();

        Integer inactiveCount = [SELECT COUNT() FROM Club_Membership__c WHERE Status__c = 'Inactive'];
        System.assertEquals(3, inactiveCount);
    }
}