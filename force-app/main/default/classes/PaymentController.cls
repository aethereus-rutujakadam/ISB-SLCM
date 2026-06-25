public without sharing class PaymentController {
    
    @AuraEnabled(cacheable=true)
    public static List<ISB_Payment__c> getPayments() {
        try {
            Id userId = UserInfo.getUserId();
            System.debug('🔍 Current User Id: ' + userId);
            
            User u = [
                SELECT Id, ContactId
                FROM User
                WHERE Id = :userId
                LIMIT 1
            ];
            System.debug('🔍 User ContactId: ' + u.ContactId);
            
            if (u.ContactId == null) {
                System.debug('❌ No Contact linked to portal user');
                return new List<ISB_Payment__c>();
            }
            
            return getPaymentsByContactId(u.ContactId);
            
        } catch (Exception e) {
            System.debug('❌ Error in getPayments: ' + e.getMessage());
            throw new AuraHandledException('Error fetching payments: ' + e.getMessage());
        }
    }
    
    /**
* Get payments for a specific Contact — used for guest user context where UserInfo
* does not resolve to a Contact. The contactId is validated by the OTP flow.
* @param contactId - Salesforce Contact Id resolved from the guest's email
* @return List of ISB_Payment__c records
*/
    @AuraEnabled(cacheable=true)
    public static List<ISB_Payment__c> getPaymentsForContact(Id contactId) {
        try {
            if (contactId == null) {
                return new List<ISB_Payment__c>();
            }
            return getPaymentsByContactId(contactId);
        } catch (Exception e) {
            System.debug('❌ Error in getPaymentsForContact: ' + e.getMessage());
            throw new AuraHandledException('Error fetching payments for contact: ' + e.getMessage());
        }
    }
    
    /**
* Shared query logic for both getPayments() and getPaymentsForContact()
*/
    private static List<ISB_Payment__c> getPaymentsByContactId(Id contactId) {
        List<ISB_Payment__c> payments = [
            SELECT Id,
            Name,
            Amount__c,
            Amount_Paid__c,
            Initiated__c,
            Payment_Mode__c,
            Payment_Type__c,
            CreatedDate,
            ISB_Installment__c,
            ISB_Installment__r.Name,
            Customer__c,
            Case__c,
            Case__r.Comments__c,
            SAP_Payment_Collected__c
            FROM ISB_Payment__c
            WHERE Customer__c = :contactId AND Program_Enrollment__r.IsActive = TRUE
            ORDER BY CreatedDate DESC
        ];
        
        System.debug('✅ Payments found count: ' + payments.size());
        System.debug('✅ Payments data: ' + payments);
        
        return payments;
    }

    /**
     * Get a single payment by ID with all related details
     * @param paymentId - The ISB_Payment__c record ID
     * @return Single ISB_Payment__c record with related data
     */
    @AuraEnabled(cacheable=true)
    public static ISB_Payment__c getPaymentById(Id paymentId) {
        try {
            if (paymentId == null) {
                throw new AuraHandledException('Payment ID is required');
            }

            System.debug('💳 Fetching payment details for ID: ' + paymentId);

            ISB_Payment__c payment = [
                SELECT Id,
                    Name,
                    Amount__c,
                    Amount_Paid__c,
                    Payment_Type__c,
                    Payment_Method__c,
                    Payment_Mode__c,
                    Payment_Mode_Type__c,
                    mode_of_payment__c,
                    Initiated__c,
                    CreatedDate,
                    Payment_Date__c,
                    Transaction_Date__c,
                    Payment_ID__c,
                    Payment_Order_Id__c,
                    Payment_Signature__c,
                    Error_Code__c,
                    Error_Message__c,
                    Bank_Name__c,
                    Cheque_DD_Number__c,
                    RTGS_NEFT_Number__c,
                    Company_Name__c,
                    Cheque_No__c,
                    Case__c,
                    Case__r.Comments__c,
                    ISB_Installment__c,
                    ISB_Fees__c,
                    Customer__c,
                    Program_Enrollment__c
                FROM ISB_Payment__c
                WHERE Id = :paymentId
                LIMIT 1
            ];

            System.debug('✅ Payment found: ' + payment.Name);
            return payment;

        } catch (QueryException e) {
            System.debug('❌ Payment not found: ' + e.getMessage());
            throw new AuraHandledException('Payment not found');
        } catch (Exception e) {
            System.debug('❌ Error fetching payment: ' + e.getMessage());
            throw new AuraHandledException('Error fetching payment: ' + e.getMessage());
        }
    }
}