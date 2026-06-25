public with sharing class ClubMembershipRolesController {
    
    public class MembershipDTO {
        @AuraEnabled public String role;
        @AuraEnabled public String clubName;
    }

    public class RolesResponse {
        @AuraEnabled public List<MembershipDTO> memberships;
        @AuraEnabled public Integer count;
        @AuraEnabled public String debugMessage;
        
        public RolesResponse() {
            this.memberships = new List<MembershipDTO>();
            this.count = 0;
        }
    }

    @AuraEnabled(cacheable=false)
    public static RolesResponse getClubMembershipRoles(Id contactId) {
        RolesResponse resp = new RolesResponse();
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

            if (effectiveContactId == null) {
                resp.debugMessage = 'No contactId provided and current user has no ContactId.';
                return resp;
            }

            // Query club memberships with roles
            List<Club_Membership__c> cms = [
                SELECT 
                    Id, 
                    Contact__c, 
                    Club__c, 
                    Club__r.Name, 
                    Role__c, 
                    Status__c
                FROM Club_Membership__c
                WHERE Contact__c = :effectiveContactId AND Status__c = 'Active'
                ORDER BY Role__c ASC
            ];

            // Transform to DTOs
            for (Club_Membership__c cm : cms) {
                MembershipDTO dto = new MembershipDTO();
                dto.role = String.isNotBlank(cm.Role__c) ? cm.Role__c : 'Member';
                dto.clubName = cm.Club__r != null ? cm.Club__r.Name : 'Unknown';
                resp.memberships.add(dto);
            }

            resp.count = resp.memberships.size();
            resp.debugMessage = 'Successfully queried ' + resp.count + ' club membership role(s) for Contact: ' + effectiveContactId;
            
        } catch (Exception e) {
            resp.debugMessage = 'Error: ' + e.getMessage() + ' | Stack: ' + e.getStackTraceString();
            System.debug('Error in getClubMembershipRoles: ' + resp.debugMessage);
        }
        
        return resp;
    }
}