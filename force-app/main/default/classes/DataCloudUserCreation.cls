/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 03-18-2026
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
public class DataCloudUserCreation {
   
	 @InvocableMethod(label='Create Community User' 
                     description='Creates a community user for the provided contact'
                     category='User Management')
    public static void createCommunityUsers(List<FlowInput> inputs) {
        
        Set<Id> contactIds = new Set<Id>();
        for (FlowInput input : inputs) {
            if (input.contactId != null) {
                contactIds.add(input.contactId);
            }
        }
        
        // Call the async method
        if (!contactIds.isEmpty()) {
            createCommunityUsersAsync(contactIds);
        }
    }
    
    // Async method to handle user creation
    @future
    public static void createCommunityUsersAsync(Set<Id> contactIds) {
        
        // Get all contacts
        List<Contact> contacts = [
            SELECT Id, FirstName, LastName, New_Admit_Email__c, AccountId,
                   Account.OwnerId, Account.Owner.UserRoleId
            FROM Contact
            WHERE Id IN :contactIds
        ];
        
        // Get Student role
        UserRole studentRole;
        try {
            studentRole = [
                SELECT Id
                FROM UserRole
                WHERE DeveloperName = 'Student'
                LIMIT 1
            ];
        } catch (Exception e) {
            System.debug('Student role not found: ' + e.getMessage());
            return;
        }
        
        // Get Experience Profile
        Profile communityProfile;
        try {
            communityProfile = [
                SELECT Id
                FROM Profile
                WHERE Name = 'Customer Community Plus User'
                LIMIT 1
            ];
        } catch (Exception e) {
            System.debug('Community Profile not found: ' + e.getMessage());
            return;
        }
        
        Set<String> permissionSetNames = new Set<String>();
        for (String psName : Label.Student_Permission_Set.split(',')) {
            permissionSetNames.add(psName.trim());
        }
        
        // Get Permission Sets
        Map<String, PermissionSet> psMap = new Map<String, PermissionSet>();
        for (PermissionSet ps : [
            SELECT Id, Name
            FROM PermissionSet
            WHERE Name IN :permissionSetNames
        ]) {
            psMap.put(ps.Name, ps);
        }
        
        // Update Account Owners' Roles if needed
        /*List<User> usersToUpdateRole = new List<User>();
        Set<Id> accountOwnerIds = new Set<Id>();
        
        for (Contact c : contacts) {
            if (c.Account.Owner.UserRoleId == null) {
                accountOwnerIds.add(c.Account.OwnerId);
            }
        }
        
        if (!accountOwnerIds.isEmpty()) {
            for (User accOwner : [
                SELECT Id, UserRoleId
                FROM User
                WHERE Id IN :accountOwnerIds
            ]) {
                if (accOwner.UserRoleId == null) {
                    accOwner.UserRoleId = studentRole.Id;
                    usersToUpdateRole.add(accOwner);
                }
            }
            
            if (!usersToUpdateRole.isEmpty()) {
                try {
                    update usersToUpdateRole;
                    System.debug('Updated ' + usersToUpdateRole.size() + ' Account Owner roles');
                } catch (Exception e) {
                    System.debug('Error updating Account Owner roles: ' + e.getMessage());
                }
            }
        }*/
        
        // Check if Users already exist for these contacts 
        Map<Id, User> existingUsersByContactId = new Map<Id, User>();
        for (User existingUser : [
            SELECT Id, ContactId, Email, Username 
            FROM User 
            WHERE ContactId IN :contactIds
        ]) {
            existingUsersByContactId.put(existingUser.ContactId, existingUser);
        }

        // Create Community Users
        List<User> usersToInsert = new List<User>();
        List<User> usersToUpdate = new List<User>();
        Map<Id, Contact> contactMap = new Map<Id, Contact>();
        
        for (Contact c : contacts) {
            try {
                if (existingUsersByContactId.containsKey(c.Id)) {
                    // -- UPDATE FLOW --
                    User existingU = existingUsersByContactId.get(c.Id);
                    
                    // Only update if email is actually different
                    if (existingU.Email != c.New_Admit_Email__c) {
                        existingU.Email = c.New_Admit_Email__c;
                        existingU.Username = c.New_Admit_Email__c.toLowerCase() + '.orgb.' +
                                             String.valueOf(c.Id).substring(0, 6);
                        usersToUpdate.add(existingU);
                    }
                } else {
                    // -- CREATE FLOW --
                    User u = new User();
                    u.ProfileId = communityProfile.Id;
                    u.ContactId = c.Id;
                    u.FirstName = c.FirstName;
                    u.LastName  = String.isBlank(c.LastName) ? 'Student' : c.LastName;
                    u.Email     = c.New_Admit_Email__c;
                    u.Username = c.New_Admit_Email__c.toLowerCase(); //+ '.orgb.' +
                                // String.valueOf(c.Id).substring(0, 6);
                    u.Alias = u.LastName.length() >= 5
                        ? u.LastName.substring(0,5).toLowerCase()
                        : u.LastName.toLowerCase();
                    
                    // Generate unique nickname with timestamp
                    String timestamp = String.valueOf(System.now().getTime()).substring(7);
                    u.CommunityNickname = ('stu' + String.valueOf(c.Id).substring(0, 8) + timestamp)
                        .replaceAll('[^a-zA-Z0-9]', '');
                        
                    u.TimeZoneSidKey    = 'Asia/Kolkata';
                    u.LocaleSidKey      = 'en_IN';
                    u.EmailEncodingKey  = 'UTF-8';
                    u.LanguageLocaleKey = 'en_US';
                    //u.IsActive = true;
                    u.IsActive = false;
                    
                    String email = c.New_Admit_Email__c;
                    String localPart = email.substring(0, email.indexOf('@'));
                    String domainPart = email.substring(email.indexOf('@'));
                    
                    List<String> segments = localPart.split('_');
                    List<String> capitalizedSegments = new List<String>();
                    for (String seg : segments) {
                        if (seg.length() > 0) {
                            capitalizedSegments.add(seg.substring(0,1).toUpperCase() + seg.substring(1).toLowerCase());
                        }
                    }
                    
                    String formattedEmail = String.join(capitalizedSegments, '_') + domainPart;
                    u.FederationIdentifier = formattedEmail; 
                   // u.FederationIdentifier = c.New_Admit_Email__c.toUpperCase(); 
                    
                    usersToInsert.add(u);
                    contactMap.put(c.Id, c);
                }
            } catch (Exception e) {
                System.debug('Error preparing user for Contact ' + c.Id + ': ' + e.getMessage());
            }
        }
        
        // Execute DML for Updates
        if (!usersToUpdate.isEmpty()) {
            try {
                update usersToUpdate;
                System.debug('Successfully updated ' + usersToUpdate.size() + ' existing Community Users emails');
            } catch (Exception e) {
                System.debug('Error updating User emails: ' + e.getMessage());
            }
        }

        // Insert Users
        if (!usersToInsert.isEmpty()) {
            try {
                insert usersToInsert;
                System.debug('Successfully created ' + usersToInsert.size() + ' Community Users');
                
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
                
                // Send Password Reset Emails
                for (User u : usersToInsert) {
                    try {
                        //System.resetPassword(u.Id, true);
                    } catch (Exception e) {
                        System.debug('Error sending password reset for User ' + u.Id + ': ' + e.getMessage());
                    }
                }
                
            } catch (Exception e) {
                System.debug('Error creating Community Users: ' + e.getMessage());
            }
        }
    }
    
    // Wrapper class for Flow input
    public class FlowInput {
        @InvocableVariable(required=true label='Contact ID' description='Contact ID to create user for')
        public Id contactId;
    }  
 
    
    /*
    @future
    public static void createCommunityUsersAsync(Set<Id> contactIds) {
        
        // Get all contacts
        List<Contact> contacts = [
            SELECT Id, FirstName, LastName, Email, AccountId,
                   Account.OwnerId, Account.Owner.UserRoleId
            FROM Contact
            WHERE Id IN :contactIds
        ];
        
        // Get Student role
        UserRole studentRole;
        try {
            studentRole = [
                SELECT Id
                FROM UserRole
                WHERE DeveloperName = 'Student'
                LIMIT 1
            ];
        } catch (Exception e) {
            System.debug(' Student role not found: ' + e.getMessage());
            return;
        }
        
        // Get Experience Profile
        Profile communityProfile;
        try {
            communityProfile = [
                SELECT Id
                FROM Profile
                WHERE Name = 'Customer Community Plus User'
                LIMIT 1
            ];
        } catch (Exception e) {
            System.debug(' Community Profile not found: ' + e.getMessage());
            return;
        }
        Set<String> permissionSetNames = new Set<String>();
        for (String psName : Label.Student_Permission_Set.split(',')) {
    		permissionSetNames.add(psName.trim());
		}
        // Get Permission Sets
        Map<String, PermissionSet> psMap = new Map<String, PermissionSet>();
        for (PermissionSet ps : [
            SELECT Id, Name
            FROM PermissionSet
            WHERE Name IN :permissionSetNames
            
        ]) {
            psMap.put(ps.Name, ps);
        }
        
        // Update Account Owners' Roles if needed
        List<User> usersToUpdateRole = new List<User>();
        Set<Id> accountOwnerIds = new Set<Id>();
        
        for (Contact c : contacts) {
            if (c.Account.Owner.UserRoleId == null) {
                accountOwnerIds.add(c.Account.OwnerId);
            }
        }
        
        if (!accountOwnerIds.isEmpty()) {
            for (User accOwner : [
                SELECT Id, UserRoleId
                FROM User
                WHERE Id IN :accountOwnerIds
            ]) {
                if (accOwner.UserRoleId == null) {
                    accOwner.UserRoleId = studentRole.Id;
                    usersToUpdateRole.add(accOwner);
                }
            }
            
            if (!usersToUpdateRole.isEmpty()) {
                try {
                    update usersToUpdateRole;
                    System.debug(' Updated ' + usersToUpdateRole.size() + ' Account Owner roles');
                } catch (Exception e) {
                    System.debug(' Error updating Account Owner roles: ' + e.getMessage());
                }
            }
        }
        
        // Create Community Users
        List<User> usersToInsert = new List<User>();
        Map<Id, Contact> contactMap = new Map<Id, Contact>();
        
        for (Contact c : contacts) {
            try {
                User u = new User();
                u.ProfileId = communityProfile.Id;
                u.ContactId = c.Id;
                u.FirstName = c.FirstName;
                u.LastName  = String.isBlank(c.LastName) ? 'Student' : c.LastName;
                u.Email     = c.Email;
                u.Username = c.Email.toLowerCase() + '.orgb.' +
                             String.valueOf(c.Id).substring(0, 6);
                u.Alias = u.LastName.length() >= 5
                    ? u.LastName.substring(0,5).toLowerCase()
                    : u.LastName.toLowerCase();
                
                // Generate unique nickname with timestamp
                String timestamp = String.valueOf(System.now().getTime()).substring(7);
                u.CommunityNickname = ('stu' + String.valueOf(c.Id).substring(0, 8) + timestamp)
                    .replaceAll('[^a-zA-Z0-9]', '');
                    
                u.TimeZoneSidKey    = 'Asia/Kolkata';
                u.LocaleSidKey      = 'en_IN';
                u.EmailEncodingKey  = 'UTF-8';
                u.LanguageLocaleKey = 'en_US';
                u.IsActive = true;
                
                usersToInsert.add(u);
                contactMap.put(c.Id, c);
                
            } catch (Exception e) {
                System.debug(' Error preparing user for Contact ' + c.Id + ': ' + e.getMessage());
            }
        }
        
        // Insert Users
        if (!usersToInsert.isEmpty()) {
            try {
                insert usersToInsert;
                System.debug(' Successfully created ' + usersToInsert.size() + ' Community Users');
                
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
                        System.debug(' Assigned ' + psaList.size() + ' Permission Sets');
                    } catch (Exception e) {
                        System.debug(' Error assigning permission sets: ' + e.getMessage());
                    }
                }
                
                // Send Password Reset Emails
                for (User u : usersToInsert) {
                    try {
                        System.resetPassword(u.Id, true);
                    } catch (Exception e) {
                        System.debug(' Error sending password reset for User ' + u.Id + ': ' + e.getMessage());
                    }
                }
                
            } catch (Exception e) {
                System.debug(' Error creating Community Users: ' + e.getMessage());
            }
        }
    }
*/
}