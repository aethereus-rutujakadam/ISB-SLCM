public without sharing class CourseManagerMetadataAssignmentService {

    public class AssignmentStats {
        public Integer totalOfferingsEvaluated = 0;
        public Integer totalAssignmentsAttempted = 0;
        public Integer totalAssignmentsCreated = 0;
        public Integer totalAssignmentsSkipped = 0;
        public Integer totalErrorsLogged = 0;
    }

    private class RuleUser implements Comparable {
        public Integer sequence;
        public String email;

        public Integer compareTo(Object obj) {
            RuleUser other = (RuleUser)obj;
            Integer thisSeq = sequence == null ? 999999 : sequence;
            Integer otherSeq = other.sequence == null ? 999999 : other.sequence;

            if (thisSeq != otherSeq) {
                return thisSeq < otherSeq ? -1 : 1;
            }
            String thisEmail = email == null ? '' : email;
            String otherEmail = other.email == null ? '' : other.email;
            return thisEmail.toLowerCase().compareTo(otherEmail.toLowerCase());
        }
    }

    private class OfferingSortable implements Comparable {
        public CourseOffering offering;

        public Integer compareTo(Object obj) {
            OfferingSortable other = (OfferingSortable)obj;
            if (offering.CreatedDate != other.offering.CreatedDate) {
                return offering.CreatedDate < other.offering.CreatedDate ? -1 : 1;
            }
            String thisId = String.valueOf(offering.Id);
            String otherId = String.valueOf(other.offering.Id);
            return thisId.toLowerCase().compareTo(otherId.toLowerCase());
        }
    }

    public static AssignmentStats assignForOfferings(Set<Id> offeringIds) {
        AssignmentStats stats = new AssignmentStats();
        if (offeringIds == null || offeringIds.isEmpty()) {
            return stats;
        }

        List<Error_Handling__c> logs = new List<Error_Handling__c>();

        List<CourseOffering> offerings = [
            SELECT Id, CreatedDate, LearningCourseId, Program__r.Program_Code__c, Location__r.Name, Course_Type__c, Academic_Term__r.Name
            FROM CourseOffering
            WHERE Id IN :offeringIds
        ];

        stats.totalOfferingsEvaluated = offerings.size();
        if (offerings.isEmpty()) {
            return stats;
        }

        List<Course_Manager_Assignment_Rule__mdt> allRules = [
            SELECT Program_Code__c, Program_Name__c, Location_Name__c, Course_Type__c, Cohort__c,
                   Role__c, User_Email__c, Sequence__c, Is_Active__c
            FROM Course_Manager_Assignment_Rule__mdt
        ];

        Set<String> duplicateRuleRowKeys = findDuplicateRuleRowKeys(allRules);
        Set<String> loggedDuplicateRuleRowKeys = new Set<String>();
        List<Course_Manager_Assignment_Rule__mdt> activeRules = new List<Course_Manager_Assignment_Rule__mdt>();
        for (Course_Manager_Assignment_Rule__mdt ruleRow : allRules) {
            String duplicateKey = buildRuleRowUniquenessKey(ruleRow);
            if (duplicateRuleRowKeys.contains(duplicateKey)) {
                if (!loggedDuplicateRuleRowKeys.contains(duplicateKey)) {
                    logs.add(buildLog(
                        'Duplicate assignment rule row skipped for key: ' + duplicateKey
                        + '. Duplicate detection ignores Is_Active__c.'
                    ));
                    loggedDuplicateRuleRowKeys.add(duplicateKey);
                }
                continue;
            }

            if (ruleRow.Is_Active__c) {
                activeRules.add(ruleRow);
            }
        }

        Set<String> activeRuleDimensionKeys = new Set<String>();
        Map<String, Set<String>> rolesByDimensionKey = new Map<String, Set<String>>();
        for (Course_Manager_Assignment_Rule__mdt ruleRow : activeRules) {
            String roleNorm = normalize(ruleRow.Role__c);
            if (String.isBlank(roleNorm)) {
                continue;
            }

            String programCode = normalize(ruleRow.Program_Code__c);
            String locationName = normalize(ruleRow.Location_Name__c);
            String courseType = normalize(ruleRow.Course_Type__c);
            String cohortName = normalize(ruleRow.Cohort__c);

            if (String.isBlank(programCode) || String.isBlank(locationName) || String.isBlank(courseType) || String.isBlank(cohortName)) {
                continue;
            }

            activeRuleDimensionKeys.add(buildRuleDimensionKey(programCode, locationName, courseType, cohortName));
            String dimensionKey = buildRuleDimensionKey(programCode, locationName, courseType, cohortName);
            if (!rolesByDimensionKey.containsKey(dimensionKey)) {
                rolesByDimensionKey.put(dimensionKey, new Set<String>());
            }
            rolesByDimensionKey.get(dimensionKey).add(roleNorm);
        }

        Map<Id, Set<String>> existingRolesByOffering = new Map<Id, Set<String>>();
        Map<Id, Set<Id>> existingUsersByOffering = new Map<Id, Set<Id>>();

        for (course_managers__c existing : [
            SELECT Course_Offering__c, Role__c, User__c
            FROM course_managers__c
            WHERE Course_Offering__c IN :offeringIds
        ]) {
            if (!existingRolesByOffering.containsKey(existing.Course_Offering__c)) {
                existingRolesByOffering.put(existing.Course_Offering__c, new Set<String>());
            }
            if (!String.isBlank(existing.Role__c)) {
                existingRolesByOffering.get(existing.Course_Offering__c).add(normalize(existing.Role__c));
            }

            if (existing.User__c != null) {
                if (!existingUsersByOffering.containsKey(existing.Course_Offering__c)) {
                    existingUsersByOffering.put(existing.Course_Offering__c, new Set<Id>());
                }
                existingUsersByOffering.get(existing.Course_Offering__c).add(existing.User__c);
            }
        }

        Map<String, List<CourseOffering>> offeringsByRuleKey = new Map<String, List<CourseOffering>>();
        Set<String> neededRuleKeys = new Set<String>();

        for (CourseOffering offering : offerings) {
            String programCode = normalize(offering.Program__r != null ? String.valueOf(offering.Program__r.get('Program_Code__c')) : null);
            String locationName = normalize(offering.Location__r != null ? offering.Location__r.Name : null);
            String courseType = normalize(offering.Course_Type__c);
            String cohortName = normalize(offering.Academic_Term__r != null ? offering.Academic_Term__r.Name : null);

            if (String.isBlank(programCode) || String.isBlank(locationName) || String.isBlank(courseType) || String.isBlank(cohortName)) {
                stats.totalAssignmentsSkipped++;
                logs.add(buildLog('Skipping offering ' + offering.Id + ' because ProgramCode/Location/Course Type/Cohort is incomplete.'));
                continue;
            }

            String dimensionKey = buildRuleDimensionKey(programCode, locationName, courseType, cohortName);
            if (!activeRuleDimensionKeys.contains(dimensionKey)) {
                stats.totalAssignmentsSkipped++;
                logs.add(buildLog('Skipping offering ' + offering.Id + ' because no active metadata rule exists for ProgramCode/Location/Course Type/Cohort.'));
                continue;
            }

            Set<String> existingRoles = existingRolesByOffering.containsKey(offering.Id)
                ? existingRolesByOffering.get(offering.Id)
                : new Set<String>();

            Set<String> availableRoles = rolesByDimensionKey.containsKey(dimensionKey)
                ? rolesByDimensionKey.get(dimensionKey)
                : new Set<String>();

            for (String roleKey : availableRoles) {
                if (existingRoles.contains(roleKey)) {
                    continue;
                }

                String ruleKey = buildRuleKey(programCode, locationName, courseType, cohortName, roleKey);
                if (!offeringsByRuleKey.containsKey(ruleKey)) {
                    offeringsByRuleKey.put(ruleKey, new List<CourseOffering>());
                }
                offeringsByRuleKey.get(ruleKey).add(offering);
                neededRuleKeys.add(ruleKey);
            }
        }

        if (neededRuleKeys.isEmpty()) {
            flushLogs(logs, stats);
            return stats;
        }

        Map<String, List<RuleUser>> ruleUsersByKey = new Map<String, List<RuleUser>>();
        Map<String, String> roleLabelByRuleKey = new Map<String, String>();
        Set<String> allRuleEmails = new Set<String>();
        Set<String> processedRuleRowKeys = new Set<String>();

        for (Course_Manager_Assignment_Rule__mdt ruleRow : activeRules) {
            String roleNorm = normalize(ruleRow.Role__c);
            if (String.isBlank(roleNorm)) {
                continue;
            }

            String key = buildRuleKey(
                normalize(ruleRow.Program_Code__c),
                normalize(ruleRow.Location_Name__c),
                normalize(ruleRow.Course_Type__c),
                normalize(ruleRow.Cohort__c),
                roleNorm
            );

            if (!neededRuleKeys.contains(key)) {
                continue;
            }

            if (!roleLabelByRuleKey.containsKey(key)) {
                roleLabelByRuleKey.put(key, normalizeRoleForRecord(ruleRow.Role__c));
            }

            String emailNorm = normalize(ruleRow.User_Email__c);
            if (String.isBlank(emailNorm)) {
                continue;
            }

            String ruleRowKey = key + '|' + emailNorm + '|'
                + String.valueOf(ruleRow.Sequence__c == null ? null : Integer.valueOf(ruleRow.Sequence__c));
            if (processedRuleRowKeys.contains(ruleRowKey)) {
                logs.add(buildLog('Duplicate active assignment rule row skipped for key: ' + key + ', email: ' + emailNorm));
                continue;
            }
            processedRuleRowKeys.add(ruleRowKey);

            RuleUser ru = new RuleUser();
            ru.email = emailNorm;
            ru.sequence = ruleRow.Sequence__c == null ? null : Integer.valueOf(ruleRow.Sequence__c);

            if (!ruleUsersByKey.containsKey(key)) {
                ruleUsersByKey.put(key, new List<RuleUser>());
            }
            ruleUsersByKey.get(key).add(ru);
            allRuleEmails.add(emailNorm);
        }

        Map<String, User> activeUserByEmail = new Map<String, User>();
        if (!allRuleEmails.isEmpty()) {
            for (User u : [
                SELECT Id, Name, Email
                FROM User
                WHERE IsActive = true
                  AND Email IN :allRuleEmails
                ORDER BY Name, Id
            ]) {
                String emailKey = normalize(u.Email);
                if (!activeUserByEmail.containsKey(emailKey)) {
                    activeUserByEmail.put(emailKey, u);
                }
            }
        }

        List<course_managers__c> managersToInsert = new List<course_managers__c>();

        for (String ruleKey : offeringsByRuleKey.keySet()) {
            List<CourseOffering> candidateOfferings = offeringsByRuleKey.get(ruleKey);
            List<RuleUser> ruleUsers = ruleUsersByKey.get(ruleKey);

            if (ruleUsers == null || ruleUsers.isEmpty()) {
                stats.totalAssignmentsSkipped += candidateOfferings.size();
                logs.add(buildLog('No active metadata rules found for key: ' + ruleKey));
                continue;
            }

            ruleUsers.sort();
            List<Id> assigneePool = new List<Id>();
            Set<Id> dedupeAssigneePool = new Set<Id>();

            for (RuleUser ruleUser : ruleUsers) {
                User matched = activeUserByEmail.get(ruleUser.email);
                if (matched == null || dedupeAssigneePool.contains(matched.Id)) {
                    continue;
                }
                dedupeAssigneePool.add(matched.Id);
                assigneePool.add(matched.Id);
            }

            if (assigneePool.isEmpty()) {
                stats.totalAssignmentsSkipped += candidateOfferings.size();
                logs.add(buildLog('No active users resolved from metadata for key: ' + ruleKey));
                continue;
            }

            List<OfferingSortable> sortable = new List<OfferingSortable>();
            for (CourseOffering co : candidateOfferings) {
                OfferingSortable row = new OfferingSortable();
                row.offering = co;
                sortable.add(row);
            }
            sortable.sort();

            String roleValue = roleLabelByRuleKey.containsKey(ruleKey)
                ? roleLabelByRuleKey.get(ruleKey)
                : extractRoleFromRuleKey(ruleKey);
            if (String.isBlank(roleValue)) {
                stats.totalAssignmentsSkipped += candidateOfferings.size();
                logs.add(buildLog('Skipping rule key ' + ruleKey + ' because Role is blank or invalid.'));
                continue;
            }
            Integer startIndex = 0;

            for (OfferingSortable sortRow : sortable) {
                CourseOffering co = sortRow.offering;
                stats.totalAssignmentsAttempted++;

                Id selectedUserId = findNextEligibleUser(
                    assigneePool,
                    startIndex,
                    existingUsersByOffering.containsKey(co.Id) ? existingUsersByOffering.get(co.Id) : new Set<Id>()
                );

                if (selectedUserId == null) {
                    stats.totalAssignmentsSkipped++;
                    logs.add(buildLog('No eligible assignee available for offering ' + co.Id + ' and role ' + roleValue + '.'));
                    continue;
                }

                course_managers__c cm = new course_managers__c();
                cm.Course_Offering__c = co.Id;
                cm.Courses__c = co.LearningCourseId;
                cm.Role__c = roleValue;
                cm.User__c = selectedUserId;
                cm.OwnerId = selectedUserId;
                managersToInsert.add(cm);

                if (!existingUsersByOffering.containsKey(co.Id)) {
                    existingUsersByOffering.put(co.Id, new Set<Id>());
                }
                existingUsersByOffering.get(co.Id).add(selectedUserId);

                if (!existingRolesByOffering.containsKey(co.Id)) {
                    existingRolesByOffering.put(co.Id, new Set<String>());
                }
                existingRolesByOffering.get(co.Id).add(normalize(roleValue));

                startIndex++;
            }
        }

        if (!managersToInsert.isEmpty()) {
            Database.SaveResult[] saveResults = Database.insert(managersToInsert, false);
            for (Integer i = 0; i < saveResults.size(); i++) {
                if (saveResults[i].isSuccess()) {
                    stats.totalAssignmentsCreated++;
                } else {
                    stats.totalAssignmentsSkipped++;
                    for (Database.Error err : saveResults[i].getErrors()) {
                        logs.add(buildLog('DML error for offering ' + managersToInsert[i].Course_Offering__c + ': ' + err.getMessage()));
                    }
                }
            }
        }

        flushLogs(logs, stats);
        return stats;
    }

    private static Id findNextEligibleUser(List<Id> userPool, Integer startIndex, Set<Id> existingUsers) {
        if (userPool == null || userPool.isEmpty()) {
            return null;
        }

        Integer idx = startIndex == null ? 0 : startIndex;
        for (Integer i = 0; i < userPool.size(); i++) {
            Id candidate = userPool[Math.mod(idx + i, userPool.size())];
            if (!existingUsers.contains(candidate)) {
                return candidate;
            }
        }
        return null;
    }

    private static void flushLogs(List<Error_Handling__c> logs, AssignmentStats stats) {
        if (logs == null || logs.isEmpty()) {
            return;
        }
        Database.insert(logs, false);
        stats.totalErrorsLogged += logs.size();
    }

    private static Error_Handling__c buildLog(String message) {
        Error_Handling__c rec = new Error_Handling__c();
        rec.Component_Name__c = 'Course Manager Metadata Assignment';
        rec.Error_message__c = truncate(message, 255);
        return rec;
    }

    @TestVisible
    private static Set<String> findDuplicateRuleRowKeys(List<Course_Manager_Assignment_Rule__mdt> rules) {
        Set<String> duplicateKeys = new Set<String>();
        if (rules == null || rules.isEmpty()) {
            return duplicateKeys;
        }

        Map<String, Integer> countByKey = new Map<String, Integer>();
        for (Course_Manager_Assignment_Rule__mdt ruleRow : rules) {
            String ruleRowKey = buildRuleRowUniquenessKey(ruleRow);
            Integer currentCount = countByKey.containsKey(ruleRowKey) ? countByKey.get(ruleRowKey) : 0;
            countByKey.put(ruleRowKey, currentCount + 1);
        }

        for (String ruleRowKey : countByKey.keySet()) {
            if (countByKey.get(ruleRowKey) > 1) {
                duplicateKeys.add(ruleRowKey);
            }
        }

        return duplicateKeys;
    }

    private static String buildRuleRowUniquenessKey(Course_Manager_Assignment_Rule__mdt ruleRow) {
        if (ruleRow == null) {
            return '';
        }

        Integer sequenceValue = ruleRow.Sequence__c == null ? null : Integer.valueOf(ruleRow.Sequence__c);
        return normalize(ruleRow.Program_Code__c)
            + '|'
            + normalize(ruleRow.Program_Name__c)
            + '|'
            + normalize(ruleRow.Location_Name__c)
            + '|'
            + normalize(ruleRow.Course_Type__c)
            + '|'
            + normalize(ruleRow.Cohort__c)
            + '|'
            + normalize(ruleRow.Role__c)
            + '|'
            + normalize(ruleRow.User_Email__c)
            + '|'
            + String.valueOf(sequenceValue);
    }

    private static String buildRuleKey(String programCode, String locationName, String courseType, String cohortName, String role) {
        return programCode + '|' + locationName + '|' + courseType + '|' + cohortName + '|' + role;
    }

    private static String buildRuleDimensionKey(String programCode, String locationName, String courseType, String cohortName) {
        return programCode + '|' + locationName + '|' + courseType + '|' + cohortName;
    }

    private static String extractRoleFromRuleKey(String key) {
        if (String.isBlank(key)) {
            return null;
        }

        List<String> parts = key.split('\\|');
        if (parts.isEmpty()) {
            return null;
        }

        String role = parts[parts.size() - 1];
        if (role == 'manager') return 'Manager';
        if (role == 'associate') return 'Associate';
        if (role == 'delivery manager') return 'Delivery Manager';
        return null;
    }

    private static String normalizeRoleForRecord(String roleValue) {
        String roleNorm = normalize(roleValue);
        if (roleNorm == 'manager') return 'Manager';
        if (roleNorm == 'associate') return 'Associate';
        if (roleNorm == 'delivery manager') return 'Delivery Manager';
        return String.isBlank(roleValue) ? null : roleValue.trim();
    }

    private static String normalize(String value) {
        return String.isBlank(value) ? '' : value.trim().toLowerCase();
    }

    private static String truncate(String message, Integer maxLen) {
        if (String.isBlank(message)) {
            return message;
        }
        if (maxLen == null || maxLen <= 0 || message.length() <= maxLen) {
            return message;
        }
        return message.substring(0, maxLen);
    }
}