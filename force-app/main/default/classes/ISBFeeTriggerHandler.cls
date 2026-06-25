public class ISBFeeTriggerHandler {
    
    public static void handleBeforeInsert(List<ISB_Fee__c> newISBFees) {
        
        // Set to store unique Contact IDs
        Set<Id> contactIds = new Set<Id>();
        
        for (ISB_Fee__c fee : newISBFees) {
            
            // Set Pending Amount = Fee Amount
            if (fee.Fee_Type__c!='AdmissionFee' && fee.Fee_Type__c!='ApplicationFee' && fee.Fee_Type__c!='CommitmentFee' ){
            if (fee.Fee_Amount__c != null) {
                fee.Pending_Amount__c = fee.Fee_Amount__c;
                fee.Total_amount__c = fee.Fee_Amount__c;
            }
            
            // Paid Amount default
            fee.Paid_Amount__c = 0;
            fee.Fee_Status__c = 'Not Paid';
            
            // If Contact is populated from UI
            if (fee.Contact__c != null) {
                
                // Populate Customer automatically
                fee.Customer__c = fee.Contact__c;
                
                contactIds.add(fee.Contact__c);
            }
            
             if (fee.Customer__c != null) {
                
                fee.Contact__c = fee.Customer__c;
                
                contactIds.add(fee.Customer__c);
            }
            }else{
                fee.Paid_Amount__c = fee.Fee_Amount__c;
                fee.Fee_Status__c = 'Paid';
            }
        }
        
        if (contactIds.isEmpty()) {
            return;
        }
        
        Map<Id, Id> contactToEnrollmentMap = new Map<Id, Id>();
        
        for (ProgramEnrollment enrollment : [
            SELECT Id, ContactId
            FROM ProgramEnrollment
            WHERE ContactId IN :contactIds
            ORDER BY CreatedDate DESC
        ]) {
            if (!contactToEnrollmentMap.containsKey(enrollment.ContactId)) {
                contactToEnrollmentMap.put(enrollment.ContactId, enrollment.Id);
            }
        }
        
        for (ISB_Fee__c fee : newISBFees) {
            if (fee.Contact__c != null &&
                contactToEnrollmentMap.containsKey(fee.Contact__c)) {
                    
                    fee.Program_Enrollment__c =
                        contactToEnrollmentMap.get(fee.Contact__c);
                }
        }
    }
    
    
    public static void handleAfterInsert(List<ISB_Fee__c> newFees){
        
        Set<Id> contactIds = new Set<Id>();
        List<ISB_Fee__c> miscFees = new List<ISB_Fee__c>();
        
        // Step 1: Filter Records
        for(ISB_Fee__c fee : newFees){
            if(isMiscFee(fee) && fee.Contact__c != null){
                contactIds.add(fee.Contact__c);
                miscFees.add(fee);
            }
        }
        System.debug('miscFees '+ miscFees);
        if(miscFees.isEmpty()){
            return;
        }
        
        // Step 2: Get Contacts
        Map<Id, Contact> contactMap = new Map<Id, Contact>(
            [SELECT Id, Email, New_Admit_Email__c FROM Contact WHERE Id IN :contactIds]
        );
        
        // Step 3: Get Email Template
        EmailTemplate template = [
            SELECT Id 
            FROM EmailTemplate 
            WHERE DeveloperName = 'New_Miscellaneous_Fee_Added'
            LIMIT 1
        ];
                System.debug('template '+ template);

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        OrgWideEmailAddress owea = [
            SELECT Id,DisplayName  
            FROM OrgWideEmailAddress 
            WHERE DisplayName  = 'ISB Support'
            LIMIT 1
        ];
                     System.debug('owea '+ owea);
   
        // Step 4: Prepare Emails
        for(ISB_Fee__c fee : miscFees){
            
            Contact con = contactMap.get(fee.Contact__c);
            
            if(con != null && String.isNotBlank(con.New_Admit_Email__c)){
                
                Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                
                mail.setTargetObjectId(con.Id); // WhoId (Contact)
                mail.setTreatTargetObjectAsRecipient(false);
                mail.setToAddresses(new List<String>{con.New_Admit_Email__c});
                mail.setWhatId(fee.Id);         // Related record
                
                mail.setTemplateId(template.Id);
                mail.setSaveAsActivity(true);
                mail.setOrgWideEmailAddressId(owea.Id);
                
                emails.add(mail);
            }
        }
        
        // Step 5: Send Emails
        if(!emails.isEmpty()){
            Messaging.sendEmail(emails);
                            System.debug('Email sent ');

        }
    }
    
    
    // 🔹 Utility Method
    private static Boolean isMiscFee(ISB_Fee__c fee){
        return fee.Fee_Type__c == 'Miscellaneous Charges';
    }
}