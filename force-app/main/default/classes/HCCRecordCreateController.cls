public without sharing class HCCRecordCreateController {

    @AuraEnabled(cacheable=true)
    public static List<Program> searchPrograms(String searchTerm) {
        String term = '%' + String.escapeSingleQuotes(searchTerm) + '%';
        return [SELECT Id, Name FROM Program WHERE Name LIKE :term ORDER BY Name LIMIT 20];
    }

    @AuraEnabled(cacheable=true)
    public static List<AcademicYear> searchAcademicYears(String searchTerm) {
        String term = '%' + String.escapeSingleQuotes(searchTerm) + '%';
        return [SELECT Id, Name FROM AcademicYear WHERE Name LIKE :term ORDER BY Name LIMIT 20];
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> searchLocations(String searchTerm) {
        String term = '%' + String.escapeSingleQuotes(searchTerm == null ? '' : searchTerm) + '%';
        List<Map<String, Object>> results = new List<Map<String, Object>>();
        for (SObject record : [SELECT Id, Name FROM Location WHERE Name LIKE :term ORDER BY Name LIMIT 20]) {
            results.add(new Map<String, Object>{
                'id' => record.get('Id'),
                'name' => record.get('Name')
            });
        }
        return results;
    }

    @AuraEnabled(cacheable=true)
    public static List<AcademicSession> searchAcademicSessions(String searchTerm, String programId) {
        String term = '%' + String.escapeSingleQuotes(searchTerm == null ? '' : searchTerm) + '%';
        if (String.isBlank(programId)) {
            return new List<AcademicSession>();
        }

        Set<Id> sessionIds = new Set<Id>();
        for (CourseOffering co : [
            SELECT AcademicSessionId
            FROM CourseOffering
            WHERE Program__c = :programId
              AND AcademicSessionId != null
            LIMIT 2000
        ]) {
            sessionIds.add(co.AcademicSessionId);
        }

        if (sessionIds.isEmpty()) {
            return new List<AcademicSession>();
        }

        return [
            SELECT Id, Name
            FROM AcademicSession
            WHERE Id IN :sessionIds
              AND Name LIKE :term
            ORDER BY Name
            LIMIT 20
        ];
    }

    @AuraEnabled
    public static List<CourseOffering> searchCourseOfferings(String searchTerm, String programId, String sessionId) {
        String term = '%' + String.escapeSingleQuotes(searchTerm == null ? '' : searchTerm) + '%';
        if (String.isBlank(programId) || String.isBlank(sessionId)) {
            return new List<CourseOffering>();
        }
        return [
            SELECT Id, Name, LearningCourse.Name
            FROM CourseOffering
            WHERE Program__c = :programId
              AND AcademicSessionId = :sessionId
              AND Name LIKE :term
            ORDER BY Name
            LIMIT 50
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<Contact> searchFacultiesByCourseOffering(String searchTerm, String courseOfferingId) {
        String term = '%' + String.escapeSingleQuotes(searchTerm == null ? '' : searchTerm) + '%';
        if (String.isBlank(courseOfferingId)) {
            return new List<Contact>();
        }

        Set<Id> facultyIds = new Set<Id>();
        for (Course_Faculty__c cf : [
            SELECT Faculty__c
            FROM Course_Faculty__c
            WHERE Course_Offering__c = :courseOfferingId
              AND Faculty__c != null
            LIMIT 500
        ]) {
            facultyIds.add(cf.Faculty__c);
        }

        if (facultyIds.isEmpty()) {
            return new List<Contact>();
        }

        return [
            SELECT Id, Name, Email
            FROM Contact
            WHERE Id IN :facultyIds
              AND (Name LIKE :term OR Email LIKE :term)
            ORDER BY Name
            LIMIT 50
        ];
    }

    @AuraEnabled
    public static Map<String, Object> getProgramEnrollmentByPGID(String pgid) {
        if (String.isBlank(pgid)) {
            return null;
        }
        List<ProgramEnrollment> enrollments = [
            SELECT Id,
                   ContactId,
                   Contact.Name,
                   Contact.New_Admit_Email__c,
                   Contact.MobilePhone,
                   ProgramId,
                   Program.Name,
                   Program.Program_Code__c,
                   Academic_Year__c,
                   Academic_Year__r.Name,
                   Location__c,
                   Location__r.Name
            FROM ProgramEnrollment
            WHERE PGID__c = :pgid
              AND IsActive = true
            LIMIT 1
        ];
        if (enrollments.isEmpty()) {
            return null;
        }
        ProgramEnrollment pe = enrollments[0];
        Map<String, Object> result = new Map<String, Object>{
            'enrollmentId'              => pe.Id,
            'contactId'                 => pe.ContactId,
            'studentName'               => pe.Contact.Name,
            'studentEmail'              => pe.Contact.New_Admit_Email__c,
            'studentMobile'             => pe.Contact.MobilePhone,
            'programId'                 => pe.ProgramId,
            'programName'               => pe.Program != null ? pe.Program.Name : null,
            'programCode'               => pe.Program != null ? pe.Program.Program_Code__c : null,
            'academicYearId'            => pe.Academic_Year__c,
            'academicYearName'          => pe.Academic_Year__r != null ? pe.Academic_Year__r.Name : null,
            'currentReportingLocationId'   => pe.Location__c,
            'currentReportingLocationName' => pe.Location__r != null ? pe.Location__r.Name : null
        };
        return result;
    }

    @AuraEnabled
    public static Map<String, Object> getContactByEmail(String email) {
        if (String.isBlank(email)) {
            return null;
        }
        List<Contact> contacts = [SELECT Id, Name FROM Contact WHERE Email = :email LIMIT 1];
        if (contacts.isEmpty()) return null;
        return new Map<String, Object>{ 'id' => contacts[0].Id, 'name' => contacts[0].Name };
    }

    @AuraEnabled
    public static Id createHCCRecord(Map<String, Object> data) {
        Honour_Code_Committee__c rec = new Honour_Code_Committee__c();

        rec.Academic_Terms_Session__c        = parseId(data.get('academicSessionId'));
        rec.Academic_Year__c                 = parseId(data.get('academicYearId'));
        rec.Appeal_Remarks__c                = (String) data.get('appealRemarks');
        rec.Case_Closed_Date__c              = parseDate(data.get('caseClosedDate'));
        rec.Case_Reported_Date__c            = parseDate(data.get('caseReportedDate'));
        rec.Chair_Decision__c                = (String) data.get('chairDecision');
        rec.Chair__c                         = parseId(data.get('chairId'));
        rec.Committee_Decision__c            = (String) data.get('committeeDecision');
        rec.Component_Name__c                = (String) data.get('componentName');
        rec.Convener__c                      = (String) data.get('convenerEmail');
        rec.Course_Penalty__c                = (String) data.get('coursePenalty');
        rec.Course__c                        = parseId(data.get('courseOfferingId'));
        rec.Current_Reporting_Location__c    = parseId(data.get('currentReportingLocationId'));
        rec.Dean_Appeal_Date__c              = parseDate(data.get('deanAppealDate'));
        rec.Dean_Appeal_Grounds__c           = (String) data.get('deanAppealGrounds');
        rec.Dean_Decision__c                 = (String) data.get('deanDecision');
        rec.Decision_Notification_Date__c    = parseDate(data.get('decisionNotificationDateToStudent'));
        rec.Decision_Reason__c               = (String) data.get('decisionReason');
        rec.Email_IDs_Faculty_Members__c     = (String) data.get('emailIdsFacultyMembers');
        rec.Email_IDs_Student_Members__c     = (String) data.get('emailIdsStudentMembers');
        rec.Email_Sent_to_Committee__c       = parseBool(data.get('emailSentToCommittee'));
        rec.Faculty__c                       = parseId(data.get('reportedFaculty'));
        rec.Final_Penalty__c                 = (String) data.get('finalPenalty');
        rec.Final_communication_Outcome__c   = (String) data.get('finalCommunicationOutcome');
        rec.HCC_Chair_Email__c               = (String) data.get('hccChairISBEmail');
        rec.Hearing_Attendance__c            = (String) data.get('hearingAttendance');
        rec.Hearing_Date__c                  = parseDateTime(data.get('hearingDate'));
        rec.Hearing_Status__c                = (String) data.get('hearingStatus');
        rec.Initial_Evidence__c              = (String) data.get('initialEvidence');
        rec.Mobile_Number__c                 = (String) data.get('studentMobile');
        rec.Outcome_Email_Date__c            = parseDate(data.get('outcomeEmailDate'));
        rec.Penalty_Details__c               = (String) data.get('penaltyDetails');
        rec.Penalty_Enforced__c              = parseBool(data.get('penaltyEnforced'));
        rec.Penalty_Type__c                  = (String) data.get('penaltyType');
        rec.Previous_Violation_Date__c       = parseDate(data.get('previousViolationFoundGuiltyDate'));
        rec.Programme__c                     = parseId(data.get('programId'));
        rec.Recording__c                     = (String) data.get('recordingUrl');
        rec.Response_Deadline__c             = parseDate(data.get('responseDeadline'));
        rec.Response_To_Charges__c           = (String) data.get('responseToCharges');
        rec.Statement_Request_Date__c        = parseDate(data.get('statementRequestDate'));
        rec.Student_Email__c                 = (String) data.get('studentEmail');
        rec.Student_PE_ID__c                 = parseId(data.get('enrollmentId'));
        rec.Student_PG_ID__c                 = (String) data.get('pgid');
        rec.Student__c                       = parseId(data.get('contactId'));
        rec.Submission_Date__c               = parseDate(data.get('submissionDate'));

        Object turnitin = data.get('turnitinSimilarity');
        if (turnitin != null && turnitin != '') {
            rec.Turnitin_Similarity__c = Decimal.valueOf(String.valueOf(turnitin));
        }

        rec.Violation_Type__c                = (String) data.get('violationType');
        rec.Vote_Result__c                   = (String) data.get('voteResult');

        insert rec;
        return rec.Id;
    }

    // ── Private helpers ──────────────────────────────────────────────────────

    private static Date parseDate(Object val) {
        if (val == null || val == '') return null;
        try {
            return Date.valueOf(String.valueOf(val));
        } catch (Exception e) {
            return null;
        }
    }

    private static Datetime parseDateTime(Object val) {
        if (val == null || val == '') return null;
        try {
            return Datetime.valueOf(String.valueOf(val).replace('T', ' '));
        } catch (Exception e) {
            return null;
        }
    }

    private static Boolean parseBool(Object val) {
        if (val == null) return false;
        if (val instanceof Boolean) return (Boolean) val;
        return String.valueOf(val).equalsIgnoreCase('true');
    }

    private static Id parseId(Object val) {
        if (val == null) return null;
        String s = String.valueOf(val);
        return String.isBlank(s) ? null : (Id) s;
    }
}