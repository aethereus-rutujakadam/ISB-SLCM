/**
 * @description Handles Workshop_Registration__c lifecycle (Label-Based Registration):
 *
 *  BEFORE INSERT:
 *    1. Reads Workshop__c and Batch_Label__c from registration record
 *    2. Queries all batches across all sessions matching workshop + label
 *    3. Validates workshop is Published and batches are not all Cancelled
 *    4. Enforces one-registration-per-workshop duplicate check
 *    5. Sets Status: Registered (if capacity available), Waitlisted (within threshold), or blocks
 *
 *  BEFORE DELETE:
 *    1. Deletes all related Workshop_Attendance__c records
 *
 *  AFTER INSERT:
 *    1. Creates Workshop_Attendance__c (Pending) for ALL matching batches across ALL sessions
 *    2. Updates Workshop__c.Total_Registrations__c via aggregate SOQL
 *    3. Updates Workshop_Batch__c.Total_Registered__c for all affected batches
 *    4. Sends registration confirmation email and in-app notification
 *
 *  AFTER UPDATE:
 *    - Waitlisted → Registered (manual advisor promotion):
 *        Creates missing attendance records
 *    - Registered/Waitlisted → Not Registered (cancellation):
 *        Deletes all related attendance records
 *        Auto-promotes oldest Waitlisted registrations
 *    Both paths update batch and workshop totals
 *
 * @author DEVSLCM Team
 * @date 2026
 */
public without sharing class WorkshopRegistrationHandler {

    // ── BEFORE INSERT ────────────────────────────────────────────────────────────

    public static void handleBeforeInsert(List<Workshop_Registration__c> newList) {
        // 1. Collect workshop IDs and batch labels from registrations
        Set<Id> workshopIds = new Set<Id>();
        Set<String> batchLabels = new Set<String>();
        Map<String, List<Workshop_Registration__c>> workshopLabelToRegs = new Map<String, List<Workshop_Registration__c>>();
        
        for (Workshop_Registration__c reg : newList) {
            if (reg.Workshop__c == null) {
                reg.addError('Workshop is required.');
                continue;
            }
            if (String.isBlank(reg.Batch_Label__c)) {
                reg.addError('Batch Label is required.');
                continue;
            }
            
            workshopIds.add(reg.Workshop__c);
            batchLabels.add(reg.Batch_Label__c);
            
            String key = reg.Workshop__c + '_' + reg.Batch_Label__c;
            if (!workshopLabelToRegs.containsKey(key)) {
                workshopLabelToRegs.put(key, new List<Workshop_Registration__c>());
            }
            workshopLabelToRegs.get(key).add(reg);
        }
        
        if (workshopIds.isEmpty()) return;

        // 2. Load workshop status
        Map<Id, Workshop__c> workshopMap = new Map<Id, Workshop__c>([
            SELECT Id, Status__c, Program__c
            FROM Workshop__c
            WHERE Id IN :workshopIds
        ]);

        // Resolve active Program Enrollment per student (prefer workshop program match)
        Set<Id> studentIds = new Set<Id>();
        for (Workshop_Registration__c reg : newList) {
            if (reg.Student__c != null) {
                studentIds.add(reg.Student__c);
            }
        }

        Map<String, Id> studentProgramToEnrollmentId = new Map<String, Id>();
        Map<Id, Id> studentToEnrollmentId = new Map<Id, Id>();

        if (!studentIds.isEmpty()) {
            for (ProgramEnrollment pe : [
                SELECT Id, ContactId, AccountId
                FROM ProgramEnrollment
                WHERE ContactId IN :studentIds
                AND IsActive = true
                ORDER BY CreatedDate DESC
            ]) {
                if (!studentToEnrollmentId.containsKey(pe.ContactId)) {
                    studentToEnrollmentId.put(pe.ContactId, pe.Id);
                }
                if (pe.AccountId != null) {
                    studentProgramToEnrollmentId.put(pe.ContactId + '_' + pe.AccountId, pe.Id);
                }
            }
        }

        // 3. Query all batches matching workshop + label combinations
        Map<String, List<Workshop_Batch__c>> workshopLabelToBatches = new Map<String, List<Workshop_Batch__c>>();
        
        for (Workshop_Batch__c b : [
            SELECT Id, Status__c, Capacity__c, Total_Registered__c, Overbooking_Threshold__c,
                   Batch_Label__c, Workshop_Session__c, Workshop_Session__r.Workshop__c,
                   Workshop_Session__r.Session_Number__c
            FROM Workshop_Batch__c
            WHERE Workshop_Session__r.Workshop__c IN :workshopIds
            AND Batch_Label__c IN :batchLabels
            ORDER BY Workshop_Session__r.Session_Number__c ASC
        ]) {
            String key = b.Workshop_Session__r.Workshop__c + '_' + b.Batch_Label__c;
            if (!workshopLabelToBatches.containsKey(key)) {
                workshopLabelToBatches.put(key, new List<Workshop_Batch__c>());
            }
            workshopLabelToBatches.get(key).add(b);
        }

        // 4. Check for existing registrations (one per workshop per student)
        studentIds = new Set<Id>();
        for (Workshop_Registration__c reg : newList) {
            if (reg.Student__c != null) studentIds.add(reg.Student__c);
        }

        Set<String> existingKeys = new Set<String>();
        for (Workshop_Registration__c existing : [
            SELECT Student__c, Workshop__c
            FROM Workshop_Registration__c
            WHERE Student__c IN :studentIds
            AND Workshop__c IN :workshopIds
            AND Status__c IN ('Registered', 'Waitlisted')
        ]) {
            existingKeys.add(existing.Student__c + '_' + existing.Workshop__c);
        }

        // 5. Process each registration
        for (Workshop_Registration__c reg : newList) {
            if (reg.Workshop__c == null || String.isBlank(reg.Batch_Label__c)) continue;
            
            Workshop__c workshop = workshopMap.get(reg.Workshop__c);
            if (workshop == null) {
                reg.addError('Invalid Workshop.');
                continue;
            }

            // Validate workshop lifecycle
            if (workshop.Status__c != 'Published') {
                reg.addError('Registrations are only open for Published workshops.');
                continue;
            }

            String key = reg.Workshop__c + '_' + reg.Batch_Label__c;
            List<Workshop_Batch__c> batches = workshopLabelToBatches.get(key);
            
            if (batches == null || batches.isEmpty()) {
                reg.addError('No batches found for the selected workshop and batch label.');
                continue;
            }

            // Check if all batches are cancelled
            Boolean allCancelled = true;
            for (Workshop_Batch__c b : batches) {
                if (b.Status__c != 'Cancelled') {
                    allCancelled = false;
                    break;
                }
            }
            if (allCancelled) {
                reg.addError('All batches with this label are cancelled.');
                continue;
            }

            // Stamp denormalized fields
            reg.Registration_Date__c = Date.today();

            // Populate Program Enrollment from student + workshop program when not provided
            if (reg.Program_Enrollment__c == null && reg.Student__c != null) {
                Id enrollmentId;
                if (workshop.Program__c != null) {
                    enrollmentId = studentProgramToEnrollmentId.get(reg.Student__c + '_' + workshop.Program__c);
                }
                if (enrollmentId == null) {
                    enrollmentId = studentToEnrollmentId.get(reg.Student__c);
                }
                if (enrollmentId != null) {
                    reg.Program_Enrollment__c = enrollmentId;
                }
            }

            // Duplicate check (one registration per workshop per student)
            String dupKey = reg.Student__c + '_' + reg.Workshop__c;
            if (existingKeys.contains(dupKey)) {
                reg.addError('You are already registered for this workshop. Only one registration per workshop is allowed.');
                continue;
            }
            existingKeys.add(dupKey); // Prevent duplicates within same transaction

            // Determine status based on aggregated capacity across all matching batches
            Decimal totalCapacity = 0;
            Decimal totalRegistered = 0;
            Decimal totalThreshold = 0;
            Boolean hasUnlimitedCapacity = false;
            
            for (Workshop_Batch__c b : batches) {
                if (b.Status__c == 'Cancelled') continue;
                
                if (b.Capacity__c == null) {
                    hasUnlimitedCapacity = true;
                    break;
                }
                totalCapacity += b.Capacity__c;
                totalRegistered += (b.Total_Registered__c != null ? b.Total_Registered__c : 0);
                totalThreshold += (b.Overbooking_Threshold__c != null ? b.Overbooking_Threshold__c : 0);
            }

            if (hasUnlimitedCapacity) {
                reg.Status__c = 'Registered';
            } else {
                if (totalRegistered < totalCapacity) {
                    reg.Status__c = 'Registered';
                } else if (totalRegistered < totalCapacity + totalThreshold) {
                    reg.Status__c = 'Waitlisted';
                } else {
                    reg.addError('All batches with this label are at full capacity. Please choose a different option.');
                }
            }
        }
    }

    // ── BEFORE DELETE ────────────────────────────────────────────────────────────

    public static void handleBeforeDelete(List<Workshop_Registration__c> oldList) {
        deleteAttendanceRecords(oldList);
        // Note: Batch and workshop totals will be recalculated by the after delete trigger
        // (if needed in the future) or can be handled via scheduled job
    }

    // ── AFTER INSERT ─────────────────────────────────────────────────────────────

    public static void handleAfterInsert(List<Workshop_Registration__c> newList) {
        List<Workshop_Registration__c> activeRegs = new List<Workshop_Registration__c>();
        for (Workshop_Registration__c reg : newList) {
            if (reg.Status__c == 'Registered' || reg.Status__c == 'Waitlisted') {
                activeRegs.add(reg);
            }
        }

        if (!activeRegs.isEmpty()) {
            createAttendanceRecords(activeRegs);
        }

        updateBatchRegisteredCounts(newList, null, false);
        updateWorkshopTotals(newList);

        // Send confirmation email + in-app notification asynchronously
        Set<Id> regIds = new Set<Id>();
        for (Workshop_Registration__c reg : newList) {
            if (reg.Status__c == 'Registered' || reg.Status__c == 'Waitlisted') {
                regIds.add(reg.Id);
            }
        }
        if (!regIds.isEmpty()) {
            WorkshopNotificationService.sendRegistrationConfirmations(regIds);
        }
    }

    // ── AFTER UPDATE ─────────────────────────────────────────────────────────────

    public static void handleAfterUpdate(
        List<Workshop_Registration__c> newList,
        Map<Id, Workshop_Registration__c> oldMap
    ) {
        List<Workshop_Registration__c> newlyRegistered  = new List<Workshop_Registration__c>();
        List<Workshop_Registration__c> newlyCancelled   = new List<Workshop_Registration__c>();

        for (Workshop_Registration__c reg : newList) {
            String oldStatus = oldMap.get(reg.Id).Status__c;

            if (reg.Status__c == 'Registered' && oldStatus != 'Registered') {
                newlyRegistered.add(reg);
            }
            if (reg.Status__c == 'Not Registered'
                && (oldStatus == 'Registered' || oldStatus == 'Waitlisted')) {
                newlyCancelled.add(reg);
            }
        }

        if (!newlyRegistered.isEmpty()) {
            createAttendanceRecords(newlyRegistered);
        }

        if (!newlyCancelled.isEmpty()) {
            deleteAttendanceRecords(newlyCancelled);
            promoteWaitlistedRegistrations(newlyCancelled);
        }

        if (!newlyRegistered.isEmpty() || !newlyCancelled.isEmpty()) {
            updateBatchRegisteredCounts(newList, oldMap, true);
            updateWorkshopTotals(newList);
        }
    }

    // ── Private helpers ──────────────────────────────────────────────────────────

    private static void deleteAttendanceRecords(List<Workshop_Registration__c> regs) {
        Set<Id> regIds = new Set<Id>();
        for (Workshop_Registration__c reg : regs) {
            regIds.add(reg.Id);
        }
        
        if (regIds.isEmpty()) return;
        
        List<Workshop_Attendance__c> attendanceToDelete = [
            SELECT Id
            FROM Workshop_Attendance__c
            WHERE Workshop_Registration__c IN :regIds
        ];
        
        if (!attendanceToDelete.isEmpty()) {
            delete attendanceToDelete;
        }
    }

    private static void createAttendanceRecords(List<Workshop_Registration__c> regs) {
        // Step 1: Collect workshop IDs and batch labels from registrations
        Set<Id> workshopIds = new Set<Id>();
        Set<String> batchLabels = new Set<String>();
        Map<String, List<Workshop_Registration__c>> keyToRegs = new Map<String, List<Workshop_Registration__c>>();
        
        for (Workshop_Registration__c reg : regs) {
            if (reg.Workshop__c == null || String.isBlank(reg.Batch_Label__c)) continue;
            
            workshopIds.add(reg.Workshop__c);
            batchLabels.add(reg.Batch_Label__c);
            
            String key = reg.Workshop__c + '_' + reg.Batch_Label__c;
            if (!keyToRegs.containsKey(key)) {
                keyToRegs.put(key, new List<Workshop_Registration__c>());
            }
            keyToRegs.get(key).add(reg);
        }
        
        if (workshopIds.isEmpty()) return;

        // Step 2: Query ALL non-cancelled batches across all sessions matching workshop + label
        Map<String, List<Workshop_Batch__c>> keyToBatches = new Map<String, List<Workshop_Batch__c>>();
        
        for (Workshop_Batch__c b : [
            SELECT Id, Batch_Label__c, Workshop_Session__c, Workshop_Session__r.Workshop__c
            FROM Workshop_Batch__c
            WHERE Workshop_Session__r.Workshop__c IN :workshopIds
            AND Batch_Label__c IN :batchLabels
            AND Status__c != 'Cancelled'
        ]) {
            String key = b.Workshop_Session__r.Workshop__c + '_' + b.Batch_Label__c;
            if (!keyToBatches.containsKey(key)) {
                keyToBatches.put(key, new List<Workshop_Batch__c>());
            }
            keyToBatches.get(key).add(b);
        }

        // Step 3: Duplicate guard — track existing (registrationId, batchId) pairs
        Set<Id> regIds = new Set<Id>();
        for (Workshop_Registration__c reg : regs) regIds.add(reg.Id);

        Set<String> existing = new Set<String>(); // regId_batchId
        for (Workshop_Attendance__c att : [
            SELECT Workshop_Registration__c, Workshop_Batch__c
            FROM Workshop_Attendance__c
            WHERE Workshop_Registration__c IN :regIds
        ]) {
            existing.add(att.Workshop_Registration__c + '_' + att.Workshop_Batch__c);
        }

        // Step 4: For each registration, create one attendance per matching batch
        //         (one per session that has a batch with the matching label)
        List<Workshop_Attendance__c> toInsert = new List<Workshop_Attendance__c>();
        
        for (String key : keyToRegs.keySet()) {
            List<Workshop_Registration__c> registrations = keyToRegs.get(key);
            List<Workshop_Batch__c> batches = keyToBatches.get(key);
            
            if (batches == null || batches.isEmpty()) continue;
            
            for (Workshop_Registration__c reg : registrations) {
                for (Workshop_Batch__c batch : batches) {
                    String dupKey = reg.Id + '_' + batch.Id;
                    if (existing.contains(dupKey)) continue;
                    existing.add(dupKey); // Prevent duplicates within this transaction
                    
                    toInsert.add(new Workshop_Attendance__c(
                        Workshop_Batch__c        = batch.Id,
                        Student__c               = reg.Student__c,
                        Program_Enrollment__c    = reg.Program_Enrollment__c,
                        Workshop__c              = reg.Workshop__c,
                        Workshop_Session__c      = batch.Workshop_Session__c,
                        Workshop_Registration__c = reg.Id,
                        Attendance_Status__c     = 'Pending'
                    ));
                }
            }
        }

        if (!toInsert.isEmpty()) {
            insert toInsert;
        }
    }

    private static void updateBatchRegisteredCounts(
        List<Workshop_Registration__c> regs,
        Map<Id, Workshop_Registration__c> oldMap,
        Boolean isUpdate
    ) {
        // Since registrations no longer have direct batch lookup,
        // we need to find affected batches through attendance records
        Set<Id> regIds = new Set<Id>();
        Set<Id> workshopIds = new Set<Id>();
        Set<String> batchLabels = new Set<String>();
        
        for (Workshop_Registration__c reg : regs) {
            regIds.add(reg.Id);
            if (reg.Workshop__c != null) workshopIds.add(reg.Workshop__c);
            if (!String.isBlank(reg.Batch_Label__c)) batchLabels.add(reg.Batch_Label__c);
        }
        
        if (workshopIds.isEmpty()) return;

        // Query all batches that match the workshops and labels of these registrations
        Set<Id> batchIds = new Set<Id>();
        for (Workshop_Batch__c b : [
            SELECT Id
            FROM Workshop_Batch__c
            WHERE Workshop_Session__r.Workshop__c IN :workshopIds
            AND Batch_Label__c IN :batchLabels
        ]) {
            batchIds.add(b.Id);
        }
        
        if (batchIds.isEmpty()) return;

        // Count unique registrations per batch by querying attendance records
        // and deduplicating registration IDs
        Map<Id, Set<Id>> batchToRegIds = new Map<Id, Set<Id>>();
        for (Workshop_Attendance__c att : [
            SELECT Workshop_Batch__c, Workshop_Registration__c,
                   Workshop_Registration__r.Status__c
            FROM Workshop_Attendance__c
            WHERE Workshop_Batch__c IN :batchIds
            AND Workshop_Registration__r.Status__c IN ('Registered', 'Waitlisted')
        ]) {
            if (!batchToRegIds.containsKey(att.Workshop_Batch__c)) {
                batchToRegIds.put(att.Workshop_Batch__c, new Set<Id>());
            }
            batchToRegIds.get(att.Workshop_Batch__c).add(att.Workshop_Registration__c);
        }

        Map<Id, Integer> countMap = new Map<Id, Integer>();
        for (Id bId : batchToRegIds.keySet()) {
            countMap.put(bId, batchToRegIds.get(bId).size());
        }

        List<Workshop_Batch__c> toUpdate = new List<Workshop_Batch__c>();
        for (Id bId : batchIds) {
            toUpdate.add(new Workshop_Batch__c(
                Id                  = bId,
                Total_Registered__c = countMap.containsKey(bId) ? countMap.get(bId) : 0
            ));
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    private static void updateWorkshopTotals(List<Workshop_Registration__c> regs) {
        Set<Id> workshopIds = new Set<Id>();
        for (Workshop_Registration__c reg : regs) {
            if (reg.Workshop__c != null) workshopIds.add(reg.Workshop__c);
        }
        if (workshopIds.isEmpty()) return;

        Map<Id, Integer> countMap = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Workshop__c wId, COUNT(Id) cnt
            FROM Workshop_Registration__c
            WHERE Workshop__c IN :workshopIds
            AND Status__c IN ('Registered', 'Waitlisted')
            GROUP BY Workshop__c
        ]) {
            countMap.put((Id) ar.get('wId'), Integer.valueOf(ar.get('cnt')));
        }

        List<Workshop__c> toUpdate = new List<Workshop__c>();
        for (Id wId : workshopIds) {
            toUpdate.add(new Workshop__c(
                Id                      = wId,
                Total_Registrations__c  = countMap.containsKey(wId) ? countMap.get(wId) : 0
            ));
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    private static void promoteWaitlistedRegistrations(
        List<Workshop_Registration__c> cancelledRegs
    ) {
        // Collect workshop + label combinations from cancelled registrations
        Set<Id> workshopIds = new Set<Id>();
        Set<String> batchLabels = new Set<String>();
        Map<String, Boolean> workshopLabelKeys = new Map<String, Boolean>();
        
        for (Workshop_Registration__c reg : cancelledRegs) {
            if (reg.Workshop__c != null && !String.isBlank(reg.Batch_Label__c)) {
                workshopIds.add(reg.Workshop__c);
                batchLabels.add(reg.Batch_Label__c);
                workshopLabelKeys.put(reg.Workshop__c + '_' + reg.Batch_Label__c, true);
            }
        }
        
        if (workshopIds.isEmpty()) return;

        // Query all batches matching these workshop + label combinations
        Map<String, List<Workshop_Batch__c>> keyToBatches = new Map<String, List<Workshop_Batch__c>>();
        for (Workshop_Batch__c b : [
            SELECT Id, Capacity__c, Total_Registered__c, Batch_Label__c,
                   Workshop_Session__r.Workshop__c
            FROM Workshop_Batch__c
            WHERE Workshop_Session__r.Workshop__c IN :workshopIds
            AND Batch_Label__c IN :batchLabels
        ]) {
            String key = b.Workshop_Session__r.Workshop__c + '_' + b.Batch_Label__c;
            if (!workshopLabelKeys.containsKey(key)) continue;
            
            if (!keyToBatches.containsKey(key)) {
                keyToBatches.put(key, new List<Workshop_Batch__c>());
            }
            keyToBatches.get(key).add(b);
        }

        List<Workshop_Registration__c> toPromote = new List<Workshop_Registration__c>();

        // For each workshop + label combination, check if there are open seats
        for (String key : keyToBatches.keySet()) {
            List<Workshop_Batch__c> batches = keyToBatches.get(key);
            
            // Calculate total capacity and current registrations across all matching batches
            Decimal totalCapacity = 0;
            Decimal totalRegistered = 0;
            Boolean hasUnlimitedCapacity = false;
            
            for (Workshop_Batch__c b : batches) {
                if (b.Capacity__c == null) {
                    hasUnlimitedCapacity = true;
                    break;
                }
                totalCapacity += b.Capacity__c;
                totalRegistered += (b.Total_Registered__c != null ? b.Total_Registered__c : 0);
            }
            
            if (hasUnlimitedCapacity) continue; // No promotion needed for unlimited capacity
            
            Integer openSeats = Integer.valueOf(totalCapacity - totalRegistered);
            if (openSeats <= 0) continue;

            // Parse key to get workshop ID and batch label
            List<String> parts = key.split('_');
            if (parts.size() < 2) continue;
            Id wId = parts[0];
            String label = key.substring(parts[0].length() + 1); // Get everything after workshopId_

            // Find the oldest Waitlisted registrations for this workshop + label combination
            List<Workshop_Registration__c> waitlisted = [
                SELECT Id, Status__c
                FROM Workshop_Registration__c
                WHERE Workshop__c = :wId
                AND Batch_Label__c = :label
                AND Status__c = 'Waitlisted'
                ORDER BY Registration_Date__c ASC, CreatedDate ASC
                LIMIT :openSeats
            ];

            for (Workshop_Registration__c w : waitlisted) {
                w.Status__c = 'Registered';
                toPromote.add(w);
            }
        }

        if (!toPromote.isEmpty()) {
            update toPromote;

            // Send promotion confirmation email + in-app notification asynchronously
            Set<Id> promotedIds = new Set<Id>();
            for (Workshop_Registration__c r : toPromote) promotedIds.add(r.Id);
            WorkshopNotificationService.sendPromotionConfirmations(promotedIds);
        }
    }
}