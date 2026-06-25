@isTest
public class ManageEligibleSessionsControllerTest {
    
    @testSetup
    static void setup() {
        // Create test program
        Program prog = TestDataFactory.testProgram();
        
        // Create academic year
        AcademicYear ay = TestDataFactory.testAcademicYear();
        
        // Create academic term
        AcademicTerm term = TestDataFactory.testAcademicTerm(prog.Id);
        
        // Create academic sessions
        AcademicSession sess1 = new AcademicSession(
            Name = 'Fall 2025',
            Program__c = prog.Id,
            AcademicTermId = term.Id
        );
        insert sess1;
        
        AcademicSession sess2 = new AcademicSession(
            Name = 'Spring 2026',
            Program__c = prog.Id,
            AcademicTermId = term.Id
        );
        insert sess2;
        
        AcademicSession sess3 = new AcademicSession(
            Name = 'Summer 2026',
            Program__c = prog.Id,
            AcademicTermId = term.Id
        );
        insert sess3;
        
        // Create ISB Fees Master
        ISB_Fees_Master__c feesMaster = new ISB_Fees_Master__c(
            Academic_Term__c = term.Id
        );
        insert feesMaster;
    }
    
    /**
     * TEST 1: Get Eligible Sessions Data - Happy Path
     * Tests retrieval of sessions and existing eligible terms
     */
    @isTest
    static void testGetEligibleSessionsData_Success() {
        // Setup
        ISB_Fees_Master__c feesMaster = [SELECT Id FROM ISB_Fees_Master__c LIMIT 1];
        List<AcademicSession> sessions = [SELECT Id FROM AcademicSession ORDER BY Name ASC];
        
        // Create some existing eligible terms
        List<ISB_Eligible_Term__c> existingTerms = new List<ISB_Eligible_Term__c>();
        for (Integer i = 0; i < 2; i++) {
            existingTerms.add(new ISB_Eligible_Term__c(
                Academic_Session__c = sessions[i].Id,
                ISB_Fees_Master__c = feesMaster.Id,
                Sequence__c = i + 1
            ));
        }
        insert existingTerms;
        
        // Execute
        Map<String, Object> result = ManageEligibleSessionsController.getEligibleSessionsData(feesMaster.Id);
        
        // Assert
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(true, result.containsKey('academicTermName'), 'Should contain academicTermName');
        System.assertEquals(true, result.containsKey('sessions'), 'Should contain sessions');
        System.assertEquals(true, result.containsKey('existingTerms'), 'Should contain existingTerms');
        System.assertEquals(true, result.containsKey('existingSessionIds'), 'Should contain existingSessionIds');
        
        List<AcademicSession> returnedSessions = (List<AcademicSession>) result.get('sessions');
        System.assertEquals(3, returnedSessions.size(), 'Should return 3 sessions');
        
        List<String> existingSessionIds = (List<String>) result.get('existingSessionIds');
        System.assertEquals(2, existingSessionIds.size(), 'Should return 2 existing session IDs');
    }
    
    /**
     * TEST 2: Get Eligible Sessions Data - No Existing Terms
     * Tests when no eligible terms exist yet
     */
    @isTest
    static void testGetEligibleSessionsData_NoExistingTerms() {
        // Setup
        ISB_Fees_Master__c feesMaster = [SELECT Id FROM ISB_Fees_Master__c LIMIT 1];
        
        // Execute
        Map<String, Object> result = ManageEligibleSessionsController.getEligibleSessionsData(feesMaster.Id);
        
        // Assert
        System.assertNotEquals(null, result, 'Result should not be null');
        
        List<ISB_Eligible_Term__c> existingTerms = (List<ISB_Eligible_Term__c>) result.get('existingTerms');
        System.assertEquals(0, existingTerms.size(), 'Should return 0 existing terms');
        
        List<String> existingSessionIds = (List<String>) result.get('existingSessionIds');
        System.assertEquals(0, existingSessionIds.size(), 'Should return empty session IDs list');
        
        List<AcademicSession> sessions = (List<AcademicSession>) result.get('sessions');
        System.assertEquals(3, sessions.size(), 'Should still return all sessions');
    }
    
    /**
     * TEST 3: Get Eligible Sessions Data - Invalid Fees Master ID
     * Tests error handling for invalid fees master
     */
    @isTest
    static void testGetEligibleSessionsData_InvalidId() {
        // Setup
        String invalidId = 'a1A000000000000';
        
        // Execute & Assert
        try {
            ManageEligibleSessionsController.getEligibleSessionsData(invalidId);
            System.assert(false, 'Should have thrown an exception');
        } catch (AuraHandledException e) {
            //System.assert(e.getMessage().contains('Error loading session data'), 'Should contain expected error message');
        }
    }
    
    /**
     * TEST 4: Create Eligible Terms - Happy Path
     * Tests creation of multiple eligible terms
     */
    @isTest
    static void testCreateEligibleTerms_Success() {
        // Setup
        ISB_Fees_Master__c feesMaster = [SELECT Id FROM ISB_Fees_Master__c LIMIT 1];
        List<AcademicSession> sessions = [SELECT Id FROM AcademicSession ORDER BY Name ASC];
        
        List<String> sessionIds = new List<String>();
        sessionIds.add(sessions[0].Id);
        sessionIds.add(sessions[1].Id);
        
        // Execute
        ManageEligibleSessionsController.createEligibleTerms(feesMaster.Id, sessionIds);
        
        // Assert
        List<ISB_Eligible_Term__c> createdTerms = [
            SELECT Id, Sequence__c, Academic_Session__c
            FROM ISB_Eligible_Term__c
            WHERE ISB_Fees_Master__c = :feesMaster.Id
            ORDER BY Sequence__c ASC
        ];
        
        System.assertEquals(2, createdTerms.size(), 'Should create 2 eligible terms');
        System.assertEquals(1, createdTerms[0].Sequence__c, 'First sequence should be 1');
        System.assertEquals(2, createdTerms[1].Sequence__c, 'Second sequence should be 2');
        System.assertEquals(sessions[0].Id, createdTerms[0].Academic_Session__c, 'Should link correct session');
    }
    
    /**
     * TEST 5: Create Eligible Terms - Replace Existing
     * Tests that existing terms are deleted and new ones created
     */
    @isTest
    static void testCreateEligibleTerms_ReplaceExisting() {
        // Setup
        ISB_Fees_Master__c feesMaster = [SELECT Id FROM ISB_Fees_Master__c LIMIT 1];
        List<AcademicSession> sessions = [SELECT Id FROM AcademicSession ORDER BY Name ASC];
        
        // Create initial eligible terms
        List<ISB_Eligible_Term__c> initialTerms = new List<ISB_Eligible_Term__c>();
        initialTerms.add(new ISB_Eligible_Term__c(
            Academic_Session__c = sessions[0].Id,
            ISB_Fees_Master__c = feesMaster.Id,
            Sequence__c = 1
        ));
        insert initialTerms;
        
        Id initialTermId = initialTerms[0].Id;
        
        // Verify initial record exists
        System.assertEquals(1, [SELECT COUNT() FROM ISB_Eligible_Term__c WHERE ISB_Fees_Master__c = :feesMaster.Id]);
        
        // Execute - Create new terms with different sessions
        List<String> newSessionIds = new List<String>();
        newSessionIds.add(sessions[1].Id);
        newSessionIds.add(sessions[2].Id);
        newSessionIds.add(sessions[0].Id);
        
        ManageEligibleSessionsController.createEligibleTerms(feesMaster.Id, newSessionIds);
        
        // Assert - Old terms should be deleted
        System.assertEquals(0, [SELECT COUNT() FROM ISB_Eligible_Term__c WHERE Id = :initialTermId], 'Old term should be deleted');
        
        // Assert - New terms should be created
        List<ISB_Eligible_Term__c> newTerms = [
            SELECT Id, Sequence__c
            FROM ISB_Eligible_Term__c
            WHERE ISB_Fees_Master__c = :feesMaster.Id
            ORDER BY Sequence__c ASC
        ];
        
        System.assertEquals(3, newTerms.size(), 'Should create 3 new terms');
        System.assertEquals(1, newTerms[0].Sequence__c, 'Sequence should start at 1');
        System.assertEquals(2, newTerms[1].Sequence__c, 'Sequence should be 2');
        System.assertEquals(3, newTerms[2].Sequence__c, 'Sequence should be 3');
    }
    
    /**
     * TEST 6: Create Eligible Terms - Empty List
     * Tests creation with empty session ID list
     */
    @isTest
    static void testCreateEligibleTerms_EmptyList() {
        // Setup
        ISB_Fees_Master__c feesMaster = [SELECT Id FROM ISB_Fees_Master__c LIMIT 1];
        List<AcademicSession> sessions = [SELECT Id FROM AcademicSession ORDER BY Name ASC];
        
        // Create initial term
        ISB_Eligible_Term__c initialTerm = new ISB_Eligible_Term__c(
            Academic_Session__c = sessions[0].Id,
            ISB_Fees_Master__c = feesMaster.Id,
            Sequence__c = 1
        );
        insert initialTerm;
        
        // Execute - Create with empty list
        ManageEligibleSessionsController.createEligibleTerms(feesMaster.Id, new List<String>());
        
        // Assert - Old terms should be deleted, no new ones created
        System.assertEquals(0, [SELECT COUNT() FROM ISB_Eligible_Term__c WHERE ISB_Fees_Master__c = :feesMaster.Id], 
            'All terms should be deleted when empty list provided');
    }
    
    /**
     * TEST 7: Create Eligible Terms - Single Session
     * Tests creation with single session
     */
    @isTest
    static void testCreateEligibleTerms_SingleSession() {
        // Setup
        ISB_Fees_Master__c feesMaster = [SELECT Id FROM ISB_Fees_Master__c LIMIT 1];
        List<AcademicSession> sessions = [SELECT Id FROM AcademicSession LIMIT 1];
        
        List<String> sessionIds = new List<String> { sessions[0].Id };
        
        // Execute
        ManageEligibleSessionsController.createEligibleTerms(feesMaster.Id, sessionIds);
        
        // Assert
        List<ISB_Eligible_Term__c> createdTerms = [
            SELECT Id, Sequence__c
            FROM ISB_Eligible_Term__c
            WHERE ISB_Fees_Master__c = :feesMaster.Id
        ];
        
        System.assertEquals(1, createdTerms.size(), 'Should create 1 term');
        System.assertEquals(1, createdTerms[0].Sequence__c, 'Sequence should be 1');
    }
    
    /**
     * TEST 8: Create Eligible Terms - Invalid Fees Master
     * Tests error handling for invalid fees master
     */
    @isTest
    static void testCreateEligibleTerms_InvalidFeesMaster() {
        // Setup
        String invalidId = 'a1A000000000000';
        List<String> sessionIds = new List<String> { 'a1A000000000001' };
        
        // Execute & Assert
        try {
            ManageEligibleSessionsController.createEligibleTerms(invalidId, sessionIds);
            System.assert(false, 'Should have thrown an exception');
        } catch (AuraHandledException e) {
           // System.assert(e.getMessage().contains('Error creating eligible terms'), 'Should contain expected error message');
        }
    }
    
    /**
     * TEST 9: Create Eligible Terms - Duplicate Session IDs
     * Tests handling of duplicate session IDs in the list
     */
    @isTest
    static void testCreateEligibleTerms_DuplicateSessionIds() {
        // Setup
        ISB_Fees_Master__c feesMaster = [SELECT Id FROM ISB_Fees_Master__c LIMIT 1];
        List<AcademicSession> sessions = [SELECT Id FROM AcademicSession LIMIT 2];
        
        // Create list with duplicates
        List<String> sessionIds = new List<String>();
        sessionIds.add(sessions[0].Id);
        sessionIds.add(sessions[0].Id);  // Duplicate
        sessionIds.add(sessions[1].Id);
        
        // Execute
        ManageEligibleSessionsController.createEligibleTerms(feesMaster.Id, sessionIds);
        
        // Assert - Should create terms for all entries (including duplicates)
        List<ISB_Eligible_Term__c> createdTerms = [
            SELECT Id, Sequence__c
            FROM ISB_Eligible_Term__c
            WHERE ISB_Fees_Master__c = :feesMaster.Id
            ORDER BY Sequence__c ASC
        ];
        
        System.assertEquals(3, createdTerms.size(), 'Should create 3 terms (including duplicate)');
        System.assertEquals(1, createdTerms[0].Sequence__c, 'First sequence should be 1');
        System.assertEquals(3, createdTerms[2].Sequence__c, 'Third sequence should be 3');
    }
    
    /**
     * TEST 10: Get Eligible Sessions Data - Verify Academic Term Name
     * Tests that correct academic term name is returned
     */
    @isTest
    static void testGetEligibleSessionsData_TermName() {
        // Setup
        ISB_Fees_Master__c feesMaster = [SELECT Id FROM ISB_Fees_Master__c LIMIT 1];
        AcademicTerm expectedTerm = [SELECT Name FROM AcademicTerm LIMIT 1];
        
        // Execute
        Map<String, Object> result = ManageEligibleSessionsController.getEligibleSessionsData(feesMaster.Id);
        
        // Assert
        String returnedTermName = (String) result.get('academicTermName');
        System.assertEquals(expectedTerm.Name, returnedTermName, 'Should return correct academic term name');
    }
    
    /**
     * TEST 11: Create Eligible Terms - Verify DML Operation
     * Tests that data is actually persisted in the database
     */
    @isTest
    static void testCreateEligibleTerms_DataPersistence() {
        // Setup
        ISB_Fees_Master__c feesMaster = [SELECT Id FROM ISB_Fees_Master__c LIMIT 1];
        List<AcademicSession> sessions = [SELECT Id FROM AcademicSession ORDER BY Name ASC LIMIT 2];
        
        List<String> sessionIds = new List<String>();
        sessionIds.add(sessions[0].Id);
        sessionIds.add(sessions[1].Id);
        
        // Execute
        ManageEligibleSessionsController.createEligibleTerms(feesMaster.Id, sessionIds);
        
        // Assert - Query fresh data to verify persistence
        ISB_Eligible_Term__c verifyFirstTerm = [
            SELECT Academic_Session__c, ISB_Fees_Master__c, Sequence__c
            FROM ISB_Eligible_Term__c
            WHERE ISB_Fees_Master__c = :feesMaster.Id
            AND Sequence__c = 1
            LIMIT 1
        ];
        
        System.assertEquals(sessions[0].Id, verifyFirstTerm.Academic_Session__c, 'First session should be persisted');
        System.assertEquals(feesMaster.Id, verifyFirstTerm.ISB_Fees_Master__c, 'Fees master should be persisted');
    }
    
    /**
     * TEST 12: Get Eligible Sessions Data - Multiple Calls
     * Tests that multiple calls return consistent results
     */
    @isTest
    static void testGetEligibleSessionsData_Consistency() {
        // Setup
        ISB_Fees_Master__c feesMaster = [SELECT Id FROM ISB_Fees_Master__c LIMIT 1];
        
        // Execute first call
        Map<String, Object> result1 = ManageEligibleSessionsController.getEligibleSessionsData(feesMaster.Id);
        
        // Execute second call
        Map<String, Object> result2 = ManageEligibleSessionsController.getEligibleSessionsData(feesMaster.Id);
        
        // Assert - Both calls should return same data
        List<AcademicSession> sessions1 = (List<AcademicSession>) result1.get('sessions');
        List<AcademicSession> sessions2 = (List<AcademicSession>) result2.get('sessions');
        
        System.assertEquals(sessions1.size(), sessions2.size(), 'Both calls should return same number of sessions');
        System.assertEquals(
            (String) result1.get('academicTermName'), 
            (String) result2.get('academicTermName'),
            'Both calls should return same academic term name'
        );
    }
}