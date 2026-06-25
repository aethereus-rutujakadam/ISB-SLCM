public with sharing class InstallmentController {
    
    // Wrapper class to include hasInitiatedPayment flag
    public class InstallmentWrapper {
        @AuraEnabled public ISB_Installment__c installment;
        @AuraEnabled public Boolean hasInitiatedPayment;
        
        public InstallmentWrapper(ISB_Installment__c inst, Boolean hasInitiated) {
            this.installment = inst;
            this.hasInitiatedPayment = hasInitiated;
        }
    }
    
    /**
     * Get installments for the logged-in Experience Cloud user's related Contact
     * @return List of InstallmentWrapper records
     */
    @AuraEnabled(cacheable=true)
    public static List<InstallmentWrapper> getInstallments() {
        try {
            Id currentUserId = UserInfo.getUserId();
            
            List<User> users = [
                SELECT ContactId 
                FROM User 
                WHERE Id = :currentUserId 
                AND ContactId != null
                LIMIT 1
            ];
            
            if (users.isEmpty() || users[0].ContactId == null) {
                System.debug('No Contact found for current user');
                return new List<InstallmentWrapper>();
            }
            
            Id contactId = users[0].ContactId;
            System.debug('Contact ID: ' + contactId);
            
            List<ISB_Installment__c> installments = [
                SELECT Id,
                       Name,
                       Installment_Number__c,
                       Due_Date__c,
                       Actual_Amount__c,
                       Total_Amount_calc__c,
                       Program__c,
                       Program__r.Name,
                       Program_Enrollment__c,
                       Pending_Amount__c,
                       Paid_Amount__c,  // ✅ Added this field
                       Contact__c,
                       (SELECT Id 
                        FROM ISB_Payments__r 
                        WHERE Initiated__c = 'Success' 
                        ORDER BY CreatedDate DESC 
                        LIMIT 1)
                FROM ISB_Installment__c
                WHERE Contact__c = :contactId
                ORDER BY Installment_Number__c ASC NULLS LAST
            ];
            
            // Get all installment IDs
            Set<Id> installmentIds = new Set<Id>();
            for (ISB_Installment__c inst : installments) {
                installmentIds.add(inst.Id);
            }
            
            // Check which installments have payments with "Initiated" status
            Map<Id, Boolean> hasInitiatedMap = new Map<Id, Boolean>();
            
            for (ISB_Payment__c payment : [
                SELECT ISB_Installment__c
                FROM ISB_Payment__c
                WHERE ISB_Installment__c IN :installmentIds
                AND Initiated__c = 'Initiated'
                LIMIT 1000
            ]) {
                hasInitiatedMap.put(payment.ISB_Installment__c, true);
            }
            
            // Create wrapper objects
            List<InstallmentWrapper> wrappers = new List<InstallmentWrapper>();
            for (ISB_Installment__c inst : installments) {
                Boolean hasInitiated = hasInitiatedMap.containsKey(inst.Id);
                wrappers.add(new InstallmentWrapper(inst, hasInitiated));
            }
            
            System.debug('Installments found: ' + wrappers.size());
            return wrappers;
            
        } catch (Exception e) {
            System.debug('Error in getInstallments: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            throw new AuraHandledException('Error retrieving installments: ' + e.getMessage());
        }
    }
    
    /**
     * Get current user's Contact information for debugging/verification
     * @return Map with user and contact details
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, String> getCurrentUserContactInfo() {
        try {
            Id currentUserId = UserInfo.getUserId();
            
            List<User> users = [
                SELECT Id, ContactId, Contact.Name, Contact.Email, Name, Email
                FROM User 
                WHERE Id = :currentUserId
                LIMIT 1
            ];
            
            Map<String, String> userInfo = new Map<String, String>();
            
            if (!users.isEmpty()) {
                User currentUser = users[0];
                userInfo.put('userId', currentUser.Id);
                userInfo.put('userName', currentUser.Name);
                userInfo.put('userEmail', currentUser.Email);
                userInfo.put('contactId', currentUser.ContactId);
                
                if (currentUser.Contact != null) {
                    userInfo.put('contactName', currentUser.Contact.Name);
                    userInfo.put('contactEmail', currentUser.Contact.Email);
                }
            }
            
            return userInfo;
            
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving user info: ' + e.getMessage());
        }
    }
}