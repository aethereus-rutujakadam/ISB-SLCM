public class ISBWaiverHandler {

   /* public static void applyWaiverToInstallments(List<ISBWaiverApplications__c> waiverList) {

        Map<Id, Decimal> waiverMap = new Map<Id, Decimal>();

        for (ISBWaiverApplications__c w : waiverList) {
            if (w.Program_Enrollment__c != null && w.ScholarshipAmount__c != null && w.ScholarshipAmount__c > 0) {
                waiverMap.put(w.Program_Enrollment__c, w.ScholarshipAmount__c);
            }
        }

        if (waiverMap.isEmpty()) {
            return;
        }

        List<ISB_Installment__c> instList = [
            SELECT Id,
                   Program_Enrollment__c,
                   Installment_Number__c,
                   Actual_Amount__c,
                   Pending_Amount__c
            FROM ISB_Installment__c
            WHERE Program_Enrollment__c IN :waiverMap.keySet()
        ];

        Map<Id, List<ISB_Installment__c>> peToInstMap = new Map<Id, List<ISB_Installment__c>>();

        for (ISB_Installment__c inst : instList) {
            if (!peToInstMap.containsKey(inst.Program_Enrollment__c)) {
                peToInstMap.put(inst.Program_Enrollment__c, new List<ISB_Installment__c>());
            }
            peToInstMap.get(inst.Program_Enrollment__c).add(inst);
        }

        List<ISB_Student_Fee_Breakage__c> breakageToInsert = new List<ISB_Student_Fee_Breakage__c>();
        Map<Id, Decimal> installmentToDeductionMap = new Map<Id, Decimal>();

        for (Id peId : waiverMap.keySet()) {

            Decimal waiverAmount = waiverMap.get(peId);
            if (waiverAmount <= 0) continue;

            List<ISB_Installment__c> installments = peToInstMap.get(peId);
            if (installments == null || installments.isEmpty()) continue;

            // Find highest installment number
            Decimal maxInstNo = 0;
            for (ISB_Installment__c inst : installments) {
                if (inst.Installment_Number__c != null && inst.Installment_Number__c > maxInstNo) {
                    maxInstNo = inst.Installment_Number__c;
                }
            }

            // Deduct from last installment backward
            for (Decimal instNo = maxInstNo; instNo >= 1 && waiverAmount > 0; instNo--) {

                for (ISB_Installment__c inst : installments) {

                    if (inst.Installment_Number__c == instNo) {

                        Decimal instAmt = inst.Actual_Amount__c != null ? inst.Actual_Amount__c : 0;
                        if (instAmt <= 0) continue;

                        Decimal deduct = Math.min(instAmt, waiverAmount);

                        // Create Scholarship Breakage
                        breakageToInsert.add(new ISB_Student_Fee_Breakage__c(
                            ISB_Installment__c = inst.Id,
                            Fee_Type__c = 'Scholarship',
                            Amount__c = -deduct
                        ));

                        // Track deduction per installment
                        Decimal existingDeduction =
                            installmentToDeductionMap.containsKey(inst.Id)
                            ? installmentToDeductionMap.get(inst.Id)
                            : 0;

                        installmentToDeductionMap.put(inst.Id, existingDeduction + deduct);

                        waiverAmount -= deduct;
                        break;
                    }
                }
            }
        }

        if (!breakageToInsert.isEmpty()) {
            insert breakageToInsert;
        }

        if (!installmentToDeductionMap.isEmpty()) {

            List<ISB_Installment__c> installmentsToUpdate = [
                SELECT Id, Pending_Amount__c
                FROM ISB_Installment__c
                WHERE Id IN :installmentToDeductionMap.keySet()
            ];

            for (ISB_Installment__c inst : installmentsToUpdate) {
                Decimal deductAmt = installmentToDeductionMap.get(inst.Id);
                Decimal currentPending = inst.Pending_Amount__c != null ? inst.Pending_Amount__c : 0;

                // Prevent negative pending amount
                inst.Pending_Amount__c = Math.max(0, currentPending - deductAmt);
            }

            update installmentsToUpdate;
        }
    }*/
}