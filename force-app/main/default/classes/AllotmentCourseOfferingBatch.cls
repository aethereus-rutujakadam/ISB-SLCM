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

        List<Allotment__c> stagingRows = [
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
                   Teaching_Location_P__c,
                   Teaching_Date__c,
                   Teaching_Dates__c,
                   Term_Start_Date__c,
                   Term_To_Date__c,
                   Sync_Status__c,
                   Error_Message__c,
                   Course_Offering__c,
                   Industry_Specialization_p__c,
                    Concentration_p__c, 
                   LastModifiedDate
            FROM Allotment__c
            WHERE Sync_Status__c IN ('Pending', 'Retry')
              AND ISB_Line_Up_ID__c IN :scope
            ORDER BY ISB_Line_Up_ID__c, LastModifiedDate DESC
        ];

        if (stagingRows.isEmpty()) return;

        Map<String, List<Allotment__c>> rowsByLineup =
            AllotmentCourseOfferingHelper.groupByLineup(stagingRows);
        AllotmentCourseOfferingHelper.ReferenceData refData =
            AllotmentCourseOfferingHelper.loadReferenceData(stagingRows, scope);

        List<Allotment__c>    processingUpdates  = new List<Allotment__c>();
        List<AcademicSession> sessionUpdates     = new List<AcademicSession>();
        List<CourseOffering>  offeringsToInsert  = new List<CourseOffering>();
        List<CourseOffering>  offeringsToUpdate  = new List<CourseOffering>();
        List<Allotment__c>    finalStatusUpdates = new List<Allotment__c>();
        List<Allotment__c>    errorUpdates       = new List<Allotment__c>();

        Map<String, CourseOffering> insertOfferingByLineup = new Map<String, CourseOffering>();
        Map<String, CourseOffering> updateOfferingByLineup = new Map<String, CourseOffering>();
        Map<String, List<Allotment__c>> lineupRowsMap      = new Map<String, List<Allotment__c>>();

        Map<Id, String> lineupByRowId = new Map<Id, String>();

        // ── Step 1: Mark all rows as Processing ──────────────────────────────
        for (String lineup : scope) {
            List<Allotment__c> lineupRows = rowsByLineup.get(lineup);
            if (lineupRows == null || lineupRows.isEmpty()) continue;
            lineupRowsMap.put(lineup, lineupRows);
            for (Allotment__c row : lineupRows) {
                lineupByRowId.put(row.Id, lineup);
                processingUpdates.add(new Allotment__c(
                    Id               = row.Id,
                    Sync_Status__c   = 'Processing',
                    Error_Message__c = null
                ));
            }
        }

        if (!processingUpdates.isEmpty()) {
            Database.SaveResult[] results = Database.update(processingUpdates, false);
            Set<String> failedLineups = new Set<String>();
            Map<String, String> errorMsgByLineup = new Map<String, String>();

            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    Allotment__c failedRow = processingUpdates[i];
                    String lineup = lineupByRowId.get(failedRow.Id);
                    failedLineups.add(lineup);

                    String ds = '';
                    for (Database.Error err : results[i].getErrors()) ds += err.getMessage() + ' ';
                    errorMsgByLineup.put(lineup, ds);
                }
            }

            if (!failedLineups.isEmpty()) {
                for (String lineup : failedLineups) {
                    for (Allotment__c row : lineupRowsMap.get(lineup)) {
                        errorUpdates.add(new Allotment__c(
                            Id               = row.Id,
                            Sync_Status__c   = 'Error',
                            Error_Message__c = AllotmentCourseOfferingHelper.truncateError('Validation or Trigger error on change to Processing: ' + errorMsgByLineup.get(lineup), 255)
                        ));
                    }
                    lineupRowsMap.remove(lineup);
                }
                
                List<String> validScope = new List<String>();
                for (String lineup : scope) {
                    if (!failedLineups.contains(lineup)) validScope.add(lineup);
                }
                scope = validScope;
                
                Database.update(errorUpdates, false);
                errorUpdates.clear(); // Reset to avoid double insertion downstream!
                
                if (scope.isEmpty()) return;
            }
        }

        // ── Step 2: PRE-SCAN all lineups to collect every session name + termId + location combo ──
        // This fixes the bug where two allotments share the same session name
        // but have different cohorts/locations processed in the same batch chunk.
        // Previously, the code only built alt-combo keys if the session already had
        // a term — meaning the first run would stamp the wrong term and only the
        // second run would detect the mismatch. Now we collect ALL combos upfront
        // regardless of whether the session currently has a term.
        Set<String> requiredExternalIds = new Set<String>();
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

// Build external ID the same way the field is populated:
// SessionName + LocationId + CohortId
String externalId = sessionRec.Name 
    + String.valueOf(reqLocationId) 
    + String.valueOf(reqTermId);   // reqTermId = Academic_Cohort__c

if (String.isNotBlank(externalId)) {
    requiredExternalIds.add(externalId);
}
        }
       // ── Step 3: Query existing sessions by External ID ──────────────────
Map<String, AcademicSession> altSessionByExternalId = new Map<String, AcademicSession>();

if (!requiredExternalIds.isEmpty()) {
    for (AcademicSession s : [
        SELECT Id, Name, AcademicTermId, Location__c, 
               Program__c, From_Date__c, To_date__c, ISB_External_Id__c
        FROM AcademicSession
        WHERE ISB_External_Id__c IN :requiredExternalIds
    ]) {
        altSessionByExternalId.put(s.ISB_External_Id__c, s);
        System.debug('Found AcademicSession via External ID: ' 
            + s.ISB_External_Id__c + ' → ID: ' + s.Id);
    }
}

        // ── Step 4: Process each lineup — resolve session, build CourseOffering ──
        Set<Id> processedSessionIds = new Set<Id>();

        for (String lineup : scope) {
            List<Allotment__c> lineupRows = lineupRowsMap.get(lineup);
            if (lineupRows == null || lineupRows.isEmpty()) continue;

            try {
                Allotment__c winner = lineupRows[0];

                Id programId         = String.isNotBlank(winner.Program__c)
                                        ? (Id)winner.Program__c : null;
                Id academicYearId    = String.isNotBlank(winner.Academic_Year__c)
                                        ? (Id)winner.Academic_Year__c : null;
                Id academicTermId    = String.isNotBlank(winner.Academic_Cohort__c)
                                        ? (Id)winner.Academic_Cohort__c : null;
                Id locationId        = String.isNotBlank(winner.Location__c)
                                        ? (Id)winner.Location__c : null;
                Id academicSessionId = String.isNotBlank(winner.Academic_Terms_Session__c)
                                        ? (Id)winner.Academic_Terms_Session__c : null;
                Id learningCourseId  = String.isNotBlank(winner.Course__c)
                                        ? (Id)winner.Course__c : null;

                if (learningCourseId == null) {
                    throw new IllegalArgumentException(
                        'Course__c (LearningCourseId) is missing. Cannot create Course Offering.');
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
        String externalId = sessionRec.Name 
            + String.valueOf(locationId) 
            + String.valueOf(academicTermId);
        AcademicSession correctSession = altSessionByExternalId.get(externalId);

        if (correctSession != null) {
            finalSessionId = correctSession.Id;
            System.debug('Resolved session for lineup ' + lineup
                + ' → externalId: ' + externalId + ' → ID: ' + finalSessionId);

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
            System.debug('WARNING: No AcademicSession found for External ID: ' 
                + externalId + ' — using original academicSessionId: ' + academicSessionId);
        }
    }
}

                // ── Create or Update CourseOffering ──────────────────────────
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
                    co.Industry_Specialization_p__c =
                        AllotmentCourseOfferingHelper.mergeMultiSelectField(null, lineupRows, 'Industry_Specialization_p__c');
                    co.Concentration_p__c =
                        AllotmentCourseOfferingHelper.mergeMultiSelectField(null, lineupRows, 'Concentration_p__c');
                    offeringsToInsert.add(co);
                    insertOfferingByLineup.put(lineup, co);

                } else {
                    CourseOffering firstExisting = existingOfferings[0];
                    Boolean createNewForPGP =
                        winner.Program__r != null &&
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
                        co.Industry_Specialization_p__c =
                            AllotmentCourseOfferingHelper.mergeMultiSelectField(null, lineupRows, 'Industry_Specialization_p__c');
                        co.Concentration_p__c =
                            AllotmentCourseOfferingHelper.mergeMultiSelectField(null, lineupRows, 'Concentration_p__c');
                        offeringsToInsert.add(co);
                        insertOfferingByLineup.put(lineup, co);

                    } else {
                        CourseOffering co = new CourseOffering(Id = firstExisting.Id);
                        AllotmentCourseOfferingHelper.populateUpdateFields(
                            co, winner, finalSessionId, academicTermId, academicYearId,
                            locationId,
                            AllotmentCourseOfferingHelper.mergeFinalSessions(
                                firstExisting.Preferred_Sessions2__c, lineupRows),
                            AllotmentCourseOfferingHelper.mergeMultiSelectField(
                                null,               
                                 lineupRows, 'Industry_Specialization_p__c'),               
                             AllotmentCourseOfferingHelper.mergeMultiSelectField(
                                null,                          
                                lineupRows, 'Concentration_p__c')                      
                        );
                        offeringsToUpdate.add(co);
                        updateOfferingByLineup.put(lineup, co);
                    }
                }

            } catch (Exception e) {
                System.debug('Error preparing lineup ' + lineup + ': ' + e.getMessage());
                List<Allotment__c> errRows = lineupRowsMap.get(lineup);
                if (errRows != null) {
                    for (Allotment__c row : errRows) {
                        errorUpdates.add(new Allotment__c(
                            Id               = row.Id,
                            Sync_Status__c   = 'Error',
                            Error_Message__c = AllotmentCourseOfferingHelper.truncateError(
                                e.getMessage(), 255)
                        ));
                    }
                }
            }
        }

        // ── Step 5: Tag correct academic sessions then DML ───────────────────
        if (!offeringsToInsert.isEmpty()) {
            AllotmentCourseOfferingHelper.tagCorrectAcademicSessions(offeringsToInsert);
        }
        if (!offeringsToUpdate.isEmpty()) {
            AllotmentCourseOfferingHelper.tagCorrectAcademicSessions(offeringsToUpdate);
        }

        // Build a reverse routing map so we know which Lineup ties to which processing record
        Map<CourseOffering, String> lineupByOffering = new Map<CourseOffering, String>();
        for (String lineup : insertOfferingByLineup.keySet()) lineupByOffering.put(insertOfferingByLineup.get(lineup), lineup);
        for (String lineup : updateOfferingByLineup.keySet()) lineupByOffering.put(updateOfferingByLineup.get(lineup), lineup);

        if (!sessionUpdates.isEmpty()) {
            Database.SaveResult[] results = Database.update(sessionUpdates, false);
            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    String ds = '';
                    for (Database.Error err : results[i].getErrors()) ds += err.getMessage() + ' ';
                    System.debug('Session Update Error: ' + ds);
                }
            }
        }

        if (!offeringsToInsert.isEmpty()) {
            Database.SaveResult[] results = Database.insert(offeringsToInsert, false);
            for (Integer i = 0; i < results.size(); i++) {
                if (results[i].isSuccess()) {
                    System.debug('Successfully inserted CourseOffering ID: ' + results[i].getId());
                } else {
                    String ds = '';
                    for(Database.Error err : results[i].getErrors()) ds += err.getMessage() + ' ';
                    System.debug('CourseOffering Insert Error: ' + ds);
                    
                    String lineup = lineupByOffering.get(offeringsToInsert[i]);
                    if (lineup != null && lineupRowsMap.containsKey(lineup)) {
                        for (Allotment__c row : lineupRowsMap.get(lineup)) {
                            errorUpdates.add(new Allotment__c(Id = row.Id, Sync_Status__c = 'Error', Error_Message__c = AllotmentCourseOfferingHelper.truncateError('CO Insert Failed: ' + ds, 255)));
                        }
                    }
                }
            }
        }

        if (!offeringsToUpdate.isEmpty()) {
            Database.SaveResult[] results = Database.update(offeringsToUpdate, false);
            for (Integer i = 0; i < results.size(); i++) {
                if (results[i].isSuccess()) {
                    System.debug('Successfully updated CourseOffering ID: ' + results[i].getId());
                } else {
                    String ds = '';
                    for(Database.Error err : results[i].getErrors()) ds += err.getMessage() + ' ';
                    System.debug('CourseOffering Update Error: ' + ds);

                    String lineup = lineupByOffering.get(offeringsToUpdate[i]);
                    if (lineup != null && lineupRowsMap.containsKey(lineup)) {
                        for (Allotment__c row : lineupRowsMap.get(lineup)) {
                            errorUpdates.add(new Allotment__c(Id = row.Id, Sync_Status__c = 'Error', Error_Message__c = AllotmentCourseOfferingHelper.truncateError('CO Update Failed: ' + ds, 255)));
                        }
                    }
                }
            }
        }

        // ── Step 6: Faculty Linking ──────────────────────────────────────────
        Map<Id, Set<Id>>         neededFacultyByOffering  = new Map<Id, Set<Id>>();
        Map<Id, Map<Id, String>> facultyNamesByOffering   = new Map<Id, Map<Id, String>>();

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
                        Faculty__c         = facultyId,
                        Name               = facultyNamesByOffering.get(offeringId).get(facultyId)
                    ));
                }
            }
        }
        if (!facultyToInsert.isEmpty()) insert facultyToInsert;

        // ── Step 7: Final Status Updates ─────────────────────────────────────
        // Build a Set of error IDs for fast lookup instead of nested loop
        Set<Id> errorRowIds = new Set<Id>();
        for (Allotment__c e : errorUpdates) {
            errorRowIds.add(e.Id);
        }

        for (String lineup : scope) {
            List<Allotment__c> lineupRows = lineupRowsMap.get(lineup);
            if (lineupRows == null) continue;

            CourseOffering co = insertOfferingByLineup.containsKey(lineup)
                ? insertOfferingByLineup.get(lineup)
                : updateOfferingByLineup.get(lineup);
            Id targetId = (co != null) ? co.Id : null;

            if (errorRowIds.contains(lineupRows[0].Id)) continue;

            for (Allotment__c row : lineupRows) {
                finalStatusUpdates.add(new Allotment__c(
                    Id                 = row.Id,
                    Sync_Status__c     = 'Synced',
                    Error_Message__c   = null,
                    Course_Offering__c = targetId
                ));
            }
        }

        if (!finalStatusUpdates.isEmpty()) update finalStatusUpdates;
        if (!errorUpdates.isEmpty())       Database.update(errorUpdates, false);
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('AllotmentCourseOfferingBatch completed.');
    }
}