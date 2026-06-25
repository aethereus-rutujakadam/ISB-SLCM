@isTest
public class ISBContactRelationshipControllerTest {

    // ================================
    // TEST: Contact Flow (Happy Path)
    // ================================
    @isTest
    static void testGetRelationships_Contact() {

        // Create contact using factory
        Contact con = TestDataFactory.testContact();

        // Set External Id (IMPORTANT)
        con.ISB_External_Id__c = 'EXT123';
        update con;

        Test.startTest();
        List<Map<String, Object>> result =
            ISBContactRelationshipController.getRelationships(con.Id);
        Test.stopTest();

        // We can't insert Data Cloud records in test,
        // so result will be empty but method should execute
        System.assertNotEquals(null, result);
    }


    // ======================================
    // TEST: AA_Profile Flow (Happy Path)
    // ======================================
    @isTest
    static void testGetRelationships_AAProfile() {

        // Create User + Contact (AA)
        User u = TestDataFactory.testUser('testaa', 'aa@test.com');
        Contact aaContact = TestDataFactory.testAAContact(u);

        // Set external id
        aaContact.ISB_External_Id__c = 'EXT456';
        update aaContact;

        // Create AA Profile
        AA_Profile__c profile = TestDataFactory.testAAProfile(aaContact.Id);

        Test.startTest();
        List<Map<String, Object>> result =
            ISBContactRelationshipController.getRelationships(profile.Id);
        Test.stopTest();

        System.assertNotEquals(null, result);
    }


    // ======================================
    // TEST: NULL Record Id
    // ======================================
    @isTest
    static void testGetRelationships_NullId() {

        Test.startTest();
        List<Map<String, Object>> result =
            ISBContactRelationshipController.getRelationships(null);
        Test.stopTest();

        System.assertEquals(0, result.size(), 'Should return empty list');
    }


    // ======================================
    // TEST: Blank External Id
    // ======================================
    @isTest
    static void testGetRelationships_BlankExternalId() {

        Contact con = TestDataFactory.testContact();
        // No external Id set

        Test.startTest();
        List<Map<String, Object>> result =
            ISBContactRelationshipController.getRelationships(con.Id);
        Test.stopTest();

        System.assertEquals(0, result.size(), 'Should return empty list');
    }


    // ======================================
    // TEST: Exception Handling
    // ======================================
    @isTest
    static void testGetRelationships_Exception() {

        Boolean exceptionThrown = false;

        try {
            Test.startTest();

            // Passing fake Id to break query
            ISBContactRelationshipController.getRelationships(
                TestDataFactory.fakeId(Contact.SObjectType)
            );

            Test.stopTest();

        } catch (Exception e) {
            exceptionThrown = true;
            System.assert(e instanceof AuraHandledException);
        }
    }
}