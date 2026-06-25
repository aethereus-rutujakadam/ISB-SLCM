public without sharing class AllotmentCourseOfferingBatch
    implements Database.Batchable<String>, Database.Stateful {

    public Iterable<String> start(Database.BatchableContext bc) {
        System.debug('--- AllotmentCourseOfferingBatch.start() ---');
        List<String> lineups = new List<String>();

       for (AggregateResult ar : [
            SELECT ISB_Line_Up_ID__c lineUp
            FROM Allotment__c
            WHERE (Sync_Status__c IN ('Pending', 'Retry')
            AND ISB_Line_Up_ID__c != null)
            GROUP BY ISB_Line_Up_ID__c limit 2000
        ]) {
            lineups.add((String) ar.get('lineUp'));
        }
        System.debug('Total lineups found in start(): ' + lineups.size());

        return lineups;
    }

    public void execute(Database.BatchableContext bc, List<String> scope) {
        System.debug('--- AllotmentCourseOfferingBatch.execute() ---');

        if (scope == null || scope.isEmpty()) return;

        // Fetch ALL allotments (both active and inactive) for these lineups
        List<Allotment__c> allAllotments = [
            SELECT Id,
                   Name,
                   ISB_External_Id__c,
                   ISB_Line_Up_ID__c,
                   Program__c,
                   Program__r.Name,
                   Course__c,
                   Faculty__c,
                   Faculty__r.Name,
                   Academic_Year__c,
                   Academic_Cohort__c,
                   Academic_Terms_Session__c,
                   Location__c,
                   Area__c,
                   Course_Type__c,
                   Preferred_Sessions2__c,
                   ISB_Sessions__c,
                   Section_Number__c,
                   Status__c,
                   Status_New__c,
                   Teaching_Location_P__c,
                   Teaching_Date__c,
                   Teaching_Dates__c,
                   Term_Start_Date__c,
                   Term_To_Date__c,
                   Sync_Status__c,
                   Error_Message__c,
                   Course_Offering__c,
                   LastModifiedDate
            FROM Allotment__c
            WHERE Sync_Status__c IN ('Pending', 'Retry')
              AND ISB_Line_Up_ID__c IN :scope
            ORDER BY ISB_Line_Up_ID__c, LastModifiedDate DESC
        ];

        if (allAllotments.isEmpty()) return;

        // Separate active and inactive allotments
        Map<String, List<Allotment__c>> activeRowsByLineup = new Map<String, List<Allotment__c>>();
        Map<String, List<Allotment__c>> inactiveRowsByLineup = new Map<String, List<Allotment__c>>();
        
        for (Allotment__c row : allAllotments) {
            if (row.Status_New__c == 'Active') {
                if (!activeRowsByLineup.containsKey(row.ISB_Line_Up_ID__c)) {
                    activeRowsByLineup.put(row.ISB_Line_Up_ID__c, new List<Allotment__c>());
                }
                activeRowsByLineup.get(row.ISB_Line_Up_ID__c).add(row);
            } else {
                if (!inactiveRowsByLineup.containsKey(row.ISB_Line_Up_ID__c)) {
                    inactiveRowsByLineup.put(row.ISB_Line_Up_ID__c, new List<Allotment__c>());
                }
                inactiveRowsByLineup.get(row.ISB_Line_Up_ID__c).add(row);
            }
        }

        AllotmentCourseOfferingHelper.ReferenceData refData =
            AllotmentCourseOfferingHelper.loadReferenceData(allAllotments, scope);

        List<Allotment__c>    processingUpdates  = new List<Allotment__c>();
        List<AcademicSession> sessionUpdates     = new List<AcademicSession>();
        List<CourseOffering>  offeringsToInsert  = new List<CourseOffering>();
        List<CourseOffering>  activeOfferingsToUpdate  = new List<CourseOffering>();
        List<Allotment__c>    finalStatusUpdates = new List<Allotment__c>();
        List<Allotment__c>    errorUpdates       = new List<Allotment__c>();

        Map<String, CourseOffering> insertOfferingByLineup = new Map<String, CourseOffering>();
        Map<String, CourseOffering> updateOfferingByLineup = new Map<String, CourseOffering>();
        Map<String, List<Allotment__c>> lineupRowsMap      = new Map<String, List<Allotment__c>>();

        // ============ PROCESS ACTIVE ALLOTMENTS ============
        for (String lineup : scope) {
            List<Allotment__c> lineupRows = activeRowsByLineup.get(lineup);
            if (lineupRows == null || lineupRows.isEmpty()) continue;
            lineupRowsMap.put(lineup, lineupRows);
            for (Allotment__c row : lineupRows) {
                processingUpdates.add(new Allotment__c(
                    Id = row.Id,
                    Sync_Status__c = 'Processing',
                    Error_Message__c = null
                ));
            }
        }
        if (!processingUpdates.isEmpty()) {
            try {
                update processingUpdates; // DML #1
            } catch (System.DmlException e) {
                System.debug('Initial Processing Update Failed: ' + e.getMessage());
                for (Allotment__c row : processingUpdates) {
                    errorUpdates.add(new Allotment__c(
                        Id = row.Id,
                        Sync_Status__c = 'Error',
                        Error_Message__c = AllotmentCourseOfferingHelper.truncateError('Validation or Trigger error on change to Processing: ' + e.getDmlMessage(0), 255)
                    ));
                }
                Database.update(errorUpdates, false);
                return;
            }
        }

        Set<Id> processedSessionIds = new Set<Id>();

        // ── Step 2: PRE-SCAN all lineups to collect every session name + termId + location combo ──
        // This fixes the bug where two allotments share the same session name
        // but have different cohorts/locations processed in the same batch chunk.
        // Previously, the code only built alt-combo keys if the session already had
        // a term — meaning the first run would stamp the wrong term and only the
        // second run would detect the mismatch. Now we collect ALL combos upfront
        // regardless of whether the session currently has a term.
        Set<String>         requiredAltComboKeys            = new Set<String>();
        Map<String, String> requiredAltComboKeyToName       = new Map<String, String>();
        Map<String, Id>     requiredAltComboKeyToTermId     = new Map<String, Id>();
        Map<String, Id>     requiredAltComboKeyToLocationId = new Map<String, Id>();
        Map<String, Id>     requiredAltComboKeyToProgramId  = new Map<String, Id>();
        Map<String, Date>   requiredAltComboKeyToStartDate  = new Map<String, Date>();
        Map<String, Date>   requiredAltComboKeyToToDate     = new Map<String, Date>();

        for (String lineup : scope) {
            List<Allotment__c> lineupRows = lineupRowsMap.get(lineup);
            if (lineupRows == null || lineupRows.isEmpty()) continue;

            Allotment__c winner   = lineupRows[0];
            Id reqTermId          = String.isNotBlank(winner.Academic_Cohort__c)
                                        ? (Id)winner.Academic_Cohort__c : null;
            Id reqSessionId       = String.isNotBlank(winner.Academic_Terms_Session__c)
                                        ? (Id)winner.Academic_Terms_Session__c : null;
            Id reqLocationId      = String.isNotBlank(winner.Location__c)
                                        ? (Id)winner.Location__c : null;
            Id reqProgramId       = String.isNotBlank(winner.Program__c)
                                        ? (Id)winner.Program__c : null;

            // Skip if Location is NULL - Location is required for Academic Session matching
            if (reqSessionId == null || reqTermId == null || reqLocationId == null) continue;

            AcademicSession sessionRec = refData.sessionById.get(reqSessionId);
            if (sessionRec == null) continue;

            // Location is required - build key with actual Location ID
            String key = sessionRec.Name + '|' + String.valueOf(reqTermId) + '|' + String.valueOf(reqLocationId);

            requiredAltComboKeys.add(key);
            requiredAltComboKeyToName.put(key, sessionRec.Name);
            requiredAltComboKeyToTermId.put(key, reqTermId);
            requiredAltComboKeyToLocationId.put(key, reqLocationId);
            if (reqProgramId != null) {
                requiredAltComboKeyToProgramId.put(key, reqProgramId);
            }
            if (winner.Term_Start_Date__c != null) {
                requiredAltComboKeyToStartDate.put(key, winner.Term_Start_Date__c);
            }
            if (winner.Term_To_Date__c != null) {
                requiredAltComboKeyToToDate.put(key, winner.Term_To_Date__c);
            }
        }

        // ── Step 3: Query existing sessions for all required combos ──────────
        Map<String, AcademicSession> altSessionByKey = new Map<String, AcademicSession>();

        if (!requiredAltComboKeys.isEmpty()) {
            List<String> namesToQuery = new List<String>(requiredAltComboKeyToName.values());
            List<Id>     termsToQuery = new List<Id>(requiredAltComboKeyToTermId.values());
            Set<Id>      locationsToQuery = new Set<Id>();
            
            // Collect all location IDs - NULL locations are excluded from processing
            for (Id locationId : requiredAltComboKeyToLocationId.values()) {
                if (locationId != null) {
                    locationsToQuery.add(locationId);
                }
            }

            // Query only for sessions with valid Location values
            if (!locationsToQuery.isEmpty()) {
                for (AcademicSession s : [
                    SELECT Id, Name, AcademicTermId, Location__c, Program__c, From_Date__c, To_date__c
                    FROM AcademicSession
                    WHERE Name IN :namesToQuery 
                      AND AcademicTermId IN :termsToQuery
                      AND Location__c IN :locationsToQuery
                ]) {
                    String key = s.Name + '|' + String.valueOf(s.AcademicTermId) + '|' + String.valueOf(s.Location__c);
                    if (requiredAltComboKeys.contains(key)) {
                        altSessionByKey.put(key, s);
                        System.debug('Found existing AcademicSession for key: ' + key + ' → ID: ' + s.Id);
                    }
                }
            }

            // Create missing sessions for ALL combos upfront in one DML
            List<AcademicSession> newAltSessions = new List<AcademicSession>();
            for (String key : requiredAltComboKeys) {
                if (!altSessionByKey.containsKey(key)) {
                    String sessionName = requiredAltComboKeyToName.get(key);
                    Id     termId      = requiredAltComboKeyToTermId.get(key);
                    Id     locationId  = requiredAltComboKeyToLocationId.get(key);
                    Id     programId   = requiredAltComboKeyToProgramId.get(key);
                    Date   startDate   = requiredAltComboKeyToStartDate.get(key);
                    Date   toDate      = requiredAltComboKeyToToDate.get(key);

                    AcademicSession newSession = new AcademicSession(
                        Name           = sessionName,
                        AcademicTermId = termId,
                        Location__c    = locationId,
                        Program__c     = programId,
                        From_Date__c   = startDate,
                        To_date__c     = toDate,
                        IsActive       = true
                    );
                    newAltSessions.add(newSession);
                    altSessionByKey.put(key, newSession);
                    System.debug('Queued new AcademicSession for key: ' + key);
                }
            }

            if (!newAltSessions.isEmpty()) {
                insert newAltSessions;
                System.debug('Inserted ' + newAltSessions.size() + ' new AcademicSession(s)');
            }
        }

        for (String lineup : scope) {
            List<Allotment__c> lineupRows = lineupRowsMap.get(lineup);
            if (lineupRows == null || lineupRows.isEmpty()) continue;

            try {
                Allotment__c winner = lineupRows[0];

                Id programId         = String.isNotBlank(winner.Program__c)               ? (Id)winner.Program__c               : null;
                Id academicYearId    = String.isNotBlank(winner.Academic_Year__c)          ? (Id)winner.Academic_Year__c          : null;
                Id academicTermId    = String.isNotBlank(winner.Academic_Cohort__c)        ? (Id)winner.Academic_Cohort__c        : null;
                Id locationId        = String.isNotBlank(winner.Location__c)               ? (Id)winner.Location__c               : null;
                Id academicSessionId = String.isNotBlank(winner.Academic_Terms_Session__c) ? (Id)winner.Academic_Terms_Session__c : null;
                Id learningCourseId  = String.isNotBlank(winner.Course__c)                 ? (Id)winner.Course__c                 : null;

                if (learningCourseId == null) {
                    System.debug('Error on lineup ' + lineup + ' – Course__c (LearningCourseId) is missing.');
                    IllegalArgumentException errMsg = new IllegalArgumentException();
                    errMsg.setMessage('Course__c (LearningCourseId) is missing. Cannot create Course Offering.');
                    throw errMsg;
                }

                // Resolve the correct AcademicSession for this lineup
                // Always use altSessionByKey which was pre-built in Step 2/3
                // This handles both cases:
                //   (a) session had no term → now has correct term via key
                //   (b) session had a different term → alt session created via key
                Id finalSessionId = academicSessionId;

                if (academicSessionId != null && academicTermId != null && locationId != null) {
                    AcademicSession sessionRec = refData.sessionById.get(academicSessionId);
                    if (sessionRec != null) {
                        String key = sessionRec.Name + '|' + String.valueOf(academicTermId) + '|' + String.valueOf(locationId);
                        AcademicSession correctSession = altSessionByKey.get(key);

                        if (correctSession != null) {
                            finalSessionId = correctSession.Id;
                            System.debug('Resolved session for lineup ' + lineup
                                + ' → key: ' + key + ' → ID: ' + finalSessionId);

                            // Update location or dates on the resolved session if needed
                            if (!processedSessionIds.contains(correctSession.Id)) {
                                Boolean needsUpdate = false;
                                AcademicSession sUpdate = new AcademicSession(Id = correctSession.Id);
                                
                                if (programId != null && correctSession.Program__c != programId) {
                                    sUpdate.Program__c = programId;
                                    needsUpdate = true;
                                }
                                if (winner.Term_Start_Date__c != null && correctSession.From_Date__c != winner.Term_Start_Date__c) {
                                    sUpdate.From_Date__c = winner.Term_Start_Date__c;
                                    needsUpdate = true;
                                }
                                if (winner.Term_To_Date__c != null && correctSession.To_date__c != winner.Term_To_Date__c) {
                                    sUpdate.To_date__c = winner.Term_To_Date__c;
                                    needsUpdate = true;
                                }
                                
                                if (needsUpdate) {
                                    sUpdate.IsActive = true;
                                    sessionUpdates.add(sUpdate);
                                    processedSessionIds.add(correctSession.Id);
                                }
                            }
                        } else {
                            System.debug('WARNING: No session found for key: ' + key
                                + ' — using original academicSessionId');
                        }
                    }
                }

                List<CourseOffering> existingOfferings = refData.offeringsByLineup.get(lineup);
                if (existingOfferings == null) {
                    existingOfferings = new List<CourseOffering>();
                }

                if (existingOfferings.isEmpty()) {
                    CourseOffering co = new CourseOffering();
                    AllotmentCourseOfferingHelper.populateCreateFields(
                        co, winner, finalSessionId, academicTermId,
                        academicYearId, programId, learningCourseId, locationId
                    );
                    co.Preferred_Sessions2__c =
                        AllotmentCourseOfferingHelper.mergeFinalSessions(null, lineupRows);
                    offeringsToInsert.add(co);
                    insertOfferingByLineup.put(lineup, co);

                } else {
                    CourseOffering firstExisting = existingOfferings[0];
                    Boolean createNewForPGP =
                        winner.Program__r.Name == 'Post Graduate Programme in Management' &&
                        firstExisting.LearningCourseId != null &&
                        firstExisting.LearningCourseId != learningCourseId;

                    if (createNewForPGP) {
                        CourseOffering co = new CourseOffering();
                        AllotmentCourseOfferingHelper.populateCreateFields(
                            co, winner, finalSessionId, academicTermId,
                            academicYearId, programId, learningCourseId, locationId
                        );
                        co.Preferred_Sessions2__c =
                            AllotmentCourseOfferingHelper.mergeFinalSessions(null, lineupRows);
                        offeringsToInsert.add(co);
                        insertOfferingByLineup.put(lineup, co);
                    } else {
                        CourseOffering co = new CourseOffering(Id = firstExisting.Id);
                        AllotmentCourseOfferingHelper.populateUpdateFields(
                            co, winner, finalSessionId, academicTermId, academicYearId,
                            locationId,
                            AllotmentCourseOfferingHelper.mergeFinalSessions(
                                firstExisting.Preferred_Sessions2__c, lineupRows)
                        );
                        activeOfferingsToUpdate.add(co);
                        updateOfferingByLineup.put(lineup, co);
                    }
                }

            } catch (Exception e) {
                System.debug('Error preparing lineup ' + lineup + ': ' + e.getMessage());
                List<Allotment__c> errRows = lineupRowsMap.get(lineup);
                if (errRows != null) {
                    for (Allotment__c row : errRows) {
                        errorUpdates.add(new Allotment__c(
                            Id = row.Id,
                            Sync_Status__c = 'Error',
                            Error_Message__c = AllotmentCourseOfferingHelper.truncateError(e.getMessage(), 255)
                        ));
                    }
                }
            }
        }

        if (!sessionUpdates.isEmpty())    Database.update(sessionUpdates, false);    
        if (!offeringsToInsert.isEmpty()) Database.insert(offeringsToInsert, false); 
        if (!activeOfferingsToUpdate.isEmpty()) Database.update(activeOfferingsToUpdate, false); 

        // Tag offerings with correct academic sessions based on term and location
        if (!offeringsToInsert.isEmpty()) {
            AllotmentCourseOfferingHelper.tagCorrectAcademicSessions(offeringsToInsert);
        }
        if (!activeOfferingsToUpdate.isEmpty()) {
            AllotmentCourseOfferingHelper.tagCorrectAcademicSessions(activeOfferingsToUpdate);
        }

        // Persist corrected session IDs back to database
        List<CourseOffering> allOfferingsToUpdateSessions = new List<CourseOffering>();
        allOfferingsToUpdateSessions.addAll(offeringsToInsert);
        allOfferingsToUpdateSessions.addAll(activeOfferingsToUpdate);
        if (!allOfferingsToUpdateSessions.isEmpty()) {
            Database.update(allOfferingsToUpdateSessions, false);
        }

        Map<Id, Set<Id>> neededFacultyByOffering    = new Map<Id, Set<Id>>();
        Map<Id, Map<Id, String>> facultyNamesByOffering = new Map<Id, Map<Id, String>>();

        for (String lineup : scope) {
            List<Allotment__c> lineupRows = lineupRowsMap.get(lineup);
            if (lineupRows == null) continue;

            CourseOffering co = insertOfferingByLineup.containsKey(lineup)
                ? insertOfferingByLineup.get(lineup)
                : updateOfferingByLineup.get(lineup);
            if (co == null || co.Id == null) continue;

            Id offeringId = co.Id;
            if (!neededFacultyByOffering.containsKey(offeringId))
                neededFacultyByOffering.put(offeringId, new Set<Id>());
            if (!facultyNamesByOffering.containsKey(offeringId))
                facultyNamesByOffering.put(offeringId, new Map<Id, String>());

            for (Allotment__c row : lineupRows) {
                if (row.Faculty__c != null) {
                    Id fId = (Id)row.Faculty__c;
                    neededFacultyByOffering.get(offeringId).add(fId);
                    facultyNamesByOffering.get(offeringId).put(
                        fId,
                        (row.Faculty__r != null && String.isNotBlank(row.Faculty__r.Name))
                            ? row.Faculty__r.Name : 'Faculty Assigned'
                    );
                }
            }
        }

        Set<Id> allOfferingIds = neededFacultyByOffering.keySet();
        Map<String, Boolean> existingLinkKey = new Map<String, Boolean>();
        if (!allOfferingIds.isEmpty()) {
            for (Course_Faculty__c cf : [
                SELECT Course_Offering__c, Faculty__c
                FROM Course_Faculty__c
                WHERE Course_Offering__c IN :allOfferingIds
            ]) {
                existingLinkKey.put(cf.Course_Offering__c + '|' + cf.Faculty__c, true);
            }
        }

        List<Course_Faculty__c> facultyToInsert = new List<Course_Faculty__c>();
        for (Id offeringId : neededFacultyByOffering.keySet()) {
            for (Id facultyId : neededFacultyByOffering.get(offeringId)) {
                if (!existingLinkKey.containsKey(offeringId + '|' + facultyId)) {
                    facultyToInsert.add(new Course_Faculty__c(
                        Course_Offering__c = offeringId,
                        Faculty__c = facultyId,
                        Name = facultyNamesByOffering.get(offeringId).get(facultyId)
                    ));
                }
            }
        }
        if (!facultyToInsert.isEmpty()) Database.insert(facultyToInsert, false); 

        for (String lineup : scope) {
            List<Allotment__c> lineupRows = lineupRowsMap.get(lineup);
            if (lineupRows == null) continue;

            CourseOffering co = insertOfferingByLineup.containsKey(lineup)
                ? insertOfferingByLineup.get(lineup)
                : updateOfferingByLineup.get(lineup);
            Id targetId = (co != null) ? co.Id : null;

            Boolean hadError = false;
            for (Allotment__c e : errorUpdates) {
                if (e.Id == lineupRows[0].Id) { hadError = true; break; }
            }
            if (hadError) continue;

            for (Allotment__c row : lineupRows) {
                finalStatusUpdates.add(new Allotment__c(
                    Id = row.Id,
                    Sync_Status__c = 'Synced',
                    Error_Message__c = null,
                    Course_Offering__c = targetId
                ));
            }
        }

        // ============ PROCESS INACTIVE ALLOTMENTS ============
        Map<String, Integer> totalAllotmentsByLineup = new Map<String, Integer>();
        Map<String, List<Allotment__c>> allAllotmentsByLineupForInactive = new Map<String, List<Allotment__c>>();
        Set<String> lineupsWithExistingHistory = new Set<String>();
        if (!inactiveRowsByLineup.isEmpty()) {
            for (AggregateResult ar : [
                SELECT ISB_Line_Up_ID__c lineUp, COUNT(Id) totalCount
                FROM Allotment__c
                WHERE ISB_Line_Up_ID__c IN :inactiveRowsByLineup.keySet()
                GROUP BY ISB_Line_Up_ID__c
            ]) {
                totalAllotmentsByLineup.put(
                    (String) ar.get('lineUp'),
                    (Integer) ar.get('totalCount')
                );
            }

            for (Allotment__c a : [
                SELECT Id,
                       ISB_Line_Up_ID__c,
                       Status_New__c,
                       Program__c,
                       Course__c,
                       Faculty__c,
                       Faculty__r.Name,
                       Academic_Year__c,
                       Academic_Cohort__c,
                       Academic_Terms_Session__c,
                       Location__c,
                       Area__c,
                       Preferred_Sessions2__c,
                       ISB_Sessions__c,
                       Section_Number__c,
                       Status__c,
                       Teaching_Location_P__c
                FROM Allotment__c
                WHERE ISB_Line_Up_ID__c IN :inactiveRowsByLineup.keySet()
                ORDER BY ISB_Line_Up_ID__c, LastModifiedDate DESC
            ]) {
                if (!allAllotmentsByLineupForInactive.containsKey(a.ISB_Line_Up_ID__c)) {
                    allAllotmentsByLineupForInactive.put(a.ISB_Line_Up_ID__c, new List<Allotment__c>());
                }
                allAllotmentsByLineupForInactive.get(a.ISB_Line_Up_ID__c).add(a);
            }

            for (CourseOffering_History__c h : [
                SELECT ISB_Line_Up_ID__c
                FROM CourseOffering_History__c
                WHERE ISB_Line_Up_ID__c IN :inactiveRowsByLineup.keySet()
            ]) {
                if (String.isNotBlank(h.ISB_Line_Up_ID__c)) {
                    lineupsWithExistingHistory.add(h.ISB_Line_Up_ID__c);
                }
            }
        }
        
        for (String lineup : inactiveRowsByLineup.keySet()) {
            try {
                List<Allotment__c> inactiveAllotments = inactiveRowsByLineup.get(lineup);
                if (inactiveAllotments == null || inactiveAllotments.isEmpty()) continue;
                
                Integer totalAllotmentsForLineup = totalAllotmentsByLineup.containsKey(lineup)
                    ? totalAllotmentsByLineup.get(lineup)
                    : 0;
                
                System.debug('Lineup ' + lineup + ' has ' + totalAllotmentsForLineup + ' total allotments');
                
                // Get the existing CourseOffering for this lineup
                List<CourseOffering> existingOfferings = refData.offeringsByLineup.get(lineup);
                if (existingOfferings == null || existingOfferings.isEmpty()) {
                    System.debug('No CourseOffering found for lineup ' + lineup);
                    for (Allotment__c row : inactiveAllotments) {
                        finalStatusUpdates.add(new Allotment__c(
                            Id = row.Id,
                            Sync_Status__c = 'Synced',
                            Error_Message__c = null
                        ));
                    }
                    continue;
                }
                
                CourseOffering firstExistingOffering = existingOfferings[0];

                // Step 3: Insert CourseOffering history first.
                if (!lineupsWithExistingHistory.contains(lineup)) {
                    CourseOffering_History__c history = AllotmentCourseOfferingHelper.copyOfferingToHistory(
                        firstExistingOffering,
                        firstExistingOffering.Id
                    );
                    Database.SaveResult[] historyInsertResults = Database.insert(
                        new List<CourseOffering_History__c>{ history },
                        false
                    );

                    // Step 4: Continue only when history insert succeeds.
                    if (historyInsertResults.isEmpty() || !historyInsertResults[0].isSuccess()) {
                        String historyErr = 'Failed to insert CourseOffering history.';
                        if (!historyInsertResults.isEmpty() && !historyInsertResults[0].isSuccess() &&
                            historyInsertResults[0].getErrors() != null &&
                            !historyInsertResults[0].getErrors().isEmpty()) {
                            historyErr = historyInsertResults[0].getErrors()[0].getMessage();
                        }
                        for (Allotment__c row : inactiveAllotments) {
                            errorUpdates.add(new Allotment__c(
                                Id = row.Id,
                                Sync_Status__c = 'Error',
                                Error_Message__c = AllotmentCourseOfferingHelper.truncateError(historyErr, 255)
                            ));
                        }
                        continue;
                    }
                    lineupsWithExistingHistory.add(lineup);
                } else {
                    System.debug('History already exists for lineup ' + lineup + '. Skipping history insert.');
                }
                
                // CASE A: Only one allotment exists for this lineup
                if (totalAllotmentsForLineup == 1) {
                    System.debug('CASE A: Single allotment for lineup ' + lineup + ' – archiving and deleting CourseOffering ' + firstExistingOffering.Id);

                    // Step 4: Delete CourseOffering only after history insert success.
                    Database.DeleteResult[] deleteResults = Database.delete(
                        new List<CourseOffering>{ new CourseOffering(Id = firstExistingOffering.Id) },
                        false
                    );
                    if (deleteResults.isEmpty() || !deleteResults[0].isSuccess()) {
                        String delErr = 'Failed to delete CourseOffering.';
                        if (!deleteResults.isEmpty() && !deleteResults[0].isSuccess() &&
                            deleteResults[0].getErrors() != null &&
                            !deleteResults[0].getErrors().isEmpty()) {
                            delErr = deleteResults[0].getErrors()[0].getMessage();
                        }
                        for (Allotment__c row : inactiveAllotments) {
                            errorUpdates.add(new Allotment__c(
                                Id = row.Id,
                                Sync_Status__c = 'Error',
                                Error_Message__c = AllotmentCourseOfferingHelper.truncateError(delErr, 255)
                            ));
                        }
                        continue;
                    }
                    
                } else {
                    // CASE B: Multiple allotments exist for this lineup
                    System.debug('CASE B: Multiple allotments for lineup ' + lineup + ' – updating CourseOffering');
                    
                    // Get all allotments for this lineup (no Sync_Status filter) to recalculate
                    List<Allotment__c> allLineupAllotments = allAllotmentsByLineupForInactive.containsKey(lineup)
                        ? allAllotmentsByLineupForInactive.get(lineup)
                        : new List<Allotment__c>();
                    
                    // Recalculate CourseOffering using only active allotments
                    CourseOffering coUpdate = new CourseOffering(Id = firstExistingOffering.Id);
                    AllotmentCourseOfferingHelper.recalculateCourseOfferingForInactiveAllotments(
                        coUpdate, 
                        allLineupAllotments, 
                        refData
                    );
                    Database.SaveResult[] coUpdateResults = Database.update(
                        new List<CourseOffering>{ coUpdate },
                        false
                    );
                    if (coUpdateResults.isEmpty() || !coUpdateResults[0].isSuccess()) {
                        String coUpdErr = 'Failed to update CourseOffering in Case B.';
                        if (!coUpdateResults.isEmpty() && !coUpdateResults[0].isSuccess() &&
                            coUpdateResults[0].getErrors() != null &&
                            !coUpdateResults[0].getErrors().isEmpty()) {
                            coUpdErr = coUpdateResults[0].getErrors()[0].getMessage();
                        }
                        for (Allotment__c row : inactiveAllotments) {
                            errorUpdates.add(new Allotment__c(
                                Id = row.Id,
                                Sync_Status__c = 'Error',
                                Error_Message__c = AllotmentCourseOfferingHelper.truncateError(coUpdErr, 255)
                            ));
                        }
                        continue;
                    }
                    
                    // Get active allotments for faculty processing
                    List<Allotment__c> activeAllotmentsForLineup = AllotmentCourseOfferingHelper.getActiveAllotments(allLineupAllotments);
                    
                    // Update faculty associations - remove Course_Faculty__c records and recreate with active allotments only
                    Set<Id> facultyToRemove = new Set<Id>();
                    for (Course_Faculty__c cf : [
                        SELECT Id, Faculty__c
                        FROM Course_Faculty__c
                        WHERE Course_Offering__c = :firstExistingOffering.Id
                    ]) {
                        facultyToRemove.add(cf.Id);
                    }
                    
                    if (!facultyToRemove.isEmpty()) {
                        delete [SELECT Id FROM Course_Faculty__c WHERE Id IN :facultyToRemove];
                    }
                    
                    // Re-add faculty from active allotments only
                    Set<Id> neededFacultyIds = new Set<Id>();
                    Map<Id, String> facultyNamesForUpdate = new Map<Id, String>();
                    
                    for (Allotment__c row : activeAllotmentsForLineup) {
                        if (row.Faculty__c != null) {
                            Id fId = (Id)row.Faculty__c;
                            neededFacultyIds.add(fId);
                            facultyNamesForUpdate.put(
                                fId,
                                (row.Faculty__r != null && String.isNotBlank(row.Faculty__r.Name))
                                    ? row.Faculty__r.Name : 'Faculty Assigned'
                            );
                        }
                    }
                    
                    List<Course_Faculty__c> facultyToInsertForInactive = new List<Course_Faculty__c>();
                    for (Id facultyId : neededFacultyIds) {
                        facultyToInsertForInactive.add(new Course_Faculty__c(
                            Course_Offering__c = firstExistingOffering.Id,
                            Faculty__c = facultyId,
                            Name = facultyNamesForUpdate.get(facultyId)
                        ));
                    }
                    if (!facultyToInsertForInactive.isEmpty()) {
                        Database.insert(facultyToInsertForInactive, false);
                    }
                }
                
                // Step 5: Update inactive allotments as Synced only after prior steps complete.
                List<Allotment__c> inactiveStatusUpdates = new List<Allotment__c>();
                for (Allotment__c row : inactiveAllotments) {
                    inactiveStatusUpdates.add(new Allotment__c(
                        Id = row.Id,
                        Sync_Status__c = 'Synced',
                        Error_Message__c = null,
                        Course_Offering__c = (totalAllotmentsForLineup == 1) ? null : firstExistingOffering.Id
                    ));
                }
                Database.SaveResult[] inactiveStatusResults = Database.update(inactiveStatusUpdates, false);
                for (Integer i = 0; i < inactiveStatusResults.size(); i++) {
                    if (!inactiveStatusResults[i].isSuccess()) {
                        String updErr = 'Failed to update inactive allotment.';
                        if (inactiveStatusResults[i].getErrors() != null && !inactiveStatusResults[i].getErrors().isEmpty()) {
                            updErr = inactiveStatusResults[i].getErrors()[0].getMessage();
                        }
                        errorUpdates.add(new Allotment__c(
                            Id = inactiveStatusUpdates[i].Id,
                            Sync_Status__c = 'Error',
                            Error_Message__c = AllotmentCourseOfferingHelper.truncateError(updErr, 255)
                        ));
                    }
                }
                
            } catch (Exception e) {
                System.debug('Error processing inactive allotments for lineup ' + lineup + ': ' + e.getMessage());
                List<Allotment__c> inactiveAllotments = inactiveRowsByLineup.get(lineup);
                if (inactiveAllotments != null) {
                    for (Allotment__c row : inactiveAllotments) {
                        errorUpdates.add(new Allotment__c(
                            Id = row.Id,
                            Sync_Status__c = 'Error',
                            Error_Message__c = AllotmentCourseOfferingHelper.truncateError(e.getMessage(), 255)
                        ));
                    }
                }
            }
        }

        // Execute all DML operations
        if (!finalStatusUpdates.isEmpty()) update finalStatusUpdates;          
        if (!errorUpdates.isEmpty())       Database.update(errorUpdates, false);
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('AllotmentCourseOfferingBatch completed.');
    }
}