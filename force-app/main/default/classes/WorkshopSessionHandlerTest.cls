/**
 * @description Test class for WorkshopSessionHandler
 * @author DEVSLCM Team
 * @date 2026
 */
@isTest
private class WorkshopSessionHandlerTest {

    @TestSetup
    static void setup() {
        Program program = new Program(Name = 'Session Handler Program');
        insert program;

        AcademicTerm term = new AcademicTerm(Name = 'Session Handler Cohort');
        insert term;

        AcademicSession session = new AcademicSession(
            Name = 'Session Handler Session',
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

        Workshop_Batch__c b1 = new Workshop_Batch__c(
            Workshop_Session__c = ws.Id,
            Batch_Label__c      = 'Batch A',
            Start_DateTime__c   = DateTime.now().addDays(1),
            End_DateTime__c     = DateTime.now().addDays(1).addHours(2),
            Capacity__c         = 10
        );
        Workshop_Batch__c b2 = new Workshop_Batch__c(
            Workshop_Session__c = ws.Id,
            Batch_Label__c      = 'Batch B',
            Start_DateTime__c   = DateTime.now().addDays(1).addHours(3),
            End_DateTime__c     = DateTime.now().addDays(1).addHours(5),
            Capacity__c         = 10
        );
        insert new List<Workshop_Batch__c>{b1, b2};
    }

    @isTest
    static void testCancelSessionCascadesToBatches() {
        Workshop_Session__c ws = [SELECT Id FROM Workshop_Session__c LIMIT 1];

        Test.startTest();
        ws.Status__c = 'Cancelled';
        update ws;
        Test.stopTest();

        List<Workshop_Batch__c> batches = [
            SELECT Status__c FROM Workshop_Batch__c WHERE Workshop_Session__c = :ws.Id
        ];
        for (Workshop_Batch__c b : batches) {
            System.assertEquals('Cancelled', b.Status__c, 'All batches should be cancelled when session is cancelled');
        }
    }

    @isTest
    static void testNonCancelUpdateDoesNotAffectBatches() {
        Workshop_Session__c ws = [SELECT Id FROM Workshop_Session__c LIMIT 1];

        Test.startTest();
        ws.Status__c  = 'Completed';
        ws.Description__c = 'Updated description';
        update ws;
        Test.stopTest();

        // Batches should NOT be cancelled
        Integer openBatches = [
            SELECT COUNT() FROM Workshop_Batch__c
            WHERE Workshop_Session__c = :ws.Id AND Status__c = 'Open'
        ];
        System.assertEquals(2, openBatches, 'Completing a session should not auto-cancel batches.');
    }
}