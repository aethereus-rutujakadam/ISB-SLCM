/**
* @description       : CaseTriggerHandler
* @author            : KLS AKASH
* @group             : 
* @last modified on  : 11-18-2025
* @last modified by  : KLS AKASH
**/
public class CaseTriggerHandler {
    private static final Id OFFLINE_PAYMENT_RT_ID =Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName().get('Offline_Payment').getRecordTypeId();
    private static final Id GENERAL_SUPPORT_RT_ID = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName().containsKey('General_Support')
        ? Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName().get('General_Support').getRecordTypeId()
        : null;
    
    public static void handleAfterUpdate(List<Case> newCases, Map<Id, Case> oldMap) {
        System.debug('=== CaseAssignmentHandler.handleAfterUpdate started ===');
        
        validateGraduationReview(newCases, oldMap);
        
        // Identify LOA cases that changed to Closed
        List<Case> closedLOACases = CaseTriggerHelper.filterClosedLOACases(newCases, oldMap);
        
        if (!closedLOACases.isEmpty()) {
            System.debug('Processing ' + closedLOACases.size() + ' closed LOA cases');
            CaseTriggerHelper.processLOACases(closedLOACases);
        }
        
        // Identify Academic Probation cases that changed to Closed
        List<Case> closedProbationCases = CaseTriggerHelper.filterClosedAcademicProbationCases(newCases, oldMap);
        
        if (!closedProbationCases.isEmpty()) {
            System.debug('Processing ' + closedProbationCases.size() + ' closed Academic Probation cases');
            CaseTriggerHelper.sendProbationClearedEmails(closedProbationCases);
        }
        
        /* Sid */
        // Identify Events and Budget cases that just got approved
        List<Case> approvedBudgetCases = CaseTriggerHelper.filterApprovedEventsAndBudgetCases(newCases, oldMap);
        
        if (!approvedBudgetCases.isEmpty()) {
            System.debug('Processing ' + approvedBudgetCases.size() + ' approved Events and Budget cases');
            CaseTriggerHelper.processApprovedBudgetCases(approvedBudgetCases);
        }
        /* SId */
        
        // Identify Withdrawal cases that changed to Closed
        List<Case> closedWithdrawalCases = CaseTriggerHelper.filterClosedWithdrawalCases(newCases, oldMap);
        
        if (!closedWithdrawalCases.isEmpty()) {
            System.debug('Processing ' + closedWithdrawalCases.size() + ' closed Withdrawal cases');
            CaseTriggerHelper.processWithdrawalCases(closedWithdrawalCases);
        }
        
        // Identify Rejoin cases that changed to Closed
        List<Case> closedRejoinCases = CaseTriggerHelper.filterClosedRejoinCases(newCases, oldMap);
        
        if (!closedRejoinCases.isEmpty()) {
            System.debug('Processing ' + closedRejoinCases.size() + ' closed Rejoin cases');
            CaseTriggerHelper.processRejoinCases(closedRejoinCases);
        }
        
        AdvisingNotificationService.notifyGeneralSupportStatusUpdates(newCases, oldMap);
        
        // COMMENTED OUT - Payment Successful path for Rejoin no longer creates Enrollment Sessions
        // List<Case> paymentApprovedRejoinCases = CaseTriggerHelper.filterPaymentApprovedRejoinCases(newCases, oldMap);
        // if (!paymentApprovedRejoinCases.isEmpty()) {
        //     System.debug('Processing ' + paymentApprovedRejoinCases.size() + ' Payment Successful Rejoin cases');
        //     CaseTriggerHelper.processRejoinPaymentApproved(paymentApprovedRejoinCases);
        // }
        
        System.debug('=== CaseAssignmentHandler.handleAfterUpdate completed ===');
    }
    
    public static void ensureGeneralSupportRejectedOwner(List<Case> newCases, Map<Id, Case> oldMap) {
        if (GENERAL_SUPPORT_RT_ID == null || newCases == null || newCases.isEmpty() || oldMap == null) {
            return;
        }
        
        for (Case caseRecord : newCases) {
            Case oldCase = oldMap.get(caseRecord.Id);
            if (oldCase == null) {
                continue;
            }
            
            if (caseRecord.RecordTypeId == GENERAL_SUPPORT_RT_ID
                && caseRecord.Status == 'Rejected'
                && caseRecord.OwnerId == null) {
                    caseRecord.OwnerId = oldCase.OwnerId != null ? oldCase.OwnerId : UserInfo.getUserId();
                }
        }
    }
    public static void createGraduationEligibilityOnCase(List<Case> newCases) {
        Id graduateAuditRecordTypeId =
            Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName()
            .get('Graduate_Audit')
            .getRecordTypeId();
        
        Set<Id> programIds = new Set<Id>();
        Set<Id> academicTermIds = new Set<Id>();
        
        for (Case c : newCases) {
            if (c.RecordTypeId == graduateAuditRecordTypeId) {
                if (c.Program__c != null) {
                    programIds.add(c.Program__c);
                }
                if (c.Academic_Term__c != null) {
                    academicTermIds.add(c.Academic_Term__c);
                }
            }
        }
        
        if (programIds.isEmpty()) {
            return;
        }
        
        Id defaultAcademicTermId = getCurrentAcademicTermId();
        
        Set<Id> termsToCheck = new Set<Id>();
        termsToCheck.addAll(academicTermIds);
        
        if (termsToCheck.isEmpty() && defaultAcademicTermId != null) {
            termsToCheck.add(defaultAcademicTermId);
        }
        
        Map<String, Graduation_Eligibility__c> existingEligibilityMap =
            new Map<String, Graduation_Eligibility__c>();
        
        if (!termsToCheck.isEmpty()) {
            
            for (Graduation_Eligibility__c ge : [
                SELECT Id,
                Program__c,
                Program_Enrollment__c,
                Academic_Term__c
                FROM Graduation_Eligibility__c
                WHERE Program__c IN :programIds
                AND Academic_Term__c IN :termsToCheck
            ]) {
                
                String key =
                    ge.Program__c + '-' +
                    ge.Program_Enrollment__c + '-' +
                    ge.Academic_Term__c;
                
                existingEligibilityMap.put(key, ge);
            }
        }
        
        List<ProgramEnrollment> enrollments = [
            
            SELECT Id,
            ProgramId,
            ContactId,
            Program.Name,
            Contact.Name,
            Status,
            Academic_Term__c,
            CGPA__c,
            Overall_Attempted_Credits__c,
            Overall_Earned_Credits__c,
            Failed_Courses__c,
            Finance_Clearance__c,
            Core_Credits_Earned__c,
            Elective_Credits_Earned__c,
            PGID__c
            
            FROM ProgramEnrollment
            
            WHERE ProgramId IN :programIds
            AND Academic_Term__c IN :termsToCheck
            AND Status = 'Registered'
            
            AND Id NOT IN (
                SELECT Program_Enrollment__c
                FROM Enrollment_Session__c
                WHERE Status__c = 'LOA'
                AND Program_Enrollment__c != null
            )
        ];
        
        List<Graduation_Eligibility__c> recordsToInsert =
            new List<Graduation_Eligibility__c>();
        
        for (Case caseRecord : newCases) {
            
            if (caseRecord.RecordTypeId != graduateAuditRecordTypeId ||
                caseRecord.Program__c == null) {
                    continue;
                }
            
            Id caseTermId =
                caseRecord.Academic_Term__c != null
                ? caseRecord.Academic_Term__c
                : defaultAcademicTermId;
            
            if (caseTermId == null) {
                continue;
            }
            
            for (ProgramEnrollment pe : enrollments) {
                
                if (pe.ProgramId != caseRecord.Program__c) {
                    continue;
                }
                
                String key =
                    pe.ProgramId + '-' +
                    pe.Id + '-' +
                    caseTermId;
                
                if (existingEligibilityMap.containsKey(key)) {
                    continue;
                }
                
                Graduation_Eligibility__c ge =
                    new Graduation_Eligibility__c();
                
                ge.Name =
                    (String.isNotBlank(pe.PGID__c)
                     ? pe.PGID__c
                     : 'Unknown PGID')
                    + '-' +
                    (pe.Contact != null
                     ? pe.Contact.Name
                     : 'Unknown Contact');
                
                ge.Case__c = caseRecord.Id;
                ge.Program__c = pe.ProgramId;
                ge.Program_Enrollment__c = pe.Id;
                ge.Contact__c = pe.ContactId;
                ge.Academic_Term__c = caseTermId;
                
                // Academic Values
                ge.Credits_Attempted__c =
                    pe.Overall_Attempted_Credits__c;
                
                ge.Credits_Earned__c =
                    pe.Overall_Earned_Credits__c;
                
                ge.Fail_Count__c =
                    pe.Failed_Courses__c;
                
                ge.Core_Credits_Earned__c =
                    pe.Core_Credits_Earned__c;
                
                ge.Elective_Credits_Earned__c =
                    pe.Elective_Credits_Earned__c;
                
                // Status remains pending until Finalize Population
                ge.Eligibility_Status__c = 'Pending';
                //ge.Eligibility_Sub_Status__c = 'Pending Evaluation';
                
                ge.Rule_Summary__c =
                    'Awaiting Finalize Population evaluation';
                
                recordsToInsert.add(ge);
                
                existingEligibilityMap.put(key, ge);
            }
        }
        
        if (!recordsToInsert.isEmpty()) {
            insert recordsToInsert;
        }
    }
    
    
    /* public static void createGraduationEligibilityOnCase(List<Case> newCases) {
Id graduateAuditRecordTypeId = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName()
.get('Graduate_Audit').getRecordTypeId();

Set<Id> programIds = new Set<Id>();
Set<Id> academicTermIds = new Set<Id>();
List<Graduation_Eligibility__c> graduationEligibilitiesToInsert = new List<Graduation_Eligibility__c>();

// Collect program and term IDs from Cases
for (Case caseRecord : newCases) {
if (caseRecord.RecordTypeId == graduateAuditRecordTypeId) {
if (caseRecord.Program__c != null) programIds.add(caseRecord.Program__c);
if (caseRecord.Academic_Term__c != null) academicTermIds.add(caseRecord.Academic_Term__c);
}
}

// Early exit if no programs
if (programIds.isEmpty()) {
System.debug('No programs found. Exiting.');
return;
}

// Query current Academic Term
Id defaultAcademicTermId = getCurrentAcademicTermId();

Set<Id> academicTermsToCheck = new Set<Id>();
if (!academicTermIds.isEmpty()) academicTermsToCheck.addAll(academicTermIds);
if (academicTermsToCheck.isEmpty() && defaultAcademicTermId != null) academicTermsToCheck.add(defaultAcademicTermId);


Map<String, Graduation_Eligibility__c> existingEligibilityMap = new Map<String, Graduation_Eligibility__c>();
if (!programIds.isEmpty() && !academicTermsToCheck.isEmpty()) {
for (Graduation_Eligibility__c ge : [
SELECT Id, Program__c, Program_Enrollment__c, Academic_Term__c, Case__c, Case__r.CaseNumber
FROM Graduation_Eligibility__c
WHERE Program__c IN :programIds AND Academic_Term__c IN :academicTermsToCheck
]) {

String programId = String.isBlank(ge.Program__c) ? 'NOPROG' : ge.Program__c;
String peId      = String.isBlank(ge.Program_Enrollment__c) ? 'NOPE' : ge.Program_Enrollment__c;
String termId    = String.isBlank(ge.Academic_Term__c) ? 'NOTERM' : ge.Academic_Term__c;

String key = programId + '-' + peId + '-' + termId;

// String key = ge.Program__c + '-' + (ge.Program_Enrollment__c != null ? ge.Program_Enrollment__c : '') + '-' + ge.Academic_Term__c;
existingEligibilityMap.put(key, ge);
}
}

// Query Program Enrollments with Status = 'Registered' only
List<ProgramEnrollment> eligibleEnrollments = [
SELECT Id, ProgramId, ContactId, Program.Name, Contact.Name, Status ,CGPA__c,Academic_Term__c
FROM ProgramEnrollment 
WHERE ProgramId IN :programIds
AND Academic_Term__c IN :academicTermsToCheck
AND Status = 'Registered'
AND Id NOT IN (
SELECT Program_Enrollment__c 
FROM Enrollment_Session__c 
WHERE Status__c = 'LOA'
AND Program_Enrollment__c != null
)
];

System.debug('Found ' + eligibleEnrollments.size() + ' Program Enrollments with Status = Registered');

if (eligibleEnrollments.isEmpty()) {
System.debug('No eligible Program Enrollments found. Skipping Graduation Eligibility creation.');
return;
}

// Get all Program Enrollment IDs
Set<Id> peIds = new Set<Id>();
for (ProgramEnrollment pe : eligibleEnrollments) {
peIds.add(pe.Id);
}

// [NEW] Query Failed Courses Count for these Enrollments
Map<Id, Integer> peFailedCountMap = new Map<Id, Integer>();

if (!peIds.isEmpty()) {
for (AggregateResult ar : [
SELECT Program_Enrollment__c peId, COUNT(Id) failCount 
FROM CourseOfferingPtcpResult 
WHERE Program_Enrollment__c IN :peIds 
AND Grade_Letter__c = 'F'  // Ensure this matches your specific failure grade
GROUP BY Program_Enrollment__c
]) {
peFailedCountMap.put(
(Id)ar.get('peId'), 
(Integer)ar.get('failCount')
);
}
}
// Query ONLY Completed Enrollment Sessions
Map<Id, List<Enrollment_Session__c>> peToSessionsMap = new Map<Id, List<Enrollment_Session__c>>();

for (Enrollment_Session__c es : [
SELECT Id, Program_Enrollment__c, Status__c, Academic_Term__c
FROM Enrollment_Session__c
WHERE Program_Enrollment__c IN :peIds
AND Status__c = 'Completed'  // Only completed sessions
]) {
if (!peToSessionsMap.containsKey(es.Program_Enrollment__c)) {
peToSessionsMap.put(es.Program_Enrollment__c, new List<Enrollment_Session__c>());
}
peToSessionsMap.get(es.Program_Enrollment__c).add(es);
}

System.debug('Found completed sessions for ' + peToSessionsMap.size() + ' Program Enrollments');



// Determine eligibility status for each Program Enrollment
Map<Id, String> peEligibilityStatusMap = new Map<Id, String>();

for (ProgramEnrollment pe : eligibleEnrollments) {

Decimal cgpa = pe.CGPA__c;
// [NEW] Get failed count (default to 0 if none found)
Integer failedCount = peFailedCountMap.containsKey(pe.Id) ? peFailedCountMap.get(pe.Id) : 0;

if (cgpa == null) {
System.debug('️ CGPA missing for PE ' + pe.Id + ' – Marked Not Eligible');
peEligibilityStatusMap.put(pe.Id, 'Not Eligible');
}
else if (cgpa < 2.5) {
System.debug(' CGPA ' + cgpa + ' < 2.5 for PE ' + pe.Id + ' – Not Eligible');
peEligibilityStatusMap.put(pe.Id, 'Not Eligible');
}

else if (failedCount > 1) {
System.debug('❌ Failed Count ' + failedCount + ' > 1 for PE ' + pe.Id + ' – Not Eligible');
peEligibilityStatusMap.put(pe.Id, 'Not Eligible');

}
else {
System.debug(' CGPA ' + cgpa + ' >= 2.5 for PE ' + pe.Id + ' – Eligible');
peEligibilityStatusMap.put(pe.Id, 'Eligible');
}
}


// Create Graduation Eligibility records
for (Case caseRecord : newCases) {
if (caseRecord.RecordTypeId != graduateAuditRecordTypeId || caseRecord.Program__c == null) {
continue;
}

Id caseAcademicTermId = (caseRecord.Academic_Term__c != null) ? 
caseRecord.Academic_Term__c : defaultAcademicTermId;

if (caseAcademicTermId == null) {
System.debug('❌ No Academic Term found for Case: ' + caseRecord.Id);
continue;
}

// Loop through eligible enrollments for THIS case's program
for (ProgramEnrollment pe : eligibleEnrollments) {
// Skip if different program
if (pe.ProgramId != caseRecord.Program__c) {
continue;
}

String key = pe.ProgramId + '-' + pe.Id + '-' + caseAcademicTermId;

// Check if duplicate exists
if (existingEligibilityMap.containsKey(key)) { 
Graduation_Eligibility__c existingGE = existingEligibilityMap.get(key);
caseRecord.addError(
'A Graduation Eligibility already exists for this Program and Term. ' +
'Existing Case: ' + (existingGE.Case__r != null ? existingGE.Case__r.CaseNumber : existingGE.Case__c)
);
continue;
}

// Get the eligibility status we determined earlier
String eligibilityStatus = peEligibilityStatusMap.get(pe.Id);
if (eligibilityStatus == null) {
eligibilityStatus = 'Not Eligible'; // Default fallback
}

Graduation_Eligibility__c ge = new Graduation_Eligibility__c(
Program__c = pe.ProgramId,
Program_Enrollment__c = pe.Id,
Academic_Term__c = caseAcademicTermId,
Eligibility_Status__c = eligibilityStatus, 
Contact__c = pe.ContactId,
Name = (pe.Program != null ? pe.Program.Name : 'Unknown Program') + '-' +
(pe.Contact != null ? pe.Contact.Name : 'Unknown Contact'),
Case__c = caseRecord.Id
);

graduationEligibilitiesToInsert.add(ge);

System.debug('Created Graduation Eligibility for PE: ' + pe.Id + 
' | Contact: ' + pe.Contact.Name + 
' | Status: ' + eligibilityStatus);
}
}

if (!graduationEligibilitiesToInsert.isEmpty()) {
System.debug('Inserting ' + graduationEligibilitiesToInsert.size() + ' Graduation Eligibility records');
insert graduationEligibilitiesToInsert;
System.debug(' Successfully created Graduation Eligibility records');
} else {
System.debug('No Graduation Eligibility records to insert');
}

}*/
    
    private static Id getCurrentAcademicTermId() {
        Integer currentYear = System.today().year();
        Integer month = System.today().month();
        String academicTermName;
        
        if (month >= 9) {
            academicTermName = String.valueOf(currentYear) + '-' + String.valueOf(currentYear + 1);
        } else {
            academicTermName = String.valueOf(currentYear - 1) + '-' + String.valueOf(currentYear);
        }
        
        try {
            AcademicTerm academicTermRecord = [
                SELECT Id 
                FROM AcademicTerm 
                WHERE Name = :academicTermName 
                LIMIT 1
            ];
            return academicTermRecord.Id;
        } catch (Exception e) {
            return null;
        }
    }
    
    public static void handleStatusChange(
        List<Case> newList,
        Map<Id, Case> oldMap
    ) {
        System.debug('=== START handleStatusChange ===');
        System.debug('Total Cases Received: ' + newList.size());
        
        for (Case c : newList) {
            
            Case old = oldMap.get(c.Id);
            
            System.debug('-----------------------------');
            System.debug('Processing Case Id: ' + c.Id);
            System.debug('Old Status: ' + old.Status);
            System.debug('New Status: ' + c.Status);
            System.debug('Record Type: ' + c.RecordTypeId);
            
            // Safety checks
            if (old == null) {
                System.debug('❌ Old Case record is NULL. Skipping...');
                continue;
            }
            
            if (c.RecordTypeId == null) {
                System.debug('❌ RecordType is NULL. Skipping...');
                continue;
            }
            system.debug('c.RecordType.DeveloperName '+ c.RecordType.DeveloperName);
            system.debug('c.Status '+ c.Status);
            system.debug('old.Status '+ old.Status);
            // Status Change Check
            if (c.Status != old.Status &&
                c.RecordTypeId == OFFLINE_PAYMENT_RT_ID ) {
                    
                    System.debug('✅ Status changed for Offline Payment case');
                    
                    if (c.Status == 'Payment Approved') {
                        System.debug('➡️ Case Approved. Proceeding to approve payment...');
                        approvePayment(c);
                        
                    } else if (c.Status == 'Payment Rejected') {
                        System.debug('➡️ Case Rejected. Proceeding to reject payment...');
                        rejectPayment(c);
                        
                    } else {
                        System.debug('⚠️ Status changed but not handled: ' + c.Status);
                    }
                } else {
                    System.debug('ℹ️ No relevant status change detected');
                }
        }
        
        System.debug('=== END handleStatusChange ===');
    }
    
    /*private static void rejectPayment(Case c) {

System.debug('=== START rejectPayment ===');
System.debug('Case Id: ' + c.Id);
System.debug('Linked Payment Id: ' + c.ISB_Payment__c);

if (c.ISB_Payment__c == null) {
System.debug('❌ No Payment linked to Case. Exiting...');
return;
}

ISB_Payment__c pay = [
SELECT Id, Amount__c, ISB_Installment__c, Initiated__c
FROM ISB_Payment__c
WHERE Id = :c.ISB_Payment__c
LIMIT 1
];

System.debug('Payment Found: ' + pay.Id);
System.debug('Payment Amount: ' + pay.Amount__c);
System.debug('Payment Installment Id: ' + pay.ISB_Installment__c);
System.debug('Current Payment Status: ' + pay.Initiated__c);

if (pay.ISB_Installment__c == null) {
System.debug('❌ Payment has no Installment. Exiting...');
return;
}

// Revert Installment
ISB_Installment__c inst = [
SELECT Id, Pending_Amount__c
FROM ISB_Installment__c
WHERE Id = :pay.ISB_Installment__c
LIMIT 1
];

System.debug('Installment Found: ' + inst.Id);
System.debug('Pending Amount BEFORE Revert: ' + inst.Pending_Amount__c);

inst.Pending_Amount__c += pay.Amount__c;

update inst;

System.debug('Pending Amount AFTER Revert: ' + inst.Pending_Amount__c);

// Mark Payment Failed
pay.Initiated__c = 'Failed';
update pay;

System.debug('Payment marked as FAILED');
System.debug('=== END rejectPayment ===');
}*/
    
    /*private static void rejectPayment(Case c) {

System.debug('=== START rejectPayment ===');
System.debug('Case Id: ' + c.Id);
System.debug('Linked Payment Id: ' + c.ISB_Payment__c);

if (c.ISB_Payment__c == null) {
System.debug('❌ No Payment linked to Case. Exiting...');
return;
}

ISB_Payment__c pay = [
SELECT Id, Amount__c, ISB_Installment__c, ISB_Fees__c, Initiated__c
FROM ISB_Payment__c
WHERE Id = :c.ISB_Payment__c
LIMIT 1
];

System.debug('Payment Found: ' + pay.Id);
System.debug('Payment Amount: ' + pay.Amount__c);
System.debug('Payment Installment Id: ' + pay.ISB_Installment__c);
System.debug('Payment Fee Id: ' + pay.ISB_Fees__c);
System.debug('Current Payment Status: ' + pay.Initiated__c);

// ✅ REVERT ISB_FEE__C
if (pay.ISB_Fees__c != null) {
ISB_Fee__c fee = [
SELECT Id, Pending_Amount__c, Paid_Amount__c
FROM ISB_Fee__c
WHERE Id = :pay.ISB_Fees__c
LIMIT 1
];

System.debug('Fee Found: ' + fee.Id);
System.debug('Fee Pending Amount BEFORE Revert: ' + fee.Pending_Amount__c);

//fee.Pending_Amount__c = (fee.Pending_Amount__c != null ? fee.Pending_Amount__c : 0) + pay.Amount__c;
//fee.Paid_Amount__c = (fee.Paid_Amount__c != null ? fee.Paid_Amount__c : 0) - pay.Amount__c;

update fee;

System.debug('Fee Pending Amount AFTER Revert: ' + fee.Pending_Amount__c);
}
// Mark Payment Failed
pay.Initiated__c = 'Failed';
update pay;

System.debug('✅ Payment marked as FAILED');
System.debug('=== END rejectPayment ===');
}*/
    private static void rejectPayment(Case c) {
        
        System.debug('=== START rejectPayment ===');
        System.debug('Case Id: ' + c.Id);
        System.debug('Linked Payment Id: ' + c.ISB_Payment__c);
        
        if (c.ISB_Payment__c == null) {
            System.debug('❌ No Payment linked to Case. Exiting...');
            return;
        }
        
        ISB_Payment__c pay = [
            SELECT Id, Amount__c, ISB_Installment__c, ISB_Fees__c, Initiated__c
            FROM ISB_Payment__c
            WHERE Id = :c.ISB_Payment__c
            LIMIT 1
        ];
        
        System.debug('Payment Found: ' + pay.Id);
        System.debug('Payment Amount: ' + pay.Amount__c);
        System.debug('Current Payment Status: ' + pay.Initiated__c);
        
        Decimal amount = pay.Amount__c;
        
        // ✅ REVERT ISB_FEE__C (ADD BACK the amount)
        if (pay.ISB_Fees__c != null) {
            ISB_Fee__c fee = [
                SELECT Id, Pending_Amount__c, Paid_Amount__c, Total_amount__c, Fee_Status__c,Fee_Amount__c
                FROM ISB_Fee__c
                WHERE Id = :pay.ISB_Fees__c
                LIMIT 1
            ];
            
            System.debug('Fee BEFORE Revert - Pending: ' + fee.Pending_Amount__c + ', Paid: ' + fee.Paid_Amount__c);
            
            // ✅ REVERT: Add back to pending, subtract from paid
            fee.Pending_Amount__c = (fee.Pending_Amount__c != null ? fee.Pending_Amount__c : 0) + amount;
            fee.Paid_Amount__c = (fee.Paid_Amount__c != null ? fee.Paid_Amount__c : 0) - amount;
            
            // ✅ Recalculate Fee Status
            if (fee.Paid_Amount__c >= fee.Fee_Amount__c) {
                fee.Fee_Status__c = 'Paid';
            } else if (fee.Paid_Amount__c > 0) {
                fee.Fee_Status__c = 'Partially Paid';
            } else {
                fee.Fee_Status__c = 'Not Paid';
            }
            
            update fee;
            System.debug('✅ Fee AFTER Revert - Pending: ' + fee.Pending_Amount__c + ', Paid: ' + fee.Paid_Amount__c + ', Status: ' + fee.Fee_Status__c);
        }
        
        // ✅ REVERT ISB_INSTALLMENT__C
        if (pay.ISB_Installment__c != null) {
            ISB_Installment__c inst = [
                SELECT Id, Pending_Amount__c, Paid_Amount__c, Total_Amount_calc__c, Installment_Status__c,Total_Amount__c
                FROM ISB_Installment__c
                WHERE Id = :pay.ISB_Installment__c
                LIMIT 1
            ];
            
            System.debug('Installment BEFORE Revert - Pending: ' + inst.Pending_Amount__c + ', Paid: ' + inst.Paid_Amount__c);
            
            // ✅ REVERT: Add back to pending, subtract from paid
            inst.Pending_Amount__c = (inst.Pending_Amount__c != null ? inst.Pending_Amount__c : 0) + amount;
            inst.Paid_Amount__c = (inst.Paid_Amount__c != null ? inst.Paid_Amount__c : 0) - amount;
            
            // ✅ Recalculate Installment Status
            if (inst.Paid_Amount__c >= inst.Total_Amount__c) {
                inst.Installment_Status__c = 'Paid';
            } else if (inst.Paid_Amount__c > 0) {
                inst.Installment_Status__c = 'Partially Paid';
            } else {
                inst.Installment_Status__c = 'Not Paid';
            }
            
            update inst;
            System.debug('✅ Installment AFTER Revert - Pending: ' + inst.Pending_Amount__c + ', Paid: ' + inst.Paid_Amount__c + ', Status: ' + inst.Installment_Status__c);
        }
        
        // ✅ Mark Payment as Failed
        pay.Initiated__c = 'Failed';
        update pay;
        
        System.debug('✅ Payment marked as FAILED - Amounts reverted to original state');
        System.debug('=== END rejectPayment ===');
    }
    /*private static void approvePayment(Case c) {

System.debug('=== START approvePayment ===');
System.debug('Case Id: ' + c.Id);
System.debug('Linked Payment Id: ' + c.ISB_Payment__c);

if (c.ISB_Payment__c == null) {
System.debug('❌ No Payment linked to Case. Exiting...');
return;
}

ISB_Payment__c pay = [
SELECT Id, ISB_Installment__c, Initiated__c,Name, CreatedDate, Transaction_Date__c, Amount__c,
Cheque_DD_Number__c, RTGS_NEFT_Number__c, 
Bank_Name__c, Branch_Branch__c,
ISB_Installment__r.Name, 
ISB_Installment__r.Program__r.Name,
Customer__r.Name,
Customer__r.Student_Id__c,
Customer__r.MailingStreet,
Customer__r.MailingCity,
Customer__r.MailingPostalCode,
Customer__r.MailingCountry
FROM ISB_Payment__c
WHERE Id = :c.ISB_Payment__c
LIMIT 1
];

System.debug('Payment Found: ' + pay.Id);
System.debug('Installment Id: ' + pay.ISB_Installment__c);
System.debug('Current Payment Status: ' + pay.Initiated__c);

// Mark Payment Success
pay.Initiated__c = 'Success';
update pay;

try {
ISB_ReceiptGenerator.generateAndAttachReceiptAsync(
pay.Id,
pay.Name
);
System.debug('✅ Receipt generation initiated (async)');
} catch (Exception receiptEx) {
System.debug('❌ Error initiating receipt generation: ' + receiptEx.getMessage());
}

System.debug('Payment marked as SUCCESS');

if (pay.ISB_Installment__c != null) {
System.debug('Updating Installment status...');
RazorpayController.updateInstallmentStatus(pay.ISB_Installment__c);
} else {
System.debug('⚠️ Payment has no Installment Id. Skipping installment update');
}

ISB_Installment__c inst = [
SELECT Id, Pending_Amount__c, Installment_Status__c
FROM ISB_Installment__c
WHERE Id = :pay.ISB_Installment__c
LIMIT 1
];

if (inst.Pending_Amount__c == 0 &&
inst.Installment_Status__c == 'Paid') {

System.debug('✅ Installment fully paid. Creating Enrollment Sessions...');
RazorpayController.processInstallmentFromMaster(inst.Id);

} else {
System.debug('⚠️ Installment not fully paid. Skipping session creation');
}


System.debug('=== END approvePayment ===');
}*/
    
    /*private static void approvePayment(Case c) {

System.debug('=== START approvePayment ===');
System.debug('Case Id: ' + c.Id);
System.debug('Linked Payment Id: ' + c.ISB_Payment__c);

if (c.ISB_Payment__c == null) {
System.debug('❌ No Payment linked to Case. Exiting...');
return;
}

ISB_Payment__c pay = [
SELECT Id, ISB_Installment__c, ISB_Fees__c, Initiated__c, Name, CreatedDate, 
Transaction_Date__c, Amount__c, Cheque_DD_Number__c, RTGS_NEFT_Number__c, 
Bank_Name__c, Branch_Branch__c,
ISB_Installment__r.Name, 
ISB_Installment__r.Program__r.Name,
Customer__r.Name,
// Customer__r.Student_Id__c,
Customer__r.MailingStreet,
Customer__r.MailingCity,
Customer__r.MailingPostalCode,
Customer__r.MailingCountry
FROM ISB_Payment__c
WHERE Id = :c.ISB_Payment__c
LIMIT 1
];

System.debug('Payment Found: ' + pay.Id);
System.debug('Installment Id: ' + pay.ISB_Installment__c);
System.debug('Fee Id: ' + pay.ISB_Fees__c);
System.debug('Current Payment Status: ' + pay.Initiated__c);

// ✅ GET FEE TYPE
String feeType = null;
if (pay.ISB_Fees__c != null) {
ISB_Fee__c fee = [
SELECT Id, Fee_Type__c, Pending_Amount__c, Paid_Amount__c, Total_amount__c, Fee_Status__c
FROM ISB_Fee__c
WHERE Id = :pay.ISB_Fees__c
LIMIT 1
];

feeType = fee.Fee_Type__c;
System.debug('Fee Type: ' + feeType);

// ✅ UPDATE FEE AMOUNTS ON APPROVAL
fee.Pending_Amount__c = (fee.Pending_Amount__c != null ? fee.Pending_Amount__c : 0) - pay.Amount__c;
fee.Paid_Amount__c = (fee.Paid_Amount__c != null ? fee.Paid_Amount__c : 0) + pay.Amount__c;

// Update Fee Status based on payment
if (fee.Paid_Amount__c >= fee.Total_amount__c) {
fee.Fee_Status__c = 'Paid';
} else if (fee.Paid_Amount__c > 0) {
fee.Fee_Status__c = 'Partially Paid';
}

update fee;
System.debug('✅ ISB_Fee__c Updated - Pending: ' + fee.Pending_Amount__c + ', Paid: ' + fee.Paid_Amount__c);
}

if (pay.ISB_Installment__c != null && feeType != null && feeType.contains('Installment')) {
System.debug('✅ Updating Breakage Records with GST Allocation...');
updateBreakageRecordsWithAllocation(pay.ISB_Installment__c, pay.Amount__c);
}

// ✅ ALSO UPDATE ISB_INSTALLMENT__C ON APPROVAL
if (pay.ISB_Installment__c != null) {
ISB_Installment__c inst = [
SELECT Id, Pending_Amount__c, Paid_Amount__c
FROM ISB_Installment__c
WHERE Id = :pay.ISB_Installment__c
LIMIT 1
];

inst.Pending_Amount__c = (inst.Pending_Amount__c != null ? inst.Pending_Amount__c : 0) - pay.Amount__c;
inst.Paid_Amount__c = (inst.Paid_Amount__c != null ? inst.Paid_Amount__c : 0) + pay.Amount__c;

update inst;
System.debug('✅ ISB_Installment__c Updated - Pending: ' + inst.Pending_Amount__c);
}

// Mark Payment Success
pay.Initiated__c = 'Success';
update pay;

try {
ISB_ReceiptGenerator.generateAndAttachReceiptAsync(
pay.Id,
pay.Name
);
System.debug('✅ Receipt generation initiated (async)');
} catch (Exception receiptEx) {
System.debug('❌ Error initiating receipt generation: ' + receiptEx.getMessage());
}

System.debug('✅ Payment marked as SUCCESS');

if (pay.ISB_Installment__c != null) {
System.debug('Updating Installment status...');
RazorpayController.updateInstallmentStatus(pay.ISB_Installment__c);
} else {
System.debug('⚠️ Payment has no Installment Id. Skipping installment update');
}

// ✅ ONLY CALL processInstallmentFromMaster FOR INSTALLMENT FEES
if (feeType != null && feeType.contains('Installment')) {
System.debug('✅ Fee Type contains "Installment" - Checking if all fees are paid...');

// ✅ PASS FEE ID INSTEAD OF INSTALLMENT ID
if (pay.ISB_Fees__c != null) {
// Check if Case is General Support to avoid unwanted execution
if (c.RecordType.Name != 'General Support' || c.Sub_Types__c != 'Name Change / Display') {
RazorpayController.processInstallmentFromMaster(pay.ISB_Fees__c);
}
} else {
System.debug('⚠️ Payment has no Fee Id. Skipping session creation');
}
} else {
System.debug('⚠️ Fee Type is NOT Installment (' + feeType + ') - Skipping processInstallmentFromMaster');
}

System.debug('=== END approvePayment ===');
}*/
    private static void approvePayment(Case c) {
        
        System.debug('=== START approvePayment ===');
        System.debug('Case Id: ' + c.Id);
        System.debug('Linked Payment Id: ' + c.ISB_Payment__c);
        
        if (c.ISB_Payment__c == null) {
            System.debug('❌ No Payment linked to Case. Exiting...');
            return;
        }
        
        ISB_Payment__c pay = [
            SELECT Id, ISB_Installment__c, ISB_Fees__c, Initiated__c, Name, CreatedDate, 
            Transaction_Date__c, Amount__c, Cheque_DD_Number__c, RTGS_NEFT_Number__c, 
            Bank_Name__c, Branch_Branch__c,
            ISB_Installment__r.Name, 
            ISB_Installment__r.Program__r.Name,
            Customer__r.Name,
            Customer__r.MailingStreet,
            Customer__r.MailingCity,
            Customer__r.MailingPostalCode,
            Customer__r.MailingCountry
            FROM ISB_Payment__c
            WHERE Id = :c.ISB_Payment__c
            LIMIT 1
        ];
        
        System.debug('Payment Found: ' + pay.Id);
        System.debug('Current Payment Status: ' + pay.Initiated__c);
        
        // ✅ NO FEE/INSTALLMENT UPDATE - Already updated in updatePaymentRecordToSuccess
        System.debug('ℹ️ Amounts already updated during payment initiation - no changes needed');
        
        // ✅ Mark Payment as Success
        pay.Initiated__c = 'Success';
        update pay;
        System.debug('✅ Payment marked as SUCCESS');
        
        // ✅ Generate Receipt
        try {
            ISB_ReceiptGenerator.generateAndAttachReceiptAsync(pay.Id, pay.Name);
            System.debug('✅ Receipt generation initiated');
        } catch (Exception receiptEx) {
            System.debug('❌ Error generating receipt: ' + receiptEx.getMessage());
        }
        
        // ✅ Update Installment Status (recalculate based on all payments)
        if (pay.ISB_Installment__c != null) {
            System.debug('Updating Installment status...');
            RazorpayController.updateInstallmentStatus(pay.ISB_Installment__c);
        }
        
        // ✅ Process Enrollment Sessions if fully paid
        if (pay.ISB_Fees__c != null) {
            ISB_Fee__c feeCheck = [
                SELECT Fee_Type__c, Fee_Status__c, Pending_Amount__c
                FROM ISB_Fee__c
                WHERE Id = :pay.ISB_Fees__c
                LIMIT 1
            ];
            
            System.debug('Fee Status after approval: ' + feeCheck.Fee_Status__c + ', Pending: ' + feeCheck.Pending_Amount__c);
            
            if (feeCheck.Fee_Type__c != null && 
                feeCheck.Fee_Type__c.contains('Installment') && 
                feeCheck.Pending_Amount__c == 0 && 
                feeCheck.Fee_Status__c == 'Paid') {
                    
                    System.debug('✅ Installment Fee fully paid - Creating Enrollment Sessions');
                    RazorpayController.processInstallmentFromMaster(pay.ISB_Fees__c);
                } else {
                    System.debug('ℹ️ Fee not fully paid yet - Pending: ' + feeCheck.Pending_Amount__c);
                }
        }
        markFirstInstallmentPaid(pay.ISB_Installment__c, pay.ISB_Fees__c, pay.Id);
        System.debug('=== END approvePayment ===');
    }
    // Add this new method to ISB_Payment_Extension class
    public static String generateAndAttachReceiptInternal(Id paymentId, String paymentName) {
        try {
            // 1. Reference the Visualforce Page
            PageReference pdfPage = Page.ISBPaymentReceipt; 
            pdfPage.getParameters().put('id', paymentId);
            
            // 2. Generate the PDF Blob (Handle Test Context)
            Blob pdfBlob;
            if (Test.isRunningTest()) { 
                pdfBlob = Blob.valueOf('Unit Test Attachment Body');
            } else {
                pdfBlob = pdfPage.getContentAsPDF();
            }
            
            // 3. Create ContentVersion (The File)
            ContentVersion cv = new ContentVersion();
            cv.Title = 'Receipt_' + paymentName + '.pdf';
            cv.PathOnClient = 'Receipt_' + paymentName + '.pdf';
            cv.VersionData = pdfBlob;
            cv.IsMajorVersion = true;
            insert cv;
            
            // 4. Get the ContentDocumentId
            Id conDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
            
            // 5. Link the File to the Payment Record
            ContentDocumentLink cdl = new ContentDocumentLink();
            cdl.LinkedEntityId = paymentId; 
            cdl.ContentDocumentId = conDocId;
            cdl.ShareType = 'V'; // Viewer permission
            cdl.Visibility = 'AllUsers'; // Visible to Community Users
            insert cdl;
            
            return 'Success';
            
        } catch (Exception e) {
            // Regular exception for Apex-to-Apex calls
            System.debug('Error generating receipt: ' + e.getMessage());
            System.debug('Stack Trace: ' + e.getStackTraceString());
            throw e; // Re-throw to let caller handle
        }
    }
    
    // Keep your existing @AuraEnabled method for LWC calls
    @AuraEnabled
    public static String generateAndAttachReceipt(Id paymentId, String paymentName) {
        try {
            return generateAndAttachReceiptInternal(paymentId, paymentName);
        } catch (Exception e) {
            throw new AuraHandledException('Error generating receipt: ' + e.getMessage());
        }
    }
    
    public static void validateGraduationReview(List<Case> newCases, Map<Id, Case> oldMap) {
        Set<Id> casesToValidate = new Set<Id>();
        
        // 1. Identify Cases changing to 'Review Done'
        for (Case c : newCases) {
            Case old = oldMap.get(c.Id);
            if (c.Status == 'Review Done' && old.Status != 'Review Done') {
                casesToValidate.add(c.Id);
            }
        }
        
        if (casesToValidate.isEmpty()) return;
        
        // 2. Query Child Records to check rules
        // We look for ANY record that violates the rules
        List<Graduation_Eligibility__c> invalidRecords = [
            SELECT Id, Case__c, Name, Eligibility_Status__c, Eligibility_Sub_Status__c
            FROM Graduation_Eligibility__c
            WHERE Case__c IN :casesToValidate
        ];
        
        Map<Id, String> errorMap = new Map<Id, String>();
        
        for (Graduation_Eligibility__c ge : invalidRecords) {
            // Rule A: If Status is "Not Eligible", Sub Status CANNOT be blank
            if (ge.Eligibility_Status__c == 'Not Eligible' && String.isBlank(ge.Eligibility_Sub_Status__c)) {
                errorMap.put(ge.Case__c, 'Student ' + ge.Name + ' is "Not Eligible" but is missing a Sub Status.');
            }
            
            // Rule B: If Status is "Approved" (or Eligible), Sub Status MUST be blank
            // (Adjust 'Approved' to 'Eligible' if that is your exact picklist value)
            if ((ge.Eligibility_Status__c == 'Approved' || ge.Eligibility_Status__c == 'Eligible') 
                && !String.isBlank(ge.Eligibility_Sub_Status__c)) {
                    errorMap.put(ge.Case__c, 'Student ' + ge.Name + ' is marked Eligible/Approved but has a Sub Status (it should be blank).');
                }
        }
        
        // 3. Apply Errors to the Case records
        for (Case c : newCases) {
            if (errorMap.containsKey(c.Id)) {
                // This prevents the Case save and shows the error to the user
                c.addError('Cannot move to Review Done: ' + errorMap.get(c.Id));
            }
        }
    }
    
    public static void checkCaseRecordTypes(List<Case> newCases){
        Id graduateAuditRecordTypeId = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName()
            .get('Graduate_Audit').getRecordTypeId();
        List<Case> graduationCases = new List<Case>();
        for (Case caseRecord : newCases) {
            if (caseRecord.RecordTypeId == graduateAuditRecordTypeId) {
                graduationCases.add(caseRecord);
            }
        }
        if(!graduationCases.isEmpty()){
            // GraduationAuditCaseTeamHandler.handleAfterInsert(graduationCases);
            createGraduationEligibilityOnCase(graduationCases);
            
        }
    }
    
    /**
* Updates ISB_Student_Fee_Breakage__c records with payment allocation
* Follows GST calculation: IGST 18% OR CGST 9% + SGST 9%, then remaining to other fees
*/
    public static void updateBreakageRecordsWithAllocation(Id installmentId, Decimal paymentAmount) {
        System.debug('=== START updateBreakageRecordsWithAllocation ===');
        System.debug('Installment ID: ' + installmentId);
        System.debug('Payment Amount: ' + paymentAmount);
        
        if (installmentId == null || paymentAmount == null || paymentAmount <= 0) {
            System.debug('⚠️ Invalid parameters. Exiting...');
            return;
        }
        
        // Query all breakage records for this installment
        List<ISB_Student_Fee_Breakage__c> breakages = [
            SELECT Id, Fee_Type__c, Amount__c
            FROM ISB_Student_Fee_Breakage__c
            WHERE ISB_Installment__c = :installmentId
        ];
        
        if (breakages.isEmpty()) {
            System.debug('⚠️ No breakage records found. Exiting...');
            return;
        }
        
        System.debug('Found ' + breakages.size() + ' breakage records');
        
        // ✅ STEP 1: Separate GST and non-GST fees
        List<ISB_Student_Fee_Breakage__c> gstFees = new List<ISB_Student_Fee_Breakage__c>();
        List<ISB_Student_Fee_Breakage__c> nonGstFees = new List<ISB_Student_Fee_Breakage__c>();
        
        Boolean hasIGST = false;
        Boolean hasCGST = false;
        Boolean hasSGST = false;
        
        for (ISB_Student_Fee_Breakage__c breakage : breakages) {
            String feeTypeUpper = breakage.Fee_Type__c != null ? breakage.Fee_Type__c.toUpperCase() : '';
            
            if (feeTypeUpper.contains('IGST')) {
                hasIGST = true;
                gstFees.add(breakage);
            } else if (feeTypeUpper.contains('CGST')) {
                hasCGST = true;
                gstFees.add(breakage);
            } else if (feeTypeUpper.contains('SGST')) {
                hasSGST = true;
                gstFees.add(breakage);
            } else {
                nonGstFees.add(breakage);
            }
        }
        
        System.debug('Has IGST: ' + hasIGST);
        System.debug('Has CGST: ' + hasCGST);
        System.debug('Has SGST: ' + hasSGST);
        System.debug('GST Fees count: ' + gstFees.size());
        System.debug('Non-GST Fees count: ' + nonGstFees.size());
        
        // ✅ STEP 2: Calculate GST amounts from payment
        Decimal igstAmount = 0;
        Decimal cgstAmount = 0;
        Decimal sgstAmount = 0;
        Decimal totalGST = 0;
        
        if (hasIGST) {
            // IGST = 18% of payment amount
            igstAmount = (paymentAmount * 0.18).setScale(2, RoundingMode.HALF_UP);
            totalGST = igstAmount;
            System.debug('IGST Amount (18%): ' + igstAmount);
        } else if (hasCGST || hasSGST) {
            // CGST = 9% of payment amount
            // SGST = 9% of payment amount
            cgstAmount = (paymentAmount * 0.09).setScale(2, RoundingMode.HALF_UP);
            sgstAmount = (paymentAmount * 0.09).setScale(2, RoundingMode.HALF_UP);
            totalGST = cgstAmount + sgstAmount;
            System.debug('CGST Amount (9%): ' + cgstAmount);
            System.debug('SGST Amount (9%): ' + sgstAmount);
        }
        
        // ✅ STEP 3: Remaining amount after GST
        Decimal remainingAfterGST = paymentAmount - totalGST;
        System.debug('Total GST: ' + totalGST);
        System.debug('Remaining after GST: ' + remainingAfterGST);
        
        // ✅ STEP 4: Sort non-GST fees by priority
        Map<String, Integer> priorityMap = new Map<String, Integer>{
            'TUITION FEE' => 1,
                'TUITION' => 1,
                'ACCOMMODATION STUDIO' => 2,
                'ACCOMMODATION' => 2,
                'SECURITY DEPOSIT' => 3,
                'SECURITY' => 3
                };
                    
                    // Sort non-GST fees by priority
                    nonGstFees.sort(new BreakagePriorityComparator(priorityMap));
        
        System.debug('✅ Non-GST fees sorted by priority');
        for (ISB_Student_Fee_Breakage__c fee : nonGstFees) {
            System.debug('  - ' + fee.Fee_Type__c);
        }
        
        // ✅ STEP 5: Process GST fees first
        List<ISB_Student_Fee_Breakage__c> recordsToUpdate = new List<ISB_Student_Fee_Breakage__c>();
        
        for (ISB_Student_Fee_Breakage__c breakage : gstFees) {
            Decimal allocatedAmount = 0;
            String feeTypeUpper = breakage.Fee_Type__c != null ? breakage.Fee_Type__c.toUpperCase() : '';
            // Decimal pendingAmount = breakage.Pending_Amount__c != null ? breakage.Pending_Amount__c : 0;
            
            if (allocatedAmount > 0) {
                //breakage.Paid_Amount__c = (breakage.Paid_Amount__c != null ? breakage.Paid_Amount__c : 0) + allocatedAmount;
                // breakage.Pending_Amount__c = (breakage.Pending_Amount__c != null ? breakage.Pending_Amount__c : 0) - allocatedAmount;
                recordsToUpdate.add(breakage);
                //System.debug('Updated ' + breakage.Fee_Type__c + ' - Paid: ' + breakage.Paid_Amount__c + ', Pending: ' + breakage.Pending_Amount__c);
            }
        }
        
        // ✅ STEP 6: Process non-GST fees in priority order
        for (ISB_Student_Fee_Breakage__c breakage : nonGstFees) {
            Decimal allocatedAmount = 0;
            // Decimal pendingAmount = breakage.Pending_Amount__c != null ? breakage.Pending_Amount__c : 0;
            
            if (remainingAfterGST > 0) {
                //allocatedAmount = Math.min(remainingAfterGST, pendingAmount);
                remainingAfterGST -= allocatedAmount;
                System.debug('✅ Allocating to ' + breakage.Fee_Type__c + ': ' + allocatedAmount + ' (Remaining: ' + remainingAfterGST + ')');
            } else {
                System.debug('⚠️ No remaining amount for ' + breakage.Fee_Type__c);
            }
            
            if (allocatedAmount > 0) {
                // breakage.Paid_Amount__c = (breakage.Paid_Amount__c != null ? breakage.Paid_Amount__c : 0) + allocatedAmount;
                //breakage.Pending_Amount__c = (breakage.Pending_Amount__c != null ? breakage.Pending_Amount__c : 0) - allocatedAmount;
                recordsToUpdate.add(breakage);
                //System.debug('Updated ' + breakage.Fee_Type__c + ' - Paid: ' + breakage.Paid_Amount__c + ', Pending: ' + breakage.Pending_Amount__c);
            }
        }
        
        // ✅ STEP 7: Update records in database
        if (!recordsToUpdate.isEmpty()) {
            update recordsToUpdate;
            System.debug('✅ Successfully updated ' + recordsToUpdate.size() + ' breakage records');
        } else {
            System.debug('⚠️ No breakage records to update');
        }
        
        System.debug('=== END updateBreakageRecordsWithAllocation ===');
    }
    
    /**
* Comparator class to sort breakage records by priority
*/
    private class BreakagePriorityComparator implements Comparator<ISB_Student_Fee_Breakage__c> {
        private Map<String, Integer> priorityMap;
        
        public BreakagePriorityComparator(Map<String, Integer> priorityMap) {
            this.priorityMap = priorityMap;
        }
        
        public Integer compare(ISB_Student_Fee_Breakage__c a, ISB_Student_Fee_Breakage__c b) {
            String feeTypeA = a.Fee_Type__c != null ? a.Fee_Type__c.toUpperCase() : '';
            String feeTypeB = b.Fee_Type__c != null ? b.Fee_Type__c.toUpperCase() : '';
            
            Integer priorityA = getPriority(feeTypeA);
            Integer priorityB = getPriority(feeTypeB);
            
            return priorityA - priorityB;
        }
        
        private Integer getPriority(String feeType) {
            for (String key : priorityMap.keySet()) {
                if (feeType.contains(key)) {
                    return priorityMap.get(key);
                }
            }
            return 999; // Unknown types go last
        }
    }
    
    private static void markFirstInstallmentPaid(Id installmentId, Id feeId, Id paymentId) {
        System.debug('=== START markFirstInstallmentPaid ===');
        System.debug('Installment Id: ' + installmentId);
        System.debug('Fee Id: ' + feeId);
        System.debug('Payment Id: ' + paymentId);
        
        // ✅ All IDs required
        if (installmentId == null || feeId == null || paymentId == null) {
            System.debug('⚠️ One or more required Ids are null. Skipping...');
            return;
        }
        
        // ✅ Query Installment to check if it's Installment 1 and fully paid
        ISB_Installment__c inst = [
            SELECT Id, Name, Pending_Amount__c, Installment_Status__c, Installment_Number__c
            FROM ISB_Installment__c
            WHERE Id = :installmentId
            LIMIT 1
        ];
        
        System.debug('Installment Name: ' + inst.Name);
        System.debug('Installment Number: ' + inst.Installment_Number__c);
        System.debug('Installment Pending Amount: ' + inst.Pending_Amount__c);
        System.debug('Installment Status: ' + inst.Installment_Status__c);
        
        // ✅ Check if this is Installment 1 using Installment_Number__c
        Boolean isFirstInstallment = (inst.Installment_Number__c == '1' || inst.Installment_Number__c == 'Single');
        
        // Fallback: check by Name if Installment_Number__c is not available
        if (!isFirstInstallment && inst.Name != null) {
            isFirstInstallment = inst.Name.toLowerCase().contains('installment 1')
                || inst.Name.toLowerCase().endsWith('-1')
                || inst.Name.toLowerCase().endsWith('- 1');
        }
        
        System.debug('Is First Installment: ' + isFirstInstallment);
        
        if (!isFirstInstallment) {
            System.debug('ℹ️ Not the first installment. Skipping First_Installment_Paid__c update.');
            return;
        }
        
        // ✅ Check if Installment is fully paid
        Boolean installmentFullyPaid = (inst.Pending_Amount__c != null && inst.Pending_Amount__c == 0)
            || inst.Installment_Status__c == 'Paid';
        
        System.debug('Installment Fully Paid: ' + installmentFullyPaid);
        
        if (!installmentFullyPaid) {
            System.debug('ℹ️ Installment still has pending amount: ' + inst.Pending_Amount__c + '. Skipping...');
            return;
        }
        
        // ✅ Query ISB_Fee to check pending amount
        ISB_Fee__c fee = [
            SELECT Id, Pending_Amount__c, Fee_Status__c
            FROM ISB_Fee__c
            WHERE Id = :feeId
            LIMIT 1
        ];
        
        System.debug('Fee Pending Amount: ' + fee.Pending_Amount__c);
        System.debug('Fee Status: ' + fee.Fee_Status__c);
        
        // ✅ Check if ISB_Fee is also fully paid
        Boolean feeFullyPaid = (fee.Pending_Amount__c != null && fee.Pending_Amount__c == 0)
            || fee.Fee_Status__c == 'Paid';
        
        System.debug('Fee Fully Paid: ' + feeFullyPaid);
        
        if (!feeFullyPaid) {
            System.debug('ℹ️ ISB_Fee still has pending amount: ' + fee.Pending_Amount__c + '. Skipping...');
            return;
        }
        
        // ✅ Query Payment to check if already marked
        ISB_Payment__c pay = [
            SELECT Id, First_Installment_Paid__c
            FROM ISB_Payment__c
            WHERE Id = :paymentId
            LIMIT 1
        ];
        
        System.debug('First_Installment_Paid__c (current): ' + pay.First_Installment_Paid__c);
        
        // ✅ Already marked - no need to update again
        if (pay.First_Installment_Paid__c == true) {
            System.debug('ℹ️ First_Installment_Paid__c already marked TRUE. No update needed.');
            return;
        }
        
        // ✅ All conditions met - Mark First_Installment_Paid__c = true on Payment
        pay.First_Installment_Paid__c = true;
        update pay;
        
        System.debug('✅ First_Installment_Paid__c successfully marked TRUE on ISB_Payment: ' + paymentId);
        System.debug('=== END markFirstInstallmentPaid ===');
    }
}
