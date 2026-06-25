public with sharing class CourseAAAssignmentInvocable {

    @InvocableMethod(
        label='Validate Duplicate Course AA Assignments'
        description='Prevents duplicate Academic Associate assignments for the same Course Offering'
    )
    public static void validateFromFlow(
        List<Course_AA_Assignment__c> records
    ) {
        if (records == null || records.isEmpty()) return;

        // Reuse trigger logic
        CourseAAAssignmentHandler.preventDuplicateAA(records, null);
    }
}