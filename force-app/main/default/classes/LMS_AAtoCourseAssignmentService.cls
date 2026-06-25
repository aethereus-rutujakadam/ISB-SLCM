public class LMS_AAtoCourseAssignmentService {
 @AuraEnabled
    public static String sendAssignmentToLMS(
        String academicAssociateId,
        String courseOfferingId,
        Date startDate,
        Date endDate,
        String remarks
    ) {
        try {
            Course_AA_Assignment__c assignment = new Course_AA_Assignment__c(
                Academic_Associate__c = academicAssociateId,
                Course_Offering__c = courseOfferingId,
                Start_Date__c = startDate,
                End_Date__c = endDate,
                Name = 'AA Assignment - ' + startDate.year(),
                Remarks__c = remarks,
                Is_Active__c = true
            );

            Map<String, Object> payload = new Map<String, Object>{
                'Academic_Associate__c' => academicAssociateId,
                'Course_Offering__c' => courseOfferingId,
                'Start_Date__c' => startDate.format(),
                'End_Date__c' => endDate.format(),
                'Is_Active__c' => true,
                'Name' => assignment.Name,
                'Remarks__c' => remarks
            };

            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:LMS_Integration'); // Named Credential
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setBody(JSON.serialize(payload));

            Http http = new Http();
            HttpResponse res = http.send(req);

            if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {
                return 'SUCCESS: ' + res.getBody();
            } else {
                return 'ERROR: ' + res.getStatusCode() + ' - ' + res.getBody();
            }

        } catch (Exception ex) {
            return 'EXCEPTION: ' + ex.getMessage();
        }
    }
}