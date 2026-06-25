/**
 * @description Test class for AdvisorAvailabilityService — 100% code coverage.
 *              Covers: getAvailableSlots (null guards, busy slot blocking,
 *              approved-appt blocking, all-free slots, custom duration).
 * @author DEVSLCM Team
 * @date 2026
 */
@isTest
private class AdvisorAvailabilityServiceTest {

    // ─────────────────────────────────────────────────────────────────────────
    //  T E S T   D A T A   S E T U P
    // ─────────────────────────────────────────────────────────────────────────

    @testSetup
    static void setupTestData() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        User advisorUser = new User(
            FirstName='Advisor', LastName='Avail',
            Email='advisor_avail@devslcm.test',
            Username='advisor_avail@devslcm.test.av',
            Alias='advav',
            TimeZoneSidKey='America/New_York', LocaleSidKey='en_US',
            EmailEncodingKey='UTF-8', LanguageLocaleKey='en_US',
            ProfileId=p.Id
        );
        insert advisorUser;

        Contact advisorContact = new Contact(
            FirstName='Advisor', LastName='Avail',
            Email='advisor_avail_c@devslcm.test',
            Linked_User_Id__c=advisorUser.Id
        );
        insert advisorContact;
        advisorUser.ContactId = advisorContact.Id;
        update advisorUser;
    }

    static User getAdvisorUser() {
        return [SELECT Id, ContactId FROM User
                WHERE Username = 'advisor_avail@devslcm.test.av' LIMIT 1];
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  T E S T   M E T H O D S
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testGetAvailableSlots_nullAdvisorId() {
        Test.startTest();
        List<AdvisorAvailabilityService.TimeSlotWrapper> slots =
            AdvisorAvailabilityService.getAvailableSlots(null, '2026-05-01', 30);
        Test.stopTest();

        System.assertEquals(0, slots.size(), 'Null advisorUserId should return empty list');
    }

    @isTest
    static void testGetAvailableSlots_blankDate() {
        User adv = getAdvisorUser();
        Test.startTest();
        List<AdvisorAvailabilityService.TimeSlotWrapper> slots =
            AdvisorAvailabilityService.getAvailableSlots(adv.Id, '', 30);
        Test.stopTest();

        System.assertEquals(0, slots.size(), 'Blank date should return empty list');
    }

    @isTest
    static void testGetAvailableSlots_nullDurationDefaultsTo30() {
        User adv = getAdvisorUser();
        // A future date with no conflicts → 9 hrs / 30 min = 18 slots
        String futureDate = Date.today().addDays(14).format();
        // Convert to YYYY-MM-DD
        Date fd = Date.today().addDays(14);
        String dateStr = fd.year() + '-'
            + (fd.month()  < 10 ? '0' : '') + fd.month()  + '-'
            + (fd.day()    < 10 ? '0' : '') + fd.day();

        Test.startTest();
        List<AdvisorAvailabilityService.TimeSlotWrapper> slots =
            AdvisorAvailabilityService.getAvailableSlots(adv.Id, dateStr, null);
        Test.stopTest();

        System.assertEquals(18, slots.size(), '8AM-5PM / 30min = 18 slots');
        for (AdvisorAvailabilityService.TimeSlotWrapper s : slots) {
            System.assertEquals(true,  s.isAvailable, 'All slots should be free with no events');
            System.assertNotEquals(null, s.label);
            System.assertNotEquals(null, s.startISO);
            System.assertNotEquals(null, s.endISO);
        }
    }

    @isTest
    static void testGetAvailableSlots_busyEventBlocksSlot() {
        User adv = getAdvisorUser();
        Date targetDate = Date.today().addDays(10);
        String dateStr  = targetDate.year() + '-'
            + (targetDate.month() < 10 ? '0' : '') + targetDate.month() + '-'
            + (targetDate.day()   < 10 ? '0' : '') + targetDate.day();

        // Create a Busy event from 09:00–09:30
        Datetime evtStart = Datetime.newInstance(targetDate, Time.newInstance(9,  0, 0, 0));
        Datetime evtEnd   = Datetime.newInstance(targetDate, Time.newInstance(9, 30, 0, 0));

        System.runAs(adv) {
            Event busyEvt = new Event(
                OwnerId       = adv.Id,
                StartDateTime = evtStart,
                EndDateTime   = evtEnd,
                DurationInMinutes = 30,
                Subject       = 'Block Test',
                ShowAs        = 'Busy'
            );
            insert busyEvt;
        }

        Test.startTest();
        List<AdvisorAvailabilityService.TimeSlotWrapper> slots =
            AdvisorAvailabilityService.getAvailableSlots(adv.Id, dateStr, 30);
        Test.stopTest();

        System.assertEquals(18, slots.size(), 'Total slot count should still be 18');
        Boolean foundBlockedSlot = false;
        for (AdvisorAvailabilityService.TimeSlotWrapper s : slots) {
            if (s.startISO.contains('T09:00:00')) {
                System.assertEquals(false, s.isAvailable, '09:00 slot should be blocked');
                foundBlockedSlot = true;
            }
        }
        System.assert(foundBlockedSlot, 'Should have found the 09:00 slot');
    }

    @isTest
    static void testGetAvailableSlots_outOfOfficeBlocksSlot() {
        User adv = getAdvisorUser();
        Date targetDate = Date.today().addDays(11);
        String dateStr  = targetDate.year() + '-'
            + (targetDate.month() < 10 ? '0' : '') + targetDate.month() + '-'
            + (targetDate.day()   < 10 ? '0' : '') + targetDate.day();

        System.runAs(adv) {
            Event oooEvt = new Event(
                OwnerId       = adv.Id,
                StartDateTime = Datetime.newInstance(targetDate, Time.newInstance(10, 0, 0, 0)),
                EndDateTime   = Datetime.newInstance(targetDate, Time.newInstance(10,30, 0, 0)),
                DurationInMinutes = 30,
                Subject       = 'OOO Test',
                ShowAs        = 'OutOfOffice'
            );
            insert oooEvt;
        }

        Test.startTest();
        List<AdvisorAvailabilityService.TimeSlotWrapper> slots =
            AdvisorAvailabilityService.getAvailableSlots(adv.Id, dateStr, 30);
        Test.stopTest();

        for (AdvisorAvailabilityService.TimeSlotWrapper s : slots) {
            if (s.startISO.contains('T10:00:00')) {
                System.assertEquals(false, s.isAvailable, '10:00 OOO slot should be blocked');
            }
        }
    }

    @isTest
    static void testGetAvailableSlots_approvedApptBlocksSlot() {
        User adv = getAdvisorUser();
        Date targetDate = Date.today().addDays(12);
        String dateStr  = targetDate.year() + '-'
            + (targetDate.month() < 10 ? '0' : '') + targetDate.month() + '-'
            + (targetDate.day()   < 10 ? '0' : '') + targetDate.day();

        // Create an approved appointment request in the 11:00–11:30 slot
        Appointment_Request__c appt = new Appointment_Request__c(
            Primary_Advisor__c  = adv.Id,
            Status__c           = 'Approved',
            Request_Type__c     = 'general',
            Reason__c           = 'Approved block test',
            Start_DateTime__c   = Datetime.newInstance(targetDate, Time.newInstance(11,  0, 0, 0)),
            End_DateTime__c     = Datetime.newInstance(targetDate, Time.newInstance(11, 30, 0, 0)),
            Minutes_of_Meeting__c = '30'
        );
        insert appt;

        Test.startTest();
        List<AdvisorAvailabilityService.TimeSlotWrapper> slots =
            AdvisorAvailabilityService.getAvailableSlots(adv.Id, dateStr, 30);
        Test.stopTest();

        for (AdvisorAvailabilityService.TimeSlotWrapper s : slots) {
            if (s.startISO.contains('T11:00:00')) {
                System.assertEquals(false, s.isAvailable, 'Approved-appt 11:00 slot should be blocked');
            }
        }
    }

    @isTest
    static void testGetAvailableSlots_customDuration60min() {
        User adv = getAdvisorUser();
        Date targetDate = Date.today().addDays(15);
        String dateStr  = targetDate.year() + '-'
            + (targetDate.month() < 10 ? '0' : '') + targetDate.month() + '-'
            + (targetDate.day()   < 10 ? '0' : '') + targetDate.day();

        Test.startTest();
        List<AdvisorAvailabilityService.TimeSlotWrapper> slots =
            AdvisorAvailabilityService.getAvailableSlots(adv.Id, dateStr, 60);
        Test.stopTest();

        // 8AM-5PM / 60min = 9 slots
        System.assertEquals(9, slots.size(), '8AM-5PM / 60min = 9 slots');
    }

    @isTest
    static void testGetAvailableSlots_zeroDurationDefaultsTo30() {
        User adv = getAdvisorUser();
        Date targetDate = Date.today().addDays(16);
        String dateStr  = targetDate.year() + '-'
            + (targetDate.month() < 10 ? '0' : '') + targetDate.month() + '-'
            + (targetDate.day()   < 10 ? '0' : '') + targetDate.day();

        Test.startTest();
        List<AdvisorAvailabilityService.TimeSlotWrapper> slots =
            AdvisorAvailabilityService.getAvailableSlots(adv.Id, dateStr, 0);
        Test.stopTest();

        System.assertEquals(18, slots.size(), 'Zero duration should default to 30min → 18 slots');
    }
}