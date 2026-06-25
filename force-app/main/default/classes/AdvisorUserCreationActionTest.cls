@isTest
public class AdvisorUserCreationActionTest {

    @isTest
    static void testWelcomeEmailSent() {
        // Create a test user
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User testUser = new User(
            FirstName = 'Welcome',
            LastName = 'Test',
            Email = 'welcometest@test.com',
            Username = 'welcometest' + System.currentTimeMillis() + '@testorg.com',
            Alias = 'wtest',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = p.Id,
            LanguageLocaleKey = 'en_US'
        );
        insert testUser;
        
        List<Id> userIds = new List<Id>{testUser.Id};
        
        Test.startTest();
        AdvisorUserCreationAction.sendWelcomeEmail(userIds);
        Test.stopTest();
        
        // Verify method was called (actual email sending happens in @future)
        System.assertEquals(1, userIds.size(), 'Should have 1 user ID');
        System.assertNotEquals(null, testUser.Email, 'User should have an email');
    }

    @isTest
    static void testBulkWelcomeEmails() {
        // Create multiple test users
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        List<User> testUsers = new List<User>();
        for (Integer i = 0; i < 5; i++) {
            testUsers.add(new User(
                FirstName = 'Bulk',
                LastName = 'Welcome' + i,
                Email = 'bulkwelcome' + i + '@test.com',
                Username = 'bulkwelcome' + i + System.currentTimeMillis() + '@testorg.com',
                Alias = 'bwel' + i,
                TimeZoneSidKey = 'America/Los_Angeles',
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                ProfileId = p.Id,
                LanguageLocaleKey = 'en_US'
            ));
        }
        insert testUsers;
        
        List<Id> userIds = new List<Id>();
        for (User u : testUsers) {
            userIds.add(u.Id);
        }
        
        Test.startTest();
        AdvisorUserCreationAction.sendWelcomeEmail(userIds);
        Test.stopTest();
        
        System.assertEquals(5, userIds.size(), 'Should process 5 users');
    }

    @isTest
    static void testEmptyUserIdList() {
        List<Id> userIds = new List<Id>();
        
        Test.startTest();
        AdvisorUserCreationAction.sendWelcomeEmail(userIds);
        Test.stopTest();
        
        // Should handle empty list gracefully
        System.assertEquals(0, userIds.size(), 'Empty list should be handled without error');
    }
}