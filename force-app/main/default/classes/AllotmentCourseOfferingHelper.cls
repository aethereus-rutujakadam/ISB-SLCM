public without sharing class AllotmentCourseOfferingHelper {

    public class ReferenceData {
        public Map<Id, AcademicSession> sessionById = new Map<Id, AcademicSession>();
        public Map<String, List<CourseOffering>> offeringsByLineup = new Map<String, List<CourseOffering>>();
    }

    public static Map<String, List<Allotment__c>> groupByLineup(List<Allotment__c> rows) {
        Map<String, List<Allotment__c>> result = new Map<String, List<Allotment__c>>();

        for (Allotment__c row : rows) {
            if (String.isBlank(row.ISB_Line_Up_ID__c)) {
                continue;
            }
            if (!result.containsKey(row.ISB_Line_Up_ID__c)) {
                result.put(row.ISB_Line_Up_ID__c, new List<Allotment__c>());
            }
            result.get(row.ISB_Line_Up_ID__c).add(row);
        }

        return result;
    }

    public static ReferenceData loadReferenceData(List<Allotment__c> rows, List<String> scopeLineups) {
        System.debug('--- AllotmentCourseOfferingHelper.loadReferenceData() ---');
        ReferenceData ref = new ReferenceData();

        Set<Id> sessionIds = new Set<Id>();

        for (Allotment__c row : rows) {
            // System.debug('Staging Row IDs: Program=' + row.Program__c + 
            //              ', Year=' + row.Academic_Year__c + 
            //              ', Cohort=' + row.Academic_Cohort__c + 
            //              ', Session=' + row.Academic_Terms_Session__c + 
            //              ', Location=' + row.Location__c + 
            //              ', Course=' + row.Course__c);

            try {
                if (String.isNotBlank(row.Academic_Terms_Session__c)) {
                    // Assuming this is a Salesforce ID, we can cast it
                    sessionIds.add((Id)row.Academic_Terms_Session__c);
                }
            } catch(Exception e) {
                System.debug('Failed to cast Session ID: ' + row.Academic_Terms_Session__c);
            }
        }

        if (!sessionIds.isEmpty()) {
            for (AcademicSession s : [
                SELECT Id, Name, AcademicTermId, Location__c
                FROM AcademicSession
                WHERE Id IN :sessionIds
            ]) {
                ref.sessionById.put(s.Id, s);
            }
        }

        for (CourseOffering co : [
            SELECT Id,
                   ISB_Line_Up_ID__c,
                   Preferred_Sessions2__c,
                   LearningCourseId,
                   LearningCourse.ISB_External_Id__c,
                   ISB_External_Id__c,
                   ISB_Sessions__c,
                   AcademicSessionId,
                   Academic_Term__c,
                   Academic_Year__c,
                   Program__c,
                   Location__c,
                   SectionNumber,
                   Area__c,
                   Course_Type__c,
                   Teaching_Date__c,
                   Teaching_Dates__c,
                   Term_Start_Date__c,
                   Term_To_Date__c,
                   Teaching_Location_P__c,
                   Status__c,
                   IsActive,
                   Course_Code__c,
                   Course_Acronym__c,
                   Description,
                   Mode_of_Delivery__c,
                   Mode_of_Teaching_Confirmation__c,
                   Exam_Types__c,
                   EnrollmentCapacity,
                   StartDate,
                   EndDate,
                   Credit__c,
                   Grade_Release_Date__c,
                   LMS_Course_Id__c,
                   LMS_Sync_Status__c,
                   LMS_Error__c,
                   Concentration__c,
                   Industry_Specialization__c
            FROM CourseOffering
            WHERE ISB_Line_Up_ID__c IN :scopeLineups
        ]) {
            if (!ref.offeringsByLineup.containsKey(co.ISB_Line_Up_ID__c)) {
                ref.offeringsByLineup.put(co.ISB_Line_Up_ID__c, new List<CourseOffering>());
            }
            ref.offeringsByLineup.get(co.ISB_Line_Up_ID__c).add(co);
        }
        
        System.debug('Reference Data loaded: Sessions=' + ref.sessionById.size() + 
                     ', CourseOfferings By Lineup=' + ref.offeringsByLineup.size());

        return ref;
    }

    public static void populateCreateFields(
        CourseOffering co,
        Allotment__c src,
        Id academicSessionId,
        Id academicTermId,
        Id academicYearId,
        Id programId,
        Id learningCourseId,
        Id locationId
    ) {
        co.AcademicSessionId = academicSessionId;
        co.Academic_Term__c = academicTermId;
        co.Academic_Year__c = academicYearId;
        co.Area__c = src.Area__c;
        co.Course_Type__c = src.Course_Type__c;
        //co.ISB_External_Id__c = src.Source_External_Id__c;
        co.ISB_Line_Up_ID__c = src.ISB_Line_Up_ID__c;
        co.ISB_Sessions__c = src.ISB_Sessions__c;
        co.IsActive = true;
        co.LearningCourseId = learningCourseId;
        co.Location__c = locationId;
        co.Name = src.Name;
        co.Program__c = programId;
        co.SectionNumber = src.Section_Number__c;
        co.Status__c = src.Status__c;
        co.Teaching_Date__c = src.Teaching_Date__c;
        co.Teaching_Dates__c = src.Teaching_Dates__c;
        co.Teaching_Location_P__c = src.Teaching_Location_P__c;
        co.Term_Start_Date__c = src.Term_Start_Date__c;
        co.Term_To_Date__c = src.Term_To_Date__c;
    }

    public static void populateUpdateFields(
        CourseOffering co,
        Allotment__c src,
        Id academicSessionId,
        Id academicTermId,
        Id academicYearId,
        Id locationId,
        String finalSessions
    ) {
        co.AcademicSessionId = academicSessionId;
        co.Academic_Term__c = academicTermId;
        co.Academic_Year__c = academicYearId;
        co.Area__c = src.Area__c;
        co.Preferred_Sessions2__c = finalSessions;
        co.ISB_Sessions__c = src.ISB_Sessions__c;
        co.SectionNumber = src.Section_Number__c;
        co.Teaching_Location_P__c = src.Teaching_Location_P__c;
        if (locationId != null) {
            co.Location__c = locationId;
        }
    }

    public static String mergeFinalSessions(String existingValue, List<Allotment__c> rows) {
        Set<String> parts = new Set<String>();

        addCsv(parts, existingValue);

        for (Allotment__c row : rows) {
            // System.debug('Row ' + row.Id + ' Raw Preferred_Sessions2__c string = ' + row.Preferred_Sessions2__c);
            addCsv(parts, row.Preferred_Sessions2__c);
        }

        List<String> sortedValues = new List<String>();
        sortedValues.addAll(parts);
        sortedValues.sort();

        String finalString = String.join(sortedValues, ',');
        System.debug('Merged Final Sessions string: ' + finalString);
        return finalString;
    }

    private static void addCsv(Set<String> collector, String csv) {
        if (String.isBlank(csv)) {
            return;
        }

        // Salesforce Multi-Select Picklists use semicolons, so we split by both commas and semicolons
        for (String value : csv.split('[,;]')) {
            String trimmed = value != null ? value.trim() : null;
            if (String.isNotBlank(trimmed)) {
                collector.add(trimmed);
            }
        }
    }

    public static String truncateError(String msg, Integer maxLen) {
        if (msg == null) {
            return null;
        }
        return msg.length() <= maxLen ? msg : msg.substring(0, maxLen);
    }

    public static List<Allotment__c> getActiveAllotments(List<Allotment__c> allAllotments) {
        List<Allotment__c> activeAllotments = new List<Allotment__c>();
        for (Allotment__c a : allAllotments) {
            if (a.Status_New__c == 'Active') {
                activeAllotments.add(a);
            }
        }
        return activeAllotments;
    }

    public static CourseOffering_History__c copyOfferingToHistory(CourseOffering co, String originalCoId) {
        CourseOffering_History__c history = new CourseOffering_History__c();
        
        // Standard fields
        //history.Name = co.Name;
        history.CourseOffering__c = originalCoId != null ? originalCoId : co.Id;
        history.ISB_Line_Up_ID__c = co.ISB_Line_Up_ID__c;
        history.ISB_External_Id__c = co.ISB_External_Id__c;
        history.ISB_Sessions__c = co.ISB_Sessions__c;
        history.LearningCourse__c = co.LearningCourseId;
        history.AcademicSession__c = co.AcademicSessionId;
        history.Academic_Term__c = co.Academic_Term__c;
        history.Academic_Year__c = co.Academic_Year__c;
        history.Program__c = co.Program__c;
        history.Location__c = co.Location__c;
        history.SectionNumber__c = co.SectionNumber;
        history.Area__c = co.Area__c;
        history.Course_Type__c = co.Course_Type__c;
        history.Teaching_Date__c = co.Teaching_Date__c;
        history.Teaching_Dates__c = co.Teaching_Dates__c;
        history.Term_Start_Date__c = co.Term_Start_Date__c;
        history.Term_To_Date__c = co.Term_To_Date__c;
        history.Teaching_Location_P__c = co.Teaching_Location_P__c;
        history.Preferred_Sessions2__c = co.Preferred_Sessions2__c;
        history.Status__c = co.Status__c;
        history.IsActive__c = co.IsActive;
        history.Course_Code__c = co.Course_Code__c;
        history.Course_Acronym__c = co.Course_Acronym__c;
        history.Description__c = co.Description;
        history.Mode_of_Delivery__c = co.Mode_of_Delivery__c;
        history.Mode_of_Teaching_Confirmation__c = co.Mode_of_Teaching_Confirmation__c;
        history.Exam_Types__c = co.Exam_Types__c;
        history.EnrollmentCapacity__c = co.EnrollmentCapacity;
        history.StartDate__c = co.StartDate != null ? co.StartDate.date() : null;
        history.EndDate__c = co.EndDate != null ? co.EndDate.date() : null;
        history.Credit__c = co.Credit__c;
        history.Grade_Release_Date__c = co.Grade_Release_Date__c;
        history.LMS_Course_Id__c = co.LMS_Course_Id__c;
        history.LMS_Sync_Status__c = co.LMS_Sync_Status__c;
        history.LMS_Error__c = co.LMS_Error__c;
        history.Concentration__c = co.Concentration__c;
        history.Industry_Specialization__c = co.Industry_Specialization__c;
        
        return history;
    }

    public static void recalculateCourseOfferingForInactiveAllotments(
        CourseOffering co,
        List<Allotment__c> allLineupAllotments,
        ReferenceData refData
    ) {
        System.debug('--- Recalculating CourseOffering for inactive allotments ---');
        
        List<Allotment__c> activeAllotments = getActiveAllotments(allLineupAllotments);
        
        if (activeAllotments.isEmpty()) {
            co.IsActive = false;
            return;
        }
        
        Allotment__c winner = activeAllotments[0];
        
        Id programId         = String.isNotBlank(winner.Program__c)               ? (Id)winner.Program__c               : null;
        Id academicYearId    = String.isNotBlank(winner.Academic_Year__c)          ? (Id)winner.Academic_Year__c          : null;
        Id academicTermId    = String.isNotBlank(winner.Academic_Cohort__c)        ? (Id)winner.Academic_Cohort__c        : null;
        Id locationId        = String.isNotBlank(winner.Location__c)               ? (Id)winner.Location__c               : null;
        Id academicSessionId = String.isNotBlank(winner.Academic_Terms_Session__c) ? (Id)winner.Academic_Terms_Session__c : null;
        Id learningCourseId  = String.isNotBlank(winner.Course__c)                 ? (Id)winner.Course__c                 : null;
        
        Id finalSessionId = academicSessionId;
        
        if (academicSessionId != null) {
            AcademicSession sessionRec = refData.sessionById.get(academicSessionId);
            if (sessionRec != null && academicTermId != null && sessionRec.AcademicTermId != null && sessionRec.AcademicTermId != academicTermId) {
                String key = sessionRec.Name + '|' + String.valueOf(academicTermId);
                finalSessionId = academicSessionId;
            }
        }
        
        co.AcademicSessionId = finalSessionId;
        co.Academic_Term__c = academicTermId;
        co.Academic_Year__c = academicYearId;
        co.Area__c = winner.Area__c;
        co.Preferred_Sessions2__c = mergeFinalSessions(null, activeAllotments);
        co.ISB_Sessions__c = winner.ISB_Sessions__c;
        co.SectionNumber = winner.Section_Number__c;
        co.Teaching_Location_P__c = winner.Teaching_Location_P__c;
        if (locationId != null) {
            co.Location__c = locationId;
        }
        co.Program__c = programId;
        co.Status__c = winner.Status__c;
        co.IsActive = true;
    }

    public static void tagCorrectAcademicSessions(List<CourseOffering> offerings) {
        System.debug('--- Running tagCorrectAcademicSessions() Helper ---');
        Set<Id> termIds = new Set<Id>();
        Set<Id> sessionIds = new Set<Id>();

        for (CourseOffering co : offerings) {
            if (co.Academic_Term__c != null && co.AcademicSessionId != null) {
                termIds.add(co.Academic_Term__c);
                sessionIds.add(co.AcademicSessionId);
            }
        }

        System.debug('Evaluating ' + termIds.size() + ' termIds and ' + sessionIds.size() + ' sessionIds from the incoming Course Offerings.');

        if (termIds.isEmpty() || sessionIds.isEmpty()) return;

        Map<Id, AcademicSession> sessionMap = new Map<Id, AcademicSession>([
            SELECT Id, Name, Location__c FROM AcademicSession WHERE Id IN :sessionIds
        ]);

        Set<String> sessionNames = new Set<String>();
        for (AcademicSession s : sessionMap.values()) {
            if (String.isNotBlank(s.Name)) {
                sessionNames.add(s.Name);
            }
        }

        if (sessionNames.isEmpty()) return;

        System.debug('Gathered target Session Names to search exactly: ' + sessionNames);
        Map<String, AcademicSession> correctSessionMap = new Map<String, AcademicSession>();
        
        // Collect all unique location IDs from offerings - NULL locations excluded
        Set<Id> locationIds = new Set<Id>();
        for (CourseOffering co : offerings) {
            if (co.Location__c != null) {
                locationIds.add(co.Location__c);
            }
        }
        // Also check locations from already-mapped sessions
        for (AcademicSession s : sessionMap.values()) {
            if (s.Location__c != null) {
                locationIds.add(s.Location__c);
            }
        }
        
        // Query only for sessions with valid Location values
        if (!locationIds.isEmpty()) {
            for (AcademicSession s : [
                SELECT Id, Name, AcademicTermId, Location__c, From_Date__c, To_date__c 
                FROM AcademicSession 
                WHERE Name IN :sessionNames 
                  AND AcademicTermId IN :termIds
                  AND Location__c IN :locationIds
            ]) {
                String key = s.Name + '-' + String.valueOf(s.AcademicTermId).substring(0,15) + '-' + String.valueOf(s.Location__c);
                correctSessionMap.put(key, s);
                System.debug('Fetched Correct Session from DB >> Key: ' + key + ' | ID: ' + s.Id);
            }
        }

        for (CourseOffering co : offerings) {
            if (co.Academic_Term__c != null && co.AcademicSessionId != null) {
                AcademicSession mappedSess = sessionMap.get(co.AcademicSessionId);
                if (mappedSess != null && String.isNotBlank(mappedSess.Name)) {
                    Id effectiveLocation = co.Location__c != null ? co.Location__c : mappedSess.Location__c;
                    // Skip if Location is NULL - Location is required for matching
                    if (effectiveLocation == null) {
                        System.debug('WARNING: Skipping CourseOffering [' + co.Id + '] - NULL Location not allowed for matching');
                        continue;
                    }
                    String key = mappedSess.Name + '-' + String.valueOf(co.Academic_Term__c).substring(0,15) + '-' + String.valueOf(effectiveLocation);
                    AcademicSession correctSess = correctSessionMap.get(key);
                    
                    if (correctSess != null) {
                        System.debug('SUCCESS: Updating CourseOffering [' + co.Id + '] Session from ' + co.AcademicSessionId + ' -> ' + correctSess.Id);
                        co.AcademicSessionId = correctSess.Id;
                    } else {
                        System.debug('WARNING: No matched DB session found for expected constraint key: ' + key);
                    }
                }
            }
        }
        System.debug('--- Finished tagCorrectAcademicSessions() ---');
    }
}