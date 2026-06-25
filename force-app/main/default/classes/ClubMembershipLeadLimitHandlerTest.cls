@isTest
private class ClubMembershipLeadLimitHandlerTest {

    public class TestLibrary {
        public Club_Membership__c createMembershipInMem(String programName, String yearName, String role, String status, String clubRtDevName) {
            Map<String, Object> attributes = new Map<String, Object>{ 'type' => 'Club_Membership__c' };
            
            // FIX: We must pass the TEXT Name here (e.g., 'MBA'), not the ID.
            // This forces the mock formula field to match the DB query result.
            Map<String, Object> record = new Map<String, Object>{
                'attributes' => attributes,
                'Program__c' => programName,
                'Academic_Year__c' => yearName,
                'Role__c' => role,
                'Status__c' => status,
                'Club_Record_Type__c' => clubRtDevName
            };
            return (Club_Membership__c) JSON.deserialize(JSON.serialize(record), Club_Membership__c.class);
        }

        public Club__c createClub(String name, Id programId, Id academicYearId, String rtDevName) {
            Id rtId = Schema.SObjectType.Club__c.getRecordTypeInfosByDeveloperName().get(rtDevName)?.getRecordTypeId();
            Club__c c = new Club__c(
                Name = name,
                RecordTypeId = rtId,
                Program__c = programId,
                Academic_Year__c = academicYearId
            );
            insert c;
            return c;
        }
    }

    @TestSetup
    static void setup() {
        Program prog = new Program(Name = 'MBA');
        insert prog;
        
        AcademicYear ay = TestDataFactory.testAcademicYear();
        Contact con = TestDataFactory.testContact();
        ProgramEnrollment pe = TestDataFactory.testProgramEnrollment(con, prog);
        pe.Academic_Year__c = ay.Id;
        update pe;
    }

    @isTest
    static void validateLeadLimit_exceedsLimit_error() {
        Program p = [SELECT Id, Name FROM Program WHERE Name = 'MBA' LIMIT 1];
        AcademicYear ay = [SELECT Id, Name FROM AcademicYear LIMIT 1];
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        Id peId = [SELECT Id FROM ProgramEnrollment LIMIT 1].Id;
        TestLibrary lib = new TestLibrary();

        Club__c club1 = lib.createClub('UniqueA', p.Id, ay.Id, 'Professional_Club');
        Club__c club2 = lib.createClub('UniqueB', p.Id, ay.Id, 'Professional_Club');
        
        // Insert real records into DB
        List<Club_Membership__c> existing = new List<Club_Membership__c>();
        existing.add(new Club_Membership__c(Club__c = club1.Id, Contact__c = con.Id, Role__c = 'Lead', Status__c = 'Active', Program_Enrollment__c = peId));
        existing.add(new Club_Membership__c(Club__c = club2.Id, Contact__c = con.Id, Role__c = 'Lead', Status__c = 'Active', Program_Enrollment__c = peId));
        insert existing; 
        
        // Mock 3rd record using the NAME 'MBA' to match the DB formula result
        Club_Membership__c incoming = lib.createMembershipInMem(p.Name, ay.Name, 'Lead', 'Active', 'Professional_Club');
        
        Test.startTest();
        ClubMembershipLeadLimitHandler.validateLeadLimit(new List<Club_Membership__c>{incoming}, null);
        Test.stopTest();
        
        System.assert(incoming.hasErrors(), 'Should fail: Handler now sees 2 existing leads for MBA');
    }

    @isTest
    static void validate_duplicateExisting_error() {
        Program p = [SELECT Id, Name FROM Program WHERE Name = 'MBA' LIMIT 1];
        AcademicYear ay = [SELECT Id, Name FROM AcademicYear LIMIT 1];
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        Id peId = [SELECT Id FROM ProgramEnrollment LIMIT 1].Id;
        TestLibrary lib = new TestLibrary();

        Club__c club = lib.createClub('Council Club', p.Id, ay.Id, 'Council');
        
        insert new Club_Membership__c(
            Club__c = club.Id,
            Contact__c = con.Id,
            Role__c = 'Lead', 
            Status__c = 'Active',
            Program_Enrollment__c = peId
        );
        
        // Mock duplicate using NAME 'MBA'
        Club_Membership__c duplicate = lib.createMembershipInMem(p.Name, ay.Name, 'Lead', 'Active', 'Council'); 
        
        Test.startTest();
        ClubMembershipLeadLimitHandler.validate(new List<Club_Membership__c>{duplicate}, null);
        Test.stopTest();
        
        System.assert(duplicate.hasErrors(), 'Should fail: Active membership already exists for MBA');
    }

    @isTest
    static void validateLeadLimit_underLimit_success() {
        Program p = [SELECT Id, Name FROM Program WHERE Name = 'MBA' LIMIT 1];
        AcademicYear ay = [SELECT Id, Name FROM AcademicYear LIMIT 1];
        TestLibrary lib = new TestLibrary();
        Club_Membership__c cm = lib.createMembershipInMem(p.Name, ay.Name, 'Lead', 'Active', 'Professional_Club');
        
        Test.startTest();
        ClubMembershipLeadLimitHandler.validateLeadLimit(new List<Club_Membership__c>{cm}, null);
        Test.stopTest();
        
        System.assertEquals(false, cm.hasErrors());
    }

    @isTest
    static void validateLeadLimit_bulkBatch_error() {
        Program p = [SELECT Id, Name FROM Program WHERE Name = 'MBA' LIMIT 1];
        AcademicYear ay = [SELECT Id, Name FROM AcademicYear LIMIT 1];
        TestLibrary lib = new TestLibrary();
        List<Club_Membership__c> incoming = new List<Club_Membership__c>();
        incoming.add(lib.createMembershipInMem(p.Name, ay.Name, 'Lead', 'Active', 'Professional_Club'));
        incoming.add(lib.createMembershipInMem(p.Name, ay.Name, 'Lead', 'Active', 'Professional_Club'));
        incoming.add(lib.createMembershipInMem(p.Name, ay.Name, 'Lead', 'Active', 'Professional_Club'));
        
        Test.startTest();
        ClubMembershipLeadLimitHandler.validateLeadLimit(incoming, null);
        Test.stopTest();
        
        System.assert(incoming[2].hasErrors());
    }

    @isTest
    static void testHelpers() {
        System.assert(ClubMembershipLeadLimitHandler.isIdLike('001720000000001AAA'));
        System.assertNotEquals(null, ClubMembershipLeadLimitHandler.buildKey('a', 'b', 'c'));
    }
}