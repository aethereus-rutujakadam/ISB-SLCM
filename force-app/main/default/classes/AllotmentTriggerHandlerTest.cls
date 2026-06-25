@IsTest
private class AllotmentTriggerHandlerTest {

    @TestSetup
    static void makeData() {
        List<Allotment__c> records = new List<Allotment__c>{
            new Allotment__c(ISB_Line_Up_ID__c = 'LINEUP-001', Sync_Status__c = 'Approved'),
            new Allotment__c(ISB_Line_Up_ID__c = 'LINEUP-001', Sync_Status__c = 'Synced'),
            new Allotment__c(ISB_Line_Up_ID__c = 'LINEUP-001', Sync_Status__c = 'Error'),
            new Allotment__c(ISB_Line_Up_ID__c = 'LINEUP-002', Sync_Status__c = 'Approved'),
            new Allotment__c(ISB_Line_Up_ID__c = 'LINEUP-002', Sync_Status__c = 'Synced')
        };
        insert records;
    }

    @IsTest
    static void testSiblingsSetToPending() {
        // Grab one LINEUP-001 record and set it to Pending
        Allotment__c triggerRec = [
            SELECT Id, ISB_Line_Up_ID__c, Sync_Status__c
            FROM   Allotment__c
            WHERE  ISB_Line_Up_ID__c = 'LINEUP-001'
            AND    Sync_Status__c    = 'Approved'
            LIMIT  1
        ];

        Test.startTest();
        triggerRec.Sync_Status__c = 'Pending';
        update triggerRec;
        Test.stopTest();

        // All LINEUP-001 records (including triggering one) should now be Pending
        List<Allotment__c> allLineUp001 = [
            SELECT Sync_Status__c
            FROM   Allotment__c
            WHERE  ISB_Line_Up_ID__c = 'LINEUP-001'
        ];

        for (Allotment__c rec : allLineUp001) {
            System.assertEquals('Pending', rec.Sync_Status__c,
                'All LINEUP-001 records should be Pending');
        }
    }

    @IsTest
    static void testNoActionWhenStatusNotChanged() {
        // Update a Pending record without changing its status — should not cascade
        Allotment__c rec = [
            SELECT Id, ISB_Line_Up_ID__c, Sync_Status__c
            FROM   Allotment__c
            WHERE  ISB_Line_Up_ID__c = 'LINEUP-001'
            AND    Sync_Status__c    = 'Approved'
            LIMIT  1
        ];

        // First set it to Pending
        rec.Sync_Status__c = 'Pending';
        update rec;

        // Now update it again without changing status
        Test.startTest();
        rec.ISB_Line_Up_ID__c = rec.ISB_Line_Up_ID__c; // no status change
        update rec;
        Test.stopTest();

        // LINEUP-002 should remain untouched
        List<Allotment__c> lineup002 = [
            SELECT Sync_Status__c
            FROM   Allotment__c
            WHERE  ISB_Line_Up_ID__c = 'LINEUP-002'
        ];

        for (Allotment__c r : lineup002) {
            System.assertNotEquals('Pending', r.Sync_Status__c,
                'LINEUP-002 records should not have been touched');
        }
    }

    @IsTest
    static void testBulkUpdate() {
        // Simulate bulk update of multiple records across different lineup IDs
        List<Allotment__c> allRecs = [
            SELECT Id, ISB_Line_Up_ID__c, Sync_Status__c
            FROM   Allotment__c
        ];

        for (Allotment__c rec : allRecs) {
            rec.Sync_Status__c = 'Pending';
        }

        Test.startTest();
        update allRecs;
        Test.stopTest();

        Integer pendingCount = [
            SELECT COUNT()
            FROM   Allotment__c
            WHERE  Sync_Status__c = 'Pending'
        ];

        System.assertEquals(5, pendingCount, 'All 5 records should be Pending');
    }
}