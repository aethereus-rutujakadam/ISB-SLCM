public with sharing class studentToCourseLMS {

    // Wrapper class matching your JSON structure
    public class RegistrationRequest {
        public String CourseOfferingId;
        public String DroppedDateTime;
        public String EndDate;
        public String IsRepeatAttempt;
        public String Name;
        public String ParticipantAffiliation;
        public String ParticipationStatus;
        public String RegistrationDateTime;
        public String StartDate;
        //public String Status__c;
        public String Summary;
        public String StudentPGID;
    }

    /**
     * Method to call LMS POST endpoint
     * @param reqBody - Request wrapper containing data to send
     */
    @AuraEnabled
    public static String sendRegistrationToLMS(RegistrationRequest reqBody) {
        try {
            HttpRequest req = new HttpRequest();
            Http http = new Http();

            // Named Credential URL
            // Example: "callout:LMS_Endpoint/registration"
            req.setEndpoint('callout:LMS_Endpoint'); 
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');

            // Convert wrapper to JSON
            String payload = JSON.serialize(reqBody);
            req.setBody(payload);

            System.debug('### LMS Request Payload: ' + payload);

            HttpResponse res = http.send(req);
            System.debug('### LMS Response Status: ' + res.getStatus());
            System.debug('### LMS Response Body: ' + res.getBody());

            return res.getBody();

        } catch (Exception ex) {
            System.debug('### LMS Error: ' + ex.getMessage());
            throw new AuraHandledException('Failed to send data to LMS: ' + ex.getMessage());
        }
    }
}