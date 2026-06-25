public without sharing class AAProfileController {

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getMyProfileData() {
        try {
            Id currentUserId = UserInfo.getUserId();
            
            List<Contact> contacts = [
                SELECT Id, FirstName, LastName, Email, Phone, AA_Type__c,
                       Primary_Campus__c, Start_Date__c, End_Date__c, 
                       Active_Status__c, LMS_Onboarded__c, Availability__c, 
                       Reporting_Manager__c, Reporting_Manager__r.Name,
                       Academic_Associate_Image__c, Birthdate, ISB_Email_ID__c, 
                       Alternate_Contact_Number__c, Designation__c, Date_of_Issue__c, 
                       Date_of_Exit__c, Academic_Year__r.Name, 
                       Highest_education_qualification__c, Location_of_Ph_D__c, 
                       Editors_of_Journal__c, Research_Collaboration_ISB__c, 
                       Research_Collaboration_with_ISB__c, Other_ISB_Related_Activities__c, 
                       CV_Link__c, Courses_Taught_at_Other_School__c, 
                       Courses_they_wish_to_teach__c, Passport_Number__c, 
                       Passport_Expiry_Date__c
                FROM Contact
                WHERE Linked_User_Id__c = :currentUserId
                LIMIT 1
            ];
            
            if (contacts.isEmpty()) {
                throw new AuraHandledException('No Academic Associate profile found for the current user. Please contact your administrator.');
            }
            
            Contact aaContact = contacts[0];

            AA_Profile__c aaProfile = null;
            List<AA_Profile__c> profiles = [
                SELECT Id, Name, Primary_Program__r.Name,
                       Start_Date__c, End_Date__c, Status__c, 
                       Availability__c, Weekly_Capacity_Hours__c,
                       Preferred_Campus_Location__r.Name,
                       Academic_Term__r.Name, LMS_Linked__c, LMS_External_ID__c,
                       Notes_Remarks__c,
                       Preferred_By_Faculty__c,
                       Employee_ID__c, AACP_Track__c, AACP_Completed__c,
                       AR_Score__c, Reason_for_Exit__c, IT_Data_Backed_Up__c,
                       Seniority__c, Tenure_Type__c, Primary_Academic_Area__c, Domain_Concentration__c,
                        Secondary_Academic_Area__c, Other_Areas_of_Interest__c,
                        Academic_Associate__r.Name,
                        Buddy_Assigned__r.Name,
                        Shadow_Course__c, Shadow_Course__r.Name
                FROM AA_Profile__c
                WHERE Academic_Associate__c = :aaContact.Id
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            
            if (!profiles.isEmpty()) {
                aaProfile = profiles[0];
            }

            return new Map<String, Object>{
                'contact' => aaContact,
                'aaProfile' => aaProfile,
                'contactId' => aaContact.Id,
                'aaProfileId' => aaProfile?.Id,
                'recordId' => aaContact.Id
            };

        } catch (QueryException qe) {
            System.debug('Query Exception in getMyProfileData: ' + qe.getMessage());
            throw new AuraHandledException('Unable to retrieve profile data: ' + qe.getMessage());
        } catch (Exception e) {
            System.debug('Error in getMyProfileData: ' + e.getMessage());
            System.debug('Stack Trace: ' + e.getStackTraceString());
            throw new AuraHandledException('Error loading AA Profile info: ' + e.getMessage());
        }
    }
    @AuraEnabled(cacheable=true)
    public static List<CourseAssignmentWrapper> getTaggedCourses(Id aaProfileId) {
        try {
            if (aaProfileId == null) {
                return new List<CourseAssignmentWrapper>();
            }

            List<AA_Profile__c> profiles = [
                SELECT Academic_Associate__c, Academic_Associate__r.Linked_User_Id__c
                FROM AA_Profile__c 
                WHERE Id = :aaProfileId
                AND Academic_Associate__r.Linked_User_Id__c = :UserInfo.getUserId()
                LIMIT 1
            ];
            
            Id contactId;
            Id linkedUserId;
            
            if (!profiles.isEmpty()) {
                contactId = profiles[0].Academic_Associate__c;
                linkedUserId = profiles[0].Academic_Associate__r.Linked_User_Id__c;
            } else {
                System.debug('Profile not found or access denied for ID: ' + aaProfileId);
                return new List<CourseAssignmentWrapper>();
            }

            // Dynamically determine what the Assignment object links to (Contact, User, or Profile)
            Id filterId = null;
            String targetObject = '';
            
            try {
                Schema.DescribeFieldResult fieldResult = Course_AA_Assignment__c.Academic_Associate__c.getDescribe();
                List<Schema.sObjectType> refs = fieldResult.getReferenceTo();
                if (!refs.isEmpty()) {
                    targetObject = refs[0].getDescribe().getName();
                }
                
                if (targetObject == 'Contact') {
                    filterId = contactId;
                } else if (targetObject == 'User') {
                    filterId = linkedUserId; // Or UserInfo.getUserId()
                } else if (targetObject == 'AA_Profile__c') {
                    filterId = aaProfileId;
                }
                
                System.debug('Junction Object links to: ' + targetObject + '. Filtering with ID: ' + filterId);
            } catch (Exception e) {
                System.debug('Error checking schema: ' + e.getMessage());
                // Fallback to Contact ID if schema check fails
                filterId = contactId;
            }

            List<Course_AA_Assignment__c> assignments = [
                SELECT Id, Name, 
                       Start_Date__c, End_Date__c, 
                       Is_Active__c, Remarks__c,
                       Academic_Term__c, Program__c,
                       LMS_Assignment_ID__c, Sync_Status__c,
                       Course_Offering__c,
                       Course_Offering__r.Name,
                       Course_Offering__r.Section_Name__c,
                       Course_Offering__r.StartDate,
                       Course_Offering__r.EndDate,
                       Course_Offering__r.EnrollmentCapacity,
                       Course_Offering__r.Enrollee_Count__c,
                       Course_Offering__r.Academic_Year__c,
                       Course_Offering__r.Academic_Year__r.Name,
                       Course_Offering__r.Teaching_Location_P__c,
                       Course_Offering__r.Location__c,
                       Course_Offering__r.Location__r.Name,
                       Course_Offering__r.Available_Seats__c,
                       Course_Offering__r.LearningCourseId,
                       Course_Offering__r.LearningCourse.Name,
                       Course_Offering__r.LearningCourse.Course_Name__c,
                       Course_Offering__r.LearningCourse.CourseNumber,
                       Course_Offering__r.LearningCourse.Credit__c,
                       Course_Offering__r.LearningCourse.Description,
                       Course_Offering__r.AcademicSessionId,
                       Course_Offering__r.AcademicSession.Name,
                       Course_Offering__r.Academic_Term__c,
                       Course_Offering__r.Academic_Term__r.Name,
                       Course_Offering__r.Program__c,
                       Course_Offering__r.Program__r.Name,
                       Course_Offering__r.PrimaryFacultyId,
                       Course_Offering__r.PrimaryFaculty.Name
                FROM Course_AA_Assignment__c
                WHERE Academic_Associate__c = :filterId
                ORDER BY Start_Date__c DESC NULLS LAST, CreatedDate DESC
            ];

            List<CourseAssignmentWrapper> wrapperList = new List<CourseAssignmentWrapper>();
            
            for (Course_AA_Assignment__c assignment : assignments) {
                CourseAssignmentWrapper wrapper = new CourseAssignmentWrapper();
                
                // Assignment fields
                wrapper.assignmentId = assignment.Id;
                wrapper.assignmentName = assignment.Name;
                wrapper.startDate = assignment.Start_Date__c;
                wrapper.endDate = assignment.End_Date__c;
                wrapper.isActive = assignment.Is_Active__c;
                wrapper.remarks = assignment.Remarks__c;
                wrapper.lmsAssignmentId = assignment.LMS_Assignment_ID__c;
                wrapper.syncStatus = assignment.Sync_Status__c;
                
                // Course Offering fields
                if (assignment.Course_Offering__r != null) {
                    wrapper.courseOfferingName = assignment.Course_Offering__r.Name;
                    wrapper.sectionName = assignment.Course_Offering__r.Section_Name__c;
                    wrapper.courseStartDate = assignment.Course_Offering__r.StartDate;
                    wrapper.courseEndDate = assignment.Course_Offering__r.EndDate;
                    wrapper.enrollmentCapacity = assignment.Course_Offering__r.EnrollmentCapacity;
                    wrapper.enrolleeCount = assignment.Course_Offering__r.Enrollee_Count__c != null ? 
                                          Integer.valueOf(assignment.Course_Offering__r.Enrollee_Count__c) : 0;
                    wrapper.availableSeats = assignment.Course_Offering__r.Available_Seats__c != null ? 
                                           Integer.valueOf(assignment.Course_Offering__r.Available_Seats__c) : 0;
                    
                    // Academic Session
                    if (assignment.Course_Offering__r.AcademicSession != null) {
                        wrapper.academicSessionName = assignment.Course_Offering__r.AcademicSession.Name;
                    }
                    
                    // Academic Term
                    if (assignment.Course_Offering__r.Academic_Term__r != null) {
                        wrapper.academicTermName = assignment.Course_Offering__r.Academic_Term__r.Name;
                    }

                    // Academic Year
                    if (assignment.Course_Offering__r.Academic_Year__r != null) {
                        wrapper.academicYear = assignment.Course_Offering__r.Academic_Year__r.Name;
                    }

                    // Location
                    String locationName = assignment.Course_Offering__r.Location__r != null ? 
                                         assignment.Course_Offering__r.Location__r.Name : 
                                         assignment.Course_Offering__r.Teaching_Location_P__c;
                    wrapper.location = locationName;
                    
                    wrapper.courseOfferingId = assignment.Course_Offering__c;
                    // Program
                    if (assignment.Course_Offering__r.Program__r != null) {
                        wrapper.programName = assignment.Course_Offering__r.Program__r.Name;
                    }
                    
                    // Primary Faculty
                    if (assignment.Course_Offering__r.PrimaryFaculty != null) {
                        wrapper.primaryFacultyName = assignment.Course_Offering__r.PrimaryFaculty.Name;
                    }
                    
                    // Learning Course fields
                    if (assignment.Course_Offering__r.LearningCourse != null) {
                        wrapper.learningCourseName = assignment.Course_Offering__r.LearningCourse.Name;
                        wrapper.courseNumber = assignment.Course_Offering__r.LearningCourse.CourseNumber;
                        wrapper.credits = assignment.Course_Offering__r.LearningCourse.Credit__c != null ? 
                                        Integer.valueOf(assignment.Course_Offering__r.LearningCourse.Credit__c) : 0;
                        wrapper.courseDescription = assignment.Course_Offering__r.LearningCourse.Description;
                    }
                }
                
                wrapperList.add(wrapper);
            }

            return wrapperList;

        } catch (Exception e) {
            System.debug('Error in getTaggedCourses: ' + e.getMessage());
            System.debug('Stack Trace: ' + e.getStackTraceString());
            throw new AuraHandledException('Error loading tagged courses: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void updateAvailability(Id aaProfileId, String availability) {
        try {
            if (aaProfileId == null) {
                throw new AuraHandledException('AA Profile ID is required');
            }

            if (String.isBlank(availability)) {
                throw new AuraHandledException('Availability value is required');
            }

            // Verify the AA Profile exists and belongs to the current user
            Id currentUserId = UserInfo.getUserId();
            List<AA_Profile__c> profiles = [
                SELECT Id, Availability__c, Academic_Associate__c,
                       Academic_Associate__r.Linked_User_Id__c
                FROM AA_Profile__c 
                WHERE Id = :aaProfileId 
                AND Academic_Associate__r.Linked_User_Id__c = :currentUserId
                LIMIT 1
            ];

            if (profiles.isEmpty()) {
                throw new AuraHandledException('AA Profile not found or you do not have permission to update it');
            }

            AA_Profile__c profileToUpdate = profiles[0];
            profileToUpdate.Availability__c = availability;
            
            update profileToUpdate;

        } catch (DmlException e) {
            System.debug('DML Error in updateAvailability: ' + e.getMessage());
            throw new AuraHandledException('Failed to update availability: ' + e.getDmlMessage(0));
        } catch (Exception e) {
            System.debug('Error in updateAvailability: ' + e.getMessage());
            System.debug('Stack Trace: ' + e.getStackTraceString());
            throw new AuraHandledException('Error updating availability: ' + e.getMessage());
        }
    }

    // Wrapper class for Course Assignment data
        public class CourseAssignmentWrapper {
        @AuraEnabled public String assignmentId { get; set; }
        @AuraEnabled public String assignmentName { get; set; }
        @AuraEnabled public Date startDate { get; set; }
        @AuraEnabled public Date endDate { get; set; }
        @AuraEnabled public Boolean isActive { get; set; }
        @AuraEnabled public String remarks { get; set; }
        @AuraEnabled public String lmsAssignmentId { get; set; }
        @AuraEnabled public String syncStatus { get; set; }
        
        @AuraEnabled public String courseOfferingName { get; set; }
        @AuraEnabled public String sectionName { get; set; }
        @AuraEnabled public DateTime courseStartDate { get; set; }  // Changed from Date to DateTime
        @AuraEnabled public DateTime courseEndDate { get; set; }    // Changed from Date to DateTime
        @AuraEnabled public Integer enrollmentCapacity { get; set; }
        @AuraEnabled public Integer enrolleeCount { get; set; }
        @AuraEnabled public Integer availableSeats { get; set; }
        
        @AuraEnabled public String learningCourseName { get; set; }
        @AuraEnabled public String courseNumber { get; set; }
        @AuraEnabled public Integer credits { get; set; }
        @AuraEnabled public String courseDescription { get; set; }
        
        @AuraEnabled public String academicSessionName { get; set; }
        @AuraEnabled public String academicTermName { get; set; }
        @AuraEnabled public String programName { get; set; }
        @AuraEnabled public String primaryFacultyName { get; set; }
        
        @AuraEnabled public String academicYear { get; set; }
        @AuraEnabled public String location { get; set; }
        @AuraEnabled public String courseOfferingId { get; set; }
    }
}