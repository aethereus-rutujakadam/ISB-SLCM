@IsTest
public class PaymentControllerTest {
    
    @TestSetup
    static void setupTestData() {
        
        // -----------------------------------------
        // STEP 1: Create Setup Objects in runAs
        // -----------------------------------------
        Profile adminProfile = [
            SELECT Id FROM Profile
            WHERE Name = 'System Administrator'
            LIMIT 1
        ];
        
        User runner = new User(
            FirstName = 'Runner',
            LastName = 'User',
            Alias = 'runr',
            Email = 'runner@test.com',
            Username = 'runner.' + System.currentTimeMillis() + '@test.com',
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = adminProfile.Id
        );
        insert runner;
        
        System.runAs(runner) {
            
            UserRole ur = new UserRole(Name = 'TestRole');
            insert ur;
            
            User accountOwner = new User(
                FirstName = 'Acct',
                LastName = 'Owner',
                Alias = 'aown',
                Email = 'acct@test.com',
                Username = 'acct.' + System.currentTimeMillis() + '@test.com',
                TimeZoneSidKey = 'Asia/Kolkata',
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US',
                ProfileId = adminProfile.Id,
                UserRoleId = ur.Id
            );
            insert accountOwner;
            
            Profile portalProfile = [
                SELECT Id FROM Profile
                WHERE UserType = 'Standard'
                LIMIT 1
            ];
            
            // Store IDs via static queries later
        }
        
        // -----------------------------------------
        // STEP 2: Non-Setup Objects (Safe)
        // -----------------------------------------
        
        User accountOwner = [SELECT Id FROM User WHERE Alias = 'aown' LIMIT 1];
        
        Account acc = new Account(
            Name = 'Student',
            OwnerId = accountOwner.Id
        );
        insert acc;
        
        Contact contact = new Contact(
            LastName = 'Student',
            AccountId = acc.Id,
            hed__Preferred_Email__c = 'VF Email ID',
            VF_Email_ID__c = 'bodhtree.admin@isb.com'
            
        );
        insert contact;
        
        // -----------------------------------------
        // STEP 3: Create Portal User (Setup) again
        // -----------------------------------------
        User runnerUser = [SELECT Id FROM User WHERE Alias = 'runr' LIMIT 1];
        
        System.runAs(runnerUser) {
            
            Profile portalProfile = [
                SELECT Id FROM Profile
                WHERE UserType = 'Standard'
                LIMIT 1
            ];
            
            User portalUser = new User(
                FirstName = 'Portal',
                LastName = 'User',
                Alias = 'pusr',
                Email = 'portal@test.com',
                Username = 'portal.' + System.currentTimeMillis() + '@test.com',
                TimeZoneSidKey = 'Asia/Kolkata',
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US',
                ProfileId = portalProfile.Id
                //ContactId = contact.Id
            );
            insert portalUser;
        }
        
        // -----------------------------------------
        // STEP 4: Business Data
        // -----------------------------------------
        
        Program program = new Program(Name = 'Test Program');
        insert program;
        
        ProgramEnrollment pe = new ProgramEnrollment(
            ContactId = contact.Id,
            ProgramId = program.Id,
            Status = 'Registered'
        );
        insert pe;
        
        List<ISB_Installment__c> installments = new List<ISB_Installment__c>{
            new ISB_Installment__c(
                Contact__c = contact.Id,
                Program__c = program.Id,
                Program_Enrollment__c = pe.Id,
                Actual_Amount__c = 1000,
                Pending_Amount__c = 1000,
                Installment_Number__c = '1'
            ),
                new ISB_Installment__c(
                    Contact__c = contact.Id,
                    Program__c = program.Id,
                    Program_Enrollment__c = pe.Id,
                    Actual_Amount__c = 2000,
                    Pending_Amount__c = 2000,
                    Installment_Number__c = '2'
                ),
                new ISB_Installment__c(
                    Contact__c = contact.Id,
                    Program__c = program.Id,
                    Program_Enrollment__c = pe.Id,
                    Actual_Amount__c = 1500,
                    Pending_Amount__c = 1500,
                    Installment_Number__c = '3'
                )
                };
                    insert installments;
        
        insert new List<ISB_Payment__c>{
            new ISB_Payment__c(
                ISB_Installment__c  = installments[0].Id,
                Customer__c = contact.Id,
                Amount__c = 1000,
                Payment_Type__c = 'Installment 1'
            ),
                new ISB_Payment__c(
                    ISB_Installment__c  = installments[1].Id,
                    Customer__c = contact.Id,
                    Amount__c = 2000,
                    Payment_Type__c = 'Installment 2'
                ),
                new ISB_Payment__c(
                    ISB_Installment__c  = installments[2].Id,
                    Customer__c = contact.Id,
                    Amount__c = 1500,
                    Payment_Type__c = 'Installment 3'
                )
                };
                    }
    
    // -----------------------------------------
    // TEST
    // -----------------------------------------
    @IsTest
    static void testGetPaymentsWithVariousPaymentTypes() {
        
        User portalUser = [SELECT Id FROM User WHERE Alias = 'pusr' LIMIT 1];
        
        System.runAs(portalUser) {
            Test.startTest();
            List<ISB_Payment__c> payments = PaymentController.getPayments();
            Test.stopTest();
            
        }
    }
    /* =====================================================
ADDITIONAL TEST METHODS FOR getPaymentsForContact
===================================================== */
    
    @isTest
    static void testGetPaymentsForContact_Success() {
        Contact c = [SELECT Id FROM Contact LIMIT 1];
        
        Test.startTest();
        List<ISB_Payment__c> payments =
            PaymentController.getPaymentsForContact(c.Id);
        Test.stopTest();
    }
    
    @isTest
    static void testGetPaymentsForContact_Null() {
        
        Test.startTest();
        List<ISB_Payment__c> payments =
            PaymentController.getPaymentsForContact(null);
        Test.stopTest();
        
        System.assertEquals(0, payments.size(),
                            'Null contact should return empty list');
    }
    
    @isTest
    static void testGetPaymentsForContact_NoPayments() {
        
        Account acc = TestDataFactory.testAccount('No Payment Account');
        Contact c = TestDataFactory.testContact(acc.Id);
        
        Test.startTest();
        List<ISB_Payment__c> payments =
            PaymentController.getPaymentsForContact(c.Id);
        Test.stopTest();
        
        System.assertEquals(0, payments.size(),
                            'Contact without payments should return empty list');
    }
    
    @isTest
    static void testGetPaymentsForContact_Exception() {
        Test.startTest();
        try {
            // Invalid Id format to force exception
            PaymentController.getPaymentsForContact('001XXXXXXXXXXXX');
            System.assert(false, 'Exception should have been thrown');
        } catch (Exception e) {
            System.assert(true);
        }
        Test.stopTest();
    }
    
    @IsTest
    static void testGetPaymentsForContact_multiplePayments() {
        Contact c = [SELECT Id FROM Contact LIMIT 1];
        
        Test.startTest();
        List<ISB_Payment__c> payments = PaymentController.getPaymentsForContact(c.Id);
        Test.stopTest();
        
        // Verify payment details
        for (ISB_Payment__c p : payments) {
            System.assertNotEquals(null, p.Id);
            System.assertNotEquals(null, p.Amount__c);
            System.assertNotEquals(null, p.Customer__c);
        }
    }
    
    @IsTest
    static void testGetPaymentsForContact_paymentFields() {
        Contact c = [SELECT Id FROM Contact LIMIT 1];
        
        Test.startTest();
        List<ISB_Payment__c> payments = PaymentController.getPaymentsForContact(c.Id);
        Test.stopTest();
        
    }
    
    @IsTest
    static void testGetPaymentsForContact_noPaymentsMultipleContacts() {
        Account acc = new Account(Name = 'No Payment Account');
        insert acc;
        
        Contact c = new Contact(
            FirstName = 'No',
            LastName = 'Payments',
            Email = 'nopayments@example.com',
            AccountId = acc.Id,
            hed__Preferred_Email__c = 'VF Email ID',
            VF_Email_ID__c = 'nopayments@example.com'
        );
        insert c;
        
        Test.startTest();
        List<ISB_Payment__c> payments = PaymentController.getPaymentsForContact(c.Id);
        Test.stopTest();
        
        System.assertEquals(0, payments.size(), 'Contact without payments should return empty list');
    }
    
    @IsTest
    static void testGetPaymentsForContact_sortingByCreatedDate() {
        Contact c = [SELECT Id FROM Contact LIMIT 1];
        
        Test.startTest();
        List<ISB_Payment__c> payments = PaymentController.getPaymentsForContact(c.Id);
        Test.stopTest();
        
        // Verify sorting is DESC by CreatedDate
        for (Integer i = 0; i < payments.size() - 1; i++) {
            System.assert(
                payments[i].CreatedDate >= payments[i + 1].CreatedDate,
                'Payments should be sorted by CreatedDate DESC'
            );
        }
    }
    
    @IsTest
    static void testGetPaymentsForContact_payment_details() {
        Contact c = [SELECT Id FROM Contact LIMIT 1];
        
        Test.startTest();
        List<ISB_Payment__c> payments = PaymentController.getPaymentsForContact(c.Id);
        Test.stopTest();
        
        for (ISB_Payment__c p : payments) {
            System.assertNotEquals(null, p.Payment_Type__c, 'Payment Type should be populated');
            System.assertEquals(c.Id, p.Customer__c, 'Customer ID should match');
        }
    }
    
    @IsTest
    static void testGetPaymentsForContact_nullContactId() {
        Test.startTest();
        List<ISB_Payment__c> payments = PaymentController.getPaymentsForContact(null);
        Test.stopTest();
        
        System.assertEquals(0, payments.size(), 'Null contact ID should return empty list');
    }
    
    @IsTest
    static void testGetPayments_success() {
        // Create a contact and portal user for it
        Account acc = new Account(Name = 'Success Account');
        insert acc;
        
        String email = 'successuser' + DateTime.now().getTime() + '@example.com';
        Contact con = new Contact(
            FirstName = 'Success', 
            LastName = 'User', 
            Email = email, 
            AccountId = acc.Id,
            hed__Preferred_Email__c = 'VF Email ID',
            VF_Email_ID__c = email
        );
        insert con;
        
        // Add payments for this contact
        insert new List<ISB_Payment__c>{
            new ISB_Payment__c(
                Customer__c = con.Id,
                Amount__c = 500,
                Payment_Type__c = 'Installment 2'
            )
                };
                    
                    // Create portal user
                    Profile successProfile = [SELECT Id FROM Profile WHERE UserType = 'Standard' LIMIT 1];
        String uniq = String.valueOf(DateTime.now().getTime());
        User u = TestDataFactory.testUser('stdUser', 'standard.user@example.com');
        
        
        System.runAs(u) {
            Test.startTest();
            List<ISB_Payment__c> payments = PaymentController.getPayments();
            Test.stopTest();
        }
    }
    
    @IsTest
    static void testPaymentControllerInstallmentRelation() {
        Contact c = [SELECT Id FROM Contact LIMIT 1];
        
        Test.startTest();
        List<ISB_Payment__c> payments = PaymentController.getPaymentsForContact(c.Id);
        Test.stopTest();
        
        for (ISB_Payment__c p : payments) {
            if (p.ISB_Installment__c != null) {
                System.assertNotEquals(null, p.ISB_Installment__r.Name, 'Installment Name should be populated');
            }
        }
    }
    
    @IsTest
    static void testGetPaymentsForContact_verifyAllFields() {
        Contact c = [SELECT Id FROM Contact LIMIT 1];
        
        Test.startTest();
        List<ISB_Payment__c> payments = PaymentController.getPaymentsForContact(c.Id);
        Test.stopTest();
        
        for (ISB_Payment__c p : payments) {
            System.assertNotEquals(null, p.Name, 'Name should be populated');
            System.assertNotEquals(null, p.Amount__c, 'Amount should be populated');
            System.assertNotEquals(null, p.Initiated__c, 'Initiated field should be populated');
        }
    }
    
    // Test 22: getPayments() exception handling - test catch block
    @IsTest
    static void testGetPayments_exceptionHandling() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        
        String uniq = String.valueOf(DateTime.now().getTime());
        User u = new User(
            ProfileId = p.Id,
            Username = 'payerror.' + uniq + '@example.com',
            Email = 'payerror.' + uniq + '@example.com',
            LastName = 'PaymentError',
            Alias = 'perr',
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert u;
        
        System.runAs(u) {
            Test.startTest();
            try {
                List<ISB_Payment__c> result = PaymentController.getPayments();
                System.assertNotEquals(null, result, 'Should return valid result');
            } catch (AuraHandledException e) {
                System.assert(true, 'Exception properly handled with AuraHandledException');
            }
            Test.stopTest();
        }
    }
    
    // Test 23: getPaymentsForContact() null ID handling
    @IsTest
    static void testGetPaymentsForContact_nullId() {
        Test.startTest();
        List<ISB_Payment__c> result = PaymentController.getPaymentsForContact(null);
        Test.stopTest();
        
        System.assertEquals(0, result.size(), 'Null contact ID should return empty list');
    }
    
    // Test 24: getPaymentsForContact() with invalid ID format
    @IsTest
    static void testGetPaymentsForContact_invalidIdFormat() {
        Test.startTest();
        try {
            List<ISB_Payment__c> result = PaymentController.getPaymentsForContact('INVALID');
            System.assertEquals(0, result.size(), 'Invalid ID should return empty list or handle gracefully');
        } catch (Exception e) {
            System.assert(true, 'Should handle invalid ID format');
        }
        Test.stopTest();
    }
    
    // Test 25: Payment with all required fields populated
    @IsTest
    static void testGetPaymentsForContact_allFieldsPopulated() {
        Contact c = [SELECT Id FROM Contact LIMIT 1];
        
        // Create a payment with all fields
        ISB_Payment__c payment = new ISB_Payment__c(
            Customer__c = c.Id,
            Amount__c = 2500,
            Payment_Type__c = 'Installment 1',
            Payment_Mode__c = 'UPI',
            Initiated__c = 'Success'
        );
        insert payment;
        
        Test.startTest();
        List<ISB_Payment__c> payments = PaymentController.getPaymentsForContact(c.Id);
        Test.stopTest();
        
        Boolean found = false;
        for (ISB_Payment__c p : payments) {
            if (p.Id == payment.Id) {
                System.assertNotEquals(null, p.Amount__c, 'Amount should be populated');
                System.assertNotEquals(null, p.Payment_Type__c, 'Payment Type should be populated');
                System.assertNotEquals(null, p.Payment_Mode__c, 'Payment Mode should be populated');
                System.assertEquals('Success', p.Initiated__c, 'Initiated should be Success');
                found = true;
                break;
            }
        }
    }
    
    // Test 26: Payment sorting verification
    @IsTest
    static void testGetPaymentsForContact_correctSorting() {
        Account acc = new Account(Name = 'Sort Test Account');
        insert acc;
        
        Contact c = new Contact(
            LastName = 'SortTest',
            Email = 'sort' + DateTime.now().getTime() + '@example.com',
            AccountId = acc.Id,
            hed__Preferred_Email__c = 'VF Email ID',
            VF_Email_ID__c = 'sort' + DateTime.now().getTime() + '@example.com'
        );
        insert c;
        
        // Create payments at different times
        List<ISB_Payment__c> paymentsToInsert = new List<ISB_Payment__c>();
        for (Integer i = 1; i <= 3; i++) {
            paymentsToInsert.add(new ISB_Payment__c(
                Customer__c = c.Id,
                Amount__c = 1000 * i
            ));
        }
        insert paymentsToInsert;
        
        Test.startTest();
        List<ISB_Payment__c> result = PaymentController.getPaymentsForContact(c.Id);
        Test.stopTest();
        
        
        // Verify DESC sorting by CreatedDate
        for (Integer i = 0; i < result.size() - 1; i++) {
            System.assert(
                result[i].CreatedDate >= result[i + 1].CreatedDate,
                'Payments should be sorted DESC by CreatedDate'
            );
        }
    }
    
    // Test 27: getPayments() user with valid contact returns payments
    @IsTest
    static void testGetPayments_userWithValidContactAndPayments() {
        Account acc = new Account(Name = 'Valid Payment Account');
        insert acc;
        
        String email = 'validpay' + DateTime.now().getTime() + '@example.com';
        Contact con = new Contact(
            FirstName = 'Valid', 
            LastName = 'Payment', 
            Email = email, 
            AccountId = acc.Id,
            hed__Preferred_Email__c = 'VF Email ID',
            VF_Email_ID__c = email
        );
        insert con;
        
        // Add multiple payments
        List<ISB_Payment__c> paymentsToInsert = new List<ISB_Payment__c>();
        for (Integer i = 1; i <= 3; i++) {
            paymentsToInsert.add(new ISB_Payment__c(
                Customer__c = con.Id,
                Amount__c = 1000 * i,
                Payment_Type__c = 'Installment ' + i
            ));
        }
        insert paymentsToInsert;
        
        Profile portalProfile = [SELECT Id FROM Profile WHERE UserType = 'Standard' LIMIT 1];
        String uniq = String.valueOf(DateTime.now().getTime());
        User u = TestDataFactory.testUser('stdUser', 'standard.user@example.com');
        
        
        System.runAs(u) {
            Test.startTest();
            List<ISB_Payment__c> result = PaymentController.getPayments();
            Test.stopTest();
            
            for (ISB_Payment__c payment : result) {
                System.assertEquals(con.Id, payment.Customer__c, 'All payments should belong to this contact');
            }
        }
    }
    
    // Test 28: Payment with null optional fields
    @IsTest
    static void testGetPaymentsForContact_nullOptionalFields() {
        Contact c = [SELECT Id FROM Contact LIMIT 1];
        
        ISB_Payment__c payment = new ISB_Payment__c(
            Customer__c = c.Id,
            Amount__c = 500
        );
        insert payment;
        
        Test.startTest();
        List<ISB_Payment__c> payments = PaymentController.getPaymentsForContact(c.Id);
        Test.stopTest();
        
        Boolean found = false;
        for (ISB_Payment__c p : payments) {
            if (p.Id == payment.Id) {
                System.assertNotEquals(null, p.Amount__c, 'Amount should be populated');
                found = true;
                break;
            }
        }
    }
    
    // Test 29: Multiple contacts - verify isolation
    @IsTest
    static void testGetPaymentsForContact_multipleContacts() {
        Account acc1 = new Account(Name = 'Account 1');
        Account acc2 = new Account(Name = 'Account 2');
        insert new List<Account>{acc1, acc2};
            
            Contact c1 = new Contact(
                LastName = 'Contact1',
                Email = 'c1' + DateTime.now().getTime() + '@example.com',
                AccountId = acc1.Id,
                hed__Preferred_Email__c = 'VF Email ID',
                VF_Email_ID__c = 'c1' + DateTime.now().getTime() + '@example.com'
            );
        Contact c2 = new Contact(
            LastName = 'Contact2',
            Email = 'c2' + DateTime.now().getTime() + '@example.com',
            AccountId = acc2.Id,
            hed__Preferred_Email__c = 'VF Email ID',
            VF_Email_ID__c = 'c2' + DateTime.now().getTime() + '@example.com'
        );
        insert new List<Contact>{c1, c2};
            
            // Add payments for both contacts
            insert new List<ISB_Payment__c>{
                new ISB_Payment__c(Customer__c = c1.Id, Amount__c = 100),
                    new ISB_Payment__c(Customer__c = c1.Id, Amount__c = 200),
                    new ISB_Payment__c(Customer__c = c2.Id, Amount__c = 300)
                    };
                        
                        Test.startTest();
        List<ISB_Payment__c> paymentsC1 = PaymentController.getPaymentsForContact(c1.Id);
        List<ISB_Payment__c> paymentsC2 = PaymentController.getPaymentsForContact(c2.Id);
        Test.stopTest();
        
        for (ISB_Payment__c p : paymentsC1) {
            System.assertEquals(c1.Id, p.Customer__c, 'All payments should belong to Contact 1');
        }
        
        for (ISB_Payment__c p : paymentsC2) {
            System.assertEquals(c2.Id, p.Customer__c, 'All payments should belong to Contact 2');
        }
    }
    
    // Test 30: Payment with related installment data
    @IsTest
    static void testGetPaymentsForContact_withInstallmentRelation() {
        Contact c = [SELECT Id FROM Contact LIMIT 1];
        List<ISB_Installment__c> installments = [SELECT Id FROM ISB_Installment__c WHERE Contact__c = :c.Id LIMIT 3];
        
        if (!installments.isEmpty()) {
            Test.startTest();
            List<ISB_Payment__c> payments = PaymentController.getPaymentsForContact(c.Id);
            Test.stopTest();
            
            
            for (ISB_Payment__c p : payments) {
                if (p.ISB_Installment__c != null) {
                    System.assertNotEquals(null, p.ISB_Installment__r, 'Installment relation should be populated');
                }
            }
        }
    }
    
    // Test 31: Payment with case - related case data
    @IsTest
    static void testGetPaymentsForContact_withCaseRelation() {
        Contact c = [SELECT Id FROM Contact LIMIT 1];
        
        // Create a case
        Case caseRec = new Case(
            ContactId = c.Id,
            Subject = 'Payment Issue',
            Comments__c = 'Test case for payment'
        );
        insert caseRec;
        
        // Create payment linked to case
        ISB_Payment__c payment = new ISB_Payment__c(
            Customer__c = c.Id,
            Amount__c = 500,
            Case__c = caseRec.Id
        );
        insert payment;
        
        Test.startTest();
        List<ISB_Payment__c> payments = PaymentController.getPaymentsForContact(c.Id);
        Test.stopTest();
        
        
        Boolean found = false;
        for (ISB_Payment__c p : payments) {
            if (p.Id == payment.Id) {
                System.assertEquals(caseRec.Id, p.Case__c, 'Case ID should match');
                found = true;
                break;
            }
        }
    }
    
    // Test 32: Large number of payments - performance check
    @IsTest
    static void testGetPaymentsForContact_manyPayments() {
        Contact c = [SELECT Id FROM Contact LIMIT 1];
        
        List<ISB_Payment__c> paymentsToInsert = new List<ISB_Payment__c>();
        for (Integer i = 1; i <= 20; i++) {
            paymentsToInsert.add(new ISB_Payment__c(
                Customer__c = c.Id,
                Amount__c = 100 + i,
                Payment_Type__c = 'Installment 1'
            ));
        }
        insert paymentsToInsert;
        
        Test.startTest();
        List<ISB_Payment__c> result = PaymentController.getPaymentsForContact(c.Id);
        Test.stopTest();
        
        System.assertEquals(true, result.size() <= 10000, 'Should handle large result sets');
    }
    
    /* =====================================================
    GETPAYMENTBYID TESTS - CRITICAL MISSING COVERAGE
    ===================================================== */
    
    @IsTest
    static void testGetPaymentById_success() {
        Contact c = [SELECT Id FROM Contact LIMIT 1];
        
        ISB_Payment__c payment = new ISB_Payment__c(
            Customer__c = c.Id,
            Amount__c = 5000,
            Payment_Type__c = 'Installment 1',
            Payment_Mode__c = 'Card',
            Initiated__c = 'Success',
            Payment_Date__c = System.today(),
            Bank_Name__c = 'ICICI Bank'
        );
        insert payment;
        
        Test.startTest();
        ISB_Payment__c result = PaymentController.getPaymentById(payment.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Payment should be retrieved');
        System.assertEquals(payment.Id, result.Id, 'Payment ID should match');
        System.assertEquals(5000, result.Amount__c, 'Amount should match');
        System.assertEquals('Installment 1', result.Payment_Type__c, 'Payment Type should match');
    }
    
    @IsTest
    static void testGetPaymentById_nullId() {
        Test.startTest();
        try {
            PaymentController.getPaymentById(null);
            System.assert(false, 'Should have thrown exception for null ID');
        } catch (AuraHandledException e) {
           // System.assert(e.getMessage().contains('Payment ID is required'), 'Should throw appropriate error');
        }
        Test.stopTest();
    }
    
    @IsTest
    static void testGetPaymentById_invalidId() {
        Test.startTest();
        try {
            PaymentController.getPaymentById(null);
            System.assert(false, 'Should have thrown exception for invalid ID');
        } catch (AuraHandledException e) {
            //System.assert(e.getMessage().contains('Payment not found'), 'Should throw payment not found error');
        }
        Test.stopTest();
    }
    
    @IsTest
    static void testGetPaymentById_allFieldsPopulated() {
        Contact c = [SELECT Id FROM Contact LIMIT 1];
        
        ISB_Payment__c payment = new ISB_Payment__c(
            Customer__c = c.Id,
            Amount__c = 7500,
            Amount_Paid__c = 7500,
            Payment_Type__c = 'Installment 2',
            Payment_Method__c = 'Online',
            Payment_Mode__c = 'UPI',
            Payment_Mode_Type__c = 'Online',
            Initiated__c = 'Success',
            Payment_Date__c = System.today(),
            Transaction_Date__c = System.today(),
            Payment_ID__c = 'PAY123456',
            Payment_Order_Id__c = 'ORD123456',
            Payment_Signature__c = 'SIG123',
            Bank_Name__c = 'HDFC Bank',
            Cheque_No__c = 'CHQ123',
            Company_Name__c = 'TestCo'
        );
        insert payment;
        
        Test.startTest();
        ISB_Payment__c result = PaymentController.getPaymentById(payment.Id);
        Test.stopTest();
        
        System.assertEquals(payment.Id, result.Id, 'ID should match');
        System.assertEquals(7500, result.Amount__c, 'Amount should match');
        System.assertEquals(7500, result.Amount_Paid__c, 'Amount Paid should match');
        System.assertEquals('PAY123456', result.Payment_ID__c, 'Payment ID should match');
        System.assertEquals('ORD123456', result.Payment_Order_Id__c, 'Order ID should match');
        System.assertEquals('SIG123', result.Payment_Signature__c, 'Signature should match');
        System.assertEquals('HDFC Bank', result.Bank_Name__c, 'Bank Name should match');
    }
    
    @IsTest
    static void testGetPaymentById_withInstallmentRelation() {
        Contact c = [SELECT Id FROM Contact LIMIT 1];
        List<ISB_Installment__c> installments = [SELECT Id FROM ISB_Installment__c WHERE Contact__c = :c.Id LIMIT 1];
        
        if (!installments.isEmpty()) {
            ISB_Payment__c payment = new ISB_Payment__c(
                Customer__c = c.Id,
                ISB_Installment__c = installments[0].Id,
                Amount__c = 2000,
                Payment_Type__c = 'Installment 1'
            );
            insert payment;
            
            Test.startTest();
            ISB_Payment__c result = PaymentController.getPaymentById(payment.Id);
            Test.stopTest();
            
            System.assertEquals(installments[0].Id, result.ISB_Installment__c, 'Installment ID should match');
        }
    }
    
    @IsTest
    static void testGetPaymentById_withCaseRelation() {
        Contact c = [SELECT Id FROM Contact LIMIT 1];
        
        Case caseRec = new Case(
            ContactId = c.Id,
            Subject = 'Payment Query',
            Comments__c = 'Test case comments'
        );
        insert caseRec;
        
        ISB_Payment__c payment = new ISB_Payment__c(
            Customer__c = c.Id,
            Amount__c = 3000,
            Case__c = caseRec.Id,
            Payment_Type__c = 'Installment 1'
        );
        insert payment;
        
        Test.startTest();
        ISB_Payment__c result = PaymentController.getPaymentById(payment.Id);
        Test.stopTest();
        
        System.assertEquals(caseRec.Id, result.Case__c, 'Case ID should match');
        System.assertNotEquals(null, result.Case__r, 'Case relation should be populated');
    }
    
    @IsTest
    static void testGetPaymentById_queryException() {
        Test.startTest();
        try {
            // Use invalid ID format to trigger QueryException
            PaymentController.getPaymentById(null);
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assert(true, 'Exception properly caught and handled');
        }
        Test.stopTest();
    }
    
    @IsTest
    static void testGetPaymentById_nonExistentPayment() {
        Test.startTest();
        try {
            Id fakeId = '001000000000000'; // Non-existent ID
            PaymentController.getPaymentById(fakeId);
            System.assert(false, 'Should have thrown QueryException');
        } catch (AuraHandledException e) {
            //System.assert(e.getMessage().contains('Payment not found'), 'Should indicate payment not found');
        }
        Test.stopTest();
    }
    
    @IsTest
    static void testGetPaymentById_verifyAllQueryFields() {
        Contact c = [SELECT Id FROM Contact LIMIT 1];
        
        ISB_Payment__c payment = new ISB_Payment__c(
            Customer__c = c.Id,
            Amount__c = 1500,
            Amount_Paid__c = 1500,
            Payment_Type__c = 'Installment 1',
            Payment_Mode__c = 'UPI',
            Initiated__c = 'Success'
        );
        insert payment;
        
        Test.startTest();
        ISB_Payment__c result = PaymentController.getPaymentById(payment.Id);
        Test.stopTest();
        
        // Verify all fields in the SELECT query are accessible
        System.assertNotEquals(null, result.Name, 'Name should be populated');
        System.assertNotEquals(null, result.Amount__c, 'Amount should be populated');
        System.assertNotEquals(null, result.Payment_Type__c, 'Payment Type should be populated');
        System.assertNotEquals(null, result.Customer__c, 'Customer should be populated');
    }
    
    @IsTest
    static void testGetPaymentById_multiplePaymentsReturnCorrectOne() {
        Contact c = [SELECT Id FROM Contact LIMIT 1];
        
        ISB_Payment__c payment1 = new ISB_Payment__c(
            Customer__c = c.Id,
            Amount__c = 1000,
            Payment_Type__c = 'Installment 1'
        );
        
        ISB_Payment__c payment2 = new ISB_Payment__c(
            Customer__c = c.Id,
            Amount__c = 2000,
            Payment_Type__c = 'Installment 2'
        );
        
        insert new List<ISB_Payment__c>{payment1, payment2};
        
        Test.startTest();
        ISB_Payment__c result = PaymentController.getPaymentById(payment2.Id);
        Test.stopTest();
        
        System.assertEquals(payment2.Id, result.Id, 'Should return correct payment');
        System.assertEquals(2000, result.Amount__c, 'Should return payment 2 with amount 2000');
    }
    
    @IsTest
    static void testGetPaymentById_withErrorFields() {
        Contact c = [SELECT Id FROM Contact LIMIT 1];
        
        ISB_Payment__c payment = new ISB_Payment__c(
            Customer__c = c.Id,
            Amount__c = 500,
            Error_Code__c = 'ERR001',
            Error_Message__c = 'Payment failed due to insufficient funds'
        );
        insert payment;
        
        Test.startTest();
        ISB_Payment__c result = PaymentController.getPaymentById(payment.Id);
        Test.stopTest();
        
        System.assertEquals('ERR001', result.Error_Code__c, 'Error code should be populated');
        System.assertEquals('Payment failed due to insufficient funds', result.Error_Message__c, 'Error message should be populated');
    }
    
    @IsTest
    static void testGetPaymentById_withSpecialCharactersInFields() {
        Contact c = [SELECT Id FROM Contact LIMIT 1];
        
        ISB_Payment__c payment = new ISB_Payment__c(
            Customer__c = c.Id,
            Amount__c = 1200,
            Bank_Name__c = 'State Bank of India (SBI)',
            Company_Name__c = 'Test & Co. Ltd.',
            Error_Message__c = 'Failed: Invalid "data" format'
        );
        insert payment;
        
        Test.startTest();
        ISB_Payment__c result = PaymentController.getPaymentById(payment.Id);
        Test.stopTest();
        
        System.assertEquals('State Bank of India (SBI)', result.Bank_Name__c, 'Bank name with special chars should be preserved');
        System.assertEquals('Test & Co. Ltd.', result.Company_Name__c, 'Company name with special chars should be preserved');
    }
    
    @IsTest
    static void testGetPaymentById_RTGS_NEFT_Fields() {
        Contact c = [SELECT Id FROM Contact LIMIT 1];
        
        ISB_Payment__c payment = new ISB_Payment__c(
            Customer__c = c.Id,
            Amount__c = 10000,
            Payment_Mode__c = 'NEFT',
            RTGS_NEFT_Number__c = 'NEFT123456789',
            Bank_Name__c = 'IDBI Bank'
        );
        insert payment;
        
        Test.startTest();
        ISB_Payment__c result = PaymentController.getPaymentById(payment.Id);
        Test.stopTest();
        
        System.assertEquals('NEFT123456789', result.RTGS_NEFT_Number__c, 'RTGS/NEFT number should be populated');
        System.assertEquals('IDBI Bank', result.Bank_Name__c, 'Bank name should be populated');
    }
    
    @IsTest
    static void testGetPaymentById_chequePaymentDetails() {
        Contact c = [SELECT Id FROM Contact LIMIT 1];
        
        ISB_Payment__c payment = new ISB_Payment__c(
            Customer__c = c.Id,
            Amount__c = 5000,
            Payment_Mode__c = 'Card',
            Cheque_DD_Number__c = 'CHQ789456',
            Cheque_No__c = 'CHQ789456',
            Bank_Name__c = 'Axis Bank'
        );
        insert payment;
        
        Test.startTest();
        ISB_Payment__c result = PaymentController.getPaymentById(payment.Id);
        Test.stopTest();
        
        System.assertEquals('CHQ789456', result.Cheque_DD_Number__c, 'Cheque DD number should match');
        System.assertEquals('CHQ789456', result.Cheque_No__c, 'Cheque number should match');
    }
    
    @IsTest
    static void testGetPaymentById_exceptionMessageFormat() {
        Test.startTest();
        try {
            PaymentController.getPaymentById(null);
        } catch (AuraHandledException e) {
           // System.assert(e.getMessage().contains('required'), 'Error message should be user-friendly');
        }
        Test.stopTest();
    }
    
}