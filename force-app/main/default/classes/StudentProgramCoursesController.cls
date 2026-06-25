public without sharing class StudentProgramCoursesController {
    
    /**
     * Get program enrollments for the current user
     * Prioritizes 'Registered' status enrollments
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getProgramEnrollments() {
        try {
            User currentUser = [
                SELECT Id, ContactId 
                FROM User 
                WHERE Id = :UserInfo.getUserId() 
                LIMIT 1
            ];
            
            if (currentUser.ContactId == null) {
                throw new AuraHandledException('No Contact record found for current user');
            }
            
            List<ProgramEnrollment> allEnrollments = [
                SELECT Id, Name, Program.Name, Status,
                       CreatedDate, StartDate, EndDate,
                       Academic_Year__c, Academic_Year__r.Name, CGPA__c,
                       Core_CGPA__c, Elective_CGPA__c,Pre_Term__c
                FROM ProgramEnrollment
                WHERE ContactId = :currentUser.ContactId
                ORDER BY Status DESC, CreatedDate DESC
            ];
            
            List<Map<String, Object>> currentEnrollments = new List<Map<String, Object>>();
            List<Map<String, Object>> previousEnrollments = new List<Map<String, Object>>();
            
            for (ProgramEnrollment enrollment : allEnrollments) {
                Map<String, Object> enrollmentData = new Map<String, Object>{
                    'id' => enrollment.Id,
                    'name' => enrollment.Name,
                    'programName' => enrollment.Program?.Name,
                    'status' => enrollment.Status,
                    'academicYear' => enrollment.Academic_Year__r.name,
                    'cgpa' => enrollment.CGPA__c,
                    'coreCgpa' => enrollment.Core_CGPA__c,
                    'electiveCgpa' => enrollment.Elective_CGPA__c,
                    'preTermStatus' => enrollment.Pre_Term__c
                    //'startDate' => enrollment.StartDate,
                    //'endDate' => enrollment.EndDate
                };
                
                if (enrollment.Status == 'Registered') {
                    currentEnrollments.add(enrollmentData);
                } else {
                    previousEnrollments.add(enrollmentData);
                }
            }
            
            return new Map<String, Object>{
                'currentEnrollments' => currentEnrollments,
                'previousEnrollments' => previousEnrollments,
                'totalCount' => allEnrollments.size()
            };
            
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching program enrollments: ' + e.getMessage());
        }
    }
    
    /**
     * Get enrollment sessions for a specific program enrollment
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getEnrollmentSessions(Id programEnrollmentId) {
        try {
            List<Enrollment_Session__c> sessions = [
                SELECT Id, Name, Academic_Session__r.Name, Status__c,
                       Program_Enrollment__c,
                       Attended_Sessions__c, Attendance__c, GPA__c,
                       Total_Attempted_Credits__c, Total_Earned_Credits__c
                FROM Enrollment_Session__c
                WHERE Program_Enrollment__c = :programEnrollmentId
                ORDER BY Academic_Session__r.Name ASC
            ];
            
            List<Map<String, Object>> sessionData = new List<Map<String, Object>>();
            
            for (Enrollment_Session__c session : sessions) {
                sessionData.add(new Map<String, Object>{
                    'id' => session.Id,
                    'name' => session.Name,
                    'sessionName' => session.Academic_Session__r?.Name,
                    'status' => session.Status__c,
                    'attendedSessions' => session.Attended_Sessions__c != null ? String.valueOf(session.Attended_Sessions__c) : '',
                    'attendance' => session.Attendance__c != null ? String.valueOf(session.Attendance__c) + '%' : '',
                    'gpa' => session.GPA__c != null ? String.valueOf(session.GPA__c) : '',
                    'totalAttemptedCredits' => session.Total_Attempted_Credits__c != null ? String.valueOf(session.Total_Attempted_Credits__c) : '0',
                    'totalEarnedCredits' => session.Total_Earned_Credits__c != null ? String.valueOf(session.Total_Earned_Credits__c) : '0'
                });
            }
            
            return sessionData;
            
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching enrollment sessions: ' + e.getMessage());
        }
    }
    
    /**
     * Get student courses as a flat list
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getStudentCourses() {
        try {
            User currentUser = [
                SELECT Id, ContactId 
                FROM User 
                WHERE Id = :UserInfo.getUserId() 
                LIMIT 1
            ];
            
            if (currentUser.ContactId == null) {
                throw new AuraHandledException('No Contact record found for current user');
            }
            
            // Query using standard education objects
            List<CourseOfferingParticipant> participants = [
                SELECT Id, Name, CourseOffering.Name, LearningCourse__c,
                       CourseOffering.Term_Start_Date__c, CourseOffering.Term_To_Date__c,
                       ParticipationStatus,
                       Term_Name__c
                FROM CourseOfferingParticipant
                WHERE ParticipantContactId = :currentUser.ContactId
                ORDER BY Term_Name__c ASC NULLS LAST,
                         CourseOffering.Name ASC
            ];
            
            List<Map<String, Object>> courseList = new List<Map<String, Object>>();
            
            for (CourseOfferingParticipant participant : participants) {
                // Use the custom fields as requested
                String learningName = participant.LearningCourse__c;
                if (String.isBlank(learningName)) {
                    learningName = participant.CourseOffering?.Name;
                }

                String startDateStr = (participant.CourseOffering != null && participant.CourseOffering.Term_Start_Date__c != null) 
                    ? participant.CourseOffering.Term_Start_Date__c.format() : '';
                String endDateStr = (participant.CourseOffering != null && participant.CourseOffering.Term_To_Date__c != null) 
                    ? participant.CourseOffering.Term_To_Date__c.format() : '';
            

                courseList.add(new Map<String, Object>{
                    'id' => participant.Id,
                    'name' => participant.Name,
                    'courseOfferingName' => participant.CourseOffering?.Name,
                    'learningCourseName' => learningName, 
                    'learningCourseNameRaw' => participant.LearningCourse__c, 
                    'startDate' => startDateStr,
                    'endDate' => endDateStr,
                    'status' => participant.ParticipationStatus,
                    'termName' => participant.Term_Name__c
                    //'yearName' => '' // Year is part of Term_Name__c or not available separately
                });
            }
            system.debug('Course List JSON'+JSON.serialize(courseList));
            
            return courseList;
            
        } catch (Exception e) {
            System.debug('ERROR in getStudentCourses: ' + e.getMessage());
            throw new AuraHandledException('Error fetching student courses: ' + e.getMessage());
        }
    }
    
    /**
     * Get simplified student grades list
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getStudentGrades() {
        try {
            User currentUser = [
                SELECT Id, ContactId 
                FROM User 
                WHERE Id = :UserInfo.getUserId() 
                LIMIT 1
            ];
            
            if (currentUser.ContactId == null) {
                throw new AuraHandledException('No Contact record found for current user');
            }
            
            // Query Results
            List<CourseOfferingPtcpResult> results = [
                SELECT Id, 
                       CourseOfferingParticipant.CourseOffering.Name,
                       CourseOfferingParticipant.CourseOffering.LearningCourse.Name,
                       CourseOfferingParticipant.CourseOffering.Term_Start_Date__c,
                       CourseOfferingParticipant.Term_Name__c,
                       Grade_Letter__c, LetterGrade, NumericGrade, Marks_Percentage__c,
                       Attempted_Credits__c, Earned_Credits__c, UnitsEarned
                FROM CourseOfferingPtcpResult
                WHERE CourseOfferingParticipant.ParticipantContactId = :currentUser.ContactId
                ORDER BY CourseOfferingParticipant.CourseOffering.Term_Start_Date__c DESC, 
                         CourseOfferingParticipant.CourseOffering.Name ASC
            ];
            
            List<Map<String, Object>> gradeList = new List<Map<String, Object>>();
            
            for (CourseOfferingPtcpResult result : results) {
                 // Fallback for Learning Course Name
                String learningName = result.CourseOfferingParticipant?.CourseOffering?.LearningCourse?.Name;
                if (String.isBlank(learningName)) {
                    learningName = result.CourseOfferingParticipant?.CourseOffering?.Name;
                }

                gradeList.add(new Map<String, Object>{
                    'id' => result.Id,
                    'courseOfferingName' => result.CourseOfferingParticipant?.CourseOffering?.Name,
                    'learningCourseName' => learningName,
                    'termName' => result.CourseOfferingParticipant?.Term_Name__c,
                    'termStartDate' => result.CourseOfferingParticipant?.CourseOffering?.Term_Start_Date__c,
                    'letterGrade' => result.LetterGrade != null ? result.LetterGrade : result.Grade_Letter__c,
                    'numericGrade' => result.NumericGrade,
                    'percentage' => result.Marks_Percentage__c,
                    'creditsAttempted' => result.Attempted_Credits__c,
                    'creditsEarned' => result.Earned_Credits__c,
                    'unitsEarned' => result.UnitsEarned
                });
            }
            
            return gradeList;
            
        } catch (Exception e) {
            System.debug('ERROR in getStudentGrades: ' + e.getMessage());
            throw new AuraHandledException('Error fetching student grades: ' + e.getMessage());
        }
    }
}