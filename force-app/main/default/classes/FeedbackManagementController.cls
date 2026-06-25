/**
 * @description Controller for Feedback Management Console LWC
 * Provides methods for hierarchical filtering, template management, 
 * feedback triggering, and tracking dashboard
 * @author ISB Team
 * @date 2026
 */
public with sharing class FeedbackManagementController {
    
    // ═══════════════════════════════════════════════════════════════
    // WRAPPER CLASSES
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @description Generic picklist option wrapper
     */
    public class PicklistOption {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String value { get; set; }
        
        public PicklistOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }
    
    /**
     * @description Course offering wrapper with learning course name
     */
    public class CourseOfferingWrapper {
        @AuraEnabled public Id courseOfferingId { get; set; }
        @AuraEnabled public String courseName { get; set; }
        @AuraEnabled public String programName { get; set; }
        @AuraEnabled public String locationName { get; set; }
        @AuraEnabled public String termName { get; set; }
        @AuraEnabled public Integer studentCount { get; set; }
        @AuraEnabled public Integer facultyCount { get; set; }
        @AuraEnabled public Integer aaCount { get; set; }
    }
    
    /**
     * @description Academic Associate wrapper
     */
    public class AAWrapper {
        @AuraEnabled public Id aaProfileId { get; set; }
        @AuraEnabled public Id contactId { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String email { get; set; }
        @AuraEnabled public String programName { get; set; }
    }
    
    /**
     * @description Recipient wrapper for trigger preview
     */
    public class RecipientWrapper {
        @AuraEnabled public Id recipientId { get; set; }
        @AuraEnabled public String recipientName { get; set; }
        @AuraEnabled public String recipientEmail { get; set; }
        @AuraEnabled public String recipientType { get; set; }
        @AuraEnabled public List<AAWrapper> academicAssociates { get; set; }
        @AuraEnabled public String courseName { get; set; }
        @AuraEnabled public Id courseOfferingId { get; set; }
    }
    
    /**
     * @description Feedback trigger request
     */
    public class TriggerRequest {
        @AuraEnabled public String scenario { get; set; }
        @AuraEnabled public Id templateId { get; set; }
        @AuraEnabled public Id programId { get; set; }
        @AuraEnabled public Id locationId { get; set; }
        @AuraEnabled public Id cohortId { get; set; }
        @AuraEnabled public Id termId { get; set; }
        @AuraEnabled public List<Id> courseOfferingIds { get; set; }
        @AuraEnabled public List<Id> academicAssociateIds { get; set; }
        @AuraEnabled public List<Id> evaluatorUserIds { get; set; } // For quarterly scenarios (Exam/PO/AD)
        @AuraEnabled public Date dueDate { get; set; }
    }
    
    /**
     * @description Feedback trigger response
     */
    public class TriggerResponse {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public Integer feedbackRecordsCreated { get; set; }
        @AuraEnabled public Integer emailsSent { get; set; }
        @AuraEnabled public String errorMessage { get; set; }
        @AuraEnabled public List<String> warnings { get; set; }
        
        public TriggerResponse() {
            this.warnings = new List<String>();
        }
    }
    
    /**
     * @description Template wrapper with questions
     */
    public class TemplateWrapper {
        @AuraEnabled public Id templateId { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String applicableFor { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public Boolean isActive { get; set; }
        @AuraEnabled public List<QuestionWrapper> questions { get; set; }
        @AuraEnabled public Integer questionCount { get; set; }
    }
    
    /**
     * @description Question wrapper
     */
    public class QuestionWrapper {
        @AuraEnabled public Id questionId { get; set; }
        @AuraEnabled public String questionText { get; set; }
        @AuraEnabled public String questionType { get; set; }
        @AuraEnabled public Decimal weightage { get; set; }
        @AuraEnabled public Decimal displayOrder { get; set; }
        @AuraEnabled public Boolean isRequired { get; set; }
        @AuraEnabled public String picklistOptions { get; set; }
        @AuraEnabled public Decimal minRating { get; set; }
        @AuraEnabled public Decimal maxRating { get; set; }
    }
    
    /**
     * @description Tracking statistics wrapper
     */
    public class TrackingStats {
        @AuraEnabled public Integer totalSent { get; set; }
        @AuraEnabled public Integer pending { get; set; }
        @AuraEnabled public Integer submitted { get; set; }
        @AuraEnabled public Integer expired { get; set; }
        @AuraEnabled public Decimal submissionRate { get; set; }
    }
    
    /**
     * @description Feedback record wrapper for tracking
     */
    public class FeedbackRecordWrapper {
        @AuraEnabled public Id feedbackId { get; set; }
        @AuraEnabled public String feedbackName { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String submitterName { get; set; }
        @AuraEnabled public String submitterType { get; set; }
        @AuraEnabled public String academicAssociateName { get; set; }
        @AuraEnabled public String courseName { get; set; }
        @AuraEnabled public String templateName { get; set; }
        @AuraEnabled public Date triggeredDate { get; set; }
        @AuraEnabled public Date dueDate { get; set; }
        @AuraEnabled public DateTime submittedDate { get; set; }
        @AuraEnabled public String overallRating { get; set; }
        @AuraEnabled public Boolean isAnonymous { get; set; }
    }
    
    // ═══════════════════════════════════════════════════════════════
    // HIERARCHICAL FILTER METHODS
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @description Get all active programs
     * @return List<PicklistOption> Program options
     */
    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getPrograms() {
        List<PicklistOption> options = new List<PicklistOption>();
        try {
            List<Program> programs = [
                SELECT Id, Name
                FROM Program
                WHERE IsActive = true
                ORDER BY Name ASC
                LIMIT 200
            ];
            for (Program p : programs) {
                options.add(new PicklistOption(p.Name, p.Id));
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching programs: ' + e.getMessage());
        }
        return options;
    }
    
    /**
     * @description Get all locations
     * @return List<PicklistOption> Location options
     */
    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getLocations() {
        List<PicklistOption> options = new List<PicklistOption>();
        try {
            List<SObject> locs = Database.query(
                'SELECT Id, Name FROM Location ORDER BY Name ASC LIMIT 200'
            );
            for (SObject loc : locs) {
                options.add(new PicklistOption((String)loc.get('Name'), (String)loc.get('Id')));
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching locations: ' + e.getMessage());
        }
        return options;
    }
    
    /**
     * @description Get cohorts (Academic Terms) for a program
     * @param programId Program ID filter
     * @return List<PicklistOption> Cohort options
     */
    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getCohorts(String programId) {
        List<PicklistOption> options = new List<PicklistOption>();
        try {
            String query = 'SELECT Id, Name FROM AcademicTerm WHERE IsActive = true';
            if (String.isNotBlank(programId)) {
                query += ' AND Program__c = :programId';
            }
            query += ' ORDER BY StartDate DESC LIMIT 200';
            List<AcademicTerm> terms = Database.query(query);
            for (AcademicTerm t : terms) {
                options.add(new PicklistOption(t.Name, t.Id));
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching cohorts: ' + e.getMessage());
        }
        return options;
    }
    
    /**
     * @description Get terms (Academic Sessions) for a cohort
     * @param cohortId Cohort (Academic Term) ID filter
     * @return List<PicklistOption> Term options
     */
    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getTerms(String cohortId) {
        List<PicklistOption> options = new List<PicklistOption>();
        try {
            String query = 'SELECT Id, Name FROM AcademicSession WHERE IsActive = true';
            if (String.isNotBlank(cohortId)) {
                query += ' AND AcademicTermId = :cohortId';
            }
            query += ' ORDER BY Name DESC LIMIT 200';
            List<AcademicSession> sessions = Database.query(query);
            for (AcademicSession s : sessions) {
                options.add(new PicklistOption(s.Name, s.Id));
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching terms: ' + e.getMessage());
        }
        return options;
    }
    
    /**
     * @description Get course offerings with filters
     * Uses LearningCourse.Name for display per requirement
     * @param programId Program ID filter
     * @param locationId Location ID filter  
     * @param termId Term (Academic Session) ID filter
     * @return List<CourseOfferingWrapper> Course offering details
     */
    @AuraEnabled(cacheable=true)
    public static List<CourseOfferingWrapper> getCourseOfferings(String programId, String locationId, String termId) {
        List<CourseOfferingWrapper> wrappers = new List<CourseOfferingWrapper>();
        try {
            // Build dynamic query with LearningCourse.Name
            String query = 'SELECT Id, Name, LearningCourse.Name, Program__r.Name, ' +
                          'Location__r.Name, AcademicSession.Name ' +
                          'FROM CourseOffering WHERE IsActive = true';
            
            if (String.isNotBlank(programId)) {
                query += ' AND Program__c = :programId';
            }
            if (String.isNotBlank(locationId)) {
                query += ' AND Location__c = :locationId';
            }
            if (String.isNotBlank(termId)) {
                query += ' AND AcademicSessionId = :termId';
            }
            query += ' ORDER BY LearningCourse.Name ASC LIMIT 500';
            
            List<CourseOffering> offerings = Database.query(query);
            Set<Id> offeringIds = new Set<Id>();
            for (CourseOffering co : offerings) {
                offeringIds.add(co.Id);
            }
            
            // Get counts
            Map<Id, Integer> studentCounts = getStudentCounts(offeringIds);
            Map<Id, Integer> facultyCounts = getFacultyCounts(offeringIds);
            Map<Id, Integer> aaCounts = getAACounts(offeringIds);
            
            for (CourseOffering co : offerings) {
                CourseOfferingWrapper wrapper = new CourseOfferingWrapper();
                wrapper.courseOfferingId = co.Id;
                // Use LearningCourse.Name for display, fallback to Name
                wrapper.courseName = co.LearningCourse != null ? co.LearningCourse.Name : co.Name;
                wrapper.programName = co.Program__r != null ? co.Program__r.Name : '';
                wrapper.locationName = co.Location__r != null ? co.Location__r.Name : '';
                wrapper.termName = co.AcademicSession != null ? co.AcademicSession.Name : '';
                wrapper.studentCount = studentCounts.containsKey(co.Id) ? studentCounts.get(co.Id) : 0;
                wrapper.facultyCount = facultyCounts.containsKey(co.Id) ? facultyCounts.get(co.Id) : 0;
                wrapper.aaCount = aaCounts.containsKey(co.Id) ? aaCounts.get(co.Id) : 0;
                wrappers.add(wrapper);
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching course offerings: ' + e.getMessage());
        }
        return wrappers;
    }
    
    /**
     * @description Get student counts per course offering
     */
    private static Map<Id, Integer> getStudentCounts(Set<Id> courseOfferingIds) {
        Map<Id, Integer> counts = new Map<Id, Integer>();
        if (courseOfferingIds.isEmpty()) return counts;
        
        for (AggregateResult ar : [
            SELECT CourseOfferingId, COUNT(Id) cnt
            FROM CourseOfferingParticipant
            WHERE CourseOfferingId IN :courseOfferingIds
            AND ParticipantContactId != null
            GROUP BY CourseOfferingId
        ]) {
            counts.put((Id)ar.get('CourseOfferingId'), (Integer)ar.get('cnt'));
        }
        return counts;
    }
    
    /**
     * @description Get faculty counts per course offering
     */
    private static Map<Id, Integer> getFacultyCounts(Set<Id> courseOfferingIds) {
        Map<Id, Integer> counts = new Map<Id, Integer>();
        if (courseOfferingIds.isEmpty()) return counts;
        
        for (AggregateResult ar : [
            SELECT Course_Offering__c, COUNT(Id) cnt
            FROM Course_Faculty__c
            WHERE Course_Offering__c IN :courseOfferingIds
            AND Faculty__r.Email != null
            GROUP BY Course_Offering__c
        ]) {
            counts.put((Id)ar.get('Course_Offering__c'), (Integer)ar.get('cnt'));
        }
        return counts;
    }
    
    /**
     * @description Get AA counts per course offering
     */
    private static Map<Id, Integer> getAACounts(Set<Id> courseOfferingIds) {
        Map<Id, Integer> counts = new Map<Id, Integer>();
        if (courseOfferingIds.isEmpty()) return counts;
        
        for (AggregateResult ar : [
            SELECT Course_Offering__c, COUNT(Id) cnt
            FROM Course_AA_Assignment__c
            WHERE Course_Offering__c IN :courseOfferingIds
            AND Is_Active__c = true
            GROUP BY Course_Offering__c
        ]) {
            counts.put((Id)ar.get('Course_Offering__c'), (Integer)ar.get('cnt'));
        }
        return counts;
    }
    
    // ═══════════════════════════════════════════════════════════════
    // RECIPIENT PREVIEW METHODS
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @description Get recipients for trigger preview based on scenario
     * @param scenario Feedback scenario (e.g., Student-to-AA, Faculty-to-AA)
     * @param courseOfferingIds List of course offering IDs
     * @return List<RecipientWrapper> Recipients with associated AAs
     */
    @AuraEnabled
    public static List<RecipientWrapper> getRecipientsForPreview(String scenario, List<Id> courseOfferingIds) {
        List<RecipientWrapper> recipients = new List<RecipientWrapper>();
        
        if (courseOfferingIds == null || courseOfferingIds.isEmpty()) {
            return recipients;
        }
        
        try {
            // Get AA assignments per course
            Map<Id, List<AAWrapper>> courseToAAs = getAAsByCoursev(courseOfferingIds);
            
            // Get course names (using LearningCourse.Name)
            Map<Id, String> courseNames = getCourseNames(courseOfferingIds);
            
            if (scenario == 'Student-to-AA') {
                recipients = getStudentRecipients(courseOfferingIds, courseToAAs, courseNames);
            } else if (scenario == 'Faculty-to-AA' || scenario == 'Faculty-to-ASA') {
                recipients = getFacultyRecipients(courseOfferingIds, courseToAAs, courseNames);
            }
            // For non-course scenarios, AAs are selected directly
            
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching recipients: ' + e.getMessage());
        }
        
        return recipients;
    }
    
    /**
     * @description Get course names using LearningCourse.Name
     */
    private static Map<Id, String> getCourseNames(List<Id> courseOfferingIds) {
        Map<Id, String> names = new Map<Id, String>();
        for (CourseOffering co : [
            SELECT Id, Name, LearningCourse.Name 
            FROM CourseOffering 
            WHERE Id IN :courseOfferingIds
        ]) {
            names.put(co.Id, co.LearningCourse != null ? co.LearningCourse.Name : co.Name);
        }
        return names;
    }
    
    /**
     * @description Get AAs grouped by course offering
     */
    private static Map<Id, List<AAWrapper>> getAAsByCoursev(List<Id> courseOfferingIds) {
        Map<Id, List<AAWrapper>> courseToAAs = new Map<Id, List<AAWrapper>>();
        
        for (Course_AA_Assignment__c assignment : [
            SELECT Id, Course_Offering__c, Academic_Associate__c,
                   Academic_Associate__r.Academic_Associate__c,
                   Academic_Associate__r.Academic_Associate__r.Name,
                   Academic_Associate__r.Academic_Associate__r.Email,
                   Academic_Associate__r.Primary_Program__r.Name
            FROM Course_AA_Assignment__c
            WHERE Course_Offering__c IN :courseOfferingIds
            AND Is_Active__c = true
        ]) {
            if (!courseToAAs.containsKey(assignment.Course_Offering__c)) {
                courseToAAs.put(assignment.Course_Offering__c, new List<AAWrapper>());
            }
            
            AAWrapper aa = new AAWrapper();
            aa.aaProfileId = assignment.Academic_Associate__c;
            if (assignment.Academic_Associate__r != null) {
                aa.contactId = assignment.Academic_Associate__r.Academic_Associate__c;
                if (assignment.Academic_Associate__r.Academic_Associate__r != null) {
                    aa.name = assignment.Academic_Associate__r.Academic_Associate__r.Name;
                    aa.email = assignment.Academic_Associate__r.Academic_Associate__r.Email;
                }
                if (assignment.Academic_Associate__r.Primary_Program__r != null) {
                    aa.programName = assignment.Academic_Associate__r.Primary_Program__r.Name;
                }
            }
            courseToAAs.get(assignment.Course_Offering__c).add(aa);
        }
        
        return courseToAAs;
    }
    
    /**
     * @description Get student recipients
     */
    private static List<RecipientWrapper> getStudentRecipients(
        List<Id> courseOfferingIds,
        Map<Id, List<AAWrapper>> courseToAAs,
        Map<Id, String> courseNames
    ) {
        List<RecipientWrapper> recipients = new List<RecipientWrapper>();
        
        for (CourseOfferingParticipant cop : [
            SELECT Id, CourseOfferingId, ParticipantContactId,
                   ParticipantContact.Name, ParticipantContact.Email
            FROM CourseOfferingParticipant
            WHERE CourseOfferingId IN :courseOfferingIds
            AND ParticipantContactId != null
            AND ParticipantContact.Email != null
        ]) {
            RecipientWrapper rw = new RecipientWrapper();
            rw.recipientId = cop.ParticipantContactId;
            rw.recipientName = cop.ParticipantContact.Name;
            rw.recipientEmail = cop.ParticipantContact.Email;
            rw.recipientType = 'Student';
            rw.courseOfferingId = cop.CourseOfferingId;
            rw.courseName = courseNames.get(cop.CourseOfferingId);
            rw.academicAssociates = courseToAAs.get(cop.CourseOfferingId);
            recipients.add(rw);
        }
        
        return recipients;
    }
    
    /**
     * @description Get faculty recipients
     */
    private static List<RecipientWrapper> getFacultyRecipients(
        List<Id> courseOfferingIds,
        Map<Id, List<AAWrapper>> courseToAAs,
        Map<Id, String> courseNames
    ) {
        List<RecipientWrapper> recipients = new List<RecipientWrapper>();
        
        for (Course_Faculty__c cf : [
            SELECT Id, Course_Offering__c, Faculty__c,
                   Faculty__r.Name, Faculty__r.Email
            FROM Course_Faculty__c
            WHERE Course_Offering__c IN :courseOfferingIds
            AND Faculty__r.Email != null
        ]) {
            RecipientWrapper rw = new RecipientWrapper();
            rw.recipientId = cf.Faculty__c;
            rw.recipientName = cf.Faculty__r.Name;
            rw.recipientEmail = cf.Faculty__r.Email;
            rw.recipientType = 'Faculty';
            rw.courseOfferingId = cf.Course_Offering__c;
            rw.courseName = courseNames.get(cf.Course_Offering__c);
            rw.academicAssociates = courseToAAs.get(cf.Course_Offering__c);
            recipients.add(rw);
        }
        
        return recipients;
    }
    
    /**
     * @description Get all Academic Associates for non-course scenarios
     * @param programId Optional program filter
     * @return List<AAWrapper> Academic Associates
     */
    @AuraEnabled(cacheable=true)
    public static List<AAWrapper> getAllAcademicAssociates(String programId) {
        List<AAWrapper> aas = new List<AAWrapper>();
        
        try {
            String query = 'SELECT Id, Academic_Associate__c, Academic_Associate__r.Name, ' +
                          'Academic_Associate__r.Email, Primary_Program__r.Name ' +
                          'FROM AA_Profile__c WHERE Status__c = \'Active\'';
            
            if (String.isNotBlank(programId)) {
                query += ' AND Primary_Program__c = :programId';
            }
            query += ' ORDER BY Academic_Associate__r.Name ASC LIMIT 500';
            
            List<AA_Profile__c> profiles = Database.query(query);
            for (AA_Profile__c profile : profiles) {
                AAWrapper aa = new AAWrapper();
                aa.aaProfileId = profile.Id;
                aa.contactId = profile.Academic_Associate__c;
                aa.name = profile.Academic_Associate__r?.Name;
                aa.email = profile.Academic_Associate__r?.Email;
                aa.programName = profile.Primary_Program__r?.Name;
                aas.add(aa);
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching academic associates: ' + e.getMessage());
        }
        
        return aas;
    }
    
    /**
     * @description User wrapper for quarterly personas
     */
    public class UserWrapper {
        @AuraEnabled public Id userId { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String email { get; set; }
        @AuraEnabled public String profileName { get; set; }
    }
    
    /**
     * @description Get users by persona for quarterly feedback scenarios
     * @param personaType Type of persona (ExamManager, ProgramManager, AssociateDirector)
     * @return List<UserWrapper> Users matching the persona
     */
    @AuraEnabled(cacheable=true)
    public static List<UserWrapper> getUsersByPersona(String personaType) {
        List<UserWrapper> users = new List<UserWrapper>();
        
        try {
            // Map persona to profile names
            Set<String> profileNames = new Set<String>();
            
            if (personaType == 'ExamManager') {
                profileNames.add('Exam Manager');
                profileNames.add('Exam Office Manager');
            } else if (personaType == 'ProgramManager') {
                profileNames.add('Program Manager');
                profileNames.add('Program Office Manager');
            } else if (personaType == 'AssociateDirector') {
                profileNames.add('Associate Director');
                profileNames.add('ASA Manager');
            }
            
            if (profileNames.isEmpty()) {
                return users;
            }
            
            // Query active users with matching profiles
            for (User u : [
                SELECT Id, Name, Email, Profile.Name
                FROM User
                WHERE IsActive = true
                AND Profile.Name IN :profileNames
                ORDER BY Name ASC
                LIMIT 100
            ]) {
                UserWrapper wrapper = new UserWrapper();
                wrapper.userId = u.Id;
                wrapper.name = u.Name;
                wrapper.email = u.Email;
                wrapper.profileName = u.Profile?.Name;
                users.add(wrapper);
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching users by persona: ' + e.getMessage());
        }
        
        return users;
    }
    
    // ═══════════════════════════════════════════════════════════════
    // FEEDBACK TRIGGER METHODS
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @description Trigger feedback - creates records and sends emails
     * @param requestJson JSON string of TriggerRequest
     * @return TriggerResponse with results
     */
    @AuraEnabled
    public static TriggerResponse triggerFeedback(String requestJson) {
        TriggerResponse response = new TriggerResponse();
        response.success = false;
        
        try {
            TriggerRequest request = (TriggerRequest)JSON.deserialize(requestJson, TriggerRequest.class);
            
            // Validate request
            if (request.templateId == null) {
                throw new AuraHandledException('Template is required');
            }
            if (request.scenario == null) {
                throw new AuraHandledException('Scenario is required');
            }
            
            // Delegate to FeedbackTriggerService
            response = FeedbackTriggerService.triggerFeedback(request);
            
        } catch (Exception e) {
            response.errorMessage = 'Error triggering feedback: ' + e.getMessage();
            System.debug('Trigger error: ' + e.getStackTraceString());
        }
        
        return response;
    }
    
    // ═══════════════════════════════════════════════════════════════
    // TEMPLATE MANAGEMENT METHODS
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @description Get all feedback templates with questions
     * @return List<TemplateWrapper> Templates with questions
     */
    @AuraEnabled(cacheable=true)
    public static List<TemplateWrapper> getTemplates() {
        List<TemplateWrapper> templates = new List<TemplateWrapper>();
        
        try {
            List<Feedback_Template__c> templateRecords = [
                SELECT Id, Name, Applicable_For__c, Description__c, Active__c,
                       (SELECT Id, Question_Text__c, Question_Type_c__c, Weightage__c,
                               Order__c, Required__c, Picklist_Options__c,
                               Min_Rating__c, Max_Rating__c
                        FROM Feedback_Template_Questions__r
                        ORDER BY Order__c ASC)
                FROM Feedback_Template__c
                ORDER BY Name ASC
            ];
            
            for (Feedback_Template__c t : templateRecords) {
                TemplateWrapper tw = new TemplateWrapper();
                tw.templateId = t.Id;
                tw.name = t.Name;
                tw.applicableFor = t.Applicable_For__c;
                tw.description = t.Description__c;
                tw.isActive = t.Active__c;
                tw.questions = new List<QuestionWrapper>();
                
                if (t.Feedback_Template_Questions__r != null) {
                    for (Feedback_Template_Question__c q : t.Feedback_Template_Questions__r) {
                        QuestionWrapper qw = new QuestionWrapper();
                        qw.questionId = q.Id;
                        qw.questionText = q.Question_Text__c;
                        qw.questionType = q.Question_Type_c__c;
                        qw.weightage = q.Weightage__c;
                        qw.displayOrder = q.Order__c;
                        qw.isRequired = q.Required__c;
                        qw.picklistOptions = q.Picklist_Options__c;
                        qw.minRating = q.Min_Rating__c;
                        qw.maxRating = q.Max_Rating__c;
                        tw.questions.add(qw);
                    }
                }
                tw.questionCount = tw.questions.size();
                templates.add(tw);
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching templates: ' + e.getMessage());
        }
        
        return templates;
    }
    
    /**
     * @description Get templates filtered by scenario
     * @param scenario The applicable scenario
     * @return List<TemplateWrapper> Matching templates
     */
    @AuraEnabled(cacheable=true)
    public static List<TemplateWrapper> getTemplatesForScenario(String scenario) {
        List<TemplateWrapper> templates = new List<TemplateWrapper>();
        
        try {
            List<Feedback_Template__c> templateRecords = [
                SELECT Id, Name, Applicable_For__c, Description__c, Active__c,
                       (SELECT Id FROM Feedback_Template_Questions__r)
                FROM Feedback_Template__c
                WHERE Active__c = true
                AND Applicable_For__c = :scenario
                ORDER BY Name ASC
            ];
            
            for (Feedback_Template__c t : templateRecords) {
                TemplateWrapper tw = new TemplateWrapper();
                tw.templateId = t.Id;
                tw.name = t.Name;
                tw.applicableFor = t.Applicable_For__c;
                tw.description = t.Description__c;
                tw.isActive = t.Active__c;
                tw.questionCount = t.Feedback_Template_Questions__r != null 
                    ? t.Feedback_Template_Questions__r.size() : 0;
                templates.add(tw);
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching templates for scenario: ' + e.getMessage());
        }
        
        return templates;
    }
    
    /**
     * @description Create a new feedback template
     * @param templateJson JSON string of template data
     * @return Id of created template
     */
    @AuraEnabled
    public static Id createTemplate(String templateJson) {
        try {
            Map<String, Object> data = (Map<String, Object>)JSON.deserializeUntyped(templateJson);
            
            Feedback_Template__c template = new Feedback_Template__c();
            template.Name = (String)data.get('name');
            template.Applicable_For__c = (String)data.get('applicableFor');
            template.Description__c = (String)data.get('description');
            template.Active__c = data.get('isActive') == true;
            
            insert template;
            return template.Id;
        } catch (Exception e) {
            throw new AuraHandledException('Error creating template: ' + e.getMessage());
        }
    }
    
    /**
     * @description Update an existing feedback template
     * @param templateJson JSON string of template data
     * @return Id of updated template
     */
    @AuraEnabled
    public static Id updateTemplate(String templateJson) {
        try {
            Map<String, Object> data = (Map<String, Object>)JSON.deserializeUntyped(templateJson);
            
            Feedback_Template__c template = new Feedback_Template__c();
            template.Id = (Id)data.get('templateId');
            template.Name = (String)data.get('name');
            template.Applicable_For__c = (String)data.get('applicableFor');
            template.Description__c = (String)data.get('description');
            template.Active__c = data.get('isActive') == true;
            
            update template;
            return template.Id;
        } catch (Exception e) {
            throw new AuraHandledException('Error updating template: ' + e.getMessage());
        }
    }
    
    /**
     * @description Deactivate a feedback template
     * @param templateId Template ID to deactivate
     */
    @AuraEnabled
    public static void deactivateTemplate(Id templateId) {
        try {
            Feedback_Template__c template = new Feedback_Template__c();
            template.Id = templateId;
            template.Active__c = false;
            update template;
        } catch (Exception e) {
            throw new AuraHandledException('Error deactivating template: ' + e.getMessage());
        }
    }
    
    // ═══════════════════════════════════════════════════════════════
    // QUESTION MANAGEMENT METHODS
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @description Create a new question
     * @param questionJson JSON string of question data
     * @return Id of created question
     */
    @AuraEnabled
    public static Id createQuestion(String questionJson) {
        try {
            Map<String, Object> data = (Map<String, Object>)JSON.deserializeUntyped(questionJson);
            
            Feedback_Template_Question__c question = new Feedback_Template_Question__c();
            question.Feedback_Template__c = (Id)data.get('templateId');
            question.Question_Text__c = (String)data.get('questionText');
            question.Question_Type_c__c = (String)data.get('questionType');
            question.Weightage__c = data.get('weightage') != null 
                ? Decimal.valueOf(String.valueOf(data.get('weightage'))) : null;
            question.Order__c = data.get('displayOrder') != null 
                ? Decimal.valueOf(String.valueOf(data.get('displayOrder'))) : null;
            question.Required__c = data.get('isRequired') == true;
            question.Picklist_Options__c = (String)data.get('picklistOptions');
            question.Min_Rating__c = data.get('minRating') != null 
                ? Decimal.valueOf(String.valueOf(data.get('minRating'))) : 1;
            question.Max_Rating__c = data.get('maxRating') != null 
                ? Decimal.valueOf(String.valueOf(data.get('maxRating'))) : 5;
            
            insert question;
            return question.Id;
        } catch (Exception e) {
            throw new AuraHandledException('Error creating question: ' + e.getMessage());
        }
    }
    
    /**
     * @description Update an existing question
     * @param questionJson JSON string of question data
     * @return Id of updated question
     */
    @AuraEnabled
    public static Id updateQuestion(String questionJson) {
        try {
            Map<String, Object> data = (Map<String, Object>)JSON.deserializeUntyped(questionJson);
            
            Feedback_Template_Question__c question = new Feedback_Template_Question__c();
            question.Id = (Id)data.get('questionId');
            question.Question_Text__c = (String)data.get('questionText');
            question.Question_Type_c__c = (String)data.get('questionType');
            question.Weightage__c = data.get('weightage') != null 
                ? Decimal.valueOf(String.valueOf(data.get('weightage'))) : null;
            question.Order__c = data.get('displayOrder') != null 
                ? Decimal.valueOf(String.valueOf(data.get('displayOrder'))) : null;
            question.Required__c = data.get('isRequired') == true;
            question.Picklist_Options__c = (String)data.get('picklistOptions');
            question.Min_Rating__c = data.get('minRating') != null 
                ? Decimal.valueOf(String.valueOf(data.get('minRating'))) : null;
            question.Max_Rating__c = data.get('maxRating') != null 
                ? Decimal.valueOf(String.valueOf(data.get('maxRating'))) : null;
            
            update question;
            return question.Id;
        } catch (Exception e) {
            throw new AuraHandledException('Error updating question: ' + e.getMessage());
        }
    }
    
    /**
     * @description Delete a question
     * @param questionId Question ID to delete
     */
    @AuraEnabled
    public static void deleteQuestion(Id questionId) {
        try {
            delete [SELECT Id FROM Feedback_Template_Question__c WHERE Id = :questionId];
        } catch (Exception e) {
            throw new AuraHandledException('Error deleting question: ' + e.getMessage());
        }
    }
    
    /**
     * @description Reorder questions
     * @param questionOrderJson JSON array of {questionId, order} objects
     */
    @AuraEnabled
    public static void reorderQuestions(String questionOrderJson) {
        try {
            List<Object> orderList = (List<Object>)JSON.deserializeUntyped(questionOrderJson);
            List<Feedback_Template_Question__c> questionsToUpdate = new List<Feedback_Template_Question__c>();
            
            for (Object item : orderList) {
                Map<String, Object> orderItem = (Map<String, Object>)item;
                Feedback_Template_Question__c q = new Feedback_Template_Question__c();
                q.Id = (Id)orderItem.get('questionId');
                q.Order__c = Decimal.valueOf(String.valueOf(orderItem.get('order')));
                questionsToUpdate.add(q);
            }
            
            update questionsToUpdate;
        } catch (Exception e) {
            throw new AuraHandledException('Error reordering questions: ' + e.getMessage());
        }
    }
    
    // ═══════════════════════════════════════════════════════════════
    // TRACKING DASHBOARD METHODS
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @description Get tracking statistics
     * @param scenario Optional scenario filter
     * @param templateId Optional template filter
     * @param termId Optional term filter
     * @return TrackingStats Aggregated statistics
     */
    @AuraEnabled
    public static TrackingStats getTrackingStats(String scenario, String templateId, String termId) {
        TrackingStats stats = new TrackingStats();
        
        try {
            String query = 'SELECT Status__c, COUNT(Id) cnt FROM Feedback__c WHERE Id != null';
            
            if (String.isNotBlank(scenario)) {
                query += ' AND Feedback_Template__r.Applicable_For__c = :scenario';
            }
            if (String.isNotBlank(templateId)) {
                query += ' AND Feedback_Template__c = :templateId';
            }
            if (String.isNotBlank(termId)) {
                query += ' AND Academic_Session__c = :termId';
            }
            query += ' GROUP BY Status__c';
            
            stats.totalSent = 0;
            stats.pending = 0;
            stats.submitted = 0;
            stats.expired = 0;
            
            for (AggregateResult ar : Database.query(query)) {
                String status = (String)ar.get('Status__c');
                Integer count = (Integer)ar.get('cnt');
                
                stats.totalSent += count;
                if (status == 'Pending') {
                    stats.pending = count;
                } else if (status == 'Submitted') {
                    stats.submitted = count;
                } else if (status == 'Expired') {
                    stats.expired = count;
                }
            }
            
            stats.submissionRate = stats.totalSent > 0 
                ? (Decimal.valueOf(stats.submitted) / Decimal.valueOf(stats.totalSent) * 100).setScale(1)
                : 0;
                
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching tracking stats: ' + e.getMessage());
        }
        
        return stats;
    }
    
    /**
     * @description Get feedback records for tracking table
     * @param scenario Optional scenario filter
     * @param templateId Optional template filter
     * @param termId Optional term filter
     * @param status Optional status filter
     * @param pageNumber Page number (1-based)
     * @param pageSize Records per page
     * @return List<FeedbackRecordWrapper> Feedback records
     */
    @AuraEnabled
    public static List<FeedbackRecordWrapper> getFeedbackRecords(
        String scenario, String templateId, String termId, String status,
        Integer pageNumber, Integer pageSize
    ) {
        List<FeedbackRecordWrapper> records = new List<FeedbackRecordWrapper>();
        
        try {
            Integer offset = ((pageNumber != null ? pageNumber : 1) - 1) * (pageSize != null ? pageSize : 50);
            Integer limitSize = pageSize != null ? pageSize : 50;
            
            String query = 'SELECT Id, Name, Status__c, Submitter_Type__c, Anonymous__c, ' +
                          'Submitter_Contact__r.Name, Academic_Associate__r.Academic_Associate__r.Name, ' +
                          'Course_Offering__r.LearningCourse.Name, Feedback_Template__r.Name, ' +
                          'Triggered_Date__c, Due_Date__c, Submitted_Date__c, Overall_Rating__c ' +
                          'FROM Feedback__c WHERE Id != null';
            
            if (String.isNotBlank(scenario)) {
                query += ' AND Feedback_Template__r.Applicable_For__c = :scenario';
            }
            if (String.isNotBlank(templateId)) {
                query += ' AND Feedback_Template__c = :templateId';
            }
            if (String.isNotBlank(termId)) {
                query += ' AND Academic_Session__c = :termId';
            }
            if (String.isNotBlank(status)) {
                query += ' AND Status__c = :status';
            }
            
            query += ' ORDER BY CreatedDate DESC LIMIT :limitSize OFFSET :offset';
            
            for (Feedback__c f : Database.query(query)) {
                FeedbackRecordWrapper frw = new FeedbackRecordWrapper();
                frw.feedbackId = f.Id;
                frw.feedbackName = f.Name;
                frw.status = f.Status__c;
                frw.submitterType = f.Submitter_Type__c;
                frw.isAnonymous = f.Anonymous__c;
                
                // Hide submitter name if anonymous
                if (f.Anonymous__c != true && f.Submitter_Contact__r != null) {
                    frw.submitterName = f.Submitter_Contact__r.Name;
                } else if (f.Anonymous__c == true) {
                    frw.submitterName = 'Anonymous';
                }
                
                if (f.Academic_Associate__r != null && f.Academic_Associate__r.Academic_Associate__r != null) {
                    frw.academicAssociateName = f.Academic_Associate__r.Academic_Associate__r.Name;
                }
                
                // Use LearningCourse.Name for course display
                if (f.Course_Offering__r != null && f.Course_Offering__r.LearningCourse != null) {
                    frw.courseName = f.Course_Offering__r.LearningCourse.Name;
                }
                
                if (f.Feedback_Template__r != null) {
                    frw.templateName = f.Feedback_Template__r.Name;
                }
                
                frw.triggeredDate = f.Triggered_Date__c;
                frw.dueDate = f.Due_Date__c;
                frw.submittedDate = f.Submitted_Date__c;
                frw.overallRating = f.Overall_Rating__c;
                
                records.add(frw);
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching feedback records: ' + e.getMessage());
        }
        
        return records;
    }
    
    /**
     * @description Get feedback scenarios for picklist
     * @return List<PicklistOption> Scenario options
     */
    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getFeedbackScenarios() {
        List<PicklistOption> options = new List<PicklistOption>();
        
        options.add(new PicklistOption('Student → AA', 'Student-to-AA'));
        options.add(new PicklistOption('Faculty → AA', 'Faculty-to-AA'));
        options.add(new PicklistOption('Exam Office → AA', 'Exam-Office-to-AA'));
        options.add(new PicklistOption('Program Office → AA', 'Program-Office-to-AA'));
        options.add(new PicklistOption('Reporting Manager → AA', 'Reporting-Manager-to-AA'));
        options.add(new PicklistOption('Senior Manager → Associate Director', 'Senior-Manager-to-AD'));
        options.add(new PicklistOption('Associate Director → AA', 'Associate-Director-to-AA'));
        
        return options;
    }
    
    /**
     * @description Send reminder email for pending feedback
     * @param feedbackId Feedback record Id to send reminder for
     */
    @AuraEnabled
    public static void sendReminderEmail(Id feedbackId) {
        try {
            // Query feedback record with recipient info
            Feedback__c feedback = [
                SELECT Id, Name, Status__c, Feedback_Link_Token__c, Batch_Token__c,
                       Submitter_Contact__c, Submitter_Contact__r.Name, Submitter_Contact__r.Email,
                       Submitter_User__c, Submitter_User__r.Name, Submitter_User__r.Email,
                       Academic_Associate__r.Academic_Associate__r.Name,
                       Due_Date__c, Feedback_Template__r.Name
                FROM Feedback__c
                WHERE Id = :feedbackId
                LIMIT 1
            ];
            
            if (feedback.Status__c != 'Pending') {
                throw new AuraHandledException('Cannot send reminder - feedback is not pending');
            }
            
            // Get recipient email
            String recipientEmail;
            String recipientName;
            if (feedback.Submitter_User__c != null) {
                recipientEmail = feedback.Submitter_User__r?.Email;
                recipientName = feedback.Submitter_User__r?.Name;
            } else {
                recipientEmail = feedback.Submitter_Contact__r?.Email;
                recipientName = feedback.Submitter_Contact__r?.Name;
            }
            
            if (String.isBlank(recipientEmail)) {
                throw new AuraHandledException('No email address found for recipient');
            }
            
            // Build email
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(new List<String>{ recipientEmail });
            email.setSubject('Reminder: Pending Feedback for ' + 
                           (feedback.Academic_Associate__r?.Academic_Associate__r?.Name ?? 'Academic Associate'));
            
            String emailBody = '<p>Dear ' + (recipientName ?? 'Respondent') + ',</p>';
            emailBody += '<p>This is a reminder that you have pending feedback to submit.</p>';
            emailBody += '<br/>';
            emailBody += '<p><strong>Template:</strong> ' + (feedback.Feedback_Template__r?.Name ?? '') + '</p>';
            emailBody += '<p><strong>Academic Associate:</strong> ' + 
                        (feedback.Academic_Associate__r?.Academic_Associate__r?.Name ?? '') + '</p>';
            if (feedback.Due_Date__c != null) {
                emailBody += '<p><strong>Due Date:</strong> ' + feedback.Due_Date__c.format() + '</p>';
            }
            emailBody += '<br/>';
            
            // Add feedback link
            String feedbackUrl = URL.getOrgDomainUrl().toExternalForm();
            if (String.isNotBlank(feedback.Batch_Token__c)) {
                feedbackUrl += '/feedback-form?batch=' + feedback.Batch_Token__c;
            } else if (String.isNotBlank(feedback.Feedback_Link_Token__c)) {
                feedbackUrl += '/feedback-form?token=' + feedback.Feedback_Link_Token__c;
            }
            
            emailBody += '<p><a href="' + feedbackUrl + '">Click here to submit your feedback</a></p>';
            emailBody += '<br/>';
            emailBody += '<p>Thank you for your time.</p>';
            emailBody += '<p>Best regards,<br/>Office of Academic Services<br/>Indian School of Business</p>';
            
            email.setHtmlBody(emailBody);
            email.setSaveAsActivity(false);
            
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });
            
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error sending reminder email: ' + e.getMessage());
        }
    }
}