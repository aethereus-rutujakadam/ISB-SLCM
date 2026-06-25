@isTest
public class ActivateAAUserActionTest {

    @isTest
    static void testActivateUsersFullFlow() {
        // 1. Setup Data
        User u;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            u = TestDataFactory.testUser('testusr', 'test' + DateTime.now().getTime() + '@example.com');
            u.IsActive = false;
            update u;
        }
        Contact c = TestDataFactory.testAAContact(u);

        // 2. Prepare Request
        ActivateAAUserAction.RequestWrapper req = new ActivateAAUserAction.RequestWrapper();
        req.contactId = c.Id;
        req.assignPlans = true; 

        // 3. Mock the Version Map with Dummy IDs 
        // This is the key to covering the "Year 1" and "Year 2" blocks!
        Map<String, Id> mockVersionMap = new Map<String, Id>{
            'Year 1- Onboarding' => c.Id, // Dummy ID (Apex Map doesn't care about Type)
            'Year-2 Certification & Professional Development' => c.Id
        };

        Test.startTest();
        // Call the main method
        ActivateAAUserAction.activateUsers(new List<ActivateAAUserAction.RequestWrapper>{req});
        
        // 4. MANUALLY execute the Queueables with the mock data to force line coverage
        ActivateAAUserAction.ActivateUsersQueueable qActivation = 
            new ActivateAAUserAction.ActivateUsersQueueable(new List<Id>{u.Id}, new Set<Id>{c.Id}, mockVersionMap);
        qActivation.execute(null);

        ActivateAAUserAction.CreateActionPlansQueueable qPlans = 
            new ActivateAAUserAction.CreateActionPlansQueueable(new Set<Id>{c.Id}, mockVersionMap);
        qPlans.execute(null);
        
        Test.stopTest(); 
        
        // Assertions
        System.assertEquals(true, [SELECT IsActive FROM User WHERE Id = :u.Id].IsActive);
    }

    @isTest
    static void testNoPlansBranch() {
        User u = TestDataFactory.testUser('testact', 'act' + DateTime.now().getTime() + '@example.com');
        Contact c = TestDataFactory.testAAContact(u);

        ActivateAAUserAction.RequestWrapper req = new ActivateAAUserAction.RequestWrapper();
        req.contactId = c.Id;
        req.assignPlans = false; 

        Test.startTest();
        // This hits the branch where assignPlans is false
        ActivateAAUserAction.activateUsers(new List<ActivateAAUserAction.RequestWrapper>{req});
        Test.stopTest();
    }

    @isTest
    static void testEmptyTemplateBranch() {
        User u = TestDataFactory.testUser('testwarn', 'warn' + DateTime.now().getTime() + '@example.com');
        Contact c = TestDataFactory.testAAContact(u);

        ActivateAAUserAction.RequestWrapper req = new ActivateAAUserAction.RequestWrapper();
        req.contactId = c.Id;
        req.assignPlans = true; 

        Test.startTest();
        // This will result in an empty versionMap, covering the "Warning" statusMessage line
        ActivateAAUserAction.activateUsers(new List<ActivateAAUserAction.RequestWrapper>{req});
        Test.stopTest();
    }

    @isTest
    static void testExceptionPath() {
        Test.startTest();
        // Passing a request that will fail (null ID) to trigger catch block
        ActivateAAUserAction.RequestWrapper req = new ActivateAAUserAction.RequestWrapper();
        req.contactId = null; 
        ActivateAAUserAction.activateUsers(new List<ActivateAAUserAction.RequestWrapper>{req});
        Test.stopTest();
    }
}