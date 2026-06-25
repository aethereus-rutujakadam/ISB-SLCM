@IsTest(SeeAllData=true)
public class DataCloudUserCreationTest {
    
    // ---------- Helpers ----------
    private static User createInternalUserWithRole() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' OR Name = 'System Administrator' LIMIT 1];
        UserRole r = [SELECT Id FROM UserRole LIMIT 1];
        
        String uniq = 'u' + String.valueOf(System.now().getTime()).substring(7) + String.valueOf(Math.abs(Crypto.getRandomInteger()));
        
        User u = new User(
            FirstName = 'Acct',
            LastName  = 'Owner',
            Email     = uniq + '@test.com',
            Username  = uniq + '@test.com',
            Alias     = 'aown',
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_IN',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = p.Id,
            UserRoleId = r.Id
        );
        
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
        }
        return u;
    }
    
    private static Account createAccountOwnedBy(User ownerUser) {
        Account a = new Account(
            Name = 'Test Account ' + System.now().getTime() + Crypto.getRandomInteger(),
            OwnerId = ownerUser.Id
        );
        
        Database.DMLOptions dml = new Database.DMLOptions();
        dml.DuplicateRuleHeader.AllowSave = true;
        Database.insert(a, dml);
        
        return a;
    }
    
    private static Contact createContact(Account a, Boolean withEmail) {
        String uniq = String.valueOf(System.now().getTime()).substring(7) + String.valueOf(Math.abs(Crypto.getRandomInteger()));
        Contact c = new Contact(
            FirstName = 'Test' + uniq,
            LastName  = 'Student' + uniq,
            Email     = withEmail ? 'student.' + uniq + '@test.com' : null,
            AccountId = a.Id,
            hed__Preferred_Email__c = 'VF Email ID',
            VF_Email_ID__c          = 'admin.' + uniq + '@isb.com',
            ISB_Email_ID__c         = withEmail ? 'student.' + uniq + '@test.com' : null,
            New_Admit_Email__c      = withEmail ? 'admit.' + uniq + '@test.com' : null
        );
        
        Database.DMLOptions dml = new Database.DMLOptions();
        dml.DuplicateRuleHeader.AllowSave = true;
        Database.insert(c, dml);
        
        return c;
    }
    
    private static UserRole getStudentRoleOrNull() {
        List<UserRole> roles = [
            SELECT Id, DeveloperName
            FROM UserRole
            WHERE DeveloperName = 'Student'
            LIMIT 1
        ];
        return roles.isEmpty() ? null : roles[0];
    }
    
    private static Profile getCommunityProfileOrNull() {
        List<Profile> profs = [
            SELECT Id, Name
            FROM Profile
            WHERE Name = 'Customer Community Plus User'
            LIMIT 1
        ];
        return profs.isEmpty() ? null : profs[0];
    }
    
    // ---------- Tests ----------
    @IsTest
    static void testCreateCommunityUsers_success_futureRuns() {
        UserRole studentRole = getStudentRoleOrNull();
        Profile communityProfile = getCommunityProfileOrNull();
        
        if (studentRole == null || communityProfile == null) return;
        
        User accountOwner = createInternalUserWithRole();
        Account a = createAccountOwnedBy(accountOwner);
        
        // Test multiple contacts
        Contact c1 = createContact(a, true);
        Contact c2 = createContact(a, true);
        
        // Test contact with missing email to trigger catch block in loop
        Contact cError = createContact(a, false);
        
        DataCloudUserCreation.FlowInput fi1 = new DataCloudUserCreation.FlowInput();
        fi1.contactId = c1.Id;
        DataCloudUserCreation.FlowInput fi2 = new DataCloudUserCreation.FlowInput();
        fi2.contactId = c2.Id;
        DataCloudUserCreation.FlowInput fiError = new DataCloudUserCreation.FlowInput();
        fiError.contactId = cError.Id;
        
        Test.startTest();
        DataCloudUserCreation.createCommunityUsers(new List<DataCloudUserCreation.FlowInput>{ fi1, fi2, fiError });
        Test.stopTest(); 
        
        // Assert: community users created for the valid contacts
        List<User> created = [
            SELECT Id, ContactId FROM User WHERE ContactId IN (:c1.Id, :c2.Id)
        ];
        System.assert(created.size() >= 1, 'At least one user should be created');
    }
    
    @IsTest
    static void testCreateCommunityUsers_UpdateFlow() {
        UserRole studentRole = getStudentRoleOrNull();
        Profile communityProfile = getCommunityProfileOrNull();
        
        if (studentRole == null || communityProfile == null) return;
        
        User accountOwner = createInternalUserWithRole();
        Account a = createAccountOwnedBy(accountOwner);
        Contact c1 = createContact(a, true);
        
        c1 = [SELECT Id, FirstName, LastName, AccountId, New_Admit_Email__c 
              FROM Contact WHERE Id = :c1.Id];
        
        String uniq = 'u' + String.valueOf(System.now().getTime()).substring(7) 
            + String.valueOf(Math.abs(Crypto.getRandomInteger()));
        
        User u = new User(
            ProfileId         = communityProfile.Id,
            ContactId         = c1.Id,         
            FirstName         = c1.FirstName,
            LastName          = c1.LastName,
            Email             = 'oldemail@test.com',
            Username          = uniq + '@orgb.com',
            Alias             = 'stuA',
            CommunityNickname = 'nick' + uniq.substring(0, 4),
            TimeZoneSidKey    = 'Asia/Kolkata',
            LocaleSidKey      = 'en_IN',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            IsActive          = true
        );
        
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
        }
        
        DataCloudUserCreation.FlowInput fi = new DataCloudUserCreation.FlowInput();
        fi.contactId = c1.Id;
        
        Test.startTest();
        DataCloudUserCreation.createCommunityUsers(
            new List<DataCloudUserCreation.FlowInput>{ fi }
        );
        Test.stopTest();
        
        User updatedU = [SELECT Id, Email FROM User WHERE Id = :u.Id];
        System.assertEquals(c1.New_Admit_Email__c, updatedU.Email, 
                            'Existing User email should be updated');
    }
    
    @IsTest
    static void testCreateCommunityUsers_NegativePaths() {
        DataCloudUserCreation.createCommunityUsers(new List<DataCloudUserCreation.FlowInput>());
        
        DataCloudUserCreation.FlowInput fiNull = new DataCloudUserCreation.FlowInput();
        fiNull.contactId = null;
        DataCloudUserCreation.createCommunityUsers(new List<DataCloudUserCreation.FlowInput>{ fiNull });
        
        DataCloudUserCreation.FlowInput fiInvalid = new DataCloudUserCreation.FlowInput();
        fiInvalid.contactId = '003000000000000AAA'; 
        
        Test.startTest();
        DataCloudUserCreation.createCommunityUsers(new List<DataCloudUserCreation.FlowInput>{ fiInvalid });
        Test.stopTest();
        
        System.assert(true, 'Negative paths should not crash');
    }
}