@isTest
public class AssignAdvisorPermissionSetTest {

    @testSetup
    static void setupData() {
        AssignAdvisorPermissionSet.advisorPermissionSetNameOverride = null;
        AssignAdvisorPermissionSet.additionalPermissionSetNameOverride = null;
    }

    @isTest
    static void testAssignsAdditionalPermissionSetWhenConfigured() {
        User testUser = createTestUser('additional');
        Id permissionSetId = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = 'Advisor_Permission_Set'
            AND IsOwnedByProfile = false
            LIMIT 1
        ].Id;

        AssignAdvisorPermissionSet.InputWrapper input = new AssignAdvisorPermissionSet.InputWrapper();
        input.userId = testUser.Id;

        Test.startTest();
        AssignAdvisorPermissionSet.advisorPermissionSetNameOverride = 'Advisor_Permission_Set';
        AssignAdvisorPermissionSet.additionalPermissionSetNameOverride = 'Missing_Test_Set';
        AssignAdvisorPermissionSet.assignPermissionSet(new List<AssignAdvisorPermissionSet.InputWrapper>{ input });
        Test.stopTest();

        List<PermissionSetAssignment> assignments = [
            SELECT Id, PermissionSetId, PermissionSetGroupId
            FROM PermissionSetAssignment
            WHERE AssigneeId = :testUser.Id
            AND PermissionSetId = :permissionSetId
        ];

        System.assertEquals(1, assignments.size(), 'One additional permission-set assignment should be created.');
        System.assertEquals(permissionSetId, assignments[0].PermissionSetId, 'The configured permission set should be assigned.');
        System.assertEquals(null, assignments[0].PermissionSetGroupId, 'The additional access should be assigned as a permission set.');
    }

    @isTest
    static void testSkipsDuplicateAdditionalPermissionSetAssignment() {
        User testUser = createTestUser('duplicate');
        AssignAdvisorPermissionSet.advisorPermissionSetNameOverride = 'Advisor_Permission_Set';
        AssignAdvisorPermissionSet.additionalPermissionSetNameOverride = 'Missing_Test_Set';

        Test.startTest();
        AssignAdvisorPermissionSet.assignAdvisorPermissionSetAsync(testUser.Id);
        AssignAdvisorPermissionSet.assignAdvisorPermissionSetAsync(testUser.Id);
        Test.stopTest();

        Id permissionSetId = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = 'Advisor_Permission_Set'
            AND IsOwnedByProfile = false
            LIMIT 1
        ].Id;

        Integer assignmentCount = [
            SELECT Count()
            FROM PermissionSetAssignment
            WHERE AssigneeId = :testUser.Id
            AND PermissionSetId = :permissionSetId
        ];

        System.assertEquals(1, assignmentCount, 'Duplicate permission set assignments should be prevented.');
    }

    @isTest
    static void testNullUserId() {
        AssignAdvisorPermissionSet.InputWrapper input = new AssignAdvisorPermissionSet.InputWrapper();
        input.userId = null;

        Test.startTest();
        AssignAdvisorPermissionSet.assignPermissionSet(new List<AssignAdvisorPermissionSet.InputWrapper>{ input });
        Test.stopTest();

        System.assertEquals(null, input.userId, 'Null user IDs should be ignored.');
    }

    @isTest
    static void testEmptyInputList() {
        List<AssignAdvisorPermissionSet.InputWrapper> inputs = new List<AssignAdvisorPermissionSet.InputWrapper>();

        Test.startTest();
        AssignAdvisorPermissionSet.assignPermissionSet(inputs);
        Test.stopTest();

        System.assertEquals(0, inputs.size(), 'Empty input should be handled without error.');
    }

    @isTest
    static void testBulkPermissionAssignment() {
        List<User> testUsers = new List<User>();
        for (Integer indexValue = 0; indexValue < 3; indexValue++) {
            testUsers.add(createTestUser('bulk' + indexValue));
        }

        List<AssignAdvisorPermissionSet.InputWrapper> inputs = new List<AssignAdvisorPermissionSet.InputWrapper>();
        Set<Id> userIds = new Set<Id>();
        for (User testUser : testUsers) {
            AssignAdvisorPermissionSet.InputWrapper input = new AssignAdvisorPermissionSet.InputWrapper();
            input.userId = testUser.Id;
            inputs.add(input);
            userIds.add(testUser.Id);
        }

        Test.startTest();
        AssignAdvisorPermissionSet.advisorPermissionSetNameOverride = 'Advisor_Permission_Set';
        AssignAdvisorPermissionSet.additionalPermissionSetNameOverride = 'Missing_Test_Set';
        AssignAdvisorPermissionSet.assignPermissionSet(inputs);
        Test.stopTest();

        Id permissionSetId = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = 'Advisor_Permission_Set'
            AND IsOwnedByProfile = false
            LIMIT 1
        ].Id;

        Integer assignmentCount = [
            SELECT Count()
            FROM PermissionSetAssignment
            WHERE AssigneeId IN :userIds
            AND PermissionSetId = :permissionSetId
        ];

        System.assertEquals(3, assignmentCount, 'Each user in the batch should receive the additional permission set.');
    }

    private static User createTestUser(String uniqueSuffix) {
        Profile profileRecord = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User testUser = new User(
            FirstName = 'Test',
            LastName = 'Advisor' + uniqueSuffix,
            Email = uniqueSuffix + '@test.com',
            Username = uniqueSuffix + System.currentTimeMillis() + '@testorg.com',
            Alias = uniqueSuffix.length() > 8 ? uniqueSuffix.substring(0, 8) : uniqueSuffix,
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = profileRecord.Id,
            LanguageLocaleKey = 'en_US'
        );
        insert testUser;
        return testUser;
    }
}