public without sharing class AssignAcademicAssociatePermissionSet {

    // Wrapper class for Flow input
    public class InputWrapper {
        @InvocableVariable(required=true)
        public Id userId;
    }

    /**
     * This Invocable Method can be used directly in Flow.
     * It internally calls a @future method for async assignment.
     */
    @InvocableMethod(label='Assign Academic Associate Permission Set' 
                     description='Assigns the AcademicAssociatePermissionSet to the given User asynchronously.')
    public static void assignPermissionSet(List<InputWrapper> inputs) {
        if (inputs == null || inputs.isEmpty()) {
            return;
        }

        for (InputWrapper input : inputs) {
            if (input.userId != null) {
                assignAAPermissionSetAsync(input.userId);
            }
        }
    }

    /**
     * Actual @future method that performs the assignment
     */
    @future
    public static void assignAAPermissionSetAsync(Id userId) {
        try {
            if (userId == null) return;
            
            String labelValue = System.Label.Academic_Associate_Permission_Name;
            
            // Query for the Permission Set Group using the label value (DeveloperName)
            List<PermissionSetGroup> groups = [
                SELECT Id 
                FROM PermissionSetGroup 
                WHERE DeveloperName = :labelValue 
                LIMIT 1
            ];

            if (groups.isEmpty()) {
                System.debug('❌ Permission Set Group not found: ' + labelValue);
                return;
            }
            
            Id psgId = groups[0].Id;

            // Avoid duplicate assignment
            List<PermissionSetAssignment> existing = [
                SELECT Id 
                FROM PermissionSetAssignment 
                WHERE AssigneeId = :userId 
                AND PermissionSetGroupId = :psgId
            ];

            if (existing.isEmpty()) {
                PermissionSetAssignment psa = new PermissionSetAssignment(
                    AssigneeId = userId,
                    PermissionSetGroupId = psgId
                );
                insert psa;
            }
        } catch (Exception e) {
            System.debug('❌ Error assigning permission set group: ' + e.getMessage() + ' at line ' + e.getLineNumber());
        }
    }
}