public class AllotmentSyncService {

    public static void process(Map<String, List<Map<String, Object>>> lineupToAllotments) {
        System.debug('Starting AllotmentSyncService.process with ' + lineupToAllotments.size() + ' lineup configurations.');

        // ── STEP 1: Collect Keys for Lookups ─────────────────────────────────
        Set<String> courseIdentifiers = new Set<String>();
        Set<String> locationIdentifiers = new Set<String>();
        Set<String> programIdentifiers = new Set<String>();
        Set<String> intakeIdentifiers = new Set<String>();
        Set<String> cohortIdentifiers = new Set<String>();
        Set<String> termIdentifiers = new Set<String>();

        for (String lineupId : lineupToAllotments.keySet()) {
            Map<String, Object> firstRecord = lineupToAllotments.get(lineupId)[0];
            System.debug('firstRecord payload: ' + JSON.serialize(firstRecord));
            System.debug('firstRecord keys: ' + firstRecord.keySet());
            
            String courseId  = (String) firstRecord.get('Allotment__c_UATAdmission__dlm_Course_c__c');
            String locId     = (String) firstRecord.get('Allotment__c_UATAdmission__dlm_Location_c__c');
            String progId    = (String) firstRecord.get('Allotment__c_UATAdmission__dlm_Program_c__c');
            String intakeId  = (String) firstRecord.get('Allotment__c_UATAdmission__dlm_Intake_c__c');
            String cohortId  = (String) firstRecord.get('Allotment__c_UATAdmission__dlm_Cohort__c');
            String termId    = (String) firstRecord.get('Allotment__c_UATAdmission__dlm_Term_c__c');

            if (String.isNotBlank(courseId)) courseIdentifiers.add(courseId);
            if (String.isNotBlank(locId)) locationIdentifiers.add(locId);
            if (String.isNotBlank(progId)) programIdentifiers.add(progId);
            if (String.isNotBlank(intakeId)) intakeIdentifiers.add(intakeId);
            if (String.isNotBlank(cohortId)) cohortIdentifiers.add(cohortId);
            if (String.isNotBlank(termId)) termIdentifiers.add(termId);
        }

        // ── STEP 2: Query Lookup Objects ─────────────────────────────────────
        Map<String, Id> courseExtToId = new Map<String, Id>();
        if (!courseIdentifiers.isEmpty()) {
            for (LearningCourse lc : [SELECT Id, ISB_External_Id__c FROM LearningCourse WHERE ISB_External_Id__c IN :courseIdentifiers]) {
                courseExtToId.put(lc.ISB_External_Id__c, lc.Id);
            }
        }

        Map<String, Id> locationExtToId = new Map<String, Id>();
        if (!locationIdentifiers.isEmpty()) {
            for (Schema.Location loc : [SELECT Id, ISB_External_Id__c FROM Location WHERE ISB_External_Id__c IN :locationIdentifiers]) {
                locationExtToId.put(loc.ISB_External_Id__c, loc.Id);
            }
        }

        Map<String, Id> programExtToId = new Map<String, Id>();
        if (!programIdentifiers.isEmpty()) {
            for (Program prog : [SELECT Id, ISB_External_Id__c FROM Program WHERE ISB_External_Id__c IN :programIdentifiers]) {
                programExtToId.put(prog.ISB_External_Id__c, prog.Id);
            }
        }

        Map<String, Id> yearExtToId = new Map<String, Id>();
        if (!intakeIdentifiers.isEmpty()) {
            for (AcademicYear ay : [SELECT Id, ISB_External_Id__c FROM AcademicYear WHERE ISB_External_Id__c IN :intakeIdentifiers]) {
                yearExtToId.put(ay.ISB_External_Id__c, ay.Id);
            }
        }

        Map<String, Id> termExtToId = new Map<String, Id>();
        if (!cohortIdentifiers.isEmpty()) {
            for (AcademicTerm at : [SELECT Id, ISB_External_Id__c FROM AcademicTerm WHERE ISB_External_Id__c IN :cohortIdentifiers]) {
                termExtToId.put(at.ISB_External_Id__c, at.Id);
            }
        }

        Map<String, Id> sessionExtToId = new Map<String, Id>();
        if (!termIdentifiers.isEmpty()) {
            for (AcademicSession sess : [SELECT Id, ISB_External_Id__c FROM AcademicSession WHERE ISB_External_Id__c IN :termIdentifiers]) {
                sessionExtToId.put(sess.ISB_External_Id__c, sess.Id);
            }
        }

        System.debug('Lookups populated: Courses: ' + courseExtToId.size() + ', Locations: ' + locationExtToId.size() + 
                     ', Programs: ' + programExtToId.size() + ', AcademicYears: ' + yearExtToId.size() + 
                     ', AcademicTerms: ' + termExtToId.size() + ', AcademicSessions: ' + sessionExtToId.size());

        // ── STEP 3: Build 1 CourseOffering per LineUp__c ──────────────────

        Map<String, CourseOffering> offeringMap = new Map<String, CourseOffering>();

        for (String lineupId : lineupToAllotments.keySet()) {

            Map<String, Object> firstRecord = lineupToAllotments.get(lineupId)[0];

            // Safely parse Dates from payload (assumes YYYY-MM-DD or parsable string)
            String teachingDateStr = (String) firstRecord.get('Allotment__c_UATAdmission__dlm_Teaching_Date_c__c');
            String termStartStr    = (String) firstRecord.get('Allotment__c_UATAdmission__dlm_Term_From_date__c');
            String termToStr       = (String) firstRecord.get('Allotment__c_UATAdmission__dlm_Term_To_date__c');

            Date parsedTeachingDate = String.isNotBlank(teachingDateStr) ? Date.valueOf(teachingDateStr) : null;
            Date parsedTermStart    = String.isNotBlank(termStartStr) ? Date.valueOf(termStartStr) : null;
            Date parsedTermTo       = String.isNotBlank(termToStr) ? Date.valueOf(termToStr) : null;
            
            // Extract external IDs to grab the actual resolved Salesforce Id
            String courseId  = (String) firstRecord.get('Allotment__c_UATAdmission__dlm_Course_c__c');
            String locId     = (String) firstRecord.get('Allotment__c_UATAdmission__dlm_Location_c__c');
            String progId    = (String) firstRecord.get('Allotment__c_UATAdmission__dlm_Program_c__c');
            String intakeId  = (String) firstRecord.get('Allotment__c_UATAdmission__dlm_Intake_c__c');
            String cohortId  = (String) firstRecord.get('Allotment__c_UATAdmission__dlm_Cohort__c');
            String termId    = (String) firstRecord.get('Allotment__c_UATAdmission__dlm_Term_c__c');

            offeringMap.put(lineupId, new CourseOffering(
                ISB_Line_Up_ID__c           = lineupId,
                ISB_External_Id__c          = (String) firstRecord.get('Allotment__c_UATAdmission__dlm_Id__c'),
                Name                        = (String) firstRecord.get('Allotment__c_UATAdmission__dlm_Name__c'),
                Area__c                     = (String) firstRecord.get('Allotment__c_UATAdmission__dlm_Area_c__c'),
                Course_Type__c              = (String) firstRecord.get('Allotment__c_UATAdmission__dlm_Course_Type__c'),
                Final_Allotment_Sessions__c = (String) firstRecord.get('Allotment__c_UATAdmission__dlm_Preferred_Sessions2_c__c'),
                ISB_Sessions__c             = (String) firstRecord.get('Allotment__c_UATAdmission__dlm_Sessions_c__c'),
                //IsActive                    = true,
                SectionNumber               = (String) firstRecord.get('Allotment__c_UATAdmission__dlm_Sections_c__c'),
                Status__c                   = (String) firstRecord.get('Allotment__c_UATAdmission__dlm_Status_c__c'),
                Teaching_Dates__c           = (String) firstRecord.get('Allotment__c_UATAdmission__dlm_Teaching_Dates_c__c'),
                Teaching_Location_P__c      = (String) firstRecord.get('Allotment__c_UATAdmission__dlm_Teaching_Location_P_c__c'),
                
                // Mapped lookups & Dates
                Teaching_Date__c            = parsedTeachingDate,
                Term_Start_Date__c          = parsedTermStart,
                Term_To_Date__c             = parsedTermTo,
                LearningCourseId            = String.isNotBlank(courseId) ? courseExtToId.get(courseId) : null,
                Location__c                 = String.isNotBlank(locId) ? locationExtToId.get(locId) : null,
                Program__c                  = String.isNotBlank(progId) ? programExtToId.get(progId) : null,
                Academic_Year__c            = String.isNotBlank(intakeId) ? yearExtToId.get(intakeId) : null,
                Academic_Term__c            = String.isNotBlank(cohortId) ? termExtToId.get(cohortId) : null,
                AcademicSessionId           = String.isNotBlank(termId) ? sessionExtToId.get(termId) : null
            ));
        }

        System.debug('Upserting ' + offeringMap.size() + ' CourseOffering records.');
        // ── STEP 4: Upsert CourseOffering FIRST (parent guaranteed) ───────
        if (!offeringMap.isEmpty()) {
            upsert offeringMap.values() ISB_External_Id__c;
        }

        // ── STEP 5: Re-query to get confirmed Salesforce IDs ──────────────
        System.debug('Re-querying CourseOffering references.');
        Map<String, Id> lineupToSFId = new Map<String, Id>();

        for (CourseOffering co : [
            SELECT Id, ISB_Line_Up_ID__c
            FROM CourseOffering
            WHERE ISB_Line_Up_ID__c IN :offeringMap.keySet()
        ]) {
            lineupToSFId.put(co.ISB_Line_Up_ID__c, co.Id);
        }

        // ── STEP 6: Build and Fetch Contacts for Course Faculty ───────────
        Set<String> facultyIdentifiers = new Set<String>();
        for (String lineupId : lineupToAllotments.keySet()) {
            for (Map<String, Object> row : lineupToAllotments.get(lineupId)) {
                String facultyId = (String) row.get('Allotment__c_UATAdmission__dlm_Faculty_Database_del_c__c');
                if (String.isNotBlank(facultyId)) {
                    facultyIdentifiers.add(facultyId);
                }
            }
        }
        
        System.debug('Identified ' + facultyIdentifiers.size() + ' distinct Faculty IDs for processing.');

        Map<String, Id> facultyIdToContactId = new Map<String, Id>();
        Map<String, String> facultyIdToContactName = new Map<String, String>();
        if (!facultyIdentifiers.isEmpty()) {
            for (Contact con : [
                SELECT Id, Name, ISB_External_Id__c 
                FROM Contact 
                WHERE Id IN :facultyIdentifiers OR ISB_External_Id__c IN :facultyIdentifiers
            ]) {
                facultyIdToContactId.put(con.Id, con.Id);
                facultyIdToContactName.put(con.Id, con.Name);
                if (String.isNotBlank(con.ISB_External_Id__c)) {
                    facultyIdToContactId.put(con.ISB_External_Id__c, con.Id);
                    facultyIdToContactName.put(con.ISB_External_Id__c, con.Name);
                }
            }
        }
        
        System.debug('Resolved ' + facultyIdToContactId.size() + ' faculty map entries against Contact.');

        List<Course_Faculty__c> facultyList = new List<Course_Faculty__c>();

        for (String lineupId : lineupToAllotments.keySet()) {

            Id parentId = lineupToSFId.get(lineupId);

            if (parentId == null) {
                System.debug('Skipping faculty map for lineup ' + lineupId + ' because parent CourseOffering Id is null.');
                continue;
            }

            for (Map<String, Object> row : lineupToAllotments.get(lineupId)) {

                String facultyIdStr = (String) row.get('Allotment__c_UATAdmission__dlm_Faculty_Database_del_c__c');
                if (String.isBlank(facultyIdStr)) continue;

                Id matchedContactId = facultyIdToContactId.get(facultyIdStr);
                String matchedContactName = facultyIdToContactName.get(facultyIdStr);
                
                if (matchedContactId == null) {
                    System.debug('Contact NOT FOUND for Faculty Id: ' + facultyIdStr + '. Skipping Course_Faculty record.');
                    continue;
                }

                facultyList.add(new Course_Faculty__c(
                    Name               = matchedContactName,
                    Course_Offering__c = parentId,        
                    Faculty__c         = matchedContactId 
                ));
            }
        }
        
        System.debug('Inserting ' + facultyList.size() + ' Course_Faculty__c records.');
        if (!facultyList.isEmpty()) {
            insert facultyList;
        }
        System.debug('AllotmentSyncService.process completed successfully.');
    }
}