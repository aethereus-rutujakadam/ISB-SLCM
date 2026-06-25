public without sharing class ExchangeCaseAssignmentRuleHandler {
    private static Boolean isApplying = false;
    private static final String RO_USERNAME = 'hodro@myridius.com';
    private static Id roUserId;

    // Config-driven via Custom Labels (or hardcoded defaults)
    private static final String INCOMING_EXCHANGE_RT = 'Incoming_Exchange_Exit_Clearance';
    private static final String OUTGOING_EXCHANGE_RT = 'Outgoing_Exchange';
    private static final String CASE_TEAM_NAME = 'Incoming Team';
    private static final String ASA_ROLE_NAME = 'Student Affairs';
    private static final String FINANCE_ROLE_NAME = 'Finance';
    private static final String RO_ROLE_NAME = 'RO';
    private static final String FINANCE_STAGE = 'Finance Processing';

    private static final Set<String> INCOMING_RO_STATUSES = new Set<String>{
        'Grades Awaited',
        'Transcript Processing'
    };

    private static final Set<String> OUTGOING_RO_STATUSES = new Set<String>{
        'RO Review',
        'Transcript Check',
        'Student Credit Check'
    };

    /**
     * ========================================
     * AFTER INSERT: Add team + assign ASA
     * ========================================
     */
    public static void handleAfterInsert(List<Case> newCases) {
        if (newCases == null || newCases.isEmpty()) {
            System.debug('=== ExchangeCaseAssignmentRuleHandler.handleAfterInsert: Empty case list ===');
            return;
        }

        System.debug('=== ExchangeCaseAssignmentRuleHandler.handleAfterInsert START - Cases: ' + newCases.size() + ' ===');

        // Step 1: Get Record Type Ids
        Map<String, Id> rtMap = new Map<String, Id>();
        for (RecordType rt : [
            SELECT Id, DeveloperName
            FROM RecordType
            WHERE SObjectType = 'Case' AND DeveloperName IN (:INCOMING_EXCHANGE_RT, :OUTGOING_EXCHANGE_RT)
        ]) {
            rtMap.put(rt.DeveloperName, rt.Id);
        }

        if (rtMap.isEmpty()) {
            System.debug('❌ No record types found for Incoming/Outgoing Exchange');
            return;
        }

        Id incomingRtId = rtMap.get(INCOMING_EXCHANGE_RT);
        Id outgoingRtId = rtMap.get(OUTGOING_EXCHANGE_RT);
        System.debug('✓ Record Types - Incoming: ' + incomingRtId + ', Outgoing: ' + outgoingRtId);

        // Step 2: Get the predefined Case Team Template
        List<CaseTeamTemplate> templates = [
            SELECT Id
            FROM CaseTeamTemplate
            WHERE Name = :CASE_TEAM_NAME
            LIMIT 1
        ];

        if (templates.isEmpty()) {
            System.debug('❌ Case Team Template "' + CASE_TEAM_NAME + '" not found');
            return;
        }

        Id teamTemplateId = templates[0].Id;
        System.debug('✓ Case Team Template Found: ' + teamTemplateId);

        // Step 3: Get ASA and Finance users from the team template
        Id asaUserId;
        Id financeUserId;
        
        // First, get the team role IDs
        Map<String, Id> roleNameToId = new Map<String, Id>();
        for (CaseTeamRole ctr : [
            SELECT Id, Name
            FROM CaseTeamRole
            WHERE Name IN (:ASA_ROLE_NAME, :FINANCE_ROLE_NAME)
        ]) {
            roleNameToId.put(ctr.Name, ctr.Id);
        }
        
        System.debug('✓ Case Team Roles Found: ' + roleNameToId.size());
        for (String roleName : roleNameToId.keySet()) {
            System.debug('  - ' + roleName + ': ' + roleNameToId.get(roleName));
        }
        
        // Then get the team members
        List<Id> roleIds = new List<Id>(roleNameToId.values());
        if (!roleIds.isEmpty()) {
            for (CaseTeamTemplateMember member : [
                SELECT MemberId, TeamRoleId
                FROM CaseTeamTemplateMember
                WHERE TeamTemplateId = :teamTemplateId
                AND TeamRoleId IN :roleIds
            ]) {
                if (member.TeamRoleId == roleNameToId.get(ASA_ROLE_NAME)) {
                    asaUserId = member.MemberId;
                    System.debug('✓ ASA User Found: ' + asaUserId);
                } else if (member.TeamRoleId == roleNameToId.get(FINANCE_ROLE_NAME)) {
                    financeUserId = member.MemberId;
                    System.debug('✓ Finance User Found: ' + financeUserId);
                }
            }
        }

        if (asaUserId == null) {
            System.debug('❌ ASA User NOT found in template');
        }

        // Step 4: Separate eligible cases
        List<Case> newEligibleCases = new List<Case>();

        for (Case c : newCases) {
            if ((c.RecordTypeId == incomingRtId || c.RecordTypeId == outgoingRtId)) {
                newEligibleCases.add(c);
                System.debug('✓ Eligible Case: ' + c.Id + ' (RT: ' + c.RecordTypeId + ')');
            } else {
                System.debug('⚠ Case ' + c.Id + ' not eligible - RT: ' + c.RecordTypeId);
            }
        }

        // Step 5: On Insert → add team + assign ASA as owner
        if (!newEligibleCases.isEmpty() && asaUserId != null) {
            List<CaseTeamTemplateRecord> teamAssignments = new List<CaseTeamTemplateRecord>();
            List<Case> casesToUpdate = new List<Case>();

            for (Case c : newEligibleCases) {
                teamAssignments.add(new CaseTeamTemplateRecord(
                    ParentId = c.Id,
                    TeamTemplateId = teamTemplateId
                ));

                casesToUpdate.add(new Case(
                    Id = c.Id,
                    OwnerId = asaUserId
                ));
            }

            if (!teamAssignments.isEmpty()) {
                insert teamAssignments;
                System.debug('✓ Case Teams Assigned: ' + teamAssignments.size());
            }

            if (!casesToUpdate.isEmpty()) {
                isApplying = true;
                try {
                    update casesToUpdate;
                    System.debug('✓ Case Owners Updated to ASA: ' + casesToUpdate.size());
                } catch (Exception ex) {
                    System.debug('❌ Error updating case owners: ' + ex.getMessage());
                } finally {
                    isApplying = false;
                }
            }
        } else {
            if (newEligibleCases.isEmpty()) {
                System.debug('❌ No eligible cases found');
            }
            if (asaUserId == null) {
                System.debug('❌ ASA User ID is null - cannot assign teams');
            }
        }

        System.debug('=== ExchangeCaseAssignmentRuleHandler.handleAfterInsert END ===');
    }

    /**
     * ========================================
     * AFTER UPDATE: Finance stage + RO stage
     * ========================================
     */
    public static void applyOnAfterUpdate(List<Case> newCases, Map<Id, Case> oldMap) {
        if (isApplying || newCases == null || newCases.isEmpty() || oldMap == null) {
            return;
        }

        // Step 1: Get Record Type Ids
        Set<Id> recordTypeIds = new Set<Id>();
        for (Case c : newCases) {
            if (c.RecordTypeId != null) {
                recordTypeIds.add(c.RecordTypeId);
            }
        }

        if (recordTypeIds.isEmpty()) {
            return;
        }

        Map<Id, String> rtDevNameById = new Map<Id, String>();
        for (RecordType rt : [
            SELECT Id, DeveloperName
            FROM RecordType
            WHERE SObjectType = 'Case' AND Id IN :recordTypeIds
        ]) {
            rtDevNameById.put(rt.Id, rt.DeveloperName);
        }

        // Step 2: Get Case Team Template for Finance user lookup
        List<CaseTeamTemplate> templates = [
            SELECT Id
            FROM CaseTeamTemplate
            WHERE Name = :CASE_TEAM_NAME
            LIMIT 1
        ];

        Id teamTemplateId = templates.isEmpty() ? null : templates[0].Id;

        Id financeUserId = null;
        Id roUserId = null;

        if (teamTemplateId != null) {
            // Get Finance and RO team role IDs
            Map<String, Id> roleNameToId = new Map<String, Id>();
            for (CaseTeamRole ctr : [
                SELECT Id, Name
                FROM CaseTeamRole
                WHERE Name IN (:FINANCE_ROLE_NAME, :RO_ROLE_NAME)
            ]) {
                roleNameToId.put(ctr.Name, ctr.Id);
            }
            
            // Get Finance and RO users
            List<Id> roleIds = new List<Id>(roleNameToId.values());
            if (!roleIds.isEmpty()) {
                for (CaseTeamTemplateMember member : [
                    SELECT MemberId, TeamRoleId
                    FROM CaseTeamTemplateMember
                    WHERE TeamTemplateId = :teamTemplateId
                    AND TeamRoleId IN :roleIds
                ]) {
                    if (member.TeamRoleId == roleNameToId.get(FINANCE_ROLE_NAME)) {
                        financeUserId = member.MemberId;
                    } else if (member.TeamRoleId == roleNameToId.get(RO_ROLE_NAME)) {
                        roUserId = member.MemberId;
                    }
                }
            }
        }

        // If RO not found in template, try getting hardcoded RO user
        if (roUserId == null) {
            roUserId = getROUserId();
        }

        // Step 3: Separate cases by scenario
        List<Case> financeStagesCases = new List<Case>();
        List<Case> roStageCases = new List<Case>();

        for (Case c : newCases) {
            Case oldCase = oldMap.get(c.Id);
            String rtDevName = rtDevNameById.get(c.RecordTypeId);

            if (rtDevName == null) {
                continue;
            }

            // Finance Processing stage transition
            if (c.Status == FINANCE_STAGE && oldCase.Status != FINANCE_STAGE) {
                financeStagesCases.add(c);
            }

            // RO stage transitions
            Boolean isIncomingROStage = rtDevName == INCOMING_EXCHANGE_RT && INCOMING_RO_STATUSES.contains(c.Status);
            Boolean isOutgoingROStage = rtDevName == OUTGOING_EXCHANGE_RT && OUTGOING_RO_STATUSES.contains(c.Status);

            if ((isIncomingROStage || isOutgoingROStage) && c.OwnerId != roUserId) {
                roStageCases.add(c);
            }
        }

        List<Case> casesToUpdate = new List<Case>();

        // Step 4: Assign Finance user for Finance Processing stage
        if (!financeStagesCases.isEmpty() && financeUserId != null) {
            for (Case c : financeStagesCases) {
                casesToUpdate.add(new Case(
                    Id = c.Id,
                    OwnerId = financeUserId
                ));
            }
        }

        // Step 5: Assign RO user for RO stages
        if (!roStageCases.isEmpty() && roUserId != null) {
            for (Case c : roStageCases) {
                casesToUpdate.add(new Case(
                    Id = c.Id,
                    OwnerId = roUserId
                ));
            }
        }

        if (!casesToUpdate.isEmpty()) {
            isApplying = true;
            try {
                update casesToUpdate;
            } finally {
                isApplying = false;
            }
        }
    }

    private static Id getROUserId() {
        if (roUserId != null) {
            return roUserId;
        }

        List<User> users = [
            SELECT Id
            FROM User
            WHERE Username = :RO_USERNAME
            LIMIT 1
        ];
        if (!users.isEmpty()) {
            roUserId = users[0].Id;
        }
        return roUserId;
    }
}