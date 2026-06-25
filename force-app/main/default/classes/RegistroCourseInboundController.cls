/**
 * RegistroCourseInboundController
 * ISB-6090 / ISB-6141 — REST endpoint that receives course confirmation data from Registro
 * for Incoming Exchange students (INT-02).
 *
 * Endpoint: POST /services/apexrest/registro/courses/incoming
 */
@RestResource(urlMapping='/registro/courses/incoming')
global with sharing class RegistroCourseInboundController {

    // ── Response wrapper ──────────────────────────────────────────────────
    global class CourseResponse {
        public Boolean success;
        public String  message;
        public List<CourseResult> results;
        public CourseResponse(Boolean success, String message, List<CourseResult> results) {
            this.success = success; this.message = message; this.results = results;
        }
    }

    global class CourseResult {
        public String  courseCode;
        public Boolean processed;
        public String  message;
        public CourseResult(String courseCode, Boolean processed, String message) {
            this.courseCode = courseCode; this.processed = processed; this.message = message;
        }
    }

    // ── Course payload item ────────────────────────────────────────────────
    global class CourseItem {
        public String  pgid;
        public String  courseCode;
        public String  courseName;
        public Decimal contactHours;
        public Decimal credits;
        public Decimal isbCredits;
    }

    // ── POST handler ──────────────────────────────────────────────────────
    @HttpPost
    global static CourseResponse handlePost() {
        RestRequest  req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        String requestBody = req.requestBody.toString();
        List<CourseResult> results = new List<CourseResult>();

        try {
            List<CourseItem> items = (List<CourseItem>) JSON.deserialize(requestBody, List<CourseItem>.class);

            if (items == null || items.isEmpty()) {
                res.statusCode = 400;
                return new CourseResponse(false, 'Request body is empty or not valid JSON array.', null);
            }

            // Gather all PGIDs and CourseCodes to resolve IDs in bulk
            Set<String> pgids = new Set<String>();
            Set<String> courseCodes = new Set<String>();
            for (CourseItem ci : items) {
                if (String.isNotBlank(ci.pgid)) pgids.add(ci.pgid);
                if (String.isNotBlank(ci.courseCode)) courseCodes.add(ci.courseCode);
            }
            
            Map<String, Id> pgidToContactId = resolveContacts(pgids);
            Map<String, Id> courseCodeToOfferingId = resolveCourseOfferings(courseCodes);

            for (CourseItem ci : items) {
                results.add(processCourseItem(ci, pgidToContactId, courseCodeToOfferingId));
            }

            res.statusCode = 200;
            return new CourseResponse(true, 'Processed ' + items.size() + ' course item(s).', results);

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'RegistroCourseInboundController error: ' + e.getMessage());
            res.statusCode = 500;
            return new CourseResponse(false, 'Internal server error: ' + e.getMessage(), null);
        }
    }

    // ── Process one course item ───────────────────────────────────────────
    private static CourseResult processCourseItem(CourseItem ci, Map<String, Id> pgidToContactId, Map<String, Id> courseCodeToOfferingId) {
        if (String.isBlank(ci.pgid)) {
            return new CourseResult(ci.courseCode, false, 'PGID is required.');
        }
        if (String.isBlank(ci.courseCode)) {
            return new CourseResult(ci.courseCode, false, 'Course Code is required.');
        }

        Id contactId = pgidToContactId.get(ci.pgid);
        if (contactId == null) {
            return new CourseResult(ci.courseCode, false, 'No Contact found with PGID: ' + ci.pgid);
        }

        Id offeringId = courseCodeToOfferingId.get(ci.courseCode);
        if (offeringId == null) {
            return new CourseResult(ci.courseCode, false, 'No CourseOffering found with Course Code: ' + ci.courseCode + '. Cannot create participant record without an offering.');
        }

        try {
            // Dedupe check: find existing CourseOfferingParticipant for same Contact + CourseOffering
            List<CourseOfferingParticipant> existing = [
                SELECT Id, Status__c, LMS_Sync_Status__c
                FROM   CourseOfferingParticipant
                WHERE  ParticipantContactId = :contactId
                  AND  CourseOfferingId     = :offeringId
                LIMIT  1
            ];

            if (!existing.isEmpty()) {
                CourseOfferingParticipant cop = existing[0];
                return new CourseResult(ci.courseCode, true, 'Updated existing course participant record.');
            } else {
                // Create new CourseOfferingParticipant linking Contact to the CourseOffering
                CourseOfferingParticipant cop = new CourseOfferingParticipant(
                    ParticipantContactId = contactId,
                    CourseOfferingId   = offeringId,
                    Status__c          = 'Registered',
                    LMS_Sync_Status__c = 'Pending'
                );
                insert cop;
                return new CourseResult(ci.courseCode, true, 'Created new course participant record.');
            }
        } catch (Exception e) {
            return new CourseResult(ci.courseCode, false, 'DML error: ' + e.getMessage());
        }
    }

    // ── Resolve PGID → Contact Id (bulk) ─────────────────────────────────
    private static Map<String, Id> resolveContacts(Set<String> pgids) {
        Map<String, Id> result = new Map<String, Id>();
        if (pgids.isEmpty()) return result;
        for (ProgramEnrollment pe : [
            SELECT PGID__c, ContactId
            FROM   ProgramEnrollment
            WHERE  PGID__c IN :pgids
              AND  Sub_Status__c = 'Incoming Exchange'
        ]) {
            result.put(pe.PGID__c, pe.ContactId);
        }
        return result;
    }
    
    // ── Resolve CourseCode → CourseOffering Id (bulk) ────────────────────
    private static Map<String, Id> resolveCourseOfferings(Set<String> courseCodes) {
        Map<String, Id> result = new Map<String, Id>();
        if (courseCodes.isEmpty()) return result;
        for (CourseOffering co : [
            SELECT Id, Course_Code__c
            FROM   CourseOffering
            WHERE  Course_Code__c IN :courseCodes
        ]) {
            result.put(co.Course_Code__c, co.Id);
        }
        return result;
    }
}
