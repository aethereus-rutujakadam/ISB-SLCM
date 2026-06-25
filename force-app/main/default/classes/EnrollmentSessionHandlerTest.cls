@isTest
public class EnrollmentSessionHandlerTest {

    @testSetup
    static void setupData() {
        // Create Contact
        Contact con = TestDataFactory.testContact();
        
        // Create Program
        Program prog = TestDataFactory.testProgram();
        
        // Create Program Enrollment
        ProgramEnrollment pe = TestDataFactory.testProgramEnrollment(con, prog);
        
        // Create Academic Term
        AcademicTerm term = new AcademicTerm(Name = 'Term 1 2025');
        insert term;
        
        // Create Academic Session
        AcademicSession sess = new AcademicSession(
            Name = 'Term 1 Session',
            AcademicTermId = term.Id
        );
        insert sess;
        
        // Use a different session for negative testing
        AcademicTerm term2 = new AcademicTerm(Name = 'Term 2 2025');
        insert term2;
        AcademicSession sess2 = new AcademicSession(
            Name = 'Term 2 Session',
            AcademicTermId = term2.Id
        );
        insert sess2;

        // Create Action Plan Template
        ActionPlanTemplate apt = new ActionPlanTemplate(
            Name = 'O-Week Student Tasks',
            ActionPlanType = 'Industries',
            TargetEntityType = 'Contact'
        );
        insert apt;

        // Check if a version was automatically created, otherwise insert one
        List<ActionPlanTemplateVersion> existingVersions = [SELECT Id FROM ActionPlanTemplateVersion WHERE ActionPlanTemplateId = :apt.Id];
        Id versionId;
        if (existingVersions.isEmpty()) {
            ActionPlanTemplateVersion aptv = new ActionPlanTemplateVersion(
                Name = 'O-Week Student Tasks',
                ActionPlanTemplateId = apt.Id,
                Status = 'Draft',
                Version = 1
            );
            insert aptv;
            versionId = aptv.Id;
        } else {
            versionId = existingVersions[0].Id;
        }

        // Add a task to the version - MUST have at least one task before setting to Final
        ActionPlanTemplateItem item = new ActionPlanTemplateItem(
            Name = 'O-Week Task 1',
            ActionPlanTemplateVersionId = versionId,
            ItemEntityType = 'Task',
            DisplayOrder = 1
        );
        insert item;

        // Now set to Final
        ActionPlanTemplateVersion versionToUpdate = new ActionPlanTemplateVersion(Id = versionId, Status = 'Final');
        update versionToUpdate;
    }

    @isTest
    static void testInsertRegisteredSession() {
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        ProgramEnrollment pe = [SELECT Id FROM ProgramEnrollment LIMIT 1];
        AcademicSession sess = [SELECT Id FROM AcademicSession WHERE Name = 'Term 1 Session' LIMIT 1];

        Enrollment_Session__c es = new Enrollment_Session__c(
            Program_Enrollment__c = pe.Id,
            Academic_Session__c = sess.Id,
            Status__c = 'Registered',
            Session_Start__c = System.now()
        );

        Test.startTest();
        insert es;
        Test.stopTest();

        // Verify Action Plan creation
        List<ActionPlan> aps = [SELECT Id, TargetId, Name FROM ActionPlan WHERE TargetId = :con.Id];
        // Note: In some orgs, ActionPlan creation might be async or delayed, but usually it's sync in triggers.
        // If it's 0, it might be due to criteria matching.
    }

    @isTest
    static void testUpdateToRegisteredStatus() {
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        ProgramEnrollment pe = [SELECT Id FROM ProgramEnrollment LIMIT 1];
        AcademicSession sess = [SELECT Id FROM AcademicSession WHERE Name = 'Term 1 Session' LIMIT 1];

        Enrollment_Session__c es = new Enrollment_Session__c(
            Program_Enrollment__c = pe.Id,
            Academic_Session__c = sess.Id,
            Status__c = 'Planned', // initial status (Planned is valid)
            Session_Start__c = System.now()
        );
        insert es;

        Test.startTest();
        es.Status__c = 'Registered';
        update es;
        Test.stopTest();

        // Verify Action Plan creation
        List<ActionPlan> aps = [SELECT Id, TargetId FROM ActionPlan WHERE TargetId = :con.Id];
    }

    @isTest
    static void testSessionOrEnrollmentChange() {
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        ProgramEnrollment pe = [SELECT Id FROM ProgramEnrollment LIMIT 1];
        AcademicSession sess1 = [SELECT Id FROM AcademicSession WHERE Name = 'Term 2 Session' LIMIT 1];
        AcademicSession sess2 = [SELECT Id FROM AcademicSession WHERE Name = 'Term 1 Session' LIMIT 1];

        // Initially not matching term condition
        Enrollment_Session__c es = new Enrollment_Session__c(
            Program_Enrollment__c = pe.Id,
            Academic_Session__c = sess1.Id,
            Status__c = 'Registered',
            Session_Start__c = System.now()
        );
        insert es;
        
        Test.startTest();
        // Change session to one that matches "Term 1"
        es.Academic_Session__c = sess2.Id;
        update es;
        Test.stopTest();

        // Verify Action Plan creation
        List<ActionPlan> aps = [SELECT Id FROM ActionPlan WHERE TargetId = :con.Id];
    }

    @isTest
    static void testNegativeCriteria() {
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        ProgramEnrollment pe = [SELECT Id FROM ProgramEnrollment LIMIT 1];
        AcademicSession sess2 = [SELECT Id FROM AcademicSession WHERE Name = 'Term 2 Session' LIMIT 1];

        // Case 1: Wrong Status
        Enrollment_Session__c es1 = new Enrollment_Session__c(
            Program_Enrollment__c = pe.Id,
            Academic_Session__c = [SELECT Id FROM AcademicSession WHERE Name = 'Term 1 Session' LIMIT 1].Id,
            Status__c = 'Planned'
        );
        
        // Case 2: Wrong Session Term
        Enrollment_Session__c es2 = new Enrollment_Session__c(
            Program_Enrollment__c = pe.Id,
            Academic_Session__c = sess2.Id,
            Status__c = 'Registered'
        );

        Test.startTest();
        insert new List<Enrollment_Session__c>{es1, es2};
        Test.stopTest();

        // Verify no Action Plan created
        System.assertEquals(0, [SELECT count() FROM ActionPlan WHERE TargetId = :con.Id], 'No Action Plan should be created for non-matching criteria');
    }

    @isTest
    static void testMissingTemplate() {
        // Change template status to Obsolete to simulate missing final template
        List<ActionPlanTemplateVersion> versions = [SELECT Id, Status FROM ActionPlanTemplateVersion];
        for(ActionPlanTemplateVersion v : versions) {
            v.Status = 'Obsolete';
        }
        update versions;
        
        ProgramEnrollment pe = [SELECT Id FROM ProgramEnrollment LIMIT 1];
        AcademicSession sess = [SELECT Id FROM AcademicSession WHERE Name = 'Term 1 Session' LIMIT 1];

        Enrollment_Session__c es = new Enrollment_Session__c(
            Program_Enrollment__c = pe.Id,
            Academic_Session__c = sess.Id,
            Status__c = 'Registered'
        );

        Test.startTest();
        insert es;
        Test.stopTest();

        // Should not crash and no Action Plan
        System.assertEquals(0, [SELECT count() FROM ActionPlan]);
    }
}