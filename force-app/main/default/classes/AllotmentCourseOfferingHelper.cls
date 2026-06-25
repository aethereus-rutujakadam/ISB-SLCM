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
                SELECT Id, Name, AcademicTermId, Location__c, Program__c, From_Date__c, To_date__c
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
                   Industry_Specialization_p__c,
                    Concentration_p__c, 
                   AcademicSessionId,
                   LearningCourse.ISB_External_Id__c
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
        String finalSessions,
        String industrySpecialization,
        String concentration 
    ) {
        co.AcademicSessionId = academicSessionId;
        co.Academic_Term__c = academicTermId;
        co.Academic_Year__c = academicYearId;
        co.Area__c = src.Area__c;
        co.Preferred_Sessions2__c = finalSessions;
        co.ISB_Sessions__c = src.ISB_Sessions__c;
        co.SectionNumber = src.Section_Number__c;
        co.Teaching_Location_P__c = src.Teaching_Location_P__c;
        co.Industry_Specialization_p__c = industrySpecialization;
        co.Concentration_p__c = concentration;
        co.IsActive = true;
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

public static String mergeMultiSelectField(String existingValue, List<Allotment__c> rows, String fieldApiName) {
    Set<String> parts = new Set<String>();
    addCsv(parts, existingValue);

    for (Allotment__c row : rows) {
        addCsv(parts, (String) row.get(fieldApiName));
    }

    List<String> sortedValues = new List<String>(parts);
    sortedValues.sort();
    return String.join(sortedValues, ';');
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
        
        // Collect external IDs from offerings to query AcademicSession
    Set<String> externalIdsToMatch = new Set<String>();
    for (CourseOffering co : offerings) {
        if (co.Academic_Term__c == null || co.Location__c == null) continue;
            AcademicSession mappedSess = sessionMap.get(co.AcademicSessionId);
        if (mappedSess != null) {
            // FIX #2: Validate Session Name is NOT blank before using it
            if (String.isBlank(mappedSess.Name)) {
                System.debug('WARNING: AcademicSession [' + mappedSess.Id + '] has blank/null Name. Skipping external ID construction for CO [' + co.Id + ']');
                continue;
            }
            
            // FIX #1: Debug logging for key construction components
            String extId = mappedSess.Name 
                + String.valueOf(co.Location__c) 
                + String.valueOf(co.Academic_Term__c);
            System.debug('Collecting External ID - Session: [' + mappedSess.Name + '] Location: [' + co.Location__c + '] Term: [' + co.Academic_Term__c + '] → Final Key: [' + extId + ']');
            externalIdsToMatch.add(extId);
        }
    }

        if (!externalIdsToMatch.isEmpty()) {
            for (AcademicSession s : [
                SELECT Id, Name, AcademicTermId, Location__c, ISB_External_Id__c
                FROM AcademicSession
                WHERE ISB_External_Id__c IN :externalIdsToMatch
            ]) {
        correctSessionMap.put(s.ISB_External_Id__c, s);
        System.debug('Fetched Correct Session from DB >> ExternalId: ' 
            + s.ISB_External_Id__c + ' | ID: ' + s.Id);
    }
}

        for (CourseOffering co : offerings) {
            if (co.Academic_Term__c != null && co.AcademicSessionId != null) {
                AcademicSession mappedSess = sessionMap.get(co.AcademicSessionId);
                if (mappedSess != null) {
                    // FIX #2: Validate Session Name is NOT blank
                    if (String.isBlank(mappedSess.Name)) {
                        System.debug('ERROR: AcademicSession [' + mappedSess.Id + '] has blank/null Name. Cannot resolve correct session for CO [' + co.Id + ']');
                        continue;
                    }
                    
                    if (co.Location__c == null || co.Academic_Term__c == null) {
                        System.debug('WARNING: Skipping CourseOffering [' + co.Id + '] - NULL Location or Term not allowed for matching');
                        continue;
                    }
                    
                    // FIX #1: Debug logging showing exact key components before lookup
                    String extId = mappedSess.Name 
                        + String.valueOf(co.Location__c) 
                        + String.valueOf(co.Academic_Term__c);
                    System.debug('Matching External ID for CO [' + co.Id + '] - Session: [' + mappedSess.Name + '] Location: [' + co.Location__c + '] Term: [' + co.Academic_Term__c + '] → Final Key: [' + extId + ']');
                    AcademicSession correctSess = correctSessionMap.get(extId);
                    
        if (correctSess != null) {
            System.debug('SUCCESS: Updating CourseOffering [' + co.Id + '] Session from ' + co.AcademicSessionId + ' -> ' + correctSess.Id);
                co.AcademicSessionId = correctSess.Id;
            } else {
                    System.debug('WARNING: No matched DB session found for expected constraint key: ' + extId);
                    }
            }
        }
     }
        System.debug('--- Finished tagCorrectAcademicSessions() ---');
    }
}