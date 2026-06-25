public without sharing class CourseAAAssignmentHandler {

    /**
     * @description Handles an after insert event for AA assignments.
     */
    public static void handleAfterInsert(List<Course_AA_Assignment__c> newList) {
        List<Course_AA_Assignment__c> assignmentsToAdd = new List<Course_AA_Assignment__c>();
        for (Course_AA_Assignment__c aa : newList) {
            if (aa.Is_Active__c) {
                assignmentsToAdd.add(aa);
            }
        }
        if (!assignmentsToAdd.isEmpty()) {
            addSharingForAssignments(assignmentsToAdd);
        }
    }

    /**
     * @description Handles an after update event for AA assignments.
     */
    public static void handleAfterUpdate(List<Course_AA_Assignment__c> newList, Map<Id, Course_AA_Assignment__c> oldMap) {
        List<Course_AA_Assignment__c> assignmentsToAdd = new List<Course_AA_Assignment__c>();
        List<Course_AA_Assignment__c> assignmentsToRemove = new List<Course_AA_Assignment__c>();

        for (Course_AA_Assignment__c aa : newList) {
            Course_AA_Assignment__c oldAa = oldMap.get(aa.Id);
            if (aa.Is_Active__c && !oldAa.Is_Active__c) {
                assignmentsToAdd.add(aa);
            } else if (!aa.Is_Active__c && oldAa.Is_Active__c) {
                assignmentsToRemove.add(aa);
            }
        }

        if (!assignmentsToAdd.isEmpty()) {
            addSharingForAssignments(assignmentsToAdd);
        }
        if (!assignmentsToRemove.isEmpty()) {
            removeSharingForAssignments(assignmentsToRemove);
        }
    }

    /**
     * @description Handles an after delete event for AA assignments.
     */
    public static void handleAfterDelete(List<Course_AA_Assignment__c> oldList) {
        List<Course_AA_Assignment__c> assignmentsToRemove = new List<Course_AA_Assignment__c>();
        for (Course_AA_Assignment__c aa : oldList) {
            if (aa.Is_Active__c) {
                assignmentsToRemove.add(aa);
            }
        }
        if (!assignmentsToRemove.isEmpty()) {
            removeSharingForAssignments(assignmentsToRemove);
        }
    }

    /**
     * @description Adds sharing to Active Course Checklists when AA is added.
     */
    private static void addSharingForAssignments(List<Course_AA_Assignment__c> assignments) {
        System.debug('### CourseAAAssignmentHandler: addSharingForAssignments starting with ' + assignments.size() + ' records.');
        Map<Id, Set<Id>> offeringToUserIds = getOfferingToUserIds(assignments);
        if (offeringToUserIds.isEmpty()) {
            System.debug('### offeringToUserIds is empty. Escaping early.');
            return;
        }

        System.debug('### offeringToUserIds: ' + offeringToUserIds);

        // Find active checklists for these offerings
        List<Course_Checklist__c> activeChecklists = [
            SELECT Id, Course_Offering__c 
            FROM Course_Checklist__c 
            WHERE Course_Offering__c IN :offeringToUserIds.keySet() 
              AND Status__c = 'Active'
        ];
        
        System.debug('### Found ' + activeChecklists.size() + ' active checklists for these offerings.');

        List<Course_Checklist__Share> checklistSharesToInsert = new List<Course_Checklist__Share>();
        List<CourseOfferingShare> offeringSharesToInsert = new List<CourseOfferingShare>();

        // Add sharing for Course Offerings first
        for (Id offeringId : offeringToUserIds.keySet()) {
            for (Id userId : offeringToUserIds.get(offeringId)) {
                offeringSharesToInsert.add(new CourseOfferingShare(
                    ParentId = offeringId,
                    UserOrGroupId = userId,
                    AccessLevel = 'Read',
                    RowCause = Schema.CourseOfferingShare.RowCause.Manual
                ));
            }
        }

        for (Course_Checklist__c cl : activeChecklists) {
            if (offeringToUserIds.containsKey(cl.Course_Offering__c)) {
                for (Id userId : offeringToUserIds.get(cl.Course_Offering__c)) {
                    checklistSharesToInsert.add(new Course_Checklist__Share(
                        ParentId = cl.Id,
                        UserOrGroupId = userId,
                        AccessLevel = 'Read',
                        RowCause = Schema.Course_Checklist__Share.RowCause.Manual
                    ));
                }
            }
        }

        if (!offeringSharesToInsert.isEmpty()) {
            System.debug('### Attempting to insert ' + offeringSharesToInsert.size() + ' CourseOfferingShare records.');
            Database.SaveResult[] srList = Database.insert(offeringSharesToInsert, false);
            for(Database.SaveResult sr : srList) {
                if(!sr.isSuccess()) {
                    System.debug('### CourseOfferingShare Insert Error: ' + sr.getErrors()[0].getMessage() + ' Fields: ' + sr.getErrors()[0].getFields());
                } else {
                    System.debug('### Successfully inserted CourseOfferingShare: ' + sr.getId());
                }
            }
        }
        
        if (!checklistSharesToInsert.isEmpty()) {
            System.debug('### Attempting to insert ' + checklistSharesToInsert.size() + ' Course_Checklist__Share records.');
            Database.SaveResult[] srList = Database.insert(checklistSharesToInsert, false);
            for(Database.SaveResult sr : srList) {
                if(!sr.isSuccess()) {
                    System.debug('### Course_Checklist__Share Insert Error: ' + sr.getErrors()[0].getMessage() + ' Fields: ' + sr.getErrors()[0].getFields());
                } else {
                    System.debug('### Successfully inserted Course_Checklist__Share: ' + sr.getId());
                }
            }
        }
    }

    /**
     * @description Removes sharing from Course Checklists when AA is removed/deactivated.
     */
    private static void removeSharingForAssignments(List<Course_AA_Assignment__c> assignments) {
        Map<Id, Set<Id>> offeringToUserIds = getOfferingToUserIds(assignments);
        if (offeringToUserIds.isEmpty()) return;

        Set<Id> checklistIds = new Set<Id>();
        List<Course_Checklist__c> checklists = [
            SELECT Id, Course_Offering__c 
            FROM Course_Checklist__c 
            WHERE Course_Offering__c IN :offeringToUserIds.keySet()
        ];
        
        // Build map of ChecklistId to OfferingId to filter shares
        Map<Id, Id> checklistToOffering = new Map<Id, Id>();
        for (Course_Checklist__c cl : checklists) {
            checklistToOffering.put(cl.Id, cl.Course_Offering__c);
            checklistIds.add(cl.Id);
        }

        Set<Id> allUserIds = new Set<Id>();
        for (Set<Id> userIds : offeringToUserIds.values()) {
            allUserIds.addAll(userIds);
        }

        // 1. Delete Course Checklist Shares
        if (!checklistIds.isEmpty()) {
            List<Course_Checklist__Share> sharesToDelete = [
                SELECT Id, ParentId, UserOrGroupId 
                FROM Course_Checklist__Share 
                WHERE ParentId IN :checklistIds 
                  AND UserOrGroupId IN :allUserIds
                  AND RowCause = :Schema.Course_Checklist__Share.RowCause.Manual
            ];

            List<Course_Checklist__Share> actualSharesToDelete = new List<Course_Checklist__Share>();
            for (Course_Checklist__Share share : sharesToDelete) {
                Id offeringId = checklistToOffering.get(share.ParentId);
                if (offeringToUserIds.containsKey(offeringId)) {
                    if (offeringToUserIds.get(offeringId).contains(share.UserOrGroupId)) {
                        actualSharesToDelete.add(share);
                    }
                }
            }

            if (!actualSharesToDelete.isEmpty()) {
                Database.delete(actualSharesToDelete, false);
            }
        }
        
        // 2. Delete Course Offering Shares
        List<CourseOfferingShare> offeringSharesToDelete = [
            SELECT Id, ParentId, UserOrGroupId 
            FROM CourseOfferingShare 
            WHERE ParentId IN :offeringToUserIds.keySet() 
              AND UserOrGroupId IN :allUserIds
              AND RowCause = :Schema.CourseOfferingShare.RowCause.Manual
        ];
        
        List<CourseOfferingShare> actualOfferingSharesToDelete = new List<CourseOfferingShare>();
        for (CourseOfferingShare share : offeringSharesToDelete) {
             if (offeringToUserIds.containsKey(share.ParentId)) {
                if (offeringToUserIds.get(share.ParentId).contains(share.UserOrGroupId)) {
                    actualOfferingSharesToDelete.add(share);
                }
            }
        }
        
        if (!actualOfferingSharesToDelete.isEmpty()) {
            Database.delete(actualOfferingSharesToDelete, false);
        }
    }

    /**
     * @description Maps Course Offering ID to a set of User IDs derived from AA Assignments.
     */
    private static Map<Id, Set<Id>> getOfferingToUserIds(List<Course_AA_Assignment__c> assignments) {
        Set<Id> aaProfileIds = new Set<Id>();
        for (Course_AA_Assignment__c aa : assignments) {
            if (aa.Academic_Associate__c != null) {
                aaProfileIds.add(aa.Academic_Associate__c);
            }
        }

        Map<Id, Id> profileToUserId = new Map<Id, Id>();
        if (!aaProfileIds.isEmpty()) {
            for (AA_Profile__c profile : [
                SELECT Id, Academic_Associate__r.Linked_User_Id__c 
                FROM AA_Profile__c 
                WHERE Id IN :aaProfileIds 
                  AND Academic_Associate__r.Linked_User_Id__c != null
            ]) {
                profileToUserId.put(profile.Id, profile.Academic_Associate__r.Linked_User_Id__c);
            }
        }

        Map<Id, Set<Id>> offeringToUserIds = new Map<Id, Set<Id>>();
        for (Course_AA_Assignment__c aa : assignments) {
            if (aa.Course_Offering__c != null && aa.Academic_Associate__c != null) {
                Id userId = profileToUserId.get(aa.Academic_Associate__c);
                if (userId != null) {
                    if (!offeringToUserIds.containsKey(aa.Course_Offering__c)) {
                        offeringToUserIds.put(aa.Course_Offering__c, new Set<Id>());
                    }
                    offeringToUserIds.get(aa.Course_Offering__c).add(userId);
                }
            }
        }

        return offeringToUserIds;
    }
}