public without sharing class CommunicationThreadEscalationService {
    public static final String STAGE_LEVEL_1 = 'Level 1';
    public static final String STAGE_LEVEL_2 = 'Level 2';
    public static final String STAGE_LEVEL_3 = 'Level 3';
    public static final String STAGE_LEVEL_4 = 'Level 4';
    public static final String STAGE_CLOSED = 'Closed';

    private static final Integer DAYS_LEVEL_1_TO_2 = 7;
    private static final Integer DEFAULT_DAYS_BETWEEN_ESCALATIONS = 3;
    private static final String ROLE_KEY_L3 = 'L3_PULKIT';
    private static final String ROLE_KEY_L4 = 'L4_PHANIBALA';

    @TestVisible
    private static Map<String, String> TEST_ROLE_TO_USERNAME;
    @TestVisible
    private static Map<String, Integer> TEST_ROLE_TO_DAYS;

    public class EscalationResult {
        public Integer processed = 0;
        public Integer updated = 0;
        public Integer skipped = 0;
        public Integer warnings = 0;
        public List<String> messages = new List<String>();
    }

    private class ConfigInfo {
        String username;
        Integer daysFromPrevious;
    }

    public static EscalationResult processScope(List<Communication_Thread__c> scope) {
        EscalationResult result = new EscalationResult();
        if (scope == null || scope.isEmpty()) {
            return result;
        }

        Set<Id> threadIds = new Set<Id>();
        for (Communication_Thread__c row : scope) {
            threadIds.add(row.Id);
        }

        Map<Id, Communication_Thread__c> threadById = new Map<Id, Communication_Thread__c>([
            SELECT Id, OwnerId, Status__c,
                   Course_Offering__c, Course_Offering__r.Term_Start_Date__c,
                   Escalation_Stage__c, Escalation_Anchor_Date__c,
                   Escalation_Last_Run_On__c, Escalation_Next_Due_On__c,
                   Initiated_Date__c, CreatedDate
            FROM Communication_Thread__c
            WHERE Id IN :threadIds
        ]);

        Map<String, ConfigInfo> configByRoleKey = loadConfigByRoleKey();
        Map<String, Id> assigneeByRoleKey = resolveAssigneeIds(configByRoleKey);
        Set<Id> offeringIds = new Set<Id>();
        for (Communication_Thread__c thread : threadById.values()) {
            if (thread != null && thread.Course_Offering__c != null) {
                offeringIds.add(thread.Course_Offering__c);
            }
        }

        Map<Id, Id> managerByOffering = new Map<Id, Id>();
        Set<Id> ambiguousManagerOfferingIds = new Set<Id>();
        if (!offeringIds.isEmpty()) {
            for (course_managers__c cm : [
                SELECT Course_Offering__c, User__c
                FROM course_managers__c
                WHERE Course_Offering__c IN :offeringIds
                AND Role__c = 'Manager'
                AND User__c != null
            ]) {
                if (cm.Course_Offering__c == null) {
                    continue;
                }
                if (ambiguousManagerOfferingIds.contains(cm.Course_Offering__c)) {
                    continue;
                }
                if (!managerByOffering.containsKey(cm.Course_Offering__c)) {
                    managerByOffering.put(cm.Course_Offering__c, cm.User__c);
                } else {
                    managerByOffering.remove(cm.Course_Offering__c);
                    ambiguousManagerOfferingIds.add(cm.Course_Offering__c);
                }
            }
        }

        List<Communication_Thread__c> updates = new List<Communication_Thread__c>();
        Datetime nowValue = System.now();

        for (Communication_Thread__c sourceThread : scope) {
            Communication_Thread__c thread = threadById.get(sourceThread.Id);
            if (thread == null) {
                continue;
            }
            result.processed++;

            Communication_Thread__c updateRow = new Communication_Thread__c(Id = thread.Id);
            updateRow.Escalation_Last_Run_On__c = nowValue;
            Boolean changed = true;

            if (thread.Status__c == 'Closed') {
                if (thread.Escalation_Stage__c != STAGE_CLOSED) {
                    updateRow.Escalation_Stage__c = STAGE_CLOSED;
                }
                updateRow.Escalation_Next_Due_On__c = null;
                updateRow.Escalation_Anchor_Date__c = null;
                updates.add(updateRow);
                continue;
            }

            if (thread.Status__c != 'Open' && thread.Status__c != 'Pending Review') {
                result.skipped++;
                continue;
            }

            Date termStartDate = thread.Course_Offering__r != null ? thread.Course_Offering__r.Term_Start_Date__c : null;
            if (termStartDate == null) {
                result.skipped++;
                continue;
            }

            String currentStage = String.isBlank(thread.Escalation_Stage__c) ? STAGE_LEVEL_1 : thread.Escalation_Stage__c;
            if (String.isBlank(thread.Escalation_Stage__c)) {
                updateRow.Escalation_Stage__c = STAGE_LEVEL_1;
            }

            Datetime termStartDateTime = Datetime.newInstance(termStartDate, Time.newInstance(0, 0, 0, 0));
            Datetime level2DueOn = termStartDateTime.addDays(DAYS_LEVEL_1_TO_2);

            if (currentStage == STAGE_LEVEL_1) {
                if (nowValue >= level2DueOn) {
                    Id level2OwnerId = resolveLevel2OwnerId(thread, managerByOffering, ambiguousManagerOfferingIds, result);
                    if (level2OwnerId != null) {
                        if (thread.OwnerId != level2OwnerId) {
                            updateRow.OwnerId = level2OwnerId;
                        }
                        updateRow.Escalation_Stage__c = STAGE_LEVEL_2;
                        updateRow.Escalation_Anchor_Date__c = nowValue;
                        updateRow.Escalation_Next_Due_On__c = nowValue.addDays(daysForRole(configByRoleKey, ROLE_KEY_L3));
                    }
                } else {
                    updateRow.Escalation_Next_Due_On__c = level2DueOn;
                }
            } else if (currentStage == STAGE_LEVEL_2) {
                if (thread.Escalation_Anchor_Date__c != null &&
                    nowValue >= thread.Escalation_Anchor_Date__c.addDays(daysForRole(configByRoleKey, ROLE_KEY_L3))) {
                    Id level3OwnerId = assigneeByRoleKey.get(ROLE_KEY_L3);
                    if (level3OwnerId != null) {
                        if (thread.OwnerId != level3OwnerId) {
                            updateRow.OwnerId = level3OwnerId;
                        }
                        updateRow.Escalation_Stage__c = STAGE_LEVEL_3;
                        updateRow.Escalation_Anchor_Date__c = nowValue;
                        updateRow.Escalation_Next_Due_On__c = nowValue.addDays(daysForRole(configByRoleKey, ROLE_KEY_L4));
                    } else {
                        addWarning(result, 'L3 assignee missing for thread ' + thread.Id + '.');
                    }
                }
            } else if (currentStage == STAGE_LEVEL_3) {
                if (thread.Escalation_Anchor_Date__c != null &&
                    nowValue >= thread.Escalation_Anchor_Date__c.addDays(daysForRole(configByRoleKey, ROLE_KEY_L4))) {
                    Id level4OwnerId = assigneeByRoleKey.get(ROLE_KEY_L4);
                    if (level4OwnerId != null) {
                        if (thread.OwnerId != level4OwnerId) {
                            updateRow.OwnerId = level4OwnerId;
                        }
                        updateRow.Escalation_Stage__c = STAGE_LEVEL_4;
                        updateRow.Escalation_Anchor_Date__c = nowValue;
                        updateRow.Escalation_Next_Due_On__c = null;
                    } else {
                        addWarning(result, 'L4 assignee missing for thread ' + thread.Id + '.');
                    }
                }
            }

            if (changed) {
                updates.add(updateRow);
            }
        }

        if (!updates.isEmpty()) {
            Database.SaveResult[] saveResults = Database.update(updates, false);
            for (Database.SaveResult saveResult : saveResults) {
                if (saveResult.isSuccess()) {
                    result.updated++;
                } else {
                    addWarning(result, 'Escalation update failed: ' + saveResult.getErrors()[0].getMessage());
                }
            }
        }

        return result;
    }

    private static Id resolveLevel2OwnerId(
        Communication_Thread__c thread,
        Map<Id, Id> managerByOffering,
        Set<Id> ambiguousManagerOfferingIds,
        EscalationResult result
    ) {
        if (thread.Course_Offering__c == null) {
            addWarning(result, 'Course Offering is missing for thread ' + thread.Id + '.');
            return null;
        }

        if (ambiguousManagerOfferingIds.contains(thread.Course_Offering__c)) {
            addWarning(result, 'Multiple Course Manager records with role Manager found for thread ' + thread.Id + '.');
            return null;
        }

        Id managerId = managerByOffering.get(thread.Course_Offering__c);
        if (managerId == null) {
            addWarning(result, 'No Course Manager record with role Manager found for thread ' + thread.Id + '.');
            return null;
        }

        return managerId;
    }

    private static Map<String, ConfigInfo> loadConfigByRoleKey() {
        Map<String, ConfigInfo> configByRoleKey = new Map<String, ConfigInfo>();

        if (Test.isRunningTest() && TEST_ROLE_TO_USERNAME != null && !TEST_ROLE_TO_USERNAME.isEmpty()) {
            for (String roleKey : TEST_ROLE_TO_USERNAME.keySet()) {
                if (String.isBlank(roleKey)) {
                    continue;
                }

                ConfigInfo configInfo = new ConfigInfo();
                configInfo.username = TEST_ROLE_TO_USERNAME.get(roleKey);
                if (TEST_ROLE_TO_DAYS != null && TEST_ROLE_TO_DAYS.containsKey(roleKey)) {
                    configInfo.daysFromPrevious = TEST_ROLE_TO_DAYS.get(roleKey);
                }
                configByRoleKey.put(roleKey, configInfo);
            }
            return configByRoleKey;
        }

        for (Communication_Thread_Escalation_Config__mdt cfg : [
            SELECT Role_Key__c, Assignee_Username__c, Days_From_Previous__c
            FROM Communication_Thread_Escalation_Config__mdt
        ]) {
            if (String.isBlank(cfg.Role_Key__c)) {
                continue;
            }
            ConfigInfo configInfo = new ConfigInfo();
            configInfo.username = cfg.Assignee_Username__c;
            configInfo.daysFromPrevious = cfg.Days_From_Previous__c != null
                ? Integer.valueOf(cfg.Days_From_Previous__c)
                : null;
            configByRoleKey.put(cfg.Role_Key__c, configInfo);
        }
        return configByRoleKey;
    }

    private static Map<String, Id> resolveAssigneeIds(Map<String, ConfigInfo> configByRoleKey) {
        Map<String, Id> assigneeByRoleKey = new Map<String, Id>();
        Set<String> usernames = new Set<String>();

        for (String roleKey : configByRoleKey.keySet()) {
            ConfigInfo info = configByRoleKey.get(roleKey);
            if (info != null && String.isNotBlank(info.username)) {
                usernames.add(info.username);
            }
        }

        if (usernames.isEmpty()) {
            return assigneeByRoleKey;
        }

        Map<String, Id> userIdByUsername = new Map<String, Id>();
        for (User userRow : [
            SELECT Id, Username
            FROM User
            WHERE Username IN :usernames
            AND IsActive = true
        ]) {
            userIdByUsername.put(userRow.Username, userRow.Id);
        }

        for (String roleKey : configByRoleKey.keySet()) {
            ConfigInfo info = configByRoleKey.get(roleKey);
            if (info == null || String.isBlank(info.username)) {
                continue;
            }
            if (userIdByUsername.containsKey(info.username)) {
                assigneeByRoleKey.put(roleKey, userIdByUsername.get(info.username));
            }
        }

        return assigneeByRoleKey;
    }

    private static Integer daysForRole(Map<String, ConfigInfo> configByRoleKey, String roleKey) {
        ConfigInfo info = configByRoleKey.get(roleKey);
        if (info == null || info.daysFromPrevious == null || info.daysFromPrevious <= 0) {
            return DEFAULT_DAYS_BETWEEN_ESCALATIONS;
        }
        return info.daysFromPrevious;
    }

    private static void addWarning(EscalationResult result, String message) {
        result.warnings++;
        result.messages.add(message);
    }
}