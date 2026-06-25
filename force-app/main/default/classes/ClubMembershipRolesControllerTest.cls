@isTest
private class ClubMembershipRolesControllerTest {
    
    @TestSetup
    static void setupTestData() {
        // 1. Create a Contact
        Contact testContact = TestDataFactory.testContact();
        
        // 2. Create actual Club records
        Club__c c1 = new Club__c(Name = 'Tech Club');
        Club__c c2 = new Club__c(Name = 'Sports Club');
        Club__c c3 = new Club__c(Name = 'Arts Club');
        Club__c c4 = new Club__c(Name = 'Inactive Club');
        insert new List<Club__c>{c1, c2, c3, c4};
        
        // 3. Create memberships using the 'Lead' role
        // This bypasses the PGP/PGPYL requirement entirely
        List<Club_Membership__c> memberships = new List<Club_Membership__c>();
        
        memberships.add(new Club_Membership__c(
            Contact__c = testContact.Id,
            Club__c = c1.Id,
            Role__c = 'Lead', // Bypasses Validation Rule
            Status__c = 'Active'
        ));
        
        memberships.add(new Club_Membership__c(
            Contact__c = testContact.Id,
            Club__c = c2.Id,
            Role__c = 'Lead', // Bypasses Validation Rule
            Status__c = 'Active'
        ));
        
        memberships.add(new Club_Membership__c(
            Contact__c = testContact.Id,
            Club__c = c3.Id,
            Role__c = 'Lead', // Bypasses Validation Rule
            Status__c = 'Active'
        ));
        
        // Inactive one
        memberships.add(new Club_Membership__c(
            Contact__c = testContact.Id,
            Club__c = c4.Id,
            Role__c = 'Lead',
            Status__c = 'Inactive'
        ));
        
        insert memberships;
    }

    @isTest
    static void testGetClubMembershipRoles_WithValidContactId_ReturnsActiveMemberships() {
        Contact testContact = [SELECT Id FROM Contact LIMIT 1];
        Test.startTest();
        ClubMembershipRolesController.RolesResponse response = ClubMembershipRolesController.getClubMembershipRoles(testContact.Id);
        Test.stopTest();
        
        System.assertEquals(3, response.count, 'Should return 3 active Lead memberships');
    }

    @isTest
static void testGetClubMembershipRoles_WithoutContactId_UsesCurrentUserContact() {
    // 1. Get the existing Contact created in Setup
    Contact testContact = [SELECT Id FROM Contact LIMIT 1];
    
    // 2. Create a PORTAL User (Community User) linked to this contact
    // Standard Users cannot have a ContactId assigned manually
    User portalUser = TestDataFactory.testPortalUser(testContact, 'Customer Community Plus User');
    
    Test.startTest();
    System.runAs(portalUser) {
        // Act - Call without contactId parameter
        // The controller should now find portalUser.ContactId automatically
        ClubMembershipRolesController.RolesResponse response = 
            ClubMembershipRolesController.getClubMembershipRoles(null);
        
        // Assert
        System.assertNotEquals(null, response, 'Response should not be null');
        System.assertEquals(3, response.count, 'Should return 3 active memberships for the portal user\'s contact');
    }
    Test.stopTest();
}

    @isTest
    static void testGetClubMembershipRoles_InvalidContactId_HandlesException() {
        Id fakeId = TestDataFactory.getFakeId(Contact.SObjectType);
        ClubMembershipRolesController.RolesResponse response = ClubMembershipRolesController.getClubMembershipRoles(fakeId);
        System.assertEquals(0, response.count);
    }
}