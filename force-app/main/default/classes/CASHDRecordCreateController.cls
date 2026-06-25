public without sharing class CASHDRecordCreateController {

    private static final Set<String> PARTY_ROLE_VALUES = new Set<String>{ 'Complainant', 'Respondent' };
    private static final Set<String> PARTY_TYPE_VALUES = new Set<String>{ 'Student', 'Staff', 'Alumni', 'Others' };

    @AuraEnabled(cacheable=true)
    public static List<CourseOffering> searchCourseOfferings(Id programId, Id academicYearId) {
        return [
            SELECT Id, Name, LearningCourse.Name, Program__c, Academic_Year__c
            FROM CourseOffering
            WHERE Program__c = :programId
              AND Academic_Year__c = :academicYearId
            ORDER BY LearningCourse.Name, Name
            LIMIT 50
        ];
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getProgramEnrollmentByPGID(String pgid) {
        if (String.isBlank(pgid)) {
            return null;
        }

        List<ProgramEnrollment> enrollments = [
            SELECT Id,
                   Name,
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
        return new Map<String, Object>{
            'enrollmentId' => pe.Id,
            'enrollmentName' => pe.Name,
            'contactId' => pe.ContactId,
            'studentName' => pe.Contact != null ? pe.Contact.Name : null,
            'studentEmail' => pe.Contact != null ? pe.Contact.New_Admit_Email__c : null,
            'studentMobile' => pe.Contact != null ? pe.Contact.MobilePhone : null,
            'programId' => pe.ProgramId,
            'programName' => pe.Program != null ? pe.Program.Name : null,
            'programCode' => pe.Program != null ? pe.Program.Program_Code__c : null,
            'academicYearId' => pe.Academic_Year__c,
            'academicYearName' => pe.Academic_Year__r != null ? pe.Academic_Year__r.Name : null,
            'currentReportingLocationId' => pe.Location__c,
            'currentReportingLocationName' => pe.Location__r != null ? pe.Location__r.Name : null
        };
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getContactByEmail(String email) {
        if (String.isBlank(email)) {
            return null;
        }

        String normalized = email.trim();
        List<Contact> contacts = [
            SELECT Id, Name, Email, VF_Email_ID__c
            FROM Contact
            WHERE Email = :normalized OR VF_Email_ID__c = :normalized
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];

        if (contacts.isEmpty()) {
            return null;
        }

        Contact c = contacts[0];
        return new Map<String, Object>{
            'id' => c.Id,
            'name' => c.Name,
            'email' => String.isBlank(c.Email) ? c.VF_Email_ID__c : c.Email
        };
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getContactByStudentId(String studentId) {
        if (String.isBlank(studentId)) {
            return null;
        }

        List<ProgramEnrollment> enrollments = [
            SELECT Id, ContactId, Contact.Name, Contact.New_Admit_Email__c, PGID__c
            FROM ProgramEnrollment
            WHERE PGID__c = :studentId
            LIMIT 1
        ];

        if (enrollments.isEmpty() || enrollments[0].ContactId == null) {
            return null;
        }

        ProgramEnrollment pe = enrollments[0];
        return new Map<String, Object>{
            'contactId' => pe.ContactId,
            'name' => pe.Contact != null ? pe.Contact.Name : null,
            'email' => pe.Contact != null ? pe.Contact.New_Admit_Email__c : null,
            'studentId' => pe.PGID__c
        };
    }

    @AuraEnabled
    public static Id createCASHDRecord(Map<String, Object> data) {
        CASHD_Committee__c rec = new CASHD_Committee__c();

        rec.Subject__c = parseString(data.get('subject'));
        rec.Date_of_Complaint_Receipt__c = parseDateTime(data.get('dateOfComplaintReceipt'));
        rec.Case_Status__c = parseString(data.get('caseStatus'));
        rec.Course__c = parseId(data.get('courseOfferingId'));
        rec.CaseAttachmentsURL__c = parseString(data.get('caseAttachmentsUrl'));

        rec.Student_PG_ID_Text__c = parseString(data.get('studentPgid'));
        rec.Student_PG_ID__c = parseId(data.get('studentProgramEnrollmentId'));
        rec.Student_Name__c = parseId(data.get('studentContactId'));
        rec.Student_Email__c = parseString(data.get('studentEmail'));
        rec.Mobile_Number__c = parseString(data.get('studentMobile'));

        rec.Program_Enrollment__c = parseId(data.get('programEnrollmentId'));
        rec.Programme__c = parseId(data.get('programId'));
        rec.Program_Code__c = parseString(data.get('programCode'));
        rec.Academic_Year__c = parseId(data.get('academicYearId'));
        rec.Current_Reporting_Location__c = parseId(data.get('currentReportingLocationId'));

        rec.Committee_Member_1_Name__c = parseString(data.get('committeeMember1Name'));
        rec.Committee_Member_2_Name__c = parseString(data.get('committeeMember2Name'));
        rec.Committee_Member_3_Name__c = parseString(data.get('committeeMember3Name'));
        rec.Committee_Member_4_Name__c = parseString(data.get('committeeMember4Name'));
        rec.Committee_Member_5_Name__c = parseString(data.get('committeeMember5Name'));
        rec.Other_Commitee_Members_Name__c = parseString(data.get('otherCommitteeMembersName'));
        rec.External_Consultant_Email__c = parseString(data.get('externalConsultantEmail'));

        rec.Lead_convenor__c = parseString(data.get('leadConvenor'));
        rec.Members_attended__c = parseString(data.get('membersAttended'));
        rec.MOM__c = parseString(data.get('mom'));
        rec.Meeting_Recording_URL__c = parseString(data.get('meetingRecordingUrl'));
        rec.Number_of_Meetings_Held__c = parseDecimal(data.get('numberOfMeetingsHeld'));

        rec.Action__c = parseString(data.get('action'));

        rec.Final_hearing_Date__c = parseDate(data.get('finalHearingDate'));
        rec.FinalOutcome__c = parseString(data.get('finalOutcome'));
        rec.Action_Taken_Description__c = parseString(data.get('actionTakenDescription'));
        rec.Action_taken_shared_with_student_date__c = parseDate(data.get('actionTakenSharedDate'));
        rec.Final_Penalty__c = parseString(data.get('finalPenalty'));
        rec.Dean_Appeal_Date__c = parseDate(data.get('deanAppealDate'));
        rec.Dean_Appeal_Grounds__c = parseString(data.get('deanAppealGrounds'));
        rec.Dean_Decision__c = parseString(data.get('deanDecision'));
        rec.Submission_date_to_Dean_Office__c = parseDate(data.get('submissionDateToDeanOffice'));

        List<CASHD_Committee_Party__c> parties = buildPartyRecords(data.get('parties'), data.get('partiesJson'), data.get('partyJson'));

        insert rec;

        if (!parties.isEmpty()) {
            for (CASHD_Committee_Party__c p : parties) {
                p.CASHD_Committee__c = rec.Id;
            }
            try {
                insert parties;
            } catch (DmlException e) {
                if (isContactLookupCrossRefError(e)) {
                    // Fallback: keep Contact lookup blank and still save parties.
                    for (CASHD_Committee_Party__c p : parties) {
                        if (p.Party_Type__c != 'Student') {
                            p.Contact__c = null;
                        }
                    }
                    insert parties;
                } else {
                    throw new AuraHandledException(e.getDmlMessage(0));
                }
            }
        }

        return rec.Id;
    }

    private static List<CASHD_Committee_Party__c> buildPartyRecords(Object partiesObj, Object partiesJsonObj, Object partyJsonAliasObj) {
        List<CASHD_Committee_Party__c> records = new List<CASHD_Committee_Party__c>();
        Set<String> nonStudentEmails = new Set<String>();
        List<Object> partyItems = normalizePartyItems(partiesObj, partiesJsonObj, partyJsonAliasObj);
        if (partyItems.isEmpty()) {
            throw new AuraHandledException('At least one party is required.');
        }

        Boolean hasComplainant = false;
        Boolean hasRespondent = false;

        for (Object item : partyItems) {
            Map<String, Object> p = coerceToStringObjectMap(item);
            if (p == null) {
                continue;
            }

            String role = parseString(p.get('role'));
            String type = parseString(p.get('type'));
            if (String.isBlank(role) || String.isBlank(type)) {
                throw new AuraHandledException('Each party row must include Role and Type.');
            }
            if (!PARTY_ROLE_VALUES.contains(role)) {
                throw new AuraHandledException('Invalid party role value: ' + role);
            }
            if (!PARTY_TYPE_VALUES.contains(type)) {
                throw new AuraHandledException('Invalid party type value: ' + type);
            }

            if (role == 'Complainant') {
                hasComplainant = true;
            }
            if (role == 'Respondent') {
                hasRespondent = true;
            }

            String studentId = parseString(p.get('studentId'));
            String email = parseString(p.get('email'));
            if (type == 'Student' && String.isBlank(studentId)) {
                throw new AuraHandledException('Student party rows require Student ID.');
            }
            if (type != 'Student' && String.isBlank(email)) {
                throw new AuraHandledException('Staff/Alumni/Others party rows require Email.');
            }

            CASHD_Committee_Party__c row = new CASHD_Committee_Party__c();
            row.Party_Role__c = role;
            row.Party_Type__c = type;
            row.Student_Id__c = studentId;
            row.Email__c = email;
            row.Contact__c = parseId(p.get('contactId'));
            if (row.Party_Type__c != 'Student' && row.Contact__c == null && !String.isBlank(row.Email__c)) {
                nonStudentEmails.add(row.Email__c.trim());
            }
            row.NDA_Signed_Date__c = parseDateTime(p.get('ndaSignedDate'));
            records.add(row);
        }

        if (!nonStudentEmails.isEmpty()) {
            Map<String, Id> emailToContact = getContactIdsByEmail(nonStudentEmails);
            for (CASHD_Committee_Party__c row : records) {
                if (row.Party_Type__c == 'Student' || row.Contact__c != null || String.isBlank(row.Email__c)) {
                    continue;
                }
                String emailKey = row.Email__c.trim();
                row.Contact__c = emailToContact.get(emailKey);
                if (row.Contact__c == null) {
                    row.Contact__c = emailToContact.get(emailKey.toLowerCase());
                }
            }
        }

        if (records.isEmpty()) {
            throw new AuraHandledException('At least one party is required.');
        }
        if (!hasComplainant || !hasRespondent) {
            throw new AuraHandledException('Add at least one Complainant and one Respondent party.');
        }

        return records;
    }

    private static List<Object> normalizePartyItems(Object partiesObj, Object partiesJsonObj, Object partyJsonAliasObj) {
        if (partiesObj instanceof List<Object>) {
            return (List<Object>) partiesObj;
        }
        String jsonPayload = parseString(partiesJsonObj);
        if (String.isBlank(jsonPayload)) {
            jsonPayload = parseString(partyJsonAliasObj);
        }
        if (!String.isBlank(jsonPayload)) {
            try {
                Object parsed = JSON.deserializeUntyped(jsonPayload);
                if (parsed instanceof List<Object>) {
                    return (List<Object>) parsed;
                }
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'Unable to parse partiesJson payload: ' + e.getMessage());
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
        if (item instanceof Map<Object, Object>) {
            Map<String, Object> normalized = new Map<String, Object>();
            Map<Object, Object> rawMap = (Map<Object, Object>) item;
            for (Object key : rawMap.keySet()) {
                normalized.put(String.valueOf(key), rawMap.get(key));
            }
            return normalized;
        }
        try {
            Object parsed = JSON.deserializeUntyped(JSON.serialize(item));
            if (parsed instanceof Map<String, Object>) {
                return (Map<String, Object>) parsed;
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Unable to normalize party item: ' + e.getMessage());
        }
        return null;
    }

    private static Map<String, Id> getContactIdsByEmail(Set<String> normalizedEmails) {
        Map<String, Id> emailToContact = new Map<String, Id>();
        if (normalizedEmails == null || normalizedEmails.isEmpty()) {
            return emailToContact;
        }

        for (Contact c : [
            SELECT Id, Email, VF_Email_ID__c
            FROM Contact
            WHERE Email IN :normalizedEmails OR VF_Email_ID__c IN :normalizedEmails
            ORDER BY LastModifiedDate DESC
        ]) {
            if (!String.isBlank(c.Email)) {
                String key = c.Email.trim();
                if (!emailToContact.containsKey(key)) {
                    emailToContact.put(key, c.Id);
                }
                String lowerKey = key.toLowerCase();
                if (!emailToContact.containsKey(lowerKey)) {
                    emailToContact.put(lowerKey, c.Id);
                }
            }
            if (!String.isBlank(c.VF_Email_ID__c)) {
                String key = c.VF_Email_ID__c.trim();
                if (!emailToContact.containsKey(key)) {
                    emailToContact.put(key, c.Id);
                }
                String lowerKey = key.toLowerCase();
                if (!emailToContact.containsKey(lowerKey)) {
                    emailToContact.put(lowerKey, c.Id);
                }
            }
        }

        return emailToContact;
    }

    private static Boolean isContactLookupCrossRefError(DmlException e) {
        if (e == null) {
            return false;
        }
        String msg = e.getMessage();
        String firstMsg = e.getNumDml() > 0 ? e.getDmlMessage(0) : null;
        String combined = ((msg == null ? '' : msg) + ' ' + (firstMsg == null ? '' : firstMsg)).toLowerCase();
        return combined.contains('insufficient access rights on cross-reference id')
            || combined.contains('field integrity exception');
    }



    private static String parseString(Object val) {
        if (val == null) {
            return null;
        }
        String s = String.valueOf(val);
        return String.isBlank(s) ? null : s;
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
        raw = raw.replace('T', ' ').replace('Z', '');
        Integer dotIndex = raw.indexOf('.');
        if (dotIndex > 0) {
            raw = raw.substring(0, dotIndex);
        }
        if (raw.length() == 16) {
            raw += ':00';
        }
        try {
            return Datetime.valueOf(raw);
        } catch (Exception e) {
            try {
                return Datetime.valueOfGmt(raw);
            } catch (Exception ignored) {
                return null;
            }
        }
    }

    private static Id parseId(Object val) {
        if (val == null) {
            return null;
        }
        String s = String.valueOf(val);
        if (String.isBlank(s)) {
            return null;
        }
        try {
            return (Id) s;
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