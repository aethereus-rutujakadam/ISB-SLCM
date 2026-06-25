public class InternationalExchangeUserCreation {

    @InvocableMethod(label='Create Exchange Portal User'
                     description='Creates a Customer Community Plus User for Incoming Exchange students.'
                     category='User Management')
    public static void createExchangeUsers(List<FlowInput> inputs) {

        List<String> inputData = new List<String>();
        for (FlowInput input : inputs) {
            if (input.contactId != null && input.pgid != null) {
                inputData.add(input.contactId + '|' + input.pgid);
            }
        }

        if (!inputData.isEmpty()) {
            // F-09 FIX: Flow path does not send welcome email (flow handles notification separately)
            createExchangeUsersAsync(inputData, false);
        }
    }

    // F-09 FIX: Consolidated single @future method (was duplicated in PGIDGeneratorService).
    // sendWelcomeEmail=true when called from PGID generation; false when called from Flow.
    @future
    public static void createExchangeUsersAsync(List<String> inputData, Boolean sendWelcomeEmail) {
         Set<String> permissionSetNames = new Set<String>();
            for (String psName : Label.Student_Permission_Set.split(',')) {
                permissionSetNames.add(psName.trim());
            }
       	Map<String, PermissionSet> psMap = new Map<String, PermissionSet>();
            for (PermissionSet ps : [
                SELECT Id, Name
                FROM PermissionSet
                WHERE Name IN :permissionSetNames
                ]) {
                    psMap.put(ps.Name, ps);
                } 
		
        UserRole studentRole;
        try {
            studentRole = [
               SELECT Id, Name, DeveloperName, PortalType 
                FROM UserRole 
                WHERE PortalType = 'CustomerPortal'
                AND DeveloperName LIKE '%rkadaCustomerPersonAccount%'
                LIMIT 1
            ];
        } catch (Exception e) {
            System.debug('Student role not found: ' + e.getMessage());
            return;
        }
        Map<Id, String> contactIdToPgid = new Map<Id, String>();
        for (String data : inputData) {
            List<String> parts = data.split('\\|');
            if (parts.size() == 2) {
                contactIdToPgid.put((Id) parts[0], parts[1]);
            }
        }

        if (contactIdToPgid.isEmpty()) return;

        List<Contact> contacts = [
            SELECT Id, FirstName, LastName, Email, AccountId
            FROM Contact
            WHERE Id IN :contactIdToPgid.keySet()
        ];

        Profile communityProfile;
        try {
            communityProfile = [
                SELECT Id FROM Profile
                WHERE Name = 'Customer Community Plus User'
                LIMIT 1
            ];
        } catch (Exception e) {
            System.debug('Community Profile not found: ' + e.getMessage());
            return;
        }

        Map<Id, User> existingUsersByContactId = new Map<Id, User>();
        for (User existingUser : [
            SELECT Id, ContactId, Email, Username
            FROM User
            WHERE ContactId IN :contactIdToPgid.keySet()
        ]) {
            existingUsersByContactId.put(existingUser.ContactId, existingUser);
        }

        List<User> usersToInsert = new List<User>();
        List<User> usersToUpdate = new List<User>();

        for (Contact c : contacts) {
            try {
                if (String.isBlank(c.Email)) {
                    System.debug('Skipping Contact ' + c.Id + ' because Email is missing.');
                    continue;
                }

                String pgid           = contactIdToPgid.get(c.Id);
                //String desiredUsername = pgid + '@isb.edu';
                String desiredAlias   = pgid.length() > 8 ? pgid.substring(0, 8) : pgid;

                if (existingUsersByContactId.containsKey(c.Id)) {
                    User existingU = existingUsersByContactId.get(c.Id);
                    if (existingU.Email != c.Email ) {
                        existingU.Email    = c.Email;
                        //existingU.Username = desiredUsername;
                        usersToUpdate.add(existingU);
                    }
                } else {
                    User u = new User();
                    u.ProfileId         = communityProfile.Id;
                    u.ContactId         = c.Id;
                    u.FirstName         = c.FirstName;
                    u.LastName          = String.isBlank(c.LastName) ? 'Student' : c.LastName;
                    u.Email             = c.Email;
                    u.Username          = c.FirstName+'.'+c.LastName+'@isb.edu';
                    u.Alias             = desiredAlias.toLowerCase();
                    //u.CommunityNickname = desiredAlias;
                    u.TimeZoneSidKey    = 'Asia/Kolkata';
                    u.LocaleSidKey      = 'en_US';
                    u.EmailEncodingKey  = 'UTF-8';
                    u.LanguageLocaleKey = 'en_US';
                    u.IsActive          = true;
                    //u.UserRoleId 		= studentRole.Id;
                    usersToInsert.add(u);
                }
            } catch (Exception e) {
                System.debug('Error preparing user for Contact ' + c.Id + ': ' + e.getMessage());
            }
        }

        if (!usersToUpdate.isEmpty()) {
            try {
                update usersToUpdate;
            } catch (Exception e) {
                System.debug('Error updating Exchange Users: ' + e.getMessage());
            }
        }

        if (!usersToInsert.isEmpty()) {
            try {
                insert usersToInsert;
                
                // Assign Permission Sets
                List<PermissionSetAssignment> psaList = new List<PermissionSetAssignment>();
                
                for (User u : usersToInsert) {
                    for (PermissionSet ps : psMap.values()) {
                        psaList.add(new PermissionSetAssignment(
                            AssigneeId = u.Id,
                            PermissionSetId = ps.Id
                        ));
                    }
                }
                
                if (!psaList.isEmpty()) {
                    try {
                        insert psaList;
                        System.debug('Assigned ' + psaList.size() + ' Permission Sets');
                    } catch (Exception e) {
                        System.debug('Error assigning permission sets: ' + e.getMessage());
                    }
                }

                // F-09 FIX: Send welcome email only when requested (PGID path), not from Flow path
                if (sendWelcomeEmail) {
                    List<Messaging.SingleEmailMessage> emailsToSend = new List<Messaging.SingleEmailMessage>();
                    for (User u : usersToInsert) {
                        String pgid = contactIdToPgid.get(u.ContactId);
                        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                        mail.setToAddresses(new String[]{ u.Email });
                        mail.setSubject('Welcome to ISB — Your Exchange Student Account is Ready');
                        String firstName = String.isNotBlank(u.FirstName) ? u.FirstName : 'Student';
                        mail.setPlainTextBody(
                            'Dear ' + firstName + ', welcome to ISB as an Incoming Exchange Student. ' +
                            'Your Student ID is ' + pgid + '. ' +
                            'Please log in to the ISB portal to complete your registration.'
                        );
                        emailsToSend.add(mail);
                    }
                    if (!emailsToSend.isEmpty()) {
                        Messaging.sendEmail(emailsToSend, false);
                    }
                }

            } catch (Exception e) {
                System.debug('Error creating Exchange Users: ' + e.getMessage());
            }
        }
    }

    public class FlowInput {
        @InvocableVariable(required=true label='Contact ID' description='Contact ID to create user for')
        public Id contactId;

        @InvocableVariable(required=true label='PGID' description='PGID to build Username and Alias')
        public String pgid;
    }
}