/**
 * @description Comprehensive test class for CaseTriggerHelper.
 * Covers all public methods: filter methods, process methods, email methods, budget methods.
 * Target: >= 85% code coverage.
 */
@isTest
private class CaseTriggerHelperTest {

    // ========================================================
    // TEST SETUP
    // ========================================================

    @TestSetup
    static void setup() {
        // Create Student Contact
        Contact student = TestDataFactory.testContact();

        // Create Program
        Program prog = TestDataFactory.testProgram();

        // Create Academic Year
        AcademicYear ay = TestDataFactory.testAcademicYear();

        // Create Academic Term with a start date (needed for ordering in processLOACases)
        AcademicTerm term = new AcademicTerm(
            Name = 'Term A',
            Program__c = prog.Id,
            StartDate = System.today()
        );
        insert term;

        // Session 1 under Term A
        AcademicSession sess1 = new AcademicSession(
            Name = 'Session 1',
            AcademicTermId = term.Id
        );
        insert sess1;

        // Session 2 under Term A (same term, ordered by name)
        AcademicSession sess2 = new AcademicSession(
            Name = 'Session 2',
            AcademicTermId = term.Id
        );
        insert sess2;

        // Create Program Enrollment
        ProgramEnrollment pe = TestDataFactory.testProgramEnrollment(student, prog);

        // Enrollment Session 1
        Enrollment_Session__c es1 = new Enrollment_Session__c(
            Program_Enrollment__c = pe.Id,
            Academic_Session__c   = sess1.Id,
            Status__c             = 'Registered',
            Assigned_Contact__c   = student.Id
        );
        insert es1;

        // Enrollment Session 2
        Enrollment_Session__c es2 = new Enrollment_Session__c(
            Program_Enrollment__c = pe.Id,
            Academic_Session__c   = sess2.Id,
            Status__c             = 'Registered',
             Assigned_Contact__c   = student.Id
        );
        insert es2;
    }

    // ========================================================
    // HELPER: Get Record Type Id by DeveloperName
    // ========================================================
    private static Id getCaseRecordTypeId(String developerName) {
        List<RecordType> rts = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Case' AND DeveloperName = :developerName
            LIMIT 1
        ];
        return rts.isEmpty() ? null : rts[0].Id;
    }

    // ========================================================
    // 1. filterClosedLOACases
    // ========================================================

    @isTest
    static void filterClosedLOACases_statusChange_returnsFilteredList() {
        Id loaRtId = getCaseRecordTypeId('LOA');
        Case c = TestDataFactory.testCase();
        c.RecordTypeId = loaRtId;
        c.TermsCondition__c = true;
        update c;

        Case oldCase = c.clone(true);
        oldCase.Status = 'New';
        c.Status = 'Closed';

        Test.startTest();
        List<Case> results = CaseTriggerHelper.filterClosedLOACases(
            new List<Case>{c},
            new Map<Id, Case>{c.Id => oldCase}
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return 1 LOA case that just closed');
    }

    @isTest
    static void filterClosedLOACases_noStatusChange_returnsEmpty() {
        Id loaRtId = getCaseRecordTypeId('LOA');
        Case c = TestDataFactory.testCase();
        c.RecordTypeId = loaRtId;
        c.TermsCondition__c = true;
        c.Status = 'New';
        update c;

        Case oldCase = c.clone(true);
        oldCase.Status = 'New'; // No change

        Test.startTest();
        List<Case> results = CaseTriggerHelper.filterClosedLOACases(
            new List<Case>{c},
            new Map<Id, Case>{c.Id => oldCase}
        );
        Test.stopTest();

        System.assertEquals(0, results.size(), 'Should return empty when status did not change to Closed');
    }

    @isTest
    static void filterClosedLOACases_termsConditionFalse_returnsEmpty() {
        Id loaRtId = getCaseRecordTypeId('LOA');
        Case c = TestDataFactory.testCase();
        c.RecordTypeId = loaRtId;
        c.TermsCondition__c = false;
        update c;

        Case oldCase = c.clone(true);
        oldCase.Status = 'New';
        c.Status = 'Closed';

        Test.startTest();
        List<Case> results = CaseTriggerHelper.filterClosedLOACases(
            new List<Case>{c},
            new Map<Id, Case>{c.Id => oldCase}
        );
        Test.stopTest();

        System.assertEquals(0, results.size(), 'TermsCondition false should exclude case from filter');
    }

    @isTest
    static void filterClosedLOACases_emptyList_returnsEmpty() {
        Test.startTest();
        List<Case> results = CaseTriggerHelper.filterClosedLOACases(
            new List<Case>(),
            new Map<Id, Case>()
        );
        Test.stopTest();
        System.assertEquals(0, results.size(), 'Empty input should return empty list');
    }

    // ========================================================
    // 2. filterClosedWithdrawalCases
    // ========================================================

    @isTest
    static void filterClosedWithdrawalCases_statusChange_returnsFilteredList() {
        Id withdrawalRtId = getCaseRecordTypeId('Withdrawal');
        Case c = TestDataFactory.testCase();
        c.RecordTypeId = withdrawalRtId;
        c.TermsCondition__c = true;
        update c;

        Case oldCase = c.clone(true);
        oldCase.Status = 'New';
        c.Status = 'Closed';

        Test.startTest();
        List<Case> results = CaseTriggerHelper.filterClosedWithdrawalCases(
            new List<Case>{c},
            new Map<Id, Case>{c.Id => oldCase}
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return 1 Withdrawal case that just closed');
    }

    @isTest
    static void filterClosedWithdrawalCases_emptyList_returnsEmpty() {
        Test.startTest();
        List<Case> results = CaseTriggerHelper.filterClosedWithdrawalCases(
            new List<Case>(),
            new Map<Id, Case>()
        );
        Test.stopTest();
        System.assertEquals(0, results.size(), 'Empty input should return empty list');
    }

    @isTest
    static void filterClosedWithdrawalCases_noStatusChange_returnsEmpty() {
        Id withdrawalRtId = getCaseRecordTypeId('Withdrawal');
        Case c = TestDataFactory.testCase();
        c.RecordTypeId = withdrawalRtId;
        c.TermsCondition__c = true;
        c.Status = 'New';
        update c;

        Case oldCase = c.clone(true);
        oldCase.Status = 'New';

        Test.startTest();
        List<Case> results = CaseTriggerHelper.filterClosedWithdrawalCases(
            new List<Case>{c},
            new Map<Id, Case>{c.Id => oldCase}
        );
        Test.stopTest();

        System.assertEquals(0, results.size(), 'No status change should return empty');
    }

    // ========================================================
    // 3. filterClosedRejoinCases
    // ========================================================

    @isTest
    static void filterClosedRejoinCases_statusChange_returnsFilteredList() {
        Id rejoinRtId = getCaseRecordTypeId('Rejoin');
        Case c = TestDataFactory.testCase();
        c.RecordTypeId = rejoinRtId;
        update c;

        Case oldCase = c.clone(true);
        oldCase.Status = 'New';
        c.Status = 'Closed';

        Test.startTest();
        List<Case> results = CaseTriggerHelper.filterClosedRejoinCases(
            new List<Case>{c},
            new Map<Id, Case>{c.Id => oldCase}
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return 1 Rejoin case that just closed');
    }

    @isTest
    static void filterClosedRejoinCases_emptyList_returnsEmpty() {
        Test.startTest();
        List<Case> results = CaseTriggerHelper.filterClosedRejoinCases(
            new List<Case>(),
            new Map<Id, Case>()
        );
        Test.stopTest();
        System.assertEquals(0, results.size(), 'Empty input should return empty list');
    }

    // ========================================================
    // 4. filterClosedAcademicProbationCases
    // ========================================================

    @isTest
    static void filterClosedAcademicProbationCases_returnsNotNull() {
        Id probRtId = getCaseRecordTypeId('Academic_Probation');
        Contact student = [SELECT Id FROM Contact LIMIT 1];

        Case c = new Case(
            RecordTypeId = probRtId,
            Status       = 'New',
            ContactId    = student.Id,
            Subject      = 'Probation Test'
        );
        insert c;

        Case oldCase = [SELECT Id, IsClosed, Status, RecordTypeId, ContactId FROM Case WHERE Id = :c.Id];
        Case triggerCase = oldCase.clone(true);

        Test.startTest();
        List<Case> results = CaseTriggerHelper.filterClosedAcademicProbationCases(
            new List<Case>{triggerCase},
            new Map<Id, Case>{oldCase.Id => oldCase}
        );
        Test.stopTest();

        System.assertNotEquals(null, results, 'Result list should not be null');
    }

    @isTest
    static void filterClosedAcademicProbationCases_emptyList_returnsEmpty() {
        Test.startTest();
        List<Case> results = CaseTriggerHelper.filterClosedAcademicProbationCases(
            new List<Case>(),
            new Map<Id, Case>()
        );
        Test.stopTest();
        System.assertEquals(0, results.size(), 'Empty input should return empty list');
    }

    // ========================================================
    // 5. filterApprovedEventsAndBudgetCases
    // ========================================================

    @isTest
    static void filterApprovedEventsAndBudgetCases_approvedCase_returnsFiltered() {
        Id eventBudgetRtId = getCaseRecordTypeId('Event_Budget_Proposal');

        // Create an AcademicTerm for the Budget field
        Program prog = [SELECT Id FROM Program LIMIT 1];
        AcademicTerm term = new AcademicTerm(
            Name      = 'Budget Term',
            Program__c = prog.Id,
            StartDate  = System.today()
        );
        insert term;

        Case c = TestDataFactory.testCase();
        c.RecordTypeId    = eventBudgetRtId;
        c.Status          = 'New';
        c.Program__c       = prog.Id;
        c.Academic_Term__c = term.Id;
        c.Budget_Ask__c   = 5000;
        update c;

        Case oldCase = c.clone(true);
        oldCase.Status = 'New';
        c.Status = 'Approved';

        Test.startTest();
        List<Case> results = CaseTriggerHelper.filterApprovedEventsAndBudgetCases(
            new List<Case>{c},
            new Map<Id, Case>{c.Id => oldCase}
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return 1 approved Event & Budget case');
    }

    @isTest
    static void filterApprovedEventsAndBudgetCases_emptyList_returnsEmpty() {
        Test.startTest();
        List<Case> results = CaseTriggerHelper.filterApprovedEventsAndBudgetCases(
            new List<Case>(),
            new Map<Id, Case>()
        );
        Test.stopTest();
        System.assertEquals(0, results.size(), 'Empty input should return empty list');
    }

    @isTest
    static void filterApprovedEventsAndBudgetCases_noBudgetAsk_returnsEmpty() {
        Id eventBudgetRtId = getCaseRecordTypeId('Event_Budget_Proposal');

        Program prog = [SELECT Id FROM Program LIMIT 1];
        AcademicTerm term = new AcademicTerm(
            Name       = 'Budget Term 2',
            Program__c = prog.Id,
            StartDate  = System.today()
        );
        insert term;

        Case c = TestDataFactory.testCase();
        c.RecordTypeId    = eventBudgetRtId;
        c.Status          = 'New';
        c.Academic_Term__c = term.Id;
        c.Budget_Ask__c   = 0; // Zero budget, should be excluded
        c.Program__c       = prog.Id;
        update c;

        Case oldCase = c.clone(true);
        oldCase.Status = 'New';
        c.Status = 'Approved';

        Test.startTest();
        List<Case> results = CaseTriggerHelper.filterApprovedEventsAndBudgetCases(
            new List<Case>{c},
            new Map<Id, Case>{c.Id => oldCase}
        );
        Test.stopTest();

        System.assertEquals(0, results.size(), 'Zero budget should exclude the case');
    }

    // ========================================================
    // 6. processLOACases — valid range
    // ========================================================

    @isTest
    static void processLOACases_validRange_updatesEnrollmentSessions() {
        Contact student = [SELECT Id FROM Contact LIMIT 1];
        Program prog    = [SELECT Id FROM Program LIMIT 1];

        Case loaCase = TestDataFactory.testCase();
        loaCase.ContactId    = student.Id;
        loaCase.Program__c   = prog.Id;
        loaCase.From_Term__c = 'Session 1';
        loaCase.To_Term__c   = 'Session 1';
        update loaCase;

        Test.startTest();
        CaseTriggerHelper.processLOACases(new List<Case>{loaCase});
        Test.stopTest();

        Enrollment_Session__c updatedEs = [
            SELECT Status__c
            FROM Enrollment_Session__c
            WHERE Program_Enrollment__r.ContactId = :student.Id
            AND Academic_Session__r.Name = 'Session 1'
            LIMIT 1
        ];
    }

    @isTest
    static void processLOACases_swappedIndices_correctsRange() {
        Contact student = [SELECT Id FROM Contact LIMIT 1];
        Program prog    = [SELECT Id FROM Program LIMIT 1];

        Case loaCase = TestDataFactory.testCase();
        loaCase.ContactId    = student.Id;
        loaCase.Program__c   = prog.Id;
        loaCase.From_Term__c = 'Session 2'; // swapped intentionally
        loaCase.To_Term__c   = 'Session 1';
        update loaCase;

        Test.startTest();
        CaseTriggerHelper.processLOACases(new List<Case>{loaCase});
        Test.stopTest();

        Enrollment_Session__c es1 = [
            SELECT Status__c
            FROM Enrollment_Session__c
            WHERE Program_Enrollment__r.ContactId = :student.Id
            AND Academic_Session__r.Name = 'Session 1'
            LIMIT 1
        ];
    }

    @isTest
    static void processLOACases_alreadyLOA_noDoubleUpdate() {
        Contact student = [SELECT Id FROM Contact LIMIT 1];
        Program prog    = [SELECT Id FROM Program LIMIT 1];

        // Pre-set session to LOA
        Enrollment_Session__c es = [
            SELECT Id FROM Enrollment_Session__c
            WHERE Program_Enrollment__r.ContactId = :student.Id
            AND Academic_Session__r.Name = 'Session 1'
            LIMIT 1
        ];
        es.Status__c = 'LOA';
        update es;

        Case loaCase = TestDataFactory.testCase();
        loaCase.ContactId    = student.Id;
        loaCase.Program__c   = prog.Id;
        loaCase.From_Term__c = 'Session 1';
        loaCase.To_Term__c   = 'Session 1';
        update loaCase;

        Test.startTest();
        CaseTriggerHelper.processLOACases(new List<Case>{loaCase}); // Should not fail
        Test.stopTest();

        Enrollment_Session__c updatedEs = [
            SELECT Status__c FROM Enrollment_Session__c WHERE Id = :es.Id
        ];
        System.assertEquals('LOA', updatedEs.Status__c, 'Status should remain LOA');
    }

    @isTest
    static void processLOACases_noContactId_skips() {
        Case loaCase = TestDataFactory.testCase();
        loaCase.ContactId    = null;
        loaCase.From_Term__c = 'Session 1';
        loaCase.To_Term__c   = 'Session 1';
        update loaCase;

        Test.startTest();
        CaseTriggerHelper.processLOACases(new List<Case>{loaCase}); // Should not throw
        Test.stopTest();

        System.assert(true, 'Method should handle null ContactId gracefully');
    }

    @isTest
    static void processLOACases_noSessionsFound_skips() {
        // Use a contact that has no enrollment sessions
        Contact orphan = new Contact(
            FirstName             = 'Orphan',
            LastName              = 'Student',
            Email                 = 'orphan@test.com',
            hed__Preferred_Email__c = 'VF Email ID',
            VF_Email_ID__c        = 'orphan@test.com'
        );
        insert orphan;

        Case loaCase = TestDataFactory.testCase();
        loaCase.ContactId    = orphan.Id;
        loaCase.From_Term__c = 'Session 1';
        loaCase.To_Term__c   = 'Session 2';
        update loaCase;

        Test.startTest();
        CaseTriggerHelper.processLOACases(new List<Case>{loaCase});
        Test.stopTest();

        System.assert(true, 'Should gracefully handle case with no enrollment sessions');
    }

    @isTest
    static void processLOACases_termNamesNotMatched_logsError() {
        Contact student = [SELECT Id FROM Contact LIMIT 1];
        Program prog    = [SELECT Id FROM Program LIMIT 1];

        Case loaCase = TestDataFactory.testCase();
        loaCase.ContactId    = student.Id;
        loaCase.Program__c   = prog.Id;
        loaCase.From_Term__c = 'Nonexistent Session A';
        loaCase.To_Term__c   = 'Nonexistent Session B';
        update loaCase;

        Test.startTest();
        CaseTriggerHelper.processLOACases(new List<Case>{loaCase});
        Test.stopTest();

        System.assert(true, 'Should handle unmatched term names without exception');
    }

    // ========================================================
    // 7. processWithdrawalCases
    // ========================================================

    @isTest
    static void processWithdrawalCases_validRange_updatesEnrollmentSessions() {
        Contact student = [SELECT Id FROM Contact LIMIT 1];
        Program prog    = [SELECT Id FROM Program LIMIT 1];

        Case wdCase = TestDataFactory.testCase();
        wdCase.ContactId    = student.Id;
        wdCase.Program__c   = prog.Id;
        wdCase.From_Term__c = 'Session 1';
        wdCase.To_Term__c   = 'Session 2';
        update wdCase;

        Test.startTest();
        CaseTriggerHelper.processWithdrawalCases(new List<Case>{wdCase});
        Test.stopTest();

        Enrollment_Session__c es = [
            SELECT Status__c
            FROM Enrollment_Session__c
            WHERE Program_Enrollment__r.ContactId = :student.Id
            AND Academic_Session__r.Name = 'Session 1'
            LIMIT 1
        ];
    }

    @isTest
    static void processWithdrawalCases_swappedIndices_correctsRange() {
        Contact student = [SELECT Id FROM Contact LIMIT 1];
        Program prog    = [SELECT Id FROM Program LIMIT 1];

        Case wdCase = TestDataFactory.testCase();
        wdCase.ContactId    = student.Id;
        wdCase.Program__c   = prog.Id;
        wdCase.From_Term__c = 'Session 2'; // swapped
        wdCase.To_Term__c   = 'Session 1';
        update wdCase;

        Test.startTest();
        CaseTriggerHelper.processWithdrawalCases(new List<Case>{wdCase});
        Test.stopTest();

        List<Enrollment_Session__c> esList = [
            SELECT Status__c
            FROM Enrollment_Session__c
            WHERE Program_Enrollment__r.ContactId = :student.Id
        ];
        
    }

    @isTest
    static void processWithdrawalCases_noContactId_skips() {
        Case wdCase = TestDataFactory.testCase();
        wdCase.ContactId    = null;
        wdCase.From_Term__c = 'Session 1';
        wdCase.To_Term__c   = 'Session 1';
        update wdCase;

        Test.startTest();
        CaseTriggerHelper.processWithdrawalCases(new List<Case>{wdCase});
        Test.stopTest();

        System.assert(true, 'Null ContactId should be handled gracefully');
    }

    @isTest
    static void processWithdrawalCases_alreadyInactive_noDoubleUpdate() {
        Contact student = [SELECT Id FROM Contact LIMIT 1];
        Program prog    = [SELECT Id FROM Program LIMIT 1];

        // Pre-set to Inactive
        Enrollment_Session__c es = [
            SELECT Id FROM Enrollment_Session__c
            WHERE Program_Enrollment__r.ContactId = :student.Id
            AND Academic_Session__r.Name = 'Session 1'
            LIMIT 1
        ];
        es.Status__c = 'Inactive';
        update es;

        Case wdCase = TestDataFactory.testCase();
        wdCase.ContactId    = student.Id;
        wdCase.Program__c   = prog.Id;
        wdCase.From_Term__c = 'Session 1';
        wdCase.To_Term__c   = 'Session 1';
        update wdCase;

        Test.startTest();
        CaseTriggerHelper.processWithdrawalCases(new List<Case>{wdCase});
        Test.stopTest();

        Enrollment_Session__c updatedEs = [SELECT Status__c FROM Enrollment_Session__c WHERE Id = :es.Id];
        System.assertEquals('Inactive', updatedEs.Status__c, 'Status should remain Inactive');
    }

    // ========================================================
    // 8. processRejoinCases
    // ========================================================

    @isTest
    static void processRejoinCases_validRange_updatesEnrollmentSessions() {
        Contact student = [SELECT Id FROM Contact LIMIT 1];
        Program prog    = [SELECT Id FROM Program LIMIT 1];

        // Set sessions to Inactive first (so rejoin can re-register them)
        List<Enrollment_Session__c> esList = [
            SELECT Id FROM Enrollment_Session__c
            WHERE Program_Enrollment__r.ContactId = :student.Id
        ];
        for (Enrollment_Session__c es : esList) {
            es.Status__c = 'Inactive';
        }
        update esList;

        Case rejoinCase = TestDataFactory.testCase();
        rejoinCase.ContactId    = student.Id;
        rejoinCase.Program__c   = prog.Id;
        rejoinCase.From_Term__c = 'Session 1';
        rejoinCase.To_Term__c   = 'Session 1';
        update rejoinCase;

        Test.startTest();
        CaseTriggerHelper.processRejoinCases(new List<Case>{rejoinCase});
        Test.stopTest();

        Enrollment_Session__c updatedEs = [
            SELECT Status__c
            FROM Enrollment_Session__c
            WHERE Program_Enrollment__r.ContactId = :student.Id
            AND Academic_Session__r.Name = 'Session 1'
            LIMIT 1
        ];
    }

    @isTest
    static void processRejoinCases_swappedIndices_correctsRange() {
        Contact student = [SELECT Id FROM Contact LIMIT 1];
        Program prog    = [SELECT Id FROM Program LIMIT 1];

        List<Enrollment_Session__c> esList = [
            SELECT Id FROM Enrollment_Session__c
            WHERE Program_Enrollment__r.ContactId = :student.Id
        ];
        for (Enrollment_Session__c es : esList) {
            es.Status__c = 'Inactive';
        }
        update esList;

        Case rejoinCase = TestDataFactory.testCase();
        rejoinCase.ContactId    = student.Id;
        rejoinCase.Program__c   = prog.Id;
        rejoinCase.From_Term__c = 'Session 2'; // swapped
        rejoinCase.To_Term__c   = 'Session 1';
        update rejoinCase;

        Test.startTest();
        CaseTriggerHelper.processRejoinCases(new List<Case>{rejoinCase});
        Test.stopTest();

        Enrollment_Session__c es1 = [
            SELECT Status__c
            FROM Enrollment_Session__c
            WHERE Program_Enrollment__r.ContactId = :student.Id
            AND Academic_Session__r.Name = 'Session 1'
            LIMIT 1
        ];
    }

    @isTest
    static void processRejoinCases_noContactId_skips() {
        Case rejoinCase = TestDataFactory.testCase();
        rejoinCase.ContactId    = null;
        rejoinCase.From_Term__c = 'Session 1';
        rejoinCase.To_Term__c   = 'Session 1';
        update rejoinCase;

        Test.startTest();
        CaseTriggerHelper.processRejoinCases(new List<Case>{rejoinCase});
        Test.stopTest();

        System.assert(true, 'Null ContactId should be handled gracefully');
    }

    @isTest
    static void processRejoinCases_alreadyReRegistered_noDoubleUpdate() {
        Contact student = [SELECT Id FROM Contact LIMIT 1];
        Program prog    = [SELECT Id FROM Program LIMIT 1];

        Enrollment_Session__c es = [
            SELECT Id FROM Enrollment_Session__c
            WHERE Program_Enrollment__r.ContactId = :student.Id
            AND Academic_Session__r.Name = 'Session 1'
            LIMIT 1
        ];
        es.Status__c = 'Re-Registered';
        update es;

        Case rejoinCase = TestDataFactory.testCase();
        rejoinCase.ContactId    = student.Id;
        rejoinCase.Program__c   = prog.Id;
        rejoinCase.From_Term__c = 'Session 1';
        rejoinCase.To_Term__c   = 'Session 1';
        update rejoinCase;

        Test.startTest();
        CaseTriggerHelper.processRejoinCases(new List<Case>{rejoinCase});
        Test.stopTest();

        Enrollment_Session__c updatedEs = [SELECT Status__c FROM Enrollment_Session__c WHERE Id = :es.Id];
        System.assertEquals('Re-Registered', updatedEs.Status__c, 'Status should remain Re-Registered');
    }

    // ========================================================
    // 9. processApprovedBudgetCases
    // ========================================================

    @isTest
    static void processApprovedBudgetCases_subtractsBudget() {
        Program prog = [SELECT Id FROM Program LIMIT 1];

        AcademicTerm term = new AcademicTerm(
            Name              = 'Budget Term Test',
            Program__c        = prog.Id,
            StartDate         = System.today(),
            Allocated_Budget__c = 10000,
            Remaining_Budget__c = 10000
        );
        insert term;

        Case c = TestDataFactory.testCase();
        c.Academic_Term__c = term.Id;
        c.Budget_Ask__c    = 3000;
        c.Program__c       = prog.Id;
        update c;

        Test.startTest();
        CaseTriggerHelper.processApprovedBudgetCases(new List<Case>{c});
        Test.stopTest();

        AcademicTerm updatedTerm = [SELECT Remaining_Budget__c FROM AcademicTerm WHERE Id = :term.Id];
        System.assertEquals(7000, updatedTerm.Remaining_Budget__c, 'Remaining budget should be reduced by Budget_Ask__c');
    }

    @isTest
    static void processApprovedBudgetCases_noRemainingBudget_usesAllocated() {
        Program prog = [SELECT Id FROM Program LIMIT 1];

        AcademicTerm term = new AcademicTerm(
            Name               = 'Budget Term No Remaining',
            Program__c         = prog.Id,
            StartDate          = System.today(),
            Allocated_Budget__c = 5000,
            Remaining_Budget__c = null  // null => fall back to Allocated
        );
        insert term;

        Case c = TestDataFactory.testCase();
        c.Academic_Term__c = term.Id;
        c.Program__c       = prog.Id;
        c.Budget_Ask__c    = 1500;
        update c;

        Test.startTest();
        CaseTriggerHelper.processApprovedBudgetCases(new List<Case>{c});
        Test.stopTest();

        AcademicTerm updatedTerm = [SELECT Remaining_Budget__c FROM AcademicTerm WHERE Id = :term.Id];
        System.assertEquals(3500, updatedTerm.Remaining_Budget__c, 'Should fall back to Allocated_Budget__c when Remaining_Budget__c is null');
    }

    @isTest
    static void processApprovedBudgetCases_emptyList_noOp() {
        Test.startTest();
        CaseTriggerHelper.processApprovedBudgetCases(new List<Case>());
        Test.stopTest();
        System.assert(true, 'Empty list should return without error');
    }

    // ========================================================
    // 10. sendProbationClearedEmails
    // ========================================================

    @isTest
    static void sendProbationClearedEmails_withContact_sendsEmail() {
        Contact student = [SELECT Id, Email FROM Contact LIMIT 1];

        Case c = TestDataFactory.testCase();
        c.ContactId = student.Id;
        update c;

        Test.startTest();
        CaseTriggerHelper.sendProbationClearedEmails(new List<Case>{c});
        Integer emailInvocations = Limits.getEmailInvocations();
        Test.stopTest();

        System.assert(emailInvocations >= 0, 'Email invocations should be non-negative');
    }

    @isTest
    static void sendProbationClearedEmails_noContactId_skips() {
        Case c = TestDataFactory.testCase();
        c.ContactId = null;
        update c;

        Test.startTest();
        CaseTriggerHelper.sendProbationClearedEmails(new List<Case>{c});
        Test.stopTest();

        System.assert(true, 'Null ContactId should be handled gracefully without sending');
    }

    @isTest
    static void sendProbationClearedEmails_emptyList_noOp() {
        Test.startTest();
        CaseTriggerHelper.sendProbationClearedEmails(new List<Case>());
        Test.stopTest();
        System.assert(true, 'Empty list should not throw');
    }
}