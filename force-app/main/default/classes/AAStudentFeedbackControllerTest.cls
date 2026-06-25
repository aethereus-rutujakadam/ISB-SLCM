@isTest
public class AAStudentFeedbackControllerTest {

    @testSetup
    static void setup() {
        // 1. Setup Student
        Contact studentCon = TestDataFactory.testContact();
        
        // 2. Setup Program and Term (needed for AA Profile)
        Program prog = TestDataFactory.testProgram();
        AcademicTerm term = TestDataFactory.testAcademicTerm(prog.Id);
        
        // 3. Setup AA User and Linked Contact
        User aaUser = TestDataFactory.testUser('aaUser', 'aauser@test.isb.com');
        Contact aaCon = TestDataFactory.testAAContact(aaUser);
        
        // 4. Setup AA Profile
        AA_Profile__c aaProfile = TestDataFactory.testAAProfile(term.Id, aaCon.Id);
        aaProfile.Primary_Program__c = prog.Id;
        update aaProfile;
        
        // 5. Setup Case
        Case c = new Case(
            Subject = 'Test Case',
            ContactId = studentCon.Id,
            Origin = 'Web',
            Status = 'New'
        );
        insert c;
        
        // 6. Setup Case Team Role
        CaseTeamRole aaRole = [SELECT Id FROM CaseTeamRole WHERE Name = 'Academic Associate' LIMIT 1];
        
        // 7. Add AA User to Case Team
        CaseTeamMember ctm = new CaseTeamMember(
            ParentId = c.Id,
            MemberId = aaUser.Id,
            TeamRoleId = aaRole.Id
        );
        insert ctm;
    }

    @isTest
    static void testSubmitFeedbackSuccess() {
        Case c = [SELECT Id FROM Case LIMIT 1];
        
        Test.startTest();
        String resultId = AAStudentFeedbackController.submitFeedback(c.Id, 4, 'Great support!');
        Test.stopTest();
        
        System.assertNotEquals(null, resultId, 'Feedback record should be created');
        
        Feedback__c f = [SELECT Id, Overall_Rating__c, Comments__c, Academic_Associate__c FROM Feedback__c WHERE Id = :resultId];
        System.assertEquals('4', f.Overall_Rating__c);
        System.assertEquals('Great support!', f.Comments__c);
    }

    @isTest
    static void testSubmitFeedbackNullCaseId() {
        try {
            AAStudentFeedbackController.submitFeedback(null, 5, 'Comment');
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assertEquals('Script-thrown exception', e.getMessage());
        }
    }

    @isTest
    static void testSubmitFeedbackCaseNotFound() {
        Id fakeId = TestDataFactory.getFakeId(Case.SObjectType);
        try {
            AAStudentFeedbackController.submitFeedback(fakeId, 5, 'Comment');
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @isTest
    static void testSubmitFeedbackNoStudentContact() {
        Case c = new Case(Subject = 'No Student Case');
        insert c;
        
        try {
            AAStudentFeedbackController.submitFeedback(c.Id, 5, 'Comment');
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @isTest
    static void testSubmitFeedbackNoTeamMember() {
        Contact studentCon = [SELECT Id FROM Contact WHERE LastName LIKE 'Student%' LIMIT 1];
        Case c = new Case(Subject = 'No Team Case', ContactId = studentCon.Id);
        insert c;
        
        try {
            AAStudentFeedbackController.submitFeedback(c.Id, 5, 'Comment');
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @isTest
    static void testSubmitFeedbackNoAAContact() {
        // Create user without linked contact
        User u = TestDataFactory.testUser('noCon', 'nocon@test.isb.com');
        Contact studentCon = [SELECT Id FROM Contact WHERE LastName LIKE 'Student%' LIMIT 1];
        Case c = new Case(Subject = 'No AA Contact Case', ContactId = studentCon.Id);
        insert c;
        
        CaseTeamRole aaRole = [SELECT Id FROM CaseTeamRole WHERE Name = 'Academic Associate' LIMIT 1];
        insert new CaseTeamMember(ParentId = c.Id, MemberId = u.Id, TeamRoleId = aaRole.Id);
        
        try {
            AAStudentFeedbackController.submitFeedback(c.Id, 5, 'Comment');
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @isTest
    static void testSubmitFeedbackNoAAProfile() {
        // Contact without profile
        Contact aaCon = new Contact(
            FirstName = 'No', 
            LastName = 'Profile', 
            Email = 'noprofile@test.com',
            VF_Email_ID__c = 'noprofile@test.com',
            hed__Preferred_Email__c = 'VF Email ID'
        );
        insert aaCon;
        
        Contact studentCon = [SELECT Id FROM Contact WHERE LastName LIKE 'Student%' LIMIT 1];
        Case c = new Case(Subject = 'No Profile Case', ContactId = studentCon.Id);
        insert c;
        
        CaseTeamRole aaRole = [SELECT Id FROM CaseTeamRole WHERE Name = 'Academic Associate' LIMIT 1];
        insert new CaseTeamMember(ParentId = c.Id, MemberId = aaCon.Id, TeamRoleId = aaRole.Id);
        
        try {
            AAStudentFeedbackController.submitFeedback(c.Id, 5, 'Comment');
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @isTest
    static void testSubmitFeedbackDuplicate() {
        Case c = [SELECT Id FROM Case LIMIT 1];
        AAStudentFeedbackController.submitFeedback(c.Id, 5, 'First');
        
        try {
            AAStudentFeedbackController.submitFeedback(c.Id, 3, 'Second');
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Script-thrown exception'));
        }
    }
}