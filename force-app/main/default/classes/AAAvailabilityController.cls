public without sharing class AAAvailabilityController {

    /**
     * Get Programs for selection.
     * RULE: Only include Programs that have at least one active AcademicTerm
     *       which itself has at least one active AcademicSession.
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getPrograms() {
        List<Map<String, String>> options = new List<Map<String, String>>();
        try {
            // Collect Program Ids reachable through Term → Session chain
            Set<Id> validProgramIds = new Set<Id>();
            for (AcademicSession sess : [
                SELECT Id, AcademicTerm.Program__c
                FROM   AcademicSession
                WHERE  IsActive = true
                AND    AcademicTerm.IsActive = true
                AND    AcademicTerm.Program__c != null
            ]) {
                validProgramIds.add(sess.AcademicTerm.Program__c);
            }

            if (!validProgramIds.isEmpty()) {
                for (Program prog : [
                    SELECT Id, Name
                    FROM   Program
                    WHERE  Id IN :validProgramIds
                    AND    IsActive = true
                    ORDER BY Name ASC
                ]) {
                    options.add(new Map<String, String>{ 'label' => prog.Name, 'value' => prog.Id });
                }
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error loading programs: ' + e.getMessage());
        }
        return options;
    }

    /**
     * Get Academic Terms (Cohorts) filtered by Program.
     * RULE: Only include active AcademicTerms that have at least one active AcademicSession.
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getAcademicTerms(Id programId) {
        List<Map<String, String>> options = new List<Map<String, String>>();
        try {
            // Collect Term Ids that own at least one active session
            Set<Id> termIdsWithSessions = new Set<Id>();
            List<AcademicSession> sessions = (programId != null)
                ? [
                    SELECT Id, AcademicTermId
                    FROM   AcademicSession
                    WHERE  IsActive = true
                    AND    AcademicTerm.Program__c = :programId
                    AND    AcademicTerm.IsActive   = true
                  ]
                : [
                    SELECT Id, AcademicTermId
                    FROM   AcademicSession
                    WHERE  IsActive = true
                    AND    AcademicTerm.IsActive = true
                  ];

            for (AcademicSession sess : sessions) {
                termIdsWithSessions.add(sess.AcademicTermId);
            }

            if (!termIdsWithSessions.isEmpty()) {
                List<AcademicTerm> terms = (programId != null)
                    ? [
                        SELECT Id, Name
                        FROM   AcademicTerm
                        WHERE  Id IN :termIdsWithSessions
                        AND    Program__c = :programId
                        AND    IsActive   = true
                        ORDER BY Name ASC
                      ]
                    : [
                        SELECT Id, Name
                        FROM   AcademicTerm
                        WHERE  Id IN :termIdsWithSessions
                        AND    IsActive = true
                        ORDER BY Name ASC
                      ];

                for (AcademicTerm t : terms) {
                    options.add(new Map<String, String>{ 'label' => t.Name, 'value' => t.Id });
                }
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching Academic Terms: ' + e.getMessage());
        }
        return options;
    }

    /**
     * Get Academic Sessions under an Academic Term
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getAcademicSessionsForTerm(Id academicTermId) {
        List<Map<String, String>> options = new List<Map<String, String>>();
        try {
            if (academicTermId == null) return options;
            for (AcademicSession s : [
                SELECT Id, Name FROM AcademicSession
                WHERE AcademicTermId = :academicTermId
                AND IsActive = true
                ORDER BY From_Date__c ASC NULLS LAST, Name ASC
            ]) {
                options.add(new Map<String, String>{ 'label' => s.Name, 'value' => s.Id });
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching Academic Sessions: ' + e.getMessage());
        }
        return options;
    }

    /**
     * Get existing AA Availability records (optionally filtered by Program + AcademicTerm)
     */
    @AuraEnabled
    public static List<AA_Availability__c> getExistingAvailability(Id aaProfileId, Id programId, Id academicTermId) {
        try {
            if (aaProfileId == null) return new List<AA_Availability__c>();

            String soql = 'SELECT Id, Name, Academic_Term__c, Academic_Term__r.Name, Academic_Session__c, '
                        + 'Academic_Session__r.Name, Availability__c, From_Date__c, To_Date__c, '
                        + 'Program__c, Program__r.Name, Notes__c '
                        + 'FROM AA_Availability__c WHERE AA_Profile__c = :aaProfileId';

            if (programId    != null) soql += ' AND Program__c       = :programId';
            if (academicTermId != null) soql += ' AND Academic_Term__c = :academicTermId';

            soql += ' ORDER BY Academic_Session__r.From_Date__c ASC NULLS LAST, CreatedDate ASC';
            return Database.query(soql);
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching existing availability: ' + e.getMessage());
        }
    }

    // ── DTO for each row sent from LWC ────────────────────────────────────────
    public class AvailabilityRow {
        @AuraEnabled public String recordId          { get; set; } // Salesforce Id of existing record (null for new)
        @AuraEnabled public String programId         { get; set; }
        @AuraEnabled public String academicTermId    { get; set; }
        @AuraEnabled public String academicSessionId { get; set; }
        @AuraEnabled public String availability      { get; set; }
        @AuraEnabled public String fromDate          { get; set; }
        @AuraEnabled public String toDate            { get; set; }
        @AuraEnabled public String notes             { get; set; }
    }

    /**
     * Save all availability rows in a single transaction.
     * - Uses Savepoint so any failure rolls back ALL changes.
     * - Detects existing records via explicit Id or context match, preventing duplicates.
     */
    @AuraEnabled
    public static void saveAllAvailability(Id aaProfileId, List<AvailabilityRow> rows) {

        if (aaProfileId == null || rows == null || rows.isEmpty()) {
            throw new AuraHandledException('Missing required parameters');
        }

        Savepoint sp = Database.setSavepoint();

        try {
            // ── 1. Validate rows and cast all String IDs up front ─────────────
            for (AvailabilityRow r : rows) {
                if (String.isBlank(r.academicSessionId) || String.isBlank(r.availability)) {
                    throw new AuraHandledException('Incomplete row: Session and Availability are required.');
                }
                
                if (r.availability == 'Available - Partial') {
                    if (String.isNotBlank(r.fromDate) && String.isNotBlank(r.toDate)) {
                        if (Date.valueOf(r.fromDate) > Date.valueOf(r.toDate)) {
                            throw new AuraHandledException('From Date cannot be later than To Date.');
                        }
                    } else if (String.isBlank(r.fromDate) || String.isBlank(r.toDate)) {
                        throw new AuraHandledException('From Date and To Date are required for partial availability.');
                    }
                }
            }

            // ── 2. Fetch profile name ─────────────────────────────────────────
            AA_Profile__c aaProfile = [SELECT Name FROM AA_Profile__c WHERE Id = :aaProfileId LIMIT 1];

            // ── 3. Collect Ids for bulk queries ───────────────────────────────
            Set<Id> sessionIds  = new Set<Id>();
            Set<Id> explicitIds = new Set<Id>();

            for (AvailabilityRow r : rows) {
                sessionIds.add((Id)r.academicSessionId);
                if (String.isNotBlank(r.recordId)) {
                    explicitIds.add((Id)r.recordId);
                }
            }

            // ── 4. Session name lookup ────────────────────────────────────────
            Map<Id, String> sessionNameById = new Map<Id, String>();
            for (AcademicSession s : [SELECT Id, Name FROM AcademicSession WHERE Id IN :sessionIds]) {
                sessionNameById.put(s.Id, s.Name);
            }

            // ── 5. Fetch existing records by explicit Id ───────────────────────
            Map<Id, AA_Availability__c> byId = new Map<Id, AA_Availability__c>();
            if (!explicitIds.isEmpty()) {
                for (AA_Availability__c rec : [
                    SELECT Id, AA_Profile__c, Program__c, Academic_Term__c, Academic_Session__c
                    FROM AA_Availability__c WHERE Id IN :explicitIds
                ]) {
                    byId.put(rec.Id, rec);
                }
            }

            // ── 6. Fetch existing records by Profile + Session (for rows without Id) ──
            //       Key: sessionId string (profile is always the same aaProfileId)
            Set<Id> newSessionIds = new Set<Id>();
            for (AvailabilityRow r : rows) {
                if (String.isBlank(r.recordId)) {
                    newSessionIds.add((Id)r.academicSessionId);
                }
            }
            Map<Id, AA_Availability__c> bySession = new Map<Id, AA_Availability__c>();
            if (!newSessionIds.isEmpty()) {
                for (AA_Availability__c rec : [
                    SELECT Id, AA_Profile__c, Academic_Session__c
                    FROM AA_Availability__c
                    WHERE AA_Profile__c       = :aaProfileId
                    AND   Academic_Session__c IN :newSessionIds
                ]) {
                    bySession.put(rec.Academic_Session__c, rec);
                }
            }

            // ── 7. Duplicate detection within submitted batch ─────────────────
            Set<Id> seenSessions = new Set<Id>();
            for (AvailabilityRow r : rows) {
                Id sessId = (Id)r.academicSessionId;
                if (seenSessions.contains(sessId)) {
                    String sessName = sessionNameById.containsKey(sessId) ? sessionNameById.get(sessId) : String.valueOf(sessId);
                    throw new AuraHandledException('Duplicate entry for session "' + sessName + '". Each session can only have one availability entry.');
                }
                seenSessions.add(sessId);
            }

            // ── 8. Build records list for upsert ──────────────────────────────
            List<AA_Availability__c> toUpsert = new List<AA_Availability__c>();

            for (AvailabilityRow r : rows) {
                Id sessId  = (Id)r.academicSessionId;
                Id termId  = (Id)r.academicTermId;
                Id progId  = (Id)r.programId;
                Id recId   = String.isNotBlank(r.recordId) ? (Id)r.recordId : null;

                AA_Availability__c record;

                if (recId != null && byId.containsKey(recId)) {
                    // Update specific existing record by Id
                    record = byId.get(recId);
                } else if (bySession.containsKey(sessId)) {
                    // Update existing record found by Profile+Session match
                    record = bySession.get(sessId);
                } else {
                    // Create new — only set master-detail on insert
                    record = new AA_Availability__c(AA_Profile__c = aaProfileId);
                }

                // Name
                String sessName = sessionNameById.containsKey(sessId) ? sessionNameById.get(sessId) : '';
                String recName  = aaProfile.Name + ' - ' + sessName + ' - ' + r.availability;
                if (recName.length() > 80) recName = recName.substring(0, 80);

                record.Name                = recName;
                record.Program__c          = progId;
                record.Academic_Term__c    = termId;
                record.Academic_Session__c = sessId;
                record.Availability__c     = r.availability;
                record.Notes__c            = r.notes;

                if (r.availability == 'Available - Partial') {
                    record.From_Date__c = String.isNotBlank(r.fromDate) ? Date.valueOf(r.fromDate) : null;
                    record.To_Date__c   = String.isNotBlank(r.toDate)   ? Date.valueOf(r.toDate)   : null;
                } else {
                    record.From_Date__c = null;
                    record.To_Date__c   = null;
                }

                toUpsert.add(record);
            }

            // ── 9. Single DML — all or nothing ───────────────────────────────
            upsert toUpsert;

        } catch (AuraHandledException ahe) {
            Database.rollback(sp);
            throw ahe;
        } catch (Exception e) {
            Database.rollback(sp);
            throw new AuraHandledException('Error saving availability: ' + e.getMessage());
        }
    }

    /**
     * Delete an availability record
     */
    @AuraEnabled
    public static void deleteAvailability(Id recordId) {
        try {
            if (recordId == null) return;
            delete [SELECT Id FROM AA_Availability__c WHERE Id = :recordId];
        } catch (Exception e) {
            throw new AuraHandledException('Error deleting availability: ' + e.getMessage());
        }
    }
}