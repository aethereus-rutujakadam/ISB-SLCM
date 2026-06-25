@isTest
public class ISB_Payment_ExtensionTest {
    
    @testSetup
    static void setupData() {
        // Create base data linked to TestDataFactory
        Contact student = TestDataFactory.testContact();
        Program prog = TestDataFactory.testProgram();
        
        // Ensure student has address for query coverage
        student.MailingStreet = '123 Test St';
        student.MailingCity = 'Test City';
        student.MailingPostalCode = '12345';
        student.MailingCountry = 'India';
        update student;
        
        // Create Program Enrollment
        ProgramEnrollment pe = TestDataFactory.testProgramEnrollment(student, prog);
        
        // Create Installment (Manually since Factory doesn't have it)
        ISB_Installment__c inst = new ISB_Installment__c(
            Contact__c = student.Id,
            Program__c = prog.Id,
            Program_Enrollment__c = pe.Id,
            Installment_Number__c = '1',
            Due_Date__c = Date.today(),
            Actual_Amount__c = 50000,
            Pending_Amount__c = 0
        );
        insert inst;
        
        // Create Payment
        ISB_Payment__c payment = new ISB_Payment__c(
            ISB_Installment__c = inst.Id,
            Customer__c = student.Id,
            Amount__c = 50000.50,
            Transaction_Date__c = Date.today(),
            Initiated__c = 'Success',
            Cheque_DD_Number__c = 'CHQ123',
            Bank_Name__c = 'Test Bank'
        );
        insert payment;
    }
    
    @isTest
    static void testConstructorWithId() {
        // Get the payment created in setup
        ISB_Payment__c payment = [SELECT Id, Amount__c FROM ISB_Payment__c LIMIT 1];
        
        Test.startTest();
        // Set the current page (required for StandardController context)
        PageReference pageRef = Page.ISBPaymentReceipt; 
        Test.setCurrentPage(pageRef);
        
        // Instantiate controller
        ApexPages.StandardController stdCon = new ApexPages.StandardController(payment);
        ISB_Payment_Extension ext = new ISB_Payment_Extension(stdCon);
        Test.stopTest();
        
        // Assertions
        System.assertNotEquals(null, ext.paymentRecord, 'paymentRecord should be populated');
        System.assertEquals(payment.Id, ext.paymentRecord.Id, 'Should fetch correct payment');
        System.assertNotEquals(null, ext.finalProgramName, 'Program name should be set');
        System.assert(ext.amountInWords != null, 'Amount in words should be calculated');
        System.assert(ext.amountInWords.contains('Rupees'), 'Amount string should contain currency');
    }
    
    @isTest
    static void testConstructorWithoutId() {
        // Test constructor behavior when ID is missing or new record
        ISB_Payment__c emptyPayment = new ISB_Payment__c();
        
        Test.startTest();
        ApexPages.StandardController stdCon = new ApexPages.StandardController(emptyPayment);
        ISB_Payment_Extension ext = new ISB_Payment_Extension(stdCon);
        Test.stopTest();
        
        // Should not crash, fields should be null/empty
        System.assertEquals(null, ext.paymentRecord, 'Payment record should be null for new instance');
    }
    
    @isTest
    static void testGenerateAndAttachReceipt() {
        ISB_Payment__c payment = [SELECT Id, Name FROM ISB_Payment__c LIMIT 1];
        
        Test.startTest();
        String result = ISB_Payment_Extension.generateAndAttachReceipt(payment.Id, 'TestPayment');
        Test.stopTest();
        
        System.assertEquals('Success', result, 'Should return Success string');
        
        // Verify ContentVersion created
        List<ContentDocumentLink> links = [
            SELECT Id, ContentDocumentId 
            FROM ContentDocumentLink 
            WHERE LinkedEntityId = :payment.Id 
        ];
        System.assert(!links.isEmpty(), 'Receipt file should be linked to payment');
        
        ContentVersion cv = [
            SELECT Id, Title 
            FROM ContentVersion 
            WHERE ContentDocumentId = :links[0].ContentDocumentId 
            LIMIT 1
        ];
        System.assert(cv.Title.contains('Receipt_TestPayment'), 'File title should match format');
    }
    
    @isTest
    static void testCurrencyConversion() {
        Test.startTest();
        // Test Integer
        String result1 = ISB_Payment_Extension.convertToIndianCurrency(100);
        System.assert(result1.contains('One Hundred'), '100 should be One Hundred');
        
        // Test Decimal
        String result2 = ISB_Payment_Extension.convertToIndianCurrency(100.50);
        System.assert(result2.contains('Fifty Paise'), 'Should handle paise');
        
        // Test Large Number
        String result3 = ISB_Payment_Extension.convertToIndianCurrency(1000000);
        System.assert(result3.contains('Ten Lakh'), 'Should handle Lakhs');
        
        // Test Null/Zero
        String result4 = ISB_Payment_Extension.convertToIndianCurrency(0);
        System.assertEquals('Rupees Zero Only', result4);
        Test.stopTest();
    }
    
   /* @isTest
    static void testPathNullCheck() {
        Contact student = TestDataFactory.testContact();
        
        // Create Installment linked to NO program (to get null Program__r)
        ISB_Installment__c inst = new ISB_Installment__c(
            Contact__c = student.Id,
            Installment_Number__c = '2',
            Due_Date__c = Date.today(),
            Actual_Amount__c = 1000,
            Pending_Amount__c = 1000
            // Program__c intentionally left null
        );
        
        try {
            insert inst;
        } catch(DmlException e) {
            System.debug('Cannot insert Installment without Program. Skipping this specific test case.');
            return;
        }
        
        ISB_Payment__c payment = new ISB_Payment__c(
            ISB_Installment__c = inst.Id,
            Customer__c = student.Id,
            Amount__c = 1000
        );
        insert payment;
        
        Test.startTest();
        ApexPages.StandardController stdCon = new ApexPages.StandardController(payment);
        ISB_Payment_Extension ext = new ISB_Payment_Extension(stdCon);
        Test.stopTest();
        
        // If program is null, the query returns null for the relationship field
        System.assertEquals('', ext.finalProgramName, 'When program is missing, result should be empty string');
    }*/
}