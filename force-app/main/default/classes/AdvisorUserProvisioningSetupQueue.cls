public without sharing class AdvisorUserProvisioningSetupQueue implements Queueable {

    private Set<Id> contactIds;
    private Id activatedByUserId;

    public AdvisorUserProvisioningSetupQueue(Set<Id> contactIds, Id activatedByUserId) {
        this.contactIds = contactIds;
        this.activatedByUserId = activatedByUserId;
    }

    public void execute(QueueableContext qc) {
        System.debug('--- AdvisorUserProvisioningSetupQueue Started ---');
        System.debug('Processing Contact IDs: ' + contactIds);
        
        List<Contact> contacts = [
            SELECT Id, FirstName, LastName, ISB_Email_ID__c, Linked_User_Id__c, Active_Status__c
            FROM Contact
            WHERE Id IN :contactIds
        ];
        System.debug('Retrieved ' + contacts.size() + ' Contact records.');

        Id profileId;
        List<Profile> profiles = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Advisor'
            LIMIT 1
        ];
        if (!profiles.isEmpty()) {
            profileId = profiles[0].Id;
            System.debug('Resolved Advisor Profile Id: ' + profileId);
        } else {
            System.debug('ERROR: Advisor Profile not found.');
        }

        Id roleId;
        List<UserRole> roles = [
            SELECT Id
            FROM UserRole
            WHERE Name = 'Advisor'
            LIMIT 1
        ];
        if (!roles.isEmpty()) {
            roleId = roles[0].Id;
            System.debug('Resolved Advisor Role Id: ' + roleId);
        } else {
            System.debug('ERROR: Advisor UserRole not found.');
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
                SELECT Id, Email, IsActive
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
        Set<Id> existingUserIdsToActivate = new Set<Id>();
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
                    User matchedUser = existingUserByEmail.get(normalizedEmail);
                    existingUserIdByContactId.put(c.Id, matchedUser.Id);
                    if (!matchedUser.IsActive) {
                        existingUserIdsToActivate.add(matchedUser.Id);
                    }
                    continue;
                }

                Boolean valid =
                    !String.isBlank(c.FirstName) &&
                    !String.isBlank(c.LastName) &&
                    !String.isBlank(c.ISB_Email_ID__c) &&
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

        if (!existingUserIdsToActivate.isEmpty()) {
            List<User> existingUsersToActivate = new List<User>();
            for (Id userId : existingUserIdsToActivate) {
                existingUsersToActivate.add(new User(
                    Id = userId,
                    IsActive = true
                ));
            }

            Database.SaveResult[] activationResults = Database.update(existingUsersToActivate, false);
            for (Integer i = 0; i < activationResults.size(); i++) {
                if (activationResults[i].isSuccess()) {
                    System.debug('Reactivated existing User ID: ' + existingUsersToActivate[i].Id);
                } else {
                    for (Database.Error err : activationResults[i].getErrors()) {
                        System.debug('ERROR reactivating existing User ' + existingUsersToActivate[i].Id + ': ' + err.getMessage());
                    }
                }
            }
        }

        List<Id> createdUserIds = new List<Id>();
        Map<Id, Id> createdUserIdByContactId = new Map<Id, Id>();

        if (!usersToInsert.isEmpty()) {
            Database.SaveResult[] srList = Database.insert(usersToInsert, false);

            for (Integer i = 0; i < srList.size(); i++) {
                if (srList[i].isSuccess()) {
                    System.debug('Successfully created User ID: ' + srList[i].getId());
                } else {
                    for (Database.Error err : srList[i].getErrors()) {
                        System.debug('ERROR creating User: ' + err.getMessage());
                    }
                }
            }

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
                    AssignAdvisorPermissionSet.assignFromQueueable(userId);
                } catch (Exception e) {
                    System.debug('Permission set assignment failed for user ' + userId + ': ' + e.getMessage());
                }

                try {
                    AdvisorUserCreationAction.sendWelcomeEmail(new List<Id>{ userId });
                } catch (Exception e) {
                    System.debug('Welcome email failed for user ' + userId + ': ' + e.getMessage());
                }
            }

            System.debug('Enqueuing AdvisorUserProvisioningBusinessQueue with ' + createdUserIdByContactId.size() + ' created users, ' + existingUserIdByContactId.size() + ' existing users, and ' + contactsToRevert.size() + ' contacts to revert.');
            if (!Test.isRunningTest()) {
                System.enqueueJob(
                    new AdvisorUserProvisioningBusinessQueue(
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
                    new AdvisorUserProvisioningBusinessQueue(
                        new Map<Id, Id>(),
                        existingUserIdByContactId,
                        contactsToRevert,
                        activatedByUserId
                    )
                );
            }
        }

        System.debug('--- AdvisorUserProvisioningSetupQueue Completed ---');
    }

    private String buildAlias(String firstName, String lastName) {
        String alias = '';
        if (!String.isBlank(firstName)) {
            alias += firstName.substring(0, 1);
        }
        if (!String.isBlank(lastName)) {
            alias += lastName.length() >= 4 ? lastName.substring(0, 4) : lastName;
        }
        return alias.length() > 8 ? alias.substring(0, 8) : alias;
    }
}