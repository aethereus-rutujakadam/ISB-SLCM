public without sharing class CourseOfferingPtcpResultHandler {
    
    public static void handleAfter(List<CourseOfferingPtcpResult> newList, Map<Id, CourseOfferingPtcpResult> oldMap) {
        Set<Id> enrollmentIds = new Set<Id>();
        Set<Id> participantIds = new Set<Id>();
        
        System.debug('@@@ newList size: ' + newList.size());
        for (CourseOfferingPtcpResult res : newList) {
            System.debug('@@@ Processing Result Id: ' + res.Id + ', Participant: ' + res.CourseOfferingParticipantId);
            if (res.CourseOfferingParticipantId != null) {
                participantIds.add(res.CourseOfferingParticipantId);
            }
        }
        
        if (!participantIds.isEmpty()) {
            Map<Id, CourseOfferingParticipant> partMap = new Map<Id, CourseOfferingParticipant>([
                SELECT Id, ParticipantContactId, CourseOffering.AcademicSessionId
                FROM CourseOfferingParticipant
                WHERE Id IN :participantIds
            ]);
            
            Set<Id> contactIds = new Set<Id>();
            Set<Id> sessionIds = new Set<Id>();
            for (CourseOfferingParticipant cop : partMap.values()) {
                if (cop.ParticipantContactId != null) contactIds.add(cop.ParticipantContactId);
                if (cop.CourseOffering.AcademicSessionId != null) sessionIds.add(cop.CourseOffering.AcademicSessionId);
            }
            
            System.debug('@@@ contactIds: ' + contactIds);
            System.debug('@@@ sessionIds: ' + sessionIds);
            
            if (!contactIds.isEmpty() && !sessionIds.isEmpty()) {
                List<Enrollment_Session__c> esList = [
                    SELECT Program_Enrollment__c, Program_Enrollment__r.ContactId, Academic_Session__c
                    FROM Enrollment_Session__c
                    WHERE Program_Enrollment__r.ContactId IN :contactIds AND Academic_Session__c IN :sessionIds
                ];
                System.debug('@@@ Found Enrollment Sessions: ' + esList.size());
                for (Enrollment_Session__c es : esList) {
                    if (es.Program_Enrollment__c != null) {
                        enrollmentIds.add(es.Program_Enrollment__c);
                    }
                }
            }
        }
        
        System.debug('@@@ Final enrollmentIds: ' + enrollmentIds);
        if (!enrollmentIds.isEmpty()) {
            calculateGpaAndCgpa(enrollmentIds);
        }
    }

    public static void calculateGpaAndCgpa(Set<Id> enrollmentIds) {

        System.debug('');
        System.debug('========== [calculateGpaAndCgpa] START ==========');
        System.debug('@@@ Input: Processing ' + enrollmentIds.size() + ' Program Enrollment Id(s): ' + enrollmentIds);

        // -----------------------------------------------------------------------
        // STEP 1: Fetch Enrollment Sessions for the given Program Enrollments
        // -----------------------------------------------------------------------
        List<Enrollment_Session__c> enrollmentSessions = [
            SELECT Id, Program_Enrollment__c, Academic_Session__c, GPA__c,
                   Total_Attempted_Credits__c, Total_Earned_Credits__c, Total_Failed_Courses__c,
                   Program_Enrollment__r.ContactId, Academic_Session__r.From_Date__c
            FROM Enrollment_Session__c
            WHERE Program_Enrollment__c IN :enrollmentIds
            ORDER BY Academic_Session__r.From_Date__c ASC NULLS LAST
        ];

        System.debug('--- STEP 1: Enrollment Sessions ---');
        System.debug('@@@ Total Enrollment Sessions fetched: ' + enrollmentSessions.size());
        Set<Id> contactIds = new Set<Id>();
        for (Enrollment_Session__c es : enrollmentSessions) {
            if (es.Program_Enrollment__r.ContactId != null) {
                contactIds.add(es.Program_Enrollment__r.ContactId);
            }
            System.debug('    -> ES Id: ' + es.Id
                + ' | PE Id: '            + es.Program_Enrollment__c
                + ' | ContactId: '        + es.Program_Enrollment__r.ContactId
                + ' | Session Id: '       + es.Academic_Session__c
                + ' | Session From: '     + es.Academic_Session__r.From_Date__c
                + ' | Existing GPA: '     + es.GPA__c
                + ' | Existing Earned: '  + es.Total_Earned_Credits__c
                + ' | Existing Attempted: ' + es.Total_Attempted_Credits__c
                + ' | Existing Failed: '  + es.Total_Failed_Courses__c);
        }
        System.debug('@@@ Unique ContactIds derived from Enrollment Sessions: ' + contactIds);

        // -----------------------------------------------------------------------
        // STEP 2: Fetch all CourseOfferingPtcpResults for those contacts
        // -----------------------------------------------------------------------
        List<CourseOfferingPtcpResult> allResults = [
            SELECT Id, Earned_Credits__c, Attempted_Credits__c, Grade_Letter__c,
                   CourseOfferingParticipant.ParticipantContactId,
                   CourseOfferingParticipant.CourseOffering.AcademicSessionId,
                   CourseOfferingParticipant.Course_Type__c
            FROM CourseOfferingPtcpResult
            WHERE CourseOfferingParticipant.ParticipantContactId IN :contactIds
        ];

        System.debug('--- STEP 2: CourseOfferingPtcpResults ---');
        System.debug('@@@ Total Results fetched across all contacts: ' + allResults.size());
        for (CourseOfferingPtcpResult res : allResults) {
            System.debug('    -> Result Id: '      + res.Id
                + ' | ContactId: '                 + res.CourseOfferingParticipant.ParticipantContactId
                + ' | Session Id: '                + res.CourseOfferingParticipant.CourseOffering.AcademicSessionId
                + ' | Course Type: '               + res.CourseOfferingParticipant.Course_Type__c
                + ' | Grade: '                     + res.Grade_Letter__c
                + ' | Earned Credits: '            + res.Earned_Credits__c
                + ' | Attempted Credits: '         + res.Attempted_Credits__c);
        }

        // -----------------------------------------------------------------------
        // STEP 3: Build Bridge Map: (ContactId + '-' + SessionId) -> ProgramEnrollmentId
        // Needed because Results are linked to Contact+Session, not directly to PE
        // -----------------------------------------------------------------------
        Map<String, Id> bridgeMap = new Map<String, Id>();
        System.debug('--- STEP 3: Bridge Map (ContactId-SessionId -> PEId) ---');
        for (Enrollment_Session__c es : enrollmentSessions) {
            String key = es.Program_Enrollment__r.ContactId + '-' + es.Academic_Session__c;
            bridgeMap.put(key, es.Program_Enrollment__c);
            System.debug('    -> Bridge Key: [' + key + '] => PE Id: ' + es.Program_Enrollment__c);
        }
        System.debug('@@@ Bridge Map size: ' + bridgeMap.size());

        // -----------------------------------------------------------------------
        // STEP 4: Group Results by ProgramEnrollmentId -> SessionId -> [Results]
        // -----------------------------------------------------------------------
        Map<Id, Map<Id, List<CourseOfferingPtcpResult>>> enrollmentToSessionResults = new Map<Id, Map<Id, List<CourseOfferingPtcpResult>>>();
        Integer skippedResults = 0;
        System.debug('--- STEP 4: Grouping Results by PE -> Session ---');
        for (CourseOfferingPtcpResult res : allResults) {
            Id sessionId = res.CourseOfferingParticipant.CourseOffering.AcademicSessionId;
            Id contactId = res.CourseOfferingParticipant.ParticipantContactId;
            Id peId      = null;

            if (contactId != null && sessionId != null) {
                String bridgeKey = contactId + '-' + sessionId;
                peId = bridgeMap.get(bridgeKey);
                System.debug('    -> Result Id: ' + res.Id + ' | BridgeKey: [' + bridgeKey + '] => Resolved PE Id: ' + peId);
            }

            if (peId == null || !enrollmentIds.contains(peId)) {
                skippedResults++;
                System.debug('    !! SKIPPED Result Id: ' + res.Id
                    + ' (PE Id resolved: ' + peId
                    + ', in target enrollments: ' + (peId != null ? enrollmentIds.contains(peId) : false) + ')');
                continue;
            }

            if (!enrollmentToSessionResults.containsKey(peId)) {
                enrollmentToSessionResults.put(peId, new Map<Id, List<CourseOfferingPtcpResult>>());
            }
            if (!enrollmentToSessionResults.get(peId).containsKey(sessionId)) {
                enrollmentToSessionResults.get(peId).put(sessionId, new List<CourseOfferingPtcpResult>());
            }
            enrollmentToSessionResults.get(peId).get(sessionId).add(res);
        }
        System.debug('@@@ Results grouped into ' + enrollmentToSessionResults.size() + ' PE(s). Skipped (no PE match): ' + skippedResults);

        // -----------------------------------------------------------------------
        // STEP 5: Per-Enrollment calculation
        // -----------------------------------------------------------------------
        List<Enrollment_Session__c>     sessionsToUpdate    = new List<Enrollment_Session__c>();
        Map<Id, ProgramEnrollment>      enrollmentsToUpdate = new Map<Id, ProgramEnrollment>();

        System.debug('--- STEP 5: Per-Enrollment GPA / CGPA Calculation ---');
        for (Id peId : enrollmentIds) {
            System.debug('');
            System.debug('  ====== Processing PE Id: ' + peId + ' ======');

            Double electiveEarned    = 0;
            Double electiveAttempted = 0;
            Double coreEarned        = 0;
            Double coreAttempted     = 0;

            // Collect sessions that belong to this PE (already ordered by From_Date ASC)
            List<Enrollment_Session__c> peSessions = new List<Enrollment_Session__c>();
            for (Enrollment_Session__c es : enrollmentSessions) {
                if (es.Program_Enrollment__c == peId) {
                    peSessions.add(es);
                }
            }
            System.debug('  @@@ PE ' + peId + ' has ' + peSessions.size() + ' Enrollment Session(s)');

            // Map: Session Id -> [termEarned, termAttempted, termFailed]
            // Stores freshly-computed term totals so STEP 5B CGPA rollup always
            // uses the latest calculated values, NOT stale DB-persisted values.
            Map<Id, Double[]> sessionTotalsMap = new Map<Id, Double[]>();

            // ------------------------------------------------------------------
            // STEP 5A: Per-Session (Term) GPA calculation
            // ------------------------------------------------------------------
            for (Enrollment_Session__c es : peSessions) {
                Double  termEarned    = 0;
                Double  termAttempted = 0;
                Integer termFailed    = 0;

                System.debug('');
                System.debug('  --- Term: Session Id: ' + es.Academic_Session__c
                    + ' | Session From: ' + es.Academic_Session__r.From_Date__c);

                Boolean hasResults = enrollmentToSessionResults.containsKey(peId)
                                  && enrollmentToSessionResults.get(peId).containsKey(es.Academic_Session__c);

                if (hasResults) {
                    List<CourseOfferingPtcpResult> termResults = enrollmentToSessionResults.get(peId).get(es.Academic_Session__c);
                    System.debug('  @@@ Found ' + termResults.size() + ' result(s) for this session. Starting accumulation...');

                    for (CourseOfferingPtcpResult res : termResults) {
                        Double  earned    = res.Earned_Credits__c   != null ? res.Earned_Credits__c   : 0;
                        Double  attempted = res.Attempted_Credits__c != null ? res.Attempted_Credits__c : 0;
                        String  grade     = res.Grade_Letter__c;
                        String  courseType = res.CourseOfferingParticipant.Course_Type__c;

                        // Running totals BEFORE this result
                        Double prevTermEarned    = termEarned;
                        Double prevTermAttempted = termAttempted;

                        termEarned    += earned;
                        termAttempted += attempted;

                        if (grade == 'F') {
                            termFailed++;
                        }

                        // Core / Elective split
                        if (courseType == 'Elective') {
                            electiveEarned    += earned;
                            electiveAttempted += attempted;
                        } else if (courseType == 'Core') {
                            coreEarned    += earned;
                            coreAttempted += attempted;
                        }

                        System.debug('      Result Id: '    + res.Id
                            + ' | Grade: '                  + grade
                            + ' | CourseType: '             + courseType
                            + ' | Earned: '                 + earned
                            + ' | Attempted: '              + attempted
                            + ' | TermEarned (running): '   + prevTermEarned + ' -> ' + termEarned
                            + ' | TermAttempted (running): ' + prevTermAttempted + ' -> ' + termAttempted
                            + (grade == 'F' ? ' | *** FAILED — termFailed now: ' + termFailed + ' ***' : ''));
                    }
                } else {
                    System.debug('  !! No results found for Session Id: ' + es.Academic_Session__c
                        + ' under PE: ' + peId + ' — term credits will be 0');
                }

                // GPA formula: Earned Credits / Attempted Credits (0 if no attempted)
                Double gpa = termAttempted > 0 ? termEarned / termAttempted : 0;

                System.debug('  @@@ Term GPA Formula: ' + termEarned + ' (earned) / ' + termAttempted
                    + ' (attempted) = ' + gpa);
                System.debug('  @@@ Term Summary — Earned: ' + termEarned
                    + ' | Attempted: ' + termAttempted
                    + ' | GPA: '       + gpa
                    + ' | Failed: '    + termFailed);

                // Dirty check — only update if any value changed
                Boolean isDirty = (es.GPA__c                  != gpa)
                               || (es.Total_Attempted_Credits__c != termAttempted)
                               || (es.Total_Earned_Credits__c    != termEarned)
                               || (es.Total_Failed_Courses__c    != termFailed);
                System.debug('  @@@ Dirty Check for ES Id: ' + es.Id
                    + ' | GPA: '         + es.GPA__c                   + ' -> ' + gpa
                    + ' | Earned: '      + es.Total_Earned_Credits__c   + ' -> ' + termEarned
                    + ' | Attempted: '   + es.Total_Attempted_Credits__c + ' -> ' + termAttempted
                    + ' | Failed: '      + es.Total_Failed_Courses__c   + ' -> ' + termFailed
                    + ' | NeedsUpdate: ' + isDirty);

                if (isDirty) {
                    es.GPA__c                   = gpa;
                    es.Total_Attempted_Credits__c = termAttempted;
                    es.Total_Earned_Credits__c    = termEarned;
                    es.Total_Failed_Courses__c    = termFailed;
                    sessionsToUpdate.add(es);
                    System.debug('  *** ES Id: ' + es.Id + ' queued for UPDATE');
                }

                // Only store freshly-computed totals in sessionTotalsMap when this session
                // actually had results processed in this run (hasResults == true).
                // If hasResults is false, termEarned/Attempted are 0 — storing 0s would
                // incorrectly replace previously committed DB values in the CGPA rollup (STEP 5B).
                // Leaving the session OUT of the map lets STEP 5B correctly use the DB values.
                if (hasResults) {
                    sessionTotalsMap.put(es.Academic_Session__c, new Double[]{ termEarned, termAttempted, (Double)termFailed });
                    System.debug('  @@@ sessionTotalsMap STORED for Session: ' + es.Academic_Session__c
                        + ' -> Earned: ' + termEarned + ', Attempted: ' + termAttempted + ', Failed: ' + termFailed);
                } else {
                    System.debug('  @@@ sessionTotalsMap SKIPPED for Session: ' + es.Academic_Session__c
                        + ' (no results this run — STEP 5B will use existing DB values)');
                }
            } // end per-session loop

            // ------------------------------------------------------------------
            // STEP 5B: Cumulative (CGPA) rollup across ALL sessions of this PE
            // ------------------------------------------------------------------
            System.debug('');
            System.debug('  --- Cumulative Rollup across all sessions for PE: ' + peId);
            System.debug('  @@@ NOTE: Using freshly-computed term totals from sessionTotalsMap (NOT stale DB values)');
            Double  cumulativeEarned    = 0;
            Double  cumulativeAttempted = 0;
            Integer totalFailed         = 0;

            for (Enrollment_Session__c es : peSessions) {
                Double  sesEarned    = 0;
                Double  sesAttempted = 0;
                Integer sesFailed    = 0;

                if (sessionTotalsMap.containsKey(es.Academic_Session__c)) {
                    // Use freshly computed values from STEP 5A
                    Double[] totals = sessionTotalsMap.get(es.Academic_Session__c);
                    sesEarned    = totals[0];
                    sesAttempted = totals[1];
                    sesFailed    = (Integer)totals[2];
                    System.debug('    Session Id: ' + es.Academic_Session__c + ' -> Using FRESHLY COMPUTED totals from sessionTotalsMap');
                } else {
                    // Session had no results this run — fall back to existing DB-persisted value
                    sesEarned    = es.Total_Earned_Credits__c    != null ? es.Total_Earned_Credits__c    : 0;
                    sesAttempted = es.Total_Attempted_Credits__c != null ? es.Total_Attempted_Credits__c : 0;
                    sesFailed    = es.Total_Failed_Courses__c    != null ? (Integer)es.Total_Failed_Courses__c : 0;
                    System.debug('    Session Id: ' + es.Academic_Session__c + ' -> No results this run, using existing DB values (Earned: ' + sesEarned + ', Attempted: ' + sesAttempted + ')');
                }

                cumulativeEarned    += sesEarned;
                cumulativeAttempted += sesAttempted;
                totalFailed         += sesFailed;

                System.debug('    Session Id: ' + es.Academic_Session__c
                    + ' | Earned: '             + sesEarned
                    + ' | Attempted: '          + sesAttempted
                    + ' | Failed: '             + sesFailed
                    + ' | Cumulative Earned so far: '    + cumulativeEarned
                    + ' | Cumulative Attempted so far: ' + cumulativeAttempted
                    + ' | Total Failed so far: '         + totalFailed);
            }

            // CGPA formula: Total Cumulative Earned / Total Cumulative Attempted
            Double cgpa         = cumulativeAttempted > 0 ? cumulativeEarned    / cumulativeAttempted : 0;
            Double electiveCgpa = electiveAttempted   > 0 ? electiveEarned      / electiveAttempted   : 0;
            Double coreCgpa     = coreAttempted       > 0 ? coreEarned          / coreAttempted       : 0;

            System.debug('  @@@ CGPA Formula:         ' + cumulativeEarned + ' / ' + cumulativeAttempted + ' = ' + cgpa);
            System.debug('  @@@ Elective CGPA Formula: ' + electiveEarned  + ' / ' + electiveAttempted   + ' = ' + electiveCgpa
                + ' (Elective Earned: ' + electiveEarned + ' | Elective Attempted: ' + electiveAttempted + ')');
            System.debug('  @@@ Core CGPA Formula:     ' + coreEarned      + ' / ' + coreAttempted       + ' = ' + coreCgpa
                + ' (Core Earned: '    + coreEarned     + ' | Core Attempted: '     + coreAttempted      + ')');
            System.debug('  @@@ Total Failed Courses:  ' + totalFailed);
            System.debug('  @@@ Overall Earned Credits: '   + cumulativeEarned
                       + ' | Overall Attempted Credits: '   + cumulativeAttempted);
            System.debug('  *** PE Id: ' + peId + ' queued for UPDATE — CGPA: ' + cgpa
                + ', Elective CGPA: ' + electiveCgpa + ', Core CGPA: ' + coreCgpa);

            enrollmentsToUpdate.put(peId, new ProgramEnrollment(
                Id                        = peId,
                CGPA__c                   = cgpa,
                Elective_CGPA__c          = electiveCgpa,
                Core_CGPA__c              = coreCgpa,
                Overall_Earned_Credits__c   = cumulativeEarned,
                Overall_Attempted_Credits__c = cumulativeAttempted,
                Failed_Courses__c         = totalFailed
            ));
        } // end per-enrollment loop

        // -----------------------------------------------------------------------
        // STEP 6: DML — Update Program Enrollments FIRST, then Enrollment Sessions
        //
        // CRITICAL ORDER: PE must be updated BEFORE Enrollment Sessions.
        // Updating an Enrollment Session fires EnrollmentSessionHandler trigger,
        // which reads CGPA__c from the related Program Enrollment.
        // If we update ES first, the trigger sees the OLD (stale) CGPA on the PE.
        // By committing the PE update first, the trigger always reads the correct CGPA.
        // -----------------------------------------------------------------------
        System.debug('');
        System.debug('--- STEP 6: DML Updates ---');
        System.debug('@@@ [ORDER] Updating Program Enrollments FIRST to ensure EnrollmentSessionHandler trigger sees correct CGPA');

        System.debug('@@@ Program Enrollments to update: ' + enrollmentsToUpdate.size());
        if (!enrollmentsToUpdate.isEmpty()) {
            update enrollmentsToUpdate.values();
            System.debug('@@@ Successfully updated ' + enrollmentsToUpdate.size() + ' Program Enrollment(s) — CGPA is now committed to DB');
        } else {
            System.debug('@@@ No Program Enrollments required update');
        }

        System.debug('@@@ Enrollment Sessions to update: ' + sessionsToUpdate.size());
        if (!sessionsToUpdate.isEmpty()) {
            update sessionsToUpdate;  // EnrollmentSessionHandler trigger fires HERE — PE CGPA already correct in DB
            System.debug('@@@ Successfully updated ' + sessionsToUpdate.size() + ' Enrollment Session(s)');
        } else {
            System.debug('@@@ No Enrollment Sessions required update (all values unchanged)');
        }

        System.debug('========== [calculateGpaAndCgpa] END ==========');
        System.debug('');
    }
}