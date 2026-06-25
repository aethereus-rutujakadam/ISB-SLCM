@isTest
private class AACoursePreferenceControllerTest {

    @testSetup
    static void makeData() {
        // Create User
        User u = TestDataFactory.testUser('aacourse', 'aacourse@test.com');
        
        // Create Contact linked to User
        Contact con = TestDataFactory.testAAContact(u);
        
        // Create Program
        Program p = TestDataFactory.testProgram();
        
        // Create Term and Session
        AcademicSession sess = TestDataFactory.createSessionWithTerm(p.Id, 'Fall 2025', Date.today());
        
        // Fetch Term (created in helper)
        AcademicSession fetchedSess = [SELECT Id, AcademicTermId FROM AcademicSession WHERE Id = :sess.Id LIMIT 1];
        
        // Create AA Profile
        AA_Profile__c profile = TestDataFactory.testAAProfile(fetchedSess.AcademicTermId, con.Id);
        
        // Create 4 distinct Learning & Learning Courses & Offerings to support max 4 preferences
        // LearningCourse has 1:1 with Learning, so we need distinct Learning records too.
        for(Integer i=0; i<4; i++) {
            Learning l = TestDataFactory.testLearning();
            LearningCourse lc = TestDataFactory.testLearningCourse(l.Id);
            TestDataFactory.testCourseOffering(lc.Id, sess.Id);
        }
    }
    
    @isTest
    static void getAcademicSessionsTest() {
        Program p = [SELECT Id FROM Program LIMIT 1];
        List<Map<String, String>> sessions = AACoursePreferenceController.getAcademicSessions(p.Id);
        System.assert(sessions != null, 'Should return sessions list');
    }
    
    @isTest
    static void getLearningCoursesTest() {
        AcademicSession sess = [SELECT Id FROM AcademicSession LIMIT 1];
        Program p = [SELECT Id FROM Program LIMIT 1];
        
        // Test with Session and Program
        List<Map<String, String>> courses = AACoursePreferenceController.getLearningCourses(sess.Id, p.Id);
        System.assert(courses != null, 'Should return courses list');
        
        // Test with nulls
        List<Map<String, String>> allCourses = AACoursePreferenceController.getLearningCourses(null, null);
        System.assert(allCourses != null, 'Should return all active courses list');
    }
    
    @isTest
    static void getAvailableCoursesTest() {
        AcademicSession sess = [SELECT Id FROM AcademicSession LIMIT 1];
        CourseOffering co = [SELECT LearningCourseId, Program__c FROM CourseOffering LIMIT 1];
        
        List<CourseOffering> results = AACoursePreferenceController.getAvailableCourses(sess.Id, co.LearningCourseId, co.Program__c);
        System.assert(results != null, 'Should return offering list');
    }
    
    @isTest
    static void getAAProfileDetailsTest() {
        AA_Profile__c profile = [SELECT Id FROM AA_Profile__c LIMIT 1];
        
        Map<String, Object> details = AACoursePreferenceController.getAAProfileDetails(profile.Id);
        
        System.assertEquals(profile.Id, details.get('profileId'));
        System.assert(details.containsKey('termName'), 'Should contain termName');
    }
    
    @isTest
    static void createDraftPreferencesTest() {
        AA_Profile__c profile = [SELECT Id, Academic_Associate__c, Academic_Term__c FROM AA_Profile__c LIMIT 1];
        List<CourseOffering> offerings = [SELECT Id FROM CourseOffering LIMIT 4];
        List<Id> courseIds = new List<Id>();
        for(CourseOffering co : offerings) {
            courseIds.add(co.Id);
        }
        
        List<String> types = new List<String>{'Credit', 'Audit', 'Credit', 'Audit'};
        
        System.Test.startTest();
        String prefId = AACoursePreferenceController.createDraftPreferences(
            courseIds,
            types,
            profile.Academic_Term__c,
            profile.Academic_Associate__c,
            profile.Id
        );
        System.Test.stopTest();
        
        System.assert(prefId != null, 'Should return a Preference ID');
        
        List<AA_Course_Preference__c> prefs = [SELECT Status__c, Preference_Rank__c FROM AA_Course_Preference__c WHERE AA_Contact__c = :profile.Academic_Associate__c];
        System.assertEquals(4, prefs.size(), 'Should have created 4 records');
        System.assertEquals('In Approval', prefs[0].Status__c);
    }
    
    @isTest
    static void createDraftPreferencesErrorTest() {
        // Test No Courses
        try {
            AACoursePreferenceController.createDraftPreferences(null, null, null, null, null);
            System.assert(false, 'Should throw exception');
        } catch (Exception e) {
            System.assert(e.getMessage().contains('Script-thrown exception'), 'Expected script exception');
        }
        
        // Test Duplicate Courses
        AA_Profile__c profile = [SELECT Id, Academic_Term__c, Academic_Associate__c FROM AA_Profile__c LIMIT 1];
        CourseOffering co = [SELECT Id FROM CourseOffering LIMIT 1];
        List<Id> duplicates = new List<Id>{co.Id, co.Id};
        
        try {
            AACoursePreferenceController.createDraftPreferences(duplicates, new List<String>{'Credit', 'Audit'}, profile.Academic_Term__c, profile.Academic_Associate__c, profile.Id);
            System.assert(false, 'Should throw exception for duplicates');
        } catch (Exception e) {
             // Expected
        }
    }
    
    @isTest
    static void submitPreferencesTest() {
        AA_Profile__c profile = [SELECT Id, Academic_Associate__c, Academic_Term__c FROM AA_Profile__c LIMIT 1];
        
        // No-op method now, but we verify it runs
        System.Test.startTest();
        AACoursePreferenceController.submitPreferences(profile.Academic_Associate__c);
        System.Test.stopTest();
    }
    
    @isTest
    static void deleteDraftPreferencesTest() {
         AA_Profile__c profile = [SELECT Id, Academic_Associate__c, Academic_Term__c FROM AA_Profile__c LIMIT 1];
         insert new AA_Course_Preference__c(
             AA_Contact__c = profile.Academic_Associate__c,
             Academic_Associate__c = profile.Id,
             Status__c = 'In Approval'
         );
         
         System.Test.startTest();
         AACoursePreferenceController.deleteDraftPreferences(profile.Academic_Associate__c);
         System.Test.stopTest();
         
         List<AA_Course_Preference__c> prefs = [SELECT Id FROM AA_Course_Preference__c WHERE AA_Contact__c = :profile.Academic_Associate__c AND Status__c = 'In Approval'];
         System.assert(prefs.isEmpty(), 'In Approval prefs should be deleted');
    }
    
    @isTest
    static void getPreferenceHistoryTest() {
        AA_Profile__c profile = [SELECT Id, Academic_Associate__c, Academic_Term__c FROM AA_Profile__c LIMIT 1];
        List<CourseOffering> offerings = [SELECT Id FROM CourseOffering LIMIT 4];
        
        // Create 4 individual records for a "batch"
        List<AA_Course_Preference__c> batch = new List<AA_Course_Preference__c>();
        DateTime submittedTime = System.now();
        for(Integer i=1; i<=4; i++) {
            batch.add(new AA_Course_Preference__c(
                AA_Contact__c = profile.Academic_Associate__c,
                Academic_Associate__c = profile.Id,
                Academic_Term__c = profile.Academic_Term__c,
                Status__c = 'Approved',
                Preference_Rank__c = i,
                Course_Offering__c = offerings[i-1].Id,
                Submitted_On__c = submittedTime
            ));
        }
        insert batch;
        
        System.Test.startTest();
        List<AACoursePreferenceController.PreferenceHistoryRecord> history = AACoursePreferenceController.getPreferenceHistory(profile.Academic_Associate__c);
        System.Test.stopTest();
        
        System.assertEquals(1, history.size(), 'Should have one history batch');
        System.assertEquals('Approved', history[0].status);
        System.assertEquals(4, history[0].preferenceItems.size(), 'Should have 4 items in batch');
    }
    
    @isTest
    static void getPreferencesTest() {
        AA_Profile__c profile = [SELECT Id, Academic_Associate__c, Academic_Term__c FROM AA_Profile__c LIMIT 1];
        List<CourseOffering> offerings = [SELECT Id FROM CourseOffering LIMIT 4];
        
        List<AA_Course_Preference__c> activePrefs = new List<AA_Course_Preference__c>();
        for(Integer i=1; i<=4; i++) {
            activePrefs.add(new AA_Course_Preference__c(
                AA_Contact__c = profile.Academic_Associate__c,
                Academic_Associate__c = profile.Id,
                Academic_Term__c = profile.Academic_Term__c,
                Status__c = 'In Approval',
                Preference_Rank__c = i,
                Course_Offering__c = offerings[i-1].Id
            ));
        }
        insert activePrefs;
        
        System.Test.startTest();
        List<Map<String, Object>> prefs = AACoursePreferenceController.getPreferences(profile.Academic_Associate__c);
        System.Test.stopTest();
        
        System.assert(!prefs.isEmpty());
        System.assertEquals(4, prefs.size(), 'Should return 4 preference items');
    }
}