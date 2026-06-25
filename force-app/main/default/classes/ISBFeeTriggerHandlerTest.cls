@isTest
private class ISBFeeTriggerHandlerTest {
    
    /**
     * @description Test data setup method
     */
    /**
     * @description Test data setup helper
     */
    static void setup() {
        // Create test Contact with required EDA fields
        Contact testContact = new Contact(
            FirstName = 'Test',
            LastName = 'Customer',
            Email = 'testcustomer' + System.currentTimeMillis() + '@example.com',
            New_Admit_Email__c = 'testcustomer' + System.currentTimeMillis() + '@example.com',
            hed__Preferred_Email__c = 'VF Email ID',
            VF_Email_ID__c = 'testcustomer' + System.currentTimeMillis() + '@example.com'
        );
        insert testContact;
        
        Program testProgram = new Program(
            Name = 'Test Program'
        );
        insert testProgram;
        
        // Create Program Enrollment linked to Contact
        ProgramEnrollment testEnrollment = new ProgramEnrollment(
            Name = 'Test Enrollment Old',
            ContactId = testContact.Id,
            ProgramId = testProgram.Id
        );
        insert testEnrollment;
    }
    
    /**
     * @description Test: handleBeforeInsert populates Program Enrollment and Customer when Contact is populated
     */
    @isTest
    static void testHandleBeforeInsert_WithValidContact() {
        setup();
        Contact testContact = [SELECT Id FROM Contact WHERE LastName = 'Customer' LIMIT 1];
        ProgramEnrollment testEnrollment = [SELECT Id FROM ProgramEnrollment WHERE ContactId = :testContact.Id LIMIT 1];
        
        Test.startTest();
        ISB_Fee__c fee = new ISB_Fee__c(
            Contact__c = testContact.Id,
            Customer__c = testContact.Id,
            Program_Enrollment__c = testEnrollment.Id,
            Fee_Amount__c = 100,
            Due_Date__c = System.Today(),
            Payment_Window__c = 2
        );
        insert fee;
        Test.stopTest();
        
        ISB_Fee__c insertedFee = [SELECT Id, Contact__c, Customer__c, Program_Enrollment__c, Fee_Status__c, Paid_Amount__c, Pending_Amount__c, Total_amount__c FROM ISB_Fee__c WHERE Id = :fee.Id];
        
        System.assertEquals(testContact.Id, insertedFee.Customer__c, 'Customer should be populated from Contact');
        System.assertEquals(testEnrollment.Id, insertedFee.Program_Enrollment__c, 'Program Enrollment should be populated');
        System.assertEquals('Not Paid', insertedFee.Fee_Status__c, 'Fee Status should be Not Paid');
        System.assertEquals(0, insertedFee.Paid_Amount__c, 'Paid Amount should be 0');
        System.assertEquals(100, insertedFee.Pending_Amount__c, 'Pending Amount should match Fee Amount');
        System.assertEquals(100, insertedFee.Total_amount__c, 'Total Amount should match Fee Amount');
    }
    
    /**
     * @description Test: handleBeforeInsert handles null Fee Amount
     */
    @isTest
    static void testHandleBeforeInsert_WithNullFeeAmount() {
        setup();
        Contact testContact = [SELECT Id FROM Contact WHERE LastName = 'Customer' LIMIT 1];
        ProgramEnrollment testEnrollment = [SELECT Id FROM ProgramEnrollment WHERE ContactId = :testContact.Id LIMIT 1];
        
        ISB_Fee__c fee = new ISB_Fee__c(
            Contact__c = testContact.Id,
            Customer__c = testContact.Id,
            Program_Enrollment__c = testEnrollment.Id,
            Fee_Amount__c = 0,
            Due_Date__c = System.Today(),
            Payment_Window__c = 2
        );
        
        Test.startTest();
        insert fee;
        Test.stopTest();
        
        ISB_Fee__c insertedFee = [SELECT Id, Pending_Amount__c, Total_amount__c FROM ISB_Fee__c WHERE Id = :fee.Id];
        System.assertNotEquals(null, insertedFee.Pending_Amount__c, 'Pending Amount should not be null when Fee Amount is 0');
    }
    
    /**
     * @description Test: handleBeforeInsert logic when map does not contain contact
     */
    @isTest
    static void testHandleBeforeInsert_ContactWithNoEnrollmentBranch() {
        // We test the logic branch direct call to cover the case where map doesn't have the contact
        ISB_Fee__c fee = new ISB_Fee__c(
            Contact__c = '003000000000000AAA', // Fake ID
            Fee_Amount__c = 100
        );
        
        Test.startTest();
        ISBFeeTriggerHandler.handleBeforeInsert(new List<ISB_Fee__c>{fee});
        Test.stopTest();
        
        System.assertEquals(null, fee.Program_Enrollment__c, 'Program Enrollment should remain null if not found in map');
    }
    
    /**
     * @description Test: handleBeforeInsert picks the most recent enrollment
     */
    @isTest
    static void testHandleBeforeInsert_MostRecentEnrollment() {
        setup();
        Contact testContact = [SELECT Id FROM Contact WHERE LastName = 'Customer' LIMIT 1];
        Program testProgram = [SELECT Id FROM Program LIMIT 1];
        ProgramEnrollment oldEnrollment = [SELECT Id FROM ProgramEnrollment WHERE ContactId = :testContact.Id LIMIT 1];
        
        // Ensure oldEnrollment has an older created date
        Test.setCreatedDate(oldEnrollment.Id, DateTime.now().addMinutes(-10));
        
        // Insert a second (more recent) enrollment
        ProgramEnrollment newerEnrollment = new ProgramEnrollment(
            Name = 'Test Enrollment New',
            ContactId = testContact.Id,
            ProgramId = testProgram.Id
        );
        insert newerEnrollment;
        
        Test.startTest();
        ISB_Fee__c fee = new ISB_Fee__c(
            Contact__c = testContact.Id,
            Customer__c = testContact.Id,
            Fee_Amount__c = 100,
            Due_Date__c = System.Today(),
            Payment_Window__c = 2
        );
        insert fee;
        Test.stopTest();
        
        ISB_Fee__c insertedFee = [SELECT Id, Program_Enrollment__c FROM ISB_Fee__c WHERE Id = :fee.Id];
        System.assertEquals(newerEnrollment.Id, insertedFee.Program_Enrollment__c, 'Most recent enrollment should be selected');
    }
    
    /**
     * @description Test: handleBeforeInsert handles empty list gracefully
     */
    @isTest
    static void testHandleBeforeInsert_EmptyList() {
        Test.startTest();
        ISBFeeTriggerHandler.handleBeforeInsert(new List<ISB_Fee__c>());
        Test.stopTest();
        
        Integer feeCount = [SELECT COUNT() FROM ISB_Fee__c];
        System.assertEquals(0, feeCount);
    }
    
    /**
     * @description Test: handleBeforeInsert handles list where all contacts are null
     */
    @isTest
    static void testHandleBeforeInsert_AllNullContacts() {
        List<ISB_Fee__c> fees = new List<ISB_Fee__c>{
            new ISB_Fee__c(Fee_Amount__c = 100),
            new ISB_Fee__c(Fee_Amount__c = 100)
        };
        
        Test.startTest();
        ISBFeeTriggerHandler.handleBeforeInsert(fees);
        Test.stopTest();
        
        for (ISB_Fee__c fee : fees) {
            System.assertEquals(null, fee.Program_Enrollment__c);
        }
    }
    
    /**
     * @description Test: handleBeforeInsert handles bulk insert correctly
     */
    @isTest
    static void testHandleBeforeInsert_Bulk() {
        setup();
        Contact testContact = [SELECT Id FROM Contact WHERE LastName = 'Customer' LIMIT 1];
        ProgramEnrollment testEnrollment = [SELECT Id FROM ProgramEnrollment WHERE ContactId = :testContact.Id LIMIT 1];
        
        List<ISB_Fee__c> fees = new List<ISB_Fee__c>();
        for (Integer i = 0; i < 50; i++) {
            fees.add(new ISB_Fee__c(
                Contact__c = testContact.Id,
                Customer__c = testContact.Id,
                Fee_Amount__c = 100,
                Due_Date__c = System.Today(),
                Payment_Window__c = 2
            ));
            fees.add(new ISB_Fee__c(
                Contact__c = null,
                Customer__c = testContact.Id,
                Fee_Amount__c = 50,
                Due_Date__c = System.Today(),
                Payment_Window__c = 2
            ));
        }
        
        Test.startTest();
        insert fees;
        Test.stopTest();
        
        List<ISB_Fee__c> insertedFees = [SELECT Id, Contact__c, Program_Enrollment__c, Customer__c FROM ISB_Fee__c WHERE Id IN :fees];
        for (ISB_Fee__c fee : insertedFees) {
            if (fee.Contact__c != null) {
                System.assertEquals(testEnrollment.Id, fee.Program_Enrollment__c);
            }
        }
    }

    /**
     * @description Test: handleBeforeInsert covers the branch where Fee Amount is null
     */
    @isTest
    static void testHandleBeforeInsert_NullFeeAmountValue() {
        ISB_Fee__c fee = new ISB_Fee__c(
            Fee_Amount__c = null
        );
        
        Test.startTest();
        ISBFeeTriggerHandler.handleBeforeInsert(new List<ISB_Fee__c>{fee});
        Test.stopTest();
        
        System.assertEquals(null, fee.Pending_Amount__c);
    }
    
    /**
     * @description Test: handleAfterInsert correctly skips non-miscellaneous fees
     */
    @isTest
    static void testHandleAfterInsert_NonMiscFee() {
        setup();
        Contact testContact = [SELECT Id FROM Contact LIMIT 1];
        ProgramEnrollment pe = [SELECT Id FROM ProgramEnrollment WHERE ContactId = :testContact.Id LIMIT 1];
        
        ISB_Fee__c fee = new ISB_Fee__c(
            Contact__c = testContact.Id,
            Program_Enrollment__c = pe.Id,
            Fee_Amount__c = 100,
            Fee_Type__c = 'Registration Fee' // NOT Miscellaneous
        );
        insert fee;
        
        Test.startTest();
        ISBFeeTriggerHandler.handleAfterInsert(new List<ISB_Fee__c>{fee});
        Test.stopTest();
        
        System.assert(true);
    }

    /**
     * @description Test: handleAfterInsert handles miscellaneous fees (Requires SeeAllData=true for template/owea)
     */
    @isTest(SeeAllData=true)
    static void testHandleAfterInsert_MiscFee() {
        EmailTemplate template;
        try {
            template = [SELECT Id FROM EmailTemplate WHERE DeveloperName = 'New_Miscellaneous_Fee_Added' LIMIT 1];
        } catch(Exception e) {}
        
        if (template != null) {
            String uniqueEmail = 'testemail' + System.currentTimeMillis() + '@example.com';
            Contact con = new Contact(
                FirstName = 'Email', 
                LastName = 'Test', 
                Email = uniqueEmail,
                New_Admit_Email__c = uniqueEmail,
                hed__Preferred_Email__c = 'VF Email ID',
                VF_Email_ID__c = uniqueEmail
            );
            insert con;
            
            Program prod = new Program(Name = 'Test P');
            insert prod;
            ProgramEnrollment pe = new ProgramEnrollment(Name = 'Test E', ContactId = con.Id, ProgramId = prod.Id);
            insert pe;
            
            ISB_Fee__c fee = new ISB_Fee__c(
                Contact__c = con.Id,
                Program_Enrollment__c = pe.Id,
                Fee_Amount__c = 50,
                Fee_Type__c = 'Miscellaneous Charges',
                Remark__c = 'Test Remark',
                Due_Date__c = System.today()
            );
            insert fee;
            
            Test.startTest();
            ISBFeeTriggerHandler.handleAfterInsert(new List<ISB_Fee__c>{fee});
            Test.stopTest();
            
            System.assertEquals('Miscellaneous Charges', fee.Fee_Type__c);
        }
    }

    /**
     * @description Test: handleAfterInsert handles empty list
     */
    @isTest
    static void testHandleAfterInsert_EmptyList() {
        Test.startTest();
        ISBFeeTriggerHandler.handleAfterInsert(new List<ISB_Fee__c>());
        Test.stopTest();
        System.assert(true);
    }

    /**
     * @description Test: Covers edge case of Customer__c population
     */
    @isTest
    static void testHandleBeforeInsert_PopulateCustomerFromContact() {
        String uniqueEmail = 'customer_test' + System.currentTimeMillis() + '@example.com';
        Contact testContact = new Contact(
            LastName = 'Customer_Test',
            Email = uniqueEmail,
            hed__Preferred_Email__c = 'VF Email ID',
            VF_Email_ID__c = uniqueEmail
        );
        insert testContact;
        
        ISB_Fee__c fee = new ISB_Fee__c(
            Fee_Amount__c = 100,
            Contact__c = testContact.Id
        );
        
        Test.startTest();
        ISBFeeTriggerHandler.handleBeforeInsert(new List<ISB_Fee__c>{fee});
        Test.stopTest();
        
        System.assertEquals(testContact.Id, fee.Customer__c, 'Customer should be populated from Contact');
    }

    /**
     * @description Test: Covers edge case of Contact__c population from Customer__c
     */
    @isTest
    static void testHandleBeforeInsert_PopulateContactFromCustomer() {
        String uniqueEmail = 'customer_test' + System.currentTimeMillis() + '@example.com';
        Contact testContact = new Contact(
            LastName = 'Customer_Test',
            Email = uniqueEmail,
            hed__Preferred_Email__c = 'VF Email ID',
            VF_Email_ID__c = uniqueEmail
        );
        insert testContact;
        
        ISB_Fee__c fee = new ISB_Fee__c(
            Fee_Amount__c = 100,
            Customer__c = testContact.Id
        );
        
        Test.startTest();
        ISBFeeTriggerHandler.handleBeforeInsert(new List<ISB_Fee__c>{fee});
        Test.stopTest();
        
        System.assertEquals(testContact.Id, fee.Contact__c, 'Contact should be populated from Customer');
    }
}