@isTest
public class DeactivateAAUserActionTest {

    /* ============================================================
     * @TestSetup
     * Creates reusable AA User + AA Contact
     * ========================================================== */
    @TestSetup
    static void setupTestData() {

        // Create AA User
        User aaUser = TestDataFactory.testUser(
            'aausr',
            'aa.user.' + Datetime.now().getTime() + '@example.com'
        );

        // Create Academic Associate Contact linked to AA User
        TestDataFactory.testAAContact(aaUser);
    }

    /* ============================================================
     * SUCCESS SCENARIO
     * Contact has linked User → User deactivated
     * ========================================================== */
    @isTest
    static void testDeactivateUsers_validContact_userDeactivated() {

        Contact aaContact = [
            SELECT Id, Linked_User_Id__c
            FROM Contact
            WHERE Linked_User_Id__c != null
            LIMIT 1
        ];

        DeactivateAAUserAction.Request req =
            new DeactivateAAUserAction.Request();
        req.contactId = aaContact.Id;

        Test.startTest();
        List<DeactivateAAUserAction.Response> responses =
            DeactivateAAUserAction.deactivateUsers(
                new List<DeactivateAAUserAction.Request>{ req }
            );
        Test.stopTest(); // flushes @future

        User updatedUser = [
            SELECT IsActive
            FROM User
            WHERE Id = :aaContact.Linked_User_Id__c
        ];

        System.assertEquals(1, responses.size());
        System.assertEquals(true, responses[0].success);
        System.assertEquals(
            false,
            updatedUser.IsActive,
            'Linked User should be deactivated'
        );
    }

    /* ============================================================
     * EDGE CASE
     * Empty request list
     * ========================================================== */
    @isTest
    static void testDeactivateUsers_emptyRequestList_returnsFailure() {

        Test.startTest();
        List<DeactivateAAUserAction.Response> responses =
            DeactivateAAUserAction.deactivateUsers(
                new List<DeactivateAAUserAction.Request>()
            );
        Test.stopTest();

        System.assertEquals(1, responses.size());
        System.assertEquals(false, responses[0].success);
        System.assertEquals(
            'No Contact IDs received from Flow.',
            responses[0].resultMessage
        );
    }

    /* ============================================================
     * EDGE CASE
     * Request with null Contact Id
     * ========================================================== */
    @isTest
    static void testDeactivateUsers_nullContactId_returnsFailure() {

        DeactivateAAUserAction.Request req =
            new DeactivateAAUserAction.Request();
        req.contactId = null;

        Test.startTest();
        List<DeactivateAAUserAction.Response> responses =
            DeactivateAAUserAction.deactivateUsers(
                new List<DeactivateAAUserAction.Request>{ req }
            );
        Test.stopTest();

        System.assertEquals(false, responses[0].success);
        System.assertEquals(
            'No Contact IDs received from Flow.',
            responses[0].resultMessage
        );
    }

    /* ============================================================
     * EDGE CASE
     * Contact without Linked User
     * ========================================================== */
    @isTest
    static void testDeactivateUsers_contactWithoutLinkedUser_returnsFailure() {

        Contact contactWithoutUser = TestDataFactory.testContact();

        DeactivateAAUserAction.Request req =
            new DeactivateAAUserAction.Request();
        req.contactId = contactWithoutUser.Id;

        Test.startTest();
        List<DeactivateAAUserAction.Response> responses =
            DeactivateAAUserAction.deactivateUsers(
                new List<DeactivateAAUserAction.Request>{ req }
            );
        Test.stopTest();

        System.assertEquals(false, responses[0].success);
        System.assertEquals(
            'No linked User IDs found for the provided Contacts.',
            responses[0].resultMessage
        );
    }

    /* ============================================================
     * EDGE CASE (NO DML)
     * Fake Contact Id using TestDataFactory.getFakeId
     * ========================================================== */
    @isTest
    static void testDeactivateUsers_fakeContactId_safeFailure() {

        DeactivateAAUserAction.Request req =
            new DeactivateAAUserAction.Request();

        req.contactId =
            (Id) TestDataFactory.getFakeId(Contact.SObjectType);

        Test.startTest();
        List<DeactivateAAUserAction.Response> responses =
            DeactivateAAUserAction.deactivateUsers(
                new List<DeactivateAAUserAction.Request>{ req }
            );
        Test.stopTest();

        System.assertEquals(false, responses[0].success);
    }
}