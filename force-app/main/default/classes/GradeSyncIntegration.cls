/*
    Sample JSON Request Body
{
    "Credits_Attempted__c": 3,                                   // Number(18, 0)
    "Credits_Earned__c": 3,                                      // Number(18, 0)
    "DurationUnit": "Credit Hours",                              // Picklist
   // "External_Key__c": "CRS-RES-2025-001",                     // Text(255)
    "Grade_Letter__c": "A",                                      // Picklist
    "LetterGrade": "A",                                          // Text(2)
    "Marks_Percentage__c": 95,                                   // Number(18, 0)
    "NumericGrade": 9.5,                                         // Number(5, 2)
    "Retake_Taken__c": false,                                    // Checkbox
    "Source_System__c": "LMS",                                   // Picklist
    "UnitsEarned": 3.0,                                          // Number(5, 2)  
    
    "StudentId" : "PGP1234",
    "CourseOfferingId" :"0P0720000001v13CAA"
  }
*/
@RestResource(urlMapping='/v1/gradesync')
global without sharing class GradeSyncIntegration {

    // Request Wrapper (Bulk)
    global class APIRequest {
        public String userid; 
        public String courseid;
        public Integer Credits_Earned;                                                            
        public String Grade_Letter;                                                                                                                
        public Decimal NumericGrade;                                                                
        public String Source_System;

        // Backward compatibility
        public String StudentId; 
        public String CourseOfferingId;
        public Integer Credits_Attempted;                   
        public String DurationUnit;                         
        public Integer Marks_Percentage;                    
        public Boolean Retake_Taken;                        
        public Decimal UnitsEarned; 
    }

    // Response Wrapper (Bulk status)
    global class ResultResponse {
        public Boolean success;
        public String message;
        public String recordId;
        public String externalId;
    }

    @HttpPost
    global static List<ResultResponse> upsertResult() {
        List<ResultResponse> results = new List<ResultResponse>();
        Set<String> userIdSet = new Set<String>();
        Set<String> courseIdSet = new Set<String>();
        Map<String, APIRequest> externalIdToRequest = new Map<String, APIRequest>();

        try {
            // Deserialize JSON input
            List<APIRequest> requests = (List<APIRequest>) JSON.deserialize(RestContext.request.requestBody.toString(), List<APIRequest>.class);
            if (requests == null || requests.isEmpty()) {
                throw new AuraHandledException('Request body cannot be empty.');
            }

            for (APIRequest req : requests) {
                // Prioritize new field names
                String uid = String.isNotBlank(req.userid) ? req.userid : req.StudentId;
                String cid = String.isNotBlank(req.courseid) ? req.courseid : req.CourseOfferingId;

                if (String.isBlank(uid) || String.isBlank(cid)) {
                    results.add(buildResult(false, 'Missing userid or courseid', null, uid + '#' + cid));
                    continue;
                }

                String extKey = uid + '#' + cid;
                externalIdToRequest.put(extKey, req);
                userIdSet.add(uid);
                courseIdSet.add(cid);
            }

            // 1. Resolve Students (Contacts)
            Map<String, Id> identifierToContactId = new Map<String, Id>();
            Set<Id> contactsMissingLmsId = new Set<Id>();

            List<Contact> contacts = [
                SELECT Id, LMS_External_ID__c, Email, New_Admit_Email__c 
                FROM Contact 
                WHERE LMS_External_ID__c IN :userIdSet 
                OR Email IN :userIdSet 
                OR New_Admit_Email__c IN :userIdSet
            ];
            
            for (Contact c : contacts) {
                if (String.isNotBlank(c.LMS_External_ID__c)) {
                    identifierToContactId.put(c.LMS_External_ID__c, c.Id);
                }
                
                // Map by email if the identifier used in request matches
                if (String.isNotBlank(c.Email)) {
                    String em = c.Email.toLowerCase();
                    if (userIdSet.contains(em)) {
                        identifierToContactId.put(em, c.Id);
                        if (String.isBlank(c.LMS_External_ID__c)) contactsMissingLmsId.add(c.Id);
                    }
                }
                if (String.isNotBlank(c.New_Admit_Email__c)) {
                    String em = c.New_Admit_Email__c.toLowerCase();
                    if (userIdSet.contains(em)) {
                        identifierToContactId.put(em, c.Id);
                        if (String.isBlank(c.LMS_External_ID__c)) contactsMissingLmsId.add(c.Id);
                    }
                }
            }

            // Fetch missing Moodle IDs from LMS endpoint if necessary
            if (!contactsMissingLmsId.isEmpty()) {
                Map<Id, String> fetchedIds = CourseOfferingParticipantLMSService.getMoodleUserIds(contactsMissingLmsId);
                for (Id cId : fetchedIds.keySet()) {
                    identifierToContactId.put(fetchedIds.get(cId), cId);
                }
            }

            Set<Id> contactIds = new Set<Id>(identifierToContactId.values());

            // 2. Query Participants and Existing Results in one go if possible, or separately
            Map<String, CourseOfferingParticipant> copMap = new Map<String, CourseOfferingParticipant>();
            if (!contactIds.isEmpty()) {
                for (CourseOfferingParticipant cop : [
                    SELECT Id, ParticipantContactId, CourseOffering.LMS_Course_Id__c 
                    FROM CourseOfferingParticipant 
                    WHERE ParticipantContactId IN :contactIds 
                    AND CourseOffering.LMS_Course_Id__c IN :courseIdSet
                ]) {
                    // Match back to the request identifier(s)
                    for (String uid : userIdSet) {
                        if (identifierToContactId.get(uid) == cop.ParticipantContactId) {
                            copMap.put(uid + '#' + cop.CourseOffering.LMS_Course_Id__c, cop);
                        }
                    }
                }
            }

            Set<Id> copIds = new Set<Id>();
            for(CourseOfferingParticipant cop : copMap.values()) copIds.add(cop.Id);

            Map<Id, CourseOfferingPtcpResult> copIdToResult = new Map<Id, CourseOfferingPtcpResult>();
            if (!copIds.isEmpty()) {
                for (CourseOfferingPtcpResult res : [
                    SELECT Id, CourseOfferingParticipantId, LetterGrade, NumericGrade,Source_System__c
                    FROM CourseOfferingPtcpResult 
                    WHERE CourseOfferingParticipantId IN :copIds
                ]) {
                    copIdToResult.put(res.CourseOfferingParticipantId, res);
                }
            }

            // 3. Prepare records for Upsert
            List<CourseOfferingPtcpResult> toUpsert = new List<CourseOfferingPtcpResult>();
            Map<Integer, String> indexToExtKey = new Map<Integer, String>();

            for (String extKey : externalIdToRequest.keySet()) {
                APIRequest req = externalIdToRequest.get(extKey);
                CourseOfferingParticipant cop = copMap.get(extKey);
                
                if (cop == null) {
                    results.add(buildResult(false, 'No Course Participant found for identifier: ' + extKey, null, extKey));
                    continue;
                }

                CourseOfferingPtcpResult copr = copIdToResult.get(cop.Id);
                if (copr == null) {
                    copr = new CourseOfferingPtcpResult();
                    copr.CourseOfferingParticipantId = cop.Id;
                }
                
                // Update fields from request - only LetterGrade and NumericGrade as per requirements
                copr.LetterGrade = req.Grade_Letter;
                copr.NumericGrade = req.NumericGrade;
                copr.Source_System__c = String.isNotBlank(req.Source_System) ? req.Source_System : 'LMS';

                indexToExtKey.put(toUpsert.size(), extKey);
                toUpsert.add(copr);
            }

            if (!toUpsert.isEmpty()) {
                Database.UpsertResult[] dmlResults = Database.upsert(toUpsert, false);
                for (Integer i = 0; i < dmlResults.size(); i++) {
                    Database.UpsertResult sr = dmlResults[i];
                    String extKey = indexToExtKey.get(i);
                    if (sr.isSuccess()) {
                        String msg = sr.isCreated() ? 'Created New Grade record: ' : 'Updated Grade record: ';
                        results.add(buildResult(true, msg + sr.getId(), sr.getId(), extKey));
                    } else {
                        results.add(buildResult(false, 'Error: ' + sr.getErrors()[0].getMessage(), null, extKey));
                    }
                }
            }

        } catch (Exception ex) {
            results.add(buildResult(false, 'Unexpected error: ' + ex.getMessage() + ' at ' + ex.getLineNumber(), null, null));
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