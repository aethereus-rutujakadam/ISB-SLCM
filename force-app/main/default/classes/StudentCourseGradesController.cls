public without sharing class StudentCourseGradesController {
    @AuraEnabled(cacheable=true)
    public static List<GradeWrapper> getStudentGrades(Id contactId) {
        try {
            List<CourseOfferingPtcpResult> results = [
                SELECT Id, 
                       Grade_Letter__c, 
                       LetterGrade, 
                       NumericGrade,
                       CourseOfferingParticipant.CourseOffering.Name,
                       CourseOfferingParticipant.CourseOffering.LearningCourse.Name,
                       CourseOfferingParticipant.CourseOffering.AcademicSession.Name,
                       CourseOfferingParticipant.ParticipationStatus
                FROM CourseOfferingPtcpResult
                WHERE CourseOfferingParticipant.ParticipantContactId = :contactId
                ORDER BY CourseOfferingParticipant.CourseOffering.AcademicSession.Name DESC, CourseOfferingParticipant.CourseOffering.LearningCourse.Name ASC
            ];

            List<GradeWrapper> wrappers = new List<GradeWrapper>();
            for (CourseOfferingPtcpResult res : results) {
                wrappers.add(new GradeWrapper(res));
            }
            return wrappers;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    public class GradeWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String courseName;
        @AuraEnabled public String academicSession;
        @AuraEnabled public String letterGrade;
        @AuraEnabled public Decimal numericGrade;
        @AuraEnabled public String enrollmentStatus;

        public GradeWrapper(CourseOfferingPtcpResult res) {
            this.id = res.Id;
            this.courseName = res.CourseOfferingParticipant?.CourseOffering?.LearningCourse?.Name;
            if (String.isBlank(this.courseName)) {
                this.courseName = res.CourseOfferingParticipant?.CourseOffering?.Name;
            }
            this.academicSession = res.CourseOfferingParticipant?.CourseOffering?.AcademicSession?.Name;
            this.letterGrade = res.LetterGrade != null ? res.LetterGrade : res.Grade_Letter__c;
            this.numericGrade = res.NumericGrade;
            this.enrollmentStatus = res.CourseOfferingParticipant?.ParticipationStatus;
        }
    }
}