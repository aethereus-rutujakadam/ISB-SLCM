/**
 * ORG B
 * Purpose : Processes ISB_Payment__c records
 *           ONLY when First_Installment_Paid__c changes to TRUE → callout to ORG A
 */
public class ISB_PaymentTriggerHelper {

    public static void handlePaymentUpdates(
        List<ISB_Payment__c> newList,
        Map<Id, ISB_Payment__c> oldMap
    ) {
        System.debug('====== ISB_PaymentTriggerHelper START ======');
        System.debug('Total records in trigger: ' + newList.size());
        System.debug('Is Update? ' + (oldMap != null));

        Set<Id> enrollmentIds                       = new Set<Id>();
        Map<Id, ISB_Payment__c> enrollmentToPayment = new Map<Id, ISB_Payment__c>();

        // ── LOOP: Check each payment ──────────────────────────────────────────
        for (ISB_Payment__c payment : newList) {
            ISB_Payment__c oldPayment = (oldMap != null)
                ? oldMap.get(payment.Id)
                : null;

            // ✅ ONLY condition: First_Installment_Paid__c just changed to TRUE
            Boolean isNowPaid  = (payment.First_Installment_Paid__c == true);
            Boolean wasNotPaid = (oldPayment == null
                               || oldPayment.First_Installment_Paid__c != true);
            Boolean hasEnrollment = (payment.Program_Enrollment__c != null);

            System.debug('--- Payment Id: ' + payment.Id);
            System.debug('    First_Installment_Paid__c (new) : ' + payment.First_Installment_Paid__c);
            System.debug('    First_Installment_Paid__c (old) : '
                + (oldPayment != null 
                    ? String.valueOf(oldPayment.First_Installment_Paid__c) 
                    : 'N/A (Insert)'));
            System.debug('    Program_Enrollment__c           : ' + payment.Program_Enrollment__c);
            System.debug('    isNowPaid     : ' + isNowPaid);
            System.debug('    wasNotPaid    : ' + wasNotPaid);
            System.debug('    hasEnrollment : ' + hasEnrollment);

            if (isNowPaid && wasNotPaid && hasEnrollment) {
                System.debug('    ✅ ELIGIBLE — First_Installment_Paid__c changed to TRUE');
                System.debug('    ✅ Adding Enrollment Id: ' + payment.Program_Enrollment__c);
                enrollmentIds.add(payment.Program_Enrollment__c);
                enrollmentToPayment.put(payment.Program_Enrollment__c, payment);
            } else {
                System.debug('    ⏭ SKIPPED - Reason: '
                    + (!isNowPaid      ? 'First_Installment_Paid__c is not TRUE. ' : '')
                    + (!wasNotPaid     ? 'First_Installment_Paid__c was already TRUE before. ' : '')
                    + (!hasEnrollment  ? 'No Program_Enrollment__c linked. ' : '')
                );
            }
        }

        System.debug('Total eligible Enrollment Ids: ' + enrollmentIds.size());

        if (enrollmentIds.isEmpty()) {
            System.debug('⏹ No eligible payments found. Exiting.');
            System.debug('====== ISB_PaymentTriggerHelper END ======');
            return;
        }

        // ── QUERY: Program Enrollments ────────────────────────────────────────
        System.debug('Querying ProgramEnrollment for Ids: ' + enrollmentIds);

        List<ProgramEnrollment> enrollments = [
            SELECT Id,
                   ISB_External_Id__c,Status,
                   Sub_Status__c,
                   Sub_Sub_Status__c
            FROM   ProgramEnrollment
            WHERE  Id IN :enrollmentIds
            AND    ISB_External_Id__c != null
        ];

        System.debug('ProgramEnrollment records found with ISB_External_Id__c: '
            + enrollments.size());

        if (enrollments.isEmpty()) {
            System.debug('⚠️ WARNING: No ProgramEnrollment found with ISB_External_Id__c populated.');
            System.debug('====== ISB_PaymentTriggerHelper END ======');
            return;
        }
        
        List<ProgramEnrollment> enrollmentsToUpdate = new List<ProgramEnrollment>();
        
        for (ProgramEnrollment enrollment : enrollments) {
            System.debug('--- Updating Program Enrollment Id: ' + enrollment.Id);
            System.debug('    Old Status         : ' + enrollment.Status);
            System.debug('    Old Sub Status     : ' + enrollment.Sub_Status__c);
            System.debug('    Old Sub Sub Status : ' + enrollment.Sub_Sub_Status__c);
            
            enrollment.Status         = 'Registered';
            enrollment.Sub_Status__c     = 'Current Student';
            enrollment.Sub_Sub_Status__c = 'Current Student';
            
            System.debug('    New Status         : ' + enrollment.Status);
            System.debug('    New Sub Status     : ' + enrollment.Sub_Status__c);
            System.debug('    New Sub Sub Status : ' + enrollment.Sub_Sub_Status__c);
            
            enrollmentsToUpdate.add(enrollment);
        }
 
        if (!enrollmentsToUpdate.isEmpty()) {
            System.debug('Updating ' + enrollmentsToUpdate.size() 
                + ' ProgramEnrollment records...');
            
            try {
                update enrollmentsToUpdate;
                System.debug('✅ ProgramEnrollment status updates completed successfully.');
            } catch (DmlException e) {
                System.debug('❌ ERROR updating ProgramEnrollments: ' + e.getMessage());
                System.debug('Stack Trace: ' + e.getStackTraceString());
                // Re-throw to fail the transaction if update fails
                throw e;
            }
        }

        // ── LOOP: Enqueue callout per enrollment ──────────────────────────────
        for (ProgramEnrollment enrollment : enrollments) {
            ISB_Payment__c payment = enrollmentToPayment.get(enrollment.Id);

            System.debug('--- Processing Enrollment Id         : ' + enrollment.Id);
            System.debug('    ISB_External_Id__c (ORG A App Id): ' 
                + enrollment.ISB_External_Id__c);

            if (payment == null) {
                System.debug('    ⚠️ WARNING: No matching payment in map for Enrollment: '
                    + enrollment.Id + '. Skipping.');
                continue;
            }

            System.debug('    Linked Payment Id : ' + payment.Id);
            System.debug('    🚀 Enqueuing ISB_OrgACalloutQueueable...');

            System.enqueueJob(
                new ISB_OrgACalloutQueueable(
                    enrollment.ISB_External_Id__c,  // ORG A Application Id
                    payment.Id,                      // ORG B Payment Id (idempotency)
                    null,                            // orgBInstallmentId
                    true,                            // firstInstallmentPaid
                    null,                            // paidAmount
                    null,                            // currencyIsoCode
                    null,                            // paidOn
                    'SUCCESS',                       // paymentStatus
                    null                             // paymentMode
                )
            );

            System.debug('    ✅ Queueable job enqueued for ORG A App Id: '
                + enrollment.ISB_External_Id__c);
        }

        System.debug('====== ISB_PaymentTriggerHelper END ======');
    }
}