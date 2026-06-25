public class ISBStudentFeeBreakageTriggerHandler {
    
    public static void handleBeforeInsert(List<ISB_Student_Fee_Breakage__c> newBreakages) {
        
        System.debug('=== ISBStudentFeeBreakageTriggerHandler.handleBeforeInsert ===');
        System.debug('Processing ' + newBreakages.size() + ' breakage records');
        
        for (ISB_Student_Fee_Breakage__c breakage : newBreakages) {
            
            // Initialize Paid Amount to 0 if null
            if (breakage.Paid_Amount__c == null) {
                breakage.Paid_Amount__c = 0;
            }
            
            // Set Pending Amount = Total Amount if not already set
            if (breakage.Pending_Amount__c == null || breakage.Pending_Amount__c == 0) {
                
                // Check if Total_Amount__c exists and has value
                if (breakage.Total_Amount__c != null && breakage.Total_Amount__c > 0) {
                    breakage.Pending_Amount__c = breakage.Total_Amount__c;
                    System.debug('✅ Set Pending_Amount__c = Total_Amount__c (' + breakage.Total_Amount__c + ') for ' + breakage.Fee_Type__c);
                }
            }
        }
        
        System.debug('=== END handleBeforeInsert ===');
    }
    
    public static void updateScholarshipOnInstallment(List<ISB_Student_Fee_Breakage__c> breakages) {
        
        System.debug('=== updateScholarshipOnInstallment START ===');
        
        Map<Id, Decimal> installmentToScholarshipMap = new Map<Id, Decimal>();
        
        // Collect scholarship per installment
        for (ISB_Student_Fee_Breakage__c br : breakages) {
            if (br.ISB_Installment__c != null && br.Scholarship_Amount__c != null && br.Fee_Type__c == 'Tuition Fee') {
                
                if (!installmentToScholarshipMap.containsKey(br.ISB_Installment__c)) {
                    installmentToScholarshipMap.put(br.ISB_Installment__c, 0);
                }
                
                installmentToScholarshipMap.put(
                    br.ISB_Installment__c,
                    installmentToScholarshipMap.get(br.ISB_Installment__c) + br.Scholarship_Amount__c
                );
            }
        }
        
        if (installmentToScholarshipMap.isEmpty()) {
            return;
        }
        
        // Fetch existing installments
        List<ISB_Installment__c> installmentsToUpdate = [
            SELECT Id, Scholarship_Amount__c, Total_Amount__c, Paid_Amount__c,Total_Amount_calc__c,Pending_Amount__c
            FROM ISB_Installment__c
            WHERE Id IN :installmentToScholarshipMap.keySet()
        ];
        
        for (ISB_Installment__c inst : installmentsToUpdate) {
            inst.Scholarship_Amount__c = installmentToScholarshipMap.get(inst.Id);
             
            //Decimal Total_Amount_calc  = inst.Total_Amount_calc__c  != null ? inst.Total_Amount_calc__c  : 0;
            //Decimal paidAmount = inst.Paid_Amount__c != null ? inst.Paid_Amount__c : 0;
            //Decimal scholarshipAmount = inst.Scholarship_Amount__c != null ? inst.Scholarship_Amount__c : 0;
            
           // inst.Pending_Amount__c = Total_Amount_calc - paidAmount - scholarshipAmount; 
                 //   System.Debug('inst.Pending_Amount__c '+ inst.Pending_Amount__c);
        }
        if (!installmentsToUpdate.isEmpty()) {
            update installmentsToUpdate;
            System.debug('✅ Updated Installments with Scholarship');
        }
        
        System.debug('=== updateScholarshipOnInstallment END ===');
    }
}