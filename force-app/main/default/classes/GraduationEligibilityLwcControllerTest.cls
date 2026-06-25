@IsTest
public class GraduationEligibilityLwcControllerTest {

    /* =========================================================
       TEST DATA SETUP (Lookup-filter safe)
       ========================================================= */
    @TestSetup
static void setupData() {
    // 1. Create a unique User to run the test. 
    // This often prevents conflicts with 'Running User' logic in Flows.
    User tUser = TestDataFactory.testUser('GradTest', 'gradtest@example.com');

    System.runAs(tUser) {
        // 2. Create Contact
        Contact con = new Contact(
            LastName = 'Student',
            Email = 'unique_student@test.com'
        );
        insert con;

        // 3. Setup Academic foundation
        AcademicYear ay = new AcademicYear(Name = '2024-25');
        insert ay;

        Program program = new Program(Name = 'BTech');
        insert program;

        AcademicTerm term = new AcademicTerm(
            Name = 'Term 1', 
            Program__c = program.Id
        );
        insert term;

        // 4. Create Academic Session (This defines the 'sess' variable)
        AcademicSession sess = new AcademicSession(
            Name = '2024 Fall Session',
            AcademicTermId = term.Id
        );
        insert sess;

        // 4. Create Case (FIX: Link Contact IMMEDIATELY to satisfy Flow logic)
        // Linking the Contact here might help the flow identify the student 
        // correctly or we can try NOT linking it if the Flow adds the contact automatically.
        Case cs = new Case(
            Subject = 'Graduation Case',
            Program__c = program.Id,
            Academic_Year__c = ay.Id,
            Academic_Term__c = term.Id,
            ContactId = con.Id // Ensure this is set to avoid Flow 'Add to Team' logic missing context
        );
        
        // If the error persists, try inserting the Case WITHOUT the ContactId 
        // to see if the Flow is trying to add the 'Case Contact' to the team.
        insert cs;

        // 5. Setup Enrollment and Eligibility
        ProgramEnrollment pe = new ProgramEnrollment(
            ContactId = con.Id,
            Status = 'Applied',
            ProgramId = program.Id
        );
        insert pe;

        Graduation_Eligibility__c ge = new Graduation_Eligibility__c(
            Program__c = program.Id,
            Academic_Year__c = ay.Id,
            Academic_Term__c = term.Id,
            Program_Enrollment__c = pe.Id,
            Case__c = cs.Id,
            Eligibility_Status__c = 'Approved',
            Notes__c = 'Initial'
        );
        insert ge;

        Enrollment_Session__c es = new Enrollment_Session__c(
            Program_Enrollment__c = pe.Id,
            Academic_Session__c = sess.Id,
            Status__c = 'Registered'
        );
        insert es;

        // 6. Template
        EmailTemplate et = new EmailTemplate(
            Name = 'Graduated',
            DeveloperName = 'Graduated',
            TemplateType = 'text',
            Subject = 'Graduation',
            Body = 'Congrats!',
            FolderId = tUser.Id // Use the test user ID
        );
        insert et;
    }
}

    /* =========================================================
       fetchEligibiltystatus
       ========================================================= */
    @IsTest
    static void testFetchEligibilityStatus_success() {

        Case cs = [SELECT Id FROM Case LIMIT 1];

        Test.startTest();
        List<Graduation_Eligibility__c> result =
            GraduationEligibilityLwcController.fetchEligibiltystatus(cs.Id);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals(1, result.size());
    }

    /* =========================================================
       getPicklistValues
       ========================================================= */
    @IsTest
    static void testGetPicklistValues_success() {

        Test.startTest();
        List<Map<String, String>> values =
            GraduationEligibilityLwcController.getPicklistValues(
                'Graduation_Eligibility__c',
                'Eligibility_Status__c'
            );
        Test.stopTest();

        System.assert(values.size() > 0);
        System.assert(values[0].containsKey('label'));
        System.assert(values[0].containsKey('value'));
    }

    /* =========================================================
       updateEligibilities
       ========================================================= */
    @IsTest
    static void testUpdateEligibilities_success() {

        Graduation_Eligibility__c ge =
            [SELECT Id, Notes__c FROM Graduation_Eligibility__c LIMIT 1];

        List<Map<String, Object>> updates = new List<Map<String, Object>>();
        Map<String, Object> row = new Map<String, Object>{
            'Id' => ge.Id,
            'Notes__c' => 'Updated Notes',
            'Eligibility_Status__c' => 'Approved'
        };
        updates.add(row);

        Test.startTest();
        GraduationEligibilityLwcController.updateEligibilities(updates);
        Test.stopTest();

        Graduation_Eligibility__c updated =
            [SELECT Notes__c FROM Graduation_Eligibility__c WHERE Id = :ge.Id];

        System.assertEquals('Updated Notes', updated.Notes__c);
    }

    /* =========================================================
       sendGraduationEmails — SUCCESS
       ========================================================= */
    @IsTest
    static void testSendGraduationEmails_success() {

        Case cs = [SELECT Id FROM Case LIMIT 1];

        Test.startTest();
        String result =
            GraduationEligibilityLwcController.sendGraduationEmails(cs.Id);
        Test.stopTest();

        System.assert(result.contains('sent'));
    }

    /* =========================================================
       sendGraduationEmails — NO APPROVED RECORDS
       ========================================================= */
    @IsTest
    static void testSendGraduationEmails_noApproved() {

        Graduation_Eligibility__c ge =
            [SELECT Id FROM Graduation_Eligibility__c LIMIT 1];

        ge.Eligibility_Status__c = 'Rejected';
        update ge;

        Case cs = [SELECT Id FROM Case LIMIT 1];

        Test.startTest();
        String result =
            GraduationEligibilityLwcController.sendGraduationEmails(cs.Id);
        Test.stopTest();

        System.assertEquals('No approved eligibility records found.', result);
    }
}