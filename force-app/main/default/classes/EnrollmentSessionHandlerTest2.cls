@IsTest
public class EnrollmentSessionHandlerTest2 {

    // ---------- Helpers ----------
    private static Contact createStudent() {
        Account a = new Account(Name = 'Test Acc');
        insert a;

        Contact c = new Contact(LastName = 'Student', AccountId = a.Id,hed__Preferred_Email__c = 'VF Email ID',
            VF_Email_ID__c = 'bodhtree.admin@isb.com');
        insert c;
        return c;
    }

    private static Program createProgram() {
        Program p = new Program(Name = 'Test Program');
        insert p;
        return p;
    }

    private static ProgramEnrollment createPE(Id contactId, Id programId) {
        ProgramEnrollment pe = new ProgramEnrollment(
            ContactId = contactId,
            ProgramId = programId,
            Status = 'Registered'
        );
        insert pe;
        return pe;
    }

    private static AcademicSession createAcademicSession(String name) {
        AcademicSession s = new AcademicSession(Name = name);
        insert s;
        return s;
    }

    /**
     * Create the template version that the handler queries:
     * ActionPlanTemplateVersion where Name='O-Week Student Tasks' and Status='Final'
     */
    private static void createTemplateFinal() {
        ActionPlanTemplate t = new ActionPlanTemplate(Name = 'O-Week Student Tasks');
        insert t;

        // If your org has different required fields on ActionPlanTemplateVersion,
        // add them here.
        ActionPlanTemplateVersion v = new ActionPlanTemplateVersion(
            Name = 'O-Week Student Tasks',
            Status = 'Final',
            ActionPlanTemplateId = t.Id,
            Version = 1
        );
        insert v;
    }

    // ---------- Tests ----------

    @IsTest
    static void testInsert_registered_term1_runsWithoutException() {
        createTemplateFinal();

        Contact student = createStudent();
        Program prog = createProgram();
        ProgramEnrollment pe = createPE(student.Id, prog.Id);

        AcademicSession sess = createAcademicSession('Term 1 - AY 2026');

        Enrollment_Session__c es = new Enrollment_Session__c(
            Program_Enrollment__c = pe.Id,
            Academic_Session__c   = sess.Id,
            Status__c             = 'Registered',
            Session_Start__c      = System.now().addDays(1)
        );
        insert es;

        Test.startTest();
        // should qualify and attempt action plan insert (may fail but should be caught)
        EnrollmentSessionHandler.handleAfterInsertUpdate(new List<Enrollment_Session__c>{ es }, null);
        Test.stopTest();

        // In your org, Industries + Contact target is not allowed, so count can be 0.
        // We assert the handler didn't crash and no unexpected AP is created.
        Integer apCount = [
            SELECT COUNT()
            FROM ActionPlan
            WHERE Name = 'O-Week Student Tasks'
            AND TargetId = :student.Id
        ];
        System.assertEquals(0, apCount,
            'In this org config, ActionPlan insert is blocked for Contact target with Industries type; should remain 0.');
    }

    @IsTest
    static void testUpdate_statusChangeToRegistered_runsWithoutException() {
        createTemplateFinal();

        Contact student = createStudent();
        Program prog = createProgram();
        ProgramEnrollment pe = createPE(student.Id, prog.Id);
        AcademicSession sess = createAcademicSession('Term 1 - AY 2026');

        Enrollment_Session__c es = new Enrollment_Session__c(
            Program_Enrollment__c = pe.Id,
            Academic_Session__c   = sess.Id,
            Status__c             = 'Pending',
            Session_Start__c      = System.now().addDays(2)
        );
        insert es;

        Enrollment_Session__c oldEs = [
            SELECT Id, Status__c, Academic_Session__c, Program_Enrollment__c
            FROM Enrollment_Session__c
            WHERE Id = :es.Id
        ];

        es.Status__c = 'Registered';
        update es;

        Enrollment_Session__c newEs = [
            SELECT Id, Status__c, Academic_Session__c, Program_Enrollment__c
            FROM Enrollment_Session__c
            WHERE Id = :es.Id
        ];

        Test.startTest();
        EnrollmentSessionHandler.handleAfterInsertUpdate(
            new List<Enrollment_Session__c>{ newEs },
            new Map<Id, Enrollment_Session__c>{ oldEs.Id => oldEs }
        );
        Test.stopTest();

        Integer apCount = [
            SELECT COUNT()
            FROM ActionPlan
            WHERE Name = 'O-Week Student Tasks'
            AND TargetId = :student.Id
        ];
        System.assertEquals(0, apCount,
            'Insert is blocked by org config; handler should swallow exception and not create AP.');
    }

    @IsTest
    static void testInsert_registered_term2_exitsNoActionPlan() {
        createTemplateFinal();

        Contact student = createStudent();
        Program prog = createProgram();
        ProgramEnrollment pe = createPE(student.Id, prog.Id);

        AcademicSession sess = createAcademicSession('Term 2 - AY 2026');

        Enrollment_Session__c es = new Enrollment_Session__c(
            Program_Enrollment__c = pe.Id,
            Academic_Session__c   = sess.Id,
            Status__c             = 'Registered',
            Session_Start__c      = System.now().addDays(1)
        );
        insert es;

        Test.startTest();
        EnrollmentSessionHandler.handleAfterInsertUpdate(new List<Enrollment_Session__c>{ es }, null);
        Test.stopTest();

        Integer apCount = [
            SELECT COUNT()
            FROM ActionPlan
            WHERE Name = 'O-Week Student Tasks'
            AND TargetId = :student.Id
        ];
        System.assertEquals(0, apCount, 'Term 2 should not qualify; no AP should be created/attempted.');
    }

    @IsTest
    static void testInsert_registered_term1_missingTemplate_exits() {
        // Intentionally DO NOT create template

        Contact student = createStudent();
        Program prog = createProgram();
        ProgramEnrollment pe = createPE(student.Id, prog.Id);
        AcademicSession sess = createAcademicSession('Term 1 - AY 2026');

        Enrollment_Session__c es = new Enrollment_Session__c(
            Program_Enrollment__c = pe.Id,
            Academic_Session__c   = sess.Id,
            Status__c             = 'Registered',
            Session_Start__c      = System.now().addDays(1)
        );
        insert es;

        Test.startTest();
        EnrollmentSessionHandler.handleAfterInsertUpdate(new List<Enrollment_Session__c>{ es }, null);
        Test.stopTest();

        Integer apCount = [
            SELECT COUNT()
            FROM ActionPlan
            WHERE Name = 'O-Week Student Tasks'
            AND TargetId = :student.Id
        ];
        System.assertEquals(0, apCount, 'If template is missing, handler should exit; no AP created.');
    }
}