public without sharing class FeeController {
    
    // Wrapper class to include hasInitiatedPayment flag
    public class FeeWrapper {
        @AuraEnabled public ISB_Fee__c fee;
        @AuraEnabled public Boolean hasInitiatedPayment;
        
        public FeeWrapper(ISB_Fee__c f, Boolean hasInitiated) {
            this.fee = f;
            this.hasInitiatedPayment = hasInitiated;
        }
    }
    
    /**
     * Get fees for the logged-in Experience Cloud user's related Contact
     * @return List of FeeWrapper records
     */
    @AuraEnabled(cacheable=true)
    public static List<FeeWrapper> getFees() {
        try {
            Id currentUserId = UserInfo.getUserId();
            
            List<User> users = [
                SELECT ContactId 
                FROM User 
                WHERE Id = :currentUserId 
                AND ContactId != null
                LIMIT 1
            ];
            
            if (users.isEmpty()) {
                return new List<FeeWrapper>();
            }
            
            Id contactId = users[0].ContactId;
            return getFeesByContactId(contactId);
            
        } catch (Exception e) {
            System.debug('❌ Error in getFees: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            throw new AuraHandledException('Error retrieving fees: ' + e.getMessage());
        }
    }

    /**
     * Get fees for a specific Contact — used for guest user context where UserInfo
     * does not resolve to a Contact. The contactId is validated by the OTP flow.
     * @param contactId - Salesforce Contact Id resolved from the guest's email
     * @return List of FeeWrapper records
     */
    @AuraEnabled(cacheable=true)
    public static List<FeeWrapper> getFeesForContact(Id contactId) {
        try {
            if (contactId == null) {
                return new List<FeeWrapper>();
            }
            return getFeesByContactId(contactId);
        } catch (Exception e) {
            System.debug('❌ Error in getFeesForContact: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            throw new AuraHandledException('Error retrieving fees for contact: ' + e.getMessage());
        }
    }

    /**
     * Shared query logic for both getFees() and getFeesForContact()
     */
    private static List<FeeWrapper> getFeesByContactId(Id contactId) {
        // Query ISB_Fee__c records
        List<ISB_Fee__c> fees = [
            SELECT Id,
                   Name,
                   Installment_Number__c,
                   Fee_Type__c,
                   Due_Date__c,
                   Extended_Due_Date__c,
                   Total_amount__c,
                   Pending_Amount__c,
                   Paid_Amount__c,
                   Fee_Status__c,
                   Contact__c,
                   Customer__c,
                   Customer__r.Name,
                   Remark__c,
                   ISB_Installment__c,
                   ISB_Installment__r.Installment_Number__c,
                   ISB_Installment__r.Program_Enrollment__c,
                   ISB_Installment__r.Program_Enrollment__r.Academic_Term__c,
                   ISB_Installment__r.Program_Enrollment__r.Academic_Term__r.Name,
                   Fee_Amount__c,Payment_Window__c,
                   Is_Active__c,
                   (SELECT Id 
                    FROM ISB_Payments__r 
                    WHERE Initiated__c = 'Success' 
                    ORDER BY CreatedDate DESC 
                    LIMIT 1)
            FROM ISB_Fee__c
            WHERE Contact__c = :contactId 
            AND Program_Enrollment__r.IsActive = TRUE
            AND Is_Active__c = TRUE
            ORDER BY ISB_Installment__r.Installment_Number__c ASC NULLS LAST
        ];
        
        // Get all fee IDs
        Set<Id> feeIds = new Set<Id>();
        for (ISB_Fee__c f : fees) {
            feeIds.add(f.Id);
        }
        
        // Check which fees have payments with "Initiated" status
        Map<Id, Boolean> hasInitiatedMap = new Map<Id, Boolean>();
        
        for (ISB_Payment__c payment : [
            SELECT ISB_Fees__c
            FROM ISB_Payment__c
            WHERE ISB_Fees__c IN :feeIds
            AND Initiated__c = 'Initiated'
            LIMIT 1000
        ]) {
            hasInitiatedMap.put(payment.ISB_Fees__c, true);
        }
        
        // Create wrapper objects
        List<FeeWrapper> wrappers = new List<FeeWrapper>();
        for (ISB_Fee__c f : fees) {
            Boolean hasInitiated = hasInitiatedMap.containsKey(f.Id);
            wrappers.add(new FeeWrapper(f, hasInitiated));
        }
        
        return wrappers;
    }
}