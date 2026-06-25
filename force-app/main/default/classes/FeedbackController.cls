/**
 * @description Controller for feedback form LWC
 * Handles template loading, validation, and feedback submission
 * Uses 'without sharing' to allow Guest Users to access feedback templates
 * @author ISB Team
 * @date 2025
 */
public without sharing class FeedbackController {
    
    /**
     * @description Wrapper for complete feedback submission
     */
    public class FeedbackWrapper {
        @AuraEnabled public Feedback__c feedback { get; set; }
        @AuraEnabled public List<AnswerWrapper> answers { get; set; }
        @AuraEnabled public String manualAAName { get; set; }
        @AuraEnabled public String templateName { get; set; }
        @AuraEnabled public String caseId { get; set; }
        @AuraEnabled public String facultyId { get; set; }
        @AuraEnabled public String feedbackToken { get; set; }
    }
    
    /**
     * @description Wrapper for individual question answers
     * Using String types for ratingAnswer and order for safe JSON serialization
     */
    public class AnswerWrapper {
        @AuraEnabled public Id questionId { get; set; }
        @AuraEnabled public String questionText { get; set; }
        @AuraEnabled public String questionType { get; set; }
        @AuraEnabled public String textAnswer { get; set; }
        @AuraEnabled public String ratingAnswer { get; set; }  // String for JSON compatibility
        @AuraEnabled public String picklistAnswer { get; set; }
        @AuraEnabled public String order { get; set; }  // String for JSON compatibility
    }
    
    /**
     * @description Template with questions data transfer object
     */
    public class TemplateDTO {
        @AuraEnabled public Feedback_Template__c template { get; set; }
        @AuraEnabled public List<Feedback_Template_Question__c> questions { get; set; }
        @AuraEnabled public ContextData context { get; set; }
    }
    
    /**
     * @description Context data from URL parameters
     */
    public class ContextData {
        @AuraEnabled public Id courseOfferingId { get; set; }
        @AuraEnabled public Id facultyId { get; set; }
        @AuraEnabled public Id academicAssociateId { get; set; }
        @AuraEnabled public Id programId { get; set; }
        @AuraEnabled public Id academicTermId { get; set; }
        @AuraEnabled public String courseOfferingName { get; set; }
        @AuraEnabled public String caseNumber { get; set; }
        @AuraEnabled public String caseSubject { get; set; }
        @AuraEnabled public String facultyName { get; set; }
        @AuraEnabled public String academicAssociateName { get; set; }
        @AuraEnabled public String programName { get; set; }
    }
    
    /**
     * @description Load template with questions based on template name
     * @param templateName Name field value of Feedback_Template__c
     * @param courseOfferingId Optional context
     * @param facultyId Optional context
     * @param academicAssociateId Optional context
     * @param programId Optional context
     * @return TemplateDTO with template, questions, and context
     */
    @AuraEnabled
    public static TemplateDTO getTemplateWithQuestions(
        String templateName,
        String courseOfferingId,
        String facultyId,
        String academicAssociateId,
        String programId
    ) {
        TemplateDTO dto = new TemplateDTO();
        
        try {
            // Validate input
            if (String.isBlank(templateName)) {
                throw new AuraHandledException('Template name is required');
            }
            
            System.debug('Loading template: ' + templateName);
            
            // Load template by Name
            List<Feedback_Template__c> templates;
            try {
                templates = [
                    SELECT Id, Name, Applicable_For__c, Description__c, Active__c
                    FROM Feedback_Template__c
                    WHERE Name = :templateName
                    AND Active__c = true
                    LIMIT 1
                ];
            } catch (Exception e) {
                System.debug('Error querying Feedback_Template__c: ' + e.getMessage());
                throw new AuraHandledException('Error loading template. Ensure Guest User has Read access to Feedback_Template__c. Error: ' + e.getMessage());
            }
            
            if (templates.isEmpty()) {
                throw new AuraHandledException('Template not found or inactive: ' + templateName + '. Create Feedback_Template__c with Name = "' + templateName + '" and Active__c = true');
            }
            
            dto.template = templates[0];
            System.debug('Template loaded: ' + dto.template.Name + ' (ID: ' + dto.template.Id + ')');
            
            // Load questions for this template, ordered
            try {
                dto.questions = [
                    SELECT Id, Question_Text__c, Question_Type_c__c, Required__c, 
                           Order__c, Picklist_Options__c, Min_Rating__c, Max_Rating__c,
                           Feedback_Template__c
                    FROM Feedback_Template_Question__c
                    WHERE Feedback_Template__c = :dto.template.Id
                    ORDER BY Order__c ASC NULLS LAST
                ];
                System.debug('Questions loaded: ' + dto.questions.size());
                
                if (dto.questions.isEmpty()) {
                    System.debug('WARNING: Template has no questions');
                }
                
            } catch (Exception e) {
                System.debug('Error querying Feedback_Template_Question__c: ' + e.getMessage());
                throw new AuraHandledException('Error loading questions. Ensure Guest User has Read access to Feedback_Template_Question__c. Error: ' + e.getMessage());
            }
            
            // Load context data if IDs provided
            dto.context = loadContextData(courseOfferingId, facultyId, academicAssociateId, programId);
            
            return dto;
            
        } catch (AuraHandledException e) {
            // Re-throw AuraHandledExceptions as-is
            throw e;
        } catch (Exception e) {
            System.debug('Unexpected error in getTemplateWithQuestions: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            throw new AuraHandledException('Unexpected error: ' + e.getMessage());
        }
    }
    
    /**
     * @description Load template with questions from Case context
     * @param caseId Case record ID
     * @param templateName Template name (optional - can be derived from Case)
     * @return TemplateDTO with template, questions, and context from Case
     */
    @AuraEnabled
    public static TemplateDTO getTemplateFromCase(String caseId, String templateName) {
        try {
            if (String.isBlank(caseId)) {
                throw new AuraHandledException('Case ID is required');
            }
            
            System.debug('Loading feedback context from Case: ' + caseId);
            
            // Query Case to get context
            // Note: Removed custom fields that don't exist
            List<Case> cases = [
                SELECT Id, CaseNumber, Subject, ContactId, Contact.Name
                FROM Case
                WHERE Id = :caseId
                LIMIT 1
            ];
            
            if (cases.isEmpty()) {
                throw new AuraHandledException('Case not found: ' + caseId);
            }
            
            Case caseRecord = cases[0];
            
            // Determine template name if not provided
            String finalTemplateName = templateName;
            if (String.isBlank(finalTemplateName)) {
                // Default to Student-AA template
                finalTemplateName = 'Student To Academic Associate Feedback';
            }
            
            // Extract context from Case
            // Note: Course/AA fields removed as they don't exist on Case
            String courseOfferingId = null;
            String academicAssociateId = null;
            String facultyId = null;
            String programId = null; // Removed Program__c to be safe
            
            System.debug('Case context loaded: ' + caseRecord.CaseNumber);
            
            // Call existing method with extracted context
            TemplateDTO dto = getTemplateWithQuestions(
                finalTemplateName,
                courseOfferingId,
                facultyId,
                academicAssociateId,
                programId
            );
            
            // Add Case details to context
            if (dto.context != null) {
                dto.context.caseNumber = caseRecord.CaseNumber;
                dto.context.caseSubject = caseRecord.Subject;
            }
            
            return dto;
            
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            System.debug('Error in getTemplateFromCase: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            throw new AuraHandledException('Error loading feedback from case: ' + e.getMessage());
        }
    }
    
    /**
     * @description Load contextual data for pre-population
     */
    private static ContextData loadContextData(
        String courseOfferingId,
        String facultyId,
        String academicAssociateId,
        String programId
    ) {
        ContextData context = new ContextData();
        
        try {
            // Load Course Offering (using custom object CourseOffering)
            if (String.isNotBlank(courseOfferingId)) {
                try {
                    // Try custom object first
                    List<CourseOffering> offerings = [
                        SELECT Id, Name, Academic_Term__c, Program__c
                        FROM CourseOffering
                        WHERE Id = :courseOfferingId
                        LIMIT 1
                    ];
                    
                    if (!offerings.isEmpty()) {
                        CourseOffering offering = offerings[0];
                        context.courseOfferingId = offering.Id;
                        context.courseOfferingName = offering.Name;
                        context.academicTermId = offering.Academic_Term__c;
                        context.programId = offering.Program__c;
                    }
                } catch (Exception e) {
                    // If custom object doesn't exist, try standard CourseOffering
                    System.debug('Custom CourseOffering not found, trying standard object');
                    try {
                        List<CourseOffering> offerings = [
                            SELECT Id, Name, AcademicSessionId
                            FROM CourseOffering
                            WHERE Id = :courseOfferingId
                            LIMIT 1
                        ];
                        
                        if (!offerings.isEmpty()) {
                            CourseOffering offering = offerings[0];
                            context.courseOfferingId = offering.Id;
                            context.courseOfferingName = offering.Name;
                            context.academicTermId = offering.AcademicSessionId;
                        }
                    } catch (Exception ex) {
                        System.debug('Neither custom nor standard CourseOffering found: ' + ex.getMessage());
                    }
                }
            }
            
            // Load Faculty
            if (String.isNotBlank(facultyId)) {
                // Validate against Course_Faculty__c if Course ID is present
                if (String.isNotBlank(courseOfferingId)) {
                    try {
                        List<Course_Faculty__c> cfs = [
                            SELECT Id, Faculty__c, Faculty__r.Name
                            FROM Course_Faculty__c
                            WHERE Course_Offering__c = :courseOfferingId
                            AND Faculty__c = :facultyId
                            LIMIT 1
                        ];
                        
                        if (!cfs.isEmpty()) {
                            context.facultyId = cfs[0].Faculty__c;
                            context.facultyName = cfs[0].Faculty__r.Name;
                        } else {
                            System.debug('Faculty ' + facultyId + ' not associated with Course ' + courseOfferingId);
                            // Do not load faculty context if not associated
                        }
                    } catch (Exception e) {
                        System.debug('Error checking Course_Faculty__c: ' + e.getMessage());
                        // Fallback logic could go here, but safer to fail silent
                    }
                } else {
                    // Fallback to direct query if no Course ID
                    List<Contact> faculties = [
                        SELECT Id, Name
                        FROM Contact
                        WHERE Id = :facultyId
                        LIMIT 1
                    ];
                    
                    if (!faculties.isEmpty()) {
                        context.facultyId = faculties[0].Id;
                        context.facultyName = faculties[0].Name;
                    }
                }
            }
            
            // Load Academic Associate from AA Profile
            if (String.isNotBlank(academicAssociateId)) {
                try {
                    // Query AA_Profile__c to get the related Contact
                    List<AA_Profile__c> aaProfiles = [
                        SELECT Id, Academic_Associate__c, Academic_Associate__r.Name
                        FROM AA_Profile__c
                        WHERE Id = :academicAssociateId
                        LIMIT 1
                    ];
                    
                    if (!aaProfiles.isEmpty()) {
                        // Store Profile ID, not Contact ID
                        context.academicAssociateId = aaProfiles[0].Id;
                        context.academicAssociateName = aaProfiles[0].Academic_Associate__r.Name;
                        System.debug('Loaded AA from Profile: ' + context.academicAssociateName);
                    }
                } catch (Exception e) {
                    System.debug('Error querying AA_Profile__c: ' + e.getMessage());
                    // Fallback: Try as Contact ID directly, but find Profile
                    try {
                        List<AA_Profile__c> profiles = [
                            SELECT Id, Academic_Associate__r.Name 
                            FROM AA_Profile__c 
                            WHERE Academic_Associate__c = :academicAssociateId 
                            LIMIT 1
                        ];
                        
                        if (!profiles.isEmpty()) {
                            context.academicAssociateId = profiles[0].Id;
                            context.academicAssociateName = profiles[0].Academic_Associate__r.Name;
                            System.debug('Loaded AA Profile from Contact ID: ' + context.academicAssociateName);
                        } else {
                            // If no profile found, try just getting name for display (though ID will be invalid for save)
                            List<Contact> aas = [SELECT Name FROM Contact WHERE Id = :academicAssociateId LIMIT 1];
                            if (!aas.isEmpty()) {
                                context.academicAssociateName = aas[0].Name;
                                // Don't set ID if it's not a Profile ID, to avoid save error
                            }
                        }
                    } catch (Exception ex) {
                        System.debug('Error querying Contact/Profile: ' + ex.getMessage());
                    }
                }
            }
            
            /* Commented out: Automatic AA lookup from junction table
             * This was causing ASA feedback to show AA name
             * If AA ID is not provided in URL, don't try to find it
            // If AA not provided but Course Offering is, try to find AA via junction
            if (String.isBlank(academicAssociateId) && String.isNotBlank(courseOfferingId)) {
                try {
                    List<Course_AA_Assignment__c> assignments = [
                        SELECT Academic_Associate__c, Academic_Associate__r.Name
                        FROM Course_AA_Assignment__c
                        WHERE Course_Offering__c = :courseOfferingId
                        AND Is_Active__c = true
                        ORDER BY CreatedDate DESC
                        LIMIT 1
                    ];
                    
                    if (!assignments.isEmpty()) {
                        context.academicAssociateId = assignments[0].Academic_Associate__c;
                        context.academicAssociateName = assignments[0].Academic_Associate__r.Name;
                    }
                } catch (Exception e) {
                    System.debug('Course_AA_Assignment__c query failed: ' + e.getMessage());
                }
            }
            */
            
        } catch (Exception e) {
            System.debug('Error loading context: ' + e.getMessage());
        }
        
        return context;
    }
    
    /**
     * @description Validate if GUID has already been used
     * @param guid Unique identifier from URL
     * @return Boolean true if already used
     */
    @AuraEnabled
    public static Boolean validateSubmission(String guid) {
        try {
            if (String.isBlank(guid)) {
                return false;
            }
            
            Integer existingCount = [
                SELECT COUNT()
                FROM Feedback__c
                WHERE Survey_Response_Id__c = :guid
            ];
            
            return existingCount > 0;
            
        } catch (Exception e) {
            System.debug('Error validating submission: ' + e.getMessage());
            throw new AuraHandledException('Error validating submission: ' + e.getMessage());
        }
    }
    
    /**
     * @description Validate if user can submit feedback for this AA-Course combination
     * @param courseOfferingId Course Offering ID
     * @param academicAssociateId Academic Associate ID
     * @param submitterEmail Email of submitter (optional)
     * @return Map with 'canSubmit' boolean and 'message' string
     */
    @AuraEnabled
    public static Map<String, Object> validateFeedbackEligibility(
        String courseOfferingId,
        String academicAssociateId,
        String submitterEmail
    ) {
        Map<String, Object> result = new Map<String, Object>();
        
        try {
            // Allow submission if IDs not provided
            if (String.isBlank(courseOfferingId) || String.isBlank(academicAssociateId)) {
                result.put('canSubmit', true);
                result.put('message', '');
                return result;
            }
            
            // Check if feedback already exists for this combination
            List<Feedback__c> existingFeedback = [
                SELECT Id, CreatedDate
                FROM Feedback__c
                WHERE Course_Offering__c = :courseOfferingId
                AND Academic_Associate__c = :academicAssociateId
                LIMIT 1
            ];
            
            if (!existingFeedback.isEmpty()) {
                result.put('canSubmit', false);
                result.put('message', 'You have already submitted feedback for this Academic Associate on this course.');
                result.put('existingFeedbackId', existingFeedback[0].Id);
                return result;
            }
            
            // All validations passed
            result.put('canSubmit', true);
            result.put('message', '');
            
        } catch (Exception e) {
            System.debug('Error validating eligibility: ' + e.getMessage());
            // Allow submission on error
            result.put('canSubmit', true);
            result.put('message', '');
        }
        
        return result;
    }
    
    /**
     * @description Create feedback record with answers
     * @param feedbackData JSON string of FeedbackWrapper
     * @return Id of created Feedback record
     */
    @AuraEnabled
    public static Id createFeedback(String feedbackData) {
        try {
            System.debug('Received feedbackData: ' + feedbackData);
            
            FeedbackWrapper wrapper = (FeedbackWrapper) JSON.deserialize(
                feedbackData, 
                FeedbackWrapper.class
            );
            
            // Validate required data
            if (wrapper.feedback == null) {
                throw new AuraHandledException('Feedback data is required');
            }
            
            System.debug('Deserialized feedback wrapper with ' + 
                        (wrapper.answers != null ? wrapper.answers.size() : 0) + ' answers');
            
            // Set default values
            if (String.isBlank(wrapper.feedback.Status__c)) {
                wrapper.feedback.Status__c = 'Published';
            }
            
            // Determine if this is AA or ASA feedback
            Boolean isAAFeedback = String.isNotBlank(wrapper.templateName) && 
                                   wrapper.templateName.contains('AA') && 
                                   !wrapper.templateName.contains('ASA');
            Boolean isASAFeedback = String.isNotBlank(wrapper.templateName) && 
                                    wrapper.templateName.contains('ASA');
            
            // Set meaningful Name based on feedback type
            String feedbackName = '';
            if (isAAFeedback) {
                // For AA feedback: "Feedback For AA - <AA Profile Name>"
                String aaName = null;
                if (wrapper.feedback.Academic_Associate__c != null) {
                    try {
                        List<AA_Profile__c> aaProfiles = [
                            SELECT Id, Academic_Associate__r.Name
                            FROM AA_Profile__c
                            WHERE Id = :wrapper.feedback.Academic_Associate__c
                            LIMIT 1
                        ];
                        if (!aaProfiles.isEmpty() && aaProfiles[0].Academic_Associate__r.Name != null) {
                            aaName = aaProfiles[0].Academic_Associate__r.Name;
                        }
                    } catch (Exception e) {
                        System.debug('Error getting AA name for feedback naming: ' + e.getMessage());
                    }
                }
                if (String.isNotBlank(aaName)) {
                    feedbackName = 'Feedback For AA - ' + aaName;
                } else {
                    feedbackName = 'Feedback For AA - ' + Date.today().format();
                }
            } else if (isASAFeedback) {
                // For ASA feedback: "Feedback For ASA - Date"
                feedbackName = 'Feedback For ASA - ' + Date.today().format();
            } else {
                // Fallback for other feedback types
                String namePrefix = String.isNotBlank(wrapper.templateName) ? wrapper.templateName : 'Feedback';
                feedbackName = namePrefix + ' - ' + Date.today().format();
            }
            
            // Ensure name doesn't exceed 80 characters
            if (feedbackName.length() > 80) {
                feedbackName = feedbackName.substring(0, 80);
            }
            wrapper.feedback.Name = feedbackName;
            
            // Set Submitter fields based on template and context
            if (String.isNotBlank(wrapper.templateName)) {
                if (wrapper.templateName.contains('Faculty')) {
                    wrapper.feedback.Submitter_Type__c = 'Faculty';
                    // Populate Submitter_Contact__c and Submitter_User__c for Faculty
                    try {
                        Id facultyContactId = null;
                        if (String.isNotBlank(wrapper.facultyId)) {
                            facultyContactId = (Id)wrapper.facultyId;
                        }
                        
                        if (facultyContactId == null) {
                            facultyContactId = wrapper.feedback.Submitter_Contact__c;
                        }

                        if (facultyContactId != null) {
                            wrapper.feedback.Submitter_Contact__c = facultyContactId;
                            
                            // Find the user linked to this contact
                            List<User> users = [SELECT Id FROM User WHERE ContactId = :facultyContactId AND IsActive = true LIMIT 1];
                            if (!users.isEmpty()) {
                                wrapper.feedback.Submitter_User__c = users[0].Id;
                            }
                        }
                        
                        if (wrapper.feedback.Submitter_User__c == null) {
                            wrapper.feedback.Submitter_User__c = UserInfo.getUserId();
                        }
                    } catch (Exception e) {
                        System.debug('Error setting Faculty submitter fields: ' + e.getMessage());
                    }
                } else if (wrapper.templateName.contains('Student')) {
                    wrapper.feedback.Submitter_Type__c = 'Student';
                    // Default to current user
                    Id submitterUserId = UserInfo.getUserId();
                    Id submitterContactId = null;
                    
                    // If coming from a Case, find the User associated with the Case Contact
                    if (String.isNotBlank(wrapper.caseId)) {
                        try {
                            List<Case> cases = [SELECT ContactId FROM Case WHERE Id = :wrapper.caseId LIMIT 1];
                            if (!cases.isEmpty() && cases[0].ContactId != null) {
                                submitterContactId = cases[0].ContactId;
                                // Find the user linked to this contact
                                List<User> users = [SELECT Id FROM User WHERE ContactId = :submitterContactId AND IsActive = true LIMIT 1];
                                if (!users.isEmpty()) {
                                    submitterUserId = users[0].Id;
                                }
                            }
                        } catch (Exception e) {
                            System.debug('Error resolving student details from Case: ' + e.getMessage());
                        }
                    } else {
                        // Fallback: Check if current user has a contact (likely if logged in student)
                        try {
                            User u = [SELECT ContactId FROM User WHERE Id = :submitterUserId LIMIT 1];
                            submitterContactId = u.ContactId;
                        } catch (Exception e) {
                            System.debug('Error getting contact from current user: ' + e.getMessage());
                        }
                    }
                    
                    try {
                        wrapper.feedback.Submitter_User__c = submitterUserId;
                        if (submitterContactId != null) {
                            wrapper.feedback.Submitter_Contact__c = submitterContactId;
                        }
                    } catch (Exception e) {
                        System.debug('Error setting Student submitter fields: ' + e.getMessage());
                    }
                }
            }
            
            // Populate Feedback_for__c with AA User if Academic_Associate__c is present
            if (wrapper.feedback.Academic_Associate__c != null) {
                try {
                    // Query AA_Profile__c to get the related Contact and then the Linked_User_Id__c
                    List<AA_Profile__c> aaProfiles = [
                        SELECT Id, Academic_Associate__c, Academic_Associate__r.Linked_User_Id__c
                        FROM AA_Profile__c
                        WHERE Id = :wrapper.feedback.Academic_Associate__c
                        LIMIT 1
                    ];
                    
                    if (!aaProfiles.isEmpty() && aaProfiles[0].Academic_Associate__r.Linked_User_Id__c != null) {
                        wrapper.feedback.Feedback_for__c = aaProfiles[0].Academic_Associate__r.Linked_User_Id__c;
                        System.debug('Set Feedback_for__c to User: ' + wrapper.feedback.Feedback_for__c);
                    } else {
                        System.debug('No Linked_User_Id__c found for AA Profile: ' + wrapper.feedback.Academic_Associate__c);
                    }
                } catch (Exception e) {
                    System.debug('Error populating Feedback_for__c: ' + e.getMessage());
                }
            }
            
            // Handle Manual AA Name Resolution
            if (String.isNotBlank(wrapper.manualAAName)) {
                try {
                    String cleanName = wrapper.manualAAName.trim();
                    String searchName = '%' + cleanName + '%';
                    List<AA_Profile__c> profiles = [
                        SELECT Id, Academic_Associate__c 
                        FROM AA_Profile__c 
                        WHERE Academic_Associate__r.Name LIKE :searchName
                        LIMIT 1
                    ];
                    
                    if (!profiles.isEmpty()) {
                        wrapper.feedback.Academic_Associate__c = profiles[0].Id;
                        // wrapper.feedback.Feedback_for__c = profiles[0].Academic_Associate__c; // If needed
                        System.debug('Resolved AA from manual name: ' + wrapper.manualAAName);
                    } else {
                        System.debug('Could not find AA with name: ' + wrapper.manualAAName);
                    }
                } catch (Exception e) {
                    System.debug('Error resolving manual AA name: ' + e.getMessage());
                }
            }
            
            Savepoint sp = Database.setSavepoint();
            
            try {
                // Check if this is an update to existing Pending feedback (via token)
                Feedback__c existingFeedback = null;
                String feedbackToken = wrapper.feedbackToken;
                
                // Also check if token was passed in the feedback record itself
                if (String.isBlank(feedbackToken) && wrapper.feedback.Feedback_Link_Token__c != null) {
                    feedbackToken = wrapper.feedback.Feedback_Link_Token__c;
                }
                
                if (String.isNotBlank(feedbackToken)) {
                    List<Feedback__c> existing = [
                        SELECT Id, Status__c, Feedback_Template__c, Academic_Associate__c,
                               Course_Offering__c, Program__c, Academic_Term__c
                        FROM Feedback__c
                        WHERE Feedback_Link_Token__c = :feedbackToken
                        AND Status__c = 'Pending'
                        LIMIT 1
                    ];
                    if (!existing.isEmpty()) {
                        existingFeedback = existing[0];
                        // Preserve the existing record ID for update
                        wrapper.feedback.Id = existingFeedback.Id;
                        // Preserve pre-populated fields from trigger if not set
                        if (wrapper.feedback.Academic_Associate__c == null) {
                            wrapper.feedback.Academic_Associate__c = existingFeedback.Academic_Associate__c;
                        }
                        if (wrapper.feedback.Course_Offering__c == null) {
                            wrapper.feedback.Course_Offering__c = existingFeedback.Course_Offering__c;
                        }
                        if (wrapper.feedback.Program__c == null) {
                            wrapper.feedback.Program__c = existingFeedback.Program__c;
                        }
                        if (wrapper.feedback.Academic_Term__c == null) {
                            wrapper.feedback.Academic_Term__c = existingFeedback.Academic_Term__c;
                        }
                    }
                }
                
                // Set status to Submitted and capture submission date
                wrapper.feedback.Status__c = 'Submitted';
                wrapper.feedback.Submitted_Date__c = DateTime.now();
                
                // Insert or Update Feedback record
                if (existingFeedback != null) {
                    update wrapper.feedback;
                    System.debug('Feedback record updated with ID: ' + wrapper.feedback.Id);
                } else {
                    insert wrapper.feedback;
                    System.debug('Feedback record created with ID: ' + wrapper.feedback.Id);
                }
                
                // Build map of question ID to weightage for weighted calculation
                Map<Id, Decimal> questionWeightages = new Map<Id, Decimal>();
                if (wrapper.answers != null && !wrapper.answers.isEmpty()) {
                    Set<Id> questionIds = new Set<Id>();
                    for (AnswerWrapper answer : wrapper.answers) {
                        if (answer.questionId != null) {
                            questionIds.add(answer.questionId);
                        }
                    }
                    
                    if (!questionIds.isEmpty()) {
                        for (Feedback_Template_Question__c q : [
                            SELECT Id, Weightage__c, Question_Type_c__c
                            FROM Feedback_Template_Question__c
                            WHERE Id IN :questionIds
                        ]) {
                            // Default weightage to 1 if not specified
                            Decimal weightage = q.Weightage__c != null ? q.Weightage__c : 1;
                            questionWeightages.put(q.Id, weightage);
                        }
                    }
                }
                
                // Calculate Overall Rating using weighted average and prepare answers
                Decimal totalWeightedRating = 0;
                Decimal totalWeightage = 0;
                List<Feedback_Answer__c> answerRecords = new List<Feedback_Answer__c>();
                
                if (wrapper.answers == null || wrapper.answers.isEmpty()) {
                     // Throw error to debug if answers are missing
                     throw new AuraHandledException('No answers received from client. Please ensure questions are answered.');
                } else {
                    for (AnswerWrapper answer : wrapper.answers) {
                        if (answer.questionId == null) {
                            System.debug('WARNING: Question ID is null for answer');
                            continue;
                        }

                        Feedback_Answer__c answerRecord = new Feedback_Answer__c(
                            Feedback__c = wrapper.feedback.Id,
                            Feedback_Template_Question__c = answer.questionId,
                            Question__c = answer.questionText,
                            Answer_Text__c = answer.textAnswer,
                            Answer_Picklist__c = answer.picklistAnswer
                        );
                        
                        // Handle rating answer conversion from String to Decimal
                        if (String.isNotBlank(answer.ratingAnswer)) {
                            try {
                                Decimal ratingValue = Decimal.valueOf(answer.ratingAnswer);
                                answerRecord.Answer_Rating__c = ratingValue;
                                
                                // Accumulate for weighted overall rating
                                if (ratingValue != null && ratingValue > 0) {
                                    Decimal weightage = questionWeightages.containsKey(answer.questionId) 
                                        ? questionWeightages.get(answer.questionId) 
                                        : 1;
                                    totalWeightedRating += ratingValue * weightage;
                                    totalWeightage += weightage;
                                }
                            } catch (Exception e) {
                                System.debug('Error converting rating: ' + e.getMessage());
                            }
                        }
                        
                        // Handle order conversion from String to Number
                        if (String.isNotBlank(answer.order)) {
                            try {
                                answerRecord.Order__c = Decimal.valueOf(answer.order);
                            } catch (Exception e) {
                                System.debug('Error converting order: ' + e.getMessage());
                            }
                        }
                        
                        answerRecords.add(answerRecord);
                    }
                    
                    // Insert all answers
                    if (!answerRecords.isEmpty()) {
                        insert answerRecords;
                        System.debug('Inserted ' + answerRecords.size() + ' answer records');
                    }
                    
                    // Calculate and update weighted Overall Rating
                    if (totalWeightage > 0) {
                        Decimal weightedAverage = (totalWeightedRating / totalWeightage).setScale(2);
                        wrapper.feedback.Overall_Rating__c = String.valueOf(weightedAverage);
                        update wrapper.feedback;
                        System.debug('Updated Overall Rating (weighted): ' + weightedAverage);
                    }
                }
                
                return wrapper.feedback.Id;
                
            } catch (Exception e) {
                Database.rollback(sp);
                System.debug('Error in feedback creation, rolling back: ' + e.getMessage());
                System.debug('Stack trace: ' + e.getStackTraceString());
                throw e;
            }
            
        } catch (Exception e) {
            System.debug('Error in createFeedback: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            throw new AuraHandledException('Error creating feedback: ' + e.getMessage());
        }
    }
    
    /**
     * @description Get feedback record types
     * @return Map of record type developer names to IDs
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Id> getFeedbackRecordTypes() {
        Map<String, Id> recordTypeMap = new Map<String, Id>();
        
        try {
            List<RecordType> recordTypes = [
                SELECT Id, DeveloperName, Name
                FROM RecordType
                WHERE SObjectType = 'Feedback__c'
                AND IsActive = true
            ];
            
            for (RecordType rt : recordTypes) {
                recordTypeMap.put(rt.DeveloperName, rt.Id);
            }
            
            System.debug('Loaded ' + recordTypeMap.size() + ' record types');
            
        } catch (Exception e) {
            System.debug('Error loading record types: ' + e.getMessage());
        }
        
        return recordTypeMap;
    }
    
    /**
     * @description Generate unique GUID for tracking
     * @return String GUID
     */
    @AuraEnabled
    public static String generateGuid() {
        return String.valueOf(Crypto.getRandomLong()) + 
               String.valueOf(System.currentTimeMillis()) + 
               String.valueOf(UserInfo.getUserId()).left(8);
    }
    
    /**
     * @description Get feedback context by token
     * Used when recipient clicks the feedback link from email
     * @param token Unique feedback link token
     * @return FeedbackContextDTO with feedback and template info
     */
    @AuraEnabled
    public static FeedbackContextDTO getFeedbackByToken(String token) {
        FeedbackContextDTO dto = new FeedbackContextDTO();
        
        try {
            if (String.isBlank(token)) {
                throw new AuraHandledException('Feedback token is required');
            }
            
            // Query feedback record by token
            List<Feedback__c> feedbackRecords = [
                SELECT Id, Name, Status__c, Feedback_Link_Token__c,
                       Feedback_Template__c, Feedback_Template__r.Name,
                       Feedback_Template__r.Applicable_For__c,
                       Academic_Associate__c, Academic_Associate__r.Academic_Associate__r.Name,
                       Course_Offering__c, Course_Offering__r.Name, 
                       Course_Offering__r.LearningCourse.Name,
                       Program__c, Program__r.Name,
                       Academic_Term__c,
                       Due_Date__c, Submitter_Type__c
                FROM Feedback__c
                WHERE Feedback_Link_Token__c = :token
                LIMIT 1
            ];
            
            if (feedbackRecords.isEmpty()) {
                dto.isValid = false;
                dto.errorMessage = 'Invalid feedback link. Please contact support.';
                return dto;
            }
            
            Feedback__c fb = feedbackRecords[0];
            
            // Check status
            if (fb.Status__c == 'Submitted') {
                dto.isValid = false;
                dto.errorMessage = 'Feedback has already been submitted.';
                dto.isAlreadySubmitted = true;
                return dto;
            }
            
            if (fb.Status__c == 'Expired') {
                dto.isValid = false;
                dto.errorMessage = 'This feedback request has expired.';
                dto.isExpired = true;
                return dto;
            }
            
            // Check due date
            if (fb.Due_Date__c != null && fb.Due_Date__c < Date.today()) {
                dto.isValid = false;
                dto.errorMessage = 'The deadline for this feedback has passed.';
                dto.isExpired = true;
                return dto;
            }
            
            // Populate DTO
            dto.isValid = true;
            dto.feedbackId = fb.Id;
            dto.feedbackToken = fb.Feedback_Link_Token__c;
            dto.status = fb.Status__c;
            dto.dueDate = fb.Due_Date__c;
            dto.submitterType = fb.Submitter_Type__c;
            
            if (fb.Feedback_Template__r != null) {
                dto.templateId = fb.Feedback_Template__c;
                dto.templateName = fb.Feedback_Template__r.Name;
                dto.scenario = fb.Feedback_Template__r.Applicable_For__c;
            }
            
            if (fb.Academic_Associate__r != null && fb.Academic_Associate__r.Academic_Associate__r != null) {
                dto.academicAssociateId = fb.Academic_Associate__c;
                dto.academicAssociateName = fb.Academic_Associate__r.Academic_Associate__r.Name;
            }
            
            if (fb.Course_Offering__r != null) {
                dto.courseOfferingId = fb.Course_Offering__c;
                // Use LearningCourse.Name for display
                dto.courseName = fb.Course_Offering__r.LearningCourse != null 
                    ? fb.Course_Offering__r.LearningCourse.Name 
                    : fb.Course_Offering__r.Name;
            }
            
            if (fb.Program__r != null) {
                dto.programId = fb.Program__c;
                dto.programName = fb.Program__r.Name;
            }
            
            // Load template questions
            if (fb.Feedback_Template__c != null) {
                dto.questions = [
                    SELECT Id, Question_Text__c, Question_Type_c__c, Required__c,
                           Order__c, Picklist_Options__c, Min_Rating__c, Max_Rating__c,
                           Weightage__c
                    FROM Feedback_Template_Question__c
                    WHERE Feedback_Template__c = :fb.Feedback_Template__c
                    ORDER BY Order__c ASC NULLS LAST
                ];
            }
            
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            System.debug('Error in getFeedbackByToken: ' + e.getMessage());
            throw new AuraHandledException('Error loading feedback: ' + e.getMessage());
        }
        
        return dto;
    }
    
    /**
     * @description DTO for feedback context loaded by token
     */
    public class FeedbackContextDTO {
        @AuraEnabled public Boolean isValid { get; set; }
        @AuraEnabled public String errorMessage { get; set; }
        @AuraEnabled public Boolean isAlreadySubmitted { get; set; }
        @AuraEnabled public Boolean isExpired { get; set; }
        
        @AuraEnabled public Id feedbackId { get; set; }
        @AuraEnabled public String feedbackToken { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Date dueDate { get; set; }
        @AuraEnabled public String submitterType { get; set; }
        
        @AuraEnabled public Id templateId { get; set; }
        @AuraEnabled public String templateName { get; set; }
        @AuraEnabled public String scenario { get; set; }
        
        @AuraEnabled public Id academicAssociateId { get; set; }
        @AuraEnabled public String academicAssociateName { get; set; }
        
        @AuraEnabled public Id courseOfferingId { get; set; }
        @AuraEnabled public String courseName { get; set; }
        
        @AuraEnabled public Id programId { get; set; }
        @AuraEnabled public String programName { get; set; }
        
        @AuraEnabled public List<Feedback_Template_Question__c> questions { get; set; }
        
        public FeedbackContextDTO() {
            this.isValid = false;
            this.isAlreadySubmitted = false;
            this.isExpired = false;
        }
    }
    
    // ═══════════════════════════════════════════════════════════════
    // BATCH TOKEN MODE - For Course-wise Feedback
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @description DTO for batch feedback option (Course-AA combination)
     */
    public class BatchFeedbackOptionDTO {
        @AuraEnabled public Id feedbackId { get; set; }
        @AuraEnabled public String feedbackToken { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Id academicAssociateId { get; set; }
        @AuraEnabled public String academicAssociateName { get; set; }
        @AuraEnabled public Id courseOfferingId { get; set; }
        @AuraEnabled public String courseName { get; set; }
        @AuraEnabled public Boolean isSubmitted { get; set; }
        @AuraEnabled public String displayLabel { get; set; }
    }
    
    /**
     * @description DTO for batch token context (multiple options)
     */
    public class BatchFeedbackContextDTO {
        @AuraEnabled public Boolean isValid { get; set; }
        @AuraEnabled public String errorMessage { get; set; }
        @AuraEnabled public String batchToken { get; set; }
        @AuraEnabled public Id templateId { get; set; }
        @AuraEnabled public String templateName { get; set; }
        @AuraEnabled public String scenario { get; set; }
        @AuraEnabled public String submitterType { get; set; }
        @AuraEnabled public Date dueDate { get; set; }
        @AuraEnabled public List<BatchFeedbackOptionDTO> feedbackOptions { get; set; }
        @AuraEnabled public List<Feedback_Template_Question__c> questions { get; set; }
        @AuraEnabled public Integer totalOptions { get; set; }
        @AuraEnabled public Integer submittedCount { get; set; }
        @AuraEnabled public Integer pendingCount { get; set; }
        
        public BatchFeedbackContextDTO() {
            this.isValid = false;
            this.feedbackOptions = new List<BatchFeedbackOptionDTO>();
        }
    }
    
    /**
     * @description Get all feedback options for a batch token (Course-wise scenarios)
     * Returns multiple Course-AA combinations as picklist options
     * @param batchToken Batch token from email link
     * @return BatchFeedbackContextDTO with all options
     */
    @AuraEnabled
    public static BatchFeedbackContextDTO getFeedbacksByBatchToken(String batchToken) {
        BatchFeedbackContextDTO dto = new BatchFeedbackContextDTO();
        
        try {
            if (String.isBlank(batchToken)) {
                dto.errorMessage = 'Batch token is required';
                return dto;
            }
            
            // Query all feedback records with this batch token
            List<Feedback__c> feedbackRecords = [
                SELECT Id, Name, Status__c, Feedback_Link_Token__c, Batch_Token__c,
                       Feedback_Template__c, Feedback_Template__r.Name,
                       Feedback_Template__r.Applicable_For__c, Feedback_Scenario__c,
                       Academic_Associate__c, Academic_Associate__r.Academic_Associate__r.Name,
                       Course_Offering__c, Course_Offering__r.Name, 
                       Course_Offering__r.LearningCourse.Name,
                       Program__c, Program__r.Name,
                       Due_Date__c, Submitter_Type__c
                FROM Feedback__c
                WHERE Batch_Token__c = :batchToken
                ORDER BY Course_Offering__r.LearningCourse.Name, 
                         Academic_Associate__r.Academic_Associate__r.Name
            ];
            
            if (feedbackRecords.isEmpty()) {
                dto.errorMessage = 'Invalid feedback link. Please contact support.';
                return dto;
            }
            
            // Populate common fields from first record
            Feedback__c firstFb = feedbackRecords[0];
            dto.isValid = true;
            dto.batchToken = batchToken;
            dto.submitterType = firstFb.Submitter_Type__c;
            dto.dueDate = firstFb.Due_Date__c;
            dto.scenario = firstFb.Feedback_Scenario__c;
            
            if (firstFb.Feedback_Template__r != null) {
                dto.templateId = firstFb.Feedback_Template__c;
                dto.templateName = firstFb.Feedback_Template__r.Name;
            }
            
            // Build options list
            Integer submittedCount = 0;
            for (Feedback__c fb : feedbackRecords) {
                BatchFeedbackOptionDTO option = new BatchFeedbackOptionDTO();
                option.feedbackId = fb.Id;
                option.feedbackToken = fb.Feedback_Link_Token__c;
                option.status = fb.Status__c;
                option.isSubmitted = (fb.Status__c == 'Submitted');
                
                if (option.isSubmitted) {
                    submittedCount++;
                }
                
                if (fb.Academic_Associate__r != null && fb.Academic_Associate__r.Academic_Associate__r != null) {
                    option.academicAssociateId = fb.Academic_Associate__c;
                    option.academicAssociateName = fb.Academic_Associate__r.Academic_Associate__r.Name;
                }
                
                if (fb.Course_Offering__r != null) {
                    option.courseOfferingId = fb.Course_Offering__c;
                    option.courseName = fb.Course_Offering__r.LearningCourse != null 
                        ? fb.Course_Offering__r.LearningCourse.Name 
                        : fb.Course_Offering__r.Name;
                }
                
                // Build display label for picklist
                option.displayLabel = buildOptionLabel(option);
                
                dto.feedbackOptions.add(option);
            }
            
            dto.totalOptions = feedbackRecords.size();
            dto.submittedCount = submittedCount;
            dto.pendingCount = feedbackRecords.size() - submittedCount;
            
            // Check if all submitted
            if (submittedCount == feedbackRecords.size()) {
                dto.isValid = false;
                dto.errorMessage = 'All feedback forms have already been submitted. Thank you!';
                return dto;
            }
            
            // Check due date
            if (firstFb.Due_Date__c != null && firstFb.Due_Date__c < Date.today()) {
                dto.isValid = false;
                dto.errorMessage = 'The deadline for this feedback has passed.';
                return dto;
            }
            
            // Load template questions
            if (firstFb.Feedback_Template__c != null) {
                dto.questions = [
                    SELECT Id, Question_Text__c, Question_Type_c__c, Required__c,
                           Order__c, Picklist_Options__c, Min_Rating__c, Max_Rating__c,
                           Weightage__c
                    FROM Feedback_Template_Question__c
                    WHERE Feedback_Template__c = :firstFb.Feedback_Template__c
                    ORDER BY Order__c ASC NULLS LAST
                ];
            }
            
        } catch (Exception e) {
            System.debug('Error in getFeedbacksByBatchToken: ' + e.getMessage());
            dto.errorMessage = 'Error loading feedback: ' + e.getMessage();
        }
        
        return dto;
    }
    
    /**
     * @description Build display label for picklist option
     */
    private static String buildOptionLabel(BatchFeedbackOptionDTO option) {
        String label = '';
        
        if (String.isNotBlank(option.courseName)) {
            label = option.courseName;
        }
        
        if (String.isNotBlank(option.academicAssociateName)) {
            if (String.isNotBlank(label)) {
                label += ' - ';
            }
            label += option.academicAssociateName;
        }
        
        if (option.isSubmitted) {
            label += ' (Submitted)';
        }
        
        return label;
    }
    
    /**
     * @description Submit feedback for a selected option from batch
     * @param feedbackId ID of the specific feedback record to submit
     * @param answers List of answer data
     * @param overallRating Overall rating value
     * @param comments Optional comments
     * @return Boolean success
     */
    @AuraEnabled
    public static Boolean submitBatchFeedback(
        Id feedbackId,
        String answersJson,
        Decimal overallRating,
        String comments
    ) {
        try {
            if (feedbackId == null) {
                throw new AuraHandledException('Feedback ID is required');
            }
            
            // Get the feedback record
            Feedback__c feedback = [
                SELECT Id, Status__c, Feedback_Template__c, Due_Date__c
                FROM Feedback__c
                WHERE Id = :feedbackId
                LIMIT 1
            ];
            
            // Validate status
            if (feedback.Status__c == 'Submitted') {
                throw new AuraHandledException('This feedback has already been submitted');
            }
            
            // Check due date
            if (feedback.Due_Date__c != null && feedback.Due_Date__c < Date.today()) {
                throw new AuraHandledException('The deadline for this feedback has passed');
            }
            
            // Parse answers
            List<AnswerData> answers = (List<AnswerData>) JSON.deserialize(
                answersJson, 
                List<AnswerData>.class
            );
            
            // Create answer records
            List<Feedback_Answer__c> answerRecords = new List<Feedback_Answer__c>();
            for (AnswerData ans : answers) {
                Feedback_Answer__c answerRecord = new Feedback_Answer__c();
                answerRecord.Feedback__c = feedbackId;
                answerRecord.Question__c = ans.questionId;
                
                if (ans.ratingValue != null) {
                    answerRecord.Answer_Rating__c = ans.ratingValue;
                }
                if (String.isNotBlank(ans.textValue)) {
                    answerRecord.Answer_Text__c = ans.textValue;
                }
                if (String.isNotBlank(ans.picklistValue)) {
                    answerRecord.Answer_Picklist__c = ans.picklistValue;
                }
                
                answerRecords.add(answerRecord);
            }
            
            if (!answerRecords.isEmpty()) {
                insert answerRecords;
            }
            
            // Update feedback record
            feedback.Status__c = 'Submitted';
            feedback.Submitted_Date__c = DateTime.now();
            if (overallRating != null) {
                feedback.Overall_Rating__c = String.valueOf(overallRating);
            }
            if (String.isNotBlank(comments)) {
                feedback.Comments__c = comments;
            }
            update feedback;
            
            return true;
            
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            System.debug('Error in submitBatchFeedback: ' + e.getMessage());
            throw new AuraHandledException('Error submitting feedback: ' + e.getMessage());
        }
    }
    
    /**
     * @description Answer data wrapper for JSON deserialization
     */
    public class AnswerData {
        public Id questionId { get; set; }
        public Decimal ratingValue { get; set; }
        public String textValue { get; set; }
        public String picklistValue { get; set; }
    }
}