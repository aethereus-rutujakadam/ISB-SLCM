/**
 * @description Test class for WorkshopBatchHandler
 * @author DEVSLCM Team
 * @date 2026
 */
@isTest
private class WorkshopBatchHandlerTest {

    @TestSetup
    static void setup() {
        Program program = new Program(Name = 'Batch Handler Program');
        insert program;

        AcademicTerm term = new AcademicTerm(Name = 'Batch Handler Cohort');
        insert term;

        AcademicSession session = new AcademicSession(
            Name = 'Batch Handler Session',
            AcademicTermId = term.Id
        );
        insert session;

        Workshop__c w = new Workshop__c(
            Name = 'Test Workshop',
            Status__c = 'Draft',
            Program__c = program.Id,
            Cohort__c = term.Id,
            Eligible_Term__c = session.Id,
            Total_Sessions__c = 1
        );
        insert w;

        Workshop_Session__c ws = [
            SELECT Id
            FROM Workshop_Session__c
            WHERE Workshop__c = :w.Id
            LIMIT 1
        ];
    }

    @isTest
    static void testDateTimeValidation() {
        Workshop_Session__c ws = [SELECT Id FROM Workshop_Session__c LIMIT 1];

        Workshop_Batch__c b = new Workshop_Batch__c(
            Workshop_Session__c = ws.Id,
            Batch_Label__c      = 'Batch A',
            Start_DateTime__c   = DateTime.now().addHours(2),
            End_DateTime__c     = DateTime.now().addHours(1), // End before start
            Capacity__c         = 20
        );

        Test.startTest();
        Database.SaveResult sr = Database.insert(b, false);
        Test.stopTest();

        System.assert(!sr.isSuccess(), 'Insert should fail due to End before Start');
    }

    @isTest
    static void testAutoAssignBatchLabel() {
        Workshop_Session__c ws = [SELECT Id FROM Workshop_Session__c LIMIT 1];

        Workshop_Batch__c b = new Workshop_Batch__c(
            Workshop_Session__c = ws.Id,
            Start_DateTime__c   = DateTime.now().addDays(1),
            End_DateTime__c     = DateTime.now().addDays(1).addHours(2),
            Capacity__c         = 20
        );

        Test.startTest();
        insert b;
        Test.stopTest();

        b = [SELECT Batch_Label__c FROM Workshop_Batch__c WHERE Id = :b.Id];
        System.assertNotEquals(null, b.Batch_Label__c, 'Batch label should be auto-assigned');
        System.assert(b.Batch_Label__c.startsWith('Batch '), 'Label should start with Batch');
    }

    @isTest
    static void testAutoPopulateWorkshopFromSession() {
        Workshop_Session__c ws = [SELECT Id, Workshop__c FROM Workshop_Session__c LIMIT 1];

        Workshop_Batch__c b = new Workshop_Batch__c(
            Workshop_Session__c = ws.Id,
            Start_DateTime__c   = DateTime.now().addDays(3),
            End_DateTime__c     = DateTime.now().addDays(3).addHours(2),
            Capacity__c         = 10
        );

        Test.startTest();
        insert b;
        Test.stopTest();

        b = [SELECT Workshop__c FROM Workshop_Batch__c WHERE Id = :b.Id];
        System.assertEquals(ws.Workshop__c, b.Workshop__c, 'Workshop should be derived from Workshop Session.');
    }

    @isTest
    static void testStatusSyncToFull() {
        Workshop_Session__c ws = [SELECT Id FROM Workshop_Session__c LIMIT 1];

        Workshop_Batch__c b = new Workshop_Batch__c(
            Workshop_Session__c = ws.Id,
            Batch_Label__c      = 'Batch A',
            Start_DateTime__c   = DateTime.now().addDays(1),
            End_DateTime__c     = DateTime.now().addDays(1).addHours(2),
            Capacity__c         = 2,
            Total_Registered__c = 2
        );
        insert b;

        Test.startTest();
        b.Total_Registered__c = 3;
        update b;
        Test.stopTest();

        b = [SELECT Status__c FROM Workshop_Batch__c WHERE Id = :b.Id];
        System.assertEquals('Full', b.Status__c, 'Status should be Full when capacity reached');
    }

    @isTest
    static void testCancelBatchCancelsRegistrations() {
        Workshop_Session__c ws = [SELECT Id FROM Workshop_Session__c LIMIT 1];
        Workshop__c wk = [SELECT Id FROM Workshop__c LIMIT 1];

        Workshop_Batch__c b = new Workshop_Batch__c(
            Workshop_Session__c = ws.Id,
            Batch_Label__c      = 'Batch A',
            Start_DateTime__c   = DateTime.now().addDays(1),
            End_DateTime__c     = DateTime.now().addDays(1).addHours(2),
            Capacity__c         = 10
        );
        insert b;

        wk.Status__c = 'Published';
        update wk;

        Contact student = new Contact(LastName = 'TestStudent', Primary_Campus__c = null);
        insert student;

        Workshop_Registration__c reg = new Workshop_Registration__c(
            Student__c          = student.Id,
            Batch_Label__c      = 'Batch A',
            Workshop__c         = wk.Id,
            Status__c           = 'Registered',
            Registration_Date__c = Date.today()
        );
        insert reg;

        Test.startTest();
        b.Status__c = 'Cancelled';
        update b;
        Test.stopTest();

        reg = [SELECT Status__c FROM Workshop_Registration__c WHERE Id = :reg.Id];
        System.assertEquals('Not Registered', reg.Status__c, 'Registration should be cancelled');
    }
}