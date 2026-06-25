public with sharing class ClubMembershipService {

    /**
     * Creates Club_Membership__c records for a contact
     * against all ACTIVE Council Clubs
     */
    public static void createMembershipsForContact(Id contactId) {

        if (contactId == null) {
            throw new IllegalArgumentException('Contact Id cannot be null');
        }

        // Fetch Council record type
        Id councilRtId = Schema.SObjectType.Club__c
            .getRecordTypeInfosByDeveloperName()
            .get('Council')
            .getRecordTypeId();

        // Fetch active Council clubs
        List<Club__c> activeCouncilClubs = [
            SELECT Id, Name
            FROM Club__c
            WHERE Active__c = true
            AND RecordTypeId = :councilRtId
        ];

        if (activeCouncilClubs.isEmpty()) {
            System.debug('No active Council clubs found');
            return;
        }

        List<Club_Membership__c> membershipsToInsert = new List<Club_Membership__c>();

        for (Club__c club : activeCouncilClubs) {
            Club_Membership__c membership = new Club_Membership__c();
            membership.Contact__c = contactId;
            membership.Club__c    = club.Id;
            membership.Status__c  = 'Active';// optional
            membership.Role__c = 'Member';
            membershipsToInsert.add(membership);
        }

        if (!membershipsToInsert.isEmpty()) {
            insert membershipsToInsert;
            System.debug(membershipsToInsert.size() + ' memberships created');
        }
    }
}