/**
 * @description Invocable action to get course faculties for a course offering
 * Returns faculty names and IDs, and can fetch email addresses for selected faculties
 * @author System
 * @date 2026-05-07
 */
public with sharing class GetCourseFacultiesAction {
    
    public class FacultyInfo {
        @InvocableVariable(label='Faculty ID')
        public Id facultyId;
        
        @InvocableVariable(label='Faculty Name')
        public String facultyName;
        
        @InvocableVariable(label='Faculty Email')
        public String facultyEmail;
    }
    
    public class Request {
        @InvocableVariable(required=true label='Course Offering ID')
        public Id courseOfferingId;
        
        @InvocableVariable(required=false label='Selected Faculty IDs (comma-separated or list)')
        public String selectedFacultyIds;
        
        @InvocableVariable(required=false label='Selected Faculty IDs (as list)')
        public List<String> selectedFacultyIdsList;
    }
    
    public class Result {
        @InvocableVariable(label='Faculty List')
        public List<FacultyInfo> faculties;
        
        @InvocableVariable(label='Selected Faculty Emails')
        public List<String> selectedFacultyEmails;

        @InvocableVariable(label='Selected Faculty Emails Joined')
        public String selectedFacultyEmailsJoined;

        @InvocableVariable(label='Primary Selected Faculty ID')
        public Id primarySelectedFacultyId;
        
        @InvocableVariable(label='Selected Faculty Count')
        public Integer selectedCount;
    }
    
    /**
     * @description Get all course faculties for a course offering
     * @param requests List containing the course offering ID
     * @return List of Result objects containing faculty information
     */
    @InvocableMethod(label='Get Course Faculties' description='Retrieves faculty members for a course offering and optionally returns their email addresses')
    public static List<Result> getCourseFaculties(List<Request> requests) {
        List<Result> results = new List<Result>();
        
        for (Request req : requests) {
            Result res = new Result();
            res.faculties = new List<FacultyInfo>();
            res.selectedFacultyEmails = new List<String>();
            res.primarySelectedFacultyId = null;
            res.selectedCount = 0;
            
            try {
                // Query all course faculties for this course offering
                List<Course_Faculty__c> courseFaculties = [
                    SELECT Id, Faculty__c, Faculty__r.Name, Faculty__r.FacultyEmail__c
                    FROM Course_Faculty__c
                    WHERE Course_Offering__c = :req.courseOfferingId
                    ORDER BY Faculty__r.Name ASC
                ];
                
                // Build faculty info list
                for (Course_Faculty__c cf : courseFaculties) {
                    FacultyInfo fi = new FacultyInfo();
                    fi.facultyId = cf.Faculty__c;
                    fi.facultyName = cf.Faculty__r.Name;
                    fi.facultyEmail = cf.Faculty__r.FacultyEmail__c;
                    res.faculties.add(fi);
                }
                
                // If selected faculty IDs provided, filter and collect emails
                if (String.isNotBlank(req.selectedFacultyIds)) {
                    List<String> selectedIds = req.selectedFacultyIds.split('[;,]');
                    Set<String> selectedIdSet = new Set<String>();
                    
                    for (String id : selectedIds) {
                        if (String.isNotBlank(id)) {
                            selectedIdSet.add(id.trim());
                        }
                    }
                    
                    for (FacultyInfo fi : res.faculties) {
                        if (selectedIdSet.contains(String.valueOf(fi.facultyId))) {
                            if (res.primarySelectedFacultyId == null) {
                                res.primarySelectedFacultyId = fi.facultyId;
                            }
                            if (String.isNotBlank(fi.facultyEmail)) {
                                res.selectedFacultyEmails.add(fi.facultyEmail);
                                res.selectedCount++;
                            }
                        }
                    }
                } else if (req.selectedFacultyIdsList != null && !req.selectedFacultyIdsList.isEmpty()) {
                    // Handle list of selected faculty IDs
                    Set<String> selectedIdSet = new Set<String>(req.selectedFacultyIdsList);
                    
                    for (FacultyInfo fi : res.faculties) {
                        if (selectedIdSet.contains(String.valueOf(fi.facultyId))) {
                            if (res.primarySelectedFacultyId == null) {
                                res.primarySelectedFacultyId = fi.facultyId;
                            }
                            if (String.isNotBlank(fi.facultyEmail)) {
                                res.selectedFacultyEmails.add(fi.facultyEmail);
                                res.selectedCount++;
                            }
                        }
                    }
                }
                res.selectedFacultyEmailsJoined = String.join(res.selectedFacultyEmails, ';');
            } catch (Exception e) {
                System.debug('Error getting course faculties: ' + e.getMessage());
            }
            
            results.add(res);
        }
        
        return results;
    }
}