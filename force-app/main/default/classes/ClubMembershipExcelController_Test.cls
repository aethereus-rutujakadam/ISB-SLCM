@isTest
public class ClubMembershipExcelController_Test {

    @testSetup
    static void setupTestData() {
        // Create Accounts
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        // Create Contacts (Students)
        List<Contact> contacts = new List<Contact>();
        contacts.add(new Contact(FirstName = 'John', LastName = 'Doe', AccountId = acc.Id, Email = 'john.doe@isb.edu'));
        contacts.add(new Contact(FirstName = 'Jane', LastName = 'Smith', AccountId = acc.Id, Email = 'jane.smith@isb.edu'));
        contacts.add(new Contact(FirstName = 'Peter', LastName = 'Jones', AccountId = acc.Id, Email = 'peter.jones@isb.edu'));
        insert contacts;

        List<Program> Prog = new List<Program>();
        Prog.add(new Program(Name = 'PGP', StartDate = System.today()));  
        Prog.add(new Program(Name = 'PGPYL', StartDate = System.today()));   
        insert Prog;

        // Create Program Enrollments with PGID__c (Student Id)
        List<ProgramEnrollment> pes = new List<ProgramEnrollment>();
        pes.add(new ProgramEnrollment(ContactId = contacts[0].Id, PGID__c = 'S001', ProgramId = Prog[0].Id, Name = 'PE1'));
        pes.add(new ProgramEnrollment(ContactId = contacts[1].Id, PGID__c = 'S002', ProgramId = Prog[1].Id, Name = 'PE2'));
        pes.add(new ProgramEnrollment(ContactId = contacts[2].Id, PGID__c = 'S003', ProgramId = Prog[0].Id, Name = 'PE3'));
        insert pes;

        // Create Club RecordTypes if they don't exist
        Id councilRtId = Schema.SObjectType.Club__c.getRecordTypeInfosByDeveloperName().get('Council').getRecordTypeId();
        Id socialClubRtId = Schema.SObjectType.Club__c.getRecordTypeInfosByDeveloperName().get('Social_Club').getRecordTypeId();

        // Create Clubs
        List<Club__c> clubs = new List<Club__c>();
        clubs.add(new Club__c(Name = 'Chess Club', RecordTypeId = councilRtId, Program__c = Prog[0].id)); 
        clubs.add(new Club__c(Name = 'Debate Society', RecordTypeId = councilRtId, Program__c = Prog[1].id)); 
        clubs.add(new Club__c(Name = 'Art Club', RecordTypeId = socialClubRtId)); // Assign a different RecordType
        insert clubs;

        // Create initial Club Memberships for update scenarios
        Club_Membership__c existingMembership = new Club_Membership__c(
            Contact__c = contacts[0].Id,
            Club__c = clubs[0].Id,
            Role__c = 'Member',
            Status__c = 'Active',
            Start_Date__c = System.today().addDays(-30),
            End_Date__c = System.today().addMonths(11),
            Source__c = 'CSV Upload'
        );
        insert existingMembership;

        Club_Membership__c existingMembership2 = new Club_Membership__c(
            Contact__c = contacts[1].Id,
            Club__c = clubs[1].Id,            
            Status__c = 'Active',
            Start_Date__c = System.today().addDays(-60),
            End_Date__c = System.today().addMonths(10),
            Source__c = 'CSV Upload'
        );
        insert existingMembership2;
    }   

    @isTest
    static void testProcessExcelRows_MixedInsertAndUpdate() {
        Contact c1 = [SELECT Id FROM Contact WHERE Id IN (SELECT ContactId FROM ProgramEnrollment WHERE PGID__c = 'S001') LIMIT 1];
        String c1StudentId = 'S001';
        Club__c chessClub = [SELECT Id, Name FROM Club__c WHERE Name = 'Chess Club' LIMIT 1];
        Contact c2 = [SELECT Id FROM Contact WHERE Id IN (SELECT ContactId FROM ProgramEnrollment WHERE PGID__c = 'S002') LIMIT 1];
        String c2StudentId = 'S002';
        Club__c artClub = [SELECT Id, Name FROM Club__c WHERE Name = 'Art Club' LIMIT 1];

        List<Map<String, String>> rows = new List<Map<String, String>>();
        // Update existing membership for S001 in Chess Club
        rows.add(new Map<String, String>{
            'StudentId' => c1StudentId,
            'ClubName' => chessClub.Name,
            'Role' => 'Vice President',
            'Status' => 'Active'
        });
        // Insert new membership for S002 in Art Club
        rows.add(new Map<String, String>{
            'StudentId' => c2StudentId,
            'ClubName' => artClub.Name,
            'Role' => 'Member',
            'Status' => 'Active'
        });

        Test.startTest();
        Map<String, Object> result = ClubMembershipExcelController.processExcelRows(JSON.serialize(rows));
        Test.stopTest();

        Club_Membership__c updatedMembership = [SELECT Id, Role__c FROM Club_Membership__c WHERE Contact__c = :c1.Id AND Club__c = :chessClub.Id];
        Club_Membership__c newMembership = [SELECT Id, Role__c FROM Club_Membership__c WHERE Contact__c = :c2.Id AND Club__c = :artClub.Id];
    }

    @isTest
    static void testProcessExcelRows_EmptyJsonRows() {
        Test.startTest();
        Map<String, Object> result = ClubMembershipExcelController.processExcelRows('');
        Test.stopTest();
    }

    @isTest
    static void testProcessExcelRows_InvalidJsonFormat() {
        Test.startTest();
        Map<String, Object> result = ClubMembershipExcelController.processExcelRows('{"key": "value"}'); // Not an array
        Test.stopTest();
    }
   

    @isTest
    static void testProcessExcelRows_MissingStudentId() {
        Club__c chessClub = [SELECT Id, Name FROM Club__c WHERE Name = 'Chess Club' LIMIT 1];

        List<Map<String, String>> rows = new List<Map<String, String>>();
        rows.add(new Map<String, String>{
            'ClubName' => chessClub.Name,
            'Role' => 'Member'
        });

        Test.startTest();
        Map<String, Object> result = ClubMembershipExcelController.processExcelRows(JSON.serialize(rows));
        Test.stopTest();
    }

    @isTest
    static void testProcessExcelRows_ContactNotFound() {
        Club__c chessClub = [SELECT Id, Name FROM Club__c WHERE Name = 'Chess Club' LIMIT 1];

        List<Map<String, String>> rows = new List<Map<String, String>>();
        rows.add(new Map<String, String>{
            'StudentId' => 'NONEXISTENT',
            'ClubName' => chessClub.Name,
            'Role' => 'Member'
        });

        Test.startTest();
        Map<String, Object> result = ClubMembershipExcelController.processExcelRows(JSON.serialize(rows));
        Test.stopTest();
    }

    @isTest
    static void testProcessExcelRows_ClubNotFound() {
        String c1StudentId = 'S001';

        List<Map<String, String>> rows = new List<Map<String, String>>();
        rows.add(new Map<String, String>{
            'StudentId' => c1StudentId,
            'ClubName' => 'NonExistent Club',
            'Role' => 'Member'
        });

        Test.startTest();
        Map<String, Object> result = ClubMembershipExcelController.processExcelRows(JSON.serialize(rows));
        Test.stopTest();
    }

    @isTest
    static void testProcessExcelRows_DuplicateMembershipAttempt() {
        Contact c1 = [SELECT Id FROM Contact WHERE Id IN (SELECT ContactId FROM ProgramEnrollment WHERE PGID__c = 'S001') LIMIT 1];
        String c1StudentId = 'S001';
        Club__c chessClub = [SELECT Id, Name FROM Club__c WHERE Name = 'Chess Club' LIMIT 1];

        List<Map<String, String>> rows = new List<Map<String, String>>();
        rows.add(new Map<String, String>{
            'StudentId' => c1StudentId,
            'ClubName' => chessClub.Name,
            'Role' => 'Member', // Existing role
            'Status' => 'Active' // Existing status
        });

        Test.startTest();
        Map<String, Object> result = ClubMembershipExcelController.processExcelRows(JSON.serialize(rows));
        Test.stopTest();
    }

    @isTest
    static void testProcessExcelRows_CaseInsensitiveMatching() {
        Contact c1 = [SELECT Id FROM Contact WHERE Id IN (SELECT ContactId FROM ProgramEnrollment WHERE PGID__c = 'S001') LIMIT 1];
        String c1StudentId = 'S001';
        Club__c chessClub = [SELECT Id, Name FROM Club__c WHERE Name = 'Chess Club' LIMIT 1];

        List<Map<String, String>> rows = new List<Map<String, String>>();
        rows.add(new Map<String, String>{
            'StudentId' => c1StudentId.toLowerCase(), // Lowercase student ID
            'ClubName' => chessClub.Name.toUpperCase(),    // Uppercase club name
            'Role' => 'President', 
            'Status' => 'Inactive'
        });

        Test.startTest();
        Map<String, Object> result = ClubMembershipExcelController.processExcelRows(JSON.serialize(rows));
        Test.stopTest();

        Club_Membership__c updatedMembership = [SELECT Id, Role__c, Status__c FROM Club_Membership__c WHERE Contact__c = :c1.Id AND Club__c = :chessClub.Id];
    }

    @isTest
    static void testProcessExcelRows_CsvGeneration() {
        String c3StudentId = 'S003';
        Club__c artClub = [SELECT Id, Name FROM Club__c WHERE Name = 'Art Club' LIMIT 1];

        List<Map<String, String>> rows = new List<Map<String, String>>();
        rows.add(new Map<String, String>{
            'StudentId' => c3StudentId,
            'ClubName' => artClub.Name,
            'Role' => 'Member',
            'Status' => 'Active'
        });

        Test.startTest();
        Map<String, Object> result = ClubMembershipExcelController.processExcelRows(JSON.serialize(rows));
        Test.stopTest();
    }

    @isTest
    static void testCreateResultFile_Success() {
        String testContent = 'Header1,Header2\nValue1,Value2';
        String base64Content = EncodingUtil.base64Encode(Blob.valueOf(testContent));
        String fileName = 'MyTestResult.csv';

        Test.startTest();
        Id cvId = ClubMembershipExcelController.createResultFile(base64Content, fileName);
        Test.stopTest();
    }   
   

    @isTest
    static void testProcessExcelRows_EmptyRoleAndStatus() {
        String c3StudentId = 'S003';
        Club__c artClub = [SELECT Id, Name FROM Club__c WHERE Name = 'Art Club' LIMIT 1];

        List<Map<String, String>> rows = new List<Map<String, String>>();
        rows.add(new Map<String, String>{
            'StudentId' => c3StudentId,
            'ClubName' => artClub.Name,
            'Role' => '',     // Empty role
            'Status' => null  // Null status
        });

        Test.startTest();
        Map<String, Object> result = ClubMembershipExcelController.processExcelRows(JSON.serialize(rows));
        Test.stopTest();

        Club_Membership__c newMembership = [SELECT Id, Role__c, Status__c FROM Club_Membership__c WHERE Contact__c IN (SELECT ContactId FROM ProgramEnrollment WHERE PGID__c = 'S003') AND Club__c = :artClub.Id];
    }

    @isTest
    static void testProcessExcelRows_ValidationFail_ProgramSpecificRole() {
        String c3StudentId = 'S003';

        List<Program> Prog1 = new List<Program>();
        Prog1.add(new Program(Name = 'AMBP', StartDate = System.today()));  
        Prog1.add(new Program(Name = 'HYJ', StartDate = System.today()));   
        insert Prog1;  

        Id councilRtId = Schema.SObjectType.Club__c.getRecordTypeInfosByDeveloperName().get('Council').getRecordTypeId();
        Club__c nonPgpClub = new Club__c(Name = 'Book Club', RecordTypeId = councilRtId, Program__c = Prog1[0].id);
        insert nonPgpClub;

        List<Map<String, String>> rows = new List<Map<String, String>>();
        rows.add(new Map<String, String>{
            'StudentId' => c3StudentId,
            'ClubName' => nonPgpClub.Name,
            'Role' => 'Lead', // This should fail the validation 'For programs other than PGP & PGPYL, only Lead role is allowed.'
            'Status' => 'Active'
        });

        Test.startTest();
        Map<String, Object> result = ClubMembershipExcelController.processExcelRows(JSON.serialize(rows));
        Test.stopTest();
    }
}