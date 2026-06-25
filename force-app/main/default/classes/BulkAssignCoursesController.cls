public without sharing class BulkAssignCoursesController {
    
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getCourseOfferingDetails(Id courseOfferingId) {
        try {
            CourseOffering co = [
                SELECT Id, Name, Program__c, Program__r.Name, AcademicSessionId, AcademicSession.Name
                FROM CourseOffering 
                WHERE Id = :courseOfferingId 
                LIMIT 1
            ];
            
            return new Map<String, Object>{
                'programId' => co.Program__c,
                'programName' => co.Program__r.Name,
                'courseName' => co.Name,
                'academicTermId' => co.AcademicSessionId,
                'academicTermName' => co.AcademicSession.Name
            };
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching Course Offering details: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<ProgramEnrollment> searchStudents(Id programId, Id termId, Id academicSessionId) {
        try {
            if (programId == null) {
                return new List<ProgramEnrollment>();
            }

            // Build dynamic query for ProgramEnrollment and related Enrollment Sessions
            
            // Query ProgramEnrollment and related Enrollment Sessions
            String query = 'SELECT Id, Name, ContactId, Contact.Name, Contact.Email, Status, StartDate, EndDate, ' +
                           'Sub_Status__c, ' +
                           '(SELECT Academic_Session__r.Name, Academic_Session__r.AcademicTermId FROM Enrollment_Sessions__r ' +
                           'WHERE Status__c IN (\'Registered\', \'Rejoined\', \'Re-Registered\')) ' +
                           'FROM ProgramEnrollment ' +
                           'WHERE ContactId != null ' +
                           'AND ProgramId = :programId ';
            
            // Add status filter (Registered with Current Student subtype, Rejoined, or Exchange Student with Incoming subtype)
            query += 'AND ((Status = \'Registered\' AND Sub_Status__c = \'Student\') OR Status = \'Rejoined\' OR (Status = \'Exchange Student\' AND Sub_Status__c = \'Incoming\')) ';
            
            // Filter by Academic Term if provided
            if (termId != null) {
                query += 'AND Id IN (SELECT Program_Enrollment__c FROM Enrollment_Session__c ' +
                         'WHERE Academic_Session__r.AcademicTermId = :termId ' +
                         'AND Status__c IN (\'Registered\', \'Rejoined\')) ';
            }
            
            // Filter by Academic Session if provided
            if (academicSessionId != null) {
                query += 'AND Id IN (SELECT Program_Enrollment__c FROM Enrollment_Session__c ' +
                         'WHERE Academic_Session__c = :academicSessionId ' +
                         'AND Status__c IN (\'Registered\', \'Rejoined\')) ';
            }
            
            query += 'ORDER BY Contact.Name ASC LIMIT 2000';
            
            return Database.query(query);
            
        } catch (Exception e) {
            System.debug('Search Error: ' + e.getMessage());
            throw new AuraHandledException('Error searching students: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getCourseOfferingsByLearningCourse(Id learningCourseId, Id academicSessionId) {
        try {
            List<Map<String, String>> options = new List<Map<String, String>>();
            
            String query = 'SELECT Id, Name, AcademicSessionId, AcademicSession.Name, Course_Type__c ' +
                          'FROM CourseOffering ' +
                          'WHERE LearningCourseId = :learningCourseId ';
            
            // Filter by Academic Session if provided
            if (academicSessionId != null) {
                query += 'AND AcademicSessionId = :academicSessionId ';
            }
            
            query += 'ORDER BY AcademicSession.Name DESC, Name ASC';
            
            for (CourseOffering co : Database.query(query)) {
                String label = co.Name + (co.Course_Type__c != null ? ' - ' + co.Course_Type__c : '') + (co.AcademicSessionId != null ? ' - ' + co.AcademicSession.Name : '');
                options.add(new Map<String, String>{
                    'label' => label,
                    'value' => co.Id
                });
            }
            return options;
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching Course Offerings: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getAcademicTermsByProgram(Id programId) {
        try {
            List<Map<String, String>> options = new List<Map<String, String>>();
            
            // Query distinct Academic Terms from Course Offerings related to the Program
            Set<Id> termIds = new Set<Id>();
            for (CourseOffering co : [
                SELECT AcademicSession.AcademicTermId
                FROM CourseOffering 
                WHERE Program__c = :programId 
                AND AcademicSession.AcademicTermId != null
            ]) {
                termIds.add(co.AcademicSession.AcademicTermId);
            }
            
            if (!termIds.isEmpty()) {
                for (AcademicTerm term : [
                    SELECT Id, Name 
                    FROM AcademicTerm 
                    WHERE Id IN :termIds
                    ORDER BY Name DESC
                ]) {
                    options.add(new Map<String, String>{
                        'label' => term.Name,
                        'value' => term.Id
                    });
                }
            }
            
            return options;
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching Academic Terms: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getAcademicSessionsByTerm(Id termId) {
        try {
            List<Map<String, String>> options = new List<Map<String, String>>();
            
            for (AcademicSession session : [
                SELECT Id, Name 
                FROM AcademicSession 
                WHERE AcademicTermId = :termId
                ORDER BY Name DESC
            ]) {
                options.add(new Map<String, String>{
                    'label' => session.Name,
                    'value' => session.Id
                });
            }
            
            return options;
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching Academic Sessions: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getLearningCoursesBySession(Id academicSessionId) {
        try {
            List<Map<String, String>> options = new List<Map<String, String>>();
            
            // Get distinct Learning Courses from Course Offerings in the selected Academic Session
            Set<Id> learningCourseIds = new Set<Id>();
            for (CourseOffering co : [
                SELECT LearningCourseId
                FROM CourseOffering 
                WHERE AcademicSessionId = :academicSessionId
                AND LearningCourseId != null
            ]) {
                learningCourseIds.add(co.LearningCourseId);
            }
            
            if (!learningCourseIds.isEmpty()) {
                for (LearningCourse lc : [
                    SELECT Id, Name 
                    FROM LearningCourse 
                    WHERE Id IN :learningCourseIds
                    ORDER BY Name ASC
                ]) {
                    options.add(new Map<String, String>{
                        'label' => lc.Name,
                        'value' => lc.Id
                    });
                }
            }
            
            return options;
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching Learning Courses: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static String getProgramObjectApiName() {
        try {
            Schema.DescribeFieldResult f = CourseOffering.Program__c.getDescribe();
            List<Schema.sObjectType> refs = f.getReferenceTo();
            if (!refs.isEmpty()) {
                return refs[0].getDescribe().getName();
            }
            return 'Program'; 
        } catch (Exception e) {
            return 'Account'; 
        }
    }
    
    // Kept for backward compatibility if JS calls it, or can remove if sure
    @AuraEnabled(cacheable=true)
    public static String getTermObjectApiName() {
        return 'AcademicTerm';
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getCourseTypePicklistValues() {
        try {
            List<Map<String, String>> options = new List<Map<String, String>>();
            
            Schema.DescribeFieldResult fieldResult = CourseOfferingParticipant.Course_Type__c.getDescribe();
            List<Schema.PicklistEntry> picklistValues = fieldResult.getPicklistValues();
            
            for (Schema.PicklistEntry entry : picklistValues) {
                if (entry.isActive()) {
                    options.add(new Map<String, String>{
                        'label' => entry.getLabel(),
                        'value' => entry.getValue()
                    });
                }
            }
            
            return options;
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching Course Type picklist values: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Integer createParticipants(List<Id> contactIds, Id courseOfferingId, String courseType) {
        if (contactIds == null || contactIds.isEmpty() || courseOfferingId == null) {
            throw new AuraHandledException('Invalid input: Contacts or Course Offering missing.');
        }
        
        try {
            // 1. Get Course Offering Session
            CourseOffering co = [SELECT AcademicSessionId FROM CourseOffering WHERE Id = :courseOfferingId LIMIT 1];
            if (co.AcademicSessionId == null) {
                 // If no session on offering, maybe skip validation or fail? 
                 // Assuming strict validation is only possible if session exists. 
                 // If session is null, we proceed (or fail). I will proceed but warn.
            } else {
                // 2. Validate Enrollment Session for Contacts
                Set<Id> validContactIds = new Set<Id>();
                for (Enrollment_Session__c es : [
                    SELECT Program_Enrollment__r.ContactId 
                    FROM Enrollment_Session__c 
                    WHERE Program_Enrollment__r.ContactId IN :contactIds 
                    AND Academic_Session__c = :co.AcademicSessionId
                    AND Status__c IN ('Registered', 'Completed', 'Rejoined', 'Re-Registered')
                ]) {
                    validContactIds.add(es.Program_Enrollment__r.ContactId);
                }
                
                // Identify invalid contacts
                List<Id> invalidContacts = new List<Id>();
                for(Id cid : contactIds) {
                    if(!validContactIds.contains(cid)) {
                        invalidContacts.add(cid);
                    }
                }
                
                if (!invalidContacts.isEmpty()) {
                    throw new AuraHandledException('Validation Failed: Selected students are not enrolled/registered in the Academic Session of this Course Offering.');
                }
            }

            // Check if any of the students are already enrolled in this Course Offering
            List<CourseOfferingParticipant> existingParticipants = [
                SELECT Id, ParticipantContactId, ParticipantContact.Name 
                FROM CourseOfferingParticipant 
                WHERE CourseOfferingId = :courseOfferingId 
                AND ParticipantContactId IN :contactIds
            ];
            
            if (!existingParticipants.isEmpty()) {
                Set<String> duplicateNames = new Set<String>();
                for (CourseOfferingParticipant cop : existingParticipants) {
                    String name = cop.ParticipantContact.Name != null ? cop.ParticipantContact.Name : (String)cop.ParticipantContactId;
                    duplicateNames.add(name);
                }
                throw new AuraHandledException('The following students are already enrolled in this course: ' + String.join(new List<String>(duplicateNames), ', '));
            }
            
            List<CourseOfferingParticipant> toInsert = new List<CourseOfferingParticipant>();
            Date today = Date.today();
            
            for (Id conId : contactIds) {
                CourseOfferingParticipant cop = new CourseOfferingParticipant();
                cop.CourseOfferingId = courseOfferingId;
                cop.ParticipantContactId = conId;
                cop.StartDate = today;
                cop.Status__c = 'Enrolled'; 
                
                cop.Course_Type__c = courseType;
                
                toInsert.add(cop);
            }
            
            if (!toInsert.isEmpty()) {
                insert toInsert;
            }
            
            return toInsert.size();
            
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}