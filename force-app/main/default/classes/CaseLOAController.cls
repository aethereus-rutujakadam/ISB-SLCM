/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 12-31-2025
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
public without sharing class CaseLOAController {

@AuraEnabled(cacheable=true)
public static UserAccountContactInfo getUserAccountContact() {
    try {
        User currentUser = [
            SELECT Id, ContactId, 
                    Contact.AccountId, Contact.Account.Name, 
                    Contact.Email, Contact.Phone, Contact.Name,
                    Contact.MailingStreet, Contact.MailingCity, Contact.MailingState,
                    Contact.MailingPostalCode, Contact.MailingCountry
            FROM User 
            WHERE Id = :UserInfo.getUserId() 
            LIMIT 1
        ];

        if (currentUser.ContactId == null) {
            throw new AuraHandledException('No Contact associated with this user. Please contact your administrator.');
        }

        // Get Program Enrollment PGID for the contact
        List<ProgramEnrollment> programEnrollments = [
            SELECT Id, PGID__c, Status, isActive, Academic_Year__r.Name, Academic_Term__c 
            FROM ProgramEnrollment 
            WHERE ContactId = :currentUser.ContactId 
            AND Status = 'Registered'
            AND isActive = true
            LIMIT 1
        ];

        UserAccountContactInfo info = new UserAccountContactInfo();
        info.contactId = currentUser.ContactId;
        info.accountId = currentUser.Contact.AccountId;
        info.accountName = currentUser.Contact.Account != null ? currentUser.Contact.Account.Name : '';
        info.email = currentUser.Contact.Email;
        info.phone = currentUser.Contact.Phone;
        info.contactName = currentUser.Contact.Name;
        info.mailingStreet = currentUser.Contact.MailingStreet;
        info.mailingCity = currentUser.Contact.MailingCity;
        info.mailingState = currentUser.Contact.MailingState;
        info.mailingPostalCode = currentUser.Contact.MailingPostalCode;
        info.mailingCountry = currentUser.Contact.MailingCountry;
        
        // Add PGID if available
        if (!programEnrollments.isEmpty()) {
            info.pgid = programEnrollments[0].PGID__c;
            info.academicYear = programEnrollments[0].Academic_Year__r.Name;
            info.currentAcademicTerm = programEnrollments[0].Academic_Term__c;
        } else {
            info.pgid = null;
        }
       
        return info;

    } catch (Exception e) {
        throw new AuraHandledException('Error retrieving user account contact info: ' + e.getMessage());
    }
}

@AuraEnabled(cacheable=true)
public static List<AcademicYear> getAcademicYears() {
    try {
        return [SELECT Id, Name FROM AcademicYear ORDER BY Name];
    } catch (Exception e) {
        throw new AuraHandledException('Error fetching academic years: ' + e.getMessage());
    }
}

@AuraEnabled(cacheable=true)
public static List<sObject> getLocation() {
    try {
        return [SELECT Id, Name FROM Location ORDER BY Name LIMIT 100];
    } catch (Exception e) { 
        throw new AuraHandledException('Error fetching locations: ' + e.getMessage());
    }
}


@AuraEnabled(cacheable=true)
public static List<PicklistValue> getLOATypeValues() {
    try {
        List<PicklistValue> picklistValues = new List<PicklistValue>();
        
        Schema.DescribeFieldResult fieldResult = Case.LOA_Type__c.getDescribe();
        List<Schema.PicklistEntry> picklistEntries = fieldResult.getPicklistValues();
        
        for (Schema.PicklistEntry entry : picklistEntries) {
            if (entry.isActive()) {
                PicklistValue pv = new PicklistValue();
                pv.label = entry.getLabel();
                pv.value = entry.getValue();
                picklistValues.add(pv);
            }
        }
        
        return picklistValues;
    } catch (Exception e) {
        throw new AuraHandledException('Error fetching LOA Type values: ' + e.getMessage());
    }
}

@AuraEnabled(cacheable=true)
public static List<PicklistValue> getAttendanceExceptionReasonValues() {
    try {
        List<PicklistValue> picklistValues = new List<PicklistValue>();
        
        Schema.DescribeFieldResult fieldResult = Case.Attendance_Exception_Reason__c.getDescribe();
        List<Schema.PicklistEntry> picklistEntries = fieldResult.getPicklistValues();
        
        for (Schema.PicklistEntry entry : picklistEntries) {
            if (entry.isActive()) {
                PicklistValue pv = new PicklistValue();
                pv.label = entry.getLabel();
                pv.value = entry.getValue();
                picklistValues.add(pv);
            }
        }
        
        return picklistValues;
    } catch (Exception e) {
        throw new AuraHandledException('Error fetching Attendance Exception Reason values: ' + e.getMessage());
    }
}
//sid

@AuraEnabled
public static UserAccountContactInfo getUserAccountContactByEmail(String email) {
    if (email != null) email = email.trim();
    return new GuestHelper().getUserAccountContactByEmail(email);
}

@AuraEnabled(cacheable=true)
public static List<ProgramWrapper> getUserProgramsByEmail(String email) {
    return new GuestHelper().getUserProgramsByEmail(email);
}

@AuraEnabled
public static List<Case> getContactCases(String contactId) {
    return new GuestHelper().getContactCases(contactId);
}

@AuraEnabled(cacheable=true)
public static List<Case> getOpenCasesByEmail(String email) {
    return new GuestHelper().getOpenCasesByEmail(email);
}

@AuraEnabled(cacheable=true)
public static List<ProgramWrapper> getRejoinEligibleProgramsByEmail(String email) {
    return new GuestHelper().getRejoinEligibleProgramsByEmail(email);
}

@AuraEnabled(cacheable=true)
public static List<AcademicSessionWrapper> getAcademicSessionsByProgramByEmail(String programId, String email) {
    return new GuestHelper().getAcademicSessionsByProgramByEmail(programId, email);
}

@AuraEnabled(cacheable=true)
public static List<ReturnReplaceCaseWrapper> getReturnReplaceCasesByEmail(String email) {
    return new GuestHelper().getReturnReplaceCasesByEmail(email);
}

@AuraEnabled(cacheable=true)
public static List<CourseWrapper> getUserCoursesByAcademicSessionsByEmail(String fromTermId, String toTermId, String programId, String email) {
    return new GuestHelper().getUserCoursesByAcademicSessionsByEmail(fromTermId, toTermId, programId, email);
}

@AuraEnabled(cacheable=true)
public static List<RejoinCaseWrapper> getRejoinCasesByEmail(String email) {
    return new GuestHelper().getRejoinCasesByEmail(email);
}

//Sid
// Inner class to handle Guest user queries without sharing
private without sharing class GuestHelper {
    public UserAccountContactInfo getUserAccountContactByEmail(String email) {
        try {
            if (String.isBlank(email)) {
                throw new AuraHandledException('Email is required');
            }
            System.debug('CaseLOAController: getUserAccountContactByEmail called with email: ' + email);

            Contact userContact = [
                SELECT Id, AccountId, Account.Name, Email, Phone, Name,
                       MailingStreet, MailingCity, MailingState, MailingPostalCode, MailingCountry
                FROM Contact 
                WHERE Email = :email 
                LIMIT 1
            ];
            
            System.debug('CaseLOAController: Found contact: ' + userContact.Id);

            // Get Program Enrollment PGID for the contact - relaxing filters slightly to ensure we find it
            List<ProgramEnrollment> programEnrollments = [
                SELECT Id, PGID__c, Status, isActive, Academic_Year__r.Name, Academic_Term__c 
                FROM ProgramEnrollment 
                WHERE ContactId = :userContact.Id
                AND (Status = 'Registered' OR Status = 'Active')
                ORDER BY isActive DESC, CreatedDate DESC
                LIMIT 1
            ];
            
            System.debug('CaseLOAController: Found ' + programEnrollments.size() + ' program enrollments');

            UserAccountContactInfo info = new UserAccountContactInfo();
            info.contactId = userContact.Id;
            info.accountId = userContact.AccountId;
            info.accountName = userContact.Account != null ? userContact.Account.Name : '';
            info.email = userContact.Email;
            info.phone = userContact.Phone;
            info.contactName = userContact.Name;
            info.mailingStreet = userContact.MailingStreet;
            info.mailingCity = userContact.MailingCity;
            info.mailingState = userContact.MailingState;
            info.mailingPostalCode = userContact.MailingPostalCode;
            info.mailingCountry = userContact.MailingCountry;
            
            // Add PGID if available
            if (!programEnrollments.isEmpty()) {
                info.pgid = programEnrollments[0].PGID__c;
                info.academicYear = programEnrollments[0].Academic_Year__r != null ? programEnrollments[0].Academic_Year__r.Name : '';
                info.currentAcademicTerm = programEnrollments[0].Academic_Term__c;
                System.debug('CaseLOAController: Populated PGID: ' + info.pgid + ', Academic Year: ' + info.academicYear);
            } else {
                info.pgid = null;
                info.academicYear = '';
                System.debug('CaseLOAController: No program enrollment found for PGID/Academic Year');
            }
           
            return info;
        } catch (Exception e) {
            System.debug('CaseLOAController error: ' + e.getMessage() + ' at ' + e.getStackTraceString());
            throw new AuraHandledException('Error retrieving contact info by email: ' + e.getMessage());
        }
    }

    public List<ProgramWrapper> getUserProgramsByEmail(String email) {
        try {
             if (String.isBlank(email)) {
                throw new AuraHandledException('Email is required');
            }

            Contact userContact = [SELECT Id FROM Contact WHERE Email = :email LIMIT 1];

            List<ProgramEnrollment> enrollments = [
                SELECT Id, ProgramId, Program.Name, Status, Academic_Term__c, Sub_Status__c
                FROM ProgramEnrollment 
                WHERE ContactId = :userContact.Id
                AND (status = 'Registered' OR status = 'Active')
                AND ProgramId != null
            ];

            List<ProgramWrapper> programs = new List<ProgramWrapper>();
            for (ProgramEnrollment pe : enrollments) {
                if (pe.Program != null && pe.Program.Name != null) {
                    ProgramWrapper wrapper = new ProgramWrapper(pe.ProgramId, pe.Program.Name);
                    wrapper.academicTermName = pe.Academic_Term__c; // Populate term name
                    // wrapper.programId is already set by constructor
                    programs.add(wrapper);
                }
            }

            return programs;
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching programs by email: ' + e.getMessage());
        }
    }

    public List<Case> getContactCases(String contactId) {
        try {
            if (String.isBlank(contactId)) {
                throw new AuraHandledException('Contact ID is required');
            }

            return [
                SELECT Id, CaseNumber, Subject, Status, CreatedDate, RecordType.Name, 
                       LOA_Type__c, Program__r.Name, Description
                FROM Case 
                WHERE ContactId = :contactId 
                ORDER BY CreatedDate DESC
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching contact cases: ' + e.getMessage());
        }
    }
    public List<Case> getOpenCasesByEmail(String email) {
        try {
            if (String.isBlank(email)) {
                return new List<Case>();
            }
            Contact userContact = [SELECT Id FROM Contact WHERE Email = :email LIMIT 1];
            return [
                SELECT Id, CaseNumber, Subject, Status, CreatedDate, RecordTypeId
                FROM Case 
                WHERE ContactId = :userContact.Id 
                AND IsClosed = false
                ORDER BY CreatedDate DESC
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching open cases by email: ' + e.getMessage());
        }
    }

    public List<ProgramWrapper> getRejoinEligibleProgramsByEmail(String email) {
        try {
            if (String.isBlank(email)) {
                return new List<ProgramWrapper>();
            }
            Contact userContact = [SELECT Id FROM Contact WHERE Email = :email LIMIT 1];
            
            List<ProgramEnrollment> enrollments = [
                SELECT Id, ProgramId, Program.Name, Status, Sub_Status__c, Sub_Sub_Status__c
                FROM ProgramEnrollment 
                WHERE ContactId = :userContact.Id
                AND Status = 'On Hold'
                AND Sub_Sub_Status__c = 'Leave of Absence'
                AND ProgramId != null
            ];

            List<ProgramWrapper> programs = new List<ProgramWrapper>();
            for (ProgramEnrollment pe : enrollments) {
                if (pe.Program != null && pe.Program.Name != null) {
                    programs.add(new ProgramWrapper(pe.ProgramId, pe.Program.Name));
                }
            }
            return programs;
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching rejoin programs by email: ' + e.getMessage());
        }
    }

    public List<AcademicSessionWrapper> getAcademicSessionsByProgramByEmail(String programId, String email) {
        try {
            if (String.isBlank(programId) || String.isBlank(email)) {
                return new List<AcademicSessionWrapper>();
            }

            // Resolve contact by email
            Contact userContact = [SELECT Id FROM Contact WHERE Email = :email LIMIT 1];

            // Fetch Enrollment_Session__c records where this contact is registered
            // Assigned_Contact__c is the real Contact lookup on Enrollment_Session__c
            // List<Enrollment_Session__c> enrollmentSessions = [
            //     SELECT Academic_Session__c, Academic_Session__r.Name
            //     FROM Enrollment_Session__c
            //     WHERE Assigned_Contact__c = :userContact.Id
            //     AND (Status__c = 'Registered' OR Status__c = 'Active')
            //     AND Academic_Session__c != null
            //     ORDER BY Academic_Session__r.Name
            // ];

            // Deduplicate by AcademicSession Id
            // Map<Id, AcademicSessionWrapper> sessionMap = new Map<Id, AcademicSessionWrapper>();
            // for (Enrollment_Session__c es : enrollmentSessions) {
            //     if (!sessionMap.containsKey(es.Academic_Session__c)) {
            //         sessionMap.put(es.Academic_Session__c,
            //             new AcademicSessionWrapper(es.Academic_Session__c, es.Academic_Session__r.Name));
            //     }
            // }
            // return sessionMap.values();

            // OLD LOGIC - via ProgramEnrollment → AcademicTerm → AcademicSession
            List<ProgramEnrollment> enrollments = [
                SELECT Id, Academic_Term__c
                FROM ProgramEnrollment
                WHERE ContactId = :userContact.Id
                AND status = 'Registered'
                AND ProgramId = :programId
            ];
            
            Set<Id> academicTermIds = new Set<Id>();
            for (ProgramEnrollment pe : enrollments) {
                if (pe.Academic_Term__c != null) {
                    academicTermIds.add(pe.Academic_Term__c);
                }
            }
            
            if (academicTermIds.isEmpty()) { 
                return new List<AcademicSessionWrapper>(); 
            }
            
            List<AcademicTerm> academicTerms = [
                SELECT Id FROM AcademicTerm WHERE Id IN :academicTermIds
            ];
            
            if (academicTerms.isEmpty()) { 
                return new List<AcademicSessionWrapper>(); 
            }
            
            List<AcademicSession> sessions = [
                SELECT Id, Name, AcademicTermId FROM AcademicSession
                WHERE AcademicTermId IN :academicTerms ORDER BY Name
            ];
            
            List<AcademicSessionWrapper> sessionList = new List<AcademicSessionWrapper>();
            for (AcademicSession session : sessions) {
                sessionList.add(new AcademicSessionWrapper(session.Id, session.Name));
            }
            
            System.debug('Found ' + sessionList.size() + ' academic sessions using ProgramEnrollment logic');
            return sessionList;
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching academic sessions by email: ' + e.getMessage());
        }
    }

    public List<ReturnReplaceCaseWrapper> getReturnReplaceCasesByEmail(String email) {
        try {
            if (String.isBlank(email)) {
                 return new List<ReturnReplaceCaseWrapper>();
            }
            Contact userContact = [SELECT Id FROM Contact WHERE Email = :email LIMIT 1];
            
            List<Case> returnReplaceCases = [
                SELECT Id, CaseNumber, LOA_Type__c, Program__r.Name, 
                       From_Term__c, To_Term__c, Subject, CreatedDate, Status
                FROM Case 
                WHERE ContactId = :userContact.Id 
                AND RecordType.Name = 'Leave of Absence'
                AND Status = 'Closed'
                AND LOA_Type__c != null
                AND Program__r.Name != null
                ORDER BY CreatedDate DESC
            ];

            List<ReturnReplaceCaseWrapper> wrappedCases = new List<ReturnReplaceCaseWrapper>();
            for (Case c : returnReplaceCases) {
                ReturnReplaceCaseWrapper wrapper = new ReturnReplaceCaseWrapper();
                wrapper.caseId = c.Id;
                wrapper.caseNumber = c.CaseNumber;
                String displayLabel = '';
                if (c.LOA_Type__c != null) displayLabel += c.LOA_Type__c;
                if (c.Program__r != null && c.Program__r.Name != null) displayLabel += ' - ' + c.Program__r.Name;
                if (c.From_Term__c != null) displayLabel += ' - ' + c.From_Term__c;
                if (c.To_Term__c != null) displayLabel += ' - ' + c.To_Term__c;
                wrapper.displayLabel = displayLabel;
                wrapper.loaType = c.LOA_Type__c;
                wrapper.programName = c.Program__r != null ? c.Program__r.Name : '';
                wrapper.fromTerm = c.From_Term__c;
                wrapper.toTerm = c.To_Term__c;
                wrapper.subject = c.Subject;
                wrapper.status = c.Status;
                wrappedCases.add(wrapper);
            }
            return wrappedCases;
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching return replace cases by email: ' + e.getMessage());
        }
    }

    public List<CourseWrapper> getUserCoursesByAcademicSessionsByEmail(String fromTermId, String toTermId, String programId, String email) {
        try {
             if (String.isBlank(email)) {
                return new List<CourseWrapper>();
            }
            Contact userContact = [SELECT Id FROM Contact WHERE Email = :email LIMIT 1];
            
            Set<String> termIds = new Set<String>();
            if (String.isNotBlank(fromTermId)) termIds.add(fromTermId);
            if (String.isNotBlank(toTermId)) termIds.add(toTermId);

            // OLD LOGIC - via CourseOfferingParticipant
            // List<CourseOfferingParticipant> participants = [
            //     SELECT Id, Name, CourseOfferingId, CourseOffering.LearningCourse.Name,
            //             CourseOffering.Academic_Term__c, CourseOffering.AcademicSession.Name,
            //             CourseOffering.AcademicSessionId, ParticipationStatus
            //     FROM CourseOfferingParticipant 
            //     WHERE ParticipantContactId = :userContact.Id
            //     AND CourseOffering.AcademicSessionId IN :termIds
            //     AND CourseOfferingId != null
            //     AND ParticipationStatus = 'Enrolled'
            //     AND CourseOffering.Program__c = :programId
            //     ORDER BY CourseOffering.AcademicSession.Name, CourseOffering.LearningCourse.Name
            // ];
            
            // List<CourseWrapper> courses = new List<CourseWrapper>();
            // for (CourseOfferingParticipant cop : participants) {
            //     if (cop.CourseOffering != null && cop.CourseOffering.LearningCourse != null && cop.CourseOffering.LearningCourse.Name != null) {
            //         CourseWrapper course = new CourseWrapper();
            //         course.courseOfferingParticipantId = cop.Id;
            //         course.courseOfferingId = cop.CourseOfferingId;
            //         course.learningCourseName = cop.CourseOffering.LearningCourse.Name;
            //         course.academicTermName = cop.CourseOffering.AcademicSession?.Name;
            //         course.academicSessionId = cop.CourseOffering.AcademicSessionId;
            //         course.participationStatus = cop.ParticipationStatus;
            //         courses.add(course);
            //     }
            // }
            // return courses;

            List<CourseOffering> offerings = [
                SELECT Id, 
                       LearningCourse.Name,
                       Academic_Term__c, 
                       AcademicSession.Name,
                       AcademicSessionId
                FROM CourseOffering 
                WHERE AcademicSessionId IN :termIds
                AND Program__c = :programId
                AND IsActive = true
                ORDER BY AcademicSession.Name, LearningCourse.Name
            ];

            List<CourseWrapper> courses = new List<CourseWrapper>();
            for (CourseOffering co : offerings) {
                if (co.LearningCourse != null && co.LearningCourse.Name != null) {
                    CourseWrapper course = new CourseWrapper();
                    course.courseOfferingParticipantId = ''; // Not applicable when querying CourseOffering directly
                    course.courseOfferingId = co.Id;
                    course.learningCourseName = co.LearningCourse.Name;
                    course.academicTermName = co.AcademicSession?.Name;
                    course.academicSessionId = co.AcademicSessionId;
                    //course.participationStatus = 'Not Enrolled';
                    courses.add(course);
                }
            }
            return courses;
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching user courses by email: ' + e.getMessage());
        }
    }

    public List<RejoinCaseWrapper> getRejoinCasesByEmail(String email) {
        system.debug('email' +email);
        try {
            if (String.isBlank(email)) {
                return new List<RejoinCaseWrapper>();
            }
            Contact userContact = [SELECT Id FROM Contact WHERE Email = :email LIMIT 1];

            List<Case> rejoinCases = [
                SELECT Id, CaseNumber, LOA_Type__c, Program__r.Name, 
                       From_Term__c, To_Term__c, Subject, CreatedDate, Status,
                       Completed_Term__c, Program__c
                FROM Case 
                WHERE ContactId = :userContact.Id 
                AND RecordType.Name = 'Leave of Absence'
                AND Status = 'Closed'
                AND Program__r.Name != null
                ORDER BY CreatedDate DESC
            ];
            
            List<RejoinCaseWrapper> wrappedCases = new List<RejoinCaseWrapper>();
            for (Case c : rejoinCases) {
                RejoinCaseWrapper wrapper = new RejoinCaseWrapper();
                wrapper.caseId = c.Id;
                wrapper.caseNumber = c.CaseNumber;
                String displayLabel = '';
                if (c.LOA_Type__c != null) displayLabel += c.LOA_Type__c;
                if (c.Program__r != null && c.Program__r.Name != null) displayLabel += ' - ' + c.Program__r.Name;
                if (c.From_Term__c != null) displayLabel += ' - ' + c.From_Term__c;
                if (c.To_Term__c != null) displayLabel += ' - ' + c.To_Term__c;
                wrapper.displayLabel = displayLabel;
                wrapper.loaType = c.LOA_Type__c;
                wrapper.programName = c.Program__r != null ? c.Program__r.Name : '';
                wrapper.fromTerm = c.From_Term__c;
                wrapper.toTerm = c.To_Term__c;
                wrapper.subject = c.Subject;
                wrappedCases.add(wrapper);
            }
            return wrappedCases;
        } catch (Exception e) {
            system.debug('Error>>> '+ e.getMessage() + e.getLineNumber());
            throw new AuraHandledException('Error fetching rejoin cases by email: ' + e.getMessage());
        }
    }
}
//Sid
//sid
// Add these methods for Attendance Exception
// New approach: Get Sessions first, then Courses based on selected session
@AuraEnabled(cacheable=true)
public static List<SessionAttendanceWrapper> getAttendanceExceptionSessions(String contactId) {
    try {
        if (String.isBlank(contactId)) {
            throw new AuraHandledException('Contact ID is required');
        }

        System.debug('=== ATTENDANCE EXCEPTION SESSIONS DEBUG START ===');
        System.debug('Contact ID: ' + contactId);

        List<SessionAttendanceWrapper> sessionWrappers = new List<SessionAttendanceWrapper>();
        
        // Step 1: Get the contact's Program Enrollment
        List<ProgramEnrollment> programEnrollments = [
            SELECT Id, ProgramId, Status
            FROM ProgramEnrollment 
            WHERE ContactId = :contactId 
            AND Status = 'Registered'
            LIMIT 1
        ];
        
        System.debug('Step 1 - Program Enrollments found: ' + programEnrollments.size());
        if (!programEnrollments.isEmpty()) {
            System.debug('Program ID: ' + programEnrollments[0].ProgramId);
            System.debug('Program Status: ' + programEnrollments[0].Status);
        }
        
        if (programEnrollments.isEmpty()) {
            System.debug('ISSUE: No Program Enrollment found with Status = Registered');
            return sessionWrappers;
        }
        
        String programId = programEnrollments[0].ProgramId;
        
        // Step 2: Get Course Offerings for this program
        List<CourseOffering> courseOfferings = [
            SELECT Id, Name, LearningCourseId, AcademicSessionId
            FROM CourseOffering 
            WHERE Program__c = :programId
            AND IsActive = true
        ];
        
        System.debug('Step 2 - Course Offerings found: ' + courseOfferings.size());
        if (!courseOfferings.isEmpty()) {
            System.debug('Sample Course Offering: ' + courseOfferings[0].Name);
        }
        
        if (courseOfferings.isEmpty()) {
            System.debug('ISSUE: No Course Offerings found for Program: ' + programId);
            return sessionWrappers;
        }
        
        Set<Id> courseOfferingIds = new Set<Id>();
        for (CourseOffering co : courseOfferings) {
            courseOfferingIds.add(co.Id);
        }
        
        // Step 3: Get Course Offering Participants for this contact
        List<CourseOfferingParticipant> participants = [
            SELECT Id, CourseOfferingId, CourseOffering.Name
            FROM CourseOfferingParticipant 
            WHERE ParticipantContactId = :contactId
            AND CourseOfferingId IN :courseOfferingIds
        ];
        
        System.debug('Step 3 - Course Offering Participants found: ' + participants.size());
        if (!participants.isEmpty()) {
            System.debug('Sample Participant Course: ' + participants[0].CourseOffering.Name);
        }
        
        if (participants.isEmpty()) {
            System.debug('ISSUE: No Course Offering Participants found for Contact: ' + contactId);
            System.debug('Available Course Offering IDs: ' + courseOfferingIds);
            return sessionWrappers;
        }
        
        Set<Id> enrolledCourseOfferingIds = new Set<Id>();
        for (CourseOfferingParticipant cop : participants) {
            enrolledCourseOfferingIds.add(cop.CourseOfferingId);
        }
        
        System.debug('Enrolled Course Offering IDs: ' + enrolledCourseOfferingIds);
        
        // Step 4: Get Session Attendance records for these enrolled courses
        List<Session_Attendance__c> sessionAttendances = [
            SELECT Id, Name, Session_Key__c, Course_Offering__c, 
                   Course_Offering__r.Name, Course_Offering__r.LearningCourse.Name,
                   Course_Offering__r.LearningCourseId,
                   Date__c, Time__c
            FROM Session_Attendance__c 
            WHERE Course_Offering__c IN :enrolledCourseOfferingIds
            AND Session_Key__c != null
            ORDER BY Date__c DESC, Time__c DESC
            LIMIT 1000
        ];
        
        System.debug('Step 4 - Session Attendance records found: ' + sessionAttendances.size());
        
        // Fetch Course Attendance records to link sessions to student's specific course attendance
        Map<Id, Id> courseToCourseAttendanceMap = new Map<Id, Id>();
        if (!sessionAttendances.isEmpty()) {
            Set<Id> learningCourseIds = new Set<Id>();
            for (Session_Attendance__c sa : sessionAttendances) {
                if (sa.Course_Offering__r.LearningCourseId != null) {
                    learningCourseIds.add(sa.Course_Offering__r.LearningCourseId);
                }
            }

            for (Course_Attendance__c ca : [
                SELECT Id, Learning_Course__c 
                FROM Course_Attendance__c 
                WHERE Contact__c = :contactId 
                AND Learning_Course__c IN :learningCourseIds
                AND Status__c = 'Absent'
            ]) {
                courseToCourseAttendanceMap.put(ca.Learning_Course__c, ca.Id);
            }
        }

        // Create wrapper for each session
        for (Session_Attendance__c sa : sessionAttendances) {
            SessionAttendanceWrapper sessionWrapper = new SessionAttendanceWrapper();
            sessionWrapper.sessionId = sa.Id;
            sessionWrapper.sessionKey = sa.Session_Key__c;
            sessionWrapper.sessionName = sa.Name;
            
            // Use LearningCourse Name if available, fallback to Offering Name
            sessionWrapper.courseName = sa.Course_Offering__r.LearningCourse != null ? 
                                       sa.Course_Offering__r.LearningCourse.Name : 
                                       sa.Course_Offering__r.Name;
            
            sessionWrapper.dateOfSession = sa.Date__c;
            sessionWrapper.timeOfSession = sa.Time__c;
            
            if (sa.Course_Offering__r.LearningCourseId != null) {
                sessionWrapper.courseAttendanceId = courseToCourseAttendanceMap.get(sa.Course_Offering__r.LearningCourseId);
            }
            
            sessionWrappers.add(sessionWrapper);
        }

        System.debug('Total Session Wrappers created: ' + sessionWrappers.size());
        System.debug('=== ATTENDANCE EXCEPTION SESSIONS DEBUG END ===');
        
        return sessionWrappers;

    } catch (Exception e) {
        System.debug('ERROR in getAttendanceExceptionSessions: ' + e.getMessage());
        System.debug('Stack Trace: ' + e.getStackTraceString());
        throw new AuraHandledException('Error fetching attendance exception sessions: ' + e.getMessage());
    }
}

@AuraEnabled(cacheable=true)
public static List<CourseAttendanceWrapper> getAttendanceExceptionCoursesBySession(String contactId, String sessionId) {
    try {
        if (String.isBlank(contactId)) {
            throw new AuraHandledException('Contact ID is required');
        }

        List<CourseAttendanceWrapper> courseWrappers = new List<CourseAttendanceWrapper>();
        
        // Query Course Attendance records with status = 'Absent' for the contact
        List<Course_Attendance__c> courseAttendances = [
            SELECT Id, Name, Status__c, Learning_Course__c, Learning_Course__r.Name,
                   Session_Attendace_Id__c, Contact__c
            FROM Course_Attendance__c 
            WHERE Contact__c = :contactId 
            AND Status__c = 'Absent'
            AND Learning_Course__c != null
            ORDER BY Learning_Course__r.Name
        ];

        // Create wrapper for each course
        for (Course_Attendance__c ca : courseAttendances) {
            CourseAttendanceWrapper wrapper = new CourseAttendanceWrapper();
            wrapper.courseId = ca.Learning_Course__c;
            wrapper.courseName = ca.Learning_Course__r.Name;
            wrapper.courseAttendanceId = ca.Id;
            courseWrappers.add(wrapper);
        }

        return courseWrappers;

    } catch (Exception e) {
        throw new AuraHandledException('Error fetching courses for session: ' + e.getMessage());
    }
}

@AuraEnabled
public static String createAttendanceExceptionCase(String contactId, String accountId, String subject, 
                                                  String description, String courseAttendanceId, 
                                                  String sessionAttendanceId, Date dateOfAbsence) {
    try {
        // Get the Attendance Exception record type ID
        List<RecordType> recordTypes = [
            SELECT Id 
            FROM RecordType 
            WHERE SObjectType = 'Case' 
            AND Name = 'Attendance Exception'
            LIMIT 1
        ];

        if (recordTypes.isEmpty()) {
            throw new AuraHandledException('Attendance Exception record type not found');
        }

        String recordTypeId = recordTypes[0].Id;

        // Create the case
        Case newCase = new Case();
        newCase.ContactId = contactId;
        newCase.AccountId = accountId;
        newCase.Subject = subject;
        newCase.Description = description;
        newCase.RecordTypeId = recordTypeId;
        newCase.Status = 'Submitted';
        newCase.Origin = 'Web';
       // newCase.Course_Attendance__c = courseAttendanceId;
       // newCase.Session_Attendance__c = sessionAttendanceId;
        newCase.Date_of_Absence__c = dateOfAbsence;

        Database.DMLOptions dmlOpts = new Database.DMLOptions();
        dmlOpts.assignmentRuleHeader.useDefaultRule = true;
        newCase.setOptions(dmlOpts);

        insert newCase;
        return newCase.Id;

    } catch (Exception e) {
        throw new AuraHandledException('Error creating attendance exception case: ' + e.getMessage());
    }
}

//Attendance Duplicacy check Sid - START
@AuraEnabled
public static Map<String, Object> checkDuplicateAttendanceException(String contactId, Date dateOfAbsence, 
                                                                     String sessionKey, String learningCourseName) {
    try {
        System.debug('=== DUPLICATE CHECK APEX START ===');
        System.debug('Input - Contact ID: ' + contactId);
        System.debug('Input - Date of Absence: ' + dateOfAbsence);
        System.debug('Input - Session Key: ' + sessionKey);
        System.debug('Input - Learning Course Name: ' + learningCourseName);
        
        Map<String, Object> result = new Map<String, Object>();
        
        // Query for existing cases with the same combination
        List<Case> existingCases = [
            SELECT Id, CaseNumber, Subject, Status, CreatedDate,
                   ContactId, Date_of_Absence__c, Session__c, Learning_Course__c
            FROM Case 
            WHERE ContactId = :contactId
            AND Date_of_Absence__c = :dateOfAbsence
            AND Session__c = :sessionKey
            AND Learning_Course__c = :learningCourseName
            AND RecordType.Name = 'Attendance Exception'
            LIMIT 1
        ];
        
        System.debug('Existing cases found: ' + existingCases.size());
        
        if (!existingCases.isEmpty()) {
            System.debug('DUPLICATE FOUND!');
            System.debug('Existing Case Number: ' + existingCases[0].CaseNumber);
            System.debug('Existing Case ID: ' + existingCases[0].Id);
            System.debug('Existing Case Status: ' + existingCases[0].Status);
            System.debug('Existing Case Contact: ' + existingCases[0].ContactId);
            System.debug('Existing Case Date: ' + existingCases[0].Date_of_Absence__c);
            System.debug('Existing Case Session: ' + existingCases[0].Session__c);
            System.debug('Existing Case Course: ' + existingCases[0].Learning_Course__c);
            
            result.put('isDuplicate', true);
            result.put('existingCaseNumber', existingCases[0].CaseNumber);
            result.put('existingCaseId', existingCases[0].Id);
            result.put('existingCaseStatus', existingCases[0].Status);
            result.put('existingCaseSubject', existingCases[0].Subject);
        } else {
            System.debug('No duplicate found - OK to create case');
            result.put('isDuplicate', false);
        }
        
        System.debug('Result map: ' + result);
        System.debug('=== DUPLICATE CHECK APEX END ===');
        
        return result;
        
    } catch (Exception e) {
        System.debug('ERROR in checkDuplicateAttendanceException: ' + e.getMessage());
        System.debug('Stack Trace: ' + e.getStackTraceString());
        throw new AuraHandledException('Error checking duplicate attendance exception: ' + e.getMessage());
    }
}
//Attendance Duplicacy check Sid - END

@AuraEnabled(cacheable=true)
public static List<ProgramWrapper> getUserPrograms() {
    try {
        User currentUser = [
            SELECT ContactId 
            FROM User 
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];

        if (currentUser.ContactId == null) {
            throw new AuraHandledException('No Contact associated with this user.');
        }

        List<ProgramEnrollment> enrollments = [
            SELECT Id, ProgramId, Program.Name,Status,Academic_Term__c,Sub_Status__c
            FROM ProgramEnrollment 
            WHERE ContactId = :currentUser.ContactId
            AND status = 'Registered'
            AND ProgramId != null
        ];

        List<ProgramWrapper> programs = new List<ProgramWrapper>();
        for (ProgramEnrollment pe : enrollments) {
            if (pe.Program != null && pe.Program.Name != null) {
                programs.add(new ProgramWrapper(pe.ProgramId, pe.Program.Name));
            }
        }

        System.debug('Found ' + programs.size() + ' programs for contact: ' + currentUser.ContactId);
        return programs;

    } catch (Exception e) {
        throw new AuraHandledException('Error fetching programs: ' + e.getMessage());
    }
}
@AuraEnabled(cacheable=true)
public static List<ProgramWrapper> getRejoinEligiblePrograms() {
    try {
        User currentUser = [
            SELECT ContactId 
            FROM User 
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];

        if (currentUser.ContactId == null) {
            throw new AuraHandledException('No Contact associated with this user.');
        }

        // For Rejoin - get programs where student is on Leave of Absence
        List<ProgramEnrollment> enrollments = [
            SELECT Id, ProgramId, Program.Name, Status, Academic_Term__c, Sub_Status__c, Sub_Sub_Status__c
            FROM ProgramEnrollment 
            WHERE ContactId = :currentUser.ContactId
            AND Status = 'On Hold'
            AND Sub_Sub_Status__c = 'Leave of Absence'
            AND ProgramId != null
        ];

        List<ProgramWrapper> programs = new List<ProgramWrapper>();
        for (ProgramEnrollment pe : enrollments) {
            if (pe.Program != null && pe.Program.Name != null) {
                programs.add(new ProgramWrapper(pe.ProgramId, pe.Program.Name));
            }
        }

        System.debug('Found ' + programs.size() + ' rejoin-eligible programs for contact: ' + currentUser.ContactId);
        return programs;

    } catch (Exception e) {
        throw new AuraHandledException('Error fetching rejoin programs: ' + e.getMessage());
    }
}

@AuraEnabled(cacheable=true)
public static List<AcademicSessionWrapper> getAcademicSessionsByProgram(String programId) {
    try {
        if (String.isBlank(programId)) {
            return new List<AcademicSessionWrapper>();
        }

        // Get the current user's ContactId
        User currentUser = [
            SELECT ContactId
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];

        if (currentUser.ContactId == null) {
            throw new AuraHandledException('No Contact associated with this user.');
        }

        // Fetch Enrollment_Session__c records where the contact is registered
        // Assigned_Contact__c is the real Contact lookup on Enrollment_Session__c
        // List<Enrollment_Session__c> enrollmentSessions = [
        //     SELECT Academic_Session__c, Academic_Session__r.Name
        //     FROM Enrollment_Session__c
        //     WHERE Assigned_Contact__c = :currentUser.ContactId
        //     AND Status__c = 'Registered'
        //     AND Academic_Session__c != null
        //     ORDER BY Academic_Session__r.Name
        // ];

        // Deduplicate: a student may have multiple enrollment sessions for the same AcademicSession
        // Map<Id, AcademicSessionWrapper> sessionMap = new Map<Id, AcademicSessionWrapper>();
        // for (Enrollment_Session__c es : enrollmentSessions) {
        //     if (!sessionMap.containsKey(es.Academic_Session__c)) {
        //         sessionMap.put(es.Academic_Session__c,
        //             new AcademicSessionWrapper(es.Academic_Session__c, es.Academic_Session__r.Name));
        //     }
        // }
        // System.debug('Found ' + sessionMap.size() + ' registered sessions for program: ' + programId);
        // return sessionMap.values();

        // OLD LOGIC - via ProgramEnrollment → AcademicTerm → AcademicSession
        List<ProgramEnrollment> enrollments = [
            SELECT Id, ProgramId, Program.Name, Status, Academic_Term__c
            FROM ProgramEnrollment
            WHERE ContactId = :currentUser.ContactId
            AND status = 'Registered'
            AND ProgramId = :programId
        ];
        
        Set<Id> academicTermIds = new Set<Id>();
        for (ProgramEnrollment pe : enrollments) {
            if (pe.Academic_Term__c != null) {
                academicTermIds.add(pe.Academic_Term__c);
            }
        }
        
        if (academicTermIds.isEmpty()) { 
            return new List<AcademicSessionWrapper>(); 
        }
        
        List<AcademicTerm> academicTerms = [
            SELECT Id, Name, StartDate, EndDate FROM AcademicTerm WHERE Id IN :academicTermIds
        ];
        
        if (academicTerms.isEmpty()) { 
            return new List<AcademicSessionWrapper>(); 
        }
        
        List<AcademicSession> sessions = [
            SELECT Id, Name, AcademicTermId FROM AcademicSession
            WHERE AcademicTermId IN :academicTerms ORDER BY Name
        ];
        
        List<AcademicSessionWrapper> sessionList = new List<AcademicSessionWrapper>();
        for (AcademicSession session : sessions) {
            sessionList.add(new AcademicSessionWrapper(session.Id, session.Name));
        }
        
        System.debug('Found ' + sessionList.size() + ' academic sessions using ProgramEnrollment logic');
        return sessionList;

    } catch (Exception e) {
        throw new AuraHandledException('Error fetching academic sessions: ' + e.getMessage());
    }
}

@AuraEnabled(cacheable=true)
public static Boolean requiresFinancialStatement(String caseId) {
    try {
        Case currentCase = [
            SELECT Id, FinancialStatement__c, Status
            FROM Case 
            WHERE Id = :caseId 
            LIMIT 1
        ];
        // Check if FinancialStatement__c is true AND Status is not already set to finance statement statuses
        return currentCase.FinancialStatement__c == true && 
               //currentCase.Status != 'Finance Statement Accepted' &&
               //currentCase.Status != 'Finance Statement Rejected';
               currentCase.Status == 'Approved By Finance HOD';
    } catch (Exception e) {
        return false;
    }
}

@AuraEnabled
public static String acceptFinancialStatement(String caseId, Boolean isAccepted, String reason) {
    try {
        Case currentCase = [
            SELECT Id, FinancialStatement__c, Status, Notes__c
            FROM Case 
            WHERE Id = :caseId 
            LIMIT 1
        ];
        
        if (currentCase.FinancialStatement__c != true) {
            throw new AuraHandledException('Financial statement is not required for this case.');
        }
        
        // Check if already processed
        if (currentCase.Status == 'Finance Statement Accepted' || currentCase.Status == 'Finance Statement Rejected') {
            throw new AuraHandledException('Financial statement has already been processed.');
        }
        
        if (isAccepted) {
            // User accepted financial statement
            currentCase.Status = 'Finance Statement Accepted';
            currentCase.Notes__c = (String.isNotBlank(currentCase.Notes__c) ? currentCase.Notes__c + '\n' : '') + 
                                  'Financial statement accepted: ' + (String.isNotBlank(reason) ? reason : 'No additional comments');
        } else {
            // User rejected financial statement
            if (String.isBlank(reason)) {
                throw new AuraHandledException('Please provide a reason for rejecting the financial statement.');
            }
            currentCase.Status = 'Finance Statement Rejected';
            currentCase.Notes__c = (String.isNotBlank(currentCase.Notes__c) ? currentCase.Notes__c + '\n' : '') + 
                                   + reason;
        }
        
        update currentCase;
        
        return 'Financial statement ' + (isAccepted ? 'accepted' : 'rejected') + ' successfully. Case status updated.';
        
    } catch (Exception e) {
        throw new AuraHandledException('Error processing financial statement: ' + e.getMessage());
    }
}
@AuraEnabled
public static void saveFiles(String parentId, List<FileUploadWrapper> files) {
    try {
        if (files == null || files.isEmpty()) {
            return;
        }
        
        List<ContentVersion> contentVersions = new List<ContentVersion>();
        
        for (FileUploadWrapper file : files) {
            if (file.base64Data == null) {
                continue;
            }
            
            ContentVersion cv = new ContentVersion();
            cv.Title = file.fileName;
            cv.PathOnClient = file.fileName;
            cv.VersionData = EncodingUtil.base64Decode(file.base64Data);
            cv.FirstPublishLocationId = parentId;
            contentVersions.add(cv);
        }
        
        if (!contentVersions.isEmpty()) {
            insert contentVersions;
            //updateCaseStatusToSubmitted(parentId);
        }
    } catch (Exception e) {
        throw new AuraHandledException('Error saving files: ' + e.getMessage());
    }
}

private static void updateCaseStatusToSubmitted(String caseId) {
    try {
        List<Case> casesToUpdate = [
            SELECT Id, Status 
            FROM Case 
            WHERE Id = :caseId 
            AND Status != 'Submitted'
            LIMIT 1
        ];
        
        if (!casesToUpdate.isEmpty()) {
            Case caseToUpdate = casesToUpdate[0];
            caseToUpdate.Status = 'Submitted';
            update caseToUpdate;
        }
    } catch (Exception e) {
        System.debug('Error updating case status: ' + e.getMessage());
    }
}

/*
@AuraEnabled(cacheable=true)
public static List<RecordType> getRecordTypes() {
    try {
        return [
            SELECT Id, Name, Description 
            FROM RecordType 
            WHERE SObjectType = 'Case' 
            AND IsActive = true
            ORDER BY Name
        ];
    } catch (Exception e) {
        throw new AuraHandledException('Error fetching record types: ' + e.getMessage());
    }
}
*/

   
   @AuraEnabled(cacheable=true)
public static List<RecordType> getRecordTypes() {

    try {
        // Describe Case object
        Schema.DescribeSObjectResult caseDescribe =
            Case.SObjectType.getDescribe();

        Map<Id, Schema.RecordTypeInfo> rtInfoById =
            caseDescribe.getRecordTypeInfosById();

        List<RecordType> accessibleRecordTypes = new List<RecordType>();

        // Fetch active Case record types
        for (RecordType rt : [
            SELECT Id, Name, Description
            FROM RecordType
            WHERE SObjectType = 'Case'
            AND IsActive = true
            ORDER BY Name
        ]) {
            // Filter by running-user access
            Schema.RecordTypeInfo rtInfo = rtInfoById.get(rt.Id);
            if (rtInfo != null && rtInfo.isAvailable()) {
                accessibleRecordTypes.add(rt);
            }
        }

        return accessibleRecordTypes;

    } catch (Exception e) {
        throw new AuraHandledException(
            'Error fetching accessible record types: ' + e.getMessage()
        );
    }
}



@AuraEnabled(cacheable=true)
public static Boolean verifyCaseOwnership(String caseId) {
    try {
        User currentUser = [
            SELECT ContactId 
            FROM User 
            WHERE Id = :UserInfo.getUserId() 
            LIMIT 1
        ];
        
        Case existingCase = [
            SELECT Id, ContactId 
            FROM Case 
            WHERE Id = :caseId 
            LIMIT 1
        ];
        
        return existingCase.ContactId == currentUser.ContactId;
        
    } catch (Exception e) {
        throw new AuraHandledException('Error verifying case ownership: ' + e.getMessage());
    }
}

@AuraEnabled(cacheable=true)
public static List<FileWrapper> getCaseFiles(String caseId) {
    try {
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId, LinkedEntityId,
                    ContentDocument.Title,
                    ContentDocument.FileExtension,
                    ContentDocument.FileType,
                    ContentDocument.LatestPublishedVersion.ContentSize,
                    ContentDocument.LatestPublishedVersion.CreatedDate
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :caseId
            ORDER BY ContentDocument.LatestPublishedVersion.CreatedDate DESC
        ];

        List<FileWrapper> files = new List<FileWrapper>();
        for (ContentDocumentLink link : links) {
            FileWrapper file = new FileWrapper();
            file.contentDocumentId = link.ContentDocumentId;
            file.contentVersionId = link.ContentDocument.LatestPublishedVersion.Id;
            file.title = link.ContentDocument.Title;
            file.fileType = link.ContentDocument.FileType;
            file.fileExtension = link.ContentDocument.FileExtension;
            file.contentSize = link.ContentDocument.LatestPublishedVersion.ContentSize;
            file.uploadedDate = link.ContentDocument.LatestPublishedVersion.CreatedDate;
            files.add(file);
        }

        return files;
    } catch (Exception e) {
        throw new AuraHandledException('Error fetching case files: ' + e.getMessage());
    }
}

@AuraEnabled
public static String downloadFile(String contentDocumentId) {
    try {
        ContentVersion contentVersion = [
            SELECT VersionData 
            FROM ContentVersion 
            WHERE ContentDocumentId = :contentDocumentId 
            AND IsLatest = true 
            LIMIT 1
        ];

        return EncodingUtil.base64Encode(contentVersion.VersionData);
    } catch (Exception e) {
        throw new AuraHandledException('Error downloading file: ' + e.getMessage());
    }
}

@AuraEnabled(cacheable=true)
public static Case getCaseDetails(String caseId) {
try {
return [
    SELECT Id, CaseNumber, Subject, Description, Status, ContactPhone, ContactMobile, OwnerId
            , ContactEmail, Alternate_Email__c, Alternate_Phone__c,
            Academic_Year__r.Name, From_Term__c, To_Term__c, 
            Completed_Term__c, LOA_Type__c, Program__r.Name, Requested_End_Date__c,
            Document_Type__c, Delivery_Mode__c, Dispatch_Address__c,
            Passport_Number__c, Passport_Expiry__c, 
            Travel_Start_Date__c, Travel_End_Date__c,
            Visa_Type__c, Visa_Purpose__c, Title__c, Proposed_Date_Time__c, Venue__c, Host_Body__c, Expected_Headcount__c, Budget_Ask__c, Event_Contact__c,
            Requested_Legal_Name__c, Rejoin_Amount_Paid__c, Type,
            RecordType.Name, RecordType.DeveloperName, Sub_Types__c, FinancialStatement__c, TermsCondition__c, Terms_and_Condition__c, LastModifiedDate,
            Account_Holder_Name__c, IFSC_Code__c, Bank__c, Branch_Name__c, AccountNumber__c, Amount__c, Type__c, Mode_of_Interaction__c
    FROM Case 
    WHERE Id = :caseId 
    LIMIT 1
];
} catch (Exception e) {
throw new AuraHandledException('Error fetching case details: ' + e.getMessage());
}
}

@AuraEnabled
public static String getOwnerName(String ownerId) {
    try {
        if (String.isBlank(ownerId)) {
            return '';
        }
        
        // Query User first
        List<User> users = [SELECT Name, FirstName, LastName FROM User WHERE Id = :ownerId LIMIT 1];
        if (!users.isEmpty()) {
            String ownerName = '';
            if (String.isNotBlank(users[0].FirstName)) {
                ownerName += users[0].FirstName;
            }
            if (String.isNotBlank(users[0].LastName)) {
                if (String.isNotBlank(ownerName)) {
                    ownerName += ' ';
                }
                ownerName += users[0].LastName;
            }
            if (String.isBlank(ownerName)) {
                ownerName = users[0].Name;
            }
            return ownerName;
        }
        
        // If not a user, query Group (for queues and groups)
        List<Group> groups = [SELECT Name FROM Group WHERE Id = :ownerId LIMIT 1];
        if (!groups.isEmpty()) {
            return groups[0].Name;
        }
        
        return '';
    } catch (Exception e) {
        throw new AuraHandledException('Error fetching owner name: ' + e.getMessage());
    }
}

@AuraEnabled(cacheable=true)
public static List<Case> getOpenCases() {
    try {
        User currentUser = [
            SELECT ContactId 
            FROM User 
            WHERE Id = :UserInfo.getUserId() 
            LIMIT 1
        ];

        if (currentUser.ContactId == null) {
            throw new AuraHandledException('No Contact associated with this user.');
        }

        List<Case> openCases = [
            SELECT Id, CaseNumber, Subject, Status, CreatedDate, RecordTypeId
            FROM Case 
            WHERE ContactId = :currentUser.ContactId 
            AND IsClosed = false
            ORDER BY CreatedDate DESC
        ];

        return openCases;

    } catch (Exception e) {
        throw new AuraHandledException('Error fetching open cases: ' + e.getMessage());
    }
}

@AuraEnabled
public static String getFilePreviewUrl(String contentDocumentId) {
    try {
        ContentVersion contentVersion = [
            SELECT Id, Title, ContentDocumentId 
            FROM ContentVersion 
            WHERE ContentDocumentId = :contentDocumentId 
            AND IsLatest = true 
            LIMIT 1
        ];
        
        List<ContentDistribution> existingDistributions = [
            SELECT Id, DistributionPublicUrl, ContentVersionId 
            FROM ContentDistribution 
            WHERE ContentVersionId = :contentVersion.Id
            LIMIT 1
        ];
        
        if (!existingDistributions.isEmpty()) {
            return existingDistributions[0].DistributionPublicUrl;
        }
        
        ContentDistribution newDistribution = new ContentDistribution();
        newDistribution.Name = 'Preview_' + contentVersion.Title;
        newDistribution.ContentVersionId = contentVersion.Id;
        newDistribution.PreferencesAllowViewInBrowser = true;
        newDistribution.PreferencesLinkLatestVersion = true;
        newDistribution.PreferencesNotifyOnVisit = false;
        newDistribution.PreferencesPasswordRequired = false;
        newDistribution.PreferencesAllowOriginalDownload = true;
        
        insert newDistribution;
        
        ContentDistribution createdDistribution = [
            SELECT DistributionPublicUrl 
            FROM ContentDistribution 
            WHERE Id = :newDistribution.Id
        ];
        
        return createdDistribution.DistributionPublicUrl;
        
    } catch (Exception e) {
        throw new AuraHandledException('Error getting file preview URL: ' + e.getMessage());
    }
}

@AuraEnabled(cacheable=true)
public static List<Case> getCasesByFormulaField() {
    try {
        User currentUser = [
            SELECT ContactId 
            FROM User 
            WHERE Id = :UserInfo.getUserId() 
            LIMIT 1
        ];

        if (currentUser.ContactId == null) {
            throw new AuraHandledException('No Contact associated with this user.');
        }

        List<Case> eligibleCases = [
            SELECT Id, CaseNumber, Subject, Status, CreatedDate
            FROM Case 
            WHERE ContactId = :currentUser.ContactId 
            AND IsClosed = false
            AND Status = 'Approved'
            ORDER BY CreatedDate DESC
        ];

        return eligibleCases;

    } catch (Exception e) {
        throw new AuraHandledException('Error fetching eligible cases: ' + e.getMessage());
    }
}

@AuraEnabled
public static ValidationResult validateStudentEnrollment(
    String contactId, 
    String programId, 
    String fromTermId, 
    String toTermId
) {
    try {
        ValidationResult result = new ValidationResult();
        result.isValid = true;
        result.message = '';
        
        List<String> termIds = new List<String>();
        if (String.isNotBlank(fromTermId)) {
            termIds.add(fromTermId);
        }
        if (String.isNotBlank(toTermId) && fromTermId != toTermId) {
            termIds.add(toTermId);
        }
        
        if (termIds.isEmpty()) {
            result.isValid = false;
            result.message = 'Please select valid terms';
            return result;
        }
        
        List<ProgramEnrollment> programEnrollments = [
            SELECT Id, ContactId, ProgramId 
            FROM ProgramEnrollment 
            WHERE ContactId = :contactId 
            AND ProgramId = :programId
            AND isActive = true
            LIMIT 1
        ];
        
        if (programEnrollments.isEmpty()) {
            result.isValid = false;
            result.message = 'You are not enrolled in this program. Please contact your administrator.';
            return result;
        }
        
        String programEnrollmentId = programEnrollments[0].Id;
        
        List<Enrollment_Session__c> enrollmentSessions = [
            SELECT Id, Program_Enrollment__c, Academic_Session__c, Status__c, Academic_Session__r.Name
            FROM Enrollment_Session__c
            WHERE Program_Enrollment__c = :programEnrollmentId
            AND Academic_Session__c IN :termIds
            AND Status__c = 'Registered'
        ];
        
        Set<String> registeredTermIds = new Set<String>();
        for (Enrollment_Session__c es : enrollmentSessions) {
            registeredTermIds.add(es.Academic_Session__c);
        }
        
        List<String> missingTerms = new List<String>();
        for (String termId : termIds) {
            if (!registeredTermIds.contains(termId)) {
                AcademicSession term = [SELECT Name FROM AcademicSession WHERE Id = :termId LIMIT 1];
                missingTerms.add(term.Name);
            }
        }
        
        if (!missingTerms.isEmpty()) {
            result.isValid = false;
            result.message = 'You are not registered for the following term(s): ' + 
                            String.join(missingTerms, ', ') + 
                            '. Please contact your administrator.';
        }
        
        return result;
        
    } catch (Exception e) {
        throw new AuraHandledException('Error validating enrollment: ' + e.getMessage());
    }
}

@AuraEnabled(cacheable=true)
public static Boolean requiresTermsAndConditions(String caseId) {
    try {
        Case currentCase = [
            SELECT Id, Status, TermsCondition__c, RecordType.Name
            FROM Case 
            WHERE Id = :caseId 
            LIMIT 1
        ];
        
        // Return true if:
        // 1. Status is 'Approved' or 'Approved11'
        // 2. TermsCondition__c is TRUE (already accepted)
        // 3. Record type contains 'LOA'
        return (currentCase.Status == 'Approved' || currentCase.Status == 'Approved11') && 
               currentCase.TermsCondition__c == true &&
               currentCase.RecordType.Name.toLowerCase().contains('leave of absence');
    } catch (Exception e) {
        return false;
    }
}

@AuraEnabled
public static String acceptTermsAndConditions(String caseId, Boolean isAccepted, String reason) {
try {
    Case currentCase = [
        SELECT Id, Status, TermsCondition__c, Notes__c
        FROM Case 
        WHERE Id = :caseId 
        LIMIT 1
    ];
    
    if (currentCase.Status != 'Approved' && currentCase.Status != 'Approved11') {
            throw new AuraHandledException('Terms and conditions are not required for this case.');
        }
    
    if (isAccepted) {
           
            
            currentCase.TermsCondition__c = true;
            //currentCase.Notes__c = reason;
            currentCase.Status = 'T&C Accepted';
            
            update currentCase;
            
            return 'Terms and conditions accepted successfully. Case status updated.';
            
        } else {
            // User rejected terms
            currentCase.TermsCondition__c = false;
            currentCase.Notes__c = reason;
            currentCase.Status = 'T & C Rejected';
            
            update currentCase;
            
            return 'Terms and conditions rejected. Case status updated to Rejected.';
        }
    
} catch (Exception e) {
    System.debug('Error >>' + e.getMessage() + e.getLineNumber());
    throw new AuraHandledException('Error processing terms and conditions: ' + e.getMessage());
}
}

@AuraEnabled
public static ValidationResult validateExistingCases(
    String contactId, 
    String fromTermId, 
    String toTermId,
    String recordTypeId
) {
    try {
        ValidationResult result = new ValidationResult();
        result.isValid = true;
        result.message = '';
        
        if (String.isBlank(contactId) || String.isBlank(fromTermId) || String.isBlank(toTermId)) {
            result.isValid = true;
            return result;
        }
        
        AcademicSession fromTerm = [SELECT Name FROM AcademicSession WHERE Id = :fromTermId LIMIT 1];
        AcademicSession toTerm = [SELECT Name FROM AcademicSession WHERE Id = :toTermId LIMIT 1];
        
        List<Case> existingCases = [
            SELECT Id, CaseNumber, Subject, Status, From_Term__c, To_Term__c, RecordTypeId,Sub_Types__c
            FROM Case 
            WHERE ContactId = :contactId
            AND From_Term__c = :fromTerm.Name
            AND To_Term__c = :toTerm.Name
            AND RecordTypeId = :recordTypeId
           // AND Sub_Types__c = :subType
            AND Status != 'Approved'
            AND IsClosed = false
        ];
        
        if (!existingCases.isEmpty()) {
            result.isValid = false;
            Case existingCase = existingCases[0];
            result.message = 'You already have a pending ' + getRecordTypeName(recordTypeId) + 
                            ' request for these terms (Case: ' + existingCase.CaseNumber + 
                            '). Please wait for approval or contact support.';
        }
        
        return result;
        
    } catch (Exception e) {
        ValidationResult errorResult = new ValidationResult();
        errorResult.isValid = true;
        errorResult.message = '';
        return errorResult;
    }
}

private static String getRecordTypeName(String recordTypeId) {
    try {
        RecordType rt = [SELECT Name FROM RecordType WHERE Id = :recordTypeId LIMIT 1];
        return rt.Name;
    } catch (Exception e) {
        return 'Leave of Absence';
    }
}

@AuraEnabled
public static ValidationResult validateOpenCaseByRecordType(
    String contactId, 
    String recordTypeId,
    String subCategory
) {
    try {
        ValidationResult result = new ValidationResult();
        result.isValid = true;
        result.message = '';
        
        if (String.isBlank(contactId) || String.isBlank(recordTypeId)) {
            result.isValid = true;
            return result;
        }
        
        // Build the query dynamically based on whether subCategory is provided
        String query = 'SELECT Id, CaseNumber, Subject, Status, RecordType.Name, Sub_Category__c FROM Case WHERE ContactId = :contactId AND RecordTypeId = :recordTypeId AND Status != \'Approved\' AND Status != \'Closed\' AND IsClosed = false';
        
        if (String.isNotBlank(subCategory)) {
            query += ' AND Sub_Category__c = :subCategory';
        }
        
        query += ' ORDER BY CreatedDate DESC LIMIT 1';
        
        List<Case> openCases = Database.query(query);
        
        if (!openCases.isEmpty()) {
            result.isValid = false;
            Case existingCase = openCases[0];
            String subCatText = String.isNotBlank(existingCase.Sub_Category__c) ? ' with sub-category "' + existingCase.Sub_Category__c + '"' : '';
            result.message = 'You already have an open ' + existingCase.RecordType.Name + 
                            ' request' + subCatText + 
                            ' (Case: ' + existingCase.CaseNumber + 
                            ', Status: ' + existingCase.Status + 
                            '). Please wait for it to be processed before submitting a new request.';
        }
        
        return result;
        
    } catch (Exception e) {
        ValidationResult errorResult = new ValidationResult();
        errorResult.isValid = true;
        errorResult.message = '';
        return errorResult;
    }
}
// Add this method to your Apex controller
@AuraEnabled
public static ValidationResult validateGeneralSupportOpenCase(
    String contactId, 
    String recordTypeId,
    String subType
) {
    try {
        ValidationResult result = new ValidationResult();
        result.isValid = true;
        result.message = '';
        
        if (String.isBlank(contactId) || String.isBlank(recordTypeId) || String.isBlank(subType)) {
            result.isValid = true;
            return result;
        }
        
        // Get the record type name to verify it's General Support
        RecordType rt = [SELECT Name FROM RecordType WHERE Id = :recordTypeId LIMIT 1];
        
        if (!rt.Name.toLowerCase().contains('general support') && 
            !rt.Name.toLowerCase().contains('general')) {
            // Not a General Support case, skip validation
            return result;
        }
        
        // Query for open General Support cases with the same subtype
        List<Case> openCases = [
            SELECT Id, CaseNumber, Subject, Status, RecordType.Name, Sub_Types__c
            FROM Case 
            WHERE ContactId = :contactId
            AND RecordTypeId = :recordTypeId
            AND Sub_Types__c = :subType
            AND Status NOT IN ('Approved', 'Closed', 'Rejected')
            AND IsClosed = false
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        
        if (!openCases.isEmpty()) {
            result.isValid = false;
            Case existingCase = openCases[0];
            result.message = 'You already have an open ' + existingCase.RecordType.Name + 
                            ' request for "' + existingCase.Sub_Types__c + 
                            '" (Case: ' + existingCase.CaseNumber + 
                            ', Status: ' + existingCase.Status + 
                            '). Please wait for it to be processed before submitting a new request.';
        }
        
        return result;
        
    } catch (Exception e) {
        ValidationResult errorResult = new ValidationResult();
        errorResult.isValid = true;
        errorResult.message = '';
        return errorResult;
    }
}
// Validate Attendance Exception Date based on reason
private static String validateAttendanceExceptionDate(Date dateOfAbsence, String reason) {
    if (dateOfAbsence == null || String.isBlank(reason)) {
        return null;
    }
    
    DateTime absenceDateTime = DateTime.newInstance(dateOfAbsence, Time.newInstance(0, 0, 0, 0));
    DateTime currentDateTime = DateTime.now();
    
    // Calculate difference in hours and days
    Long millisecondsDiff = currentDateTime.getTime() - absenceDateTime.getTime();
    Decimal hoursDiff = millisecondsDiff / (1000.0 * 60 * 60);
    Integer daysDiff = dateOfAbsence.daysBetween(Date.today());
    
    // Reasons that require submission within 72 hours
    Set<String> urgentReasons = new Set<String>{
        'Medical Exigency',
        'Medical Emergency in Immediate Family',
        'Loss/Bereavement',
        'Hardship/Trauma'
    };
    
    // Reasons that require submission within 7 working days
    Set<String> standardReasons = new Set<String>{
        'Approved Case Competitions',
        'Professional Certification Exams',
        'National/International Sports Tournaments'
    };
    
    String reasonLower = reason.toLowerCase();
    Boolean isUrgentReason = false;
    Boolean isStandardReason = false;
    
    for (String urgentReason : urgentReasons) {
        if (reasonLower.contains(urgentReason.toLowerCase())) {
            isUrgentReason = true;
            break;
        }
    }
    
    for (String standardReason : standardReasons) {
        if (reasonLower.contains(standardReason.toLowerCase())) {
            isStandardReason = true;
            break;
        }
    }
    
    if (isUrgentReason) {
        // Check if more than 72 hours have passed
        if (hoursDiff > 72) {
            return 'For "' + reason + '", the exception must be raised within 72 hours from the date of absence. ' +
                   'The absence date is more than 72 hours ago. Please contact support for assistance.';
        }
    } else if (isStandardReason) {
        // Check if more than 7 working days have passed
        if (daysDiff > 7) {
            return 'For "' + reason + '", the exception must be raised within 7 working days from the date of absence. ' +
                   'The absence date is more than 7 days ago. Please contact support for assistance.';
        }
    }
    
    return null; // No validation error
}

// Helper method to extract date from Session_Key__c
// Format: "2025-07-01 | | A | | 10:00 AM"
private static Date extractDateFromSessionKey(String sessionKey) {
    if (String.isBlank(sessionKey)) {
        return null;
    }
    
    try {
        // Split by pipe delimiter and get first part (date)
        List<String> parts = sessionKey.split('\\|\\|');
        if (parts.size() > 0) {
            String datePart = parts[0].trim();
            // Parse date in format YYYY-MM-DD
            return Date.valueOf(datePart);
        }
    } catch (Exception e) {
        System.debug('Error extracting date from session key: ' + e.getMessage());
    }
    
    return null;
}

// REPLACE your existing getCompletedTerms method with this:
@AuraEnabled(cacheable=true)
public static String getCompletedTerms(String contactId, String programId) {
try {
if (String.isBlank(contactId) || String.isBlank(programId)) {
    return '';
}

// Get Program Enrollment
List<ProgramEnrollment> programEnrollments = [
    SELECT Id 
    FROM ProgramEnrollment 
    WHERE ContactId = :contactId 
    AND ProgramId = :programId
    AND Status = 'Registered'
    AND isActive = true
    LIMIT 1
];

if (programEnrollments.isEmpty()) {
    return '';
}

String programEnrollmentId = programEnrollments[0].Id;

// Get ONLY Academic Session names from completed enrollment sessions
List<Enrollment_Session__c> completedSessions = [
    SELECT Academic_Session__r.Name
    FROM Enrollment_Session__c
    WHERE Program_Enrollment__c = :programEnrollmentId
    AND Status__c = 'Completed'
    AND Academic_Session__r.Name != null
    ORDER BY Academic_Session__r.Name DESC
    LIMIT 1  // Only get the first one since you expect single result
];

// Return the single academic session name (or empty string if none found)
if (!completedSessions.isEmpty() && completedSessions[0].Academic_Session__r != null) {
    system.debug('completedSessions[0].Academic_Session__r.Name'+completedSessions[0].Academic_Session__r.Name);
    return completedSessions[0].Academic_Session__r.Name;
} else {
    return '';
}

} catch (Exception e) {
throw new AuraHandledException('Error fetching completed terms: ' + e.getMessage());
}
}

@AuraEnabled(cacheable=true)
public static List<PicklistValue> getSubTypeOptions(String recordTypeId) {
    try {
        List<PicklistValue> picklistValues = new List<PicklistValue>();
        
        Schema.DescribeFieldResult fieldResult = Case.Sub_Types__c.getDescribe();
        List<Schema.PicklistEntry> picklistEntries = fieldResult.getPicklistValues();
        
        for (Schema.PicklistEntry entry : picklistEntries) {
            if (entry.isActive()) {
                PicklistValue pv = new PicklistValue();
                pv.label = entry.getLabel();
                pv.value = entry.getValue();
                picklistValues.add(pv);
            }
        }
        
        return picklistValues;
        
    } catch (Exception e) {
        throw new AuraHandledException('Error fetching sub type options: ' + e.getMessage());
    }
}

@AuraEnabled(cacheable=true)
public static List<PicklistValue> getSubCategoryOptions() {
    try {
        List<PicklistValue> picklistValues = new List<PicklistValue>();
        
        Schema.DescribeFieldResult fieldResult = Case.Sub_Category__c.getDescribe();
        List<Schema.PicklistEntry> picklistEntries = fieldResult.getPicklistValues();
        
        for (Schema.PicklistEntry entry : picklistEntries) {
            if (entry.isActive()) {
                PicklistValue pv = new PicklistValue();
                pv.label = entry.getLabel();
                pv.value = entry.getValue();
                picklistValues.add(pv);
            }
        }
        
        return picklistValues;
        
    } catch (Exception e) {
        throw new AuraHandledException('Error fetching sub category options: ' + e.getMessage());
    }
}

@AuraEnabled(cacheable=true)
public static List<AcademicTermWrapper> getAcademicTermsForRejoin(String programId) {
    try {
        if (String.isBlank(programId)) {
            return new List<AcademicTermWrapper>();
        }

        // Get current date
        Date today = Date.today();
        
        // Get academic terms that start AFTER today
        List<AcademicTerm> academicTerms = [
            SELECT Id, Name, StartDate, EndDate
            FROM AcademicTerm 
            WHERE Program__c = :programId
            AND StartDate <= NEXT_N_YEARS:2 //To be reviewed with Rutuja
            ORDER BY StartDate DESC
            LIMIT 2  // Show next 5 cohorts
        ];

        System.debug('Academic terms found: ' + academicTerms.size());
        
        List<AcademicTermWrapper> termList = new List<AcademicTermWrapper>();
        
        for (AcademicTerm term : academicTerms) {
            AcademicTermWrapper wrapper = new AcademicTermWrapper();
            wrapper.id = term.Id;
            wrapper.name = term.Name;
            wrapper.startDate = term.StartDate;
            wrapper.endDate = term.EndDate;
            wrapper.formattedDateRange = formatDateRange(term.StartDate, term.EndDate);
            
            termList.add(wrapper);
        }

        return termList;

    } catch (Exception e) {
        throw new AuraHandledException('Error fetching academic terms: ' + e.getMessage());
    }
}
// Keep the same helper method
private static String formatDateRange(DateTime startDate, DateTime endDate) {
    if (startDate == null || endDate == null) return '';
    
    String startFormatted = startDate.format('MMM yyyy');
    String endFormatted = endDate.format('MMM yyyy');
    
    return startFormatted + ' - ' + endFormatted;
}

@AuraEnabled
public static String createLOACase(CaseDataWrapper caseData) {
    try {
        // VALIDATION SECTION - Applies to both new and existing cases
        if (caseData.fromTermId != null && caseData.toTermId != null && caseData.recordTypeId != null ) {
            ValidationResult existingCaseValidation = validateExistingCases(
                caseData.contactId, 
                caseData.fromTermId, 
                caseData.toTermId, 
                caseData.recordTypeId
            );
            
            if (!existingCaseValidation.isValid) {
                throw new AuraHandledException(existingCaseValidation.message);
            }
        }
        
        // UPDATE EXISTING CASE SECTION
        if (caseData.caseId != null) {
            // This is an update to an existing case
            Case existingCase = [SELECT Id, RecordType.Name FROM Case WHERE Id = :caseData.caseId LIMIT 1];
            
            System.debug('BANK UPDATE: Existing case found with ID: ' + caseData.caseId);
            System.debug('BANK UPDATE: Existing case record type: ' + existingCase.RecordType.Name);
            System.debug('BANK UPDATE: CaseData accountHolderName: ' + caseData.accountHolderName);
            System.debug('BANK UPDATE: CaseData accountNumber: ' + caseData.accountNumber);
            System.debug('BANK UPDATE: CaseData ifscCode: ' + caseData.ifscCode);
            System.debug('BANK UPDATE: CaseData bankName: ' + caseData.bankName);
            System.debug('BANK UPDATE: CaseData branchName: ' + caseData.branchName);
            
            // If it's a Withdrawal case, update bank details
            // TEMPORARILY UPDATE FOR ANY CASE TYPE FOR DEBUGGING
            if (existingCase.RecordType.Name.toLowerCase().contains('withdrawal') || true) { // Temporarily allow all case types
                System.debug('BANK UPDATE: Proceeding with bank details update (temporarily allowing all case types)');
                // Update bank details fields
                existingCase.Account_Holder_Name__c = caseData.accountHolderName;
                existingCase.AccountNumber__c = caseData.accountNumber;
                existingCase.IFSC_Code__c = caseData.ifscCode;
                existingCase.Bank__c = caseData.bankName;
                existingCase.Branch_Name__c = caseData.branchName;
                
                System.debug('BANK UPDATE: About to update existing case with bank details');
                update existingCase;
                System.debug('BANK UPDATE: Update completed successfully');
                return existingCase.Id;
            } else {
                System.debug('BANK UPDATE: Record type does not contain withdrawal - record type is: ' + existingCase.RecordType.Name);
                // For other case types, handle updates as needed
                // You might want to add other field updates here
                update existingCase;
                return existingCase.Id;
            }
        } 
        // CREATE NEW CASE SECTION
        else {
            Case newCase = new Case();
            
            // Set ContactId only if not blank (required field in most cases)
            if (String.isNotBlank(caseData.contactId)) {
                newCase.ContactId = caseData.contactId;
            }
            
            // Set AccountId only if not blank (may be null for some case types)
            if (String.isNotBlank(caseData.accountId)) {
                newCase.AccountId = caseData.accountId;
            }
            
            newCase.Subject = caseData.subject;
            newCase.Description = caseData.description;
            newCase.Type = caseData.caseType;
            newCase.Status = 'Submitted';
            newCase.Origin = 'Web';

            if (String.isNotBlank(caseData.programId)) {
                newCase.Program__c = caseData.programId;
            }
            if (String.isNotBlank(caseData.recordTypeId)) {
                newCase.RecordTypeId = caseData.recordTypeId;
            }

            if (String.isNotBlank(caseData.parentId)) {
                newCase.ParentId = caseData.parentId;
            }

            if (String.isNotBlank(caseData.loaType)) {
                newCase.LOA_Type__c = caseData.loaType;
            }

            if (String.isNotBlank(caseData.subType)) {
                newCase.Sub_Types__c = caseData.subType;
            }

            if (String.isNotBlank(caseData.subCategory)) {
                newCase.Sub_Category__c = caseData.subCategory;
            }

            if (String.isNotBlank(caseData.cohortId)) {
                newCase.Academic_Term__c = caseData.cohortId;
            }

            if (String.isNotBlank(caseData.alternateEmail)) {
                newCase.Alternate_Email__c = caseData.alternateEmail;
            }
            
            if (String.isNotBlank(caseData.alternatePhone)) {
                newCase.Alternate_Phone__c = caseData.alternatePhone;
            }

            // Set SuppliedEmail to ensure Flow matches the correct Contact
            if (String.isNotBlank(caseData.contactEmail)) {
                newCase.SuppliedEmail = caseData.contactEmail;
                System.debug('Set SuppliedEmail to: ' + caseData.contactEmail);
            }

            if (String.isNotBlank(caseData.parentId)) {
            // Get the parent case details
            Case parentCase = [
                SELECT Id, LOA_Type__c, From_Term__c, To_Term__c
                FROM Case 
                WHERE Id = :caseData.parentId 
                LIMIT 1
            ];
            
            // Populate LOA Type from parent case
            /* if (String.isNotBlank(parentCase.LOA_Type__c)) {
                newCase.LOA_Type__c = parentCase.LOA_Type__c;
            } */
            
            // If terms are not provided, use parent case terms
            if (String.isBlank(caseData.fromTermId) && String.isNotBlank(parentCase.From_Term__c)) {
                // Find academic session matching the parent's From Term
                List<AcademicSession> fromSessions = [
                    SELECT Id 
                    FROM AcademicSession 
                    WHERE Name = :parentCase.From_Term__c
                    LIMIT 1
                ];
                if (!fromSessions.isEmpty()) {
                    newCase.From_Term__c = parentCase.From_Term__c;
                }
            }
            
            if (String.isBlank(caseData.toTermId) && String.isNotBlank(parentCase.To_Term__c)) {
                // Find academic session matching the parent's To Term
                List<AcademicSession> toSessions = [
                    SELECT Id 
                    FROM AcademicSession 
                    WHERE Name = :parentCase.To_Term__c
                    LIMIT 1
                ];
                if (!toSessions.isEmpty()) {
                    newCase.To_Term__c = parentCase.To_Term__c;
                }
            }}

            if (String.isNotBlank(caseData.fromTermId)) {
                AcademicSession fromTerm = [
                    SELECT Name 
                    FROM AcademicSession 
                    WHERE Id = :caseData.fromTermId 
                    LIMIT 1
                ];
                newCase.From_Term__c = fromTerm.Name;
            }

            if (String.isNotBlank(caseData.toTermId)) {
                AcademicSession toTerm = [
                    SELECT Name 
                    FROM AcademicSession 
                    WHERE Id = :caseData.toTermId 
                    LIMIT 1
                ];
                newCase.To_Term__c = toTerm.Name;
            }

            if (String.isNotBlank(caseData.contactId) && String.isNotBlank(caseData.programId)) {
                String completedTerm = getCompletedTerms(caseData.contactId, caseData.programId);
                if (String.isNotBlank(completedTerm)) {
                    newCase.Completed_Term__c = completedTerm;
                }
            }
            

            if (String.isNotBlank(caseData.documentType)) {
                newCase.Document_Type__c = caseData.documentType;
            }

            if (String.isNotBlank(caseData.deliveryMode)) {
                newCase.Delivery_Mode__c = caseData.deliveryMode;
            }

        if (String.isNotBlank(caseData.deliveryMode) && 
        caseData.deliveryMode == 'Print' && 
        String.isNotBlank(caseData.dispatchAddress)) {
        newCase.Dispatch_Address__c = caseData.dispatchAddress;
        System.debug('Dispatch Address set to: ' + caseData.dispatchAddress);
        }

            if (String.isNotBlank(caseData.passportNumber)) {
                newCase.Passport_Number__c = caseData.passportNumber;
            }

            if (String.isNotBlank(caseData.passportExpiry)) {
                newCase.Passport_Expiry__c = Date.valueOf(caseData.passportExpiry);
            }

            if (String.isNotBlank(caseData.requestedEndDate)) {
                newCase.Requested_End_Date__c = Date.valueOf(caseData.requestedEndDate);
            }

            if (String.isNotBlank(caseData.travelStartDate)) {
                newCase.Travel_Start_Date__c = Date.valueOf(caseData.travelStartDate);
            }

            if (String.isNotBlank(caseData.travelEndDate)) {
                newCase.Travel_End_Date__c = Date.valueOf(caseData.travelEndDate);
            }

            if (String.isNotBlank(caseData.visaType)) {
                newCase.Visa_Type__c = caseData.visaType;
            }

            if (String.isNotBlank(caseData.visaPurpose)) {
                newCase.Visa_Purpose__c = caseData.visaPurpose;
            }

            // Name Change Fields
            if (String.isNotBlank(caseData.requestedLegalName)) {
                newCase.Requested_Legal_Name__c = caseData.requestedLegalName;
            }

            if (String.isNotBlank(caseData.nameChangeReason)) {
                newCase.Description = caseData.nameChangeReason;
            }

            // Event & Budget fields
            if (String.isNotBlank(caseData.eventTitle)) {
                newCase.Title__c = caseData.eventTitle;
            }

            if (String.isNotBlank(caseData.eventProposedDateTime)) {
                newCase.Proposed_Date_Time__c = (DateTime)JSON.deserialize('"' + caseData.eventProposedDateTime + '"', DateTime.class);
            }

            if (String.isNotBlank(caseData.eventVenue)) {
                newCase.Venue__c = caseData.eventVenue;
            }

            if (String.isNotBlank(caseData.eventHostBody)) {
                newCase.Host_Body__c = caseData.eventHostBody;
            }

            if (String.isNotBlank(caseData.eventExpectedHeadcount)) {
                newCase.Expected_Headcount__c = Decimal.valueOf(caseData.eventExpectedHeadcount);
            }

            if (String.isNotBlank(caseData.eventBudgetAsk)) {
                newCase.Budget_Ask__c = Decimal.valueOf(caseData.eventBudgetAsk);
            }
            if (String.isNotBlank(caseData.eventContacts)) {
                newCase.Event_Contact__c = caseData.eventContacts;
            }

            if (String.isNotBlank(caseData.currentAcademicTerm)) {
                newCase.Academic_Term__c = caseData.currentAcademicTerm;
            }

            // Attendance Exception fields
            if (String.isNotBlank(caseData.attendanceExceptionReason)) {
                newCase.Attendance_Exception_Reason__c = caseData.attendanceExceptionReason;
            }

            if (String.isNotBlank(caseData.selectedReturnReplaceCourseId)) {
                try {
                    List<CourseOfferingParticipant> participants = [
                        SELECT Id, CourseOffering.LearningCourse.Name
                        FROM CourseOfferingParticipant 
                        WHERE Id = :caseData.selectedReturnReplaceCourseId
                        LIMIT 1
                    ];
                    
                    if (!participants.isEmpty() && participants[0].CourseOffering != null && 
                        participants[0].CourseOffering.LearningCourse != null) {
                        newCase.Learning_Course__c = participants[0].CourseOffering.LearningCourse.Name;
                    }
                    
                } catch (Exception e) {
                    System.debug('Error fetching course name: ' + e.getMessage());
                    newCase.Learning_Course__c = 'Selected Course';
                }
            }

            // Extract date from sessionKey if provided
            Date extractedDateOfAbsence = null;
            if (String.isNotBlank(caseData.sessionKey)) {
                extractedDateOfAbsence = extractDateFromSessionKey(caseData.sessionKey);
                if (extractedDateOfAbsence != null) {
                    newCase.Date_of_Absence__c = extractedDateOfAbsence;
                }
            }

            // Store selected session (Session_Key__c) in Session__c text field
            if (String.isNotBlank(caseData.sessionKey)) {
                newCase.Session__c = caseData.sessionKey;
            }

       // In the createLOACase method, change this:
if (String.isNotBlank(caseData.wellbeingSeverity)) {
    newCase.Severity__c = caseData.wellbeingSeverity;
}
if (String.isNotBlank(caseData.wellbeingModeOfInteraction)) {
    newCase.Mode_of_Interaction__c = caseData.wellbeingModeOfInteraction;
}
if (String.isNotBlank(caseData.wellbeingType)) {
    newCase.Type__c = caseData.wellbeingType;
}
if (String.isNotBlank(caseData.wellbeingActionTaken)) {
    System.debug('valueeeeee111->'+ caseData.wellbeingActionTaken);
    newCase.Action_Taken__c = caseData.wellbeingActionTaken;
}

            // Store selected course name in Learning_Course__c text field
            if (String.isNotBlank(caseData.courseName)) {
                newCase.Learning_Course__c = caseData.courseName;
            } else if (String.isNotBlank(caseData.courseAttendanceId)) {
                try {
                    List<Course_Attendance__c> courseAttendances = [
                        SELECT Id, Learning_Course__r.Name
                        FROM Course_Attendance__c 
                        WHERE Id = :caseData.courseAttendanceId
                        LIMIT 1
                    ];
                    
                    if (!courseAttendances.isEmpty() && courseAttendances[0].Learning_Course__r != null) {
                        newCase.Learning_Course__c = courseAttendances[0].Learning_Course__r.Name;
                    }
                } catch (Exception e) {
                    System.debug('Error fetching course name: ' + e.getMessage());
                    if (String.isNotBlank(caseData.sessionKey)) {
                        newCase.Learning_Course__c = 'Selected Course';
                    }
                }
            }

            // Add Terms and Conditions data based on record type
            if (caseData.recordTypeId != null) {
                RecordType rt = [SELECT Name FROM RecordType WHERE Id = :caseData.recordTypeId LIMIT 1];
                
                if (rt.Name.toLowerCase().contains('withdrawal')) {
                    // Withdrawal specific terms and conditions
                    newCase.Terms_and_Condition__c = 'I understand that upon withdrawal, I will not be entitled to any refund of fees paid.\n\n' +
                                                    'I acknowledge that all pending dues must be cleared before withdrawal can be processed.\n\n' +
                                                    'I agree to return all institute property including ID cards, library books, and other resources.\n\n' +
                                                    'I understand that withdrawal may impact my academic record and future enrollment opportunities.\n\n' +
                                                    'I confirm that I have read and understood the withdrawal policy in its entirety.';
                } else if (rt.Name.toLowerCase().contains('leave of absence')) {
                    // LOA specific terms and conditions
                    newCase.Terms_and_Condition__c = 'I understand that my participation in the graduation ceremony will not be used by me or others to mislead or misguide any individual / placement companies or third party on my graduation status and / or claim any benefit that is permissible to only a graduate.\n\n' +
                                                    'I undertake to abide by the programme graduation requirements policy and all the terms and conditions to successfully graduate.\n\n' +
                                                    'I shall not hold ISB responsible for any liability whatsoever that may arise presently or in future.\n\n' +
                                                    'I shall refrain from posting my pictures of this graduation ceremony in any form of social media which may portray or indicate me to be a graduate.\n\n' +
                                                    'I will be graduating with the batch where I rejoined and completed my graduation requirements';
                }
            }
            
            // Validate date of absence based on reason
            if (extractedDateOfAbsence != null && String.isNotBlank(caseData.attendanceExceptionReason)) {
                String validationError = validateAttendanceExceptionDate(
                    extractedDateOfAbsence, 
                    caseData.attendanceExceptionReason
                );
                if (String.isNotBlank(validationError)) {
                    throw new AuraHandledException(validationError);
                }
            }

            // Tag active ProgramEnrollment and Academic Year onto the case
            // There is always exactly 1 active ProgramEnrollment per contact
            if (String.isNotBlank(caseData.contactId)) {
                List<ProgramEnrollment> activePEs = [
                    SELECT Id, Academic_Year__c, Academic_Year__r.Name
                    FROM ProgramEnrollment
                    WHERE ContactId = :caseData.contactId
                    AND (Status = 'Registered' OR Status = 'Active')
                    ORDER BY isActive DESC, CreatedDate DESC
                    LIMIT 1
                ];

                if (!activePEs.isEmpty()) {
                    // ** UPDATE the API names below to match your Case custom fields **
                    newCase.Program_Enrollment__c = activePEs[0].Id;              // Lookup to ProgramEnrollment

                    if (activePEs[0].Academic_Year__c != null) {
                        newCase.Academic_Year__c = activePEs[0].Academic_Year__c; // Lookup to AcademicYear
                    }

                    System.debug('Tagged ProgramEnrollment: ' + activePEs[0].Id 
                        + ' | Academic Year: ' + activePEs[0].Academic_Year__r?.Name);
                } else {
                    System.debug('No active ProgramEnrollment found for contactId: ' + caseData.contactId);
                }
            }

             Database.DMLOptions dmlOpts = new Database.DMLOptions();
            // Do NOT apply the default Case Assignment Rule for General Support > Academic > Fee Related Queries.
            // For that path, the case should stay with the creating user; no queue routing needed.
            Boolean isFeeRelatedQuery = 'Academic'.equalsIgnoreCase(caseData.subType)
                && 'Fee Related Queries'.equalsIgnoreCase(caseData.subCategory);
            if (isFeeRelatedQuery) {
                // Only set OwnerId if the label has a valid value
                if (String.isNotBlank(Label.Fee_Case_Default_Owner_Id)) {
                    try {
                        // Validate it's a proper ID format before assignment
                        Id ownerId = (Id)Label.Fee_Case_Default_Owner_Id;
                        newCase.OwnerId = ownerId;
                    } catch (Exception ex) {
                        System.debug('Invalid Fee_Case_Default_Owner_Id label value: ' + Label.Fee_Case_Default_Owner_Id);
                        // If invalid, let the default case owner assignment happen
                    }
                }
            }
            dmlOpts.assignmentRuleHeader.useDefaultRule = !isFeeRelatedQuery;
            newCase.setOptions(dmlOpts);

            insert newCase;
            return newCase.Id;
        }

    } catch (DmlException e) {
        System.debug('DML Exception: ' + e.getMessage());
        System.debug('DML Exception Fields: ' + e.getDmlFieldNames(0));
        System.debug('DML Exception Status Code: ' + e.getDmlStatusCode(0));
        
        String errorMessage = 'Database error: ';
        if (e.getDmlFieldNames(0) != null && e.getDmlFieldNames(0).size() > 0) {
            errorMessage += 'Field: ' + String.join(e.getDmlFieldNames(0), ', ') + ' - ';
        }
        errorMessage += e.getDmlMessage(0);
        system.debug('errorMessage '+ errorMessage + e.getLineNumber());
        throw new AuraHandledException(errorMessage);
        
    } catch (Exception e) {
        System.debug('General Exception: ' + e.getMessage());
        System.debug('Exception Line: ' + e.getLineNumber());
        System.debug('Exception Stack: ' + e.getStackTraceString());
        
        throw new AuraHandledException('Error creating case: ' + e.getMessage() + 
                                      ' (Line: ' + e.getLineNumber() + ')');
    }
}

// Add this method to get Return and Replace cases
@AuraEnabled(cacheable=true)
public static List<ReturnReplaceCaseWrapper> getReturnReplaceCases() {
    try {
        User currentUser = [
            SELECT ContactId 
            FROM User 
            WHERE Id = :UserInfo.getUserId() 
            LIMIT 1
        ];

        if (currentUser.ContactId == null) {
            throw new AuraHandledException('No Contact associated with this user.');
        }

        // Get cases that are eligible for Return and Replace
        // These would be approved LOA cases with specific status
        List<Case> returnReplaceCases = [
            SELECT Id, CaseNumber, LOA_Type__c, Program__r.Name, 
                   From_Term__c, To_Term__c, Subject, CreatedDate, Status
            FROM Case 
            WHERE ContactId = :currentUser.ContactId 
            AND RecordType.Name = 'Leave of Absence'
            AND Status = 'Closed'
            AND LOA_Type__c != null
            AND Program__r.Name != null
            ORDER BY CreatedDate DESC
        ];

        List<ReturnReplaceCaseWrapper> wrappedCases = new List<ReturnReplaceCaseWrapper>();
        
        for (Case c : returnReplaceCases) {
            ReturnReplaceCaseWrapper wrapper = new ReturnReplaceCaseWrapper();
            wrapper.caseId = c.Id;
            wrapper.caseNumber = c.CaseNumber;
            
            // Format the display label
            String displayLabel = '';
            
            if (c.LOA_Type__c != null) {
                displayLabel += c.LOA_Type__c;
            }
            
            if (c.Program__r != null && c.Program__r.Name != null) {
                displayLabel += ' - ' + c.Program__r.Name;
            }
            
            if (c.From_Term__c != null) {
                displayLabel += ' - ' + c.From_Term__c;
            }
            
            if (c.To_Term__c != null) {
                displayLabel += ' - ' + c.To_Term__c;
            }
            
            wrapper.displayLabel = displayLabel;
            wrapper.loaType = c.LOA_Type__c;
            wrapper.programName = c.Program__r != null ? c.Program__r.Name : '';
            wrapper.fromTerm = c.From_Term__c;
            wrapper.toTerm = c.To_Term__c;
            wrapper.subject = c.Subject;
            wrapper.status = c.Status;
            
            wrappedCases.add(wrapper);
        }

        return wrappedCases;

    } catch (Exception e) {
        throw new AuraHandledException('Error fetching return and replace cases: ' + e.getMessage());
    }
}

// Add this wrapper class
public class ReturnReplaceCaseWrapper {
    @AuraEnabled public String caseId;
    @AuraEnabled public String caseNumber;
    @AuraEnabled public String displayLabel;
    @AuraEnabled public String loaType;
    @AuraEnabled public String programName;
    @AuraEnabled public String fromTerm;
    @AuraEnabled public String toTerm;
    @AuraEnabled public String subject;
    @AuraEnabled public String status;
}

// Add this method to get courses for Return and Replace
@AuraEnabled(cacheable=true)
public static List<ReturnReplaceCourseWrapper> getReturnReplaceCourses(String contactId, String programId) {
    try {
        List<ReturnReplaceCourseWrapper> courseWrappers = new List<ReturnReplaceCourseWrapper>();
        
        // Get Program Enrollment
        List<ProgramEnrollment> programEnrollments = [
            SELECT Id 
            FROM ProgramEnrollment 
            WHERE ContactId = :contactId 
            AND ProgramId = :programId
            AND Status = 'Registered'
            LIMIT 1
        ];
        
        if (programEnrollments.isEmpty()) {
            return courseWrappers;
        }
        
        // Get Course Offering Participants for this contact
        List<CourseOfferingParticipant> participants = [
            SELECT Id, CourseOfferingId, CourseOffering.LearningCourse.Name,
                   CourseOffering.LearningCourse.Id, CourseOffering.AcademicSession.Name,
                   ParticipationStatus
            FROM CourseOfferingParticipant 
            WHERE ParticipantContactId = :contactId
            AND ParticipationStatus = 'Enrolled'
            AND CourseOffering.Program__c = :programId
            ORDER BY CourseOffering.LearningCourse.Name
        ];
        
        // Create wrapper for each course
        for (CourseOfferingParticipant cop : participants) {
            if (cop.CourseOffering != null && cop.CourseOffering.LearningCourse != null) {
                ReturnReplaceCourseWrapper wrapper = new ReturnReplaceCourseWrapper();
                wrapper.courseId = cop.CourseOffering.LearningCourse.Id;
                wrapper.courseName = cop.CourseOffering.LearningCourse.Name;
                wrapper.courseOfferingParticipantId = cop.Id;
                wrapper.academicSessionName = cop.CourseOffering.AcademicSession?.Name;
                wrapper.participationStatus = cop.ParticipationStatus;
                courseWrappers.add(wrapper);
            }
        }

        return courseWrappers;

    } catch (Exception e) {
        throw new AuraHandledException('Error fetching return and replace courses: ' + e.getMessage());
    }
}


    public class CommentWrapper {
        @AuraEnabled public String Id;
        @AuraEnabled public String CommentBody;
        @AuraEnabled public String CreatedById;
        @AuraEnabled public DateTime CreatedDate;
        @AuraEnabled public String displayName;
        @AuraEnabled public Boolean isCurrentUser;
    }

    @AuraEnabled(cacheable=true)
    public static List<CommentWrapper> getCaseComments(String caseId) {
        try {
            List<CaseComment> comments = [
                SELECT Id, CommentBody, CreatedById, CreatedBy.Name, CreatedBy.FirstName, CreatedBy.LastName, CreatedBy.Profile.Name, CreatedDate, 
                       Parent.Contact.FirstName, Parent.Contact.LastName
                FROM CaseComment 
                WHERE ParentId = :caseId 
                ORDER BY CreatedDate DESC
            ];

            List<CommentWrapper> wrappers = new List<CommentWrapper>();
            Id currentUserId = UserInfo.getUserId();

            for (CaseComment cc : comments) {
                CommentWrapper cw = new CommentWrapper();
                cw.Id = cc.Id;
                cw.CommentBody = cc.CommentBody;
                cw.CreatedById = cc.CreatedById;
                cw.CreatedDate = cc.CreatedDate;
                cw.isCurrentUser = (cc.CreatedById == currentUserId);

                String userName = '';
                if (cc.CreatedBy != null) {
                    String firstName = cc.CreatedBy.FirstName != null ? cc.CreatedBy.FirstName : '';
                    String lastName = cc.CreatedBy.LastName != null ? cc.CreatedBy.LastName : '';
                    userName = (firstName + ' ' + lastName).trim();
                    if (String.isBlank(userName) && cc.CreatedBy.Name != null) {
                        userName = cc.CreatedBy.Name;
                    }
                }
                String profileName = (cc.CreatedBy != null && cc.CreatedBy.Profile != null) ? cc.CreatedBy.Profile.Name : '';
                String name = userName;

                // Requirement: Always take contact context from Case itself for Guest and Student users
                // Student check: Profile name matches or is community plus user
                // Guest check: User name contains 'Guest'
                if (userName.toLowerCase().contains('guest') || profileName == 'Customer Community Plus User') {
                    String fName = cc.Parent.Contact.FirstName != null ? cc.Parent.Contact.FirstName : '';
                    String lName = cc.Parent.Contact.LastName != null ? cc.Parent.Contact.LastName : '';
                    String contactFullName = (fName + ' ' + lName).trim();
                    if (String.isNotBlank(contactFullName)) {
                        name = contactFullName;
                    }
                }

                cw.displayName = name;
                wrappers.add(cw);
            }
            return wrappers;
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching case comments: ' + e.getMessage());
        }
    }


@AuraEnabled
public static String addCaseComment(String caseId, String commentBody, Boolean isPublished) {
    try {
        CaseComment newComment = new CaseComment();
        newComment.ParentId = caseId;
        newComment.CommentBody = commentBody;
        newComment.IsPublished = isPublished != null ? isPublished : false;
        
        insert newComment;
        
        return newComment.Id;
    } catch (Exception e) {
        throw new AuraHandledException('Error adding comment: ' + e.getMessage());
    }
}

@AuraEnabled(cacheable=true)
public static List<CourseWrapper> getUserCoursesByAcademicSessions(String fromTermId, String toTermId,String programId) {
    try {
        User currentUser = [
            SELECT ContactId 
            FROM User 
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];

        if (currentUser.ContactId == null) {
            throw new AuraHandledException('No Contact associated with this user.');
        }

        Set<String> termIds = new Set<String>();
        if (String.isNotBlank(fromTermId)) {
            termIds.add(fromTermId);
        }
        if (String.isNotBlank(toTermId)) {
            termIds.add(toTermId);
        }

        // OLD LOGIC - via CourseOfferingParticipant
        // List<CourseOfferingParticipant> participants = [
        //     SELECT Id, 
        //             Name,
        //             CourseOfferingId,
        //             CourseOffering.LearningCourse.Name,
        //             CourseOffering.Academic_Term__c,
        //             CourseOffering.AcademicSession.Name,
        //             CourseOffering.AcademicSessionId,
        //             ParticipationStatus
        //     FROM CourseOfferingParticipant 
        //     WHERE ParticipantContactId = :currentUser.ContactId
        //     AND CourseOffering.AcademicSessionId IN :termIds
        //     AND CourseOfferingId != null
        //     AND ParticipationStatus = 'Enrolled'
        //     AND CourseOffering.Program__c = :programId
        //     ORDER BY CourseOffering.AcademicSession.Name, CourseOffering.LearningCourse.Name
        // ];

        // List<CourseWrapper> courses = new List<CourseWrapper>();
        // for (CourseOfferingParticipant cop : participants) {
        //     if (cop.CourseOffering != null && 
        //         cop.CourseOffering.LearningCourse != null && 
        //         cop.CourseOffering.LearningCourse.Name != null) {
        //         
        //         CourseWrapper course = new CourseWrapper();
        //         course.courseOfferingParticipantId = cop.Id;
        //         course.courseOfferingId = cop.CourseOfferingId;
        //         course.learningCourseName = cop.CourseOffering.LearningCourse.Name;
        //         course.academicTermName = cop.CourseOffering.AcademicSession?.Name;
        //         course.academicSessionId = cop.CourseOffering.AcademicSessionId;
        //         course.participationStatus = cop.ParticipationStatus;
        //         courses.add(course);
        //     }
        // }
        // return courses;

        List<CourseOffering> offerings = [
            SELECT Id, 
                   LearningCourse.Name,
                   Academic_Term__c,
                   AcademicSession.Name,
                   AcademicSessionId
            FROM CourseOffering 
            WHERE AcademicSessionId IN :termIds
            AND Program__c = :programId
            AND IsActive = true
            ORDER BY AcademicSession.Name, LearningCourse.Name
        ];

        List<CourseWrapper> courses = new List<CourseWrapper>();
        for (CourseOffering co : offerings) {
            if (co.LearningCourse != null && co.LearningCourse.Name != null) {
                
                CourseWrapper course = new CourseWrapper();
                course.courseOfferingParticipantId = ''; // Not applicable when querying CourseOffering directly
                course.courseOfferingId = co.Id;
                course.learningCourseName = co.LearningCourse.Name;
                course.academicTermName = co.AcademicSession?.Name;
                course.academicSessionId = co.AcademicSessionId;
                course.participationStatus = 'Not Enrolled';
                courses.add(course);
            }
        }

        return courses;

    } catch (Exception e) {
        throw new AuraHandledException('Error fetching user courses by academic sessions: ' + e.getMessage());
    }
}


@AuraEnabled(cacheable=true)
public static Map<String, String> getStatusLabelMapping() {
    try {
        Map<String, String> statusLabelMap = new Map<String, String>();

        // Define your custom mapping with hardcoded values
        statusLabelMap.put('Draft', 'Draft');
        statusLabelMap.put('Submitted', 'Submitted');
        statusLabelMap.put('In Progress', 'In Progress');
        statusLabelMap.put('Approved', 'Approved');
        statusLabelMap.put('Approved11', 'Approved-Pending T&C'); // Hardcoded fix
        statusLabelMap.put('T&C Accepted', 'T&C Accepted');
        statusLabelMap.put('T & C Rejected', 'T & C Rejected');
        statusLabelMap.put('Closed', 'Closed');
        statusLabelMap.put('Rejected', 'Rejected');
        
        // You can also keep the dynamic part for other values
        Schema.DescribeFieldResult fieldResult = Case.Status.getDescribe();
        List<Schema.PicklistEntry> picklistEntries = fieldResult.getPicklistValues();
        
        for (Schema.PicklistEntry entry : picklistEntries) {
            if (entry.isActive() && !statusLabelMap.containsKey(entry.getValue())) {
                // Only add if not already in our hardcoded map
                statusLabelMap.put(entry.getValue(), entry.getLabel());
            }
        }
        
        return statusLabelMap;
    } catch (Exception e) {
        throw new AuraHandledException('Error fetching status label mapping: ' + e.getMessage());
    }
}

@AuraEnabled(cacheable=true)
public static List<RejoinCaseWrapper> getRejoinCases() {
    try {
        User currentUser = [
            SELECT ContactId 
            FROM User 
            WHERE Id = :UserInfo.getUserId() 
            LIMIT 1
        ];

        if (currentUser.ContactId == null) {
            throw new AuraHandledException('No Contact associated with this user.');
        }

        // Get cases that are eligible for Rejoin (approved LOA cases)
        List<Case> rejoinCases = [
            SELECT Id, CaseNumber, LOA_Type__c, Program__r.Name, 
                   From_Term__c, To_Term__c, Subject, CreatedDate, Status,
                   Completed_Term__c, Program__c  // Added these fields
            FROM Case 
            WHERE ContactId = :currentUser.ContactId 
            AND RecordType.Name = 'Leave of Absence'
            AND Status = 'Closed'  // Or whatever status indicates approved/completed LOA
            //AND LOA_Type__c != null
            AND Program__r.Name != null
            ORDER BY CreatedDate DESC
        ];
        List<RejoinCaseWrapper> wrappedCases = new List<RejoinCaseWrapper>();
        
        for (Case c : rejoinCases) {
            RejoinCaseWrapper wrapper = new RejoinCaseWrapper();
            wrapper.caseId = c.Id;
            wrapper.caseNumber = c.CaseNumber;
            
            // Format the display label as: "LOA Type - Program - From Term - To Term"
            String displayLabel = '';
            
            if (c.LOA_Type__c != null) {
                displayLabel += c.LOA_Type__c;
            }
            
            if (c.Program__r != null && c.Program__r.Name != null) {
                displayLabel += ' - ' + c.Program__r.Name;
            }
            
            if (c.From_Term__c != null) {
                displayLabel += ' - ' + c.From_Term__c;
            }
            
            if (c.To_Term__c != null) {
                displayLabel += ' - ' + c.To_Term__c;
            }
            
            wrapper.displayLabel = displayLabel;
            wrapper.loaType = c.LOA_Type__c;
            wrapper.programName = c.Program__r != null ? c.Program__r.Name : '';
            wrapper.fromTerm = c.From_Term__c;
            wrapper.toTerm = c.To_Term__c;
            wrapper.subject = c.Subject;
            
            wrappedCases.add(wrapper);
        }

        return wrappedCases;

    } catch (Exception e) {
        throw new AuraHandledException('Error fetching rejoin cases: ' + e.getMessage());
    }
}

@AuraEnabled(cacheable=true)
public static TermValidationResult validateTermOverlap(
    String contactId, 
    String recordTypeId, 
    String fromTermId,
    String toTermId,
    String programId
) {
    try {
        TermValidationResult validationResult = new TermValidationResult();
        validationResult.isValid = true;
        validationResult.message = '';
        validationResult.overlappingCases = new List<OverlappingCaseInfo>();
        
        if (String.isBlank(contactId) || String.isBlank(fromTermId) || String.isBlank(toTermId)) {
            validationResult.isValid = true;
            return validationResult;
        }
        
        // Get AcademicSession names from IDs
        AcademicSession fromTerm = [SELECT Id, Name FROM AcademicSession WHERE Id = :fromTermId LIMIT 1];
        AcademicSession toTerm = [SELECT Id, Name FROM AcademicSession WHERE Id = :toTermId LIMIT 1];
        
        String fromTermName = fromTerm.Name;
        String toTermName = toTerm.Name;
        
        List<Case> existingCases = [
            SELECT Id, CaseNumber, From_Term__c, To_Term__c, Status, 
                   Program__c, Program__r.Name, CreatedDate
            FROM Case 
            WHERE ContactId = :contactId
            AND RecordTypeId = :recordTypeId
            AND From_Term__c != null
            AND To_Term__c != null
            AND IsClosed = false
            AND Status != 'Rejected'
            ORDER BY CreatedDate DESC
        ];
        
        if (existingCases.isEmpty()) {
            validationResult.message = 'No term overlap detected.';
            return validationResult;
        }
        
        // Get all academic sessions for the program to build ordering
        List<AcademicSession> programSessions = new List<AcademicSession>();
        if (String.isNotBlank(programId)) {
            programSessions = [
                SELECT Id, Name 
                FROM AcademicSession 
                WHERE AcademicTerm.Program__c = :programId
                ORDER BY AcademicTerm.StartDate, Name
            ];
        }
        
        // Build term name to order mapping
        Map<String, Integer> termOrderMap = new Map<String, Integer>();
        for (Integer i = 0; i < programSessions.size(); i++) {
            termOrderMap.put(programSessions[i].Name, i);
        }
        
        // Check if fromTermName and toTermName exist in the order map
        Integer fromTermOrder = termOrderMap.get(fromTermName);
        Integer toTermOrder = termOrderMap.get(toTermName);
        
        // If we can't find term order, skip detailed overlap checking
        if (fromTermOrder == null || toTermOrder == null) {
            validationResult.isValid = true;
            validationResult.message = 'Unable to validate term ordering. Terms not found in program sessions.';
            return validationResult;
        }
        
        List<OverlappingCaseInfo> overlappingCases = new List<OverlappingCaseInfo>();
        
        for (Case existingCase : existingCases) {
            String existingFromTerm = existingCase.From_Term__c;
            String existingToTerm = existingCase.To_Term__c;
            
            // Get order positions for existing case terms
            Integer existingFromOrder = termOrderMap.get(existingFromTerm);
            Integer existingToOrder = termOrderMap.get(existingToTerm);
            
            // Skip if we can't find ordering for existing terms
            if (existingFromOrder == null || existingToOrder == null) {
                continue;
            }
            
            // Check for overlap scenarios
            boolean isOverlapping = false;
            String overlapType = '';
            
            // Scenario 1: New request starts within existing range
            if (fromTermOrder >= existingFromOrder && fromTermOrder <= existingToOrder) {
                isOverlapping = true;
                overlapType = 'start';
            }
            // Scenario 2: New request ends within existing range
            else if (toTermOrder >= existingFromOrder && toTermOrder <= existingToOrder) {
                isOverlapping = true;
                overlapType = 'end';
            }
            // Scenario 3: New request completely contains existing range
            else if (fromTermOrder <= existingFromOrder && toTermOrder >= existingToOrder) {
                isOverlapping = true;
                overlapType = 'contains';
            }
            // Scenario 4: New request is completely within existing range
            else if (fromTermOrder >= existingFromOrder && toTermOrder <= existingToOrder) {
                isOverlapping = true;
                overlapType = 'within';
            }
            
            if (isOverlapping) {
                OverlappingCaseInfo overlapInfo = new OverlappingCaseInfo();
                overlapInfo.caseId = existingCase.Id;
                overlapInfo.caseNumber = existingCase.CaseNumber;
                overlapInfo.existingFromTerm = existingFromTerm;
                overlapInfo.existingToTerm = existingToTerm;
                overlapInfo.status = existingCase.Status;
                overlapInfo.programName = existingCase.Program__r?.Name;
                overlapInfo.overlapType = overlapType;
                
                overlappingCases.add(overlapInfo);
            }
        }
        
        if (!overlappingCases.isEmpty()) {
            validationResult.isValid = false;
            validationResult.overlappingCases = overlappingCases;
            
            // Build informative message
            List<String> conflictMessages = new List<String>();
            for (OverlappingCaseInfo overlap : overlappingCases) {
                String conflictMsg = 'Case ' + overlap.caseNumber + ': ' + 
                                    overlap.existingFromTerm + ' to ' + overlap.existingToTerm + 
                                    ' (' + overlap.status + ')';
                
                if (overlap.overlapType == 'within') {
                    conflictMsg += ' - Your selected terms fall completely within this existing case range.';
                } else if (overlap.overlapType == 'contains') {
                    conflictMsg += ' - Your selected terms completely contain this existing case range.';
                } else if (overlap.overlapType == 'start') {
                    conflictMsg += ' - Your From Term (' + fromTermName + ') falls within this existing case range.';
                } else if (overlap.overlapType == 'end') {
                    conflictMsg += ' - Your To Term (' + toTermName + ') falls within this existing case range.';
                } else if (overlap.overlapType == 'partial') {
                    conflictMsg += ' - Your terms partially overlap with this existing case range.';
                }
                
                conflictMessages.add(conflictMsg);
            }
            
            validationResult.message = 'Term overlap detected with existing case(s):\n' + 
                            String.join(conflictMessages, '\n') + 
                            '\n\nPlease select terms that do not overlap with existing requests.';
        } else {
            validationResult.message = 'No term overlap detected.';
        }
        
        return validationResult;
        
    } catch (Exception e) {
        // Create a new result object on error
        TermValidationResult errorResult = new TermValidationResult();
        errorResult.isValid = true; // Allow submission if validation fails
        errorResult.message = 'Validation error: ' + e.getMessage();
        System.debug('Validation error: ' + e.getStackTraceString());
        return errorResult;
    }
}
@AuraEnabled(cacheable=true)
    public static Boolean isRejoinCasePresent(Id caseId) {
        if (caseId == null) return false;

        Integer cnt = [
            SELECT COUNT()
            FROM Case
            WHERE ParentId = :caseId
            AND RecordType.DeveloperName = 'Rejoin'
        ];

        return cnt > 0;
    }

// Add these wrapper classes at the END of your controller class (outside all methods)
public class TermValidationResult {
    @AuraEnabled public Boolean isValid;
    @AuraEnabled public String message;
    @AuraEnabled public List<OverlappingCaseInfo> overlappingCases;
}

public class OverlappingCaseInfo {
    @AuraEnabled public String caseId;
    @AuraEnabled public String caseNumber;
    @AuraEnabled public String existingFromTerm;
    @AuraEnabled public String existingToTerm;
    @AuraEnabled public String status;
    @AuraEnabled public String programName;
    @AuraEnabled public String overlapType;
}

// Add this wrapper class inside your controller class
public class RejoinCaseWrapper {
    @AuraEnabled public String caseId;
    @AuraEnabled public String caseNumber;
    @AuraEnabled public String displayLabel;
    @AuraEnabled public String loaType;
    @AuraEnabled public String programName;
    @AuraEnabled public String fromTerm;
    @AuraEnabled public String toTerm;
    @AuraEnabled public String subject;
}
// Wrapper Classes
public class FileUploadWrapper {
    @AuraEnabled public String fileName { get; set; }
    @AuraEnabled public String base64Data { get; set; }
    @AuraEnabled public String contentType { get; set; }
}
// Add this wrapper class
public class ReturnReplaceCourseWrapper {
    @AuraEnabled public String courseId;
    @AuraEnabled public String courseName;
    @AuraEnabled public String courseOfferingParticipantId;
    @AuraEnabled public String academicSessionName;
    @AuraEnabled public String participationStatus;
}

public class FileWrapper {
    @AuraEnabled public String contentDocumentId;
    @AuraEnabled public String contentVersionId;
    @AuraEnabled public String title;
    @AuraEnabled public String fileType;
    @AuraEnabled public String fileExtension;
    @AuraEnabled public Integer contentSize;
    @AuraEnabled public Datetime uploadedDate;
}

// Add this wrapper class
public class AcademicTermWrapper {
    @AuraEnabled public String id;
    @AuraEnabled public String name;
    @AuraEnabled public DateTime startDate;
    @AuraEnabled public DateTime endDate;
    @AuraEnabled public String formattedDateRange;
}

public class UserAccountContactInfo {
    @AuraEnabled public String contactId;
    @AuraEnabled public String accountId;
    @AuraEnabled public String accountName;
    @AuraEnabled public String email;
    @AuraEnabled public String phone;
    @AuraEnabled public String contactName;
    @AuraEnabled public String mailingStreet;
    @AuraEnabled public String mailingCity;
    @AuraEnabled public String mailingState;
    @AuraEnabled public String mailingPostalCode;
    @AuraEnabled public String mailingCountry;
    @AuraEnabled public String pgid;
    @AuraEnabled public string academicYear;
    @AuraEnabled public string currentAcademicTerm;
}
public class CourseAttendanceWrapper {
    @AuraEnabled public String courseId;
    @AuraEnabled public String courseName;
    @AuraEnabled public String courseAttendanceId;
    @AuraEnabled public List<SessionAttendanceWrapper> sessions;
}

public class SessionAttendanceWrapper {
    @AuraEnabled public String sessionId;
    @AuraEnabled public String sessionName;
    @AuraEnabled public String sessionKey;
    @AuraEnabled public String courseAttendanceId;
    @AuraEnabled public String courseName;  // Added field
    @AuraEnabled public Date dateOfSession; // Added field
    @AuraEnabled public String timeOfSession; // Added field
}
public class ProgramWrapper {
    @AuraEnabled public String id;
    @AuraEnabled public String name;
    @AuraEnabled public String programId; // Add this
    @AuraEnabled public String academicTermName; // Add this

    public ProgramWrapper(String id, String name) {
        this.id = id;
        this.name = name;
        this.programId = id; // Ensure programId is populated
    }
}

public class AcademicSessionWrapper {
    @AuraEnabled public String id;
    @AuraEnabled public String name;
    @AuraEnabled public DateTime termStartDate;
    @AuraEnabled public String termName;
    
    // Keep old constructor for backward compatibility
    public AcademicSessionWrapper(String id, String name) {
        this.id = id;
        this.name = name;
    }
    
    // Add default constructor
    public AcademicSessionWrapper() {}
}

public class PicklistValue {
    @AuraEnabled public String label;
    @AuraEnabled public String value;
}

public class ValidationResult {
    @AuraEnabled public Boolean isValid;
    @AuraEnabled public String message;
}

public class CourseWrapper {
    @AuraEnabled public String courseOfferingParticipantId;
    @AuraEnabled public String courseOfferingId;
    @AuraEnabled public String learningCourseName;
    @AuraEnabled public String academicTermName;
    @AuraEnabled public String participationStatus;
    @AuraEnabled public String academicSessionId;
}
public class CaseDataWrapper {
 @AuraEnabled public String wellbeingSeverity { get; set; }
    @AuraEnabled public String wellbeingModeOfInteraction { get; set; }
    @AuraEnabled public String wellbeingType { get; set; }
    @AuraEnabled public String wellbeingActionTaken { get; set; }
@AuraEnabled public String caseId { get; set; }
@AuraEnabled public String accountHolderName { get; set; }
@AuraEnabled public String accountNumber { get; set; }
@AuraEnabled public String ifscCode { get; set; }
@AuraEnabled public String bankName { get; set; }
@AuraEnabled public String branchName { get; set; }

@AuraEnabled public String contactId { get; set; }
@AuraEnabled public String termsAndConditionsData { get; set; }
@AuraEnabled public String accountId { get; set; }
@AuraEnabled public String subject { get; set; }
@AuraEnabled public String description { get; set; }
@AuraEnabled public String caseType { get; set; }
@AuraEnabled public String programId { get; set; }
@AuraEnabled public String fromTermId { get; set; }
@AuraEnabled public String toTermId { get; set; }
@AuraEnabled public String contactEmail { get; set; }
@AuraEnabled public String contactPhone { get; set; }
@AuraEnabled public String contactMobile { get; set; }
@AuraEnabled public String ownerId { get; set; }
@AuraEnabled public String ownerName { get; set; }
@AuraEnabled public String recordTypeId { get; set; }
@AuraEnabled public String parentId { get; set; }
@AuraEnabled public String loaType { get; set; }
@AuraEnabled public String subType { get; set; }
@AuraEnabled public String subCategory { get; set; }
@AuraEnabled public String documentType { get; set; }
@AuraEnabled public String deliveryMode { get; set; }
@AuraEnabled public String requestedEndDate { get; set; }
@AuraEnabled public String dispatchAddress { get; set; }
@AuraEnabled public String passportNumber { get; set; }
@AuraEnabled public String passportExpiry { get; set; }
@AuraEnabled public String travelStartDate { get; set; }
@AuraEnabled public String travelEndDate { get; set; }
@AuraEnabled public String visaType { get; set; }
@AuraEnabled public String visaPurpose { get; set; }
@AuraEnabled public String requestedLegalName { get; set; }
@AuraEnabled public String nameChangeReason { get; set; }
@AuraEnabled public String eventTitle { get; set; }
@AuraEnabled public String eventProposedDateTime { get; set; }
@AuraEnabled public String eventVenue { get; set; }
@AuraEnabled public String eventHostBody { get; set; }
@AuraEnabled public String eventExpectedHeadcount { get; set; }
@AuraEnabled public String eventBudgetAsk { get; set; }
@AuraEnabled public String eventContacts { get; set; }
@AuraEnabled public String alternateEmail { get; set; }
@AuraEnabled public String alternatePhone { get; set; }
@AuraEnabled public String attendanceExceptionReason { get; set; }
@AuraEnabled public String courseAttendanceId { get; set; }
@AuraEnabled public String sessionAttendanceId { get; set; }
@AuraEnabled public String sessionKey { get; set; }
@AuraEnabled public String dateOfAbsence { get; set; }
@AuraEnabled public String sessionName { get; set; }
@AuraEnabled public String courseName { get; set; }
@AuraEnabled public String cohortId { get; set; }  // Add this field
@AuraEnabled public String selectedReturnReplaceCourseId { get; set; }
// // Add these to your CaseDataWrapper class
// @AuraEnabled public String severity { get; set; }
// @AuraEnabled public String modeOfInteraction { get; set; }
// @AuraEnabled public String typeField { get; set; }
// @AuraEnabled public String actionTaken { get; set; }
    @AuraEnabled public String currentAcademicTerm { get; set; }
}
}