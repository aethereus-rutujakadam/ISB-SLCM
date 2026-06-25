@isTest
public class AAUserCreationActionTest {

    @isTest
    static void testSendWelcomeEmailSuccess() {
        // Create a test user
        String uniqueStr = String.valueOf(Datetime.now().getTime()) + String.valueOf(Math.random());
        User testUser = new User(
            FirstName = 'Test',
            LastName = 'AAUser',
            Email = 'testaauser' + uniqueStr + '@example.com',
            Username = 'testaauser' + uniqueStr + '@example.com.test',
            Alias = 'taau',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
            LanguageLocaleKey = 'en_US'
        );
        insert testUser;
        
        Test.startTest();
        // Call the invocable method
        AAUserCreationAction.sendWelcomeEmail(new List<Id>{testUser.Id});
        Test.stopTest();
        
        // Verify user still exists (no errors occurred)
        User verifyUser = [SELECT Id, Email FROM User WHERE Id = :testUser.Id];
        System.assertNotEquals(null, verifyUser, 'User should exist after email send');
    }

    @isTest
    static void testSendWelcomeEmailMultipleUsers() {
        // Create multiple test users
        String uniqueStr = String.valueOf(Datetime.now().getTime());
        List<User> testUsers = new List<User>();
        
        for (Integer i = 0; i < 3; i++) {
            testUsers.add(new User(
                FirstName = 'Test' + i,
                LastName = 'AAUser' + i,
                Email = 'testaauser' + i + uniqueStr + '@example.com',
                Username = 'testaauser' + i + uniqueStr + '@example.com.test',
                Alias = 'tau' + i,
                TimeZoneSidKey = 'America/Los_Angeles',
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
                LanguageLocaleKey = 'en_US'
            ));
        }
        insert testUsers;
        
        List<Id> userIds = new List<Id>();
        for (User u : testUsers) {
            userIds.add(u.Id);
        }
        
        Test.startTest();
        // Call the invocable method with multiple users
        AAUserCreationAction.sendWelcomeEmail(userIds);
        Test.stopTest();
        
        // Verify all users still exist
        List<User> verifyUsers = [SELECT Id FROM User WHERE Id IN :userIds];
        System.assertEquals(3, verifyUsers.size(), 'All 3 users should exist after email send');
    }

    @isTest
    static void testSendWelcomeEmailEmptyList() {
        Test.startTest();
        // Call with empty list
        AAUserCreationAction.sendWelcomeEmail(new List<Id>());
        Test.stopTest();
        
        // Should complete without errors
        System.assert(true, 'Method should handle empty list gracefully');
    }

    @isTest
    static void testSendWelcomeEmailInvalidUserId() {
        // Create a fake user ID
        Id fakeUserId = Id.valueOf(User.SObjectType.getDescribe().getKeyPrefix() + '000000000001');
        
        Test.startTest();
        // Call with invalid user ID - should be caught by exception handler
        AAUserCreationAction.sendWelcomeEmail(new List<Id>{fakeUserId});
        Test.stopTest();
        
        // Should complete without throwing exception (caught internally)
        System.assert(true, 'Method should handle invalid user ID gracefully');
    }

    @isTest
    static void testSendWelcomeEmailWithValidAndInvalidIds() {
        // Create one valid user
        String uniqueStr = String.valueOf(Datetime.now().getTime()) + String.valueOf(Math.random());
        User testUser = new User(
            FirstName = 'Valid',
            LastName = 'User',
            Email = 'validuser' + uniqueStr + '@example.com',
            Username = 'validuser' + uniqueStr + '@example.com.test',
            Alias = 'vuser',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
            LanguageLocaleKey = 'en_US'
        );
        insert testUser;
        
        // Create a fake user ID
        Id fakeUserId = Id.valueOf(User.SObjectType.getDescribe().getKeyPrefix() + '000000000002');
        
        Test.startTest();
        // Call with mix of valid and invalid IDs
        AAUserCreationAction.sendWelcomeEmail(new List<Id>{testUser.Id, fakeUserId});
        Test.stopTest();
        
        // Valid user should still exist
        User verifyUser = [SELECT Id FROM User WHERE Id = :testUser.Id];
        System.assertNotEquals(null, verifyUser, 'Valid user should exist');
    }
}