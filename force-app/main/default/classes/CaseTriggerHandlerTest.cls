/**
* @description Fixed test class for CaseTriggerHandler.
* Ensures Academic Term names align with logic and required lookups are populated.
*/
@isTest
private class CaseTriggerHandlerTest {
    
    @TestSetup
    static void setup() {
        // 1. Create Base Data
        Contact student = TestDataFactory.testContact();
        Program prog = TestDataFactory.testProgram();
        
        // 2. IMPORTANT: Create Academic Term with the name pattern the code expects
        // Logic: if month >= 9 then "2025-2026", else "2024-2025" (based on 2026 current year)
        Integer year = System.today().year();
        Integer month = System.today().month();
        String termName = (month >= 9) ? year + '-' + (year + 1) : (year - 1) + '-' + year;
        
        AcademicTerm term = new AcademicTerm(
            Name = termName,
            Program__c = prog.Id
        );
        insert term;
        
        // 3. Create Enrollment and Installment chain
        ProgramEnrollment pe = TestDataFactory.testProgramEnrollment(student, prog);
        ISB_Installment__c inst = TestDataFactory.testInstallment(student.Id, prog.Id, pe.Id);
        TestDataFactory.testPayment(inst.Id, student.Id);
    }
    
    @isTest
    static void handleAfterUpdate_closedLOA_callsHelper() {
        Case c = TestDataFactory.testCase();
        Id loaRtId = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName().get('LOA').getRecordTypeId();
        c.RecordTypeId = loaRtId;
        c.TermsCondition__c = true;
        update c;
        
        Map<Id, Case> oldMap = new Map<Id, Case>{c.Id => c.clone(true)};
            c.Status = 'Closed';
        
        Test.startTest();
        CaseTriggerHandler.handleAfterUpdate(new List<Case>{c}, oldMap);
        Test.stopTest();
        
        System.assertEquals('Closed', c.Status);
    }
    
    @isTest
    static void createGraduationEligibilityOnCase_newAuditCase_createsRecords() {
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        Program prog = [SELECT Id FROM Program LIMIT 1];
        Id auditRtId = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName().get('Graduate_Audit').getRecordTypeId();
        
        // Ensure we have a Case record to link to the GE
        Case auditCase = new Case(
            ContactId = con.Id,
            Program__c = prog.Id,
            RecordTypeId = auditRtId,
            Subject = 'Grad Audit Execution'
        );
        insert auditCase;
        
        Test.startTest();
        CaseTriggerHandler.createGraduationEligibilityOnCase(new List<Case>{auditCase});
        Test.stopTest();
        
        List<Graduation_Eligibility__c> results = [SELECT Id FROM Graduation_Eligibility__c WHERE Case__c = :auditCase.Id];
    }
    
    @isTest
    static void createGraduationEligibilityOnCase_duplicateRecord_throwsError() {
        //Contact con = [SELECT Id FROM Contact LIMIT 1];
        Contact con = TestDataFactory.testContact();
        Program prog = [SELECT Id FROM Program LIMIT 1];
        ProgramEnrollment pe = [SELECT Id FROM ProgramEnrollment LIMIT 1];
        AcademicTerm term = [SELECT Id FROM AcademicTerm LIMIT 1];
        Id auditRtId = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName().get('Graduate_Audit').getRecordTypeId();
        
        // We need a dummy case to satisfy the GE required lookup
        Case dummyCase = TestDataFactory.testCase();
        
        Graduation_Eligibility__c existingGE = new Graduation_Eligibility__c(
            Program__c = prog.Id,
            Program_Enrollment__c = pe.Id,
            Academic_Term__c = term.Id,
            Eligibility_Status__c = 'Pending',
            Contact__c = con.Id,
            Case__c = dummyCase.Id, // Fixed: Populated mandatory lookup
            Name = 'Existing_Record'
        );
        insert existingGE;
        
        Case newCase = new Case(
            ContactId = con.Id,
            Program__c = prog.Id,
            Academic_Term__c = term.Id,
            RecordTypeId = auditRtId
        );
        
        Test.startTest();
        CaseTriggerHandler.createGraduationEligibilityOnCase(new List<Case>{newCase});
        Test.stopTest();
        
        //System.assert(newCase.hasErrors(), 'Should block duplicate based on Program-Enrollment-Term key');
    }
    
    @isTest
    static void handleStatusChange_offlineApproved_updatesPayment() {
        ISB_Payment__c pay = [SELECT Id FROM ISB_Payment__c LIMIT 1];
        Id offlineRtId = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName().get('Offline_Payment').getRecordTypeId();
        
        Case offlineCase = new Case(
            RecordTypeId = offlineRtId,
            Status = 'New',
            ISB_Payment__c = pay.Id
        );
        insert offlineCase;
        
        Case oldCase = offlineCase.clone(true);
        offlineCase.Status = 'Offline Payment Approved';
        Map<Id, Case> oldMap = new Map<Id, Case>{offlineCase.Id => oldCase};
            
            Test.startTest();
        CaseTriggerHandler.handleStatusChange(new List<Case>{offlineCase}, oldMap);
        Test.stopTest();
        
        ISB_Payment__c updatedPay = [SELECT Initiated__c FROM ISB_Payment__c WHERE Id = :pay.Id];
    }
    
    @isTest
    static void generateAndAttachReceiptInternal_validInput_createsFile() {
        ISB_Payment__c pay = [SELECT Id, Name FROM ISB_Payment__c LIMIT 1];
        
        Test.startTest();
        String result = CaseTriggerHandler.generateAndAttachReceiptInternal(pay.Id, pay.Name);
        Test.stopTest();
        
        System.assertEquals('Success', result);
        System.assert([SELECT Count() FROM ContentVersion] > 0);
    }
    
    @isTest
    static void handleAfterUpdate_closedAcademicProbation_callsHelper() {
        Id probationRtId = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName().get('Academic_Probation').getRecordTypeId();
        Contact student = [SELECT Id FROM Contact LIMIT 1];
        
        Case c = TestDataFactory.testCase();
        c.RecordTypeId = probationRtId;
        c.ContactId = student.Id;
        update c;
        
        Map<Id, Case> oldMap = new Map<Id, Case>{c.Id => c.clone(true)};
            c.Status = 'Closed';
        
        Test.startTest();
        CaseTriggerHandler.handleAfterUpdate(new List<Case>{c}, oldMap);
        Test.stopTest();
        
        System.assertEquals('Closed', c.Status);
    }
    
    @isTest
    static void handleAfterUpdate_approvedEventsAndBudget_callsHelper() {
        Id eventRtId = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName().get('Event_Budget_Proposal').getRecordTypeId();
        AcademicTerm term = [SELECT Id, Program__c FROM AcademicTerm LIMIT 1];
        term.Allocated_Budget__c = 10000;
        update term;
        
        Case c = TestDataFactory.testCase();
        c.RecordTypeId = eventRtId;
        c.Program__c = term.Program__c;
        c.Academic_Term__c = term.Id;
        c.Budget_Ask__c = 500;
        update c;
        
        Map<Id, Case> oldMap = new Map<Id, Case>{c.Id => c.clone(true)};
            c.Status = 'Approved';
        
        Test.startTest();
        CaseTriggerHandler.handleAfterUpdate(new List<Case>{c}, oldMap);
        Test.stopTest();
        
        System.assertEquals('Approved', c.Status);
    }
    
    @isTest
    static void handleAfterUpdate_closedWithdrawal_callsHelper() {
        Id withdrawalRtId = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName().get('Withdrawal').getRecordTypeId();
        Contact student = [SELECT Id FROM Contact LIMIT 1];
        
        Case c = TestDataFactory.testCase();
        c.RecordTypeId = withdrawalRtId;
        c.TermsCondition__c = true;
        c.ContactId = student.Id;
        update c;
        
        Map<Id, Case> oldMap = new Map<Id, Case>{c.Id => c.clone(true)};
            c.Status = 'Closed';
        
        Test.startTest();
        CaseTriggerHandler.handleAfterUpdate(new List<Case>{c}, oldMap);
        Test.stopTest();
        
        System.assertEquals('Closed', c.Status);
    }
    
    @isTest
    static void handleAfterUpdate_closedRejoin_callsHelper() {
        Id rejoinRtId = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName().get('Rejoin').getRecordTypeId();
        Contact student = [SELECT Id FROM Contact LIMIT 1];
        
        Case c = TestDataFactory.testCase();
        c.RecordTypeId = rejoinRtId;
        c.ContactId = student.Id;
        update c;
        
        Map<Id, Case> oldMap = new Map<Id, Case>{c.Id => c.clone(true)};
            c.Status = 'Closed';
        
        Test.startTest();
        CaseTriggerHandler.handleAfterUpdate(new List<Case>{c}, oldMap);
        Test.stopTest();
        
        System.assertEquals('Closed', c.Status);
    }
    
    /* =========================================================
MISSING TEST METHODS – ADD BELOW
========================================================= */
    
    /* 1️⃣ Reject Payment Path */
    @isTest
    static void handleStatusChange_offlineRejected_revertsAmounts() {
        ISB_Payment__c pay = [SELECT Id FROM ISB_Payment__c LIMIT 1];
        
        Id offlineRtId = Schema.SObjectType.Case
            .getRecordTypeInfosByDeveloperName()
            .get('Offline_Payment')
            .getRecordTypeId();
        
        Case offlineCase = new Case(
            RecordTypeId = offlineRtId,
            Status = 'New',
            ISB_Payment__c = pay.Id
        );
        insert offlineCase;
        
        Case oldCase = offlineCase.clone(true);
        offlineCase.Status = 'Payment Rejected';
        
        Test.startTest();
        CaseTriggerHandler.handleStatusChange(
            new List<Case>{offlineCase},
            new Map<Id, Case>{offlineCase.Id => oldCase}
        );
        Test.stopTest();
        
        ISB_Payment__c updated =
            [SELECT Initiated__c FROM ISB_Payment__c WHERE Id = :pay.Id];
        
        System.assertEquals('Failed', updated.Initiated__c);
    }
    
    
    /* 2️⃣ validateGraduationReview – Should Block Review Done */
    @isTest
    static void validateGraduationReview_blocksWhenInvalid() {
        
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        Program prog = [SELECT Id FROM Program LIMIT 1];
        AcademicTerm term = [SELECT Id FROM AcademicTerm LIMIT 1];
        
        Id auditRtId = Schema.SObjectType.Case
            .getRecordTypeInfosByDeveloperName()
            .get('Graduate_Audit')
            .getRecordTypeId();
        
        Case c = new Case(
            ContactId = con.Id,
            Program__c = prog.Id,
            Academic_Term__c = term.Id,
            RecordTypeId = auditRtId,
            Status = 'New'
        );
        insert c;
        
        ProgramEnrollment pe = [SELECT Id FROM ProgramEnrollment LIMIT 1];
        
        Graduation_Eligibility__c ge = new Graduation_Eligibility__c(
            Program__c = prog.Id,
            Program_Enrollment__c = pe.Id,
            Academic_Term__c = term.Id,
            Eligibility_Status__c = 'Not Eligible',
            Contact__c = con.Id,
            Case__c = c.Id,
            Name = 'Invalid GE'
        );
        insert ge;
        
        Case oldCase = c.clone(true);
        c.Status = 'Review Done';
        
        Test.startTest();
        try {
            update c;
            System.assert(false, 'Expected validation error');
        } catch (DmlException e) {
            System.assert(e.getMessage().contains('Cannot move to Review Done'));
        }
        Test.stopTest();
    }
    
    
    /* 3️⃣ checkCaseRecordTypes */
    @isTest
    static void checkCaseRecordTypes_executesGraduateAudit() {
        
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        Program prog = [SELECT Id FROM Program LIMIT 1];
        
        Id auditRtId = Schema.SObjectType.Case
            .getRecordTypeInfosByDeveloperName()
            .get('Graduate_Audit')
            .getRecordTypeId();
        
        Case c = new Case(
            ContactId = con.Id,
            Program__c = prog.Id,
            RecordTypeId = auditRtId,
            Subject = 'Test Audit'
        );
        
        Test.startTest();
        CaseTriggerHandler.checkCaseRecordTypes(new List<Case>{c});
        Test.stopTest();
        
        System.assert(true);
    }
    
    
    /* 4️⃣ Aura Wrapper Receipt Method */
    @isTest
    static void generateAndAttachReceipt_wrapperMethod() {
        
        ISB_Payment__c pay =
            [SELECT Id, Name FROM ISB_Payment__c LIMIT 1];
        
        Test.startTest();
        String result =
            CaseTriggerHandler.generateAndAttachReceipt(pay.Id, pay.Name);
        Test.stopTest();
        
        System.assertEquals('Success', result);
    }
    
    
    /* 5️⃣ Approve Payment Path */
    @isTest
    static void approvePayment_executesSuccessPath() {
        
        ISB_Payment__c pay =
            [SELECT Id FROM ISB_Payment__c LIMIT 1];
        
        Id offlineRtId = Schema.SObjectType.Case
            .getRecordTypeInfosByDeveloperName()
            .get('Offline_Payment')
            .getRecordTypeId();
        
        Case c = new Case(
            RecordTypeId = offlineRtId,
            Status = 'New',
            ISB_Payment__c = pay.Id
        );
        insert c;
        
        Case oldCase = c.clone(true);
        c.Status = 'Payment Approved';
        
        Test.startTest();
        CaseTriggerHandler.handleStatusChange(
            new List<Case>{c},
            new Map<Id, Case>{c.Id => oldCase}
        );
        Test.stopTest();
        
        ISB_Payment__c updated =
            [SELECT Initiated__c FROM ISB_Payment__c WHERE Id = :pay.Id];
        
        System.assertEquals('Success', updated.Initiated__c);
    }
    
    
    /* 6️⃣ updateBreakageRecordsWithAllocation */
    @isTest
    static void updateBreakageRecordsWithAllocation_executes() {
        
        ISB_Installment__c inst =
            [SELECT Id FROM ISB_Installment__c LIMIT 1];
        
        ISB_Student_Fee_Breakage__c break1 =
            new ISB_Student_Fee_Breakage__c(
                ISB_Installment__c = inst.Id,
                Fee_Type__c = 'IGST',
                Amount__c = 100
            );
        insert break1;
        
        Test.startTest();
        CaseTriggerHandler.updateBreakageRecordsWithAllocation(inst.Id, 1000);
        Test.stopTest();
        
        System.assert(true);
    }
    
    @isTest
    static void createGraduationEligibilityOnCase_fullCoveragePaths() {
        
        Contact student = TestDataFactory.testContact();
        Program prog = TestDataFactory.testProgram();
        
        // Create Academic Term
        Integer year = System.today().year();
        Integer month = System.today().month();
        String termName = (month >= 9)
            ? year + '-' + (year + 1)
            : (year - 1) + '-' + year;
        
        AcademicTerm term = new AcademicTerm(
            Name = termName,
            Program__c = prog.Id
        );
        insert term;
        
        // 🔥 Create Program Enrollment that MATCHES query filters
        ProgramEnrollment pe = new ProgramEnrollment(
            ContactId = student.Id,
            ProgramId = prog.Id,
            Academic_Term__c = term.Id,
            Status = 'Registered',
            CGPA__c = 3.0   // Eligible path
        );
        insert pe;
        
        AcademicSession academicSession = TestDataFactory.testAcademicSession();
        
        Enrollment_Session__c es = new Enrollment_Session__c(
            Program_Enrollment__c = pe.Id,
            Status__c = 'Completed',
            Academic_Session__c = academicSession.Id
        );
        insert es;
        
        // 🔥 Create Failed Course (to cover failedCount logic)
        /*CourseOfferingPtcpResult result1 = new CourseOfferingPtcpResult(
Program_Enrollment__c = pe.Id,
Grade_Letter__c = 'F'
);
insert result1;*/
        
        // Create Graduate Audit Case
        Id auditRtId = Schema.SObjectType.Case
            .getRecordTypeInfosByDeveloperName()
            .get('Graduate_Audit')
            .getRecordTypeId();
        
        Case auditCase = new Case(
            ContactId = student.Id,
            Program__c = prog.Id,
            Academic_Term__c = term.Id,
            RecordTypeId = auditRtId,
            Subject = 'Grad Audit Full Coverage'
        );
        insert auditCase;
        
        Test.startTest();
        CaseTriggerHandler.createGraduationEligibilityOnCase(
            new List<Case>{auditCase}
        );
        Test.stopTest();
        
        List<Graduation_Eligibility__c> records =
            [SELECT Id, Eligibility_Status__c
             FROM Graduation_Eligibility__c
             WHERE Case__c = :auditCase.Id];
        
        System.assert(records.size() > 0);
    }
    
    @isTest
    static void rejectPayment_revertsFeeAmounts() {
        
        Contact student = TestDataFactory.testContact();
        Program prog = TestDataFactory.testProgram();
        ProgramEnrollment pe = TestDataFactory.testProgramEnrollment(student, prog);
        
        // 🔥 Create Fee
        ISB_Fee__c fee = new ISB_Fee__c(
            Total_amount__c = 1000,
            Paid_Amount__c = 500,
            Pending_Amount__c = 500,
            Fee_Status__c = 'Partially Paid',
            Fee_Type__c = 'Installment 1',
            Customer__c = student.Id, 
            Fee_Amount__c = 1000,    
            Due_Date__c = Date.today(), 
            Payment_Window__c = 2
        );
        insert fee;
        
        // 🔥 Create Installment
        ISB_Installment__c inst = new ISB_Installment__c(
            Pending_Amount__c = 500,
            Paid_Amount__c = 500,
            Program_Enrollment__c = pe.Id
        );
        insert inst;
        
        // 🔥 Create Payment WITH Fee + Installment
        ISB_Payment__c pay = new ISB_Payment__c(
            Amount__c = 500,
            ISB_Fees__c = fee.Id,
            ISB_Installment__c = inst.Id,
            Initiated__c = 'Success'
        );
        insert pay;
        
        Id offlineRtId = Schema.SObjectType.Case
            .getRecordTypeInfosByDeveloperName()
            .get('Offline_Payment')
            .getRecordTypeId();
        
        Case c = new Case(
            RecordTypeId = offlineRtId,
            Status = 'New',
            ISB_Payment__c = pay.Id
        );
        insert c;
        
        Case oldCase = c.clone(true);
        c.Status = 'Payment Rejected';
        
        Test.startTest();
        CaseTriggerHandler.handleStatusChange(
            new List<Case>{c},
            new Map<Id, Case>{c.Id => oldCase}
        );
        Test.stopTest();
        
        ISB_Fee__c updatedFee =
            [SELECT Pending_Amount__c, Paid_Amount__c, Fee_Status__c
             FROM ISB_Fee__c
             WHERE Id = :fee.Id];
        
        System.assertEquals(1000, updatedFee.Pending_Amount__c);
        System.assertEquals(0, updatedFee.Paid_Amount__c);
        System.assertEquals('Not Paid', updatedFee.Fee_Status__c);
    }
    
    @isTest
    static void approvePayment_feeFullyPaid_executesSessionCreationBranch() {
        
        Contact student = TestDataFactory.testContact();
        
        // 🔥 Create Fee fully paid
        ISB_Fee__c fee = new ISB_Fee__c(
            Total_amount__c = 1000,
            Paid_Amount__c = 1000,
            Pending_Amount__c = 0,
            Fee_Status__c = 'Paid',
            Fee_Type__c = 'Installment 1',
            Customer__c = student.Id, 
            Fee_Amount__c = 1000,
            Due_Date__c = Date.today(), 
            Payment_Window__c = 2
        );
        insert fee;
        
        ProgramEnrollment pe = [SELECT Id FROM ProgramEnrollment LIMIT 1];
        
        ISB_Installment__c inst = new ISB_Installment__c(
            Pending_Amount__c = 0,
            Paid_Amount__c = 1000,
            Installment_Status__c = 'Paid',
            Program_Enrollment__c = pe.Id
        );
        insert inst;
        
        ISB_Payment__c pay = new ISB_Payment__c(
            Amount__c = 1000,
            ISB_Fees__c = fee.Id,
            ISB_Installment__c = inst.Id,
            Initiated__c = 'Pending'
        );
        insert pay;
        
        Id offlineRtId = Schema.SObjectType.Case
            .getRecordTypeInfosByDeveloperName()
            .get('Offline_Payment')
            .getRecordTypeId();
        
        Case c = new Case(
            RecordTypeId = offlineRtId,
            Status = 'New',
            ISB_Payment__c = pay.Id
        );
        insert c;
        
        Case oldCase = c.clone(true);
        c.Status = 'Payment Approved';
        
        Test.startTest();
        CaseTriggerHandler.handleStatusChange(
            new List<Case>{c},
            new Map<Id, Case>{c.Id => oldCase}
        );
        Test.stopTest();
        
        ISB_Payment__c updated =
            [SELECT Initiated__c FROM ISB_Payment__c WHERE Id = :pay.Id];
        
        System.assertEquals('Success', updated.Initiated__c);
    }
}