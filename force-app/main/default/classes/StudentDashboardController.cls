public without sharing class StudentDashboardController {
    
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getStudentDashboardData() {
        Map<String, Object> dashboardData = new Map<String, Object>();
        
        try {
            // Get current user's contact
            User currentUser = getCurrentUser();
            if (currentUser.ContactId == null) {
                throw new AuraHandledException('No Contact record found for current user');
            }
            
            // Get Contact details
            Contact studentContact = getStudentContact(currentUser.ContactId);
            Boolean isPgpylStudent = isPgpylProgram(studentContact.Current_Program__c);
            
            // Build dashboard data
            dashboardData.put('profile', buildProfileData(studentContact));
            dashboardData.put('isPgpylStudent', isPgpylStudent);

            if (!isPgpylStudent) {
                dashboardData.put('program', buildProgramData(studentContact.Id));
                dashboardData.put('tasks', buildTasksData());
                dashboardData.put('cases', buildCasesData(studentContact.Id));
                dashboardData.put('attendance', buildAttendanceSummary(studentContact.Id));
            }
            
            return dashboardData;
            
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching dashboard data: ' + e.getMessage());
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getDetailedAttendanceData(Id contactId) {
        Map<String, Object> attendanceData = new Map<String, Object>();
        
        try {
            System.debug('=== getDetailedAttendanceData START ===');
            if (contactId == null) {
                User currentUser = getCurrentUser();
                contactId = currentUser.ContactId;
            }
            
            if (contactId == null) {
                throw new AuraHandledException('No Student Contact found for current user context.');
            }
            
            Contact currentContact = [SELECT Id, Name, Email FROM Contact WHERE Id = :contactId LIMIT 1];
            System.debug('Contact: ' + currentContact.Name + ' (' + contactId + ')');
            
            // 1. Get ALL Course Attendance for this contact - No filtering by Term Status yet
            List<Course_Attendance__c> sessionRecords = [
                SELECT Id, Status__c, Course_Offering__c, Course_Offering__r.Name,
                       Course_Offering__r.LearningCourse.Name, Course_Offering__r.AcademicSession.Name,
                       Course_Offering__r.Academic_Term__c,
                       Academic_Session_Name__c, Academic_Term_Name__c, Program_Name__c,
                       CreatedDate
                FROM Course_Attendance__c
                WHERE Contact__c = :contactId
                ORDER BY CreatedDate DESC, Course_Offering__r.Name ASC
            ];
            
            System.debug('Total attendance records found: ' + sessionRecords.size());
            
            if (sessionRecords.isEmpty()) {
                // Secondary check: search by email just in case the link is via a different contact record
                String studentEmail = currentContact.Email;
                if (String.isNotBlank(studentEmail)) {
                    sessionRecords = [
                        SELECT Id, Status__c, Course_Offering__c, Course_Offering__r.Name,
                               Course_Offering__r.LearningCourse.Name, Course_Offering__r.AcademicSession.Name,
                               Course_Offering__r.Academic_Term__c,
                               Academic_Session_Name__c, Academic_Term_Name__c, Program_Name__c,
                               CreatedDate
                        FROM Course_Attendance__c
                        WHERE Contact__r.Email = :studentEmail
                        ORDER BY CreatedDate DESC
                    ];
                    System.debug('Attendance records found via email fallback: ' + sessionRecords.size());
                }
            }
            
            // 2. Identify relevant Terms from Enrollment Sessions for metadata
            List<Enrollment_Session__c> registeredSessions = [
                SELECT Academic_Session__c, Academic_Session__r.Name
                FROM Enrollment_Session__c
                WHERE Program_Enrollment__r.ContactId = :contactId
            ];
            
            // Group sessions by Course Offering and Academic Session
            Map<String, List<Course_Attendance__c>> groupedSessions = groupSessionsByOffering(sessionRecords);
            
            // Process and calculate attendance per course offering
            attendanceData.put('records', processGroupedSessions(groupedSessions));
            attendanceData.put('summary', calculateDetailedSummary(sessionRecords));
            attendanceData.put('termGroups', groupByTerm(sessionRecords));
            attendanceData.put('debugInfo', new Map<String, Object>{
                'contactName' => currentContact.Name,
                'recordsFound' => sessionRecords.size(),
                'termsFound' => registeredSessions.size()
            });
            
            System.debug('=== getDetailedAttendanceData END ===');
            return attendanceData;
            
        } catch (Exception e) {
            System.debug('ERROR in getDetailedAttendanceData: ' + e.getMessage());
            throw new AuraHandledException('Error fetching detailed attendance: ' + e.getMessage());
        }
    }

    // Helper Methods (Re-activated and restored)

    // Group sessions by Course Offering and Academic Session
    private static Map<String, List<Course_Attendance__c>> groupSessionsByOffering(List<Course_Attendance__c> sessions) {
        System.debug('=== groupSessionsByOffering START ===');
        Map<String, List<Course_Attendance__c>> groupedMap = new Map<String, List<Course_Attendance__c>>();
        
        for (Course_Attendance__c session : sessions) {
            String termName = session.Academic_Session_Name__c;
            if (String.isBlank(termName)) {
                termName = session.Course_Offering__r?.AcademicSession?.Name;
            }
            if (String.isBlank(termName)) {
                termName = 'No Session';
            }
            
            String key = session.Course_Offering__c + '_' + termName;
            if (!groupedMap.containsKey(key)) {
                groupedMap.put(key, new List<Course_Attendance__c>());
            }
            groupedMap.get(key).add(session);
        }
        return groupedMap;
    }
    
    // Process grouped sessions to calculate attendance per course offering
    private static List<Map<String, Object>> processGroupedSessions(Map<String, List<Course_Attendance__c>> groupedSessions) {
        List<Map<String, Object>> processedRecords = new List<Map<String, Object>>();
        
        for (String key : groupedSessions.keySet()) {
            List<Course_Attendance__c> sessions = groupedSessions.get(key);
            if (sessions.isEmpty()) continue;
            
            // Get course offering details from first session
            Course_Attendance__c firstSession = sessions[0];
            
            Integer totalScheduled = sessions.size();
            Integer totalAttended = 0;
            Date lastAttendanceDate = null;
            
            for (Course_Attendance__c session : sessions) {
                if (session.Status__c == 'Present') {
                    totalAttended++;
                    if (lastAttendanceDate == null || session.CreatedDate.date() > lastAttendanceDate) {
                        lastAttendanceDate = session.CreatedDate.date();
                    }
                }
            }
            
            Decimal percentage = totalScheduled > 0 ? ((Decimal)totalAttended / totalScheduled * 100).setScale(2) : 0;
            
            String statusClass = 'status-excellent';
            if (percentage < 50) {
                statusClass = 'status-critical';
            } else if (percentage < 75) {
                statusClass = 'status-warning';
            }
            
            // Try to get Learning Course Name, fallback to Course Offering Name
            String learningCourseName = firstSession.Course_Offering__r?.LearningCourse.Name;
            String displayName = String.isNotBlank(learningCourseName) ? learningCourseName : firstSession.Course_Offering__r?.Name;
            
            String termName = firstSession.Academic_Session_Name__c;
            if (String.isBlank(termName)) {
                termName = firstSession.Course_Offering__r?.AcademicSession?.Name;
            }
            
            processedRecords.add(new Map<String, Object>{
                'id' => firstSession.Course_Offering__c != null ? (Object)firstSession.Course_Offering__c : (Object)firstSession.Id,
                'courseName' => displayName != null ? displayName : 'N/A',
                'academicTerm' => firstSession.Academic_Term_Name__c,
                'academicSession' => termName != null ? termName : 'N/A',
                'programName' => firstSession.Program_Name__c,
                'classesScheduled' => totalScheduled,
                'classesAttended' => totalAttended,
                'classesExcused' => 0,
                'percentage' => percentage,
                'statusClass' => statusClass,
                'attendanceRatio' => totalAttended + '/' + totalScheduled,
                'lastAttendanceDate' => lastAttendanceDate != null ? lastAttendanceDate.format() : 'N/A'
            });
        }
        return processedRecords;
    }
    
    private static Map<String, Object> calculateDetailedSummary(List<Course_Attendance__c> sessionRecords) {
        // Group sessions to count unique course offerings
        Set<String> uniqueCourseOfferings = new Set<String>();
        Integer totalScheduled = sessionRecords.size();
        Integer totalAttended = 0;
        
        for (Course_Attendance__c session : sessionRecords) {
            String key = session.Course_Offering__c + '_' + session.Academic_Session_Name__c;
            uniqueCourseOfferings.add(key);
            
            if (session.Status__c == 'Present') {
                totalAttended++;
            }
        }
        
        Decimal overallPercentage = totalScheduled > 0 ? ((Decimal)totalAttended / totalScheduled * 100).setScale(2) : 0;
        
        return new Map<String, Object>{
            'totalCourses' => uniqueCourseOfferings.size(),
            'totalScheduled' => totalScheduled,
            'totalAttended' => totalAttended,
            'totalExcused' => 0,
            'overallPercentage' => overallPercentage,
            'attendanceRatio' => totalAttended + '/' + totalScheduled
        };
    }
    
    private static List<Map<String, Object>> groupByTerm(List<Course_Attendance__c> sessionRecords) {
        Map<String, Set<String>> termCourseMap = new Map<String, Set<String>>();
        // Using TreeMap to sort terms? Can't easily in Apex without comparable. 
        // We rely on the initial query order or just map order (unpredictable).
        
        for (Course_Attendance__c session : sessionRecords) {
            String term = session.Academic_Session_Name__c;
            if (String.isBlank(term)) {
                term = session.Course_Offering__r?.AcademicSession?.Name;
            }
            if (String.isBlank(term)) {
                term = 'No Session';
            }
            
            String courseKey = session.Course_Offering__c + '_' + term;
            
            if (!termCourseMap.containsKey(term)) {
                termCourseMap.put(term, new Set<String>());
            }
            termCourseMap.get(term).add(courseKey);
        }
        
        List<Map<String, Object>> termGroups = new List<Map<String, Object>>();
        for (String term : termCourseMap.keySet()) {
            // Need to get the course attendance Objects for this term
            // This method just returns counts in the previous version, 
            // but the LWC does the mapping via 'groupedByTerm' getter using the flat list.
            // Wait, looking at the JS:
            // "groupedByTerm" getter in JS iterates "attendanceRecords".
            // "attendanceRecords" is filled with "processedRecords".
            // So we don't strictly need detail in termGroups unless JS uses it?
            // JS: this.termGroups = data.termGroups || [];
            // BUT JS getter: "groupedByTerm" uses this.attendanceRecords. It does NOT use this.termGroups.
            // So this method is likely just for summary or unused by the new JS logic?
            // Ah, checking JS:
            // The JS calculates grouping itself:
            // const termMap = new Map(); this.attendanceRecords.forEach...
            // So the Apex groupByTerm might be redundant or used for something else?
            // Original code had it. Let's keep it consistent.
            
            termGroups.add(new Map<String, Object>{
                'termName' => term,
                'courseCount' => termCourseMap.get(term).size()
            });
        }
        
        return termGroups;
    }


    // Missing Helper Methods
    private static User getCurrentUser() {
        return [
            SELECT Id, ContactId, Name, Email, Phone 
            FROM User 
            WHERE Id = :UserInfo.getUserId() 
            LIMIT 1
        ];
    }
    
    private static Contact getStudentContact(Id contactId) {
        return [
            SELECT Id, Name, Email, MobilePhone, Current_Program__c
            FROM Contact 
            WHERE Id = :contactId 
            LIMIT 1
        ];
    }
    
    private static Map<String, Object> buildProfileData(Contact student) {
        return new Map<String, Object>{
            'recordId' => student.Id,
            'name' => student.Name,
            'email' => student.Email,
            'phone' => student.MobilePhone,
            'currentProgram' => student.Current_Program__c
        };
    }

    private static Boolean isPgpylProgram(String currentProgram) {
        return String.isNotBlank(currentProgram)
            && currentProgram.toUpperCase().contains('PGPYL');
    }
    
    private static Map<String, Object> buildProgramData(Id contactId) {
        List<ProgramEnrollment> enrollments = [
            SELECT Id,
                Name,
                Program.Name,
                Status,
                Primary_Advisor__r.Name
            FROM ProgramEnrollment 
            WHERE ContactId = :contactId 
            AND Status = 'Registered'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
    
        if (enrollments.isEmpty()) {
            return new Map<String, Object>();
        }
    
        ProgramEnrollment enrollment = enrollments[0];
        return new Map<String, Object>{
            'recordId' => enrollment.Id,
            'name' => enrollment.Program?.Name,
            'cohort' => 'Current',
            'status' => enrollment.Status,
            'primaryAdvisor' => enrollment.Primary_Advisor__r != null ? enrollment.Primary_Advisor__r.Name : ''
        };
    }
    
    private static Map<String, Object> buildTasksData() {
        Integer openCount = [
            SELECT COUNT() 
            FROM Task 
            WHERE OwnerId = :UserInfo.getUserId() 
            AND IsClosed = false
        ];
        
        return new Map<String, Object>{ 'openCount' => openCount };
    }
    
    private static Map<String, Object> buildCasesData(Id contactId) {
        List<Case> openCases = [
            SELECT Id, Subject 
            FROM Case 
            WHERE ContactId = :contactId 
            AND IsClosed = false
            ORDER BY CreatedDate DESC
        ];
        
        return new Map<String, Object>{
            'openCount' => openCases.size(),
            'recentSubject' => openCases.isEmpty() ? '' : openCases[0].Subject
        };
    }
    
    private static Map<String, Object> buildAttendanceSummary(Id contactId) {
        System.debug('=== buildAttendanceSummary START (Direct Calculation) ===');
        System.debug('Contact ID: ' + contactId);

        // Query Course_Attendance__c records directly — no reliance on Enrollment_Session fields
        List<Course_Attendance__c> attendanceRecords = [
            SELECT Id, Status__c, CreatedDate
            FROM Course_Attendance__c
            WHERE Contact__c = :contactId
        ];

        System.debug('Total Course_Attendance records found: ' + attendanceRecords.size());

        Integer totalScheduled = attendanceRecords.size();
        Integer totalAttended  = 0;
        Date    lastUpdatedDate = null;

        for (Course_Attendance__c rec : attendanceRecords) {
            if (rec.Status__c == 'Present') {
                totalAttended++;
                Date recDate = rec.CreatedDate.date();
                if (lastUpdatedDate == null || recDate > lastUpdatedDate) {
                    lastUpdatedDate = recDate;
                }
            }
        }

        // Calculate percentage directly from raw counts
        Decimal percentage = totalScheduled > 0
            ? ((Decimal) totalAttended / totalScheduled * 100).setScale(2)
            : 0;

        String lastUpdatedStr = lastUpdatedDate != null
            ? lastUpdatedDate.format()
            : System.now().format('MMM dd, yyyy');

        System.debug('Direct Calculation — Scheduled: ' + totalScheduled
            + ', Attended: ' + totalAttended
            + ', Percentage: ' + percentage);
        System.debug('=== buildAttendanceSummary END ===');

        return new Map<String, Object>{
            'percentage'     => percentage,
            'totalScheduled' => totalScheduled,
            'totalAttended'  => totalAttended,
            'lastUpdated'    => lastUpdatedStr
        };
    }
}