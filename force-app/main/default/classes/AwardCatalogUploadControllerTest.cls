@isTest
public class AwardCatalogUploadControllerTest {

    // ================================================================
    // Fake ID generator (minimizes unnecessary DML)
    // ================================================================
    public static Id generateFakeId(String prefix) {
        return (Id)(prefix + '000000000000000AAA');
    }

    // ================================================================
    // @TestSetup - Insert ONE existing catalog to test org duplicate logic
    // ================================================================
    @TestSetup
    static void setupData() {
        Award_Catalog__c ac = new Award_Catalog__c(
            Name = 'Existing Award',
            Award_Recipient_Type__c = 'Single',   // VALID PICKLIST VALUE
            Category__c = 'Academic',             // VALID PICKLIST VALUE
            Active__c = true
        );
        insert ac;
    }


    // =====================================================================================
    // TEST 1: No rows → must return error message "No records found in Excel"
    // =====================================================================================
    @isTest
    static void testProcessCatalogData_noRecords_returnsError() {

        Map<String,Object> result =
            AwardCatalogUploadController.processCatalogData(new List<Map<String,Object>>());

        List<String> errors = (List<String>)result.get('errorRows');

        System.assertEquals(0, result.get('successCount'));
        System.assertEquals(0, result.get('failedCount'));
        System.assertEquals(true, errors[0].contains('No records found in Excel'));
    }


    // =====================================================================================
    // TEST 2: Duplicate inside Excel
    // =====================================================================================
    @isTest
    static void testProcessCatalogData_excelDuplicate_detected() {

        List<Map<String,Object>> rows = new List<Map<String,Object>>();

        Map<String,Object> r1 = new Map<String,Object>{
            'Award Catalog Name' => 'ExcelDup',
            'Award Recipient Type' => 'Single',
            'Category' => 'Academic',
            'Active' => 'Yes',
            'Description' => 'Desc'
        };

        Map<String,Object> r2 = new Map<String,Object>{
            'Award Catalog Name' => 'ExcelDup',   // duplicate
            'Award Recipient Type' => 'Single',
            'Category' => 'Academic',
            'Active' => 'Yes',
            'Description' => 'Desc'
        };

        rows.add(r1);
        rows.add(r2);

        Map<String,Object> result =
            AwardCatalogUploadController.processCatalogData(rows);

        List<String> errors = (List<String>)result.get('errorRows');

        System.assertEquals(true, errors[0].contains('Duplicate entry in uploaded Excel'));
        System.assertEquals(0, result.get('successCount'));
    }


    // =====================================================================================
    // TEST 3: Duplicate in Salesforce (from @TestSetup record)
    // =====================================================================================
    @isTest
    static void testProcessCatalogData_orgDuplicate_detected() {

        List<Map<String,Object>> rows = new List<Map<String,Object>>();

        Map<String,Object> r1 = new Map<String,Object>{
            'Award Catalog Name' => 'Existing Award',  // duplicate with org
            'Award Recipient Type' => 'Single',
            'Category' => 'Academic',
            'Active' => 'Yes',
            'Description' => 'Something'
        };

        rows.add(r1);

        Map<String,Object> result =
            AwardCatalogUploadController.processCatalogData(rows);

        List<String> errors = (List<String>)result.get('errorRows');

        System.assertEquals(true, errors[0].contains('Duplicate found in Salesforce'));
    }


    // =====================================================================================
    // TEST 4: Missing name → validation error
    // =====================================================================================
    @isTest
    static void testProcessCatalogData_missingName_error() {

        List<Map<String,Object>> rows = new List<Map<String,Object>>();

        Map<String,Object> r1 = new Map<String,Object>{
            'Award Catalog Name' => null,
            'Award Recipient Type' => 'Single',
            'Category' => 'Academic',
            'Active' => 'Yes',
            'Description' => 'Text'
        };

        rows.add(r1);

        Map<String,Object> result =
            AwardCatalogUploadController.processCatalogData(rows);

        List<String> errors = (List<String>)result.get('errorRows');

        System.assertEquals(true,
            errors[0].contains('Award Catalog Name is required'));
    }


    // =====================================================================================
    // TEST 5: 100% Valid Rows → successful insert
    // =====================================================================================
    @isTest
    static void testProcessCatalogData_validRows_success() {

        List<Map<String,Object>> rows = new List<Map<String,Object>>();

        Map<String,Object> r1 = new Map<String,Object>{
            'Award Catalog Name' => 'Cat A',
            'Award Recipient Type' => 'Single',
            'Category' => 'Academic',
            'Active' => 'Yes',
            'Description' => 'First'
        };

        Map<String,Object> r2 = new Map<String,Object>{
            'Award Catalog Name' => 'Cat B',
            'Award Recipient Type' => 'Multiple',
            'Category' => 'Leadership',
            'Active' => 'No',
            'Description' => 'Second'
        };

        rows.add(r1);
        rows.add(r2);

        Map<String,Object> result =
            AwardCatalogUploadController.processCatalogData(rows);

        System.assertEquals(2, result.get('successCount'));
        System.assertEquals(0, result.get('failedCount'));

        List<Award_Catalog__c> inserted =
            [SELECT Name FROM Award_Catalog__c WHERE Name IN ('Cat A', 'Cat B')];

        System.assertEquals(2, inserted.size());
    }


    // =====================================================================================
    // TEST 6: Partial failure → one valid, one invalid
    // =====================================================================================
    @isTest
    static void testProcessCatalogData_partialFailure() {

        List<Map<String,Object>> rows = new List<Map<String,Object>>();

        // VALID
        Map<String,Object> r1 = new Map<String,Object>{
            'Award Catalog Name' => 'ValidCat',
            'Award Recipient Type' => 'Single',
            'Category' => 'Academic',
            'Active' => 'Yes',
            'Description' => 'Good'
        };

        // INVALID (missing name)
        Map<String,Object> r2 = new Map<String,Object>{
            'Award Catalog Name' => null,
            'Award Recipient Type' => 'Multiple',
            'Category' => 'Academic',
            'Active' => 'Yes',
            'Description' => 'Bad'
        };

        rows.add(r1);
        rows.add(r2);

        Map<String,Object> result =
            AwardCatalogUploadController.processCatalogData(rows);

        System.assertEquals(1, result.get('successCount'));

        List<String> errors = (List<String>)result.get('errorRows');
        System.assertEquals(true, errors[0].contains('Award Catalog Name is required'));
    }
}