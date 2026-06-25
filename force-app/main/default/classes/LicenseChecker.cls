public without sharing class LicenseChecker {

    public class Request {
        @InvocableVariable
        public String licenseName;
    }

    public class Response {
        @InvocableVariable
        public Integer remainingLicenses;
    }

    @InvocableMethod(label='Check Remaining Licenses')
    public static List<Response> checkLicense(List<Request> requests) {

        List<Response> results = new List<Response>();

        for(Request req : requests){

            UserLicense lic = [
                SELECT TotalLicenses, UsedLicenses
                FROM UserLicense
                WHERE Name = :req.licenseName
                LIMIT 1
            ];

            Response res = new Response();
            res.remainingLicenses = lic.TotalLicenses - lic.UsedLicenses;

            results.add(res);
        }

        return results;
    }
}