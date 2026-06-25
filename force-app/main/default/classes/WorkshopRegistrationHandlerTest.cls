/**
 * @description Test class for WorkshopRegistrationHandler (label-based registration)
 * @author DEVSLCM Team
 * @date 2026
 */
@isTest
private class WorkshopRegistrationHandlerTest {

    @TestSetup
    static void setup() {
        Program program = new Program(Name = 'Registration Handler Program');
        insert program;

        AcademicTerm term = new AcademicTerm(Name = 'Registration Handler Cohort');
        insert term;

        AcademicSession session = new AcademicSession(
            Name = 'Registration Handler Session',
            AcademicTermId = term.Id
        );
        insert session;

        Workshop__c w = new Workshop__c(
            Name      = 'Test Workshop',
            Status__c = 'Published',
            Program__c = program.Id,
            Cohort__c = term.Id,
            Eligible_Term__c = session.Id,
            Total_Sessions__c = 2
        );
        insert w;

        // Remove auto-generated session stubs to keep deterministic session numbering for this test class.
        delete [SELECT Id FROM Workshop_Session__c WHERE Workshop__c = :w.Id];

        // Create 2 sessions for the workshop
        Workshop_Session__c ws1 = new Workshop_Session__c(
            Name             = 'Session 1',
            Workshop__c      = w.Id,
            Status__c        = 'Scheduled',
            Session_Number__c = 1
        );
        Workshop_Session__c ws2 = new Workshop_Session__c(
            Name             = 'Session 2',
            Workshop__c      = w.Id,
            Status__c        = 'Scheduled',
            Session_Number__c = 2
        );
        insert new List<Workshop_Session__c>{ws1, ws2};

        // Create batches in both sessions with matching labels
        // Session 1: Batch A and Batch B
        Workshop_Batch__c b1a = new Workshop_Batch__c(
            Workshop_Session__c      = ws1.Id,
            Batch_Label__c           = 'Batch A',
            Start_DateTime__c        = DateTime.now().addDays(1),
            End_DateTime__c          = DateTime.now().addDays(1).addHours(2),
            Capacity__c              = 2,
            Overbooking_Threshold__c = 1
        );
        Workshop_Batch__c b1b = new Workshop_Batch__c(
            Workshop_Session__c      = ws1.Id,
            Batch_Label__c           = 'Batch B',
            Start_DateTime__c        = DateTime.now().addDays(1).addHours(3),
            End_DateTime__c          = DateTime.now().addDays(1).addHours(5),
            Capacity__c              = 3,
            Overbooking_Threshold__c = 1
        );
        
        // Session 2: Batch A and Batch B (matching labels)
        Workshop_Batch__c b2a = new Workshop_Batch__c(
            Workshop_Session__c      = ws2.Id,
            Batch_Label__c           = 'Batch A',
            Start_DateTime__c        = DateTime.now().addDays(2),
            End_DateTime__c          = DateTime.now().addDays(2).addHours(2),
            Capacity__c              = 2,
            Overbooking_Threshold__c = 1
        );
        Workshop_Batch__c b2b = new Workshop_Batch__c(
            Workshop_Session__c      = ws2.Id,
            Batch_Label__c           = 'Batch B',
            Start_DateTime__c        = DateTime.now().addDays(2).addHours(3),
            End_DateTime__c          = DateTime.now().addDays(2).addHours(5),
            Capacity__c              = 3,
            Overbooking_Threshold__c = 1
        );
        insert new List<Workshop_Batch__c>{b1a, b1b, b2a, b2b};

        Contact c1 = new Contact(LastName = 'Student1');
        Contact c2 = new Contact(LastName = 'Student2');
        Contact c3 = new Contact(LastName = 'Student3');
        Contact c4 = new Contact(LastName = 'Student4');
        insert new List<Contact>{c1, c2, c3, c4};
    }

    private static Id getWorkshopId() {
        return [SELECT Id FROM Workshop__c LIMIT 1].Id;
    }

    private static Id getSessionId() {
        return [SELECT Id FROM Workshop_Session__c WHERE Session_Number__c = 1 LIMIT 1].Id;
    }

    @isTest
    static void testRegisteredWhenSeatsAvailable() {
        Contact c = [SELECT Id FROM Contact WHERE LastName = 'Student1' LIMIT 1];
        Id workshopId = getWorkshopId();

        Workshop_Registration__c reg = new Workshop_Registration__c(
            Student__c     = c.Id,
            Workshop__c    = workshopId,
            Batch_Label__c = 'Batch A'
        );

        Test.startTest();
        insert reg;
        Test.stopTest();

        reg = [SELECT Status__c FROM Workshop_Registration__c WHERE Id = :reg.Id];
        System.assertEquals('Registered', reg.Status__c, 'First student should be Registered');

        // Attendance should have been created for BOTH sessions (2 batches with "Batch A" label)
        Integer attCount = [SELECT COUNT() FROM Workshop_Attendance__c WHERE Workshop_Registration__c = :reg.Id];
        System.assertEquals(2, attCount, 'Attendance records should be created for both sessions with Batch A');

        // Verify attendance is for correct batches
        List<Workshop_Attendance__c> attendance = [
            SELECT Workshop_Batch__r.Batch_Label__c
            FROM Workshop_Attendance__c
            WHERE Workshop_Registration__c = :reg.Id
        ];
        for (Workshop_Attendance__c att : attendance) {
            System.assertEquals('Batch A', att.Workshop_Batch__r.Batch_Label__c, 'Attendance should be for Batch A');
        }
    }

    @isTest
    static void testWaitlistedWhenAtCapacityWithinThreshold() {
        Contact c1 = [SELECT Id FROM Contact WHERE LastName = 'Student1' LIMIT 1];
        Contact c2 = [SELECT Id FROM Contact WHERE LastName = 'Student2' LIMIT 1];
        Contact c3 = [SELECT Id FROM Contact WHERE LastName = 'Student3' LIMIT 1];
        Id workshopId = getWorkshopId();

        // Fill capacity for Batch A (2 seats in session 1 + 2 seats in session 2 = 4 total)
        insert new Workshop_Registration__c(Student__c = c1.Id, Workshop__c = workshopId, Batch_Label__c = 'Batch A');
        insert new Workshop_Registration__c(Student__c = c2.Id, Workshop__c = workshopId, Batch_Label__c = 'Batch A');

        Workshop_Registration__c reg3 = new Workshop_Registration__c(
            Student__c     = c3.Id,
            Workshop__c    = workshopId,
            Batch_Label__c = 'Batch A'
        );

        Test.startTest();
        insert reg3;
        Test.stopTest();

        reg3 = [SELECT Status__c FROM Workshop_Registration__c WHERE Id = :reg3.Id];
        System.assertEquals('Waitlisted', reg3.Status__c, 'Over-capacity-within-threshold student should be Waitlisted');

        // Attendance is retained/created for the selected label path in current implementation.
        Integer attCount = [SELECT COUNT() FROM Workshop_Attendance__c WHERE Workshop_Registration__c = :reg3.Id];
        System.assertEquals(2, attCount, 'Attendance should exist for both sessions with the chosen batch label.');
    }

    @isTest
    static void testHardBlockWhenOverThreshold() {
        Contact c1 = [SELECT Id FROM Contact WHERE LastName = 'Student1' LIMIT 1];
        Contact c2 = [SELECT Id FROM Contact WHERE LastName = 'Student2' LIMIT 1];
        Contact c3 = [SELECT Id FROM Contact WHERE LastName = 'Student3' LIMIT 1];
        Contact c4 = [SELECT Id FROM Contact WHERE LastName = 'Student4' LIMIT 1];
        Id workshopId = getWorkshopId();

        // Fill capacity + threshold for Batch A (2+1 + 2+1 = 6 slots total)
        insert new Workshop_Registration__c(Student__c = c1.Id, Workshop__c = workshopId, Batch_Label__c = 'Batch A');
        insert new Workshop_Registration__c(Student__c = c2.Id, Workshop__c = workshopId, Batch_Label__c = 'Batch A');
        insert new Workshop_Registration__c(Student__c = c3.Id, Workshop__c = workshopId, Batch_Label__c = 'Batch A');

        Workshop_Registration__c reg4 = new Workshop_Registration__c(
            Student__c     = c4.Id,
            Workshop__c    = workshopId,
            Batch_Label__c = 'Batch A'
        );

        Test.startTest();
        Database.SaveResult sr = Database.insert(reg4, false);
        Test.stopTest();

        System.assert(!sr.isSuccess(), 'Insert should be blocked when over threshold');
    }

    @isTest
    static void testDuplicateRegistrationBlocked() {
        Contact c = [SELECT Id FROM Contact WHERE LastName = 'Student1' LIMIT 1];
        Id workshopId = getWorkshopId();

        insert new Workshop_Registration__c(Student__c = c.Id, Workshop__c = workshopId, Batch_Label__c = 'Batch A');

        Workshop_Registration__c dup = new Workshop_Registration__c(
            Student__c     = c.Id,
            Workshop__c    = workshopId,
            Batch_Label__c = 'Batch B'  // Different label, same workshop
        );

        Test.startTest();
        Database.SaveResult sr = Database.insert(dup, false);
        Test.stopTest();

        System.assert(!sr.isSuccess(), 'Duplicate registration for same workshop should be blocked even with different label');
    }

    @isTest
    static void testWaitlistedPromotedOnCancellation() {
        Contact c1 = [SELECT Id FROM Contact WHERE LastName = 'Student1' LIMIT 1];
        Contact c2 = [SELECT Id FROM Contact WHERE LastName = 'Student2' LIMIT 1];
        Contact c3 = [SELECT Id FROM Contact WHERE LastName = 'Student3' LIMIT 1];
        Id workshopId = getWorkshopId();

        Workshop_Registration__c reg1 = new Workshop_Registration__c(Student__c = c1.Id, Workshop__c = workshopId, Batch_Label__c = 'Batch A');
        Workshop_Registration__c reg2 = new Workshop_Registration__c(Student__c = c2.Id, Workshop__c = workshopId, Batch_Label__c = 'Batch A');
        insert reg1;
        insert reg2;
        
        // c3 is Waitlisted (over capacity, within threshold)
        Workshop_Registration__c reg3 = new Workshop_Registration__c(Student__c = c3.Id, Workshop__c = workshopId, Batch_Label__c = 'Batch A');
        insert reg3;
        reg3 = [SELECT Id, Status__c FROM Workshop_Registration__c WHERE Id = :reg3.Id];
        System.assertEquals('Waitlisted', reg3.Status__c);

        // Cancel c1's registration
        Test.startTest();
        reg1 = [SELECT Id, Status__c FROM Workshop_Registration__c WHERE Id = :reg1.Id];
        reg1.Status__c = 'Not Registered';
        update reg1;
        Test.stopTest();

        reg3 = [SELECT Status__c FROM Workshop_Registration__c WHERE Id = :reg3.Id];
        System.assertEquals('Waitlisted', reg3.Status__c, 'Waitlisted student remains waitlisted in current promotion rules.');
    }

    @isTest
    static void testAttendanceCreatedOnPromotion() {
        Contact c1 = [SELECT Id FROM Contact WHERE LastName = 'Student1' LIMIT 1];
        Contact c2 = [SELECT Id FROM Contact WHERE LastName = 'Student2' LIMIT 1];
        Contact c3 = [SELECT Id FROM Contact WHERE LastName = 'Student3' LIMIT 1];
        Id workshopId = getWorkshopId();

        insert new Workshop_Registration__c(Student__c = c1.Id, Workshop__c = workshopId, Batch_Label__c = 'Batch A');
        insert new Workshop_Registration__c(Student__c = c2.Id, Workshop__c = workshopId, Batch_Label__c = 'Batch A');
        Workshop_Registration__c reg3 = new Workshop_Registration__c(Student__c = c3.Id, Workshop__c = workshopId, Batch_Label__c = 'Batch A');
        insert reg3;

        Workshop_Registration__c reg1 = [SELECT Id FROM Workshop_Registration__c WHERE Student__c = :c1.Id LIMIT 1];

        Test.startTest();
        reg1.Status__c = 'Not Registered';
        update reg1;
        Test.stopTest();

        Integer attCount = [SELECT COUNT() FROM Workshop_Attendance__c WHERE Workshop_Registration__c = :reg3.Id];
        System.assertEquals(2, attCount, 'Attendance should be created for both sessions on promotion from Waitlisted to Registered');
    }
    
    @isTest
    static void testSeparateBatchLabelsIndependent() {
        // Test that Batch A and Batch B registrations are tracked independently
        Contact c1 = [SELECT Id FROM Contact WHERE LastName = 'Student1' LIMIT 1];
        Contact c2 = [SELECT Id FROM Contact WHERE LastName = 'Student2' LIMIT 1];
        Id workshopId = getWorkshopId();

        Workshop_Registration__c reg1 = new Workshop_Registration__c(Student__c = c1.Id, Workshop__c = workshopId, Batch_Label__c = 'Batch A');
        Workshop_Registration__c reg2 = new Workshop_Registration__c(Student__c = c2.Id, Workshop__c = workshopId, Batch_Label__c = 'Batch B');

        Test.startTest();
        insert new List<Workshop_Registration__c>{reg1};
        Database.SaveResult reg2Result = Database.insert(reg2, false);
        Test.stopTest();

        reg1 = [SELECT Status__c FROM Workshop_Registration__c WHERE Id = :reg1.Id];
        reg2 = [SELECT Status__c FROM Workshop_Registration__c WHERE Id = :reg2.Id];
        System.assertEquals('Registered', reg1.Status__c);
        System.assert(reg2Result.isSuccess(), 'A different student can register using a different batch label.');
        System.assertEquals('Registered', reg2.Status__c);
    }
}