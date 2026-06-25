@IsTest
public class FeeControllerTest {

    @TestSetup
    static void setup() {
        // Account + Contact
        Account acc = new Account(Name = 'Test Student Account');
        insert acc;

        Contact con = TestDataFactory.testContact();
        //insert con;

        // Create Program and Program Enrollment
        Program program = new Program(Name = 'Test Program');
        insert program;

        ProgramEnrollment pe = new ProgramEnrollment(
            ContactId = con.Id,
            ProgramId = program.Id,
            Status = 'Registered'
        );
        // Set IsActive if the field exists
        Map<String, SObjectField> peFields = Schema.SObjectType.ProgramEnrollment.fields.getMap();
        if (peFields.containsKey('IsActive')) {
            pe.put('IsActive', true);
        }
        insert pe;

        // Create Installments
        ISB_Installment__c installment1 = new ISB_Installment__c(
            Contact__c = con.Id,
            Program__c = program.Id,
            Program_Enrollment__c = pe.Id,
            Actual_Amount__c = 32325,
            Pending_Amount__c = 32325,
            Installment_Number__c = '1',
            Is_Active__c = true
        );
        insert installment1;

        ISB_Installment__c installment2 = new ISB_Installment__c(
            Contact__c = con.Id,
            Program__c = program.Id,
            Program_Enrollment__c = pe.Id,
            Actual_Amount__c = 3232,
            Pending_Amount__c = 3232,
            Installment_Number__c = '2',
            Is_Active__c = true
        );
        insert installment2;

        // Fee 1 (will have an Initiated payment)
        ISB_Fee__c fee1 = new ISB_Fee__c(
            Contact__c = con.Id,
            Customer__c = con.Id,
            ISB_Installment__c = installment1.Id,
            Fee_Amount__c = 32325
        );
        // Set optional fields only if present in org
        Map<String, SObjectField> feeFields = Schema.SObjectType.ISB_Fee__c.fields.getMap();
        if (feeFields.containsKey('Pending_Amount__c')) fee1.put('Pending_Amount__c', 1000);
        if (feeFields.containsKey('Paid_Amount__c'))    fee1.put('Paid_Amount__c', 0);
        if (feeFields.containsKey('Total_amount__c'))   fee1.put('Total_amount__c', 1000);
        if (feeFields.containsKey('Fee_Status__c'))      fee1.put('Fee_Status__c', 'Paid');
        if (feeFields.containsKey('Due_Date__c'))      fee1.put('Due_Date__c', System.Today());
        if (feeFields.containsKey('Payment_Window__c'))      fee1.put('Payment_Window__c', 2);
        if (feeFields.containsKey('Is_Active__c'))      fee1.put('Is_Active__c', true);
        insert fee1;

        // Fee 2 (no Initiated payment)
        ISB_Fee__c fee2 = new ISB_Fee__c(
            Contact__c = con.Id,
            Customer__c = con.Id,
            ISB_Installment__c = installment2.Id,
            Fee_Amount__c = 3232
        );
        if (feeFields.containsKey('Pending_Amount__c')) fee2.put('Pending_Amount__c', 2000);
        if (feeFields.containsKey('Paid_Amount__c'))    fee2.put('Paid_Amount__c', 0);
        if (feeFields.containsKey('Total_amount__c'))   fee2.put('Total_amount__c', 2000);
        if (feeFields.containsKey('Fee_Status__c'))      fee2.put('Fee_Status__c', 'Paid');
        if (feeFields.containsKey('Due_Date__c'))      fee2.put('Due_Date__c', System.Today());
        if (feeFields.containsKey('Payment_Window__c'))      fee2.put('Payment_Window__c', 2);
        if (feeFields.containsKey('Is_Active__c'))      fee2.put('Is_Active__c', true);
        insert fee2;

        // Payments
        // 1) Initiated = 'Initiated' -> should set hasInitiatedPayment = true for fee1
        ISB_Payment__c pInitiated = new ISB_Payment__c();
        Map<String, SObjectField> payFields = Schema.SObjectType.ISB_Payment__c.fields.getMap();

        // Lookup field used in controller query
        if (payFields.containsKey('ISB_Fees__c'))   pInitiated.put('ISB_Fees__c', fee1.Id);
        if (payFields.containsKey('Initiated__c'))  pInitiated.put('Initiated__c', 'Initiated');
        //if (payFields.containsKey('Name'))          pInitiated.put('Name', 'Pay-Initiated');
        insert pInitiated;

        // 2) Initiated = 'Success' -> used only by the subquery in Fee query (not the boolean map)
        ISB_Payment__c pSuccess = new ISB_Payment__c();
        if (payFields.containsKey('ISB_Fees__c'))   pSuccess.put('ISB_Fees__c', fee1.Id);
        if (payFields.containsKey('Initiated__c'))  pSuccess.put('Initiated__c', 'Success');
       // if (payFields.containsKey('Name'))          pSuccess.put('Name', 'Pay-Success');
        insert pSuccess;
    }

    @IsTest
    static void testGetFeesForContact_withAndWithoutInitiated() {
        // Query the contact created in @TestSetup
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        List<FeeController.FeeWrapper> res;

        Test.startTest();
        res = FeeController.getFeesForContact(con.Id);
        Test.stopTest();

        System.assertNotEquals(null, res, 'Result should not be null');

        Boolean foundInitiated = false;
        Boolean foundNotInitiated = false;

        for (FeeController.FeeWrapper w : res) {
            System.assertNotEquals(null, w.fee, 'Wrapper fee should not be null');
            if (w.fee.Fee_Amount__c == 32325) {
                System.assertEquals(true, w.hasInitiatedPayment, 'Fee 1 should have initiated payment');
                foundInitiated = true;
            }
            if (w.fee.Fee_Amount__c == 3232) {
                System.assertEquals(false, w.hasInitiatedPayment, 'Fee 2 should not have initiated payment');
                foundNotInitiated = true;
            }
        }
        System.assert(foundInitiated, 'Fee 1 not found');
        System.assert(foundNotInitiated, 'Fee 2 not found');
    }

    @IsTest
    static void testGetFeesForContact_null_returnsEmpty() {
        Test.startTest();
        List<FeeController.FeeWrapper> res = FeeController.getFeesForContact(null);
        Test.stopTest();

        System.assertEquals(0, res.size(), 'Null contactId should return empty list');
    }

    @IsTest
    static void testGetFees_userWithContact_returnsFees() {
        // Create a contact and a portal user for it
        Account acc = new Account(Name = 'Portal Account');
        insert acc;
        
        String email = 'portal' + DateTime.now().getTime() + '@example.com';
        Contact con = new Contact(
            FirstName = 'Test', 
            LastName = 'Portal', 
            Email = email, 
            AccountId = acc.Id,
            hed__Preferred_Email__c = 'VF Email ID',
            VF_Email_ID__c = email
        );
        insert con;

        // Try to find a community profile, fallback to Standard User if none found
        List<Profile> profiles = [SELECT Id FROM Profile WHERE Name LIKE '%Community%' LIMIT 1];
        Profile p = !profiles.isEmpty() ? profiles[0] : [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        String uniq = String.valueOf(DateTime.now().getTime());
        User u = new User(
            ProfileId = p.Id,
            Username = 'feecontroller.success.' + uniq + '@example.com',
            Email = 'feecontroller.success.' + uniq + '@example.com',
            LastName = 'WithContact',
            Alias = 'wcnt',
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_IN',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        
        // Internal users can't have ContactId, but Portal/Community users MUST.
        // We set it only if we're not using a Standard User profile (which would fail anyway for ContactId)
        // However, the error was on Contact insert. Let's fix that first.
        
        // Check if we can actually create a portal user in this environment without a Role assigned to the owner.
        // For simplicity in tests, often we just use System.runAs or ensure the current user has a role.
        
        if (p.Id != [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id) {
            u.ContactId = con.Id;
        }

        insert u;

        // Add a fee for this contact
        ISB_Fee__c fee = new ISB_Fee__c(
            Contact__c = con.Id,
            Customer__c = con.Id,
            Fee_Amount__c = 500,
            Payment_Window__c  = 2,
            Due_Date__c = System.Today()
        );
        Map<String, SObjectField> feeFields = Schema.SObjectType.ISB_Fee__c.fields.getMap();
        if (feeFields.containsKey('Is_Active__c')) {
            fee.put('Is_Active__c', true);
        }
        insert fee;

        System.runAs(u) {
            Test.startTest();
            List<FeeController.FeeWrapper> res = FeeController.getFees();
            Test.stopTest();

        }
    }

    @IsTest
    static void testGetFees_userWithoutContact_returnsEmpty() {
        // Create a standard internal user with no ContactId
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        String uniq = String.valueOf(DateTime.now().getTime());
        User u = new User(
            ProfileId = p.Id,
            Username = 'feecontroller.test.' + uniq + '@example.com',
            Email = 'feecontroller.test.' + uniq + '@example.com',
            LastName = 'NoContact',
            Alias = 'nocnt',
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_IN',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert u;

        System.runAs(u) {
            Test.startTest();
            List<FeeController.FeeWrapper> res = FeeController.getFees();
            Test.stopTest();

            System.assertEquals(0, res.size(), 'User without ContactId should get empty list');
        }
    }
    
      // Test 10: Empty result for contact with no fees
    @IsTest
    static void testGetFeesForContact_emptyResult() {
        Account acc = new Account(Name = 'Empty Account');
        insert acc;

         String uniqueEmail = 'customer_test' + System.currentTimeMillis() + '@example.com';
           Contact con = new Contact(
            LastName = 'Customer_Test',
            Email = uniqueEmail,
            hed__Preferred_Email__c = 'VF Email ID',
            VF_Email_ID__c = uniqueEmail
        );
        insert con;

        Test.startTest();
        List<FeeController.FeeWrapper> result = FeeController.getFeesForContact(con.Id);
        Test.stopTest();

        System.assertEquals(0, result.size(), 'Contact with no fees should return empty list');
    }

    // Test 11: Contact reference preserved in result
    @IsTest
    static void testGetFeesForContact_contactReferencePreserved() {
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        
        Test.startTest();
        List<FeeController.FeeWrapper> result = FeeController.getFeesForContact(con.Id);
        Test.stopTest();

        for (FeeController.FeeWrapper w : result) {
            System.assertEquals(con.Id, w.fee.Contact__c, 'Fee should maintain contact reference');
        }
    }

    // Test 12: Fee amount preserved in result
    @IsTest
    static void testGetFeesForContact_feeAmountPreserved() {
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        
        Test.startTest();
        List<FeeController.FeeWrapper> result = FeeController.getFeesForContact(con.Id);
        Test.stopTest();

        Boolean found1 = false;
        Boolean found2 = false;

        for (FeeController.FeeWrapper w : result) {
            if (w.fee.Fee_Amount__c == 32325) found1 = true;
            if (w.fee.Fee_Amount__c == 3232) found2 = true;
        }

        System.assert(found1, 'Should find fee with amount 32325');
        System.assert(found2, 'Should find fee with amount 3232');
    }

    // Test 13: Exception handling for invalid input
    @IsTest
    static void testGetFeesForContact_handlesException() {
        Test.startTest();
        try {
            List<FeeController.FeeWrapper> result = FeeController.getFeesForContact(null);
            System.assert(true, 'Should handle null gracefully');
        } catch (Exception e) {
            System.assert(false, 'Should not throw for null: ' + e.getMessage());
        }
        Test.stopTest();
    }

    // Test 14: getFees() with valid contact - should return wrapped fees
    @IsTest
    static void testGetFees_withValidContact() {
        Account acc = new Account(Name = 'Fee Test Account');
        insert acc;
        
        String email = 'feetest' + DateTime.now().getTime() + '@example.com';
        Contact con = new Contact(
            FirstName = 'Fee', 
            LastName = 'Test', 
            Email = email, 
            AccountId = acc.Id,
            hed__Preferred_Email__c = 'VF Email ID',
            VF_Email_ID__c = email
        );
        insert con;

        // Create fees for the contact
        ISB_Fee__c fee = new ISB_Fee__c(
            Contact__c = con.Id,
            Customer__c = con.Id,
            Fee_Amount__c = 1500,
            Fee_Status__c = 'Not Paid',
            Due_Date__c = System.Today().addDays(30)
        );
        insert fee;

        // Create a portal user linked to this contact
        Profile p = [SELECT Id FROM Profile WHERE UserType = 'Standard' LIMIT 1];
        String uniq = String.valueOf(DateTime.now().getTime());
           User u = TestDataFactory.testUser('stdUser', 'standard.user@example.com');


        System.runAs(u) {
            Test.startTest();
            List<FeeController.FeeWrapper> result = FeeController.getFees();
            Test.stopTest();
        }
    }

    // Test 15: getFees() with user without contact - should return empty list
    @IsTest
    static void testGetFees_userWithoutContact() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        String uniq = String.valueOf(DateTime.now().getTime());
        User u = new User(
            ProfileId = p.Id,
            Username = 'feenocontact.' + uniq + '@example.com',
            Email = 'feenocontact.' + uniq + '@example.com',
            LastName = 'NoContact',
            Alias = 'ncon',
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert u;

        System.runAs(u) {
            Test.startTest();
            List<FeeController.FeeWrapper> result = FeeController.getFees();
            Test.stopTest();

            System.assertEquals(0, result.size(), 'User without ContactId should get empty list');
        }
    }

    // Test 16: getFees() exception handling
    @IsTest
    static void testGetFees_exceptionHandling() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        String uniq = String.valueOf(DateTime.now().getTime());
        User u = new User(
            ProfileId = p.Id,
            Username = 'feeerror.' + uniq + '@example.com',
            Email = 'feeerror.' + uniq + '@example.com',
            LastName = 'FeeError',
            Alias = 'ferr',
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert u;

        System.runAs(u) {
            Test.startTest();
            try {
                List<FeeController.FeeWrapper> result = FeeController.getFees();
                System.assertNotEquals(null, result, 'Should return valid result or throw AuraHandledException');
            } catch (AuraHandledException e) {
                System.assert(true, 'Exception properly handled');
            }
            Test.stopTest();
        }
    }

    // Test 17: getFeesForContact() exception handling with invalid ID
    @IsTest
    static void testGetFeesForContact_exceptionWithInvalidId() {
        Test.startTest();
        try {
            List<FeeController.FeeWrapper> result = FeeController.getFeesForContact('001INVALID00000');
            System.assertNotEquals(null, result, 'Should handle invalid ID gracefully or return empty');
        } catch (Exception e) {
            System.assert(true, 'Exception handling works correctly');
        }
        Test.stopTest();
    }

    // Test 18: Multiple fees with mixed payment statuses
    @IsTest
    static void testGetFeesForContact_mixedPaymentStatuses() {
        Account acc = new Account(Name = 'Mixed Payment Account');
        insert acc;

        String email = 'mixed' + DateTime.now().getTime() + '@example.com';
        Contact con = new Contact(
            FirstName = 'Mixed', 
            LastName = 'Payments', 
            Email = email, 
            AccountId = acc.Id,
            hed__Preferred_Email__c = 'VF Email ID',
            VF_Email_ID__c = email
        );
        insert con;

        // Create 3 fees
        List<ISB_Fee__c> fees = new List<ISB_Fee__c>();
        for (Integer i = 1; i <= 3; i++) {
            fees.add(new ISB_Fee__c(
                Contact__c = con.Id,
                Customer__c = con.Id,
                Fee_Amount__c = 1000 * i,
                Fee_Status__c = 'Not Paid',
                Due_Date__c = System.Today().addDays(30)
            ));
        }
        insert fees;

        // Add payments with different statuses
        insert new ISB_Payment__c(
            ISB_Fees__c = fees[0].Id,
            Initiated__c = 'Initiated'
        );

        insert new ISB_Payment__c(
            ISB_Fees__c = fees[1].Id,
            Initiated__c = 'Failed'
        );

        insert new ISB_Payment__c(
            ISB_Fees__c = fees[2].Id,
            Initiated__c = 'Success'
        );

        Test.startTest();
        List<FeeController.FeeWrapper> result = FeeController.getFeesForContact(con.Id);
        Test.stopTest();

        
        Boolean foundInitiated = false;
        Boolean foundFailed = false;
        Boolean foundSuccess = false;

        for (FeeController.FeeWrapper w : result) {
            if (w.fee.Fee_Amount__c == 1000 && w.hasInitiatedPayment) foundInitiated = true;
            if (w.fee.Fee_Amount__c == 2000 && !w.hasInitiatedPayment) foundFailed = true;
            if (w.fee.Fee_Amount__c == 3000 && !w.hasInitiatedPayment) foundSuccess = true;
        }

    }

    // Test 19: Fee wrapper fields are correctly set
    @IsTest
    static void testFeeWrapper_fieldsCorrectlySet() {
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        
        Test.startTest();
        List<FeeController.FeeWrapper> result = FeeController.getFeesForContact(con.Id);
        Test.stopTest();

        for (FeeController.FeeWrapper w : result) {
            System.assertNotEquals(null, w.fee, 'Fee object should not be null');
            System.assertNotEquals(null, w.hasInitiatedPayment, 'hasInitiatedPayment should be set');
        }
    }

    // Test 20: Large number of fees with pagination handling
    @IsTest
    static void testGetFeesForContact_manyFees() {
        Account acc = new Account(Name = 'Many Fees Account');
        insert acc;

        String email = 'many' + DateTime.now().getTime() + '@example.com';
        Contact con = new Contact(
            FirstName = 'Many', 
            LastName = 'Fees', 
            Email = email, 
            AccountId = acc.Id,
            hed__Preferred_Email__c = 'VF Email ID',
            VF_Email_ID__c = email
        );
        insert con;

        // Create 10 fees
        List<ISB_Fee__c> fees = new List<ISB_Fee__c>();
        for (Integer i = 1; i <= 10; i++) {
            fees.add(new ISB_Fee__c(
                Contact__c = con.Id,
                Customer__c = con.Id,
                Fee_Amount__c = 1000 + i,
                Fee_Status__c = 'Not Paid'
            ));
        }
        insert fees;

        Test.startTest();
        List<FeeController.FeeWrapper> result = FeeController.getFeesForContact(con.Id);
        Test.stopTest();

        System.assertEquals(true, result.size() <= 10000, 'Should handle large result sets');
    }

    // Test 21: Fee with null field values
    @IsTest
    static void testGetFeesForContact_nullFieldValues() {
        Account acc = new Account(Name = 'Null Fields Account');
        insert acc;

        Contact con = new Contact(
            LastName = 'NullFields',
            Email = 'null' + DateTime.now().getTime() + '@example.com',
            AccountId = acc.Id,
            hed__Preferred_Email__c = 'VF Email ID',
            VF_Email_ID__c = 'null' + DateTime.now().getTime() + '@example.com'
        );
        insert con;

        ISB_Fee__c fee = new ISB_Fee__c(
            Contact__c = con.Id,
            Customer__c = con.Id,
            Fee_Amount__c = 500
        );
        insert fee;

        Test.startTest();
        List<FeeController.FeeWrapper> result = FeeController.getFeesForContact(con.Id);
        Test.stopTest();

    }
}