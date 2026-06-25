public without sharing class AssignAdvisorPermissionSet {

    @TestVisible
    private static String advisorPermissionSetNameOverride;

    @TestVisible
    private static String additionalPermissionSetNameOverride;

    private static final String ADVISOR_PERMISSION_SET_NAME = 'Advisor_Permission_Set';
    private static final String ADDITIONAL_PERMISSION_SET_NAME = 'StandardEinsteinActivityCapturePsl';
    private static final String EDUCATION_CLOUD_ACCESS_CLONED_PERMISSION_SET_NAME = 'EducationCloudAccessCloned';

    // Wrapper class for Flow input
    public class InputWrapper {
        @InvocableVariable(required=true)
        public Id userId;
    }

    /**
     * This Invocable Method can be used directly in Flow.
     * It internally calls a @future method for async assignment.
     */
    @InvocableMethod(label='Assign Advisor Permission Set'
                     description='Assigns the configured advisor access to the given User asynchronously.')
    public static void assignPermissionSet(List<InputWrapper> inputs) {
        if (inputs == null || inputs.isEmpty()) {
            return;
        }

        for (InputWrapper input : inputs) {
            if (input.userId != null) {
                assignAdvisorPermissionSetAsync(input.userId);
            }
        }
    }

    /**
     * Assigns both the advisor Permission Set Group and the additional Permission Set.
     * Can be called directly from a Queueable context (no @future needed there).
     * When called from a non-async context (e.g. Flow), it delegates to the @future method.
     */
    public static void assignFromQueueable(Id userId) {
        if (userId == null) return;
        try {
            assignConfiguredPermissionSets(userId);
        } catch (Exception e) {
            System.debug('Error assigning advisor access: ' + e.getMessage() + ' at line ' + e.getLineNumber());
        }
    }

    /**
     * Actual @future method — use only when NOT already in an async (Queueable/Batch/future) context.
     */
    @future
    public static void assignAdvisorPermissionSetAsync(Id userId) {
        if (userId == null) return;
        try {
            assignConfiguredPermissionSets(userId);
        } catch (Exception e) {
            System.debug('Error assigning advisor access: ' + e.getMessage() + ' at line ' + e.getLineNumber());
        }
    }

    private static void assignConfiguredPermissionSets(Id userId) {
        Set<String> permissionSetNames = new Set<String>{
            getAdvisorPermissionSetName(),
            getAdditionalPermissionSetName(),
            EDUCATION_CLOUD_ACCESS_CLONED_PERMISSION_SET_NAME
        };

        permissionSetNames.remove('');
        permissionSetNames.remove(null);
        if (permissionSetNames.isEmpty()) {
            return;
        }

        List<PermissionSet> permissionSets = [
            SELECT Id, Name
            FROM PermissionSet
            WHERE Name IN :permissionSetNames
            AND IsOwnedByProfile = false
        ];

        if (permissionSets.isEmpty()) {
            System.debug('No configured Permission Sets found for assignment.');
            return;
        }

        Set<Id> permissionSetIds = new Set<Id>();
        for (PermissionSet ps : permissionSets) {
            permissionSetIds.add(ps.Id);
        }

        Set<Id> alreadyAssignedPermissionSetIds = new Set<Id>();
        for (PermissionSetAssignment psa : [
            SELECT PermissionSetId
            FROM PermissionSetAssignment
            WHERE AssigneeId = :userId
            AND PermissionSetId IN :permissionSetIds
        ]) {
            alreadyAssignedPermissionSetIds.add(psa.PermissionSetId);
        }

        List<PermissionSetAssignment> assignmentsToInsert = new List<PermissionSetAssignment>();
        for (PermissionSet ps : permissionSets) {
            if (!alreadyAssignedPermissionSetIds.contains(ps.Id)) {
                assignmentsToInsert.add(new PermissionSetAssignment(
                    AssigneeId = userId,
                    PermissionSetId = ps.Id
                ));
            }
        }

        if (!assignmentsToInsert.isEmpty()) {
            insert assignmentsToInsert;
        }
    }

    private static String getAdvisorPermissionSetName() {
        if (Test.isRunningTest() && advisorPermissionSetNameOverride != null) {
            return advisorPermissionSetNameOverride;
        }

        return ADVISOR_PERMISSION_SET_NAME;
    }

    private static String getAdditionalPermissionSetName() {
        if (Test.isRunningTest() && additionalPermissionSetNameOverride != null) {
            return additionalPermissionSetNameOverride;
        }

        return ADDITIONAL_PERMISSION_SET_NAME;
    }
}