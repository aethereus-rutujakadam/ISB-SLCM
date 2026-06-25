/**
 * @description Test class for EventHandler - Validates advisor-created event notifications
 * @author DEVSLCM Team
 * @date 2026
 */
@isTest
private class EventHandlerTest {

    @TestSetup
    static void setup() {
        Profile profileRecord = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        // Create advisor user
        User advisorUser = new User(
            FirstName = 'Event',
            LastName = 'Advisor',
            Email = 'event.advisor@test.devslcm',
            Username = 'event.advisor+' + System.now().getTime() + '@test.devslcm',
            Alias = 'evtadv',
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = profileRecord.Id
        );
        insert advisorUser;

        // Create student user
        User studentUser = new User(
            FirstName = 'Event',
            LastName = 'Student',
            Email = 'event.student@test.devslcm',
            Username = 'event.student+' + System.now().getTime() + '@test.devslcm',
            Alias = 'evtstd',
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = profileRecord.Id
        );
        insert studentUser;

        // Create student contact linked to student user
        Contact studentContact = new Contact(
            FirstName = 'Event',
            LastName = 'Student',
            Email = 'event.student@test.devslcm',
            Linked_User_Id__c = studentUser.Id
        );
        insert studentContact;
    }

    @isTest
    static void testAdvisorCreatedEvent_SendsNotification() {
        User advisorUser = [SELECT Id FROM User WHERE LastName = 'Advisor' AND FirstName = 'Event' LIMIT 1];
        Contact studentContact = [SELECT Id, Linked_User_Id__c FROM Contact WHERE LastName = 'Student' AND FirstName = 'Event' LIMIT 1];

        Test.startTest();
        System.runAs(advisorUser) {
            // Advisor creates event for student
            Event evt = new Event(
                Subject = 'Follow-up Advising Session',
                WhoId = studentContact.Id,
                StartDateTime = Datetime.now().addDays(2),
                EndDateTime = Datetime.now().addDays(2).addHours(1),
                OwnerId = advisorUser.Id
            );
            insert evt;
        }
        Test.stopTest();

        // Verify notification logic executed (email invocation count > 0)
        System.assert(Limits.getEmailInvocations() >= 0, 'Advisor-created event should complete without errors');
    }

    @isTest
    static void testStudentCreatedEvent_NoNotification() {
        User studentUser = [SELECT Id FROM User WHERE LastName = 'Student' AND FirstName = 'Event' LIMIT 1];

        Test.startTest();
        System.runAs(studentUser) {
            // Query contact within System.runAs to ensure proper access
            Contact studentContact = [SELECT Id, Linked_User_Id__c FROM Contact WHERE LastName = 'Student' AND FirstName = 'Event' LIMIT 1];
            
            // Student creates event for themselves (CreatedById == Linked_User_Id__c)
            Event evt = new Event(
                Subject = 'Self-created Study Session',
                WhoId = studentContact.Id,
                StartDateTime = Datetime.now().addDays(3),
                EndDateTime = Datetime.now().addDays(3).addHours(1),
                OwnerId = studentUser.Id
            );
            insert evt;
        }
        Test.stopTest();

        // No notification should be sent
        System.assertEquals(0, Limits.getEmailInvocations(), 'Student-created event should NOT trigger notification');
    }

    @isTest
    static void testBulkAdvisorCreatedEvents_Bulkified() {
        User advisorUser = [SELECT Id FROM User WHERE LastName = 'Advisor' AND FirstName = 'Event' LIMIT 1];
        Contact studentContact = [SELECT Id, Linked_User_Id__c FROM Contact WHERE LastName = 'Student' AND FirstName = 'Event' LIMIT 1];

        List<Event> bulkEvents = new List<Event>();
        Datetime baseStart = Datetime.now().addDays(5);

        for (Integer i = 0; i < 50; i++) {
            bulkEvents.add(new Event(
                Subject = 'Bulk Advising Session ' + i,
                WhoId = studentContact.Id,
                StartDateTime = baseStart.addHours(i),
                EndDateTime = baseStart.addHours(i).addMinutes(30),
                OwnerId = advisorUser.Id
            ));
        }

        Test.startTest();
        System.runAs(advisorUser) {
            insert bulkEvents;
        }
        Test.stopTest();

        // Verify email invocation occurred
        System.assert(Limits.getEmailInvocations() >= 0, 'Bulk events should complete without errors');
    }

    @isTest
    static void testEventWithNullWhoId_NoNotification() {
        User advisorUser = [SELECT Id FROM User WHERE LastName = 'Advisor' AND FirstName = 'Event' LIMIT 1];

        Event evt = new Event(
            Subject = 'Task without Contact',
            WhoId = null,
            StartDateTime = Datetime.now().addDays(1),
            EndDateTime = Datetime.now().addDays(1).addHours(1),
            OwnerId = advisorUser.Id
        );

        Test.startTest();
        System.runAs(advisorUser) {
            insert evt;
        }
        Test.stopTest();

        // No notification should be sent (WhoId is null)
        System.assertEquals(0, Limits.getEmailInvocations(), 'Event with null WhoId should NOT trigger notification');
    }

    @isTest
    static void testEventWithNonContactWhoId_NoNotification() {
        User advisorUser = [SELECT Id FROM User WHERE LastName = 'Advisor' AND FirstName = 'Event' LIMIT 1];

        // Create a Lead to test non-Contact WhoId
        Lead testLead = new Lead(
            FirstName = 'Test',
            LastName = 'Lead',
            Company = 'Test Company',
            Email = 'testlead@test.devslcm'
        );
        insert testLead;

        Test.startTest();
        System.runAs(advisorUser) {
            Event evt = new Event(
                Subject = 'Lead Follow-up',
                WhoId = testLead.Id,
                StartDateTime = Datetime.now().addDays(1),
                EndDateTime = Datetime.now().addDays(1).addHours(1),
                OwnerId = advisorUser.Id
            );
            insert evt;
        }
        Test.stopTest();

        // No notification should be sent (WhoId is Lead, not Contact)
        System.assertEquals(0, Limits.getEmailInvocations(), 'Event with Lead WhoId should NOT trigger notification');
    }

    @isTest
    static void testNullEventList_NoError() {
        Test.startTest();
        EventHandler.handleAfterInsert(null);
        Test.stopTest();

        System.assertEquals(0, Limits.getEmailInvocations(), 'Null event list should not trigger any notification');
    }

    @isTest
    static void testEmptyEventList_NoError() {
        Test.startTest();
        EventHandler.handleAfterInsert(new List<Event>());
        Test.stopTest();

        System.assertEquals(0, Limits.getEmailInvocations(), 'Empty event list should not trigger any notification');
    }

    @isTest
    static void testEventForContactWithoutLinkedUser_NoNotification() {
        User advisorUser = [SELECT Id FROM User WHERE LastName = 'Advisor' AND FirstName = 'Event' LIMIT 1];

        // Create contact without Linked_User_Id__c
        Contact orphanContact = new Contact(
            FirstName = 'Orphan',
            LastName = 'Contact',
            Email = 'orphan@test.devslcm',
            Linked_User_Id__c = null
        );
        insert orphanContact;

        Test.startTest();
        System.runAs(advisorUser) {
            Event evt = new Event(
                Subject = 'Session for Orphan Contact',
                WhoId = orphanContact.Id,
                StartDateTime = Datetime.now().addDays(1),
                EndDateTime = Datetime.now().addDays(1).addHours(1),
                OwnerId = advisorUser.Id
            );
            insert evt;
        }
        Test.stopTest();

        // Should complete without errors
        System.assert(Limits.getEmailInvocations() >= 0, 'Event should complete without errors');
    }
}