public without sharing class ActivateAAUserAction {

    // Wrapper class for Flow input
    public class RequestWrapper {
        @InvocableVariable(label='Contact Id' required=true)
        public Id contactId;

        @InvocableVariable(label='Assign Plans' required=false)
        public Boolean assignPlans;
    }

    // Wrapper class for Flow output
    public class ResultWrapper {
        @InvocableVariable
        public Boolean success;

        @InvocableVariable
        public String message;
    }

    @InvocableMethod(label='Activate User and Assign Plans')
    public static List<ResultWrapper> activateUsers(List<RequestWrapper> requests) {
        List<ResultWrapper> results = new List<ResultWrapper>();
        
        Set<Id> contactIds = new Set<Id>();
        Map<Id, Boolean> assignPlansMap = new Map<Id, Boolean>();
        for (RequestWrapper req : requests) {
            contactIds.add(req.contactId);
            assignPlansMap.put(req.contactId, req.assignPlans == true);
        }

        try {
            // Query contacts with extra fields for naming and user activation
            Map<Id, Contact> contactsMap = new Map<Id, Contact>([
                SELECT Id, FirstName, Linked_User_Id__c
                FROM Contact
                WHERE Id IN :contactIds
            ]);
            
            List<Id> userIdsToActivate = new List<Id>();
            Set<Id> contactsNeedingPlans = new Set<Id>();

            // Get Templates
            Map<Id, String> templateIdToName = new Map<Id, String>();
            for (ActionPlanTemplate apt : [
                SELECT Id, Name 
                FROM ActionPlanTemplate 
                WHERE Name IN ('Year 1- Onboarding', 'Year-2 Certification & Professional Development')
                AND Status IN ('Published', 'Final')
            ]) {
                templateIdToName.put(apt.Id, apt.Name);
            }

            // Get Version IDs for those Templates
            Map<String, Id> versionMap = new Map<String, Id>();
            if (!templateIdToName.isEmpty()) {
                for (ActionPlanTemplateVersion aptv : [
                    SELECT Id, ActionPlanTemplateId 
                    FROM ActionPlanTemplateVersion 
                    WHERE ActionPlanTemplateId IN :templateIdToName.keySet()
                ]) {
                    // Mapping the template name to its version id
                    String templateName = templateIdToName.get(aptv.ActionPlanTemplateId);
                    versionMap.put(templateName, aptv.Id);
                }
            }

            for (Id cId : contactIds) {
                Contact c = contactsMap.get(cId);
                if (c == null) continue;

                if (c.Linked_User_Id__c != null) {
                    userIdsToActivate.add(c.Linked_User_Id__c);
                }

                if (assignPlansMap.get(cId)) {
                    contactsNeedingPlans.add(cId);
                }
            }

            // Enqueue action plan creation to run after user creation completes
            String statusMessage = '';
            if (!contactsNeedingPlans.isEmpty()) {
                if (versionMap.isEmpty()) {
                    statusMessage = 'Warning: Action Plan Templates not found or not published. Plans could not be assigned. ';
                } else {
                    // Action plans need to be created
                    if (!userIdsToActivate.isEmpty()) {
                        // Users exist and need activation - chain action plan creation after
                        System.enqueueJob(new ActivateUsersQueueable(userIdsToActivate, contactsNeedingPlans, versionMap));
                        statusMessage = 'User activation and plan assignment initiated. ';
                    } else {
                        // No existing users to activate (new contacts) - create action plans directly
                        System.enqueueJob(new CreateActionPlansQueueable(contactsNeedingPlans, versionMap));
                        statusMessage = 'Plan assignment initiated (waiting for user creation). ';
                    }
                }
            } else if (!userIdsToActivate.isEmpty()) {
                // Only user activation needed, no action plans
                System.enqueueJob(new ActivateUsersQueueable(userIdsToActivate));
                statusMessage = 'User activation initiated. ';
            }

            ResultWrapper res = new ResultWrapper();
            if (String.isNotBlank(statusMessage)) {
                res.success = true;
                res.message = statusMessage.trim();
            } else {
                res.success = true;
                res.message = 'No activation or plan assignment required for the selected contacts.';
            }
            results.add(res);

        } catch (Exception e) {
            ResultWrapper res = new ResultWrapper();
            res.success = false;
            res.message = 'Error: ' + e.getMessage();
            results.add(res);
        }

        return results;
    }


    // Queueable class → creates action plans after user creation
    public class CreateActionPlansQueueable implements Queueable {
        
        private Set<Id> contactIds;
        private Map<String, Id> versionMap;
        private Integer retryCount;
        private final Integer MAX_RETRIES = 5;
        private final Integer RETRY_DELAY_MS = 2000; // 2 seconds between retries
        
        public CreateActionPlansQueueable(Set<Id> cIds, Map<String, Id> vMap) {
            this(cIds, vMap, 0);
        }
        
        private CreateActionPlansQueueable(Set<Id> cIds, Map<String, Id> vMap, Integer retry) {
            this.contactIds = cIds;
            this.versionMap = vMap;
            this.retryCount = retry;
        }
        
        public void execute(QueueableContext qc) {
            try {
                // Query contacts to check if Linked_User_Id__c is populated
                Map<Id, Contact> contactsMap = new Map<Id, Contact>([
                    SELECT Id, FirstName, Linked_User_Id__c
                    FROM Contact
                    WHERE Id IN :contactIds
                ]);
                
                List<ActionPlan> plansToInsert = new List<ActionPlan>();
                Set<Id> contactsStillWaiting = new Set<Id>();
                
                for (Id cId : contactIds) {
                    Contact c = contactsMap.get(cId);
                    if (c == null) continue;
                    
                    // Check if user has been created yet
                    if (c.Linked_User_Id__c == null) {
                        contactsStillWaiting.add(cId);
                        continue;
                    }
                    
                    // User exists, create action plans
                    Id v1Id = versionMap.get('Year 1- Onboarding');
                    if (v1Id != null) {
                        plansToInsert.add(new ActionPlan(
                            Name = c.FirstName + ' - Year 1 Plan',
                            ActionPlanTemplateVersionId = v1Id,
                            TargetId = c.Id,
                            StartDate = Date.today(),
                            ActionPlanState = 'In Progress',
                            IsUsingHolidayHours = true,
                            ActionPlanType = 'Industries',
                            Action_Plan_Type__c = 'Academic Associate Plan'
                        ));
                    }
                    
                    Id v2Id = versionMap.get('Year-2 Certification & Professional Development');
                    if (v2Id != null) {
                        plansToInsert.add(new ActionPlan(
                            Name = c.FirstName + ' - Year 2 Plan',
                            ActionPlanTemplateVersionId = v2Id,
                            TargetId = c.Id,
                            StartDate = Date.today().addYears(1),
                            ActionPlanState = 'In Progress',
                            IsUsingHolidayHours = true,
                            ActionPlanType = 'Industries',
                            Action_Plan_Type__c = 'Academic Associate Plan'
                        ));
                    }
                }
                
                // Insert action plans for contacts where user exists
                if (!plansToInsert.isEmpty()) {
                    insert plansToInsert;
                }
                
                // Retry for contacts still waiting for user creation
                if (!contactsStillWaiting.isEmpty() && retryCount < MAX_RETRIES) {
                    System.enqueueJob(new CreateActionPlansQueueable(contactsStillWaiting, versionMap, retryCount + 1));
                } else if (!contactsStillWaiting.isEmpty()) {
                    // Max retries reached
                }
                
            } catch (Exception ex) {
                // Handle exception
            }
        }
    }

    // Queueable class → avoids mixed DML
    public class ActivateUsersQueueable implements Queueable {

        private List<Id> userIds;
        private Set<Id> contactsNeedingPlans;
        private Map<String, Id> versionMap;

        // Constructor for user activation only
        public ActivateUsersQueueable(List<Id> uIds) {
            this.userIds = uIds;
            this.contactsNeedingPlans = null;
            this.versionMap = null;
        }
        
        // Constructor for user activation + action plan creation
        public ActivateUsersQueueable(List<Id> uIds, Set<Id> planContactIds, Map<String, Id> vMap) {
            this.userIds = uIds;
            this.contactsNeedingPlans = planContactIds;
            this.versionMap = vMap;
        }

        public void execute(QueueableContext qc) {
            try {
                // Fetch the role ID for "Academic Associate"
                Id roleId = null;
                List<UserRole> roleList = [SELECT Id FROM UserRole WHERE Name = 'Academic Associate' LIMIT 1];
                if (!roleList.isEmpty()) {
                    roleId = roleList[0].Id;
                }

                List<User> usersToUpdate = [
                    SELECT Id, IsActive, UserRoleId 
                    FROM User 
                    WHERE Id IN :userIds
                ];

                List<User> finalUsersToUpdate = new List<User>();
                for (User u : usersToUpdate) {
                    Boolean modified = false;
                    // If user is inactive, activate them
                    if (!u.IsActive) {
                        u.IsActive = true;
                        modified = true;
                    }
                    // If user doesn't have the correct role, assign it
                    if (roleId != null && u.UserRoleId != roleId) {
                        u.UserRoleId = roleId;
                        modified = true;
                    }
                    if (modified) {
                        finalUsersToUpdate.add(u);
                    }
                }

                if (!finalUsersToUpdate.isEmpty()) {
                    update finalUsersToUpdate;
                }
                
                // After user activation, chain action plan creation if needed
                if (contactsNeedingPlans != null && !contactsNeedingPlans.isEmpty() && versionMap != null && !versionMap.isEmpty()) {
                    System.enqueueJob(new CreateActionPlansQueueable(contactsNeedingPlans, versionMap));
                }

            } catch (Exception ex) {
                // User Activation/Role Assignment Error
            }
        }
    }
}