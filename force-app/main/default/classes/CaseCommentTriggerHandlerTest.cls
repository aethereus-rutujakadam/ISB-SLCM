@isTest
public class CaseCommentTriggerHandlerTest {

    // Helper to create roles avoiding Mixed DML issues
    // We can't insert roles in the same transaction as non-setup objects easily unless we use System.runAs separate blocks
    
    private static User createTestUser(String lastName, String roleName) {
        Profile p = [SELECT Id FROM Profile WHERE Name='System Administrator' LIMIT 1];
        
        // Find or create role
        UserRole r;
        if (roleName != null) {
             // In tests, we can insert roles. 
             // To avoid "MIXED_DML_OPERATION", we must do this in a separate context or handle carefully.
             // We can check if it exists first.
             List<UserRole> roles = [SELECT Id FROM UserRole WHERE Name = :roleName LIMIT 1];
             if (!roles.isEmpty()) {
                 r = roles[0];
             } else {
                 r = new UserRole(Name = roleName);
                 insert r;
             }
        }
        
        String uniqueKey = 'u' + System.currentTimeMillis() + lastName.replaceAll('\\s+','');
        User u = new User(
            Alias = 'testu', 
            Email = uniqueKey + '@test.com',
            EmailEncodingKey = 'UTF-8', 
            LastName = lastName, 
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US', 
            ProfileId = p.Id,
            UserRoleId = (r != null ? r.Id : null),
            TimeZoneSidKey = 'America/Los_Angeles', 
            UserName = uniqueKey + '@test.com'
        );
        insert u;
        return u;
    }

    @isTest
    static void testNotifyCaseCreator() {
        // 1. Setup Data
        User roUser, nonRoUser;
        
        System.runAs(new User(Id = UserInfo.getUserId())) {
            roUser = createTestUser('RO User', 'RO Level 1');
            nonRoUser = createTestUser('Normal User', null);
        }
        
        // 2. Create Case as Non-RO User (simulating case created by someone else)
        Case c;
        System.runAs(nonRoUser) {
             c = new Case(Subject = 'Test Case', Status = 'New');
             insert c;
        }
        
        // Share Case with RO User so they can comment
        System.runAs(new User(Id = UserInfo.getUserId())) {
            CaseShare cs = new CaseShare();
            cs.CaseId = c.Id;
            cs.UserOrGroupId = roUser.Id;
            cs.CaseAccessLevel = 'Edit';
            cs.RowCause = 'Manual';
            insert cs;
        }
        
        // 3. Add Comment as RO User
        System.runAs(roUser) {
            CaseComment cc = new CaseComment(ParentId = c.Id, CommentBody = 'RO Comment');
            
            Test.startTest();
            insert cc;
            Test.stopTest();
        }
    }

    @isTest
    static void testNotifyPreviousCommenter() {
        
        User lpuUser, initialCommenter, caseCreator;
        
        System.runAs(new User(Id = UserInfo.getUserId())) {
            lpuUser = createTestUser('LPU User', 'Lovely Professional University Customer User');
            initialCommenter = createTestUser('Initial Commenter', null);
            caseCreator = createTestUser('Case Creator', null);
        }
        
        Case c;
        System.runAs(caseCreator) {
            c = new Case(Subject = 'LPU Case', Status = 'New');
            insert c;
        }
        
        // Share Case with Commenters
        System.runAs(new User(Id = UserInfo.getUserId())) {
            List<CaseShare> shares = new List<CaseShare>();
            
            CaseShare cs1 = new CaseShare();
            cs1.CaseId = c.Id;
            cs1.UserOrGroupId = initialCommenter.Id;
            cs1.CaseAccessLevel = 'Edit';
            cs1.RowCause = 'Manual';
            shares.add(cs1);
            
            CaseShare cs2 = new CaseShare();
            cs2.CaseId = c.Id;
            cs2.UserOrGroupId = lpuUser.Id;
            cs2.CaseAccessLevel = 'Edit';
            cs2.RowCause = 'Manual';
            shares.add(cs2);
            
            insert shares;
        }
        
        // Initial comment by someone
        System.runAs(initialCommenter) {
            CaseComment cc1 = new CaseComment(ParentId = c.Id, CommentBody = 'First Comment');
            insert cc1;
        }
        
        // Second comment by LPU User
        System.runAs(lpuUser) {
            Test.startTest();
            CaseComment cc2 = new CaseComment(ParentId = c.Id, CommentBody = 'LPU Response');
            insert cc2;
            Test.stopTest();
        }
    }
    
    @isTest
    static void testNoNotification_InvalidRole() {
        User normalUser;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            normalUser = createTestUser('Normal User', null);
        }
        
        Case c;
        System.runAs(normalUser) {
            c = new Case(Subject = 'Normal Case');
            insert c;
        }
        
        System.runAs(normalUser) {
            Test.startTest();
            CaseComment cc = new CaseComment(ParentId = c.Id, CommentBody = 'Just a comment');
            insert cc;
            Test.stopTest();
        }
    }

    // Explicitly test Helper Private Methods via "VisibleForTesting" or just trust coverage?
    // Since methods are private and class isn't @TestVisible, we rely on Trigger execution.
}