/**
 * @description Service class for feedback triggering operations
 * Handles bulk creation of Feedback__c records and email sending
 * Uses Queueable for large batches to handle governor limits
 * 
 * Two modes:
 * 1. Course-wise (Faculty/Student to AA): Single batch token per recipient, picklist in form
 * 2. Quarterly (Exam/PO/RM/AD to AA): Unique token per AA, individual links
 * 
 * @author ISB Team
 * @date 2026
 */
public with sharing class FeedbackTriggerService {
    
    private static final Integer EMAIL_BATCH_SIZE = 100;
    private static final Integer LARGE_BATCH_THRESHOLD = 500;
    private static final Integer QUEUEABLE_BATCH_SIZE = 100;
    
    // Course-wise scenarios use batch token (single link with picklist)
    private static final Set<String> COURSE_WISE_SCENARIOS = new Set<String>{
        'Student-to-AA', 'Faculty-to-AA'
    };
    
    // Quarterly scenarios use unique tokens per AA
    private static final Set<String> QUARTERLY_SCENARIOS = new Set<String>{
        'Exam-Office-to-AA', 'Program-Office-to-AA', 
        'Reporting-Manager-to-AA', 'Associate-Director-to-AA'
    };
    
    /**
     * @description Main entry point - triggers feedback for given request
     * Step 1: Create Feedback__c records with Status='Pending'
     * Step 2: Send emails with unique links per AA
     * @param request TriggerRequest from controller
     * @return TriggerResponse with results
     */
    public static FeedbackManagementController.TriggerResponse triggerFeedback(
        FeedbackManagementController.TriggerRequest request
    ) {
        FeedbackManagementController.TriggerResponse response = new FeedbackManagementController.TriggerResponse();
        response.success = false;
        response.feedbackRecordsCreated = 0;
        response.emailsSent = 0;
        
        try {
            // Validate template exists
            Feedback_Template__c template = [
                SELECT Id, Name, Applicable_For__c 
                FROM Feedback_Template__c 
                WHERE Id = :request.templateId 
                AND Active__c = true 
                LIMIT 1
            ];
            
            // Get recipients based on scenario
            List<FeedbackRecordData> feedbackDataList = buildFeedbackDataList(request, template);
            
            if (feedbackDataList.isEmpty()) {
                response.errorMessage = 'No recipients found for the selected criteria';
                return response;
            }
            
            // Step 1: Create Feedback records with Pending status
            List<Feedback__c> createdRecords = createFeedbackRecords(feedbackDataList, request, template);
            response.feedbackRecordsCreated = createdRecords.size();
            
            if (createdRecords.isEmpty()) {
                response.errorMessage = 'Failed to create feedback records';
                return response;
            }
            
            // Step 2: Send emails
            // Use Queueable for large batches
            if (createdRecords.size() > LARGE_BATCH_THRESHOLD) {
                // Enqueue for async processing
                System.enqueueJob(new FeedbackEmailQueueable(createdRecords, template.Name));
                response.emailsSent = createdRecords.size(); // Estimated
                response.warnings.add('Large batch detected. Emails will be sent asynchronously.');
            } else {
                Integer emailsSent = sendFeedbackEmails(createdRecords, template.Name);
                response.emailsSent = emailsSent;
            }
            
            response.success = true;
            
        } catch (Exception e) {
            response.errorMessage = 'Error: ' + e.getMessage();
            System.debug('FeedbackTriggerService error: ' + e.getStackTraceString());
        }
        
        return response;
    }
    
    /**
     * @description Data structure for feedback record creation
     */
    public class FeedbackRecordData {
        // Recipient info
        public Id recipientContactId { get; set; }
        public Id recipientUserId { get; set; }
        public String recipientEmail { get; set; }
        public String recipientName { get; set; }
        public String recipientType { get; set; }
        
        // AA info
        public Id aaProfileId { get; set; }
        public String aaName { get; set; }
        public Id aaContactId { get; set; }
        
        // Course context
        public Id courseOfferingId { get; set; }
        public String courseName { get; set; }
        public Id courseAAAssignmentId { get; set; }
        public Id courseFacultyId { get; set; }
        public Id courseOfferingParticipantId { get; set; }
        
        // Program context
        public Id programId { get; set; }
        public Id termId { get; set; }
        public Id locationId { get; set; }
        
        // Batch token for course-wise scenarios
        public String batchToken { get; set; }
    }
    
    /**
     * @description Build list of feedback data based on scenario
     * Course-wise scenarios: Generate batch tokens (same token per recipient)
     * Quarterly scenarios: Tokens generated per record in createFeedbackRecords
     */
    private static List<FeedbackRecordData> buildFeedbackDataList(
        FeedbackManagementController.TriggerRequest request,
        Feedback_Template__c template
    ) {
        List<FeedbackRecordData> dataList = new List<FeedbackRecordData>();
        
        String scenario = request.scenario;
        
        if (COURSE_WISE_SCENARIOS.contains(scenario)) {
            dataList = buildCourseBasedFeedbackData(request, scenario);
            
            // Generate batch tokens - same token per recipient for course-wise
            Map<String, String> recipientToBatchToken = new Map<String, String>();
            for (FeedbackRecordData data : dataList) {
                String recipientKey = getRecipientKey(data);
                if (!recipientToBatchToken.containsKey(recipientKey)) {
                    recipientToBatchToken.put(recipientKey, generateUniqueToken());
                }
                data.batchToken = recipientToBatchToken.get(recipientKey);
            }
        } else if (QUARTERLY_SCENARIOS.contains(scenario)) {
            dataList = buildQuarterlyFeedbackData(request, scenario);
            // Quarterly scenarios: No batch token, unique token per record
        } else {
            // Legacy direct AA selection
            dataList = buildDirectAAFeedbackData(request);
        }
        
        return dataList;
    }
    
    /**
     * @description Get unique key for recipient (Contact or User)
     */
    private static String getRecipientKey(FeedbackRecordData data) {
        if (data.recipientContactId != null) {
            return 'Contact:' + data.recipientContactId;
        } else if (data.recipientUserId != null) {
            return 'User:' + data.recipientUserId;
        }
        return 'Email:' + data.recipientEmail;
    }
    
    /**
     * @description Build feedback data for course-based scenarios (Student/Faculty to AA)
     * - Filters only active students (Active_Status__c = 'Active')
     * - Stores Course_AA_Assignment__c, Course_Faculty__c, CourseOfferingParticipant references
     */
    private static List<FeedbackRecordData> buildCourseBasedFeedbackData(
        FeedbackManagementController.TriggerRequest request,
        String scenario
    ) {
        List<FeedbackRecordData> dataList = new List<FeedbackRecordData>();
        
        if (request.courseOfferingIds == null || request.courseOfferingIds.isEmpty()) {
            return dataList;
        }
        
        // Get course details with LearningCourse.Name
        Map<Id, CourseOffering> courseMap = new Map<Id, CourseOffering>([
            SELECT Id, Name, LearningCourse.Name, Program__c, AcademicSessionId, Location__c
            FROM CourseOffering
            WHERE Id IN :request.courseOfferingIds
        ]);
        
        // Get AA assignments per course (only active assignments)
        Map<Id, List<Course_AA_Assignment__c>> courseToAAs = new Map<Id, List<Course_AA_Assignment__c>>();
        for (Course_AA_Assignment__c assignment : [
            SELECT Id, Course_Offering__c, Academic_Associate__c,
                   Academic_Associate__r.Academic_Associate__c,
                   Academic_Associate__r.Academic_Associate__r.Name,
                   Academic_Associate__r.Academic_Associate__r.Active_Status__c
            FROM Course_AA_Assignment__c
            WHERE Course_Offering__c IN :request.courseOfferingIds
            AND Is_Active__c = true
            AND Academic_Associate__r.Academic_Associate__r.Active_Status__c = 'Active'
        ]) {
            if (!courseToAAs.containsKey(assignment.Course_Offering__c)) {
                courseToAAs.put(assignment.Course_Offering__c, new List<Course_AA_Assignment__c>());
            }
            courseToAAs.get(assignment.Course_Offering__c).add(assignment);
        }
        
        if (scenario == 'Student-to-AA') {
            // Get students enrolled in courses (only active students)
            for (CourseOfferingParticipant cop : [
                SELECT Id, CourseOfferingId, ParticipantContactId,
                       ParticipantContact.Name, ParticipantContact.Email,
                       ParticipantContact.Active_Status__c
                FROM CourseOfferingParticipant
                WHERE CourseOfferingId IN :request.courseOfferingIds
                AND ParticipantContactId != null
                AND ParticipantContact.Email != null
                AND ParticipantContact.Active_Status__c = 'Active'
            ]) {
                CourseOffering co = courseMap.get(cop.CourseOfferingId);
                List<Course_AA_Assignment__c> aaAssignments = courseToAAs.get(cop.CourseOfferingId);
                
                if (aaAssignments != null) {
                    // Create one feedback record per Student-AA combination
                    for (Course_AA_Assignment__c aa : aaAssignments) {
                        FeedbackRecordData data = new FeedbackRecordData();
                        data.recipientContactId = cop.ParticipantContactId;
                        data.recipientEmail = cop.ParticipantContact.Email;
                        data.recipientName = cop.ParticipantContact.Name;
                        data.recipientType = 'Student';
                        data.aaProfileId = aa.Academic_Associate__c;
                        data.aaContactId = aa.Academic_Associate__r?.Academic_Associate__c;
                        data.aaName = aa.Academic_Associate__r?.Academic_Associate__r?.Name;
                        data.courseOfferingId = cop.CourseOfferingId;
                        data.courseAAAssignmentId = aa.Id;
                        data.courseOfferingParticipantId = cop.Id;
                        // Use LearningCourse.Name
                        data.courseName = co.LearningCourse != null ? co.LearningCourse.Name : co.Name;
                        data.programId = co.Program__c;
                        data.termId = co.AcademicSessionId;
                        data.locationId = co.Location__c;
                        dataList.add(data);
                    }
                }
            }
        } else if (scenario == 'Faculty-to-AA') {
            // Get faculty assigned to courses
            for (Course_Faculty__c cf : [
                SELECT Id, Course_Offering__c, Faculty__c,
                       Faculty__r.Name, Faculty__r.Email, Faculty__r.Active_Status__c
                FROM Course_Faculty__c
                WHERE Course_Offering__c IN :request.courseOfferingIds
                AND Faculty__r.Email != null
            ]) {
                CourseOffering co = courseMap.get(cf.Course_Offering__c);
                List<Course_AA_Assignment__c> aaAssignments = courseToAAs.get(cf.Course_Offering__c);
                
                if (aaAssignments != null) {
                    // Create one feedback record per Faculty-AA combination
                    for (Course_AA_Assignment__c aa : aaAssignments) {
                        FeedbackRecordData data = new FeedbackRecordData();
                        data.recipientContactId = cf.Faculty__c;
                        data.recipientEmail = cf.Faculty__r.Email;
                        data.recipientName = cf.Faculty__r.Name;
                        data.recipientType = 'Faculty';
                        data.aaProfileId = aa.Academic_Associate__c;
                        data.aaContactId = aa.Academic_Associate__r?.Academic_Associate__c;
                        data.aaName = aa.Academic_Associate__r?.Academic_Associate__r?.Name;
                        data.courseOfferingId = cf.Course_Offering__c;
                        data.courseAAAssignmentId = aa.Id;
                        data.courseFacultyId = cf.Id;
                        // Use LearningCourse.Name
                        data.courseName = co.LearningCourse != null ? co.LearningCourse.Name : co.Name;
                        data.programId = co.Program__c;
                        data.termId = co.AcademicSessionId;
                        data.locationId = co.Location__c;
                        dataList.add(data);
                    }
                }
            }
        }
        
        return dataList;
    }
    
    /**
     * @description Build feedback data for quarterly scenarios (Exam/PO/RM/AD to AA)
     * - Reporting Manager: Get from AA Contact.Reporting_Manager__c
     * - Exam Office: Get Users with Exam Manager profile from request.evaluatorUserIds
     * - Program Office: Get Users with Program Office profile from request.evaluatorUserIds
     * - Associate Director: Get Users with AD profile from request.evaluatorUserIds
     * Only creates feedback for AAs with Active_Status__c = 'Active'
     */
    private static List<FeedbackRecordData> buildQuarterlyFeedbackData(
        FeedbackManagementController.TriggerRequest request,
        String scenario
    ) {
        List<FeedbackRecordData> dataList = new List<FeedbackRecordData>();
        
        if (request.academicAssociateIds == null || request.academicAssociateIds.isEmpty()) {
            return dataList;
        }
        
        // Get AA profiles with Contact details (only active AAs)
        Map<Id, AA_Profile__c> aaProfiles = new Map<Id, AA_Profile__c>([
            SELECT Id, Academic_Associate__c, Academic_Associate__r.Name,
                   Academic_Associate__r.Email, Academic_Associate__r.Active_Status__c,
                   Academic_Associate__r.Reporting_Manager__c,
                   Academic_Associate__r.Reporting_Manager__r.Name,
                   Academic_Associate__r.Reporting_Manager__r.Email,
                   Primary_Program__c, Academic_Term__c
            FROM AA_Profile__c
            WHERE Id IN :request.academicAssociateIds
            AND Academic_Associate__r.Active_Status__c = 'Active'
        ]);
        
        if (scenario == 'Reporting-Manager-to-AA') {
            // For each AA, get their Reporting Manager from Contact
            for (AA_Profile__c profile : aaProfiles.values()) {
                Contact aaContact = profile.Academic_Associate__r;
                if (aaContact != null && aaContact.Reporting_Manager__c != null) {
                    FeedbackRecordData data = new FeedbackRecordData();
                    data.aaProfileId = profile.Id;
                    data.aaContactId = profile.Academic_Associate__c;
                    data.aaName = aaContact.Name;
                    data.recipientContactId = aaContact.Reporting_Manager__c;
                    data.recipientName = aaContact.Reporting_Manager__r?.Name;
                    data.recipientEmail = aaContact.Reporting_Manager__r?.Email;
                    data.recipientType = 'Reporting Manager';
                    data.programId = profile.Primary_Program__c;
                    data.termId = profile.Academic_Term__c;
                    dataList.add(data);
                }
            }
        } else {
            // For Exam Office, Program Office, Associate Director:
            // Evaluators are Users selected from the console (request.evaluatorUserIds)
            if (request.evaluatorUserIds == null || request.evaluatorUserIds.isEmpty()) {
                return dataList;
            }
            
            // Get User details
            Map<Id, User> evaluatorUsers = new Map<Id, User>([
                SELECT Id, Name, Email, ContactId
                FROM User
                WHERE Id IN :request.evaluatorUserIds
                AND IsActive = true
            ]);
            
            String recipientType = getRecipientTypeForScenario(scenario);
            
            // Create cross-product: each evaluator evaluates each AA
            for (User evaluator : evaluatorUsers.values()) {
                for (AA_Profile__c profile : aaProfiles.values()) {
                    FeedbackRecordData data = new FeedbackRecordData();
                    data.aaProfileId = profile.Id;
                    data.aaContactId = profile.Academic_Associate__c;
                    data.aaName = profile.Academic_Associate__r?.Name;
                    data.recipientUserId = evaluator.Id;
                    data.recipientContactId = evaluator.ContactId;
                    data.recipientName = evaluator.Name;
                    data.recipientEmail = evaluator.Email;
                    data.recipientType = recipientType;
                    data.programId = profile.Primary_Program__c;
                    data.termId = profile.Academic_Term__c;
                    dataList.add(data);
                }
            }
        }
        
        return dataList;
    }
    
    /**
     * @description Get recipient type label for quarterly scenarios
     */
    private static String getRecipientTypeForScenario(String scenario) {
        if (scenario == 'Exam-Office-to-AA') {
            return 'Exam Manager';
        } else if (scenario == 'Program-Office-to-AA') {
            return 'Program Manager';
        } else if (scenario == 'Associate-Director-to-AA') {
            return 'Associate Director';
        }
        return 'Other';
    }
    
    /**
     * @description Build feedback data for non-course scenarios (legacy)
     */
    private static List<FeedbackRecordData> buildDirectAAFeedbackData(
        FeedbackManagementController.TriggerRequest request
    ) {
        List<FeedbackRecordData> dataList = new List<FeedbackRecordData>();
        
        if (request.academicAssociateIds == null || request.academicAssociateIds.isEmpty()) {
            return dataList;
        }
        
        // Get AA profiles (only active AAs)
        Map<Id, AA_Profile__c> aaProfiles = new Map<Id, AA_Profile__c>([
            SELECT Id, Academic_Associate__c, Academic_Associate__r.Name,
                   Academic_Associate__r.Active_Status__c,
                   Primary_Program__c, Academic_Term__c
            FROM AA_Profile__c
            WHERE Id IN :request.academicAssociateIds
            AND Academic_Associate__r.Active_Status__c = 'Active'
        ]);
        
        for (Id aaId : request.academicAssociateIds) {
            AA_Profile__c profile = aaProfiles.get(aaId);
            if (profile != null) {
                FeedbackRecordData data = new FeedbackRecordData();
                data.aaProfileId = profile.Id;
                data.aaContactId = profile.Academic_Associate__c;
                data.aaName = profile.Academic_Associate__r?.Name;
                data.programId = profile.Primary_Program__c;
                data.termId = profile.Academic_Term__c;
                dataList.add(data);
            }
        }
        
        return dataList;
    }
    
    /**
     * @description Create Feedback__c records with Pending status
     * - Course-wise scenarios: Uses Batch_Token__c for grouped links
     * - Quarterly scenarios: Generates unique Feedback_Link_Token__c per record
     * - Sets Submitter_User__c for User-based, Submitter_Contact__c for Contact-based
     */
    private static List<Feedback__c> createFeedbackRecords(
        List<FeedbackRecordData> dataList,
        FeedbackManagementController.TriggerRequest request,
        Feedback_Template__c template
    ) {
        List<Feedback__c> feedbackRecords = new List<Feedback__c>();
        Date dueDate = request.dueDate != null ? request.dueDate : Date.today().addDays(30);
        Date triggeredDate = Date.today();
        String scenario = request.scenario;
        Boolean isCourseWise = COURSE_WISE_SCENARIOS.contains(scenario);
        
        // Get record type
        Id recordTypeId = getRecordTypeId(request.scenario);
        
        for (FeedbackRecordData data : dataList) {
            Feedback__c fb = new Feedback__c();
            
            // Generate unique token for each record
            fb.Feedback_Link_Token__c = generateUniqueToken();
            
            // Set batch token for course-wise scenarios (same token per recipient)
            if (isCourseWise && data.batchToken != null) {
                fb.Batch_Token__c = data.batchToken;
            }
            
            // Set feedback scenario
            fb.Feedback_Scenario__c = scenario;
            
            // Set status as Pending
            fb.Status__c = 'Pending';
            
            // Set dates
            fb.Triggered_Date__c = triggeredDate;
            fb.Due_Date__c = dueDate;
            
            // Set template
            fb.Feedback_Template__c = template.Id;
            
            // Set record type if available
            if (recordTypeId != null) {
                fb.RecordTypeId = recordTypeId;
            }
            
            // Set AA
            fb.Academic_Associate__c = data.aaProfileId;
            
            // Set submitter info based on User vs Contact
            if (data.recipientUserId != null) {
                fb.Submitter_User__c = data.recipientUserId;
            }
            fb.Submitter_Contact__c = data.recipientContactId;
            fb.Submitter_Type__c = data.recipientType;
            
            // Set course and context
            fb.Course_Offering__c = data.courseOfferingId;
            fb.Program__c = data.programId;
            fb.Academic_Session__c = data.termId;
            fb.Location__c = data.locationId;
            
            // Set course-wise lookup fields
            if (data.courseAAAssignmentId != null) {
                fb.Course_AA_Assignment__c = data.courseAAAssignmentId;
            }
            if (data.courseFacultyId != null) {
                fb.Course_Faculty__c = data.courseFacultyId;
            }
            if (data.courseOfferingParticipantId != null) {
                fb.Course_Offering_Participant__c = data.courseOfferingParticipantId;
            }
            
            // Set name (will be auto-generated if auto-number, but provide fallback)
            fb.Name = 'Feedback - ' + (data.aaName != null ? data.aaName : 'AA') + 
                     ' - ' + triggeredDate.format();
            
            feedbackRecords.add(fb);
        }
        
        if (!feedbackRecords.isEmpty()) {
            insert feedbackRecords;
        }
        
        return feedbackRecords;
    }
    
    /**
     * @description Get record type ID based on scenario
     */
    private static Id getRecordTypeId(String scenario) {
        String developerName = 'Academic_Associate'; // Default
        
        if (scenario == 'Senior-Manager-to-AD') {
            developerName = 'ASA_Manager';
        }
        
        Map<String, Schema.RecordTypeInfo> rtMap = 
            Schema.SObjectType.Feedback__c.getRecordTypeInfosByDeveloperName();
        
        if (rtMap.containsKey(developerName)) {
            return rtMap.get(developerName).getRecordTypeId();
        }
        
        return null;
    }
    
    /**
     * @description Generate unique token for feedback link
     */
    private static String generateUniqueToken() {
        Blob b = Crypto.generateAesKey(128);
        String h = EncodingUtil.convertToHex(b);
        return h.substring(0, 8) + '-' + h.substring(8, 12) + '-' + 
               h.substring(12, 16) + '-' + h.substring(16, 20) + '-' + 
               h.substring(20, 32);
    }
    
    /**
     * @description Send feedback emails
     * - Course-wise: Single email per recipient with batch token link (picklist form)
     * - Quarterly: Unique link per AA (existing behavior)
     * @param feedbackRecords List of created Feedback__c records
     * @param templateName Name of the feedback template
     * @return Number of emails sent
     */
    public static Integer sendFeedbackEmails(List<Feedback__c> feedbackRecords, String templateName) {
        if (feedbackRecords.isEmpty()) {
            return 0;
        }
        
        // Re-query to get all needed fields including new fields
        Set<Id> feedbackIds = new Set<Id>();
        for (Feedback__c fb : feedbackRecords) {
            feedbackIds.add(fb.Id);
        }
        
        List<Feedback__c> fullRecords = [
            SELECT Id, Feedback_Link_Token__c, Batch_Token__c, Feedback_Scenario__c,
                   Submitter_Contact__c, Submitter_User__c, Submitter_Type__c,
                   Submitter_Contact__r.Name, Submitter_Contact__r.Email,
                   Submitter_User__r.Name, Submitter_User__r.Email,
                   Academic_Associate__r.Academic_Associate__r.Name,
                   Course_Offering__r.LearningCourse.Name, Course_Offering__r.Name,
                   Due_Date__c
            FROM Feedback__c
            WHERE Id IN :feedbackIds
        ];
        
        if (fullRecords.isEmpty()) {
            return 0;
        }
        
        // Determine mode based on scenario
        String scenario = fullRecords[0].Feedback_Scenario__c;
        Boolean isCourseWise = COURSE_WISE_SCENARIOS.contains(scenario);
        
        // Build and send emails
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        String baseUrl = getExperienceCloudBaseUrl();
        
        if (isCourseWise) {
            // Course-wise: Group by batch token, send one email per recipient
            emails = buildCourseWiseEmails(fullRecords, baseUrl, templateName);
        } else {
            // Quarterly: One email per evaluator-AA pair with unique links
            emails = buildQuarterlyEmails(fullRecords, baseUrl, templateName);
        }
        
        // Send emails in batches
        Integer sentCount = 0;
        if (!emails.isEmpty()) {
            List<List<Messaging.SingleEmailMessage>> batches = splitIntoBatches(emails, EMAIL_BATCH_SIZE);
            for (List<Messaging.SingleEmailMessage> batch : batches) {
                try {
                    Messaging.sendEmail(batch);
                    sentCount += batch.size();
                } catch (Exception e) {
                    System.debug('Email send error: ' + e.getMessage());
                }
            }
        }
        
        return sentCount;
    }
    
    /**
     * @description Build emails for course-wise scenarios (batch token mode)
     * Single email per recipient with picklist form link
     */
    private static List<Messaging.SingleEmailMessage> buildCourseWiseEmails(
        List<Feedback__c> feedbackRecords,
        String baseUrl,
        String templateName
    ) {
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        
        // Group by batch token (same recipient)
        Map<String, List<Feedback__c>> batchToFeedback = new Map<String, List<Feedback__c>>();
        for (Feedback__c fb : feedbackRecords) {
            String batchToken = fb.Batch_Token__c;
            if (String.isNotBlank(batchToken)) {
                if (!batchToFeedback.containsKey(batchToken)) {
                    batchToFeedback.put(batchToken, new List<Feedback__c>());
                }
                batchToFeedback.get(batchToken).add(fb);
            }
        }
        
        for (String batchToken : batchToFeedback.keySet()) {
            List<Feedback__c> batch = batchToFeedback.get(batchToken);
            if (batch.isEmpty()) continue;
            
            Feedback__c firstFb = batch[0];
            
            // Get recipient info (Contact or User)
            String recipientEmail;
            String recipientName;
            if (firstFb.Submitter_User__c != null) {
                recipientEmail = firstFb.Submitter_User__r?.Email;
                recipientName = firstFb.Submitter_User__r?.Name;
            } else {
                recipientEmail = firstFb.Submitter_Contact__r?.Email;
                recipientName = firstFb.Submitter_Contact__r?.Name;
            }
            
            if (String.isBlank(recipientEmail)) continue;
            
            // Build email body with single batch token link
            String emailBody = buildBatchTokenEmailBody(
                recipientName,
                batch,
                batchToken,
                baseUrl,
                templateName
            );
            
            // Get course name for subject
            String courseName = '';
            if (firstFb.Course_Offering__r != null) {
                courseName = firstFb.Course_Offering__r.LearningCourse != null 
                    ? firstFb.Course_Offering__r.LearningCourse.Name 
                    : firstFb.Course_Offering__r.Name;
            }
            
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(new List<String>{ recipientEmail });
            email.setSubject('Feedback Request' + (String.isNotBlank(courseName) ? ': ' + courseName : ''));
            email.setHtmlBody(emailBody);
            email.setSaveAsActivity(false);
            
            emails.add(email);
        }
        
        return emails;
    }
    
    /**
     * @description Build emails for quarterly scenarios (unique link per AA)
     */
    private static List<Messaging.SingleEmailMessage> buildQuarterlyEmails(
        List<Feedback__c> feedbackRecords,
        String baseUrl,
        String templateName
    ) {
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        
        // Group by recipient (Contact or User)
        Map<String, List<Feedback__c>> recipientToFeedback = new Map<String, List<Feedback__c>>();
        for (Feedback__c fb : feedbackRecords) {
            String recipientKey = getRecipientKeyFromFeedback(fb);
            if (String.isNotBlank(recipientKey)) {
                if (!recipientToFeedback.containsKey(recipientKey)) {
                    recipientToFeedback.put(recipientKey, new List<Feedback__c>());
                }
                recipientToFeedback.get(recipientKey).add(fb);
            }
        }
        
        for (String recipientKey : recipientToFeedback.keySet()) {
            List<Feedback__c> recipientFeedback = recipientToFeedback.get(recipientKey);
            if (recipientFeedback.isEmpty()) continue;
            
            Feedback__c firstFb = recipientFeedback[0];
            
            // Get recipient info
            String recipientEmail;
            String recipientName;
            if (firstFb.Submitter_User__c != null) {
                recipientEmail = firstFb.Submitter_User__r?.Email;
                recipientName = firstFb.Submitter_User__r?.Name;
            } else {
                recipientEmail = firstFb.Submitter_Contact__r?.Email;
                recipientName = firstFb.Submitter_Contact__r?.Name;
            }
            
            if (String.isBlank(recipientEmail)) continue;
            
            // Build email body with unique links per AA
            String emailBody = buildFeedbackEmailBody(
                recipientName, 
                recipientFeedback, 
                baseUrl, 
                templateName
            );
            
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(new List<String>{ recipientEmail });
            email.setSubject('Academic Associate Feedback Request');
            email.setHtmlBody(emailBody);
            email.setSaveAsActivity(false);
            
            emails.add(email);
        }
        
        return emails;
    }
    
    /**
     * @description Get recipient key from Feedback record
     */
    private static String getRecipientKeyFromFeedback(Feedback__c fb) {
        if (fb.Submitter_User__c != null) {
            return 'User:' + fb.Submitter_User__c;
        } else if (fb.Submitter_Contact__c != null) {
            return 'Contact:' + fb.Submitter_Contact__c;
        }
        return null;
    }
    
    /**
     * @description Build email body for batch token mode (single link, picklist form)
     */
    private static String buildBatchTokenEmailBody(
        String recipientName,
        List<Feedback__c> feedbackRecords,
        String batchToken,
        String baseUrl,
        String templateName
    ) {
        String body = '<p>Dear ' + (recipientName != null ? recipientName : 'Respondent') + ',</p>';
        body += '<p>Greetings from the Office of Academic Services!</p>';
        body += '<p>We kindly request you to complete the feedback forms for the following Academic Associates:</p>';
        body += '<br/>';
        
        // List AAs for this batch
        body += '<ul>';
        for (Feedback__c fb : feedbackRecords) {
            String aaName = fb.Academic_Associate__r?.Academic_Associate__r?.Name;
            if (String.isBlank(aaName)) {
                aaName = 'Academic Associate';
            }
            
            String courseName = '';
            if (fb.Course_Offering__r != null) {
                courseName = fb.Course_Offering__r.LearningCourse != null 
                    ? fb.Course_Offering__r.LearningCourse.Name 
                    : fb.Course_Offering__r.Name;
            }
            
            body += '<li><strong>' + aaName + '</strong>';
            if (String.isNotBlank(courseName)) {
                body += ' (' + courseName + ')';
            }
            body += '</li>';
        }
        body += '</ul>';
        body += '<br/>';
        
        // Single link with batch token (form will show picklist)
        String feedbackUrl = baseUrl + '/feedback-form?batch=' + batchToken;
        body += '<p><strong><a href="' + feedbackUrl + '">Click Here to Submit Feedback</a></strong></p>';
        body += '<br/>';
        
        // Add due date if available
        if (feedbackRecords[0].Due_Date__c != null) {
            body += '<p>Please submit your feedback by <strong>' + 
                    feedbackRecords[0].Due_Date__c.format() + '</strong>.</p>';
        }
        
        body += '<br/>';
        body += '<p>Thank you for your time and valuable feedback.</p>';
        body += '<br/>';
        body += '<p>Best regards,<br/>Office of Academic Services<br/>Indian School of Business</p>';
        
        return body;
    }
    
    /**
     * @description Build email body with unique links per AA
     */
    private static String buildFeedbackEmailBody(
        String recipientName,
        List<Feedback__c> feedbackRecords,
        String baseUrl,
        String templateName
    ) {
        String body = '<p>Dear ' + (recipientName != null ? recipientName : 'Respondent') + ',</p>';
        body += '<p>Greetings from the Office of Academic Services!</p>';
        body += '<p>We kindly request you to complete the feedback forms linked below.</p>';
        body += '<br/>';
        body += '<p><strong>Feedback on Academic Associates:</strong></p>';
        body += '<ul>';
        
        for (Feedback__c fb : feedbackRecords) {
            String aaName = fb.Academic_Associate__r?.Academic_Associate__r?.Name;
            if (String.isBlank(aaName)) {
                aaName = 'Academic Associate';
            }
            
            String feedbackUrl = baseUrl + '/feedback-form?token=' + fb.Feedback_Link_Token__c;
            body += '<li>Feedback for <strong>' + aaName + '</strong>: ';
            body += '<a href="' + feedbackUrl + '">Click Here</a></li>';
        }
        
        body += '</ul>';
        body += '<br/>';
        
        // Add due date if available
        if (feedbackRecords[0].Due_Date__c != null) {
            body += '<p>Please submit your feedback by <strong>' + 
                    feedbackRecords[0].Due_Date__c.format() + '</strong>.</p>';
        }
        
        body += '<br/>';
        body += '<p>Thank you for your time and valuable feedback.</p>';
        body += '<br/>';
        body += '<p>Best regards,<br/>Office of Academic Services<br/>Indian School of Business</p>';
        
        return body;
    }
    
    /**
     * @description Get Experience Cloud site base URL
     */
    private static String getExperienceCloudBaseUrl() {
        // Try to get from Site
        try {
            List<Site> sites = [SELECT Id FROM Site WHERE Status = 'Active' LIMIT 1];
            if (!sites.isEmpty()) {
                SiteDetail sd = [SELECT SecureUrl FROM SiteDetail WHERE DurableId = :sites[0].Id];
                if (sd != null && String.isNotBlank(sd.SecureUrl)) {
                    return sd.SecureUrl;
                }
            }
        } catch (Exception e) {
            System.debug('Could not get Site URL: ' + e.getMessage());
        }
        
        // Fallback to org URL
        return URL.getOrgDomainUrl().toExternalForm();
    }
    
    /**
     * @description Split list into batches
     */
    private static List<List<Messaging.SingleEmailMessage>> splitIntoBatches(
        List<Messaging.SingleEmailMessage> emails, 
        Integer batchSize
    ) {
        List<List<Messaging.SingleEmailMessage>> batches = new List<List<Messaging.SingleEmailMessage>>();
        List<Messaging.SingleEmailMessage> currentBatch = new List<Messaging.SingleEmailMessage>();
        
        for (Messaging.SingleEmailMessage email : emails) {
            currentBatch.add(email);
            if (currentBatch.size() >= batchSize) {
                batches.add(currentBatch);
                currentBatch = new List<Messaging.SingleEmailMessage>();
            }
        }
        
        if (!currentBatch.isEmpty()) {
            batches.add(currentBatch);
        }
        
        return batches;
    }
    
    /**
     * @description Queueable class for async email sending (large batches)
     */
    public class FeedbackEmailQueueable implements Queueable {
        private List<Feedback__c> feedbackRecords;
        private String templateName;
        private Integer startIndex;
        
        public FeedbackEmailQueueable(List<Feedback__c> records, String templateName) {
            this(records, templateName, 0);
        }
        
        public FeedbackEmailQueueable(List<Feedback__c> records, String templateName, Integer startIndex) {
            this.feedbackRecords = records;
            this.templateName = templateName;
            this.startIndex = startIndex;
        }
        
        public void execute(QueueableContext context) {
            // Process batch
            Integer endIndex = Math.min(startIndex + QUEUEABLE_BATCH_SIZE, feedbackRecords.size());
            List<Feedback__c> batch = new List<Feedback__c>();
            
            for (Integer i = startIndex; i < endIndex; i++) {
                batch.add(feedbackRecords[i]);
            }
            
            if (!batch.isEmpty()) {
                FeedbackTriggerService.sendFeedbackEmails(batch, templateName);
            }
            
            // Chain next batch if more records
            if (endIndex < feedbackRecords.size()) {
                System.enqueueJob(new FeedbackEmailQueueable(feedbackRecords, templateName, endIndex));
            }
        }
    }
}