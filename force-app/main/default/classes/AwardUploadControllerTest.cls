@isTest
public class AwardUploadControllerTest {

    @TestSetup
    static void setupTestData() {
        // Dynamically identify the Program SObject type to avoid Type errors
        Schema.DescribeFieldResult f = ProgramEnrollment.ProgramId.getDescribe();
        Schema.sObjectType programType = f.getReferenceTo()[0];
        
        SObject testProg = programType.newSObject();
        testProg.put('Name', 'Computer Science');
        insert testProg;

        Contact student = new Contact(FirstName = 'Test', LastName = 'Student',hed__Preferred_Email__c = 'VF Email ID',VF_Email_ID__c = 'bodhtree.admin@isb.com');
        insert student;

        ProgramEnrollment pe = new ProgramEnrollment(
            Name = 'Test Enrollment',
            ContactId = student.Id,
            ProgramId = (Id)testProg.get('Id'), 
            PGID__c = 'PG123'
        );
        insert pe;

        Award_Catalog__c activeCatalog = new Award_Catalog__c(
            Name = 'Active Catalog',
            Active__c = true,
            Category__c = 'Leadership' 
        );
        
        Award_Catalog__c inactiveCatalog = new Award_Catalog__c(
            Name = 'Inactive Catalog',
            Active__c = false,
            Category__c = 'Leadership' 
        );
        insert new List<Award_Catalog__c>{ activeCatalog, inactiveCatalog };
    }

    @isTest
    static void testProcessAwardData_FullSuccess() {
        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            new Map<String, Object>{
                'studentId'    => 'PG123',
                'awardCatalog' => 'Active Catalog',
                'awardDate'    => '2023-10-01T10:00:00.000Z' 
            }
        };

        Test.startTest();
        Map<String, Object> response = AwardUploadController.processAwardData(rows);
        Test.stopTest();

        System.assertEquals(1, response.get('successCount'));
    }

    @isTest
    static void testProcessAwardData_DateParsingVariants() {
        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            new Map<String, Object>{
                'studentId'    => 'PG123',
                'awardCatalog' => 'Active Catalog',
                'awardDate'    => '2023-10-01T10:00:00Z' // ISO No Millis
            },
            new Map<String, Object>{
                'studentId'    => 'PG123',
                'awardCatalog' => 'Active Catalog',
                'awardDate'    => '2023-12-25' // Date.valueOf path
            },
            new Map<String, Object>{
                'studentId'    => 'PG123',
                'awardCatalog' => 'Active Catalog',
                'awardDate'    => 'Invalid Date String' // Hits inner catch
            }
        };

        Map<String, Object> response = AwardUploadController.processAwardData(rows);
        System.assertEquals(1, response.get('failedCount'));
    }

    @isTest
    static void testProcessAwardData_DuplicateCheck() {
        ProgramEnrollment pe = [SELECT Id,ContactId FROM ProgramEnrollment LIMIT 1];
        Award_Catalog__c ac = [SELECT Id,Category__c  FROM Award_Catalog__c WHERE Category__c  = 'Leadership' and Active__c = true LIMIT 1];
        insert new Award(Program_Enrollment__c = pe.Id, Award_Catalog__c = ac.Id ,Contact__c = pe.ContactId );

        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            new Map<String, Object>{
                'studentId'    => 'PG123',
                'awardCatalog' => 'Active Catalog'
            }
        };

        Map<String, Object> response = AwardUploadController.processAwardData(rows);
        System.assertEquals(1, response.get('failedCount'));
        System.assert(((String)response.get('errorCSV')).contains('Duplicate Award'));
    }

    @isTest
    static void testProcessAwardData_InactiveCatalog() {
        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            new Map<String, Object>{
                'studentId'    => 'PG123',
                'awardCatalog' => 'Inactive Catalog'
            }
        };

        Map<String, Object> response = AwardUploadController.processAwardData(rows);
        System.assertEquals(1, response.get('failedCount'));
        System.assert(((String)response.get('errorCSV')).contains('is not Active'));
    }

    @isTest
    static void testProcessAwardData_CatchBlockCoverage() {
        // To hit the "catch (Exception ex)" block on line 205:
        // We provide a row that exists but has data that will cause an error 
        // when being processed (e.g., trying to put a Long into a Date field).
        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            new Map<String, Object>{
                'studentId'    => 'PG123',
                'awardCatalog' => 'Active Catalog',
                'awardDate'    => 123456789 // Passing an Integer/Long instead of String/Date forces a casting exception
            }
        };

        Map<String, Object> response = AwardUploadController.processAwardData(rows);
        System.assertEquals(1, response.get('failedCount'), 'The catch block should capture the error');
    }

    @isTest
    static void testProcessAwardData_NullInputs() {
        // Covers lines 10-11 (empty records)
        AwardUploadController.processAwardData(null);
        AwardUploadController.processAwardData(new List<Map<String, Object>>());
        
        // Covers rows with null values but valid Map structure
        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            new Map<String, Object>{ 'studentId' => null, 'awardCatalog' => null }
        };
        AwardUploadController.processAwardData(rows);
    }
}