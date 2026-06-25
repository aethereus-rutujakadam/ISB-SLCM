public without sharing class ClubMembershipLeadLimitHandler {

    // Helper: lightweight check whether a string looks like a Salesforce Id (15 or 18 alphanumeric chars)
    @TestVisible
    private static Boolean isIdLike(String s) {
        if (s == null) return false;
        Integer len = s.length();
        if (len != 15 && len != 18) return false;
        String regex = '^[0-9A-Za-z]{15,18}$';
        try {
            return Pattern.matches(regex, s);
        } catch (Exception ex) {
            return false;
        }
    }

    // Helper: normalize (trim + lower) for in-memory comparisons
    private static String normalize(String v) {
        if (v == null) return '';
        return v.trim().toLowerCase();
    }

    // Build canonical composite key used only in-memory for comparisons
    @TestVisible
    private static String buildKey(String programVal, String yearVal, String roleVal) {
        return normalize(programVal) + '::' + normalize(yearVal) + '::' + normalize(roleVal);
    }

    // Validate max 2 active Leads per Program + Academic Year
    // (does NOT depend on any custom composite field; queries existing records by Program__c & Academic_Year__c & Role__c)
    public static void validateLeadLimit(List<Club_Membership__c> newList, Map<Id, Club_Membership__c> oldMap) {
        if (newList == null || newList.isEmpty()) return;

        final String ACTIVE_STR = 'active';
        final String LEAD_STR = 'lead';

        // Map compositeKey -> count (existing + incoming within this transaction)
        Map<String, Integer> leadCounts = new Map<String, Integer>();
        // Keys we need to check against DB
        Set<String> keysToCheck = new Set<String>();
        // For SOQL IN lists
        Set<String> programVals = new Set<String>();
        Set<String> yearVals = new Set<String>();
        Set<Id> incomingIds = new Set<Id>();

        // First pass - build incoming keys for Lead + Active candidates
        for (Club_Membership__c cm : newList) {
            String programVal = (cm.Program__c == null) ? '' : String.valueOf(cm.Program__c).trim();
            String yearVal = (cm.Academic_Year__c == null) ? '' : cm.Academic_Year__c.trim();
            String roleVal = (cm.Role__c == null) ? '' : cm.Role__c.trim();

            String statusNew = (cm.Status__c == null) ? '' : cm.Status__c;
            Boolean willBeActive = normalize(statusNew) == ACTIVE_STR;
            Boolean isLead = normalize(roleVal) == LEAD_STR;

            if (isLead && willBeActive && !String.isBlank(programVal) && !String.isBlank(yearVal)) {
                String key = buildKey(programVal, yearVal, roleVal);
                if (!leadCounts.containsKey(key)) leadCounts.put(key, 0);
                keysToCheck.add(key);

                programVals.add(programVal);
                yearVals.add(yearVal);
                if (cm.Id != null) incomingIds.add(cm.Id);
            }
        }

        // Query existing active lead records matching those Program & Year combos (exclude incoming IDs)
        List<Club_Membership__c> existingLeads = new List<Club_Membership__c>();
        if (!programVals.isEmpty() && !yearVals.isEmpty()) {
            existingLeads = [
                SELECT Id, Program__c, Academic_Year__c, Role__c
                FROM Club_Membership__c
                WHERE Program__c IN :programVals
                  AND Academic_Year__c IN :yearVals
                  AND Role__c = 'Lead'
                  AND Status__c = 'Active'
                  AND Id NOT IN :incomingIds
            ];
        }

        // populate leadCounts with existing counts
        for (Club_Membership__c ex : existingLeads) {
            String p = (ex.Program__c == null) ? '' : String.valueOf(ex.Program__c).trim();
            String y = (ex.Academic_Year__c == null) ? '' : ex.Academic_Year__c.trim();
            String r = (ex.Role__c == null) ? '' : ex.Role__c.trim();
            String key = buildKey(p, y, r);
            Integer cur = leadCounts.containsKey(key) ? leadCounts.get(key) : 0;
            leadCounts.put(key, cur + 1);
        }

        // Now validate incoming records: if candidate is Lead+Active, check count limit (limit = 2)
        for (Club_Membership__c cm : newList) {
            String programVal = (cm.Program__c == null) ? '' : String.valueOf(cm.Program__c).trim();
            String yearVal = (cm.Academic_Year__c == null) ? '' : cm.Academic_Year__c.trim();
            String roleVal = (cm.Role__c == null) ? '' : cm.Role__c.trim();

            String statusNew = (cm.Status__c == null) ? '' : cm.Status__c;
            Boolean willBeActive = normalize(statusNew) == ACTIVE_STR;
            Boolean isLead = normalize(roleVal) == LEAD_STR;

            if (!isLead || !willBeActive) continue;
            if (String.isBlank(programVal) || String.isBlank(yearVal)) continue;

            String key = buildKey(programVal, yearVal, roleVal);
            Integer cur = leadCounts.containsKey(key) ? leadCounts.get(key) : 0;
            cur++; // include this incoming record
            if (cur > 2) {
                cm.addError('Only 2 active Lead roles allowed for same Program and Academic Year.');
            } else {
                leadCounts.put(key, cur);
            }
        }
    }

   // Validate single active membership per Program/Year/Role for non-exempt record types
    // (does not use Program__r and works with Program__c and Academic_Year__c as formula/text)
    public static void validate(List<Club_Membership__c> newRecs, Map<Id, Club_Membership__c> oldMap) {
        if (newRecs == null || newRecs.isEmpty()) return;

        // Names of exempt record types stored in Club_Record_Type__c (formula/text)
        Set<String> exemptRecordTypes = new Set<String>{ 'Professional_Club', 'Social_Club' };
        final String ACTIVE_STR = 'active';

        // incoming bucket by in-memory key
        Map<String, List<Club_Membership__c>> incomingByKey = new Map<String, List<Club_Membership__c>>();
        Set<String> programVals = new Set<String>();
        Set<String> yearVals = new Set<String>();
        Set<String> roleVals = new Set<String>();
        Set<Id> incomingIds = new Set<Id>();

        // 1) Build buckets of incoming records that WILL be Active and are non-exempt
        for (Club_Membership__c r : newRecs) {
            String rtName = (r.Club_Record_Type__c == null) ? '' : String.valueOf(r.Club_Record_Type__c).trim();
            if (rtName != '' && exemptRecordTypes.contains(rtName)) {
                continue; // exempt, skip
            }

            String statusNew = (r.Status__c == null) ? '' : r.Status__c;
            Boolean isActiveNew = normalize(statusNew) == ACTIVE_STR;
            if (!isActiveNew) {
                // not active in new state — still set key optionally but skip validation
            }

            // require components present
            if (r.Program__c == null || String.isBlank(r.Academic_Year__c) || String.isBlank(r.Role__c)) {
                continue;
            }

            String programVal = String.valueOf(r.Program__c).trim();
            String yearVal = r.Academic_Year__c.trim();
            String roleVal = r.Role__c.trim();
            String key = buildKey(programVal, yearVal, roleVal);

            if (!incomingByKey.containsKey(key)) incomingByKey.put(key, new List<Club_Membership__c>());
            incomingByKey.get(key).add(r);

            // collect for SOQL
            programVals.add(programVal);
            yearVals.add(yearVal);
            roleVals.add(roleVal);
            if (r.Id != null) incomingIds.add(r.Id);
        }

        if (incomingByKey.isEmpty()) return;

        // 2) intra-batch duplicates: allow first in bucket, error the rest
        for (String k : incomingByKey.keySet()) {
            List<Club_Membership__c> bucket = incomingByKey.get(k);
            if (bucket.size() > 1) {
                Boolean first = true;
                for (Club_Membership__c rec : bucket) {
                    if (first) {
                        first = false;
                    } else {
                        rec.addError('Duplicate within upload: only one active membership allowed for this Program, Academic Year and Role in the same upload.');
                    }
                }
            }
        }

        // 3) Query existing active records matching Program, Year and Role (exclude incoming Ids)
        List<Club_Membership__c> existing = new List<Club_Membership__c>();
        if (!programVals.isEmpty() && !yearVals.isEmpty() && !roleVals.isEmpty()) {
            existing = [
                SELECT Id, Program__c, Academic_Year__c, Role__c
                FROM Club_Membership__c
                WHERE Program__c IN :programVals
                  AND Academic_Year__c IN :yearVals
                  AND Role__c IN :roleVals
                  AND Status__c = 'Active'
                  AND Id NOT IN :incomingIds
            ];
        }

        // 4) build set of existing normalized keys
        Set<String> existingKeys = new Set<String>();
        for (Club_Membership__c e : existing) {
            String p = (e.Program__c == null) ? '' : String.valueOf(e.Program__c).trim();
            String y = (e.Academic_Year__c == null) ? '' : e.Academic_Year__c.trim();
            String rRole = (e.Role__c == null) ? '' : e.Role__c.trim();
            existingKeys.add(buildKey(p, y, rRole));
        }

        // 5) For each incoming bucket, if existingKeys contains the key -> error all incoming in that bucket
        for (String key : incomingByKey.keySet()) {
            if (existingKeys.contains(key)) {
                for (Club_Membership__c rec : incomingByKey.get(key)) {
                    rec.addError('An active Club Membership already exists for this Program, Academic Year and Role. Only one active membership allowed.');
                }
            }
            // else: we already handled intra-batch duplicates above (allowed first, error rest)
        }
    }

    // Validate no duplicate Professional Club memberships for same Contact + Club
    // unless the existing one is Inactive + Rejected
    public static void validateProfessionalDuplicates(List<Club_Membership__c> newList, Map<Id, Club_Membership__c> oldMap) {
        Set<Id> clubIds = new Set<Id>();
        for (Club_Membership__c cm : newList) {
            if (cm.Club__c != null) clubIds.add(cm.Club__c);
        }
        if (clubIds.isEmpty()) return;

        // Bypassing formula field since it's null during 'before insert'
        Map<Id, String> clubToRtName = new Map<Id, String>();
        for (Club__c c : [SELECT Id, RecordType.DeveloperName FROM Club__c WHERE Id IN :clubIds]) {
            clubToRtName.put(c.Id, c.RecordType.DeveloperName);
        }

        Set<Id> contactIds = new Set<Id>();
        List<Club_Membership__c> proMemberships = new List<Club_Membership__c>();

        for (Club_Membership__c cm : newList) {
            String rtName = clubToRtName.get(cm.Club__c);
            if (rtName == 'Professional_Club' && cm.Contact__c != null) {
                proMemberships.add(cm);
                contactIds.add(cm.Contact__c);
            }
        }

        if (proMemberships.isEmpty()) return;

        // targeted cleanup: Remove pre-existing Rejected/Stale records for the SAME contact and club combinations
        // This allows the Flow to successfully insert new records without hitting duplicate rules or validation errors.
        List<Club_Membership__c> existingToClear = [
            SELECT Id, Contact__c, Club__c
            FROM Club_Membership__c
            WHERE Contact__c IN :contactIds
              AND Club__c IN :clubIds
              AND Club_Record_Type__c = 'Professional_Club'
              AND Status__c != 'Active'
              AND Approval_Status__c != 'Approved'
              AND Approval_Status__c != 'Pending Approval'
        ];
        
        if (!existingToClear.isEmpty()) {
            delete existingToClear;
        }

        // Intra-batch duplicate check
        Map<String, Club_Membership__c> batchMap = new Map<String, Club_Membership__c>();
        for (Club_Membership__c cm : proMemberships) {
            String key = cm.Contact__c + '-' + cm.Club__c;
            if (batchMap.containsKey(key)) {
                cm.addError('Duplicate Professional Club membership for the same student and club found in this request.');
            } else {
                batchMap.put(key, cm);
            }
        }

        // Query existing blocking records in DB (Active or Pending Approval)
        List<Club_Membership__c> existing = [
            SELECT Id, Contact__c, Club__c
            FROM Club_Membership__c
            WHERE Contact__c IN :contactIds
              AND Club__c IN :clubIds
              AND Club_Record_Type__c = 'Professional_Club'
              AND (
                  Status__c = 'Active' 
                  OR (Status__c = 'Inactive' AND Approval_Status__c = 'Pending Approval')
              )
              AND Id NOT IN :proMemberships
        ];

        if (existing.isEmpty()) return;

        Map<String, Id> dbMap = new Map<String, Id>();
        for (Club_Membership__c ex : existing) {
            dbMap.put(ex.Contact__c + '-' + ex.Club__c, ex.Id);
        }

        for (Club_Membership__c cm : proMemberships) {
            String key = cm.Contact__c + '-' + cm.Club__c;
            if (dbMap.containsKey(key)) {
                cm.addError('A Professional Club membership already exists or is pending approval for this student and club.');
            }
        }
    }

    public static void updateRegisteredClubCount(Map<Id, Club_Membership__c> newMap, Map<Id, Club_Membership__c> oldMap) {
        Set<Id> contactIds = new Set<Id>();

        if (newMap != null) {
            for (Club_Membership__c cm : newMap.values()) {
                if (cm.Contact__c != null) {
                    contactIds.add(cm.Contact__c);
                }
                // Handle Contact transfer
                if (oldMap != null && oldMap.containsKey(cm.Id)) {
                   Id oldContactId = oldMap.get(cm.Id).Contact__c;
                   if (oldContactId != null && oldContactId != cm.Contact__c) {
                       contactIds.add(oldContactId);
                   }
                }
            }
        }

        if (newMap == null && oldMap != null) {
            // Delete operation
            for (Club_Membership__c cm : oldMap.values()) {
                if (cm.Contact__c != null) {
                    contactIds.add(cm.Contact__c);
                }
            }
        }

        if (contactIds.isEmpty()) return;

        // Query active professional club counts for affected contacts
        List<Contact> contactsToUpdate = new List<Contact>();
        
        // Aggregate query to get counts
        Map<Id, Integer> contactToCountMap = new Map<Id, Integer>();
        for (Id cId : contactIds) {
            contactToCountMap.put(cId, 0);
        }

        List<AggregateResult> results = [
            SELECT Contact__c, COUNT(Id) cnt
            FROM Club_Membership__c
            WHERE Contact__c IN :contactIds
              AND Status__c = 'Active'
              AND Club_Record_Type__c = 'Professional_Club'
              AND Approval_Status__c = 'Approved'
            GROUP BY Contact__c
        ];

        for (AggregateResult ar : results) {
            Id cId = (Id)ar.get('Contact__c');
            Integer count = (Integer)ar.get('cnt');
            contactToCountMap.put(cId, count);
        }

        for (Id cId : contactToCountMap.keySet()) {
            contactsToUpdate.add(new Contact(
                Id = cId,
                Registered_Club__c = contactToCountMap.get(cId)
            ));
        }

        if (!contactsToUpdate.isEmpty()) {
            update contactsToUpdate;
        }
    }

    public static void catchApprovalDetails(Map<Id, Club_Membership__c> newMap, Map<Id, Club_Membership__c> oldMap) {
        Set<Id> approvedIds = new Set<Id>();
        for (Club_Membership__c cm : newMap.values()) {
            if (cm.Approval_Status__c == 'Approved' && oldMap.get(cm.Id).Approval_Status__c != 'Approved') {
                approvedIds.add(cm.Id);
            }
        }
        if (approvedIds.isEmpty()) return;

        Map<Id, ProcessInstanceStep> latestStepMap = new Map<Id, ProcessInstanceStep>();
        for (ProcessInstanceStep step : [
            SELECT ProcessInstance.TargetObjectId, ActorId, Comments, CreatedDate
            FROM ProcessInstanceStep
            WHERE ProcessInstance.TargetObjectId IN :approvedIds
            ORDER BY CreatedDate DESC
        ]) {
            if (!latestStepMap.containsKey(step.ProcessInstance.TargetObjectId)) {
                latestStepMap.put(step.ProcessInstance.TargetObjectId, step);
            }
        }

        List<Club_Membership__c> updates = new List<Club_Membership__c>();
        for (Id recId : approvedIds) {
            if (latestStepMap.containsKey(recId)) {
                ProcessInstanceStep step = latestStepMap.get(recId);
                updates.add(new Club_Membership__c(
                    Id = recId,
                    Approver__c = step.ActorId,
                    Approval_Notes__c = step.Comments
                ));
            }
        }
        if (!updates.isEmpty()) {
            update updates;
        }
    }
}