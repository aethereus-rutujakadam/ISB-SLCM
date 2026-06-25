@isTest
public class CaseCommentTriggerHelperTest {

    /* ---------------------------------------------------------
       COMMON USER FACTORY
    ----------------------------------------------------------*/
    private static User createUser(String lastName, String roleName) {
        Profile p = [SELECT Id FROM Profile WHERE Name='System Administrator' LIMIT 1];
        UserRole r;

        if (roleName != null) {
            List<UserRole> roles = [SELECT Id FROM UserRole WHERE Name=:roleName LIMIT 1];
            r = roles.isEmpty() ? new UserRole(Name=roleName) : roles[0];
            if (r.Id == null) insert r;
        }

        String uname = 'u' + System.currentTimeMillis() + '@test.com';
        User u = new User(
            Username = uname,
            Email = uname,
            LastName = lastName,
            Alias = lastName.substring(0,2),
            ProfileId = p.Id,
            UserRoleId = r != null ? r.Id : null,
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles'
        );
        insert u;
        return u;
    }

    /* ---------------------------------------------------------
       TEST 1: Case Creator Notification Path (RO User)
    ----------------------------------------------------------*/
    @isTest
static void testNotifyCaseCreatorPath() {

    User admin = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
    User roUser;
    User caseCreator;

    // ---- SETUP OBJECTS ONLY ----
    System.runAs(admin) {
        roUser = createUser('ROUser', 'RO Level 1');
        caseCreator = createUser('Creator', null);
    }

    // ---- NON-SETUP OBJECTS ONLY ----
    System.runAs(caseCreator) {
        Case c = new Case(Subject='RO Path', Status='New');
        insert c;

        insert new CaseShare(
            CaseId = c.Id,
            UserOrGroupId = roUser.Id,
            CaseAccessLevel = 'Edit',
            RowCause = 'Manual'
        );

        System.runAs(roUser) {
            CaseComment cc = new CaseComment(
                ParentId = c.Id,
                CommentBody = 'RO Comment'
            );
            insert cc;

            Test.startTest();
            CaseCommentTriggerHelper.processNotifications(
                new List<CaseComment>{cc},
                new Set<Id>{c.Id}
            );
            Test.stopTest();
        }
    }
}


    /* ---------------------------------------------------------
       TEST 2: Previous Commenter Notification Path (LPU User)
    ----------------------------------------------------------*/
    @isTest
static void testNotifyPreviousCommenterPath() {

    User admin = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
    User creator;
    User first;
    User lpuUser;

    // ---- SETUP OBJECTS ----
    System.runAs(admin) {
        creator = createUser('Creator2', null);
        first = createUser('First', null);
        lpuUser = createUser(
            'LPU',
            'Lovely Professional University Customer User'
        );
    }

    // ---- NON-SETUP OBJECTS ----
    System.runAs(creator) {
        Case c = new Case(Subject='Previous Logic', Status='New');
        insert c;

        insert new List<CaseShare>{
            new CaseShare(
                CaseId=c.Id,
                UserOrGroupId=first.Id,
                CaseAccessLevel='Edit',
                RowCause='Manual'
            ),
            new CaseShare(
                CaseId=c.Id,
                UserOrGroupId=lpuUser.Id,
                CaseAccessLevel='Edit',
                RowCause='Manual'
            )
        };

        System.runAs(first) {
            insert new CaseComment(
                ParentId=c.Id,
                CommentBody='Initial comment'
            );
        }

        CaseComment cc2 =
            new CaseComment(ParentId=c.Id, CommentBody='Reply');

        System.runAs(lpuUser) {
            insert cc2;

            Test.startTest();
            CaseCommentTriggerHelper.processNotifications(
                new List<CaseComment>{cc2},
                new Set<Id>{c.Id}
            );
            Test.stopTest();
        }
    }
}


    /* ---------------------------------------------------------
       TEST 3: No Previous Comment Exists (NULL branch)
    ----------------------------------------------------------*/
    @isTest
    static void testNoPreviousCommentBranch() {
        User user = createUser('Solo', 'Lovely Professional University Customer User');

        Case c;
        System.runAs(user) {
            c = new Case(Subject='Single Comment', Status='New');
            insert c;

            CaseComment cc = new CaseComment(
                ParentId = c.Id,
                CommentBody = 'Only comment'
            );
            insert cc;

            Test.startTest();
            CaseCommentTriggerHelper.processNotifications(
                new List<CaseComment>{cc},
                new Set<Id>{c.Id}
            );
            Test.stopTest();
        }
    }

    /* ---------------------------------------------------------
       TEST 4: Notification Type NOT Found (early return)
    ----------------------------------------------------------*/
    @isTest
static void testNotificationTypeNotFound() {

    User admin = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
    User u;

    // ---- SETUP ONLY ----
    System.runAs(admin) {
        u = createUser('NoType', 'RO Level 2');
    }

    // ---- NON-SETUP ONLY ----
    System.runAs(u) {
        Case c = new Case(
            Subject='No Notification Type',
            Status='New'
        );
        insert c;

        CaseComment cc = new CaseComment(
            ParentId=c.Id,
            CommentBody='Test'
        );
        insert cc;

        Test.startTest();
        CaseCommentTriggerHelper.processNotifications(
            new List<CaseComment>{cc},
            new Set<Id>{c.Id}
        );
        Test.stopTest();
    }
}


    /* ---------------------------------------------------------
       TEST 5: Direct Config Coverage
    ----------------------------------------------------------*/
    @isTest
    static void testNotificationConfigGetters() {
        CaseCommentTriggerHelper.NotificationConfig config =
            new CaseCommentTriggerHelper.NotificationConfig();

        Test.startTest();
        Set<String> a = config.notifyCaseCreatorRoles;
        Set<String> b = config.notifyPreviousCommenterRoles;
        String c = config.notificationTypeDeveloperName;
        String d = config.notificationTitle;
        String e = config.notificationBodyTemplate;
        Test.stopTest();

        System.assertNotEquals(null, a);
        System.assertNotEquals(null, b);
        System.assertNotEquals(null, c);
        System.assertNotEquals(null, d);
        System.assertNotEquals(null, e);
    }
}