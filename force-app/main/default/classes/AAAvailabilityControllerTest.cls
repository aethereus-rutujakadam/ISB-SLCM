@isTest
private class AAAvailabilityControllerTest {

    @testSetup
    static void makeData() {
        // Create User
        User testUser = TestDataFactory.testUser('alias', 'tuser@test.com');
        
        // Create AA Contact linked to User
        Contact aaContact = TestDataFactory.testAAContact(testUser);
        
        // Create Program
        Program prog = new Program(Name = 'Test Program', IsActive = true);
        insert prog;
        
        // Create Academic Term & Session
        AcademicTerm t = new AcademicTerm(Name = 'Test Term 2025', Program__c = prog.Id, IsActive = true);
        insert t;
        
        AcademicSession sess = new AcademicSession(Name = 'Test Session 2025', AcademicTermId = t.Id, IsActive = true);
        insert sess;
        
        // Create AA Profile
        AA_Profile__c aaProfile = TestDataFactory.testAAProfile(t.Id, aaContact.Id);
        
        // Create Availability
        TestDataFactory.testAAAvailability(aaProfile.Id, t.Id, 'Available - Full');
    }

    @isTest
    static void getProgramsTest() {
        Test.startTest();
        List<Map<String, String>> results = AAAvailabilityController.getPrograms();
        Test.stopTest();
        System.assert(results != null);
    }

    @isTest
    static void getAcademicTermsTest() {
        Program p = [SELECT Id FROM Program LIMIT 1];
        Test.startTest();
        List<Map<String, String>> results = AAAvailabilityController.getAcademicTerms(p.Id);
        Test.stopTest();
        System.assert(results != null);
    }

    @isTest
    static void getAcademicSessionsForTermTest() {
        AcademicSession sess = [SELECT Id, AcademicTermId FROM AcademicSession LIMIT 1];
        
        Test.startTest();
        List<Map<String, String>> results = AAAvailabilityController.getAcademicSessionsForTerm(sess.AcademicTermId);
        Test.stopTest();
        
        System.assert(results.size() > 0, 'Should return sessions');
    }
    
    @isTest
    static void getExistingAvailabilityTest() {
        AA_Profile__c profile = [SELECT Id FROM AA_Profile__c LIMIT 1];
        Program p = [SELECT Id FROM Program LIMIT 1];
        AcademicTerm t = [SELECT Id FROM AcademicTerm LIMIT 1];
        
        Test.startTest();
        List<AA_Availability__c> results = AAAvailabilityController.getExistingAvailability(profile.Id, p.Id, t.Id);
        Test.stopTest();
        
        System.assert(results != null);
    }
    
    @isTest
    static void saveAllAvailabilityTest() {
        AA_Profile__c profile = [SELECT Id FROM AA_Profile__c LIMIT 1];
        AcademicSession sess = [SELECT Id, AcademicTermId FROM AcademicSession LIMIT 1];
        Program p = [SELECT Id FROM Program LIMIT 1];
        
        // Prepare Row Data
        List<AAAvailabilityController.AvailabilityRow> rows = new List<AAAvailabilityController.AvailabilityRow>();
        
        AAAvailabilityController.AvailabilityRow r1 = new AAAvailabilityController.AvailabilityRow();
        r1.academicSessionId = sess.Id;
        r1.academicTermId = sess.AcademicTermId;
        r1.programId = p.Id;
        r1.availability = 'Available - Partial';
        r1.fromDate = String.valueOf(Date.today());
        r1.toDate = String.valueOf(Date.today().addDays(2));
        r1.notes = 'Test Note';
        rows.add(r1);
        
        Test.startTest();
        AAAvailabilityController.saveAllAvailability(profile.Id, rows);
        Test.stopTest();
        
        // Verify Insertion
        List<AA_Availability__c> records = [SELECT Id, Availability__c, From_Date__c, Notes__c FROM AA_Availability__c WHERE AA_Profile__c = :profile.Id AND Availability__c = 'Available - Partial'];
        System.assertEquals(1, records.size(), 'Should have saved 1 partial availability record');
    }
    
    @isTest
    static void saveAllAvailabilityOverlapTest() {
        AA_Profile__c profile = [SELECT Id FROM AA_Profile__c LIMIT 1];
        AcademicSession sess = [SELECT Id, AcademicTermId FROM AcademicSession LIMIT 1];
        Program p = [SELECT Id FROM Program LIMIT 1];
        
        // Test update existing
        AA_Availability__c existing = [SELECT Id FROM AA_Availability__c LIMIT 1];
        
        List<AAAvailabilityController.AvailabilityRow> rows = new List<AAAvailabilityController.AvailabilityRow>();
        AAAvailabilityController.AvailabilityRow r1 = new AAAvailabilityController.AvailabilityRow();
        r1.recordId = existing.Id;
        r1.academicSessionId = sess.Id;
        r1.academicTermId = sess.AcademicTermId;
        r1.programId = p.Id;
        r1.availability = 'Available - Full';
        rows.add(r1);
        
        Test.startTest();
        AAAvailabilityController.saveAllAvailability(profile.Id, rows);
        Test.stopTest();
        
        AA_Availability__c updated = [SELECT Id, Availability__c FROM AA_Availability__c WHERE Id = :existing.Id];
        System.assertEquals('Available - Full', updated.Availability__c);
    }
    
    @isTest
    static void deleteAvailabilityTest() {
        AA_Availability__c existing = [SELECT Id FROM AA_Availability__c LIMIT 1];
        
        Test.startTest();
        AAAvailabilityController.deleteAvailability(existing.Id);
        Test.stopTest();
        
        List<AA_Availability__c> results = [SELECT Id FROM AA_Availability__c WHERE Id = :existing.Id];
        System.assert(results.isEmpty());
    }

    @isTest
    static void saveAllAvailabilityErrorTest() {
        AA_Profile__c profile = [SELECT Id FROM AA_Profile__c LIMIT 1];
        AcademicSession sess = [SELECT Id, AcademicTermId FROM AcademicSession LIMIT 1];
        
        // Test Incomplete Row
        List<AAAvailabilityController.AvailabilityRow> rows = new List<AAAvailabilityController.AvailabilityRow>();
        AAAvailabilityController.AvailabilityRow r1 = new AAAvailabilityController.AvailabilityRow();
        r1.academicSessionId = sess.Id;
        r1.availability = null; 
        rows.add(r1);
        
        try {
            AAAvailabilityController.saveAllAvailability(profile.Id, rows);
            System.assert(false, 'Should throw exception for missing availability');
        } catch (Exception e) {}

        // Test Date Logic
        r1.availability = 'Available - Partial';
        r1.fromDate = String.valueOf(Date.today().addDays(5));
        r1.toDate = String.valueOf(Date.today());
        try {
            AAAvailabilityController.saveAllAvailability(profile.Id, rows);
            System.assert(false, 'Should throw exception for invalid date range');
        } catch (Exception e) {}
        
        // Test Duplicate in batch
        rows.add(r1); 
        try {
            AAAvailabilityController.saveAllAvailability(profile.Id, rows);
            System.assert(false, 'Should throw exception for duplicates in batch');
        } catch (Exception e) {}
    }
}