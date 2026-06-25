public without sharing class ClubMembershipController {
    
    public class MembershipDTO {
        @AuraEnabled public Id membershipId;
        @AuraEnabled public Id clubId;
        @AuraEnabled public String clubName;
        @AuraEnabled public String role;
        @AuraEnabled public String status;
        @AuraEnabled public String approvalStatus;
        @AuraEnabled public String clubRecordType;
        @AuraEnabled public String academicYear;
        @AuraEnabled public Id programEnrollmentId;
    }

    public class MembershipResponse {
        @AuraEnabled public List<MembershipDTO> memberships;
        @AuraEnabled public Integer count;
        @AuraEnabled public Id effectiveContactId;
        @AuraEnabled public String debugMessage;
        
        public MembershipResponse() {
            this.memberships = new List<MembershipDTO>();
            this.count = 0;
        }
    }

    public class ClubRequestDTO {
        @AuraEnabled public Id requestId;
        @AuraEnabled public String requestName;
        @AuraEnabled public String status;
        @AuraEnabled public String category;
        @AuraEnabled public Date createdDate;
    }

    public class ClubRequestResponse {
        @AuraEnabled public List<ClubRequestDTO> requests;
        @AuraEnabled public Integer count;
        @AuraEnabled public String debugMessage;

        public ClubRequestResponse() {
            this.requests = new List<ClubRequestDTO>();
            this.count = 0;
        }
    }

    @AuraEnabled(cacheable=false)
    public static MembershipResponse getProfessionalMemberships(Id contactId) {
        MembershipResponse resp = new MembershipResponse();
        Id effectiveContactId = contactId;

        try {
            // If no contactId provided, get it from current user
            if (effectiveContactId == null) {
                List<User> users = [
                    SELECT ContactId 
                    FROM User 
                    WHERE Id = :UserInfo.getUserId() 
                    LIMIT 1
                ];
                
                if (!users.isEmpty() && users[0].ContactId != null) {
                    effectiveContactId = users[0].ContactId;
                }
            }
            
            resp.effectiveContactId = effectiveContactId;

            if (effectiveContactId == null) {
                resp.debugMessage = 'No contactId provided and current user has no ContactId.';
                return resp;
            }

            // Query club memberships with Professional record type
            List<Club_Membership__c> cms = [
                SELECT 
                    Id, 
                    Contact__c, 
                    Club__c, 
                    Club__r.Name, 
                    Club__r.RecordType.DeveloperName,
                    Role__c, 
                    Status__c,
                    Approval_Status__c,
                    Academic_Year__c,
                    Program_Enrollment__c
                FROM Club_Membership__c
                WHERE Contact__c = :effectiveContactId 
                AND (Status__c = 'Active' OR Approval_Status__c = 'Approved')
                AND Status__c != 'Inactive'
                AND Club__r.RecordType.DeveloperName = 'Professional_Club'
                ORDER BY Club__r.Name ASC
            ];

            // Transform to DTOs
            for (Club_Membership__c cm : cms) {
                MembershipDTO dto = new MembershipDTO();
                dto.membershipId = cm.Id;
                dto.clubId = cm.Club__c;
                dto.clubName = cm.Club__r != null ? cm.Club__r.Name : 'Unknown';
                dto.role = String.isNotBlank(cm.Role__c) ? cm.Role__c : 'Lead';
                dto.status = String.isNotBlank(cm.Status__c) ? cm.Status__c : 'Unknown';
                dto.approvalStatus = cm.Approval_Status__c;
                dto.clubRecordType = cm.Club__r != null && cm.Club__r.RecordType != null 
                    ? cm.Club__r.RecordType.DeveloperName 
                    : '';
                dto.academicYear = cm.Academic_Year__c;
                dto.programEnrollmentId = cm.Program_Enrollment__c;
                resp.memberships.add(dto);
            }

            resp.count = resp.memberships.size();
            resp.debugMessage = 'Successfully queried ' + resp.count + ' professional club membership(s) for Contact: ' + effectiveContactId;
            
        } catch (Exception e) {
            resp.debugMessage = 'Error: ' + e.getMessage() + ' | Stack: ' + e.getStackTraceString();
            System.debug('Error in getProfessionalMemberships: ' + resp.debugMessage);
        }
        
        return resp;
    }

    @AuraEnabled(cacheable=false)
    public static MembershipResponse getOtherMemberships(Id contactId) {
        MembershipResponse resp = new MembershipResponse();
        Id effectiveContactId = contactId;

        try {
            // If no contactId provided, get it from current user
            if (effectiveContactId == null) {
                List<User> users = [
                    SELECT ContactId 
                    FROM User 
                    WHERE Id = :UserInfo.getUserId() 
                    LIMIT 1
                ];
                
                if (!users.isEmpty() && users[0].ContactId != null) {
                    effectiveContactId = users[0].ContactId;
                }
            }
            
            resp.effectiveContactId = effectiveContactId;

            if (effectiveContactId == null) {
                resp.debugMessage = 'No contactId provided and current user has no ContactId.';
                return resp;
            }

            // Query club memberships with Social_Club record type
            List<Club_Membership__c> cms = [
                SELECT 
                    Id, 
                    Contact__c, 
                    Club__c, 
                    Club__r.Name, 
                    Club__r.RecordType.DeveloperName,
                    Role__c, 
                    Status__c,
                    Approval_Status__c,
                    Academic_Year__c,
                    Program_Enrollment__c
                FROM Club_Membership__c
                WHERE Contact__c = :effectiveContactId 
                AND (Status__c = 'Active' OR Approval_Status__c = 'Approved')
                AND Status__c != 'Inactive'
                AND Club__r.RecordType.DeveloperName = 'Social_Club'
                ORDER BY Club__r.Name ASC
            ];

            // Transform to DTOs
            for (Club_Membership__c cm : cms) {
                MembershipDTO dto = new MembershipDTO();
                dto.membershipId = cm.Id;
                dto.clubId = cm.Club__c;
                dto.clubName = cm.Club__r != null ? cm.Club__r.Name : 'Unknown';
                dto.role = String.isNotBlank(cm.Role__c) ? cm.Role__c : 'Member';
                dto.status = String.isNotBlank(cm.Status__c) ? cm.Status__c : 'Unknown';
                dto.approvalStatus = cm.Approval_Status__c;
                dto.clubRecordType = cm.Club__r != null && cm.Club__r.RecordType != null 
                    ? cm.Club__r.RecordType.DeveloperName 
                    : '';
                dto.academicYear = cm.Academic_Year__c;
                dto.programEnrollmentId = cm.Program_Enrollment__c;
                resp.memberships.add(dto);
            }

            resp.count = resp.memberships.size();
            resp.debugMessage = 'Successfully queried ' + resp.count + ' social club membership(s) for Contact: ' + effectiveContactId;
            
        } catch (Exception e) {
            resp.debugMessage = 'Error: ' + e.getMessage() + ' | Stack: ' + e.getStackTraceString();
            System.debug('Error in getOtherMemberships: ' + resp.debugMessage);
        }
        
        return resp;
    }

    @AuraEnabled(cacheable=false)
    public static ClubRequestResponse getClubRequests(Id contactId) {
        ClubRequestResponse resp = new ClubRequestResponse();
        Id effectiveContactId = contactId;
        
        try {
             if (effectiveContactId == null) {
                List<User> users = [SELECT ContactId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
                if (!users.isEmpty() && users[0].ContactId != null) {
                    effectiveContactId = users[0].ContactId;
                }
            }
            
            if (effectiveContactId == null) {
                resp.debugMessage = 'No contactId provided and current user has no ContactId.';
                return resp;
            }

            Id associatedUserId = null;
            if (effectiveContactId != null) {
                List<User> relatedUsers = [SELECT Id FROM User WHERE ContactId = :effectiveContactId LIMIT 1];
                if (!relatedUsers.isEmpty()) {
                    associatedUserId = relatedUsers[0].Id;
                }
            }

            List<Club_Request__c> requests = [
                SELECT Id, Name, Approval_Status__c, Category__c, CreatedDate
                FROM Club_Request__c
                WHERE Contact__c = :effectiveContactId
                OR Proposed_Lead__c = :effectiveContactId
                OR OwnerId = :associatedUserId
                ORDER BY CreatedDate DESC
            ];

            for(Club_Request__c req : requests) {
                ClubRequestDTO dto = new ClubRequestDTO();
                dto.requestId = req.Id;
                dto.requestName = req.Name;
                dto.status = req.Approval_Status__c;
                dto.category = req.Category__c;
                dto.createdDate = req.CreatedDate.date();
                resp.requests.add(dto);
            }
            
            resp.count = resp.requests.size();
            resp.debugMessage = 'Successfully queried ' + resp.count + ' club requests.';
            
        } catch (Exception e) {
            resp.debugMessage = 'Error: ' + e.getMessage();
            System.debug('Error in getClubRequests: ' + e.getMessage());
        }
        
        return resp;
    }

    @AuraEnabled(cacheable=false)
    public static MembershipResponse getPendingMemberships(Id contactId) {
        MembershipResponse resp = new MembershipResponse();
        Id effectiveContactId = contactId;

        try {
            if (effectiveContactId == null) {
                List<User> users = [SELECT ContactId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
                if (!users.isEmpty() && users[0].ContactId != null) {
                    effectiveContactId = users[0].ContactId;
                }
            }
            
            resp.effectiveContactId = effectiveContactId;

            if (effectiveContactId == null) {
                resp.debugMessage = 'No contactId provided.';
                return resp;
            }

            List<Club_Membership__c> cms = [
                SELECT 
                    Id, 
                    Contact__c, 
                    Club__c, 
                    Club__r.Name, 
                    Club__r.RecordType.DeveloperName,
                    Role__c, 
                    Status__c,
                    Approval_Status__c,
                    Academic_Year__c,
                    Program_Enrollment__c
                FROM Club_Membership__c
                WHERE Contact__c = :effectiveContactId 
                AND ((Status__c != 'Active' AND Approval_Status__c != 'Approved') OR Status__c = 'Inactive')
                ORDER BY Club__r.Name ASC
            ];

            for (Club_Membership__c cm : cms) {
                MembershipDTO dto = new MembershipDTO();
                dto.membershipId = cm.Id;
                dto.clubId = cm.Club__c;
                dto.clubName = cm.Club__r != null ? cm.Club__r.Name : 'Unknown';
                dto.role = String.isNotBlank(cm.Role__c) ? cm.Role__c : 'Member';
                dto.status = String.isNotBlank(cm.Status__c) ? cm.Status__c : 'Unknown';
                dto.approvalStatus = cm.Approval_Status__c;
                dto.clubRecordType = cm.Club__r != null && cm.Club__r.RecordType != null 
                    ? cm.Club__r.RecordType.DeveloperName 
                    : '';
                dto.academicYear = cm.Academic_Year__c;
                dto.programEnrollmentId = cm.Program_Enrollment__c;
                resp.memberships.add(dto);
            }

            resp.count = resp.memberships.size();
            resp.debugMessage = 'Successfully queried ' + resp.count + ' pending/other memberships.';
            
        } catch (Exception e) {
            resp.debugMessage = 'Error: ' + e.getMessage();
             System.debug('Error in getPendingMemberships: ' + e.getMessage());
        }
        
        return resp;
    }

    // Changes made by Diksha: New Reassignment Logic START
    @AuraEnabled(cacheable=false)
    public static List<Map<String, String>> getAvailableClubsForReassignment(Id contactId) {
        List<Map<String, String>> options = new List<Map<String, String>>();
        try {
            Id effectiveContactId = contactId;
            if (effectiveContactId == null) {
                Id userId = UserInfo.getUserId();
                User u = [SELECT ContactId FROM User WHERE Id = :userId LIMIT 1];
                effectiveContactId = u.ContactId;
            }

            Set<Id> activeClubs = new Set<Id>();
            // Match the logic of the "Active Memberships" table to exclude exactly what is shown there
            for(Club_Membership__c cm : [
                SELECT Club__c 
                FROM Club_Membership__c 
                WHERE Contact__c = :effectiveContactId 
                AND (Status__c = 'Active' OR Approval_Status__c = 'Approved')
                AND Status__c != 'Inactive'
                AND Club__r.RecordType.DeveloperName = 'Professional_Club'
            ]) {
                activeClubs.add(cm.Club__c);
            }

            List<Club__c> available = [
                SELECT Id, Name FROM Club__c 
                WHERE RecordType.DeveloperName = 'Professional_Club' 
                AND Active__c = true
                AND Id NOT IN :activeClubs 
                ORDER BY Name ASC
            ];

            for(Club__c c : available) {
                options.add(new Map<String, String>{'label' => c.Name, 'value' => c.Id});
            }
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
        return options;
    }

    @AuraEnabled
    public static void processClubReassignment(Id oldMembershipId, Id newClubId, Id contactId) {
        try {
            // Changes made by Diksha: Carry over existing Role to satisfy validation rule
            Club_Membership__c oldRec = [SELECT Id, Role__c, Contact__c, Program_Enrollment__c FROM Club_Membership__c WHERE Id = :oldMembershipId LIMIT 1];

            // Set existing to Inactive - Diksha Fix: Removed Approval_Status assignment to avoid restricted picklist error
            Club_Membership__c oldMember = new Club_Membership__c(Id = oldMembershipId, Status__c = 'Inactive');
            update oldMember;

            // New Addition: Cleanup any existing records for the target club to avoid Duplicate Rule errors
            Id targetContact = contactId != null ? contactId : oldRec.Contact__c;
            List<Club_Membership__c> existingStale = [SELECT Id FROM Club_Membership__c WHERE Contact__c = :targetContact AND Club__c = :newClubId];
            if(!existingStale.isEmpty()) {
                delete existingStale;
            }

            // Create new request
            Club_Membership__c newMember = new Club_Membership__c();
            newMember.Contact__c = contactId != null ? contactId : oldRec.Contact__c;
            newMember.Club__c = newClubId;
            newMember.Status__c = 'Inactive';
            newMember.Approval_Status__c = 'Pending Approval';
            newMember.Role__c = oldRec.Role__c;
            newMember.Program_Enrollment__c = oldRec.Program_Enrollment__c;
            insert newMember;

            // Changes made by Diksha: Explicitly submit for Approval Process
            Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
            req.setObjectId(newMember.Id);
            req.setComments('Submitted for Club Reassignment.');
            Approval.process(req);
            
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    // Changes made by Diksha: New Reassignment Logic END

    @AuraEnabled
    public static void cleanupRejectedMemberships(Id contactId) {
        Id effectiveContactId = contactId;
        try {
            // If contactId is null, try to get it from the current user
            if (effectiveContactId == null) {
                List<User> users = [SELECT ContactId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
                if (!users.isEmpty() && users[0].ContactId != null) {
                    effectiveContactId = users[0].ContactId;
                }
            }
            
            if (effectiveContactId == null) {
                return;
            }

            // Aggressive cleanup: Find all Professional Club memberships for this student 
            // that are NOT Active and NOT Pending Approval.
            // This ensures ANY blocked state (Rejected, Inactive, etc.) is cleared.
            List<Club_Membership__c> toCleanup = [
                SELECT Id 
                FROM Club_Membership__c 
                WHERE Contact__c = :effectiveContactId 
                AND Club_Record_Type__c = 'Professional_Club'
                AND Status__c != 'Active'
                AND Approval_Status__c != 'Approved'
                AND Approval_Status__c != 'Pending Approval'
            ];
            
            if (!toCleanup.isEmpty()) {
                delete toCleanup;
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error cleaning up memberships: ' + e.getMessage());
        }
    }
}