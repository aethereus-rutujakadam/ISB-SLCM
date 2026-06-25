@IsTest
private class AdvisorUserStatusSyncQueueTest {

    @IsTest
    static void testDeactivatesActiveUser() {
        User advisorUser = createUser('deactivate');

        Test.startTest();
        System.enqueueJob(new AdvisorUserStatusSyncQueue(
            new Map<Id, Boolean>{ advisorUser.Id => false }
        ));
        Test.stopTest();

        User updatedUser = [SELECT IsActive FROM User WHERE Id = :advisorUser.Id];
        System.assertEquals(false, updatedUser.IsActive,
            'Queue should deactivate a linked user when desired state is false.');
    }

    @IsTest
    static void testActivatesInactiveUser() {
        User advisorUser = createUser('activate');
        advisorUser.IsActive = false;
        update advisorUser;

        Test.startTest();
        System.enqueueJob(new AdvisorUserStatusSyncQueue(
            new Map<Id, Boolean>{ advisorUser.Id => true }
        ));
        Test.stopTest();

        User updatedUser = [SELECT IsActive FROM User WHERE Id = :advisorUser.Id];
        System.assertEquals(true, updatedUser.IsActive,
            'Queue should activate a linked user when desired state is true.');
    }

    @IsTest
    static void testIgnoresEmptyMap() {
        User advisorUser = createUser('empty');

        Test.startTest();
        System.enqueueJob(new AdvisorUserStatusSyncQueue(new Map<Id, Boolean>()));
        Test.stopTest();

        User unchangedUser = [SELECT IsActive FROM User WHERE Id = :advisorUser.Id];
        System.assertEquals(true, unchangedUser.IsActive,
            'Queue should leave users unchanged when no ids are supplied.');
    }

    @IsTest
    static void testSkipsUserWhenStatusAlreadyMatches() {
        User advisorUser = createUser('noop');

        Test.startTest();
        System.enqueueJob(new AdvisorUserStatusSyncQueue(
            new Map<Id, Boolean>{ advisorUser.Id => true }
        ));
        Test.stopTest();

        User unchangedUser = [SELECT IsActive FROM User WHERE Id = :advisorUser.Id];
        System.assertEquals(true, unchangedUser.IsActive,
            'Queue should skip updates when the current user status already matches.');
    }

    private static User createUser(String token) {
        Profile profileRecord = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String unique = String.valueOf(System.currentTimeMillis()) + token;

        User userRecord = new User(
            FirstName = 'Advisor',
            LastName = 'Queue' + token,
            Email = 'advisor.queue.' + unique + '@test.com',
            Username = 'advisor.queue.' + unique + '@example.test',
            Alias = ('aq' + token).substring(0, Math.min(8, ('aq' + token).length())),
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = profileRecord.Id
        );
        insert userRecord;
        return userRecord;
    }
}