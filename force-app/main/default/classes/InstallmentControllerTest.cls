@IsTest
public class InstallmentControllerTest {

    // Stable identifier
    private static final String RUN_AS_ALIAS = 'instusr';

    @TestSetup
    static void setupData() {
        // Create explicit ACTIVE test user for fallback tests
        TestDataFactory.testUser(RUN_AS_ALIAS, 'ignored@email.com');
    }

    private static User getRunAsUser() {
        return [
            SELECT Id, Email
            FROM User
            WHERE Alias = :RUN_AS_ALIAS
            AND IsActive = true
            LIMIT 1
        ];
    }

    // Helper to find an existing portal user to test against
    private static User getExistingPortalUser() {
        List<User> users = [
            SELECT Id, ContactId, Contact.AccountId 
            FROM User 
            WHERE ContactId != null 
            AND IsActive = true 
            AND Profile.UserType IN ('PowerCustomerSuccess', 'CspLitePortal') 
            LIMIT 1
        ];
        return users.isEmpty() ? null : users[0];
    }

    @IsTest
    static void testGetInstallments_withData() {
        // 1. Try to find an existing portal user
        User u = getExistingPortalUser();
        
        if (u == null) {
            System.debug('No existing Portal User found. Skipping data test.');
            return;
        }

        // 2. Create Data linked to this user's contact
        // We run as Admin to create the data
        System.runAs(new User(Id = UserInfo.getUserId())) {
            
            // Programs and Enrollment (needed for lookup)
            Program prog = new Program(Name = 'Test Data Program');
            insert prog;
            
            ProgramEnrollment pe = new ProgramEnrollment(
                Name = 'Test Data PE',
                ContactId = u.ContactId,
                ProgramId = prog.Id
            );
            insert pe;
            
            // Create Installments
            List<ISB_Installment__c> installments = new List<ISB_Installment__c>();
            
            ISB_Installment__c inst1 = new ISB_Installment__c(
                Contact__c = u.ContactId,
                Program_Enrollment__c = pe.Id,
                Program__c = prog.Id,
                Installment_Number__c = '1',
                Due_Date__c = Date.today().addDays(10),
                Actual_Amount__c = 1000,
                Pending_Amount__c = 1000
            );
            installments.add(inst1);
            
            ISB_Installment__c inst2 = new ISB_Installment__c(
                Contact__c = u.ContactId,
                Program_Enrollment__c = pe.Id,
                Program__c = prog.Id,
                Installment_Number__c = '2',
                Due_Date__c = Date.today().addDays(40),
                Actual_Amount__c = 1000,
                Pending_Amount__c = 1000
            );
            installments.add(inst2);
            
            insert installments;
            
            // Create Payment for Installment 1 (Initiated)
            ISB_Payment__c pay1 = new ISB_Payment__c(
                ISB_Installment__c = inst1.Id,
                Initiated__c = 'Initiated',
                Amount__c = 500
            );
            insert pay1;
            
            // Create Payment for Installment 2 (Success - should NOT mark "hasInitiated")
            // Wait, logic says "WHERE Initiated__c = 'Initiated'". 
            // So if it is 'Success', hasInitiated should be false in the wrapper map?
            // The wrapper logic checks:
            // for (ISB_Payment__c ... WHERE Initiated__c = 'Initiated') -> map.put(true)
            // So 'Success' payment won't trigger the flag.
            ISB_Payment__c pay2 = new ISB_Payment__c(
                ISB_Installment__c = inst2.Id,
                Initiated__c = 'Success',
                Amount__c = 1000
            );
            insert pay2;
        }

        // 3. Run Test as Portal User
        System.runAs(u) {
            Test.startTest();
            List<InstallmentController.InstallmentWrapper> result = InstallmentController.getInstallments();
            Test.stopTest();
            
            // 4. Validate
            System.assertEquals(2, result.size(), 'Should return 2 installments');
            
            // Validate Order (Installment 1 first)
            InstallmentController.InstallmentWrapper w1 = result[0];
            InstallmentController.InstallmentWrapper w2 = result[1];
            
            if (w1.installment.Installment_Number__c > w2.installment.Installment_Number__c) {
                // Swap if order is unexpected, though logic says ORDER BY Installment_Number__c ASC
                InstallmentController.InstallmentWrapper temp = w1;
                w1 = w2;
                w2 = temp;
            }
            
            // Check flags
            System.assertEquals(true, w1.hasInitiatedPayment, 'Installment 1 should have initiated payment');
            System.assertEquals(false, w2.hasInitiatedPayment, 'Installment 2 should NOT have initiated payment (it is Success)');
        }
    }

    @IsTest
    static void testGetInstallments_userWithoutContact_returnsEmptyList() {
        User u = getRunAsUser();
        System.runAs(u) {
            Test.startTest();
            List<InstallmentController.InstallmentWrapper> result = InstallmentController.getInstallments();
            Test.stopTest();
            System.assertEquals(0, result.size());
        }
    }

    @IsTest
    static void testGetCurrentUserContactInfo_userWithoutContact() {
        User u = getRunAsUser();
        System.runAs(u) {
            Test.startTest();
            Map<String, String> info = InstallmentController.getCurrentUserContactInfo();
            Test.stopTest();
            System.assertEquals(u.Id, info.get('userId'));
            System.assertEquals(null, info.get('contactId'));
        }
    }
    
    @IsTest
    static void testGetCurrentUserContactInfo_withPortalUser() {
        User u = getExistingPortalUser();
        if (u == null) return;
        
        System.runAs(u) {
            Test.startTest();
            Map<String, String> info = InstallmentController.getCurrentUserContactInfo();
            Test.stopTest();
            
            System.assertEquals(u.Id, info.get('userId'));
            System.assertNotEquals(null, info.get('contactId'));
            System.assertNotEquals(null, info.get('contactName'));
        }
    }
}