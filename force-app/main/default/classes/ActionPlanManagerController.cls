public with sharing class ActionPlanManagerController {

    // =============================================
    // FETCH PUBLISHED TEMPLATE VERSIONS
    // =============================================
    @AuraEnabled(cacheable=true)
    public static List<ActionPlanTemplateVersion> getPublishedTemplateVersions() {
            return [
                SELECT Id, Name, Status
                FROM ActionPlanTemplateVersion
                WHERE Status IN ('Published', 'Final')
                ORDER BY Name
                LIMIT 1000
            ];
    }

    // =============================================
    // CREATE ACTION PLAN TEMPLATE + VERSION (Draft)
    // =============================================
    @AuraEnabled
    public static Map<String, String> createTemplate(String name, String type, String targetObject) {
        try {
            if (String.isBlank(name)) throw new AuraHandledException('Template name is required');
            if (String.isBlank(type)) throw new AuraHandledException('Action Plan Type is required');
            if (String.isBlank(targetObject)) throw new AuraHandledException('Target Object is required');
            
            ActionPlanTemplate apt = new ActionPlanTemplate(
                Name = name,
                ActionPlanType = type,
                TargetEntityType = targetObject,
                OwnerId = UserInfo.getUserId()
            );
            insert apt;

            // Check if a version was automatically created
            List<ActionPlanTemplateVersion> existingVersions = [
                SELECT Id 
                FROM ActionPlanTemplateVersion 
                WHERE ActionPlanTemplateId = :apt.Id 
                LIMIT 1
            ];

            ActionPlanTemplateVersion templateVersion;
            if (!existingVersions.isEmpty()) {
                templateVersion = existingVersions[0];
                // Update name if needed
                templateVersion.Name = name;
                update templateVersion;
            } /*else {
                templateVersion = new ActionPlanTemplateVersion(
                    Name = name,
                    ActionPlanTemplateId = apt.Id,
                    Status = 'Draft'
                );
                insert templateVersion;
            }*/

            return new Map<String, String>{
                'templateId' => apt.Id,
                'templateVersionId' => templateVersion.Id
            };
        } catch (DmlException e) {
            throw new AuraHandledException('Error creating template: ' + e.getDmlMessage(0));
        } catch (Exception e) {
            throw new AuraHandledException('Error creating template: ' + e.getMessage());
        }
    }

    // =============================================
    // CREATE TEMPLATE ITEM (TASK)
    // =============================================
    @AuraEnabled
    public static ActionPlanTemplateItem createTemplateItem(Id templateVersionId, String itemName, Integer dayOffset) {
        try {
            if (templateVersionId == null) throw new AuraHandledException('Template Version ID is required');
            if (String.isBlank(itemName)) throw new AuraHandledException('Item name is required');

            ActionPlanTemplateItem item = new ActionPlanTemplateItem(
                ActionPlanTemplateVersionId = templateVersionId,
                Name = itemName,
                ItemEntityType = 'Task'
            );

            
            insert item;
            return item;
        } catch (DmlException e) {
            throw new AuraHandledException('Error creating template item: ' + e.getDmlMessage(0));
        } catch (Exception e) {
            throw new AuraHandledException('Error creating template item: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Id createActionPlan(
        String planName,
        Id templateVersionId,
        Date startDate,
        String status,
        String planType,
        Boolean skipNonWorkDays,
        String actionPlanTypeCustom, // maps to Action_Plan_Type__c
        Id targetId,
        String targetObjectName
    ) {
        try {
            if (String.isBlank(planName))
                throw new AuraHandledException('Action Plan Name is required');
            if (startDate == null)
                throw new AuraHandledException('Start Date is required');
            if (targetId == null)
                throw new AuraHandledException('Target Record ID is required');

            // Validate Template
            List<ActionPlanTemplateVersion> templates = [
                SELECT Id, Name, Status
                FROM ActionPlanTemplateVersion
                WHERE Id = :templateVersionId
                LIMIT 1
            ];
            if (templates.isEmpty()) {
                throw new AuraHandledException('Template not found');
            }
            
            ActionPlanTemplateVersion template = templates[0];
            if (!(template.Status == 'Published' || template.Status == 'Final')) {
                throw new AuraHandledException('Template must be Published or Final.');
            }

            // Create Action Plan
            ActionPlan plan = new ActionPlan(
                Name = planName,
                ActionPlanTemplateVersionId = templateVersionId,
                StartDate = startDate,
                ActionPlanState = status,
                ActionPlanType = 'Industries',
                Action_Plan_Type__c = planType,
                TargetId = targetId
            );

            insert plan;
            return plan.Id;

        } catch (DmlException e) {
            throw new AuraHandledException('Error creating Action Plan: ' + e.getDmlMessage(0));
        } catch (Exception e) {
            throw new AuraHandledException('Error: ' + e.getMessage());
        }
    }

    // ===================================================================
    // BULK ACTION PLAN CREATION
    // ===================================================================
    @AuraEnabled
    public static List<Id> bulkCreateActionPlans(
        String planName,
        Id templateVersionId,
        Date startDate,
        String status,
        String planType,
        Boolean skipNonWorkDays,
        String actionPlanTypeCustom,
        List<Id> targetIds,
        String targetObjectName
    ) {
        try {
            if (String.isBlank(planName))
                throw new AuraHandledException('Action Plan Name is required');
            if (templateVersionId == null)
                throw new AuraHandledException('Template Version ID is required');
            if (startDate == null)
                throw new AuraHandledException('Start Date is required');
            if (targetIds == null || targetIds.isEmpty())
                throw new AuraHandledException('At least one Target Record ID is required');

            // Validate Template
            List<ActionPlanTemplateVersion> templates = [
                SELECT Id, Name, Status
                FROM ActionPlanTemplateVersion
                WHERE Id = :templateVersionId
                LIMIT 1
            ];
            if (templates.isEmpty()) {
                throw new AuraHandledException('Template not found');
            }
            
            ActionPlanTemplateVersion template = templates[0];
            if (!(template.Status == 'Published' || template.Status == 'Final')) {
                throw new AuraHandledException('Template must be Published or Final.');
            }

            // Create Action Plans for each target record
            List<ActionPlan> plansToInsert = new List<ActionPlan>();
            for (Id tId : targetIds) {
                plansToInsert.add(new ActionPlan(
                    Name = planName,
                    ActionPlanTemplateVersionId = templateVersionId,
                    StartDate = startDate,
                    ActionPlanState = status,
                    ActionPlanType = 'Industries',
                    Action_Plan_Type__c = planType,
                    TargetId = tId
                ));
            }

            insert plansToInsert;

            // Collect and return IDs
            List<Id> createdIds = new List<Id>();
            for (ActionPlan ap : plansToInsert)
                createdIds.add(ap.Id);

            return createdIds;

        } catch (DmlException e) {
            throw new AuraHandledException('Error creating Action Plans: ' + e.getDmlMessage(0));
        } catch (Exception e) {
            throw new AuraHandledException('Error: ' + e.getMessage());
        }
    }


    // =============================================
    // TARGET OBJECT OPTIONS (USED IN LWC)
    // =============================================
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getTargetObjectOptions() {
        List<Map<String, String>> options = new List<Map<String, String>>();
        options.add(new Map<String, String>{'label' => 'Case', 'value' => 'Case'});
        options.add(new Map<String, String>{'label' => 'Program Enrollment', 'value' => 'ProgramEnrollment'});
        options.add(new Map<String, String>{'label' => 'Program Plan', 'value' => 'ProgramPlan'});
        options.add(new Map<String, String>{'label' => 'Care Plan', 'value' => 'CarePlan'});
        options.add(new Map<String, String>{'label' => 'Contact', 'value' => 'Contact'});
        options.add(new Map<String, String>{'label' => 'Account', 'value' => 'Account'});
        return options;
    }

    @AuraEnabled(cacheable=true)
	public static List<Map<String, String>> getTargetRecords(String objectApiName) {
    List<Map<String, String>> results = new List<Map<String, String>>();
    
    try {
        if (String.isBlank(objectApiName)) {
            return results;
        }

        String query;
        // Build dynamic SOQL based on object
        if (objectApiName == 'ProgramEnrollment') {
            query = 'SELECT Id, Name FROM ProgramEnrollment LIMIT 200';
        } else if (objectApiName == 'ProgramPlan') {
            query = 'SELECT Id, Name FROM ProgramPlan LIMIT 200';
        } else if (objectApiName == 'Case') {
            query = 'SELECT Id, CaseNumber FROM Case LIMIT 200';
        } else if (objectApiName == 'Account') {
            query = 'SELECT Id, Name FROM Account LIMIT 200';
        } else if (objectApiName == 'Contact') {
            query = 'SELECT Id, Name FROM Contact WHERE RecordType.Name = \'Academic Associate\' LIMIT 200';
        } else {
            // fallback for unsupported objects
            query = 'SELECT Id, Name FROM ' + objectApiName + ' LIMIT 100';
        }

        List<SObject> records = Database.query(query);
        for (SObject s : records) {
            String label = (objectApiName == 'Case') ? (String) s.get('CaseNumber') : (String) s.get('Name');
            results.add(new Map<String, String>{
                'label' => label,
                'value' => (String) s.get('Id')
            });
        }

        return results;
    } catch (Exception e) {
        throw new AuraHandledException('Error fetching target records: ' + e.getMessage());
    }
	}
	
		// =============================================
// FETCH PICKLIST VALUES DYNAMICALLY
// =============================================
@AuraEnabled(cacheable=true)
public static List<Map<String, String>> getPicklistValues(String objectApiName, String fieldApiName) {
    List<Map<String, String>> values = new List<Map<String, String>>();
    try {
        Schema.DescribeFieldResult fieldResult = Schema.getGlobalDescribe()
            .get(objectApiName)
            .getDescribe()
            .fields
            .getMap()
            .get(fieldApiName)
            .getDescribe();

        for (Schema.PicklistEntry entry : fieldResult.getPicklistValues()) {
            values.add(new Map<String, String>{
                'label' => entry.getLabel(),
                'value' => entry.getValue()
            });
        }

        return values;
    } catch (Exception e) {
        throw new AuraHandledException('Error fetching picklist values for ' + objectApiName + '.' + fieldApiName + ': ' + e.getMessage());
    }
}


    @AuraEnabled(cacheable=true)
    public static Boolean validateUserAccess() {
        try {
            return Schema.sObjectType.ActionPlan.isCreateable();
        } catch (Exception e) {
            return false;
        }
    }
}