/**
 * @description Invocable Apex class to generate feedback URLs dynamically
 * Supports multiple feedback types: Faculty-to-AA, Faculty-to-ASA, Student-to-AA, etc.
 * Used in Flow to create unique feedback links
 * @author ISB Team
 * @date 2025
 */
public with sharing class FeedbackURLGenerator {
    
    /**
     * @description Input wrapper for Flow
     */
    public class FeedbackURLRequest {
        @InvocableVariable(required=true label='Course Offering ID')
        public Id courseOfferingId;
        
        @InvocableVariable(required=false label='Academic Associate ID' description='Required for AA feedback')
        public Id academicAssociateId;
        
        @InvocableVariable(required=false label='Faculty ID')
        public Id facultyId;
        
        @InvocableVariable(required=true label='Template Name' description='e.g., Faculty-AA, Faculty-ASA, Student-AA')
        public String templateName;
        
        @InvocableVariable(required=false label='Include ASA Feedback URL' description='Generate Faculty-to-Academic Services feedback URL')
        public Boolean includeASAFeedback;
        
        @InvocableVariable(required=false label='ASA Template Name' description='Template name for ASA feedback (e.g., Faculty To Academic Services Feedback)')
        public String asaTemplateName;
    }
    
    /**
     * @description Output wrapper for Flow
     */
    public class FeedbackURLResponse {
        @InvocableVariable(label='Feedback URL')
        public String feedbackUrl;
        
        @InvocableVariable(label='Unique GUID')
        public String guid;
        
        @InvocableVariable(label='AA Name')
        public String aaName;
        
        @InvocableVariable(label='ASA Feedback URL')
        public String asaFeedbackUrl;
        
        @InvocableVariable(label='ASA Unique GUID')
        public String asaGuid;
    }
    
    /**
     * @description Generate feedback URLs for Flow
     * @param requests List of FeedbackURLRequest
     * @return List of FeedbackURLResponse
     */
    @InvocableMethod(label='Generate Feedback URL' description='Generates unique feedback URLs dynamically based on template type' category='Feedback')
    public static List<FeedbackURLResponse> generateFeedbackURLs(List<FeedbackURLRequest> requests) {
        List<FeedbackURLResponse> responses = new List<FeedbackURLResponse>();
        
        // Get Experience Cloud site base URL
        String baseUrl = getExperienceCloudBaseUrl();
        
        for (FeedbackURLRequest request : requests) {
            FeedbackURLResponse response = new FeedbackURLResponse();
            
            try {
                // Determine if this is AA or ASA feedback based on template
                Boolean isAAFeedback = request.templateName.contains('AA') && !request.templateName.contains('ASA');
                Boolean isASAFeedback = request.templateName.contains('ASA');
                
                // Generate primary feedback URL (AA or ASA based on template)
                if (isAAFeedback && request.academicAssociateId != null) {
                    // Generate AA feedback URL
                    String guid = generateUniqueGUID(
                        request.courseOfferingId, 
                        request.academicAssociateId,
                        request.facultyId,
                        'AA'
                    );
                    
                    String aaName = getAAName(request.academicAssociateId);
                    
                    String feedbackUrl = buildFeedbackURL(
                        baseUrl,
                        request.templateName,
                        request.courseOfferingId,
                        request.academicAssociateId,
                        request.facultyId,
                        null, // No ASA for AA feedback
                        guid
                    );
                    
                    response.feedbackUrl = feedbackUrl;
                    response.guid = guid;
                    response.aaName = aaName;
                    
                } else if (isASAFeedback) {
                    // Generate ASA feedback URL
                    String guid = generateUniqueGUID(
                        request.courseOfferingId, 
                        null,
                        request.facultyId,
                        'ASA'
                    );
                    
                    String feedbackUrl = buildFeedbackURL(
                        baseUrl,
                        request.templateName,
                        request.courseOfferingId,
                        null, // No AA for ASA feedback
                        request.facultyId,
                        true, // Include ASA context
                        guid
                    );
                    
                    response.feedbackUrl = feedbackUrl;
                    response.guid = guid;
                    response.aaName = 'Academic Services';
                }
                
                // Generate additional ASA feedback URL if requested
                if (request.includeASAFeedback != null && request.includeASAFeedback) {
                    // Use provided ASA template name or default to 'Faculty To Academic Services Feedback'
                    String asaTemplate = String.isNotBlank(request.asaTemplateName) 
                        ? request.asaTemplateName 
                        : 'Faculty To Academic Services Feedback';
                    
                    String asaGuid = generateUniqueGUID(
                        request.courseOfferingId, 
                        null,
                        request.facultyId,
                        'ASA'
                    );
                    
                    String asaFeedbackUrl = buildFeedbackURL(
                        baseUrl,
                        asaTemplate,
                        request.courseOfferingId,
                        null,
                        request.facultyId,
                        true,
                        asaGuid
                    );
                    
                    response.asaFeedbackUrl = asaFeedbackUrl;
                    response.asaGuid = asaGuid;
                }
                
            } catch (Exception e) {
                System.debug('Error generating feedback URL: ' + e.getMessage());
                response.feedbackUrl = 'Error: ' + e.getMessage();
                response.guid = '';
                response.aaName = '';
            }
            
            responses.add(response);
        }
        
        return responses;
    }
    
    /**
     * @description Generate a single feedback link (to be used by Batch Apex)
     * @param courseOfferingId Course Offering ID
     * @param facultyId Faculty ID (who is giving feedback)
     * @param academicAssociateId AA ID (who is being evaluated) - null for ASA
     * @param templateName Name of the feedback template
     * @return String The generated URL
     */
    public static String generateLink(Id courseOfferingId, Id facultyId, Id academicAssociateId, String templateName) {
        String baseUrl = getExperienceCloudBaseUrl();
        Boolean isASAFeedback = templateName.contains('ASA');
        String feedbackType = isASAFeedback ? 'ASA' : 'AA';
        
        String guid = generateUniqueGUID(
            courseOfferingId, 
            academicAssociateId,
            facultyId,
            feedbackType
        );
        
        return buildFeedbackURL(
            baseUrl,
            templateName,
            courseOfferingId,
            academicAssociateId,
            facultyId,
            isASAFeedback,
            guid
        );
    }

    /**
     * @description Get Experience Cloud base URL with hardcoded site name
     * @return String base URL for Experience Cloud site
     */
    public static String getExperienceCloudBaseUrl() {
        // Try to get from Site context first (when running in Experience Cloud)
        String baseUrl = Site.getBaseUrl();
        
        // If null (running in non-site context like Flow), construct from org domain
        if (String.isBlank(baseUrl)) {
            try {
                // Get the org's domain URL
                Url orgDomainUrl = System.URL.getOrgDomainUrl();
                
                if (orgDomainUrl != null) {
                    // Get the base domain (e.g., https://mydomain.my.salesforce.com)
                    String orgDomain = orgDomainUrl.toExternalForm();
                    
                    // Hardcoded site name
                    String siteName = 'ISBStudentSuccessPortal';
                    
                    // Extract base domain from org URL
                    // e.g., from https://ruby-business-123--isbdevslcm.sandbox.my.salesforce.com
                    // to ruby-business-123--isbdevslcm.sandbox.my.site.com
                    String siteDomain = orgDomain.replace('.salesforce.com', '.site.com');
                    
                    // Build the complete URL with hardcoded site name
                    baseUrl = siteDomain + '/' + siteName;
                    
                    System.debug('Constructed Experience Cloud URL: ' + baseUrl);
                } else {
                    System.debug('Unable to determine org domain URL');
                }
            } catch (Exception e) {
                System.debug('Error getting Experience Cloud URL: ' + e.getMessage());
            }
        }
        
        return baseUrl;
    }
    
    /**
     * @description Generate unique GUID for tracking
     * @param courseOfferingId Course Offering ID
     * @param academicAssociateId AA ID (null for ASA feedback)
     * @param facultyId Faculty ID
     * @param feedbackType Type of feedback (AA or ASA)
     * @return String unique GUID
     */
    public static String generateUniqueGUID(Id courseOfferingId, Id academicAssociateId, Id facultyId, String feedbackType) {
        // Create a unique identifier combining:
        // - Feedback Type
        // - Random number
        // - Timestamp
        // - Course ID
        // - AA ID or ASA marker
        // - Faculty ID (if provided)
        
        String guid = 'FB-' + feedbackType + '-' +
                     String.valueOf(Crypto.getRandomLong()).substring(0, 8) + '-' +
                     String.valueOf(System.currentTimeMillis()).substring(7) + '-' +
                     String.valueOf(courseOfferingId).substring(0, 8);
        
        if (academicAssociateId != null) {
            guid += '-' + String.valueOf(academicAssociateId).substring(0, 8);
        } else {
            guid += '-ASA';
        }
        
        if (facultyId != null) {
            guid += '-' + String.valueOf(facultyId).substring(0, 8);
        }
        
        return guid;
    }
    
    /**
     * @description Get AA Name
     * @param academicAssociateId AA ID
     * @return String AA Name
     */
    private static String getAAName(Id academicAssociateId) {
        try {
            Contact aa = [
                SELECT Name 
                FROM Contact 
                WHERE Id = :academicAssociateId 
                LIMIT 1
            ];
            return aa.Name;
        } catch (Exception e) {
            return 'Unknown';
        }
    }
    
    /**
     * @description Build complete feedback URL
     * @param baseUrl Experience Cloud base URL
     * @param templateName Template name
     * @param courseOfferingId Course Offering ID
     * @param academicAssociateId AA ID (null for ASA feedback)
     * @param facultyId Faculty ID
     * @param isASAFeedback Whether this is ASA feedback
     * @param guid Unique GUID
     * @return String complete feedback URL
     */
    public static String buildFeedbackURL(
        String baseUrl,
        String templateName,
        Id courseOfferingId,
        Id academicAssociateId,
        Id facultyId,
        Boolean isASAFeedback,
        String guid
    ) {
        // Build URL with parameters
        // Include /s/ for Experience Cloud standard URL structure
        String url = baseUrl + '/s/surveypage?';
        url += 'template=' + EncodingUtil.urlEncode(templateName, 'UTF-8');
        url += '&courseOfferingId=' + courseOfferingId;
        
        // Only include AA ID if not ASA feedback
        if (academicAssociateId != null && (isASAFeedback == null || !isASAFeedback)) {
            url += '&academicAssociateId=' + academicAssociateId;
        }
        
        if (facultyId != null) {
            url += '&facultyId=' + facultyId;
        }
        
        url += '&guid=' + EncodingUtil.urlEncode(guid, 'UTF-8');
        
        return url;
    }
}