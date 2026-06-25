/**
 * @description Trigger validation handler for course_managers__c.
 * Enforces:
 * 1) One manager per role per course offering.
 * 2) One user per course offering (user cannot hold multiple roles on same offering).
 */
public class CourseManagerDuplicateValidationHandler {

    public static void validateNoDuplicates(List<course_managers__c> newManagers, Map<Id, course_managers__c> oldMap) {
        if (newManagers == null || newManagers.isEmpty()) {
            return;
        }

        Set<Id> offeringIds = new Set<Id>();
        Set<String> roles = new Set<String>();
        Set<Id> userIds = new Set<Id>();

        for (course_managers__c mgr : newManagers) {
            if (mgr.Course_Offering__c == null) {
                continue;
            }
            offeringIds.add(mgr.Course_Offering__c);
            if (!String.isBlank(mgr.Role__c)) {
                roles.add(mgr.Role__c);
            }
            if (mgr.User__c != null) {
                userIds.add(mgr.User__c);
            }
        }

        if (offeringIds.isEmpty()) {
            return;
        }

        List<course_managers__c> existingManagers = [
            SELECT Id, Course_Offering__c, Role__c, User__c
            FROM course_managers__c
            WHERE Course_Offering__c IN :offeringIds
              AND (
                   (Role__c IN :roles)
                OR (User__c IN :userIds)
              )
        ];

        Map<String, List<course_managers__c>> existingByOfferingRole = new Map<String, List<course_managers__c>>();
        Map<String, List<course_managers__c>> existingByOfferingUser = new Map<String, List<course_managers__c>>();
        for (course_managers__c existing : existingManagers) {
            if (!String.isBlank(existing.Role__c)) {
                String offeringRoleKey = existing.Course_Offering__c + '|' + existing.Role__c;
                if (!existingByOfferingRole.containsKey(offeringRoleKey)) {
                    existingByOfferingRole.put(offeringRoleKey, new List<course_managers__c>());
                }
                existingByOfferingRole.get(offeringRoleKey).add(existing);
            }

            if (existing.User__c != null) {
                String offeringUserKey = existing.Course_Offering__c + '|' + existing.User__c;
                if (!existingByOfferingUser.containsKey(offeringUserKey)) {
                    existingByOfferingUser.put(offeringUserKey, new List<course_managers__c>());
                }
                existingByOfferingUser.get(offeringUserKey).add(existing);
            }
        }

        // In-transaction checks to catch duplicates inside the same DML batch.
        Map<String, String> seenRoleByOffering = new Map<String, String>();
        Map<String, String> seenRoleByOfferingUser = new Map<String, String>();

        for (course_managers__c mgr : newManagers) {
            if (mgr.Course_Offering__c == null) {
                continue;
            }

            if (!String.isBlank(mgr.Role__c)) {
                String offeringRoleKey = mgr.Course_Offering__c + '|' + mgr.Role__c;
                if (seenRoleByOffering.containsKey(offeringRoleKey) && seenRoleByOffering.get(offeringRoleKey) != String.valueOf(mgr.Id)) {
                    mgr.addError(
                        'A course manager with role "' + mgr.Role__c + '" already exists for this course offering. ' +
                        'Only one manager per role is allowed per course offering.'
                    );
                } else {
                    seenRoleByOffering.put(offeringRoleKey, String.valueOf(mgr.Id));
                }

                List<course_managers__c> roleMatches = existingByOfferingRole.get(offeringRoleKey);
                if (hasOtherRecord(roleMatches, mgr.Id)) {
                    mgr.addError(
                        'A course manager with role "' + mgr.Role__c + '" already exists for this course offering. ' +
                        'Only one manager per role is allowed per course offering.'
                    );
                }
            }

            if (mgr.User__c != null && !String.isBlank(mgr.Role__c)) {
                String offeringUserKey = mgr.Course_Offering__c + '|' + mgr.User__c;

                if (seenRoleByOfferingUser.containsKey(offeringUserKey)) {
                    String seenRole = seenRoleByOfferingUser.get(offeringUserKey);
                    if (!String.isBlank(seenRole) && seenRole != mgr.Role__c) {
                        mgr.addError(
                            'This user is already assigned another role for this course offering. ' +
                            'A user can hold only one role per course offering.'
                        );
                    }
                } else {
                    seenRoleByOfferingUser.put(offeringUserKey, mgr.Role__c);
                }

                List<course_managers__c> userMatches = existingByOfferingUser.get(offeringUserKey);
                if (userMatches != null) {
                    for (course_managers__c existing : userMatches) {
                        if (existing.Id == mgr.Id) {
                            continue;
                        }
                        if (!String.isBlank(existing.Role__c) && existing.Role__c != mgr.Role__c) {
                            mgr.addError(
                                'This user is already assigned role "' + existing.Role__c +
                                '" for this course offering. A user cannot be assigned multiple roles on the same course offering.'
                            );
                            break;
                        }
                    }
                }
            }
        }
    }

    private static Boolean hasOtherRecord(List<course_managers__c> records, Id currentId) {
        if (records == null || records.isEmpty()) {
            return false;
        }
        for (course_managers__c rec : records) {
            if (rec.Id != currentId) {
                return true;
            }
        }
        return false;
    }
}