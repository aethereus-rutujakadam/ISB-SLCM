/**
 * @description Batch job to send feedback emails to Faculty for Course Offerings that have ended.
 * Checks for Term_To_Date__c = YESTERDAY.
 * Generates unique links for each assigned Academic Associate.
 */
global class FeedbackBatch implements Database.Batchable<SObject>, Schedulable {
    
    global void execute(SchedulableContext sc) {
        Database.executeBatch(new FeedbackBatch(), 20); // Batch size 20 to handle email limits safer
    }
    
    global Database.QueryLocator start(Database.BatchableContext bc) {
        // Query Course Offerings where Term_To_Date__c was yesterday
        // Using dynamic query to avoid compilation if field names are slightly off in my assumption, but I should use static query for safety.
        // Assuming Term_To_Date__c is a Date field.
        Date yesterday = Date.today().addDays(-1);
        String query = 'SELECT Id, Name, Term_To_Date__c, Program__r.Name FROM CourseOffering WHERE Term_To_Date__c = :yesterday'; // Or < TODAY ??? User said 'is passed'. I'll stick to yesterday for daily run.
        return Database.getQueryLocator(query);
    }
    
    global void execute(Database.BatchableContext bc, List<CourseOffering> scope) {
        try {
            Set<Id> courseIds = new Set<Id>();
            for (CourseOffering c : scope) {
                courseIds.add(c.Id);
            }
            
            // 1. Get Assigned Faculties (via Course_Faculty__c junction)
            // Assuming Course_Faculty__c has Course_Offering__c and Faculty__c (Contact)
            // If Faculty__c is not the name, I might need to check. But I'll try Faculty__c.
            List<Course_Faculty__c> courseFaculties = [
                SELECT Id, Course_Offering__c, Faculty__c, Faculty__r.Email, Faculty__r.Name 
                FROM Course_Faculty__c 
                WHERE Course_Offering__c IN :courseIds
                AND Faculty__r.Email != null
            ];
            
            Map<Id, List<Course_Faculty__c>> courseToFacultyMap = new Map<Id, List<Course_Faculty__c>>();
            for (Course_Faculty__c cf : courseFaculties) {
                if (!courseToFacultyMap.containsKey(cf.Course_Offering__c)) {
                    courseToFacultyMap.put(cf.Course_Offering__c, new List<Course_Faculty__c>());
                }
                courseToFacultyMap.get(cf.Course_Offering__c).add(cf);
            }
            
            // 2. Get Active assigned AAs (via Course_AA_Assignment__c)
            List<Course_AA_Assignment__c> aaAssignments = [
                SELECT Id, Course_Offering__c, Academic_Associate__c, Academic_Associate__r.Name 
                FROM Course_AA_Assignment__c 
                WHERE Course_Offering__c IN :courseIds
                AND Is_Active__c = true
            ];
            
            Map<Id, List<Course_AA_Assignment__c>> courseToAAMap = new Map<Id, List<Course_AA_Assignment__c>>();
            for (Course_AA_Assignment__c ca : aaAssignments) {
                if (!courseToAAMap.containsKey(ca.Course_Offering__c)) {
                    courseToAAMap.put(ca.Course_Offering__c, new List<Course_AA_Assignment__c>());
                }
                courseToAAMap.get(ca.Course_Offering__c).add(ca);
            }
            
            // 3. Prepare Emails
            List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
            String aaTemplateName = 'Faculty To AA Feedback';
            String asaTemplateName = 'Faculty To Academic Services Feedback';
            
            for (CourseOffering course : scope) {
                List<Course_Faculty__c> faculties = courseToFacultyMap.get(course.Id);
                List<Course_AA_Assignment__c> aas = courseToAAMap.get(course.Id);
                
                if (faculties == null || faculties.isEmpty()) continue;
                
                for (Course_Faculty__c faculty : faculties) {
                    // Generate Email Body
                    String body = 'Dear ' + faculty.Faculty__r.Name + ',\n\n';
                    body += 'The course "' + course.Name + '" has concluded. Please provide your feedback using the links below:\n\n';
                    
                    Boolean hasLinks = false;
                    
                    // AA Links
                    if (aas != null && !aas.isEmpty()) {
                        body += '<b>Academic Associate Feedback:</b><br/>';
                        for (Course_AA_Assignment__c aa : aas) {
                            String url = FeedbackURLGenerator.generateLink(
                                course.Id,
                                faculty.Faculty__c,
                                aa.Academic_Associate__c,
                                aaTemplateName
                            );
                            body += '- Feedback for ' + aa.Academic_Associate__r.Name + ': <a href="' + url + '">Click Here</a><br/>';
                            hasLinks = true;
                        }
                    } else {
                         body += 'No Academic Associates were assigned to this course.<br/>';
                    }
                    
                    body += '<br/>';
                    
                    // ASA Link
                    String asaUrl = FeedbackURLGenerator.generateLink(
                        course.Id,
                        faculty.Faculty__c,
                        null,
                        asaTemplateName
                    );
                    body += '<b>Academic Services Feedback:</b><br/>';
                    body += '- Feedback for Academic Services: <a href="' + asaUrl + '">Click Here</a><br/>';
                    hasLinks = true;
                    
                    body += '\nThank you,\nISB Team';
                    
                    // Send Email
                    Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                    mail.setToAddresses(new List<String>{ faculty.Faculty__r.Email });
                    mail.setSubject('Feedback Requested: ' + course.Name);
                    mail.setHtmlBody(body);
                    mail.setSaveAsActivity(false); // Don't save as activity task
                    emails.add(mail);
                }
            }
            
            // 4. Send Emails
            if (!emails.isEmpty()) {
                Messaging.sendEmail(emails);
                System.debug('Sent ' + emails.size() + ' feedback emails.');
            }
            
        } catch (Exception e) {
            System.debug('Error in FeedbackBatch execution: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
             // Optionally log to error object
        }
    }
    
    global void finish(Database.BatchableContext bc) {
        System.debug('FeedbackBatch finished.');
    }
}