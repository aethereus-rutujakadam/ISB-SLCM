/**
 * @description Test class for WorkshopPortalController (student-facing)
 * @author DEVSLCM Team
 * @date 2026
 */
@isTest
private class WorkshopPortalControllerTest {

    @TestSetup
    static void setup() {
        Contact studentContact = new Contact(LastName = 'PortalStudent');
        insert studentContact;

        Program studentProgram = new Program(
            Name = 'Portal Test Program'
        );
        insert studentProgram;

        ProgramEnrollment pe = new ProgramEnrollment(
            ContactId = studentContact.Id,
            ProgramId = studentProgram.Id,
            IsActive  = true
        );
        insert pe;

        AcademicTerm term = new AcademicTerm(Name = 'Portal Term');
        insert term;

        AcademicSession enrolledSession = new AcademicSession(
            Name = 'Portal Enrolled Session',
            AcademicTermId = term.Id
        );
        insert enrolledSession;

        Enrollment_Session__c es = new Enrollment_Session__c(
            Program_Enrollment__c = pe.Id,
            Academic_Session__c   = enrolledSession.Id,
            Status__c             = 'Registered',
            Session_Start__c      = System.now()
        );
        insert es;

        Workshop__c w = new Workshop__c(
            Name             = 'Portal Test Workshop',
            Status__c        = 'Published',
            Program__c       = studentProgram.Id,
            Cohort__c        = term.Id,
            Eligible_Term__c = enrolledSession.Id,
            Total_Sessions__c = 1
        );
        insert w;

        Workshop_Session__c ws = new Workshop_Session__c(
            Name        = 'Session 1',
            Workshop__c = w.Id,
            Status__c   = 'Scheduled'
        );
        insert ws;

        Workshop_Batch__c b = new Workshop_Batch__c(
            Workshop_Session__c      = ws.Id,
            Batch_Label__c           = 'Batch A',
            Start_DateTime__c        = DateTime.now().addDays(1),
            End_DateTime__c          = DateTime.now().addDays(1).addHours(2),
            Capacity__c              = 5,
            Overbooking_Threshold__c = 1
        );
        insert b;
    }

    private static void setPortalStudentContext() {
        Contact studentContact = [SELECT Id FROM Contact WHERE LastName = 'PortalStudent' LIMIT 1];
        WorkshopPortalController.testStudentContactId = studentContact.Id;
    }

    @isTest
    static void testGetEligibleWorkshopsNoTerm() {
        setPortalStudentContext();
        Test.startTest();
        List<WorkshopPortalController.WorkshopPortalWrapper> result =
            WorkshopPortalController.getEligibleWorkshops(null);
        Test.stopTest();
        System.assert(!result.isEmpty(), 'Should return active workshops');
    }

    @isTest
    static void testRegisterForWorkshop() {
        setPortalStudentContext();
        Workshop__c w = [SELECT Id FROM Workshop__c LIMIT 1];

        Test.startTest();
        WorkshopPortalController.RegistrationResult result =
            WorkshopPortalController.registerForWorkshop(w.Id, 'Batch A');
        Test.stopTest();

        System.assert(result.success, 'Registration should succeed');
        System.assertEquals('Registered', result.status, 'Status should be Registered');
        System.assert(!result.showWarning, 'No warning when seats available');
    }

    @isTest
    static void testRegisterForWorkshop_noRegistrationRequired() {
        setPortalStudentContext();
        AcademicSession enrolledSession = [SELECT Id, AcademicTermId FROM AcademicSession WHERE Name = 'Portal Enrolled Session' LIMIT 1];
        Program enrolledProgram = [SELECT Id FROM Program WHERE Name = 'Portal Test Program' LIMIT 1];

        Workshop__c viewOnlyWorkshop = new Workshop__c(
            Name = 'Read-Only Workshop',
            Status__c = 'Published',
            Program__c = enrolledProgram.Id,
            Cohort__c = enrolledSession.AcademicTermId,
            Eligible_Term__c = enrolledSession.Id,
            Registration_Required__c = false,
            Total_Sessions__c = 1
        );
        insert viewOnlyWorkshop;

        Test.startTest();
        WorkshopPortalController.RegistrationResult result =
            WorkshopPortalController.registerForWorkshop(viewOnlyWorkshop.Id, 'Batch A');
        Test.stopTest();

        System.assertEquals(false, result.success, 'Registration should be blocked when no registration is required.');
        System.assert(result.message != null && result.message.contains('does not require registration'));
    }

    @isTest
    static void testRegisterShowsWarningWhenWaitlisted() {
        Workshop__c w = [SELECT Id FROM Workshop__c LIMIT 1];
        Workshop_Batch__c b = [SELECT Id, Capacity__c FROM Workshop_Batch__c LIMIT 1];

        // Pre-fill the batch to capacity using direct DML (bypass trigger student check)
        List<Contact> contacts = new List<Contact>();
        for (Integer i = 0; i < 5; i++) {
            contacts.add(new Contact(LastName = 'Filler' + i));
        }
        insert contacts;

        List<Workshop_Registration__c> regs = new List<Workshop_Registration__c>();
        for (Contact c : contacts) {
            regs.add(new Workshop_Registration__c(
                Student__c          = c.Id,
                Workshop__c         = w.Id,
                Batch_Label__c      = 'Batch A',
                Status__c           = 'Registered',
                Registration_Date__c = Date.today()
            ));
        }
        insert regs;

        // Update batch total directly
        b.Total_Registered__c = 5;
        update b;

        setPortalStudentContext();
        Test.startTest();
        WorkshopPortalController.RegistrationResult result =
            WorkshopPortalController.registerForWorkshop(w.Id, 'Batch A');
        Test.stopTest();

        System.assert(result.success, 'Should succeed within overbooking threshold');
        System.assertEquals('Waitlisted', result.status, 'Should be Waitlisted');
        System.assert(result.showWarning, 'Warning should be shown');
    }

    @isTest
    static void testGetMyRegistrations() {
        setPortalStudentContext();
        Workshop__c w = [SELECT Id FROM Workshop__c LIMIT 1];

        WorkshopPortalController.registerForWorkshop(w.Id, 'Batch A');
        Test.startTest();
        List<Workshop_Registration__c> regs = WorkshopPortalController.getMyRegistrations();
        Test.stopTest();
        System.assertEquals(1, regs.size(), 'Should return the student registration');
    }

    @isTest
    static void testCancelRegistration() {
        setPortalStudentContext();
        Workshop__c w = [SELECT Id FROM Workshop__c LIMIT 1];

        WorkshopPortalController.registerForWorkshop(w.Id, 'Batch A');
        Workshop_Registration__c reg = [
            SELECT Id FROM Workshop_Registration__c
            WHERE Workshop__c = :w.Id
            LIMIT 1
        ];

        Test.startTest();
        WorkshopPortalController.cancelRegistration(reg.Id);
        Test.stopTest();

        reg = [SELECT Status__c FROM Workshop_Registration__c WHERE Id = :reg.Id];
        System.assertEquals('Not Registered', reg.Status__c, 'Registration should be cancelled');
    }

    @isTest
    static void testGetAcademicTerms() {
        setPortalStudentContext();
        Test.startTest();
        List<AcademicSession> terms = WorkshopPortalController.getAcademicTerms();
        Test.stopTest();
        System.assertEquals(1, terms.size(), 'Should only return terms from registered enrollment sessions.');
        System.assertEquals('Portal Enrolled Session', terms[0].Name);
    }

    @isTest
    static void testGetEligibleWorkshopsIgnoresNonEnrolledTerm() {
        setPortalStudentContext();

        AcademicTerm otherTerm = new AcademicTerm(Name = 'Other Term');
        insert otherTerm;
        AcademicSession otherSession = new AcademicSession(
            Name = 'Other Session',
            AcademicTermId = otherTerm.Id
        );
        insert otherSession;

        Test.startTest();
        List<WorkshopPortalController.WorkshopPortalWrapper> result =
            WorkshopPortalController.getEligibleWorkshops(otherSession.Id);
        Test.stopTest();
        System.assertEquals(0, result.size(), 'Should not return workshops for non-enrolled terms.');
    }

    @isTest
    static void testGetEligibleWorkshopsIgnoresNonEnrolledProgram() {
        setPortalStudentContext();
        AcademicSession enrolledSession = [SELECT Id FROM AcademicSession WHERE Name = 'Portal Enrolled Session' LIMIT 1];

        // Create a different program and a workshop tied to it — student should NOT see this.
        Program otherProg = new Program(Name = 'Other Program');
        insert otherProg;

        Workshop__c otherWs = new Workshop__c(
            Name             = 'Other Program Workshop',
            Status__c        = 'Published',
            Eligible_Term__c = enrolledSession.Id,
            Program__c       = otherProg.Id,
            Cohort__c        = [SELECT AcademicTermId FROM AcademicSession WHERE Id = :enrolledSession.Id LIMIT 1].AcademicTermId,
            Total_Sessions__c = 1
        );
        insert otherWs;

        Test.startTest();
        List<WorkshopPortalController.WorkshopPortalWrapper> result =
            WorkshopPortalController.getEligibleWorkshops(enrolledSession.Id);
        Test.stopTest();
        // Only the workshop for the enrolled program should be returned, not the other-program one.
        for (WorkshopPortalController.WorkshopPortalWrapper w : result) {
            System.assertNotEquals(otherWs.Id, w.workshop.Id, 'Workshop for a non-enrolled program must not be returned.');
        }
    }

    @isTest
    static void testGetEligibleWorkshopsHidesCohortMismatch() {
        setPortalStudentContext();
        AcademicSession enrolledSession = [SELECT Id FROM AcademicSession WHERE Name = 'Portal Enrolled Session' LIMIT 1];
        Program enrolledProgram = [SELECT Id FROM Program WHERE Name = 'Portal Test Program' LIMIT 1];

        AcademicTerm otherTerm = new AcademicTerm(Name = 'Other Cohort');
        insert otherTerm;

        Workshop__c mismatchWs = new Workshop__c(
            Name             = 'Cohort Mismatch Workshop',
            Status__c        = 'Published',
            Program__c       = enrolledProgram.Id,
            Cohort__c        = otherTerm.Id,
            Eligible_Term__c = enrolledSession.Id,
            Total_Sessions__c = 1
        );
        insert mismatchWs;

        Test.startTest();
        List<WorkshopPortalController.WorkshopPortalWrapper> result =
            WorkshopPortalController.getEligibleWorkshops(enrolledSession.Id);
        Test.stopTest();

        for (WorkshopPortalController.WorkshopPortalWrapper w : result) {
            System.assertNotEquals(
                mismatchWs.Id,
                w.workshop.Id,
                'Workshop for a non-enrolled cohort must not be returned.'
            );
        }
    }

    @isTest
    static void testCreateWorkshopFailsWithoutRequiredEligibility() {
        Workshop__c invalid = new Workshop__c(
            Name = 'Invalid Workshop',
            Status__c = 'Published'
        );

        Test.startTest();
        Database.SaveResult saveResult = Database.insert(invalid, false);
        Test.stopTest();

        System.assert(!saveResult.isSuccess(), 'Workshop create should fail when required eligibility fields are missing.');
    }
}