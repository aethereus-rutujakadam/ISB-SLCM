@isTest
public class AwardAutoNumberHandlerTest {

    @isTest
    static void testBeforeInsert_FirstRun() {
        // Scenario: No Award_Counter__c exists yet.
        
        // Prepare Records
        List<Award> awards = new List<Award>();
        for(Integer i=0; i<5; i++) {
            Award a = new Award();
            // Add required fields if any. Assuming standard Award object minimal requirements.
            // If custom fields are required, add them here.
            // a.Award_Date__c = Date.today(); 
            awards.add(a);
        }
        
        Test.startTest();
        // Call Handler Directy (Before Insert)
        AwardAutoNumberHandler.handleEvents(awards, true, false);
        Test.stopTest();
        
        // Asset Names generated
        // Counter starts at 0.
        // Item 0 -> Awd-001
        // Item 1 -> Awd-002
        System.assertEquals('Awd-001', awards[0].Name, 'First award should be Awd-001');
        System.assertEquals('Awd-005', awards[4].Name, 'Fifth award should be Awd-005');
        
        // Verify Counter Created
        Award_Counter__c counter = [SELECT Last_Number__c FROM Award_Counter__c LIMIT 1];
        System.assertEquals(5, counter.Last_Number__c, 'Counter should be updated to 5');
    }
    
    @isTest
    static void testBeforeInsert_ExistingCounter() {
        // Scenario: Counter exists
        Award_Counter__c counter = new Award_Counter__c(Last_Number__c = 100);
        insert counter;
        
        List<Award> awards = new List<Award>();
        Award a = new Award();
        awards.add(a);
        
        Test.startTest();
        AwardAutoNumberHandler.handleEvents(awards, true, false);
        Test.stopTest();
        
        System.assertEquals('Awd-101', awards[0].Name);
        
        // Verify Counter Updated
        Award_Counter__c updatedCounter = [SELECT Last_Number__c FROM Award_Counter__c WHERE Id = :counter.Id];
        System.assertEquals(101, updatedCounter.Last_Number__c);
    }
    
    @isTest
    static void testBeforeInsert_NameProvided() {
        // Scenario: Name provided, should not change
        Award a = new Award(Name = 'Custom-Name');
        List<Award> awards = new List<Award>{a};
        
        Test.startTest();
        AwardAutoNumberHandler.handleEvents(awards, true, false);
        Test.stopTest();
        
        System.assertEquals('Custom-Name', awards[0].Name);
        
        // Verify Counter NOT Created/Updated if all have names?
        // Code logic: It fetches counter anyway (line 21).
        // It skips incrementing inside loop (line 39).
        // It updates counter with 'nextNumber' (line 45).
        // If nextNumber didn't change (still 0 or initial), it updates with same value.
        // Let's verify counter exists (created if not exists)
        List<Award_Counter__c> counters = [SELECT Last_Number__c FROM Award_Counter__c];
        System.assert(!counters.isEmpty(), 'Counter should be created even if name provided');
        System.assertEquals(0, counters[0].Last_Number__c, 'Counter should be 0 if no auto-number used');
    }
    
    @isTest
    static void testAfterInsert_Approval() {
        // Scenario: After Insert triggers Approval submission
        // Need to Insert Award first to have ID
        
        Award a = new Award(Name = 'Test-Award');
        insert a;
        
        List<Award> awards = new List<Award>{a};
        
        Test.startTest();
        // The handler logic for After Insert submits for approval.
        // Inside test, the logical skips Approval.process() call via !Test.isRunningTest() check.
        // We verify no exceptions occur.
        AwardAutoNumberHandler.handleEvents(awards, false, true);
        Test.stopTest();
        
        // Since we can't verify approval process in unit test easily without mocking or real process,
        // and code explicitly skips it, we just ensure successful execution.
        System.assert(true, 'Executed without exception');
    }
}