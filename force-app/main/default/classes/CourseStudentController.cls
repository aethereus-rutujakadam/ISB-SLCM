public with sharing class CourseStudentController {
    
    @AuraEnabled(cacheable=true)
    public static List<AggregateResult> getProgramOptions() {
        return [
            SELECT Program__c, Program__r.Name label
            FROM CourseOffering 
            WHERE Program__c != null 
            GROUP BY Program__c, Program__r.Name
            ORDER BY Program__r.Name
        ];
    }
    
    @AuraEnabled(cacheable=true)
    public static List<AggregateResult> getSessionOptions(String programId) {
        if (String.isBlank(programId)) {
            return new List<AggregateResult>();
        }
        return [
            SELECT AcademicSessionId, AcademicSession.Name label
            FROM CourseOffering 
            WHERE Program__c = :programId 
            AND AcademicSessionId != null 
            GROUP BY AcademicSessionId, AcademicSession.Name
            ORDER BY AcademicSession.Name
        ];
    }
    
    @AuraEnabled(cacheable=true)
    public static List<AggregateResult> getCourseOptions(String programId, String sessionId) {
        if (String.isBlank(programId) || String.isBlank(sessionId)) {
            return new List<AggregateResult>();
        }
        return [
            SELECT LearningCourseId, LearningCourse.Name label
            FROM CourseOffering 
            WHERE Program__c  = :programId 
            AND AcademicSessionId = :sessionId 
            AND LearningCourseId != null 
            GROUP BY LearningCourseId, LearningCourse.Name
            ORDER BY LearningCourse.Name
        ];
    }
    
    @AuraEnabled(cacheable=true)
    public static List<StudentWrapper> getStudents(String programId, String sessionId, String courseId) {
        List<StudentWrapper> students = new List<StudentWrapper>();
        
        if (String.isBlank(programId)) {
            return students;
        }
        
      String query = 'SELECT Id, CourseOfferingId, ParticipantContactId, ParticipantContact.Name, ' +
               'ParticipantContact.Email, ParticipationStatus, ' +
               'CourseOffering.Program__r.Name, ' +
               'CourseOffering.AcademicSession.Name, ' +
               'CourseOffering.LearningCourse.Name ' +
               'FROM CourseOfferingParticipant ' +
               'WHERE CourseOffering.Program__c = :programId ' +
               'AND ParticipationStatus = \'Enrolled\'';

        
        if (String.isNotBlank(sessionId)) {
            query += 'AND CourseOffering.AcademicSessionId = :sessionId ';
        }
        
        if (String.isNotBlank(courseId)) {
            query += 'AND CourseOffering.LearningCourseId = :courseId ';
        }
        
        query += 'ORDER BY ParticipantContact.Name';
        
        for (CourseOfferingParticipant participant : Database.query(query)) {
            students.add(new StudentWrapper(participant));
        }
        
        return students;
    }

    @AuraEnabled
    public static void sendNotificationsToStudents(List<String> studentIds) {
        if (studentIds == null || studentIds.isEmpty()) {
            throw new AuraHandledException('No students selected');
        }

        // Query students (Contacts)
        List<Contact> students = [
            SELECT Id, Name, Email
            FROM Contact
            WHERE Id IN :studentIds
        ];

        // Get Custom Notification Type
        CustomNotificationType notifType = [
            SELECT Id
            FROM CustomNotificationType
            WHERE DeveloperName = 'Student_Notification'
            LIMIT 1
        ];

        for (Contact student : students) {
            try {
                Messaging.CustomNotification notification = new Messaging.CustomNotification();
                notification.setBody('Notification for student ' + student.Name + '.');
                notification.setTitle('Student Notification');
                notification.setSenderId(UserInfo.getUserId());
                notification.setNotificationTypeId(notifType.Id);
                notification.setTargetId(student.Id);
                notification.send(new Set<String>{ student.Id });
            } catch (Exception e) {
                System.debug(
                    'Error sending custom notification for Contact: ' +
                    student.Id + ' Error: ' + e.getMessage()
                );
            }
        }
    }
    
    public class StudentWrapper {
        @AuraEnabled public String participantId;
        @AuraEnabled public String courseOfferingId;
        @AuraEnabled public String studentId;
        @AuraEnabled public String studentName;
        @AuraEnabled public String email;
        @AuraEnabled public String status;
        @AuraEnabled public String programName;
        @AuraEnabled public String sessionName;
        @AuraEnabled public String courseName;
        
        public StudentWrapper(CourseOfferingParticipant participant) {
            this.participantId = participant.Id;
            this.courseOfferingId = participant.CourseOfferingId;
            this.studentId = participant.ParticipantContactId;
            this.studentName = participant.ParticipantContact.Name;
            this.email = participant.ParticipantContact.Email;
            this.status = participant.ParticipationStatus;
            this.programName = participant.CourseOffering.Program__r.Name;
            this.sessionName = participant.CourseOffering.AcademicSession.Name;
            this.courseName = participant.CourseOffering.LearningCourse.Name;
        }
    }
}