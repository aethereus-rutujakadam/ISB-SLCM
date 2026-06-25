public with sharing class ISBContactTriggerHandler {

    private static Boolean isRunning = false;

    public static void beforeUpdate(List<Contact> newList, Map<Id, Contact> oldMap) {
        // Default behavior: respect ISBUserContext
        if (isRunning) {
            System.debug('ISBContactTriggerHandler.beforeUpdate is already running. Exiting to prevent recursion.');
            return;
        }
        isRunning = true;
        try {
            System.debug('Checking if the current user is an external user.');
            if (!ISBUserContext.isExternalUser()) {
                System.debug('Current user is NOT an external user. Skiping external validation.');
                return;
            }
            System.debug('Current user is an external user. Proceeding with beforeUpdate processing.');
            processBeforeUpdate(newList, oldMap);
        } finally {
            isRunning = false;
        }
    }

    /**
     * Test-friendly overload to force the external-user branch.
     * Call with forceExternal=true from tests to execute the loop and addError paths.
     */
    public static void beforeUpdate(List<Contact> newList, Map<Id, Contact> oldMap, Boolean forceExternal) {
        if (isRunning) return;
        isRunning = true;
        try {
            if (!forceExternal && !ISBUserContext.isExternalUser()) return;
            processBeforeUpdate(newList, oldMap);
        } finally {
            isRunning = false;
        }
    }

    // Extracted logic for easier testing and reuse
    private static void processBeforeUpdate(List<Contact> newList, Map<Id, Contact> oldMap) {
        System.debug('Starting processBeforeUpdate validation for ' + newList.size() + ' Contact records.');
        for (Contact cNew : newList) {
            Contact cOld = oldMap.get(cNew.Id);
            if (cOld == null) continue;

            // Block if name-related fields changed
            Boolean salutationChanged = (cNew.Salutation != cOld.Salutation);
            Boolean firstChanged = (cNew.FirstName != cOld.FirstName);
            Boolean middleChanged = (cNew.MiddleName != cOld.MiddleName);
            Boolean lastChanged  = (cNew.LastName  != cOld.LastName);

            if (salutationChanged || firstChanged || middleChanged || lastChanged) {
                System.debug('Validation Failed: Name-related fields were changed for Contact ID: ' + cNew.Id);
                cNew.addError('You cannot change name-related fields (Salutation, First Name, Middle Name, Last Name) from the Experience Portal. Please contact support.');
            }
        }
        System.debug('Completed processBeforeUpdate validation safely.');
    }
    
    public static void afterUpdate(List<Contact> newList, Map<Id, Contact> oldMap) {
        System.debug('Starting afterUpdate logic for user provisioning. Checking ' + newList.size() + ' Contacts.');
        Set<Id> aaContactIdsToProcess = new Set<Id>();
        Set<Id> advisorContactIdsToProcess = new Set<Id>();
        Map<Id, Boolean> advisorUserStatusByUserId = new Map<Id, Boolean>();
        
        // Get Record Type IDs
        Id academicAssociateRTId = null;
        Id advisorRTId = null;
        Map<String, Schema.RecordTypeInfo> rtMap = Schema.SObjectType.Contact.getRecordTypeInfosByName();
        Map<String, Schema.RecordTypeInfo> rtDeveloperMap = Schema.SObjectType.Contact.getRecordTypeInfosByDeveloperName();
        
        if (rtMap.containsKey('Academic Associate')) {
            academicAssociateRTId = rtMap.get('Academic Associate').getRecordTypeId();
            System.debug('Found "Academic Associate" Record Type ID: ' + academicAssociateRTId);
        } else if (rtDeveloperMap.containsKey('Academic_Associate')) {
            academicAssociateRTId = rtDeveloperMap.get('Academic_Associate').getRecordTypeId();
            System.debug('Found "Academic_Associate" Record Type ID by developer name: ' + academicAssociateRTId);
        } else {
            System.debug('WARNING: "Academic Associate" Record Type could not be found.');
        }
        
        if (rtMap.containsKey('Advisor')) {
            advisorRTId = rtMap.get('Advisor').getRecordTypeId();
            System.debug('Found "Advisor" Record Type ID: ' + advisorRTId);
        } else if (rtDeveloperMap.containsKey('Advisor')) {
            advisorRTId = rtDeveloperMap.get('Advisor').getRecordTypeId();
            System.debug('Found "Advisor" Record Type ID by developer name: ' + advisorRTId);
        } else {
            System.debug('WARNING: "Advisor" Record Type could not be found.');
        }

        for (Contact con : newList) {
            Contact oldCon = oldMap.get(con.Id);

            Boolean activeChangedToActive =
                con.Active_Status__c == 'Active' &&
                (oldCon != null && oldCon.Active_Status__c != 'Active');

            Boolean linkedUserBlank = String.isBlank(con.Linked_User_Id__c);
            Boolean statusChanged = (oldCon != null && con.Active_Status__c != oldCon.Active_Status__c);
            
            Boolean isAcademicAssociate = (academicAssociateRTId != null && con.RecordTypeId == academicAssociateRTId);
            Boolean isAdvisor = (advisorRTId != null && con.RecordTypeId == advisorRTId);

            System.debug('Evaluation for Contact ID: ' + con.Id);
            System.debug(' -> activeChangedToActive: ' + activeChangedToActive + 
                         ' (New Status: ' + con.Active_Status__c + 
                         ', Old Status: ' + (oldCon != null ? oldCon.Active_Status__c : 'N/A') + ')');
            System.debug(' -> linkedUserBlank: ' + linkedUserBlank + 
                         ' (Linked_User_Id__c: ' + con.Linked_User_Id__c + ')');
            System.debug(' -> statusChanged: ' + statusChanged);
            System.debug(' -> isAcademicAssociate: ' + isAcademicAssociate);
            System.debug(' -> isAdvisor: ' + isAdvisor + 
                         ' (Actual RT: ' + con.RecordTypeId + 
                         ', Target RT: ' + advisorRTId + ')');

            if (activeChangedToActive && linkedUserBlank && isAcademicAssociate) {
                System.debug('Contact Match Found! ID: ' + con.Id + ' meets User Provisioning criteria (Academic Associate, Activated, Unlinked).');
                aaContactIdsToProcess.add(con.Id);
            }
            
            if (activeChangedToActive && linkedUserBlank && isAdvisor) {
                System.debug('Contact Match Found! ID: ' + con.Id + ' meets User Provisioning criteria (Advisor, Activated, Unlinked).');
                advisorContactIdsToProcess.add(con.Id);
            }

            if (statusChanged && !linkedUserBlank && isAdvisor) {
                try {
                    Id linkedUserId = (Id) con.Linked_User_Id__c;
                    Boolean shouldBeActive = (con.Active_Status__c == 'Active');

                    if (advisorUserStatusByUserId.containsKey(linkedUserId)) {
                        // If conflicting statuses are requested in the same transaction, inactive wins.
                        advisorUserStatusByUserId.put(
                            linkedUserId,
                            advisorUserStatusByUserId.get(linkedUserId) && shouldBeActive
                        );
                    } else {
                        advisorUserStatusByUserId.put(linkedUserId, shouldBeActive);
                    }

                    System.debug('Advisor linked User ' + linkedUserId + ' queued for IsActive=' + shouldBeActive);
                } catch (Exception e) {
                    System.debug('Invalid Linked_User_Id__c on Contact ' + con.Id + ': ' + con.Linked_User_Id__c + '. Error: ' + e.getMessage());
                }
            }
        }

        if (!aaContactIdsToProcess.isEmpty()) {
            System.debug('Enqueuing ISBContactUserProvisioningSetupQueue for ' + aaContactIdsToProcess.size() + ' Academic Associate Contacts.');
            System.enqueueJob(new ISBContactUserProvisioningSetupQueue(aaContactIdsToProcess, UserInfo.getUserId()));
        }
        
        if (!advisorContactIdsToProcess.isEmpty()) {
            System.debug('Enqueuing AdvisorUserProvisioningSetupQueue for ' + advisorContactIdsToProcess.size() + ' Advisor Contacts.');
            System.enqueueJob(new AdvisorUserProvisioningSetupQueue(advisorContactIdsToProcess, UserInfo.getUserId()));
        }

        if (!advisorUserStatusByUserId.isEmpty()) {
            System.debug('Enqueuing AdvisorUserStatusSyncQueue for ' + advisorUserStatusByUserId.size() + ' linked Advisor users.');
            System.enqueueJob(new AdvisorUserStatusSyncQueue(advisorUserStatusByUserId));
        }
        
        if (aaContactIdsToProcess.isEmpty() && advisorContactIdsToProcess.isEmpty() && advisorUserStatusByUserId.isEmpty()) {
            System.debug('No Contacts met the criteria for User Provisioning in this transaction.');
        }
    }
    public static void handleBeforeDelete(List<Contact> oldContacts) {
        // Step 1: Collect Contact IDs being deleted
        Set<Id> contactIds = new Set<Id>();
        for (Contact con : oldContacts) {
            contactIds.add(con.Id);
        }

        // Step 2: Query related Active AA Profiles
        Map<Id, Boolean> contactHasActiveAAProfile = new Map<Id, Boolean>();

        for (AA_Profile__c aa : [
            SELECT Id, Academic_Associate__c
            FROM AA_Profile__c
            WHERE Academic_Associate__c IN :contactIds
            AND Status__c = 'Active'
        ]) {
            contactHasActiveAAProfile.put(aa.Academic_Associate__c, true);
        }

        // Step 3: Check each Contact before deletion
        for (Contact con : oldContacts) {

            Boolean isAcademicAssociate = 
                con.RecordTypeId != null &&
                Schema.SObjectType.Contact
                    .getRecordTypeInfosById()
                    .get(con.RecordTypeId)
                    .getDeveloperName() == 'Academic_Associate';

            Boolean isContactActive = (con.Active_Status__c == 'Active');

            Boolean hasActiveAAProfile = contactHasActiveAAProfile.containsKey(con.Id);

            if ((isAcademicAssociate && isContactActive) || hasActiveAAProfile) {
                con.addError(
                    'Cannot delete Academic Associate. ' +
                    'Either the Contact status or a related AA Profile is Active. ' +
                    'Please deactivate before deletion.'
                );
            }
        }
    }
}