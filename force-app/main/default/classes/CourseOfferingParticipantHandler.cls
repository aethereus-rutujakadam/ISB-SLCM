public class CourseOfferingParticipantHandler {

    public static void preventDuplicateParticipants(
        List<CourseOfferingParticipant> newList,
        Map<Id, CourseOfferingParticipant> oldMap
    ) {
        // Collect pairs we need to validate
        Set<Id> offeringIds = new Set<Id>();
        Set<Id> contactIds  = new Set<Id>();

        // Map: "offeringId-contactId" -> record (for error marking)
        Map<String, CourseOfferingParticipant> keyToRecord = new Map<String, CourseOfferingParticipant>();

        for (CourseOfferingParticipant cop : newList) {
            if (cop.CourseOfferingId == null || cop.ParticipantContactId  == null) continue;

            // If update and neither field changed, skip extra validation
            if (oldMap != null && oldMap.containsKey(cop.Id)) {
                CourseOfferingParticipant oldRec = oldMap.get(cop.Id);
                if (oldRec.CourseOfferingId == cop.CourseOfferingId &&
                    oldRec.ParticipantContactId  == cop.ParticipantContactId ) {
                    continue;
                }
            }

            offeringIds.add(cop.CourseOfferingId);
            contactIds.add(cop.ParticipantContactId );

            String key = cop.CourseOfferingId + '-' + cop.ParticipantContactId ;
            // If duplicates are already in the same transaction (same save), catch them too
            if (keyToRecord.containsKey(key)) {
                cop.addError('This Contact is already added as a participant for this Course Offering.');
            } else {
                keyToRecord.put(key, cop);
            }
        }

        if (keyToRecord.isEmpty()) return;

        // Query existing participants for those offerings + contacts
        List<CourseOfferingParticipant> existing = [
            SELECT Id, CourseOfferingId, ParticipantContactId 
            FROM CourseOfferingParticipant
            WHERE CourseOfferingId IN :offeringIds
              AND ParticipantContactId IN :contactIds
        ];

        Set<String> existingKeys = new Set<String>();
        for (CourseOfferingParticipant ex : existing) {
            existingKeys.add(ex.CourseOfferingId + '-' + ex.ParticipantContactId);
        }

        // Mark error if already exists in DB
        for (String key : keyToRecord.keySet()) {
            if (existingKeys.contains(key)) {
                keyToRecord.get(key).addError(
                    'Duplicate participant: this Contact is already a participant for this Course.'
                );
            }
        }
    }

    public static void markPendingOnChanges(
        List<CourseOfferingParticipant> newList,
        Map<Id, CourseOfferingParticipant> oldMap,
        Boolean isInsert
    ) {
        if (isInsert) {
            for (CourseOfferingParticipant cop : newList) {
                if (String.isNotBlank(cop.Section_Name__c) && cop.LMS_Sync_Status__c != 'Success') {
                    cop.LMS_Sync_Status__c = 'Pending';
                }
            }
        } else {
            for (CourseOfferingParticipant cop : newList) {
                CourseOfferingParticipant oldCop = oldMap.get(cop.Id);
                if (cop.Section_Name__c != oldCop.Section_Name__c || cop.ParticipantContactId != oldCop.ParticipantContactId) {
                    cop.LMS_Sync_Status__c = 'Pending';
                }
            }
        }
    }

    /**
     * @description Handles course checklist creation after CourseOfferingParticipant insert
     * Delegates to ChecklistEngineService for automated checklist generation
     * @param newMap Map of newly inserted CourseOfferingParticipant records
     */
    public static void handleCourseChecklistCreation(Map<Id, CourseOfferingParticipant> newMap) {
        if (newMap == null || newMap.isEmpty()) {
            return;
        }
        
        // Filter for enrolled participants with valid data
        Set<Id> eligibleCopIds = new Set<Id>();
        
        for (CourseOfferingParticipant cop : newMap.values()) {
            // Only process if status is Enrolled and required fields are populated
            if (cop.ParticipationStatus == 'Enrolled' 
                && cop.ParticipantContactId != null 
                && cop.CourseOfferingId != null) {
                eligibleCopIds.add(cop.Id);
            }
        }
        
        // Call service to create course checklists
        if (!eligibleCopIds.isEmpty()) {
            ChecklistEngineService.createCourseChecklists(eligibleCopIds);
        }
    }
}