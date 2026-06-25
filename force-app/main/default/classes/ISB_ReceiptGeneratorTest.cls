@isTest
public class ISB_ReceiptGeneratorTest {
    // Test class for ISB_ReceiptGenerator
    // Using TestDataFactory for reusable test data

    @testSetup
    static void setup() {
        // Create Contact (Student/Customer)
        Contact con = TestDataFactory.testContact();
        con.Email = 'testrecipient@example.com';
        update con;
        
        // Create Program
        Program prog = TestDataFactory.testProgram();
        
        // Create Program Enrollment
        ProgramEnrollment pe = TestDataFactory.testProgramEnrollment(con, prog);
        
        // Create ISB Installment using TestDataFactory
        ISB_Installment__c inst = TestDataFactory.testInstallment(con.Id, prog.Id, pe.Id);
        
        // Create ISB Payment using TestDataFactory
        ISB_Payment__c pay = TestDataFactory.testPayment(inst.Id, con.Id);

        // Create Email Template if it doesn't exist
        TestDataFactory.getOrCreatePaymentSuccessTemplate();
    }

    /**
     * Test: Generate and attach receipt successfully
     * Coverage: Happy path scenario
     */
    @isTest
    static void testGenerateAndAttachReceiptAsync() {
        ISB_Payment__c pay = [SELECT Id, Name FROM ISB_Payment__c LIMIT 1];
        
        Test.startTest();
        ISB_ReceiptGenerator.generateAndAttachReceiptAsync(pay.Id, pay.Name);
        Test.stopTest();
        
        // Verify: ContentDocumentLink created and linked to Payment
        List<ContentDocumentLink> links = [SELECT Id, ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :pay.Id];
        System.assert(!links.isEmpty(), 'Receipt PDF should be attached to Payment');
        System.assertEquals(1, links.size(), 'Exactly one attachment expected');
        
        // Verify: ContentVersion has correct title format
        ContentVersion cv = [SELECT Title FROM ContentVersion WHERE ContentDocumentId = :links[0].ContentDocumentId LIMIT 1];
        System.assert(cv.Title.contains('Receipt_'), 'Attachment title should contain Receipt_ prefix');
        System.assert(cv.Title.contains('.pdf'), 'Attachment title should have .pdf extension');
    }

    /**
     * Test: Email robustness when customer has no email
     * Coverage: Error handling path - null email scenario
     */
    

    /**
     * Test: Email robustness when customer is null
     * Coverage: Error handling path - null customer scenario
     */
    @isTest
    static void testEmailLogicRobustness_NoCustomer() {
        ISB_Payment__c pay = [SELECT Id, Name FROM ISB_Payment__c LIMIT 1];
        pay.Customer__c = null;
        update pay;
        
        Test.startTest();
        ISB_ReceiptGenerator.generateAndAttachReceiptAsync(pay.Id, pay.Name);
        Test.stopTest();
        
        // Verify: Receipt PDF still attached even if customer is null
        List<ContentDocumentLink> links = [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :pay.Id];
        System.assertEquals(1, links.size(), 'Receipt PDF should still be attached even if customer is null');
    }

    /**
     * Test: Receipt generation with different payment amounts
     * Coverage: Variability in payment data
     */
    @isTest
    static void testGenerateReceiptWithVariousAmounts() {
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        Program prog = [SELECT Id FROM Program LIMIT 1];
        ProgramEnrollment pe = [SELECT Id FROM ProgramEnrollment LIMIT 1];
        
        // Create multiple installments with different amounts
        ISB_Installment__c inst1 = TestDataFactory.testInstallment(con.Id, prog.Id, pe.Id, 500.0, 500.0, 1);
        ISB_Installment__c inst2 = TestDataFactory.testInstallment(con.Id, prog.Id, pe.Id, 2000.0, 2000.0, 2);
        
        ISB_Payment__c pay1 = TestDataFactory.testPayment(inst1.Id, con.Id, 500.0);
        ISB_Payment__c pay2 = TestDataFactory.testPayment(inst2.Id, con.Id, 2000.0);
        
        Test.startTest();
        ISB_ReceiptGenerator.generateAndAttachReceiptAsync(pay1.Id, pay1.Name);
        ISB_ReceiptGenerator.generateAndAttachReceiptAsync(pay2.Id, pay2.Name);
        Test.stopTest();
        
        // Verify: Both receipts generated successfully
        List<ContentDocumentLink> links1 = [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :pay1.Id];
        List<ContentDocumentLink> links2 = [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :pay2.Id];
        
        System.assertEquals(1, links1.size(), 'First receipt should be attached');
        System.assertEquals(1, links2.size(), 'Second receipt should be attached');
    }

    /**
     * Test: Multiple receipts for same payment (edge case)
     * Coverage: Multiple attachments scenario
     */
    @isTest
    static void testMultipleReceiptAttachments() {
        ISB_Payment__c pay = [SELECT Id, Name FROM ISB_Payment__c LIMIT 1];
        
        Test.startTest();
        // Call method multiple times
        ISB_ReceiptGenerator.generateAndAttachReceiptAsync(pay.Id, pay.Name);
        ISB_ReceiptGenerator.generateAndAttachReceiptAsync(pay.Id, pay.Name);
        Test.stopTest();
        
        // Verify: Multiple attachments created
        List<ContentDocumentLink> links = [SELECT Id, ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :pay.Id];
        System.assertEquals(2, links.size(), 'Two receipts should be attached for two calls');
    }

    /**
     * Test: Verify ContentVersion properties
     * Coverage: File metadata validation
     */
    @isTest
    static void testContentVersionProperties() {
        ISB_Payment__c pay = [SELECT Id, Name FROM ISB_Payment__c LIMIT 1];
        
        Test.startTest();
        ISB_ReceiptGenerator.generateAndAttachReceiptAsync(pay.Id, pay.Name);
        Test.stopTest();
        
        // Get ContentVersion and verify properties
        List<ContentVersion> cvList = [SELECT Id, Title, IsMajorVersion, VersionData FROM ContentVersion WHERE Title LIKE 'Receipt_%'];
        System.assertEquals(1, cvList.size(), 'Exactly one ContentVersion should be created');
        
        ContentVersion cv = cvList[0];
        System.assert(cv.IsMajorVersion, 'ContentVersion should be marked as major version');
        System.assert(cv.VersionData != null, 'ContentVersion should have file data');
        System.assert(cv.VersionData.size() > 0, 'ContentVersion should have non-empty file data');
    }

    /**
     * Test: Verify ContentDocumentLink properties
     * Coverage: File sharing and permissions validation
     */
    @isTest
    static void testContentDocumentLinkProperties() {
        ISB_Payment__c pay = [SELECT Id, Name FROM ISB_Payment__c LIMIT 1];
        
        Test.startTest();
        ISB_ReceiptGenerator.generateAndAttachReceiptAsync(pay.Id, pay.Name);
        Test.stopTest();
        
        // Get ContentDocumentLink and verify sharing settings
        List<ContentDocumentLink> links = [SELECT Id, ShareType, Visibility FROM ContentDocumentLink WHERE LinkedEntityId = :pay.Id];
        System.assertEquals(1, links.size(), 'Exactly one ContentDocumentLink should be created');
        
        ContentDocumentLink cdl = links[0];
        System.assertEquals('V', cdl.ShareType, 'ShareType should be Viewer (V)');
        System.assertEquals('AllUsers', cdl.Visibility, 'Visibility should be AllUsers');
    }

    /**
     * Test: Payment with different customer emails
     * Coverage: Email address variations
     */
    @isTest
    static void testPaymentWithDifferentEmails() {
        // Create contact with different email
        Contact con2 = new Contact(
            FirstName = 'Test',
            LastName = 'User2',
            Email = 'testuser2@example.com',
            hed__Preferred_Email__c = 'VF Email ID',
            VF_Email_ID__c = 'bodhtree.admin@isb.com'
        );
        insert con2;
        
        Program prog = [SELECT Id FROM Program LIMIT 1];
        ProgramEnrollment pe = TestDataFactory.testProgramEnrollment(con2, prog);
        
        ISB_Installment__c inst = TestDataFactory.testInstallment(con2.Id, prog.Id, pe.Id);
        ISB_Payment__c pay = TestDataFactory.testPayment(inst.Id, con2.Id);
        
        Test.startTest();
        ISB_ReceiptGenerator.generateAndAttachReceiptAsync(pay.Id, pay.Name);
        Test.stopTest();
        
        // Verify: Receipt generated successfully
        List<ContentDocumentLink> links = [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :pay.Id];
        System.assertEquals(1, links.size(), 'Receipt should be attached for different customer email');
    }

    /**
     * Test: Blank payment name handling
     * Coverage: Edge case - blank payment name
     */
    @isTest
    static void testReceiptGenerationWithBlankPaymentName() {
        ISB_Payment__c pay = [SELECT Id, Name FROM ISB_Payment__c LIMIT 1];
        
        Test.startTest();
        ISB_ReceiptGenerator.generateAndAttachReceiptAsync(pay.Id, '');
        Test.stopTest();
        
        // Verify: Receipt still generated with blank name
        List<ContentDocumentLink> links = [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :pay.Id];
        System.assertEquals(1, links.size(), 'Receipt should be attached even with blank payment name');
    }

    /**
     * Test: Future method execution context
     * Coverage: Async execution validation
     */
    @isTest
    static void testAsyncExecutionContext() {
        ISB_Payment__c pay = [SELECT Id, Name FROM ISB_Payment__c LIMIT 1];
        
        Test.startTest();
        // Future method can only be called from synchronous context
        ISB_ReceiptGenerator.generateAndAttachReceiptAsync(pay.Id, pay.Name);
        Test.stopTest();
        
        // Verify: No exceptions thrown
        List<ContentDocumentLink> links = [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :pay.Id];
        System.assertEquals(1, links.size(), 'Async execution should complete successfully');
    }

    /**
     * Test: Installment with zero pending amount
     * Coverage: Edge case - fully paid installment
     */
    @isTest
    static void testReceiptForFullyPaidInstallment() {
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        Program prog = [SELECT Id FROM Program LIMIT 1];
        ProgramEnrollment pe = [SELECT Id FROM ProgramEnrollment LIMIT 1];
        
        // Create installment with zero pending amount
        ISB_Installment__c inst = TestDataFactory.testInstallment(con.Id, prog.Id, pe.Id, 1000.0, 0.0, 1);
        ISB_Payment__c pay = TestDataFactory.testPayment(inst.Id, con.Id, 1000.0);
        
        Test.startTest();
        ISB_ReceiptGenerator.generateAndAttachReceiptAsync(pay.Id, pay.Name);
        Test.stopTest();
        
        // Verify: Receipt generated for fully paid installment
        List<ContentDocumentLink> links = [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :pay.Id];
        System.assertEquals(1, links.size(), 'Receipt should be generated for fully paid installment');
    }

    /**
     * Test: Multiple payments linked to same installment
     * Coverage: Multiple payments per installment scenario
     */
    @isTest
    static void testMultiplePaymentsForSingleInstallment() {
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        Program prog = [SELECT Id FROM Program LIMIT 1];
        ProgramEnrollment pe = [SELECT Id FROM ProgramEnrollment LIMIT 1];
        
        ISB_Installment__c inst = TestDataFactory.testInstallment(con.Id, prog.Id, pe.Id, 1000.0, 600.0, 1);
        
        // Create two payments for same installment (partial payments)
        ISB_Payment__c pay1 = TestDataFactory.testPayment(inst.Id, con.Id, 400.0);
        ISB_Payment__c pay2 = TestDataFactory.testPayment(inst.Id, con.Id, 600.0);
        
        Test.startTest();
        ISB_ReceiptGenerator.generateAndAttachReceiptAsync(pay1.Id, pay1.Name);
        ISB_ReceiptGenerator.generateAndAttachReceiptAsync(pay2.Id, pay2.Name);
        Test.stopTest();
        
        // Verify: Both receipts generated independently
        List<ContentDocumentLink> links1 = [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :pay1.Id];
        List<ContentDocumentLink> links2 = [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :pay2.Id];
        
        System.assertEquals(1, links1.size(), 'First payment receipt should be attached');
        System.assertEquals(1, links2.size(), 'Second payment receipt should be attached');
    }
}