public with sharing class ProgramEnrollmentAdvisorSharingService {

    public class ShareRequest {
        @InvocableVariable(required=true)
        public Id programEnrollmentId;

        @InvocableVariable
        public Id studentContactId;

        @InvocableVariable
        public Id oldAdvisorContactId;

        @InvocableVariable
        public Id newAdvisorContactId;

        @InvocableVariable
        public Boolean isActive;
    }

    @InvocableMethod(
        label='Sync Advisor Shares for Enrollment'
        description='Creates/removes Manual shares on Contact and ProgramEnrollment when Primary Advisor changes.'
    )
    public static void syncAdvisorShares(List<ShareRequest> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }

        Map<Id, Id> advisorContactToUserId = getAdvisorUserMap(requests);

        Set<String> contactDeleteKeys = new Set<String>();
        Set<String> contactCreateKeys = new Set<String>();
        Set<String> enrollmentDeleteKeys = new Set<String>();
        Set<String> enrollmentCreateKeys = new Set<String>();

        Set<Id> contactDeleteParentIds = new Set<Id>();
        Set<Id> contactCreateParentIds = new Set<Id>();
        Set<Id> enrollmentDeleteParentIds = new Set<Id>();
        Set<Id> enrollmentCreateParentIds = new Set<Id>();

        Set<Id> deleteUserIds = new Set<Id>();
        Set<Id> createUserIds = new Set<Id>();

        for (ShareRequest req : requests) {
            if (req == null || req.isActive != true) {
                continue;
            }

            Id oldAdvisorUserId = advisorContactToUserId.get(req.oldAdvisorContactId);
            Id newAdvisorUserId = advisorContactToUserId.get(req.newAdvisorContactId);

            if (req.studentContactId != null && oldAdvisorUserId != null) {
                contactDeleteParentIds.add(req.studentContactId);
                deleteUserIds.add(oldAdvisorUserId);
                contactDeleteKeys.add(buildKey(req.studentContactId, oldAdvisorUserId));
            }

            if (req.studentContactId != null && newAdvisorUserId != null) {
                contactCreateParentIds.add(req.studentContactId);
                createUserIds.add(newAdvisorUserId);
                contactCreateKeys.add(buildKey(req.studentContactId, newAdvisorUserId));
            }

            if (req.programEnrollmentId != null && oldAdvisorUserId != null) {
                enrollmentDeleteParentIds.add(req.programEnrollmentId);
                deleteUserIds.add(oldAdvisorUserId);
                enrollmentDeleteKeys.add(buildKey(req.programEnrollmentId, oldAdvisorUserId));
            }

            if (req.programEnrollmentId != null && newAdvisorUserId != null) {
                enrollmentCreateParentIds.add(req.programEnrollmentId);
                createUserIds.add(newAdvisorUserId);
                enrollmentCreateKeys.add(buildKey(req.programEnrollmentId, newAdvisorUserId));
            }
        }

        deleteContactShares(contactDeleteParentIds, deleteUserIds, contactDeleteKeys);
        createContactShares(contactCreateParentIds, createUserIds, contactCreateKeys);

        deleteProgramEnrollmentShares(enrollmentDeleteParentIds, deleteUserIds, enrollmentDeleteKeys);
        createProgramEnrollmentShares(enrollmentCreateParentIds, createUserIds, enrollmentCreateKeys);
    }

    private static Map<Id, Id> getAdvisorUserMap(List<ShareRequest> requests) {
        Set<Id> advisorContactIds = new Set<Id>();
        for (ShareRequest req : requests) {
            if (req == null || req.isActive != true) {
                continue;
            }
            if (req.oldAdvisorContactId != null) {
                advisorContactIds.add(req.oldAdvisorContactId);
            }
            if (req.newAdvisorContactId != null) {
                advisorContactIds.add(req.newAdvisorContactId);
            }
        }

        Map<Id, Id> advisorContactToUserId = new Map<Id, Id>();
        if (advisorContactIds.isEmpty()) {
            return advisorContactToUserId;
        }

        for (Contact advisor : [
            SELECT Id, Linked_User_Id__c
            FROM Contact
            WHERE Id IN :advisorContactIds
        ]) {
            if (advisor.Linked_User_Id__c != null) {
                advisorContactToUserId.put(advisor.Id, advisor.Linked_User_Id__c);
            }
        }
        return advisorContactToUserId;
    }

    private static void deleteContactShares(Set<Id> parentIds, Set<Id> userIds, Set<String> targetKeys) {
        if (parentIds.isEmpty() || userIds.isEmpty() || targetKeys.isEmpty()) {
            return;
        }

        List<ContactShare> toDelete = new List<ContactShare>();
        for (ContactShare shareRow : [
            SELECT Id, ContactId, UserOrGroupId
            FROM ContactShare
            WHERE ContactId IN :parentIds
            AND UserOrGroupId IN :userIds
            AND RowCause = 'Manual'
        ]) {
            if (targetKeys.contains(buildKey(shareRow.ContactId, shareRow.UserOrGroupId))) {
                toDelete.add(shareRow);
            }
        }

        if (!toDelete.isEmpty()) {
            Database.delete(toDelete, false);
        }
    }

    private static void createContactShares(Set<Id> parentIds, Set<Id> userIds, Set<String> targetKeys) {
        if (parentIds.isEmpty() || userIds.isEmpty() || targetKeys.isEmpty()) {
            return;
        }

        Set<String> existingKeys = new Set<String>();
        for (ContactShare shareRow : [
            SELECT ContactId, UserOrGroupId
            FROM ContactShare
            WHERE ContactId IN :parentIds
            AND UserOrGroupId IN :userIds
            AND RowCause = 'Manual'
        ]) {
            existingKeys.add(buildKey(shareRow.ContactId, shareRow.UserOrGroupId));
        }

        List<ContactShare> toInsert = new List<ContactShare>();
        for (String key : targetKeys) {
            if (existingKeys.contains(key)) {
                continue;
            }
            List<String> parts = key.split(':');
            toInsert.add(new ContactShare(
                ContactId = (Id) parts[0],
                UserOrGroupId = (Id) parts[1],
                ContactAccessLevel = 'Read',
                RowCause = Schema.ContactShare.RowCause.Manual
            ));
        }

        if (!toInsert.isEmpty()) {
            Database.insert(toInsert, false);
        }
    }

    private static void deleteProgramEnrollmentShares(Set<Id> parentIds, Set<Id> userIds, Set<String> targetKeys) {
        if (parentIds.isEmpty() || userIds.isEmpty() || targetKeys.isEmpty()) {
            return;
        }

        String shareObjectName = 'ProgramEnrollmentShare';
        String accessFieldName = resolveProgramEnrollmentAccessFieldName();
        Schema.SObjectType shareType = Schema.getGlobalDescribe().get(shareObjectName);

        if (shareType == null || String.isBlank(accessFieldName)) {
            return;
        }

        String soql =
            'SELECT Id, ParentId, UserOrGroupId ' +
            'FROM ' + shareObjectName + ' ' +
            'WHERE ParentId IN :parentIds ' +
            'AND UserOrGroupId IN :userIds ' +
            'AND RowCause = \'' + 'Manual' + '\'';

        List<SObject> queriedRows = Database.query(soql);
        List<SObject> toDelete = new List<SObject>();
        for (SObject row : queriedRows) {
            Id parentId = (Id) row.get('ParentId');
            Id userId = (Id) row.get('UserOrGroupId');
            if (targetKeys.contains(buildKey(parentId, userId))) {
                toDelete.add(row);
            }
        }

        if (!toDelete.isEmpty()) {
            Database.delete(toDelete, false);
        }
    }

    private static void createProgramEnrollmentShares(Set<Id> parentIds, Set<Id> userIds, Set<String> targetKeys) {
        if (parentIds.isEmpty() || userIds.isEmpty() || targetKeys.isEmpty()) {
            return;
        }

        String shareObjectName = 'ProgramEnrollmentShare';
        String accessFieldName = resolveProgramEnrollmentAccessFieldName();
        Schema.SObjectType shareType = Schema.getGlobalDescribe().get(shareObjectName);

        if (shareType == null || String.isBlank(accessFieldName)) {
            return;
        }

        String soql =
            'SELECT ParentId, UserOrGroupId ' +
            'FROM ' + shareObjectName + ' ' +
            'WHERE ParentId IN :parentIds ' +
            'AND UserOrGroupId IN :userIds ' +
            'AND RowCause = \'' + 'Manual' + '\'';

        Set<String> existingKeys = new Set<String>();
        for (SObject row : Database.query(soql)) {
            existingKeys.add(buildKey((Id) row.get('ParentId'), (Id) row.get('UserOrGroupId')));
        }

        List<SObject> toInsert = new List<SObject>();
        for (String key : targetKeys) {
            if (existingKeys.contains(key)) {
                continue;
            }
            List<String> parts = key.split(':');
            SObject shareRow = shareType.newSObject();
            shareRow.put('ParentId', (Id) parts[0]);
            shareRow.put('UserOrGroupId', (Id) parts[1]);
            shareRow.put(accessFieldName, 'Read');
            shareRow.put('RowCause', 'Manual');
            toInsert.add(shareRow);
        }

        if (!toInsert.isEmpty()) {
            Database.insert(toInsert, false);
        }
    }

    private static String resolveProgramEnrollmentAccessFieldName() {
        Schema.SObjectType shareType = Schema.getGlobalDescribe().get('ProgramEnrollmentShare');
        if (shareType == null) {
            return null;
        }
        Map<String, Schema.SObjectField> fieldsByName = shareType.getDescribe().fields.getMap();
        if (fieldsByName.containsKey('AccessLevel')) {
            return 'AccessLevel';
        }
        if (fieldsByName.containsKey('ProgramEnrollmentAccessLevel')) {
            return 'ProgramEnrollmentAccessLevel';
        }
        return null;
    }

    private static String buildKey(Id parentId, Id userId) {
        return String.valueOf(parentId) + ':' + String.valueOf(userId);
    }
}