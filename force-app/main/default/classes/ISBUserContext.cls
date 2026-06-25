public with sharing class ISBUserContext {

    // Cache per-transaction so we don’t query repeatedly
    private static Boolean cachedIsExternal;

    public static Boolean isExternalUser() {
        if (cachedIsExternal != null) return cachedIsExternal;

        User u = [
            SELECT Id, UserType,
                   Profile.UserLicense.Name
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];

        // Primary check (most reliable)
        // Internal users are typically 'Standard'. Experience/portal users are often 'CustomerPortal', 'PowerCustomerSuccess', 'CSPLitePortal', etc.
        if (u.UserType != 'Standard') {
            cachedIsExternal = true;
            return cachedIsExternal;
        }

        // Backup check via license name (helps some orgs)
        String lic = (u.Profile != null && u.Profile.UserLicense != null)
            ? u.Profile.UserLicense.Name
            : '';

        cachedIsExternal =
            lic.contains('Customer Community') ||
            lic.contains('Customer Community Plus') ||
            lic.contains('Partner Community') ||
            lic.contains('External Identity') ||
            lic.contains('Community') ||
            lic.contains('Portal');

        return cachedIsExternal;
    }
}