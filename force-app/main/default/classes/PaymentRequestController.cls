/**
 * @description Controller for Payment Request Creator LWC
 * Provides methods to fetch programs, years, faculties and create payment requests
 */
public with sharing class PaymentRequestController {
    
    /**
     * @description Get all active programs
     * @return List<Program> List of programs
     */
    @AuraEnabled(cacheable=true)
    public static List<Program> getPrograms() {
        return [
            SELECT Id, Name 
            FROM Program 
            ORDER BY Name
        ];
    }
    
    /**
     * @description Get all active academic years
     * @return List<AcademicYear> List of academic years
     */
    @AuraEnabled(cacheable=true)
    public static List<AcademicYear> getAcademicYears() {
        return [
            SELECT Id, Name 
            FROM AcademicYear 
            ORDER BY Name DESC
        ];
    }

    /**
     * @description Get all academic sessions for selection
     * @return List<AcademicSession> List of academic sessions
     */
    @AuraEnabled(cacheable=true)
    public static List<AcademicSession> getAcademicSessions() {
        return [
            SELECT Id, Name, AcademicTerm.Name
            FROM AcademicSession
            ORDER BY Name DESC
        ];
    }
    
    /**
     * @description Get faculties teaching in specified program and academic year
     * @param programId Program ID
     * @param academicYearId Academic Year ID
     * @return List<FacultyWrapper> List of faculty wrappers with aggregated data
     */
    @AuraEnabled
    public static List<FacultyWrapper> getFacultiesByProgramYear(Id programId, Id academicYearId) {
        // Query Course_Faculty__c records for the given program and year
        List<Course_Faculty__c> courseFaculties = [
            SELECT Faculty__c, Faculty__r.Name,
                   Faculty__r.Location__c, Course_Offering__c, Course_Offering__r.Name,
                                     Course_Offering__r.AcademicSessionId,
                                     Course_Offering__r.Academic_Year__r.Name,
                                     Course_Offering__r.AcademicSession.AcademicTerm.Name
            FROM Course_Faculty__c
            WHERE Course_Offering__r.Program__c = :programId
              AND Course_Offering__r.Academic_Year__c = :academicYearId
              AND Faculty__c != null
              AND Faculty__r.RecordType.DeveloperName = 'Faculty'
            ORDER BY Faculty__r.Name
        ];
        
        // Group by faculty
        Map<Id, FacultyWrapper> facultyMap = new Map<Id, FacultyWrapper>();
        
        for (Course_Faculty__c cf : courseFaculties) {
            if (!facultyMap.containsKey(cf.Faculty__c)) {
                FacultyWrapper fw = new FacultyWrapper();
                fw.facultyId = cf.Faculty__c;
                fw.facultyName = cf.Faculty__r.Name;
                fw.location = cf.Faculty__r.Location__c;
                fw.courseOfferings = new List<CourseOfferingInfo>();
                facultyMap.put(cf.Faculty__c, fw);
            }
            
            FacultyWrapper fw = facultyMap.get(cf.Faculty__c);
            CourseOfferingInfo courseInfo = new CourseOfferingInfo();
            courseInfo.courseOfferingId = cf.Course_Offering__c;
            courseInfo.courseName = cf.Course_Offering__r.Name;
            courseInfo.academicYearName = cf.Course_Offering__r.Academic_Year__r.Name;
            courseInfo.academicTermName = cf.Course_Offering__r.AcademicSession.AcademicTerm.Name;
            fw.courseOfferings.add(courseInfo);
            fw.courseCount = fw.courseOfferings.size();
        }
        
        return facultyMap.values();
    }

    /**
     * @description Get faculties teaching in specified program and selected academic sessions
     * @param programId Program ID
     * @param academicSessionIds Selected Academic Session IDs
     * @return List<FacultyWrapper> List of faculty wrappers with aggregated data
     */
    @AuraEnabled
    public static List<FacultyWrapper> getFacultiesByProgramSessions(Id programId, List<Id> academicSessionIds) {
        if (programId == null || academicSessionIds == null || academicSessionIds.isEmpty()) {
            return new List<FacultyWrapper>();
        }

        // Get Academic Terms from selected sessions
        List<AcademicSession> sessions = [
            SELECT Id, AcademicTermId 
            FROM AcademicSession 
            WHERE Id IN :academicSessionIds AND AcademicTermId != null
        ];
        
        Set<Id> academicTermIds = new Set<Id>();
        for (AcademicSession session : sessions) {
            academicTermIds.add(session.AcademicTermId);
        }
        
        // Only proceed if we have valid academic terms
        if (academicTermIds.isEmpty()) {
            return new List<FacultyWrapper>();
        }

        List<Course_Faculty__c> courseFaculties = [
            SELECT Faculty__c, Faculty__r.Name,
                   Faculty__r.Location__c, Course_Offering__c, Course_Offering__r.Name,
                   Course_Offering__r.LearningCourse.Name,
                   Course_Offering__r.AcademicSessionId, Course_Offering__r.Academic_Year__c,
                   Course_Offering__r.Academic_Year__r.Name,
                   Course_Offering__r.AcademicSession.AcademicTerm.Name
            FROM Course_Faculty__c
            WHERE Course_Offering__r.Program__c = :programId
              AND Course_Offering__r.AcademicSessionId IN :academicSessionIds
              AND Course_Offering__r.AcademicSession.AcademicTermId IN :academicTermIds
              AND Course_Offering__r.Program__c != null
              AND Course_Offering__r.AcademicSessionId != null
              AND Course_Offering__r.Academic_Year__c != null
              AND Course_Offering__r.Academic_Term__c != null
              AND Faculty__c != null
              AND Faculty__r.RecordType.DeveloperName = 'Faculty'
            ORDER BY Faculty__r.Name
        ];

        Map<Id, FacultyWrapper> facultyMap = new Map<Id, FacultyWrapper>();

        for (Course_Faculty__c cf : courseFaculties) {
            if (!facultyMap.containsKey(cf.Faculty__c)) {
                FacultyWrapper fw = new FacultyWrapper();
                fw.facultyId = cf.Faculty__c;
                fw.facultyName = cf.Faculty__r.Name;
                fw.location = cf.Faculty__r.Location__c;
                fw.courseOfferings = new List<CourseOfferingInfo>();
                facultyMap.put(cf.Faculty__c, fw);
            }

            FacultyWrapper fw = facultyMap.get(cf.Faculty__c);
            CourseOfferingInfo courseInfo = new CourseOfferingInfo();
            courseInfo.courseOfferingId = cf.Course_Offering__c;
            courseInfo.courseName = cf.Course_Offering__r.Name;
            courseInfo.learningCourseName = cf.Course_Offering__r.LearningCourse.Name;
            courseInfo.academicSessionId = cf.Course_Offering__r.AcademicSessionId;
            courseInfo.academicYearId = cf.Course_Offering__r.Academic_Year__c;
            courseInfo.academicYearName = cf.Course_Offering__r.Academic_Year__r.Name;
            courseInfo.academicTermName = cf.Course_Offering__r.AcademicSession.AcademicTerm.Name;
            fw.courseOfferings.add(courseInfo);
            fw.courseCount = fw.courseOfferings.size();
        }

        return facultyMap.values();
    }
    
    /**
     * @description Create payment requests for selected faculties
     * @param selectedFaculties List of faculty wrappers
     * @param programId Program ID
     * @param academicYearId Academic Year ID
     * @return String Success message with count
     */
    @AuraEnabled
    public static String createPaymentRequests(List<FacultyWrapper> selectedFaculties, Id programId, Id academicYearId) {
        List<Payment_Information__c> paymentsToInsert = new List<Payment_Information__c>();
        
        // Get Program and Academic Year names for naming
        Program prog = [SELECT Id, Name FROM Program WHERE Id = :programId LIMIT 1];
        AcademicYear year = [SELECT Id, Name FROM AcademicYear WHERE Id = :academicYearId LIMIT 1];
        
        for (FacultyWrapper fw : selectedFaculties) {
            Payment_Information__c payment = new Payment_Information__c();
            payment.Faculty__c = fw.facultyId;
            payment.Location__c = fw.location;
            payment.Program__c = programId;
            payment.Academic_Year__c = academicYearId;
            
            
            paymentsToInsert.add(payment);
        }
        
        // Insert payment requests
        insert paymentsToInsert;
        
        // Create Faculty_Term_Mapping__c child records
        List<Faculty_Term_Mapping__c> mappingsToInsert = new List<Faculty_Term_Mapping__c>();
        
        for (Integer i = 0; i < paymentsToInsert.size(); i++) {
            Payment_Information__c payment = paymentsToInsert[i];
            FacultyWrapper fw = selectedFaculties[i];
            
            for (CourseOfferingInfo courseInfo : fw.courseOfferings) {
                Faculty_Term_Mapping__c mapping = new Faculty_Term_Mapping__c();
                mapping.Payment_Information__c = payment.Id;
                mapping.Course_Offering__c = courseInfo.courseOfferingId;
                
                mappingsToInsert.add(mapping);
            }
        }
        
        if (!mappingsToInsert.isEmpty()) {
            insert mappingsToInsert;
        }
        
        return 'Successfully created ' + paymentsToInsert.size() + ' payment request(s) with ' + 
               mappingsToInsert.size() + ' course mapping(s).';
    }

    /**
     * @description Create payment requests for all faculties in selected academic sessions
     * @param facultyIds List of faculty Contact IDs
     * @param programId Program ID
     * @param academicSessionIds Selected Academic Session IDs
     * @return String Success message with count
     */
    @AuraEnabled
    public static String createPaymentRequestsBySessions(
        List<Id> facultyIds,
        Id programId,
        List<Id> academicSessionIds
    ) {
        if (facultyIds == null || facultyIds.isEmpty()) {
            return 'No faculties selected.';
        }

        // Re-query faculty data to ensure we have fresh, complete data
        Map<Id, FacultyWrapper> facultyDataMap = new Map<Id, FacultyWrapper>();
        
        List<Course_Faculty__c> courseFaculties = [
            SELECT Faculty__c, Faculty__r.Name,
                   Faculty__r.Location__c, Course_Offering__c, Course_Offering__r.Name,
                   Course_Offering__r.LearningCourse.Name,
                   Course_Offering__r.AcademicSessionId, Course_Offering__r.Academic_Year__c,
                   Course_Offering__r.Academic_Year__r.Name,
                   Course_Offering__r.AcademicSession.AcademicTerm.Name
            FROM Course_Faculty__c
            WHERE Faculty__c IN :facultyIds
              AND Course_Offering__r.Program__c = :programId
              AND Course_Offering__r.AcademicSessionId IN :academicSessionIds
              AND Faculty__c != null
            ORDER BY Faculty__r.Name
        ];
        
        // Build faculty wrapper map
        for (Course_Faculty__c cf : courseFaculties) {
            if (!facultyDataMap.containsKey(cf.Faculty__c)) {
                FacultyWrapper fw = new FacultyWrapper();
                fw.facultyId = cf.Faculty__c;
                fw.facultyName = cf.Faculty__r.Name;
                //fw.facultyType = cf.Faculty__r.Faculty_Type__c;
                fw.location = cf.Faculty__r.Location__c;
                fw.courseOfferings = new List<CourseOfferingInfo>();
                facultyDataMap.put(cf.Faculty__c, fw);
            }
            
            FacultyWrapper fw = facultyDataMap.get(cf.Faculty__c);
            CourseOfferingInfo courseInfo = new CourseOfferingInfo();
            courseInfo.courseOfferingId = cf.Course_Offering__c;
            courseInfo.courseName = cf.Course_Offering__r.Name;
            courseInfo.learningCourseName = cf.Course_Offering__r.LearningCourse.Name;
            courseInfo.academicSessionId = cf.Course_Offering__r.AcademicSessionId;
            courseInfo.academicYearId = cf.Course_Offering__r.Academic_Year__c;
            courseInfo.academicYearName = cf.Course_Offering__r.Academic_Year__r.Name;
            courseInfo.academicTermName = cf.Course_Offering__r.AcademicSession.AcademicTerm.Name;
            fw.courseOfferings.add(courseInfo);
            fw.courseCount = fw.courseOfferings.size();
        }
        
        List<FacultyWrapper> selectedFaculties = facultyDataMap.values();
        if (selectedFaculties.isEmpty()) {
            return 'No course offerings found for selected faculties and sessions.';
        }

        List<Payment_Information__c> paymentsToInsert = new List<Payment_Information__c>();
        
        // Query program with null check
        List<Program> programs = [SELECT Id, Name FROM Program WHERE Id = :programId LIMIT 1];
        if (programs.isEmpty()) {
            throw new AuraHandledException('Program not found.');
        }
        Program prog = programs[0];

        for (FacultyWrapper fw : selectedFaculties) {
            Set<Id> yearIds = new Set<Id>();
            for (CourseOfferingInfo courseInfo : fw.courseOfferings) {
                if (courseInfo.academicYearId != null) {
                    yearIds.add(courseInfo.academicYearId);
                }
            }

            Id singleAcademicYearId = yearIds.size() == 1 ? yearIds.iterator().next() : null;

            Payment_Information__c payment = new Payment_Information__c();
            payment.Faculty__c = fw.facultyId;
            payment.Location__c = fw.location;
            payment.Program__c = programId;
            payment.Academic_Year__c = singleAcademicYearId;
            

            paymentsToInsert.add(payment);
        }

        insert paymentsToInsert;

        List<Faculty_Term_Mapping__c> mappingsToInsert = new List<Faculty_Term_Mapping__c>();

        for (Integer i = 0; i < paymentsToInsert.size(); i++) {
            Payment_Information__c payment = paymentsToInsert[i];
            FacultyWrapper fw = selectedFaculties[i];

            for (CourseOfferingInfo courseInfo : fw.courseOfferings) {
                Faculty_Term_Mapping__c mapping = new Faculty_Term_Mapping__c();
                mapping.Payment_Information__c = payment.Id;
                mapping.Course_Offering__c = courseInfo.courseOfferingId;
                mappingsToInsert.add(mapping);
            }
        }

        if (!mappingsToInsert.isEmpty()) {
            insert mappingsToInsert;
        }

        return 'Successfully created ' + paymentsToInsert.size() + ' payment request(s) with ' +
               mappingsToInsert.size() + ' course mapping(s).';
    }
    
    /**
     * Wrapper class for faculty data
     */
    public class FacultyWrapper {
        @AuraEnabled public Id facultyId;
        @AuraEnabled public String facultyName;
        @AuraEnabled public String location;
        @AuraEnabled public Integer courseCount;
        @AuraEnabled public List<CourseOfferingInfo> courseOfferings;
    }
    
    /**
     * Wrapper class for course offering info
     */
    public class CourseOfferingInfo {
        @AuraEnabled public Id courseOfferingId;
        @AuraEnabled public String courseName;
        @AuraEnabled public String learningCourseName;
        @AuraEnabled public Id academicSessionId;
        @AuraEnabled public Id academicYearId;
        @AuraEnabled public String academicYearName;
        @AuraEnabled public String academicTermName;
    }
}