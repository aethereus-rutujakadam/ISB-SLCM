@isTest
private class InternationalExchangeController_Test {

    @isTest
    static void testProcessExchangeData_Success() {

        Program prog = TestDataFactory.testProgram();

        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        rows.add(new Map<String, Object>{
            'contactName' => 'John Doe',
            'pgid' => 'PGP001',
            'programName' => prog.Name
        });
        rows.add(new Map<String, Object>{
            'contactName' => 'Jane Smith',
            'pgid' => 'PGP002',
            'programName' => prog.Name
        });

        Test.startTest();
        Map<String, Object> response = InternationalExchangeController.processExchangeData(rows);
        Test.stopTest();

        System.assert(response != null);
        
        List<Map<String,Object>> errorRows = (List<Map<String,Object>>) response.get('errorRows');

        String csv = (String) response.get('errorCSV');
    }


    @isTest
    static void testProcessExchangeData_Failure_MissingProgram() {

        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        rows.add(new Map<String, Object>{
            'contactName' => 'John Error',
            'pgid' => 'PGPERR1',
            'programName' => 'Unknown Program'
        });

        Test.startTest();
        Map<String, Object> response = InternationalExchangeController.processExchangeData(rows);
        Test.stopTest();

        System.assert(response != null);

        List<Map<String,Object>> errorRows = (List<Map<String,Object>>) response.get('errorRows');
        System.assertEquals(1, errorRows.size());

        String errorCsv = (String) response.get('errorCSV');
        System.assert(errorCsv.contains('Unknown Program'));
    }


    @isTest
    static void testProcessExchangeData_EmptyInput() {

        List<Map<String, Object>> rows = new List<Map<String, Object>>();

        Test.startTest();
        Map<String, Object> response = InternationalExchangeController.processExchangeData(rows);
        Test.stopTest();

        System.assertEquals(0, response.get('successCount'));
        System.assertEquals(0, response.get('failedCount'));
    }


    @isTest
    static void testProcessExchangeData_InvalidContactError() {

        Program prog = TestDataFactory.testProgram();

        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        rows.add(new Map<String, Object>{
            'contactName' => null,
            'pgid' => 'PGPERR2',
            'programName' => prog.Name
        });

        Test.startTest();
        Map<String, Object> response = InternationalExchangeController.processExchangeData(rows);
        Test.stopTest();

        List<Map<String,Object>> errorRows = (List<Map<String,Object>>) response.get('errorRows');
        System.assertEquals(1, errorRows.size());

        String msg = (String) errorRows[0].get('errorMessage');
        System.assert(msg != null);
    }

@isTest
static void testProcessExchangeData_ExistingStudent() {

    Program prog = TestDataFactory.testProgram();
    Contact existingContact = TestDataFactory.testContact();

    // Insert existing ProgramEnrollment
    insert new ProgramEnrollment(
        PGID__c = 'PGEXIST1',
        ContactId = existingContact.Id,
        ProgramId = prog.Id
    );

    List<Map<String, Object>> rows = new List<Map<String, Object>>{
        new Map<String, Object>{
            'fullName' => 'Existing Student',
            'pgid' => 'PGEXIST1',
            'programName' => prog.Name,
            'exchangeType' => 'Semester',
            'homeUniversity' => 'MIT',
            'visitingTerm' => 'Fall'
        }
    };

    Test.startTest();
    Map<String, Object> response =
        InternationalExchangeController.processExchangeData(rows);
    Test.stopTest();

    List<Map<String,Object>> errors =
        (List<Map<String,Object>>) response.get('errorRows');

    System.assertEquals(1, errors.size());
    System.assertEquals('Student Id already exists in system',
        errors[0].get('errorMessage'));
}

@isTest
static void testProcessExchangeData_PE_SuccessBranch() {

    Program prog = TestDataFactory.testProgram();

    List<Map<String, Object>> rows = new List<Map<String, Object>>{
        new Map<String, Object>{
            'fullName' => 'Success Student',
            'pgid' => 'PGSUCCESS1',
            'programName' => prog.Name,
            'exchangeType' => 'Semester',
            'homeUniversity' => 'MIT',
            'visitingTerm' => 'Fall'
        }
    };

    Test.startTest();
    Map<String, Object> response =
        InternationalExchangeController.processExchangeData(rows);
    Test.stopTest();

}

@isTest
static void testProcessExchangeData_PE_FailureBranch() {

    List<Map<String, Object>> rows = new List<Map<String, Object>>{
        new Map<String, Object>{
            'fullName' => 'Bad Program Student',
            'pgid' => 'PGFAIL1',
            'programName' => 'DoesNotExist', // Forces ProgramId null
            'exchangeType' => 'Semester'
        }
    };

    Test.startTest();
    Map<String, Object> response =
        InternationalExchangeController.processExchangeData(rows);
    Test.stopTest();

    System.assert(
        ((String)response.get('errorCSV')).contains('Error') ||
        ((Integer)response.get('failedCount')) > 0,
        'Failure branch should execute'
    );
}
}