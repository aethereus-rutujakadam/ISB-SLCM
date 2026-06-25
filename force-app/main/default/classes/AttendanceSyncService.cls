@RestResource(urlMapping='/LMS/AttendanceSync')
global without sharing class AttendanceSyncService {

    @HttpPost
    global static ResponseWrapper receiveAttendance() {

        try {
            RestRequest req = RestContext.request;

            // Handle potential empty body
            if (req.requestBody == null) {
                return new ResponseWrapper('ERROR', 'Request body is empty.');
            }

            List<AttendanceRequestWrapper> inputList =
                (List<AttendanceRequestWrapper>) JSON.deserialize(
                    req.requestBody.toString(),
                    List<AttendanceRequestWrapper>.class
                );

            if (inputList == null || inputList.isEmpty()) {
                return new ResponseWrapper('ERROR', 'Request body list is empty.');
            }

            // ----------------------------
            // 1️⃣ Collect StudentPGIDs + CourseOfferingIds
            // ----------------------------
            Set<String> pgIds = new Set<String>();
            Set<String> lmsCourseIds = new Set<String>();

            Integer rowIndex = 0;
            for (AttendanceRequestWrapper ar : inputList) {
                if (String.isBlank(ar.CourseOfferingId)) {
                    return new ResponseWrapper('ERROR', 'Missing CourseOfferingId at index ' + rowIndex);
                }
                if (String.isBlank(ar.SessionDate) || String.isBlank(ar.SessionTime)) {
                    return new ResponseWrapper('ERROR', 'Missing SessionDate/SessionTime at index ' + rowIndex);
                }

                lmsCourseIds.add(ar.CourseOfferingId);

                if (ar.Students != null) {
                    for (StudentData stu : ar.Students) {
                        if (!String.isBlank(stu.StudentPGID)) {
                            pgIds.add(stu.StudentPGID);
                        }
                    }
                }
                rowIndex++;
            }

            // ----------------------------
            // 2️⃣ Fetch Course Offerings (Map by LMS ID)
            // ----------------------------
            Map<String, CourseOffering> lmsIdToOfferingMap = new Map<String, CourseOffering>();
            Set<Id> termIds = new Set<Id>();

            if (!lmsCourseIds.isEmpty()) {
                for (CourseOffering co : [
                    SELECT Id, Academic_Term__c, LMS_Course_ID__c
                    FROM CourseOffering
                    WHERE LMS_Course_ID__c IN :lmsCourseIds
                ]) {
                    if (co.LMS_Course_ID__c != null) {
                        lmsIdToOfferingMap.put(co.LMS_Course_ID__c, co);
                        if (co.Academic_Term__c != null) {
                            termIds.add(co.Academic_Term__c);
                        }
                    }
                }
            }

            // ----------------------------
            // 3️⃣ Fetch Program Enrollments by PGID (Map by PGID)
            // ----------------------------
            Map<String, ProgramEnrollment> peMap = new Map<String, ProgramEnrollment>();
            
            if (!pgIds.isEmpty()) {
                // Fetch PEs that match PGID
                List<ProgramEnrollment> peList = [
                    SELECT Id, PGID__c, Academic_Term__c, ContactId
                    FROM ProgramEnrollment
                    WHERE PGID__c IN :pgIds
                ];

                for (ProgramEnrollment pe : peList) {
                    // Key: PGID
                    if (pe.PGID__c != null) {
                        peMap.put(pe.PGID__c, pe);
                    }
                }
            }

            // ----------------------------
            // 4️⃣ Enrollment_Session__c by Program Enrollment
            // ----------------------------
            Map<Id, Enrollment_Session__c> peToES = new Map<Id, Enrollment_Session__c>();

            Set<Id> peIds = new Set<Id>();
            for (ProgramEnrollment pe : peMap.values()) peIds.add(pe.Id);

            if (!peIds.isEmpty()) {
                List<Enrollment_Session__c> esList = [
                    SELECT Id, Program_Enrollment__c, CreatedDate
                    FROM Enrollment_Session__c
                    WHERE Program_Enrollment__c IN :peIds
                    ORDER BY CreatedDate DESC
                ];

                for (Enrollment_Session__c es : esList) {
                    if (!peToES.containsKey(es.Program_Enrollment__c)) {
                        peToES.put(es.Program_Enrollment__c, es);
                    }
                }
            }

            // ----------------------------
            // 5️⃣ Create Session Attendance (1 per request row)
            // ----------------------------
            List<Session_Attendance__c> sessionToInsert = new List<Session_Attendance__c>();
            // Keep track of which input index corresponds to which Session ID
            Map<Integer, Id> indexToSessionId = new Map<Integer, Id>(); 

            // We iterate all inputs to order the insert list
            for (Integer i = 0; i < inputList.size(); i++) {
                AttendanceRequestWrapper ar = inputList[i];
                
                CourseOffering offering = lmsIdToOfferingMap.get(ar.CourseOfferingId);
                
                if (offering == null) {
                    System.debug('Course Offering not found for LMS ID: ' + ar.CourseOfferingId);
                    // Add dummy to maintain index or handle offset. 
                    // To simplify, we'll store null and handle it in the next loop.
                    sessionToInsert.add(null); 
                    continue;
                }

                Session_Attendance__c s = new Session_Attendance__c(
                    Course_Offering__c = offering.Id,
                    Section__c = ar.Section,
                    Date__c = Date.valueOf(ar.SessionDate),
                    Time__c = ar.SessionTime,
                    Name = ar.SessionName
                );
                sessionToInsert.add(s);
            }

            // Filter out nulls for actual upsert
            List<Session_Attendance__c> actualUpsertList = new List<Session_Attendance__c>();
            Map<Integer, Integer> actualToOriginalIndexMatch = new Map<Integer, Integer>();

            for(Integer i=0; i<sessionToInsert.size(); i++) {
                if(sessionToInsert[i] != null) {
                    actualToOriginalIndexMatch.put(actualUpsertList.size(), i);
                    actualUpsertList.add(sessionToInsert[i]);
                }
            }

            // Bulkified Logic to find existing sessions (Avoiding SOQL in loop)
            Set<Id> courseOfferingIds = new Set<Id>();
            Set<String> sections = new Set<String>();
            Set<Date> dates = new Set<Date>();
            Set<String> times = new Set<String>();

            for(Session_Attendance__c sa : actualUpsertList) {
                courseOfferingIds.add(sa.Course_Offering__c);
                sections.add(sa.Section__c);
                dates.add(sa.Date__c);
                times.add(sa.Time__c);
            }

            Map<String, Session_Attendance__c> existingSessionsMap = new Map<String, Session_Attendance__c>();
            for(Session_Attendance__c existing : [
                SELECT Id, Course_Offering__c, Section__c, Date__c, Time__c 
                FROM Session_Attendance__c 
                WHERE Course_Offering__c IN :courseOfferingIds 
                AND Section__c IN :sections 
                AND Date__c IN :dates 
                AND Time__c IN :times
            ]) {
                String key = existing.Course_Offering__c + '-' + existing.Section__c + '-' + existing.Date__c + '-' + existing.Time__c;
                existingSessionsMap.put(key, existing);
            }

            for(Session_Attendance__c sa : actualUpsertList) {
                String key = sa.Course_Offering__c + '-' + sa.Section__c + '-' + sa.Date__c + '-' + sa.Time__c;
                if(existingSessionsMap.containsKey(key)) {
                    sa.Id = existingSessionsMap.get(key).Id;
                }
            }

            Database.UpsertResult[] sessionResults = Database.upsert(actualUpsertList, false);

            for (Integer i = 0; i < sessionResults.size(); i++) {
                if (sessionResults[i].isSuccess()) {
                    Integer originalIndex = actualToOriginalIndexMatch.get(i);
                    indexToSessionId.put(originalIndex, actualUpsertList[i].Id);
                } else {
                     System.debug('Failed to upsert Session Attendance: ' + sessionResults[i].getErrors()[0].getMessage());
                }
            }

            if (indexToSessionId.isEmpty()) {
                return new ResponseWrapper('ERROR', 'Failed to create any Session_Attendance__c records. Check LMS Course IDs.');
            }

            // ----------------------------
            // ----------------------------
            // 6️⃣ Create/Update Course_Attendance__c (Upsert logic)
            // ----------------------------
            List<Course_Attendance__c> attendanceToUpsert = new List<Course_Attendance__c>();
            
            // 1. Collect all Session IDs and Student PGIDs for bulk lookup
            Set<Id> sessionIds = new Set<Id>();
            Set<String> studentPgIds = new Set<String>();
            for (Id sid : indexToSessionId.values()) sessionIds.add(sid);
            for (AttendanceRequestWrapper ar : inputList) {
                if (ar.Students != null) {
                    for (StudentData stu : ar.Students) {
                        if (!String.isBlank(stu.StudentPGID)) studentPgIds.add(stu.StudentPGID);
                    }
                }
            }

            // 2. Query existing Course Attendance records for these sessions/students
            Map<String, Course_Attendance__c> existingCAMap = new Map<String, Course_Attendance__c>();
            if (!sessionIds.isEmpty() && !studentPgIds.isEmpty()) {
                for (Course_Attendance__c ca : [
                    SELECT Id, Session_Attendance__c, Student_PgId__c 
                    FROM Course_Attendance__c 
                    WHERE Session_Attendance__c IN :sessionIds 
                    AND Student_PgId__c IN :studentPgIds
                ]) {
                    String key = ca.Session_Attendance__c + '-' + ca.Student_PgId__c;
                    existingCAMap.put(key, ca);
                }
            }

            for (Integer i = 0; i < inputList.size(); i++) {
                if (!indexToSessionId.containsKey(i)) continue;

                AttendanceRequestWrapper ar = inputList[i];
                Id sessionId = indexToSessionId.get(i);
                CourseOffering offering = lmsIdToOfferingMap.get(ar.CourseOfferingId);

                if (ar.Students != null) {
                    for (StudentData stu : ar.Students) {
                         if (String.isBlank(stu.StudentPGID)) continue;
                         
                         ProgramEnrollment pe = peMap.get(stu.StudentPGID);
                         if (pe == null) continue;

                         Enrollment_Session__c es = peToES.get(pe.Id);
                         if (es == null) {
                             System.debug('Enrollment Session missing for ' + stu.StudentPGID + '. Skipping to avoid required field error.');
                             continue; 
                         }

                         Course_Attendance__c ca = new Course_Attendance__c(
                            Course_Offering__c = offering.Id,
                            Session_Attendance__c = sessionId,
                            Enrollment_Session__c = es.Id,
                            Program_Enrollment__c = pe.Id,
                            Contact__c = pe.ContactId,
                            Student_PgId__c = stu.StudentPGID,
                            Status__c = stu.Status
                        );

                        // Check if an existing record exists to perform an update
                        String caKey = sessionId + '-' + stu.StudentPGID;
                        if (existingCAMap.containsKey(caKey)) {
                            ca.Id = existingCAMap.get(caKey).Id;
                        }
                        
                        attendanceToUpsert.add(ca);
                    }
                }
            }

            if (!attendanceToUpsert.isEmpty()) {
                upsert attendanceToUpsert;
            }

            return new ResponseWrapper(
                'SUCCESS',
                'Attendance processing completed. Upserted ' +
                attendanceToUpsert.size() + ' Course_Attendance__c records.'
            );
        } catch (Exception e) {
            System.debug('Attendance Sync Error: ' + e.getMessage() + '\n' + e.getStackTraceString());
            return new ResponseWrapper('ERROR', e.getMessage());
        }
    }

    global class ResponseWrapper {
        public String status;
        public String message;
        public ResponseWrapper(String s, String m) {
            status = s;
            message = m;
        }
    }
    
    // Inner Classes for Request Parsing
    global class AttendanceRequestWrapper {
        public String CourseOfferingId;
        public String SessionDate;
        public String SessionTime;
        public String SessionName;
        public String Section;
        public List<StudentData> Students;
    }

    global class StudentData {
        public String StudentPGID;
        public String Status; 
    }
}