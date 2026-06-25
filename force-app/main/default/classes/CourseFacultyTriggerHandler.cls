/**
 * @description Handler class for CourseFacultyTrigger
 * Automatically creates Payment_Information__c records when Course_Faculty__c records are created
 * @author System
 * @date 2026-04-22
 */
public with sharing class CourseFacultyTriggerHandler {
    
    /**
     * @description Handles after insert trigger event on Course_Faculty__c
     * Creates Payment_Information__c records for newly created Course_Faculty__c records
     * @param newCourseFaculties List of newly inserted Course_Faculty__c records
     */
    public static void handleAfterInsert(List<Course_Faculty__c> newCourseFaculties) {
        // Filter out records that don't have required lookups
        Set<Id> courseOfferingIds = new Set<Id>();
        Set<Id> facultyIds = new Set<Id>();
        
        for (Course_Faculty__c cf : newCourseFaculties) {
            if (cf.Faculty__c != null && cf.Course_Offering__c != null) {
                courseOfferingIds.add(cf.Course_Offering__c);
                facultyIds.add(cf.Faculty__c);
            }
        }
        
        if (courseOfferingIds.isEmpty() || facultyIds.isEmpty()) {
            return;
        }
        
        // Query CourseOffering records to get Program, Academic Year, Learning Course, etc.
        Map<Id, CourseOffering> courseOfferingMap = new Map<Id, CourseOffering>([
            SELECT Id, Name, Program__c, Program__r.Name, 
                   Academic_Year__c, Academic_Year__r.Name,
                   LearningCourseId, Academic_Term__c, 
                   AcademicSessionId, Location__c
            FROM CourseOffering
            WHERE Id IN :courseOfferingIds
        ]);
        
        // Query Faculty (Contact) records to get Faculty Type and Location
        Map<Id, Contact> facultyMap = new Map<Id, Contact>([
            SELECT Id, Name, Faculty_Type__c, Location__c
            FROM Contact
            WHERE Id IN :facultyIds
              AND RecordType.DeveloperName = 'Faculty'
        ]);
        
        // Query CourseManager records for the relevant Course Offerings
        Map<Id, Id> spocByOffering = new Map<Id, Id>();
        Map<Id, Id> courseManagerByOffering = new Map<Id, Id>();

        for (course_managers__c cm : [
            SELECT Course_Offering__c, Role__c, User__c
            FROM course_managers__c
            WHERE Course_Offering__c IN :courseOfferingIds
        ]) {
            if (cm.Role__c == 'Delivery Manager' && cm.User__c != null) {
                spocByOffering.put(cm.Course_Offering__c, cm.User__c);
            } else if (cm.Role__c == 'Manager' && cm.User__c != null) {
                courseManagerByOffering.put(cm.Course_Offering__c, cm.User__c);
            }
        }

        // Create Payment_Information__c records
        List<Payment_Information__c> paymentsToInsert = new List<Payment_Information__c>();
        for (Course_Faculty__c cf : newCourseFaculties) {
            // Skip if required lookups are missing
            if (cf.Faculty__c == null || cf.Course_Offering__c == null) {
                continue;
            }

            CourseOffering courseOffering = courseOfferingMap.get(cf.Course_Offering__c);
            Contact faculty = facultyMap.get(cf.Faculty__c);

            // Skip if related records not found
            if (courseOffering == null || faculty == null) {
                continue;
            }

            // Create Payment_Information__c record
            Payment_Information__c payment = new Payment_Information__c();

            // Set Subject (Faculty Name - Program Name - Academic Year Name) with max 255 chars
            String programName = courseOffering.Program__r?.Name;
            String academicYearName = courseOffering.Academic_Year__r?.Name;
            String fullSubject = faculty.Name + 
                                (programName != null ? ' - ' + programName : '') + 
                                (academicYearName != null ? ' - ' + academicYearName : '');

            // Truncate to 255 characters if needed
            payment.Subject__c = fullSubject.length() > 255 ? fullSubject.substring(0, 255) : fullSubject;

            // Set lookup fields
            payment.Faculty__c = cf.Faculty__c;
            payment.Course_Faculty__c = cf.Id;
            payment.Course_Offering__c = cf.Course_Offering__c;
            payment.Program__c = courseOffering.Program__c;
            payment.Academic_Year__c = courseOffering.Academic_Year__c;

            // Set additional lookups from CourseOffering
            payment.Learning_Course__c = courseOffering.LearningCourseId;
            payment.Academic_Term__c = courseOffering.Academic_Term__c;
            payment.Academic_Session__c = courseOffering.AcademicSessionId;
            payment.Location_Lookup__c = courseOffering.Location__c;

            // Populate SPOC and Course Manager fields if either role is found
            Id spoc = spocByOffering.get(cf.Course_Offering__c);
            Id courseManager = courseManagerByOffering.get(cf.Course_Offering__c);

            if (spoc != null) {
                payment.SPOC__c = spoc;
            }

            if (courseManager != null) {
                payment.Course_Manager__c = courseManager;
            }

            paymentsToInsert.add(payment);
        }
        
        // Insert Payment_Information__c records
        if (!paymentsToInsert.isEmpty()) {
            try {
                insert paymentsToInsert;
            } catch (DmlException e) {
                // Log error and add to Course_Faculty__c records
                for (Course_Faculty__c cf : newCourseFaculties) {
                    cf.addError('Error creating Payment Information: ' + e.getMessage());
                }
            }
        }
    }
}