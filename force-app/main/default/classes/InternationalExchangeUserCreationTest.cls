// F-10 FIX: Removed SeeAllData=true — all data created explicitly in @TestSetup
@IsTest
public class InternationalExchangeUserCreationTest {

    @TestSetup
    static void setup() {
        // Create an Account to own the Contacts
        Account a = new Account(Name = 'Test University');
        Database.DMLOptions dml = new Database.DMLOptions();
        dml.DuplicateRuleHeader.AllowSave = true;
        Database.insert(a, dml);
    }

    private static Account getAccount() {
        return [SELECT Id FROM Account WHERE Name = 'Test University' LIMIT 1];
    }

    // F-12 FIX: Use Long cast before Math.abs to prevent Integer.MIN_VALUE overflow
    private static String uniqueStr() {
        return String.valueOf(Math.abs((Long) Crypto.getRandomInteger()))
             + String.valueOf(System.now().getTime()).right(6);
    }

    private static Contact createContact(Account a, Boolean withEmail) {
        String uniq = uniqueStr();
        Contact c = new Contact(
            FirstName = 'Test',
            LastName  = 'Student',
            Email     = withEmail ? 'student.' + uniq + '@test.com' : null,
            AccountId = a.Id
        );
        Database.DMLOptions dml = new Database.DMLOptions();
        dml.DuplicateRuleHeader.AllowSave = true;
        Database.insert(c, dml);
        return c;
    }

    @IsTest
    static void testCreateExchangeUsers() {
        Account a  = getAccount();
        Contact c1 = createContact(a, true);   // has email → user should be created
        Contact c2 = createContact(a, false);  // no email  → user should be skipped

        InternationalExchangeUserCreation.FlowInput fi1 = new InternationalExchangeUserCreation.FlowInput();
        fi1.contactId = c1.Id;
        fi1.pgid      = 'EXC2612345';

        InternationalExchangeUserCreation.FlowInput fi2 = new InternationalExchangeUserCreation.FlowInput();
        fi2.contactId = c2.Id;
        fi2.pgid      = 'EXC2612346';

        Test.startTest();
        InternationalExchangeUserCreation.createExchangeUsers(
            new List<InternationalExchangeUserCreation.FlowInput>{ fi1, fi2 }
        );
        Test.stopTest();

        // Assert user created for c1 with correct username
        List<User> createdForC1 = [SELECT Id, Username FROM User WHERE ContactId = :c1.Id];
        System.assert(createdForC1.size() >= 1, 'At least one user should be created for c1');
        System.assertEquals('EXC2612345@isb.edu', createdForC1[0].Username,
            'Username should be PGID@isb.edu');

        // F-11 FIX: Assert that contact without email was correctly skipped
        List<User> createdForC2 = [SELECT Id FROM User WHERE ContactId = :c2.Id];
        System.assertEquals(0, createdForC2.size(),
            'No user should be created for a contact without an email address');
    }
}