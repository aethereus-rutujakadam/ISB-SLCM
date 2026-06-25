public without sharing class DCRecordCreateController {

    private static final Set<String> TESTIMONY_TYPE_VALUES = new Set<String>{ 'Complainant', 'Respondent' };

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getProgramEnrollmentByPGID(String pgid) {
        if (String.isBlank(pgid)) {
            return null;
        }

        List<ProgramEnrollment> enrollments = [
            SELECT Id,
                   Name,
                   PGID__c,
                   ContactId,
                   Contact.Name,
                   Contact.New_Admit_Email__c,
                   Contact.MobilePhone,
                   ProgramId,
                   Program.Name,
                   Program.Program_Code__c,
                   Academic_Term__c,
                   Academic_Term__r.Name,
                   Academic_Year__c
            FROM ProgramEnrollment
            WHERE PGID__c = :pgid
              AND IsActive = true
            LIMIT 1
        ];

        if (enrollments.isEmpty()) {
            return null;
        }

        ProgramEnrollment pe = enrollments[0];
        return new Map<String, Object>{
            'enrollmentId' => pe.Id,
            'enrollmentName' => pe.Name,
            'pgid' => pe.PGID__c,
            'contactId' => pe.ContactId,
            'studentName' => pe.Contact != null ? pe.Contact.Name : null,
            'studentEmail' => pe.Contact != null ? pe.Contact.New_Admit_Email__c : null,
            'studentMobile' => pe.Contact != null ? pe.Contact.MobilePhone : null,
            'programId' => pe.ProgramId,
            'programName' => pe.Program != null ? pe.Program.Name : null,
            'programCode' => pe.Program != null ? pe.Program.Program_Code__c : null,
            'cohortId' => pe.Academic_Term__c,
            'cohortName' => pe.Academic_Term__r != null ? pe.Academic_Term__r.Name : null,
            'academicYearId' => pe.Academic_Year__c
        };
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getCohortOptions() {
        List<AcademicTerm> terms = [
            SELECT Id, Name 
            FROM AcademicTerm
            ORDER BY Name DESC 
            LIMIT 100
        ];
        
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (AcademicTerm t : terms) {
            result.add(new Map<String, Object>{
                'id' => t.Id,
                'name' => t.Name
            });
        }
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getTermOptions() {
        List<AcademicTerm> terms = [
            SELECT Id, Name 
            FROM AcademicTerm
            ORDER BY Name DESC 
            LIMIT 100
        ];
        
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (AcademicTerm t : terms) {
            result.add(new Map<String, Object>{
                'id' => t.Id,
                'name' => t.Name
            });
        }
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getTermOptionsByProgramAndCohort(String programId, String cohortId) {
        if (String.isBlank(programId) || String.isBlank(cohortId)) {
            return new List<Map<String, Object>>();
        }

        List<AcademicSession> sessions = [
            SELECT Id, Name
            FROM AcademicSession
            WHERE Program__c = :programId
              AND AcademicTermId = :cohortId
            ORDER BY Name ASC
        ];

        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (AcademicSession s : sessions) {
            result.add(new Map<String, Object>{
                'id' => s.Id,
                'name' => s.Name
            });
        }
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getStudentByPGID(String pgid) {
        if (String.isBlank(pgid)) {
            return null;
        }

        List<ProgramEnrollment> enrollments = [
            SELECT Id, ContactId, Contact.Name, Contact.MobilePhone, PGID__c
            FROM ProgramEnrollment
            WHERE PGID__c = :pgid
            LIMIT 1
        ];

        if (enrollments.isEmpty() || enrollments[0].ContactId == null) {
            return null;
        }

        ProgramEnrollment pe = enrollments[0];
        return new Map<String, Object>{
            'contactId' => pe.ContactId,
            'name' => pe.Contact != null ? pe.Contact.Name : null,
            'mobile' => pe.Contact != null ? pe.Contact.MobilePhone : null,
            'studentId' => pe.PGID__c
        };
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getStaffByEmail(String email) {
        if (String.isBlank(email)) {
            return null;
        }

        String normalized = email.trim();
        List<Contact> contacts = [
            SELECT Id, Name, MobilePhone, ISB_Email_ID__c, VF_Email_ID__c
            FROM Contact
            WHERE (ISB_Email_ID__c = :normalized OR VF_Email_ID__c = :normalized)
              AND RecordType.DeveloperName = 'Faculty'
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];

        if (contacts.isEmpty()) {
            return null;
        }

        Contact c = contacts[0];
        return new Map<String, Object>{
            'contactId' => c.Id,
            'name' => c.Name,
            'mobile' => c.MobilePhone,
            'email' => String.isNotBlank(c.ISB_Email_ID__c) ? c.ISB_Email_ID__c : c.VF_Email_ID__c
        };
    }

    @AuraEnabled
    public static Id createDCRecord(Map<String, Object> data) {
        Disciplinary_Committee__c rec = new Disciplinary_Committee__c();

        // Basic Information
        rec.Student_PG_ID__c = parseString(data.get('studentPgid'));
        rec.ProgramEnrollment__c = parseId(data.get('programEnrollmentId'));
        rec.Student_Staff_Name__c = parseId(data.get('studentContactId'));
        rec.Programme__c = parseId(data.get('programId'));
        rec.Cohort__c = parseId(data.get('cohortId'));
        rec.Term__c = parseId(data.get('termId'));
        rec.Status__c = parseString(data.get('status'));

        // Complaint Details
        rec.Complaint_details_Description__c = parseString(data.get('complaintDescription'));
        rec.Complaint_Received__c = parseDateTime(data.get('complaintReceived'));
        rec.Complaint_raised_by__c = parseString(data.get('complaintRaisedBy'));
        rec.Complaint_received_by_contact_info__c = parseString(data.get('complaintReceivedByContactInfo'));

        // Student Complaint Details (if complaint raised by student)
        if (parseString(data.get('complaintRaisedBy')) == 'Student') {
            rec.Complaint_raised_by_Student_ID__c = parseString(data.get('complaintStudentId'));
            rec.Student_Complaint__c = parseId(data.get('complaintStudentContactId'));
            rec.Mobile_Number_Student__c = parseString(data.get('complaintStudentMobile'));
        }

        // Staff Complaint Details (if complaint raised by staff)
        if (parseString(data.get('complaintRaisedBy')) == 'Staff') {
            rec.Complaint_raised_by_Staff_ID__c = parseString(data.get('complaintStaffEmail'));
            rec.Complaint_raised_by_Staff__c = parseId(data.get('complaintStaffContactId'));
            rec.Mobile_Number_Staff__c = parseString(data.get('complaintStaffMobile'));
        }

        // Show Cause Notice
        rec.Showcause_notice_sent_to_student__c = parseDate(data.get('showcauseNoticeSent'));
        rec.Student_response_to_showcause_notice__c = parseDate(data.get('studentResponseToShowcause'));

        // Committee Information
        rec.Disciplinary_committee_chair_email__c = parseString(data.get('committeeChairEmail'));
        rec.Disciplinary_Chair_Name__c = parseString(data.get('committeeChairName'));
        rec.Disciplinary_Committee_Meeting_Name__c = parseString(data.get('meetingName'));
        rec.Disciplinary_Committee_Meeting_date__c = parseDate(data.get('meetingDate'));
        rec.Participants_of_the_Meeting__c = parseString(data.get('meetingParticipants'));
        rec.Students_involved__c = parseString(data.get('studentsInvolved'));
        rec.Duration_of_Meeting_hours__c = parseDecimal(data.get('meetingDuration'));

        // Decision & Outcome
        rec.Number_of_sittings__c = parseDecimal(data.get('numberOfSittings'));
        rec.Final_hearing_Date__c = parseDate(data.get('finalHearingDate'));
        rec.Final_outcome__c = parseString(data.get('finalOutcome'));
        rec.Action_taken_shared_with_student_date__c = parseDate(data.get('actionSharedDate'));
        rec.Action_Taken_Description__c = parseString(data.get('actionTakenDescription'));

        // Appeal
        rec.Dean_Appeal_Date__c = parseDate(data.get('deanAppealDate'));
        rec.Dean_Appeal_Grounds__c = parseString(data.get('deanAppealGrounds'));
        rec.Dean_Decision__c = parseString(data.get('deanDecision'));
        rec.Final_Penalty__c = parseString(data.get('finalPenalty'));

        // Build testimonies
        List<DC_Meeting_Testimony__c> testimonies = buildTestimonyRecords(data.get('testimonies'), data.get('testimoniesJson'));

        insert rec;

        if (!testimonies.isEmpty()) {
            for (DC_Meeting_Testimony__c t : testimonies) {
                t.Disciplinary_Committee__c = rec.Id;
            }
            insert testimonies;
        }

        return rec.Id;
    }

    private static List<DC_Meeting_Testimony__c> buildTestimonyRecords(Object testimoniesObj, Object testimoniesJsonObj) {
        List<DC_Meeting_Testimony__c> records = new List<DC_Meeting_Testimony__c>();
        List<Object> testimonyItems = normalizeTestimonyItems(testimoniesObj, testimoniesJsonObj);
        
        if (testimonyItems.isEmpty()) {
            return records;
        }

        for (Object item : testimonyItems) {
            Map<String, Object> t = coerceToStringObjectMap(item);
            if (t == null) {
                continue;
            }

            String type = parseString(t.get('type'));
            if (String.isBlank(type) || !TESTIMONY_TYPE_VALUES.contains(type)) {
                continue;
            }

            DC_Meeting_Testimony__c testimony = new DC_Meeting_Testimony__c();
            testimony.Testimony_Type__c = type;
            testimony.MOM__c = parseString(t.get('mom'));
            testimony.Recording_URL__c = parseString(t.get('recordingUrl'));

            records.add(testimony);
        }

        return records;
    }

    private static List<Object> normalizeTestimonyItems(Object testimoniesObj, Object testimoniesJsonObj) {
        // Try direct list first
        if (testimoniesObj instanceof List<Object>) {
            return (List<Object>) testimoniesObj;
        }

        // Try JSON string
        if (testimoniesJsonObj != null) {
            String jsonStr = String.valueOf(testimoniesJsonObj);
            if (String.isNotBlank(jsonStr)) {
                try {
                    Object parsed = JSON.deserializeUntyped(jsonStr);
                    if (parsed instanceof List<Object>) {
                        return (List<Object>) parsed;
                    }
                } catch (Exception e) {
                    System.debug(LoggingLevel.WARN, 'Failed to parse testimoniesJson: ' + e.getMessage());
                }
            }
        }

        return new List<Object>();
    }

    private static Map<String, Object> coerceToStringObjectMap(Object item) {
        if (item == null) {
            return null;
        }
        if (item instanceof Map<String, Object>) {
            return (Map<String, Object>) item;
        }
        try {
            Object parsed = JSON.deserializeUntyped(JSON.serialize(item));
            if (parsed instanceof Map<String, Object>) {
                return (Map<String, Object>) parsed;
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Unable to normalize testimony item: ' + e.getMessage());
        }
        return null;
    }

    private static String parseString(Object val) {
        if (val == null) {
            return null;
        }
        String s = String.valueOf(val);
        return String.isBlank(s) ? null : s;
    }

    private static Id parseId(Object val) {
        if (val == null || val == '') {
            return null;
        }
        try {
            return Id.valueOf(String.valueOf(val));
        } catch (Exception e) {
            return null;
        }
    }

    private static Date parseDate(Object val) {
        if (val == null || val == '') {
            return null;
        }
        try {
            return Date.valueOf(String.valueOf(val));
        } catch (Exception e) {
            return null;
        }
    }

    private static Datetime parseDateTime(Object val) {
        if (val == null || val == '') {
            return null;
        }
        String raw = String.valueOf(val).trim();
        if (String.isBlank(raw)) {
            return null;
        }
        try {
            if (raw.contains('T')) {
                return Datetime.valueOfGmt(raw.replace('T', ' ').replace('Z', ''));
            }
            return Datetime.valueOf(raw);
        } catch (Exception e) {
            return null;
        }
    }

    private static Decimal parseDecimal(Object val) {
        if (val == null || val == '') {
            return null;
        }
        try {
            return Decimal.valueOf(String.valueOf(val));
        } catch (Exception e) {
            return null;
        }
    }
}