/**
 * @description Handler for sharing Course Checklist and updating Items when Checklist is activated.
 * Academic Associates (AAs) get Read access to the Checklist header and Edit access to the Items.
 * Sharing is triggered only when the Course Checklist Status is set to 'Active'.
 */
public without sharing class CourseChecklistSharingHandler {
    
    /**
     * @description Handles Checklist activation logic: sharing and item status updates.
     * @param newList Trigger.new
     * @param oldMap Trigger.oldMap
     */
    public static void handleChecklistAfterUpdate(List<Course_Checklist__c> newList, Map<Id, Course_Checklist__c> oldMap) {
        List<Course_Checklist__c> activatedChecklists = new List<Course_Checklist__c>();
        
        for (Course_Checklist__c cl : newList) {
            Course_Checklist__c oldCl = oldMap != null ? oldMap.get(cl.Id) : null;
            
            // Check if status changed to 'Active' or if it was inserted as 'Active'
            Boolean isNowActive = (cl.Status__c == 'Active' && (oldCl == null || oldCl.Status__c != 'Active'));
            
            if (isNowActive) {
                activatedChecklists.add(cl);
            }
        }
        
        if (!activatedChecklists.isEmpty()) {
            activateChecklists(activatedChecklists);
        }
    }

    /**
     * @description Orchestrates the activation process for a list of checklists.
     * @param checklists List of checklists being activated.
     */
    private static void activateChecklists(List<Course_Checklist__c> checklists) {
        Set<Id> checklistIds = new Map<Id, Course_Checklist__c>(checklists).keySet();
        
        // 1. Update related Checklist Items to 'In Progress'
        updateItemsToInProgress(checklistIds);
        
        // 2. Create sharing records for Academic Associates
        shareChecklist(checklists);
    }

    /**
     * @description Updates all items related to the given checklists to 'In Progress'.
     * @param checklistIds Set of Checklist IDs.
     */
    private static void updateItemsToInProgress(Set<Id> checklistIds) {
        List<Course_Checklist_Item__c> itemsToUpdate = [
            SELECT Id, Status__c 
            FROM Course_Checklist_Item__c 
            WHERE Course_Checklist__c IN :checklistIds 
              AND Status__c != 'In Progress'
        ];
        
        if (!itemsToUpdate.isEmpty()) {
            for (Course_Checklist_Item__c item : itemsToUpdate) {
                item.Status__c = 'In Progress';
            }
            update itemsToUpdate;
        }
    }

    /**
     * @description Shares Course Checklist records with Academic Associates.
     * @param checklists List of Checklist records to share.
     */
    public static void shareChecklist(List<Course_Checklist__c> checklists) {
        Set<Id> offeringIds = new Set<Id>();
        for (Course_Checklist__c cl : checklists) {
            if (cl.Course_Offering__c != null) {
                offeringIds.add(cl.Course_Offering__c);
            }
        }
        
        if (offeringIds.isEmpty()) return;
        
        Map<Id, List<Id>> offeringToUserIds = getOfferingToUserIds(offeringIds);
        List<Course_Checklist__Share> checklistSharesToInsert = new List<Course_Checklist__Share>();
        List<CourseOfferingShare> offeringSharesToInsert = new List<CourseOfferingShare>();
        
        // Add course offering shares
        for (Id offeringId : offeringIds) {
            if (offeringToUserIds.containsKey(offeringId)) {
                for (Id userId : offeringToUserIds.get(offeringId)) {
                    offeringSharesToInsert.add(new CourseOfferingShare(
                        ParentId = offeringId,
                        UserOrGroupId = userId,
                        AccessLevel = 'Read',
                        RowCause = Schema.CourseOfferingShare.RowCause.Manual
                    ));
                }
            }
        }
        
        // Add checklist shares
        for (Course_Checklist__c cl : checklists) {
            if (cl.Course_Offering__c != null && offeringToUserIds.containsKey(cl.Course_Offering__c)) {
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
            Database.insert(offeringSharesToInsert, false);
        }

        if (!checklistSharesToInsert.isEmpty()) {
            Database.insert(checklistSharesToInsert, false);
        }
    }

    /**
     * @description Helper to get active Academic Associates' User IDs.
     */
    private static Map<Id, List<Id>> getOfferingToUserIds(Set<Id> offeringIds) {
        Map<Id, List<Id>> resultMap = new Map<Id, List<Id>>();
        
        List<Course_AA_Assignment__c> assignments = [
            SELECT Course_Offering__c, 
                   Academic_Associate__r.Academic_Associate__r.Linked_User_Id__c 
            FROM Course_AA_Assignment__c 
            WHERE Course_Offering__c IN :offeringIds 
              AND Is_Active__c = true
              AND Academic_Associate__r.Academic_Associate__r.Linked_User_Id__c != null
        ];
        
        for (Course_AA_Assignment__c aa : assignments) {
            Id userId = aa.Academic_Associate__r.Academic_Associate__r.Linked_User_Id__c;
            if (!resultMap.containsKey(aa.Course_Offering__c)) {
                resultMap.put(aa.Course_Offering__c, new List<Id>());
            }
            resultMap.get(aa.Course_Offering__c).add(userId);
        }
        
        return resultMap;
    }
}