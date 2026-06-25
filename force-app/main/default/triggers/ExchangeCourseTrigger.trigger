trigger ExchangeCourseTrigger on Exchange_Course__c (before insert, before update) {
    Set<Id> enrollmentIds = new Set<Id>();
    for (Exchange_Course__c ec : Trigger.new) {
        if (ec.ProgramEnrollment__c != null && ec.Course_Code__c != null) {
            enrollmentIds.add(ec.ProgramEnrollment__c);
        }
    }
    
    if (!enrollmentIds.isEmpty()) {
        List<Exchange_Course__c> existingCourses = [
            SELECT Id, ProgramEnrollment__c, Course_Code__c 
            FROM Exchange_Course__c 
            WHERE ProgramEnrollment__c IN :enrollmentIds
        ];
        
        Map<String, Id> existingKeyMap = new Map<String, Id>();
        for (Exchange_Course__c existing : existingCourses) {
            String key = existing.ProgramEnrollment__c + '-' + existing.Course_Code__c;
            existingKeyMap.put(key, existing.Id);
        }
        
        for (Exchange_Course__c ec : Trigger.new) {
            if (ec.ProgramEnrollment__c != null && ec.Course_Code__c != null) {
                String key = ec.ProgramEnrollment__c + '-' + ec.Course_Code__c;
                if (existingKeyMap.containsKey(key) && existingKeyMap.get(key) != ec.Id) {
                    ec.addError('A duplicate Exchange Course with the same Course Code already exists for this Program Enrollment.');
                }
            }
        }
    }
}
