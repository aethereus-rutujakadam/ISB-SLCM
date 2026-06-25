/*
    Sample JSON Request Body
    [
        {
            "pgid" : "PGP1234",
            "user_id" :"123",
            "term_id" : "2",
            "term_name" :  "term 1",
            "academic_year" : "2025-2026",
            "gpa" : 4.2,
            "cgpa" : 5.2,
            "cum_credits" : 10,
            "cum_grade_points" : 14,
            "core_cgpa" : 3.5
        }
    ]
*/
@RestResource(urlMapping='/v1/cgpa_gpa_sync')
global with sharing class CGPA_GPA_SyncIntegration {

    // Request Wrapper
    global class APIRequest {
        public String pgid;
        public String user_id;
        public String term_id;
        public String term_name;
        public String academic_year;
        public Decimal gpa;
        public Decimal cgpa;
        public Decimal cum_credits;
        public Decimal cum_grade_points;
        public Decimal core_cgpa;
    }

    // Response Wrapper
    global class ResultResponse {
        public Boolean success;
        public String message;
        public String recordId;
        public String externalId;
    }

    @HttpPost
    global static List<ResultResponse> updateResult() {
        List<ResultResponse> results = new List<ResultResponse>();
        Map<String, APIRequest> externalKeyToRequest = new Map<String, APIRequest>();
        Set<String> pgidSet = new Set<String>();
        Set<String> userIdSet = new Set<String>();
        Set<String> termIdSet = new Set<String>();
        Set<String> termNameSet = new Set<String>();
        Set<String> academicYearSet = new Set<String>();

        try {
            // Deserialize JSON input
            String jsonBody = RestContext.request.requestBody.toString();
            List<APIRequest> requests = (List<APIRequest>) JSON.deserialize(jsonBody, List<APIRequest>.class);

            if (requests == null || requests.isEmpty()) {
                throw new AuraHandledException('Request body cannot be empty.');
            }

            // Collect keys for bulk processing
            for (APIRequest req : requests) {
                // External key for response tracking
                String extKey = (String.isNotBlank(req.pgid) ? req.pgid : req.user_id) + '#' + (String.isNotBlank(req.term_id) ? req.term_id : req.term_name);
                externalKeyToRequest.put(extKey, req);
                
                if (String.isNotBlank(req.pgid)) pgidSet.add(req.pgid);
                if (String.isNotBlank(req.user_id)) userIdSet.add(req.user_id);
                if (String.isNotBlank(req.term_id)) termIdSet.add(req.term_id);
                if (String.isNotBlank(req.term_name)) termNameSet.add(req.term_name);
                if (String.isNotBlank(req.academic_year)) academicYearSet.add(req.academic_year);
            }

            // 1. Resolve Contacts if pgid is missing (User ID fallback logic)
            Map<String, Id> identifierToContactId = new Map<String, Id>();
            if (!userIdSet.isEmpty()) {
                List<Contact> contacts = [
                    SELECT Id, LMS_External_ID__c, Email, New_Admit_Email__c 
                    FROM Contact 
                    WHERE LMS_External_ID__c IN :userIdSet 
                    OR Email IN :userIdSet 
                    OR New_Admit_Email__c IN :userIdSet
                ];
                
                Set<Id> contactsMissingLmsId = new Set<Id>();
                for (Contact c : contacts) {
                    if (String.isNotBlank(c.LMS_External_ID__c)) {
                        identifierToContactId.put(c.LMS_External_ID__c, c.Id);
                    }
                    if (String.isNotBlank(c.Email) && userIdSet.contains(c.Email.toLowerCase())) {
                        identifierToContactId.put(c.Email.toLowerCase(), c.Id);
                        if (String.isBlank(c.LMS_External_ID__c)) contactsMissingLmsId.add(c.Id);
                    }
                    if (String.isNotBlank(c.New_Admit_Email__c) && userIdSet.contains(c.New_Admit_Email__c.toLowerCase())) {
                        identifierToContactId.put(c.New_Admit_Email__c.toLowerCase(), c.Id);
                        if (String.isBlank(c.LMS_External_ID__c)) contactsMissingLmsId.add(c.Id);
                    }
                }
                
                // Fallback to fetch missing Moodle IDs from LMS
                if (!contactsMissingLmsId.isEmpty()) {
                    Map<Id, String> fetchedIds = CourseOfferingParticipantLMSService.getMoodleUserIds(contactsMissingLmsId);
                    for (Id cId : fetchedIds.keySet()) {
                        identifierToContactId.put(fetchedIds.get(cId), cId);
                    }
                }
            }

            // 2. Query Program Enrollments
            Map<String, ProgramEnrollment> peMap = new Map<String, ProgramEnrollment>();
            List<ProgramEnrollment> pes = [
                SELECT Id, PGID__c, ContactId 
                FROM ProgramEnrollment 
                WHERE PGID__c IN :pgidSet 
                OR ContactId IN :identifierToContactId.values()
            ];
            
            for (ProgramEnrollment pe : pes) {
                if (String.isNotBlank(pe.PGID__c)) {
                    peMap.put(pe.PGID__c, pe);
                }
                // Also map by contact ID if found via user_id
                for (String uid : identifierToContactId.keySet()) {
                    if (identifierToContactId.get(uid) == pe.ContactId) {
                        peMap.put(uid, pe);
                    }
                }
            }

            // 3. Query all Enrollment Sessions for these Program Enrollments
            Set<Id> peIds = new Set<Id>();
            for (ProgramEnrollment pe : peMap.values()) peIds.add(pe.Id);

            Map<Id, List<Enrollment_Session__c>> peToESListMap = new Map<Id, List<Enrollment_Session__c>>();
            if (!peIds.isEmpty()) {
                List<Enrollment_Session__c> allES = [
                    SELECT Id, Program_Enrollment__c, Academic_Session__c, Academic_Session__r.Name, Academic_Session__r.ISB_External_Id__c 
                    FROM Enrollment_Session__c 
                    WHERE Program_Enrollment__c IN :peIds
                ];
                for (Enrollment_Session__c es : allES) {
                    if (!peToESListMap.containsKey(es.Program_Enrollment__c)) {
                        peToESListMap.put(es.Program_Enrollment__c, new List<Enrollment_Session__c>());
                    }
                    peToESListMap.get(es.Program_Enrollment__c).add(es);
                }
            }

            // 4. Build update lists
            Map<Id, ProgramEnrollment> peToUpdate = new Map<Id, ProgramEnrollment>();
            List<Enrollment_Session__c> esToUpdate = new List<Enrollment_Session__c>();
            Map<Integer, String> esIndexToExtKey = new Map<Integer, String>();

            for (String extKey : externalKeyToRequest.keySet()) {
                APIRequest req = externalKeyToRequest.get(extKey);
                ProgramEnrollment pe = String.isNotBlank(req.pgid) ? peMap.get(req.pgid) : peMap.get(req.user_id);
                
                if (pe == null) {
                    results.add(buildResult(false, 'Program Enrollment not found for identifier used', null, extKey));
                    continue;
                }

                // Map to new LMS fields on Program Enrollment
                ProgramEnrollment peUpd = peToUpdate.containsKey(pe.Id) ? peToUpdate.get(pe.Id) : new ProgramEnrollment(Id = pe.Id);
                peUpd.LMS_GPA__c = req.gpa;
                peUpd.LMS_CGPA__c = req.cgpa;
                peUpd.LMS_Cum_Credits__c = req.cum_credits;
                peUpd.LMS_Grade_Points__c = req.cum_grade_points;
                peUpd.LMS_Core_CGPA__c = req.core_cgpa;
                peToUpdate.put(pe.Id, peUpd);

                // Find matching Enrollment Session
                Enrollment_Session__c matchedES = null;
                if (peToESListMap.containsKey(pe.Id)) {
                    for (Enrollment_Session__c es : peToESListMap.get(pe.Id)) {
                        Boolean matchFound = false;
                        
                        // 1. Try matching by term_id (External ID)
                        if (String.isNotBlank(req.term_id) && es.Academic_Session__r.ISB_External_Id__c == req.term_id) {
                            matchFound = true;
                        }
                        
                        // 2. Try matching by term_name (Name contains)
                        if (!matchFound && String.isNotBlank(req.term_name) && es.Academic_Session__r.Name != null) {
                            String sessionName = es.Academic_Session__r.Name.toLowerCase();
                            String targetTerm = req.term_name.toLowerCase();
                            if (sessionName.contains(targetTerm)) {
                                matchFound = true;
                            }
                        }
                        
                        if (matchFound) {
                            matchedES = es;
                            break;
                        }
                    }
                }

                if (matchedES != null) {
                    Enrollment_Session__c esUpd = new Enrollment_Session__c(
                        Id = matchedES.Id, 
                        LMS_GPA__c = req.gpa
                    );
                    esIndexToExtKey.put(esToUpdate.size(), extKey);
                    esToUpdate.add(esUpd);
                } else {
                    results.add(buildResult(false, 'Enrollment Session not found for term: ' + (req.term_name != null ? req.term_name : req.term_id), null, extKey));
                }
            }

            // Perform DML Updates
            if (!peToUpdate.isEmpty()) {
                Database.update(peToUpdate.values(), false);
            }
            
            if (!esToUpdate.isEmpty()) {
                Database.SaveResult[] srList = Database.update(esToUpdate, false);
                for (Integer i = 0; i < srList.size(); i++) {
                    Database.SaveResult sr = srList[i];
                    String extKey = esIndexToExtKey.get(i);
                    if (sr.isSuccess()) {
                        results.add(buildResult(true, 'Updated successfully', sr.getId(), extKey));
                    } else {
                        results.add(buildResult(false, 'Update failed: ' + sr.getErrors()[0].getMessage(), null, extKey));
                    }
                }
            }


        } catch (Exception ex) {
            results.add(buildResult(false, 'Unexpected error: ' + ex.getMessage(), null, null));
        }

        return results;
    }

    // Helper method to generate result entries
    private static ResultResponse buildResult(Boolean success, String message, String recordId, String externalId) {
        ResultResponse res = new ResultResponse();
        res.success = success;
        res.message = message;
        res.recordId = recordId;
        res.externalId = externalId;
        return res;
    }
}