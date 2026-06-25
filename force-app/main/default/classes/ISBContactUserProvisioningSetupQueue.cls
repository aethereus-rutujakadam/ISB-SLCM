public without sharing class ISBContactUserProvisioningSetupQueue implements Queueable {

    private Set<Id> contactIds;
    private Id activatedByUserId;

    public ISBContactUserProvisioningSetupQueue(Set<Id> contactIds, Id activatedByUserId) {
        this.contactIds = contactIds;
        this.activatedByUserId = activatedByUserId;
    }

    public void execute(QueueableContext qc) {
        System.debug('--- ISBContactUserProvisioningSetupQueue Started ---');
        System.debug('Processing Contact IDs: ' + contactIds);
        
        List<Contact> contacts = [
            SELECT Id, FirstName, LastName, ISB_Email_ID__c, Linked_User_Id__c, Active_Status__c
            FROM Contact
            WHERE Id IN :contactIds
        ];
        System.debug('Retrieved ' + contacts.size() + ' Contact records.');

        Map<Id, AA_Profile__c> aaProfileByContactId = new Map<Id, AA_Profile__c>();
        System.debug('Fetching related AA Profile records...');
        for (AA_Profile__c aa : [
            SELECT Id, Academic_Associate__c, Employee_ID__c
            FROM AA_Profile__c
            WHERE Academic_Associate__c IN :contactIds
        ]) {
            aaProfileByContactId.put(aa.Academic_Associate__c, aa);
        }
        System.debug('Found ' + aaProfileByContactId.size() + ' matching AA Profiles.');

        Id profileId;
        List<Profile> profiles = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Academic Associate'
            LIMIT 1
        ];
        if (!profiles.isEmpty()) {
            profileId = profiles[0].Id;
            System.debug('Resolved Academic Associate Profile Id: ' + profileId);
        } else {
            System.debug('ERROR: Academic Associate Profile not found.');
        }

        Id roleId;
        List<UserRole> roles = [
            SELECT Id
            FROM UserRole
            WHERE Name = 'Academic Associate'
            LIMIT 1
        ];
        if (!roles.isEmpty()) {
            roleId = roles[0].Id;
            System.debug('Resolved Academic Associate Role Id: ' + roleId);
        } else {
            System.debug('ERROR: Academic Associate UserRole not found.');
        }

        Set<String> emails = new Set<String>();
        for (Contact c : contacts) {
            if (!String.isBlank(c.ISB_Email_ID__c)) {
                emails.add(c.ISB_Email_ID__c.trim().toLowerCase());
            }
        }
        System.debug('Collected ' + emails.size() + ' unique email addresses to cross-check against existing Users.');

        Map<String, User> existingUserByEmail = new Map<String, User>();
        if (!emails.isEmpty()) {
            for (User u : [
                SELECT Id, Email
                FROM User
                WHERE Email IN :emails
            ]) {
                existingUserByEmail.put(u.Email.toLowerCase(), u);
            }
        }
        System.debug('Found ' + existingUserByEmail.size() + ' existing Users matching these emails.');

        List<User> usersToInsert = new List<User>();
        Map<Id, User> pendingUserByContactId = new Map<Id, User>();
        Map<Id, Id> existingUserIdByContactId = new Map<Id, Id>();
        Set<Id> contactsToRevert = new Set<Id>();

        for (Contact c : contacts) {
            System.debug('Evaluating Contact ID: ' + c.Id);
            try {
                if (!String.isBlank(c.Linked_User_Id__c)) {
                    System.debug('Contact ' + c.Id + ' already has a Linked User Id. Skipping.');
                    continue;
                }

                String normalizedEmail = String.isBlank(c.ISB_Email_ID__c) ? null : c.ISB_Email_ID__c.trim().toLowerCase();

                if (normalizedEmail != null && existingUserByEmail.containsKey(normalizedEmail)) {
                    System.debug('Contact ' + c.Id + ' has an Email (' + normalizedEmail + ') that maps to an existing User. Tagging for Link only.');
                    existingUserIdByContactId.put(c.Id, existingUserByEmail.get(normalizedEmail).Id);
                    continue;
                }

                AA_Profile__c aa = aaProfileByContactId.get(c.Id);

                Boolean valid =
                    !String.isBlank(c.FirstName) &&
                    !String.isBlank(c.LastName) &&
                    !String.isBlank(c.ISB_Email_ID__c) &&
                    aa != null &&
                    !String.isBlank(aa.Employee_ID__c) &&
                    profileId != null &&
                    roleId != null;

                if (!valid) {
                    System.debug('Validation failed for Contact ' + c.Id + '. Missing critical user data or profile/role mappings. Tagging to revert Active Status.');
                    contactsToRevert.add(c.Id);
                    continue;
                }

                User u = new User();
                u.FirstName = c.FirstName;
                u.LastName = c.LastName;
                u.Email = c.ISB_Email_ID__c;
                u.Username = c.ISB_Email_ID__c;
                u.Alias = buildAlias(c.FirstName, c.LastName);
                u.EmailEncodingKey = 'UTF-8';
                u.LanguageLocaleKey = 'en_US';
                u.LocaleSidKey = 'en_IN';
                u.TimeZoneSidKey = 'Asia/Kolkata';
                u.IsActive = true;
                u.ProfileId = profileId;
                u.UserRoleId = roleId;

                usersToInsert.add(u);
                pendingUserByContactId.put(c.Id, u);
                System.debug('Successfully built new User object for Contact: ' + c.Id);

            } catch (Exception e) {
                System.debug('Exception while evaluating Contact ' + c.Id + ': ' + e.getMessage() + '\n' + e.getStackTraceString());
                contactsToRevert.add(c.Id);
            }
        }

        System.debug('Total Users ready for Database.insert: ' + usersToInsert.size());

        if (!usersToInsert.isEmpty()) {
            Database.SaveResult[] srList = Database.insert(usersToInsert, false);

            List<Id> createdUserIds = new List<Id>();
            Map<Id, Id> createdUserIdByContactId = new Map<Id, Id>();

            for (Id contactId : pendingUserByContactId.keySet()) {
                User pending = pendingUserByContactId.get(contactId);

                if (pending.Id != null) {
                    System.debug('Successfully inserted User ID: ' + pending.Id + ' for Contact: ' + contactId);
                    createdUserIds.add(pending.Id);
                    createdUserIdByContactId.put(contactId, pending.Id);
                } else {
                    System.debug('Failed to insert User record for Contact: ' + contactId + '. Reverting Active status.');
                    contactsToRevert.add(contactId);
                }
            }

            System.debug('Proceeding to dispatch Welcome Emails and Permissions for ' + createdUserIds.size() + ' Users.');
            for (Id userId : createdUserIds) {
                try {
                    AssignAcademicAssociatePermissionSet.assignAAPermissionSetAsync(userId);
                } catch (Exception e) {
                    System.debug('Permission set assignment failed for user ' + userId + ': ' + e.getMessage());
                }

                try {
                    AAUserCreationAction.sendWelcomeEmail(new List<Id>{ userId });
                } catch (Exception e) {
                    System.debug('Welcome email failed for user ' + userId + ': ' + e.getMessage());
                }
            }

            System.debug('Enqueuing ISBContactUserProvisioningBusinessQueue with ' + createdUserIdByContactId.size() + ' created users, ' + existingUserIdByContactId.size() + ' existing users, and ' + contactsToRevert.size() + ' contacts to revert.');
            if (!Test.isRunningTest()) {
                System.enqueueJob(
                    new ISBContactUserProvisioningBusinessQueue(
                        createdUserIdByContactId,
                        existingUserIdByContactId,
                        contactsToRevert,
                        activatedByUserId
                    )
                );
            }
        } else {
            System.debug('No new Users to insert. Enqueuing BusinessQueue with ' + existingUserIdByContactId.size() + ' existing users and ' + contactsToRevert.size() + ' contacts to revert.');
            if (!Test.isRunningTest()) {
                System.enqueueJob(
                    new ISBContactUserProvisioningBusinessQueue(
                        new Map<Id, Id>(),
                        existingUserIdByContactId,
                        contactsToRevert,
                        activatedByUserId
                    )
                );
            }
        }
        System.debug('--- ISBContactUserProvisioningSetupQueue Completed ---');
    }

    private static String buildAlias(String firstName, String lastName) {
        String f = String.isBlank(firstName) ? '' : firstName.substring(0, 1);
        String l = String.isBlank(lastName) ? '' : lastName;
        l = l.length() > 7 ? l.substring(0, 7) : l;
        String aliasValue = (f + l).toLowerCase();
        return aliasValue.length() > 8 ? aliasValue.substring(0, 8) : aliasValue;
    }
}