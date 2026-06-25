@IsTest
public class LicenseCheckerTest {

    @IsTest
    static void testCheckLicense() {
        // Query an existing license name to use in the test
        List<UserLicense> licenses = [SELECT Name, TotalLicenses, UsedLicenses FROM UserLicense LIMIT 1];
        
        if (licenses.isEmpty()) {
            return; // Rare case, but avoids failure if no licenses in org
        }
        
        String licName = licenses[0].Name;
        Integer expectedRemaining = licenses[0].TotalLicenses - licenses[0].UsedLicenses;

        LicenseChecker.Request req = new LicenseChecker.Request();
        req.licenseName = licName;

        Test.startTest();
        List<LicenseChecker.Response> responses = LicenseChecker.checkLicense(new List<LicenseChecker.Request>{req});
        Test.stopTest();

        System.assertEquals(1, responses.size(), 'Should return one response');
        System.assertEquals(expectedRemaining, responses[0].remainingLicenses, 'Remaining licenses should match');
    }

    @IsTest
    static void testCheckLicense_Multiple() {
        // Query up to 2 license names
        List<UserLicense> licenses = [SELECT Name, TotalLicenses, UsedLicenses FROM UserLicense LIMIT 2];
        
        if (licenses.isEmpty()) {
            return;
        }
        
        List<LicenseChecker.Request> requests = new List<LicenseChecker.Request>();
        for (UserLicense lic : licenses) {
            LicenseChecker.Request req = new LicenseChecker.Request();
            req.licenseName = lic.Name;
            requests.add(req);
        }

        Test.startTest();
        List<LicenseChecker.Response> responses = LicenseChecker.checkLicense(requests);
        Test.stopTest();

        System.assertEquals(requests.size(), responses.size(), 'Should return response for each request');
        for (Integer i = 0; i < licenses.size(); i++) {
            Integer expected = licenses[i].TotalLicenses - licenses[i].UsedLicenses;
            System.assertEquals(expected, responses[i].remainingLicenses);
        }
    }
}