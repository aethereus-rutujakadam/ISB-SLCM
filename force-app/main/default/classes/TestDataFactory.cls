@isTest
public class TestDataFactory {

    // Static map to store test record IDs for easy reference in other test classes
    public static Map<String, Id> testDataMap = new Map<String, Id>();
    public static Integer fakeIdCount = 0;

    // Utility: Generate Fake ID (No DML)
    public static String getFakeId(Schema.SObjectType sot) {
        String result = String.valueOf(fakeIdCount++);
        return sot.getDescribe().getKeyPrefix() + '0'.repeat(12 - result.length()) + result;
    }

    // Test Contact (Student)
    public static Contact testContact() {
        Id studentRTId = [SELECT Id FROM RecordType WHERE SObjectType='Contact' AND DeveloperName='Student' LIMIT 1].Id;
        String uniqueKey = System.currentTimeMillis() + String.valueOf(Math.abs(Crypto.getRandomInteger()));
        Contact con = new Contact(
            FirstName = 'Test',
            LastName = 'Student_' + uniqueKey,
            Email = 'test' + uniqueKey + '@isb.com',
            hed__Preferred_Email__c = 'VF Email ID',
            VF_Email_ID__c = 'test' + uniqueKey + '@isb.com',
            RecordTypeId = studentRTId
        );
        insert con;
        testDataMap.put('studentContactId', con.Id);
        return con;
    }

    // Test Program
    public static Program testProgram() {
        Program prog = new Program(
            Name = 'MBA Program'
        );
        insert prog;
        testDataMap.put('programId', prog.Id);
        return prog;
    }

    // Test Academic Year
    public static AcademicYear testAcademicYear() {
        AcademicYear ay = new AcademicYear(
            Name = '2025-2026'
        );
        insert ay;
        testDataMap.put('academicYearId', ay.Id);
        return ay;
    }

    // Test Program Enrollment
    public static ProgramEnrollment testProgramEnrollment(Contact studentContact, Program prog) {
        return testProgramEnrollment(studentContact, prog, null);
    }

    public static ProgramEnrollment testProgramEnrollment(Contact studentContact, Program prog, String pgid) {
        AcademicYear ay = testAcademicYear();
        ProgramEnrollment pe = new ProgramEnrollment(
            Name = 'Test Enrollment',
            ContactId = studentContact.Id,
            ProgramId = prog.Id,
            PGID__c = pgid,
            Status = 'Registered',
            Academic_Year__c = ay.Id
        );
        insert pe;
        testDataMap.put('programEnrollmentId', pe.Id);
        return pe;
    }

    // Test Case (Generic)
    public static Case testCase() {

        Contact con = testContact();

        Case c = new Case(
            RecordTypeId = [SELECT Id FROM RecordType WHERE SObjectType = 'Case' AND Name = 'Graduate Audit' LIMIT 1].Id,
            Status = 'New',
            Origin = 'Phone',
            Subject = 'Test Case',
            Comments__c = 'Initial test case creation',
            ContactId = con.Id
        );
        insert c;
        testDataMap.put('genericCaseId', c.Id);
        return c;
    }

    // Test Graduation Eligibility
    public static Graduation_Eligibility__c testGraduationEligibility(
        Id programId,
        Id programEnrollmentId,
        Id academicYearId,
        String status,
        Case testcase
    ) {
        Graduation_Eligibility__c ge = new Graduation_Eligibility__c(
            Name = 'Test GE',
            Program__c = programId,
            Program_Enrollment__c = programEnrollmentId,
            Academic_Year__c = academicYearId,
            Eligibility_Status__c = status,
            Case__c = testcase.Id
        );
        insert ge;
        testDataMap.put('graduationEligibilityId', ge.Id);
        return ge;
    }

    public static Learning testLearning() {
        Learning lrn = new Learning(
            Name = 'Test Learning'
        );
        insert lrn;
        testDataMap.put('learningId', lrn.Id);
        return lrn;
    }

    // Learning Course
    public static LearningCourse testLearningCourse(Id learningId) {
        String uniqueKey = String.valueOf(System.currentTimeMillis()) + String.valueOf(Math.abs(Crypto.getRandomInteger()));
        LearningCourse lc = new LearningCourse(
            Name = 'Test Learning Course',
            LearningId = learningId,
            CourseNumber = 'TEST-' + uniqueKey.right(6)
        );
        insert lc;
        testDataMap.put('learningCourseId', lc.Id);
        return lc;
    }

    // Academic Session
    public static AcademicSession testAcademicSession() {
        AcademicSession sess = new AcademicSession(
            Name = '2025 Fall'
        );
        insert sess;
        testDataMap.put('academicSessionId', sess.Id);
        return sess;
    }

    public static AcademicTerm testAcademicTerm() {
        return testAcademicTerm(null);
    }

    public static AcademicTerm testAcademicTerm(Id programId) {
        AcademicTerm t = new AcademicTerm(
            Name = 'Term 2025'
        );
        if (programId != null) {
            t.Program__c = programId;
        }
        insert t;
        testDataMap.put('academicTermId', t.Id);
        return t;
    }

    // Course Offering
    public static CourseOffering testCourseOffering(Id learningCourseId, Id academicSessionId) {
        return testCourseOffering(learningCourseId, academicSessionId, null, null, null, null);
    }

    public static CourseOffering testCourseOffering(Id learningCourseId, Id academicSessionId, Id programId, Id termId, Id locationId, String examTypes) {
        CourseOffering co = new CourseOffering(
            Name = 'Test Offering',
            IsActive = true,
            AcademicSessionId = academicSessionId,
            LearningCourseId = learningCourseId,
            Program__c = programId,
            Academic_term__c = termId,
            Location__c = locationId,
            Exam_Types__c = examTypes
        );
        insert co;
        testDataMap.put('courseOfferingId', co.Id);
        return co;
    }

    // Convenience: zero-args — builds full prerequisite chain (no Program / Term_To_Date).
    // Explicit casts resolve Apex ambiguity between (Id,Id) and (Id,Date) overloads.
    public static CourseOffering testCourseOffering() {
        return testCourseOffering((Id) null, (Date) null);
    }

    // Convenience: caller supplies Program + Term_To_Date; builds Learning→LearningCourse→AcademicSession internally.
    public static CourseOffering testCourseOffering(Id programId, Date termToDate) {
        Learning lrn = new Learning(Name = 'Test Learning');
        insert lrn;
        testDataMap.put('learningId', lrn.Id);

        String uniqueKey = String.valueOf(System.currentTimeMillis())
                         + String.valueOf(Math.abs(Crypto.getRandomInteger()));
        LearningCourse lc = new LearningCourse(
            Name         = 'Test Learning Course',
            LearningId   = lrn.Id,
            CourseNumber = 'TEST-' + uniqueKey.right(6)
        );
        insert lc;
        testDataMap.put('learningCourseId', lc.Id);

        AcademicSession sess = new AcademicSession(Name = '2025 Fall');
        insert sess;
        testDataMap.put('academicSessionId', sess.Id);

        CourseOffering co = new CourseOffering(
            Name              = 'Test Offering',
            IsActive          = true,
            LearningCourseId  = lc.Id,
            AcademicSessionId = sess.Id,
            Program__c        = programId,
            Term_To_Date__c   = termToDate
        );
        insert co;
        testDataMap.put('courseOfferingId', co.Id);
        return co;
    }

    // Test User
     // Test User (FIXED – REQUIRED)
public static User testUser(String alias, String email) {

    Profile p = [
        SELECT Id
        FROM Profile
        WHERE Name = 'Standard User'
        LIMIT 1
    ];

    String uniqueKey =
        System.currentTimeMillis() +
        '_' +
        Math.abs(Crypto.getRandomInteger());

    User u = new User(
        FirstName = 'Test',
        LastName = 'User_' + uniqueKey,
        Email = 'test_' + uniqueKey + '@example.com',
        Username = 'test_' + uniqueKey + '@example.com', // ✅ FIX
        Alias = alias.length() > 8 ? alias.substring(0, 8) : alias,
        TimeZoneSidKey = 'America/Los_Angeles',
        LocaleSidKey = 'en_US',
        EmailEncodingKey = 'UTF-8',
        ProfileId = p.Id,
        LanguageLocaleKey = 'en_US'
    );

    insert u;
    return u;
}
    // Test Academic Associate Contact
    public static Contact testAAContact(User u) {
        if (u == null) {
            u = [SELECT Id, Email FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        }

        Contact aaContact = new Contact(
            FirstName         = 'AA',
            LastName          = 'Associate',
            Email             = 'aa.associate.' + Datetime.now().getTime() + '@example.com',
            VF_Email_ID__c    = 'aa.associate.' + Datetime.now().getTime() + '@example.com',
            hed__Preferred_Email__c = 'VF Email ID',
            Linked_User_Id__c = u.Id,
            Active_Status__c  = 'Active'   // required: PreventAssignmentWhenAAInactive validation rule checks
                                            // Course_AA_Assignment → AA_Profile → Contact.Active_Status__c
        );

        Id aaContactRTId = [SELECT Id FROM RecordType WHERE SObjectType='Contact' AND DeveloperName='Academic_Associate' LIMIT 1].Id;
        aaContact.RecordTypeId = aaContactRTId;

        insert aaContact;
        testDataMap.put('aaContactId', aaContact.Id);
        return aaContact;
    }

    // AA Profile
    public static AA_Profile__c testAAProfile(Id termId, Id contactId) {
        AA_Profile__c profile = new AA_Profile__c(
            Name = 'Test AA Profile',
            Academic_Term__c = termId,
            Academic_Associate__c = contactId,
            Status__c = 'Active'
        );
        insert profile;
        testDataMap.put('aaProfileId', profile.Id);
        return profile;
    }

    // Create Case linked to Student and owned by AA User
    public static Case testStudentCase(Contact student, User aaUser) {
        Case c = new Case(
            RecordTypeId = [SELECT Id FROM RecordType WHERE SObjectType='Case' AND Name='Graduate Audit' LIMIT 1].Id,
            Status = 'New',
            Origin = 'Phone',
            Subject = 'Test Student Case',
            ContactId = student.Id,
            OwnerId = aaUser.Id
        );
        insert c;
        testDataMap.put('studentCaseId', c.Id);
        return c;
    }

    // Action Plan Template
    public static ActionPlanTemplate testActionPlanTemplate() {
        ActionPlanTemplate apt = new ActionPlanTemplate(
            Name = 'Test Template',
            ActionPlanType = 'Industries',
            TargetEntityType = 'Case'
        );
        insert apt;
        testDataMap.put('actionPlanTemplateId', apt.Id);
        return apt;
    }

    // Action Plan Template Version
    public static ActionPlanTemplateVersion testActionPlanTemplateVersion(Id templateId) {
        List<ActionPlanTemplateVersion> existing = [SELECT Id, Name, Status FROM ActionPlanTemplateVersion WHERE ActionPlanTemplateId = :templateId LIMIT 1];
        if (!existing.isEmpty()) {
            return existing[0]; 
        }
        
        ActionPlanTemplateVersion aptv = new ActionPlanTemplateVersion(
            Name = 'Test Template Version',
            ActionPlanTemplateId = templateId,
            Status = 'Draft'
        );
        insert aptv;
        testDataMap.put('actionPlanTemplateVersionId', aptv.Id);
        return aptv;
    }

    // Action Plan Template Item
    public static ActionPlanTemplateItem testActionPlanTemplateItem(Id templateVersionId) {
        ActionPlanTemplateItem apti = new ActionPlanTemplateItem(
            Name = 'Test Item',
            ActionPlanTemplateVersionId = templateVersionId,
            ItemEntityType = 'Task'
        );
        insert apti;
        testDataMap.put('actionPlanTemplateItemId', apti.Id);
        return apti;
    }

    // Action Plan
    public static ActionPlan testActionPlan(Id templateVersionId, Id targetId) {
        ActionPlan ap = new ActionPlan(
            Name = 'Test Action Plan',
            ActionPlanTemplateVersionId = templateVersionId,
            TargetId = targetId,
            StartDate = Date.today(),
            ActionPlanState = 'In Progress',
            ActionPlanType = 'Industries',
            IsUsingHolidayHours = false
        );
        insert ap;
        testDataMap.put('actionPlanId', ap.Id);
        return ap;
    }

    // Location
    public static Schema.Location testLocation(String name) {
        Schema.Location loc = new Schema.Location(
            Name = name,
            LocationType = 'Building' 
        );
        insert loc;
        testDataMap.put('locationId', loc.Id);
        return loc;
    }

    // Exam Schedule
    public static Exam_Schedule__c testExamSchedule(Id programId, Id termId, Id locationId) {
        Exam_Schedule__c examSchedule = new Exam_Schedule__c(
            Window_Start__c = Date.today().addDays(7),
            Window_End__c = Date.today().addDays(8),
            Program__c = programId,
            Academic_Term__c = termId,
            Location__c = locationId
        );
        insert examSchedule;
        testDataMap.put('examScheduleId', examSchedule.Id);
        return examSchedule;
    }

    // Exam (Examination)
    public static Examination testExama(Id programId, Id termId) {
        // Create Exam Schedule first (required)
        Schema.Location loc = testLocation('Test Exam Hall');
        Exam_Schedule__c examSchedule = testExamSchedule(programId, termId, loc.Id);
        
        Examination exam = new Examination(
            Name = 'Test Exam',
            Program__c = programId,
            Academic_Term__c = termId,
            Exam_Schedule__c = examSchedule.Id,
            Start_Date_Time__c = System.now().addDays(7),
            End_Date_Time__c = System.now().addDays(7).addHours(2),
            Date_of_Exam__c = Date.today().addDays(7), // <--- ADD THIS LINE
            Slot__c = 'Morning',
            Mode__c = 'Offline',
            Visible_To_AA__c = true
        );
        insert exam;
        testDataMap.put('examId', exam.Id);
        return exam;
    }

    // Exam AA
    public static Exam_AA__c testExamAA(Id examId, Id contactId) {
        Exam_AA__c eaa = new Exam_AA__c(
            Exam__c = examId,
            Academic_Associate__c = contactId,
            Special_Instructions__c = 'Test Instructions',
            Assigned_On__c = Date.today()
        );
        insert eaa;
        testDataMap.put('examAAId', eaa.Id);
        return eaa;
    }

    // Faculty Contact
    public static Contact testFacultyContact(String firstName, String lastName, String email) {
        Id facultyRTId = [SELECT Id FROM RecordType WHERE SObjectType='Contact' AND DeveloperName='Faculty' LIMIT 1].Id;
        Contact faculty = new Contact(
            FirstName = firstName,
            LastName = lastName,
            Email = email,
            RecordTypeId = facultyRTId
        );
        insert faculty;
        testDataMap.put('facultyContactId', faculty.Id);
        return faculty;
    }

    // AA Profile
    public static AA_Profile__c testAAProfile(Id contactId) {
        AA_Profile__c aaProfile = new AA_Profile__c(
            Academic_Associate__c = contactId,
            Status__c             = 'Active'
        );
        insert aaProfile;
        testDataMap.put('aaProfileId', aaProfile.Id);
        return aaProfile;
    }

    // Course AA Assignment
public static Course_AA_Assignment__c testCourseAAAssignment(
    Id contactId,
    Id courseOfferingId,
    Id aaProfileId
) {
    // Determine lookup target dynamically
    Schema.DescribeFieldResult d =
        Course_AA_Assignment__c.Academic_Associate__c.getDescribe();

    String targetObject = d.getReferenceTo()[0].getDescribe().getName();
    Id associateId;

    if (targetObject == 'AA_Profile__c') {
        associateId = aaProfileId;
    } else if (targetObject == 'User') {
        associateId = [
            SELECT Linked_User_Id__c
            FROM Contact
            WHERE Id = :contactId
            LIMIT 1
        ].Linked_User_Id__c;
    } else {
        // Contact
        associateId = contactId;
    }

    Course_AA_Assignment__c assign = new Course_AA_Assignment__c(
        Name = 'Test Assignment',
        Academic_Associate__c = associateId,
        Course_Offering__c = courseOfferingId,
        Start_Date__c = Date.today(),
        End_Date__c = Date.today().addDays(90),
        Is_Active__c = true
    );
    insert assign;

    testDataMap.put('courseAAAssignmentId', assign.Id);
    return assign;
}
    // =========================================
// NEW METHODS FOR LOA CASE TESTING
// =========================================

// Create Academic Term
public static AcademicTerm createTerm(Id programId, String termName, Date startDate) {
    AcademicTerm t = new AcademicTerm(
        Name = termName,
        Program__c = programId,   // FIXED FIELD NAME
        StartDate = startDate
    );
    insert t;
    return t;
}
public static AcademicSession createSessionWithTerm(Id programId, String termName, Date startDate) {

    AcademicTerm t = new AcademicTerm(
        Name = termName,
        Program__c = programId
    );
    insert t;

    AcademicSession s = new AcademicSession(
        Name = termName,
        AcademicTermId = t.Id
    );
    insert s;

    return s;
}


// Create Enrollment Session for LOA Processing
public static Enrollment_Session__c createEnrollmentSession(
    Id programEnrollmentId,
    Id academicSessionId
) {

    // ✅ Get a VALID picklist value dynamically
    Schema.DescribeFieldResult d =
        Enrollment_Session__c.SObjectType
            .getDescribe()
            .fields.getMap()
            .get('Status__c')
            .getDescribe();

    String validStatus;
    for (Schema.PicklistEntry p : d.getPicklistValues()) {
        if (p.isActive()) {
            validStatus = p.getValue();
            break;
        }
    }

    System.assertNotEquals(
        null,
        validStatus,
        'No valid Status__c picklist value found'
    );

    Enrollment_Session__c es = new Enrollment_Session__c(
        Program_Enrollment__c = programEnrollmentId,
        Academic_Session__c = academicSessionId,
        Status__c = validStatus // ✅ SAFE
    );

    insert es;
    return es;
}

// Overloaded method: Accepts Status manually
    // FIX: Removed assignments to Read-Only fields (Attendance__c, Attended_Sessions__c)
    public static Enrollment_Session__c createEnrollmentSession(
        Id programEnrollmentId,
        Id academicSessionId,
        String status
    ) {
        Enrollment_Session__c es = new Enrollment_Session__c(
            Program_Enrollment__c = programEnrollmentId,
            Academic_Session__c = academicSessionId,
            Status__c = status
        );

        insert es;
        return es;
    }

    // Helper to create Course Attendance
    // UPDATED: Now accepts and sets the REQUIRED Master-Detail and Lookup fields
    public static Course_Attendance__c createCourseAttendance(
        Id contactId, 
        Id courseOfferingId, 
        String status, 
        Date dateVal,
        Id enrollmentSessionId, // REQUIRED (Master-Detail)
        Id programEnrollmentId  // REQUIRED (Mandatory Lookup)
    ) {
        Course_Attendance__c ca = new Course_Attendance__c(
            Contact__c = contactId,
            Course_Offering__c = courseOfferingId,
            Status__c = status,
            // Date__c = dateVal, // Removed because this field does not exist
            Enrollment_Session__c = enrollmentSessionId, // ✅ Fixes REQUIRED_FIELD_MISSING
            Program_Enrollment__c = programEnrollmentId  // ✅ Fixes REQUIRED_FIELD_MISSING
        );
        insert ca;
        return ca;
    }

// Create LOA Case for CaseTriggerHelper
public static Case createLOACase(
    Contact con,
    Id programId,
    String fromTerm,
    String toTerm,
    Id recordTypeId,
    String statusBeforeUpdate
) {
    Case c = new Case(
        Subject = 'Test LOA Case',
        Status = statusBeforeUpdate,
        ContactId = con.Id,
        OwnerId = UserInfo.getUserId(),
        RecordTypeId = recordTypeId,
        Program__c = programId,
        From_Term__c = fromTerm,
        To_Term__c = toTerm,
        Origin = 'Web'
    );
    insert c;

    return c;
}
    
    // =========================================
    // NEW METHODS FOR CLUB MEMBERSHIP TESTING
    // =========================================

    // // Test Club (Account)
    // public static Account testClub(String name, String recordTypeDevName) {
    //     Id recordTypeId = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND DeveloperName = :recordTypeDevName LIMIT 1].Id;
    //     Account club = new Account(
    //         Name = name,
    //         RecordTypeId = recordTypeId
    //     );
    //     insert club;
    //     testDataMap.put('clubId_' + name, club.Id);
    //     return club;
    // }

    // Add this to your TestDataFactory class
    public static SObject testActualClub(String clubName) {
        // We use a generic SObject approach since I don't know the exact API name 
        // of your custom Club object, but based on your field, it's likely 'Club__c'
        Schema.SObjectType targetType = Schema.getGlobalDescribe().get('Club__c');
        SObject newClub = targetType.newSObject();
        newClub.put('Name', clubName);
        // Add other required fields if you know them
        insert newClub;
        return newClub;
    }

    // Test Club (Account) - UPDATED TO BE DEFENSIVE
    public static Account testClub(String name, String recordTypeDevName) {
    // 1. Try to find the specific Record Type requested
    List<RecordType> rtypes = [SELECT Id FROM RecordType 
                               WHERE SObjectType = 'Account' 
                               AND (DeveloperName = :recordTypeDevName OR Name = :recordTypeDevName) 
                               LIMIT 1];
    
    Id rtId;
    if (!rtypes.isEmpty()) {
        rtId = rtypes[0].Id;
    } else {
        // 2. FALLBACK: Try Sports Organization (Common for Clubs)
        List<RecordType> sports = [SELECT Id FROM RecordType 
                                   WHERE SObjectType = 'Account' 
                                   AND DeveloperName = 'Sports_Organization' LIMIT 1];
        if(!sports.isEmpty()) rtId = sports[0].Id;
    }

    Account club = new Account(
        Name = name,
        RecordTypeId = rtId
    );
    insert club;
    return club;
}

    // Test Club Membership
    public static Club_Membership__c testClubMembership(Id contactId, Id clubId, String role, String status) {
        Club_Membership__c cm = new Club_Membership__c(
            Contact__c = contactId,
            Club__c = clubId,
            Role__c = role,
            Status__c = status
        );
        insert cm;
        testDataMap.put('clubMembershipId_' + clubId, cm.Id);
        return cm;
    }

    // AA Availability
    public static AA_Availability__c testAAAvailability(Id aaProfileId, Id academicTermId, String availability) {
        AA_Availability__c avail = new AA_Availability__c(
            AA_Profile__c = aaProfileId,
            Academic_Term__c = academicTermId,
            Availability__c = availability
        );
        insert avail;
        testDataMap.put('aaAvailabilityId', avail.Id);
        return avail;
    }

    // AA Course Preference
    public static AA_Course_Preference__c testAACoursePreference(Id contactId, Id aaProfileId, Id termId, String status) {
        AA_Course_Preference__c pref = new AA_Course_Preference__c(
            AA_Contact__c = contactId,
            Academic_Associate__c = aaProfileId,
            Academic_Term__c = termId,
            Status__c = status
        );
        insert pref;
        testDataMap.put('aaCoursePreferenceId', pref.Id);
        return pref;
    }
    /* Commented out - Post_Body__c field does not exist in target org
     public static Student_Post__c createStudentPost(
        String status,
        Date expiryDate,
        Datetime publishedOn
    ) {
        Student_Post__c post = new Student_Post__c();
        post.Title__c = 'Test Post Title ' + System.now().getTime();
        post.Post_Body__c = 'Test post body';
        post.Status__c = status;
        post.Expiry_Date__c = expiryDate;
        post.Published_on__c = publishedOn;
        post.Reviewer_s_Comments__c = 'Approved';

        return post;
    }
    */
    // Course Offering Participant
    public static CourseOfferingParticipant testCourseOfferingParticipant(Id courseOfferingId, Id studentContactId) {
        CourseOfferingParticipant cop = new CourseOfferingParticipant(
            CourseOfferingId = courseOfferingId,
            ParticipantContactId = studentContactId,
            ParticipationStatus = 'Enrolled'
        );
        insert cop;
        testDataMap.put('courseOfferingParticipantId', cop.Id);
        return cop;
    }

    // NEW overloaded method
public static CourseOfferingParticipant testCourseOfferingParticipant(Id courseOfferingId, Id studentContactId, String status) {
    CourseOfferingParticipant cop = new CourseOfferingParticipant(
        CourseOfferingId = courseOfferingId,
        ParticipantContactId = studentContactId,
        ParticipationStatus = (String.isNotBlank(status) ? status : 'Enrolled')
    );
    insert cop;
    // We use the same map key so the factory stays consistent
    testDataMap.put('courseOfferingParticipantId', cop.Id); 
    return cop;
}

    // Helper to create Session Attendance records
    public static Session_Attendance__c testSessionAttendance(Id courseOfferingId, String sessionName) {
        Session_Attendance__c sa = new Session_Attendance__c(
            Name = sessionName,
            Course_Offering__c = courseOfferingId,
            Date__c = Date.today(),
            Time__c = '10:00 AM',
            Section__c = 'A'
            // Session_Key__c is a Formula, so we don't set it here.
            // Salesforce will calculate it automatically upon insert.
        );
        insert sa;
        testDataMap.put('sessionAttendanceId', sa.Id);
        return sa;
    }

    // Generic Account
    public static Account testAccount(String name) {
        Account a = new Account(Name = name);
        insert a;
        testDataMap.put('accountId', a.Id);
        return a;
    }

    // Contact with Account
    public static Contact testContact(Id accountId) {
        Id studentRTId = [SELECT Id FROM RecordType WHERE SObjectType='Contact' AND DeveloperName='Student' LIMIT 1].Id;
        String dynamicEmail = 'teststudentacct.' + Datetime.now().getTime() + '@example.com';
        Contact con = new Contact(
            FirstName = 'Test',
            LastName = 'StudentWithAccount',
            Email = dynamicEmail,
            AccountId = accountId,
            hed__Preferred_Email__c = 'VF Email ID',
            VF_Email_ID__c = dynamicEmail,
            RecordTypeId = studentRTId
        );
        insert con;
        testDataMap.put('contactWithAccountId', con.Id);
        return con;
    }

    // Portal User
    // public static User testPortalUser(Contact c, String profileName) {
    //      Profile p = [SELECT Id FROM Profile WHERE Name = :profileName LIMIT 1];
    //      String uniqueKey = String.valueOf(System.currentTimeMillis()) + String.valueOf(Math.abs(Crypto.getRandomInteger()));
    //      User u = new User(
    //         FirstName = 'Portal',
    //         LastName = 'User',
    //         Email = 'portaluser' + uniqueKey + '@test.com',
    //         Username = 'portaluser' + uniqueKey + '@test.com',
    //         Alias = 'puser',
    //         TimeZoneSidKey = 'America/Los_Angeles',
    //         LocaleSidKey = 'en_US',
    //         EmailEncodingKey = 'UTF-8',
    //         ProfileId = p.Id,
    //         LanguageLocaleKey = 'en_US',
    //         ContactId = c.Id
    //     );

    //     // ✅ SAFETY CHECK: Only attach Contact if NOT Standard User
    //     // Standard Users cannot have a ContactId.
    //     if (profileName != 'Standard User' && profileName != 'System Administrator') {
    //         u.ContactId = c.Id;
    //     }
    //     insert u;
    //     testDataMap.put('portalUserId', u.Id);
    //     return u;
    // }


public static User createInternalUserWithRole() {

    UserRole role = new UserRole(
        Name = 'Test Role',
        DeveloperName = 'Test_Role_' + System.currentTimeMillis()
    );
    insert role;

    Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

    User u = new User(
        FirstName = 'Internal',
        LastName = 'Owner',
        Email = 'internal' + System.currentTimeMillis() + '@test.com',
        Username = 'internal' + System.currentTimeMillis() + '@test.com',
        Alias = 'intusr',
        TimeZoneSidKey = 'America/Los_Angeles',
        LocaleSidKey = 'en_US',
        EmailEncodingKey = 'UTF-8',
        LanguageLocaleKey = 'en_US',
        ProfileId = p.Id,
        UserRoleId = role.Id
    );
    insert u;

    return u;
}

   public static User testPortalUser(Contact c, String profileName) {

    // Get profile (fallback to Standard User if not found)
    List<Profile> profiles = [
        SELECT Id, Name, UserType
        FROM Profile
        WHERE Name = :profileName
        LIMIT 1
    ];

    Profile p;
    if (!profiles.isEmpty()) {
        p = profiles[0];
    } else {
        // Try searching for a community profile first
        profiles = [SELECT Id, Name, UserType FROM Profile WHERE UserType IN ('PowerCustomerSuccess', 'CustomerCommunityPlus', 'CSPLiteUser') LIMIT 1];
        if (!profiles.isEmpty()) {
            p = profiles[0];
        } else {
            p = [SELECT Id, Name, UserType FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        }
    }

    String uniqueKey = String.valueOf(System.currentTimeMillis()) + String.valueOf(Math.abs(Crypto.getRandomInteger()));

    User u = new User(
        FirstName = 'Portal',
        LastName  = 'User',
        Email     = 'portaluser' + uniqueKey + '@test.com',
        Username  = 'portaluser' + uniqueKey + '@test.com',
        Alias     = 'puser',
        TimeZoneSidKey = 'America/Los_Angeles',
        LocaleSidKey   = 'en_US',
        EmailEncodingKey = 'UTF-8',
        LanguageLocaleKey = 'en_US',
        ProfileId = p.Id
    );

    // Attach Contact ONLY if the profile is not Standard
    // (Standard users cannot have ContactId)
    if (p.UserType != 'Standard') {
        u.ContactId = c.Id;
    }

    // ❌ DO NOT set UserRoleId here (causes role type mismatch for portal users)
    insert u;

    testDataMap.put('portalUserId', u.Id);
    return u;
}
    // User with Contact (for testing batch jobs that need User.ContactId)
    public static User testUserWithContact(Contact c) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String uniqueKey = String.valueOf(System.currentTimeMillis()) + String.valueOf(Math.abs(Crypto.getRandomInteger()));
        User u = new User(
            FirstName = 'Test',
            LastName = 'UserWithContact',
            Email = 'userwithcontact' + uniqueKey + '@test.com',
            Username = 'userwithcontact' + uniqueKey + '@test.com',
            Alias = 'uwc',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = p.Id,
            LanguageLocaleKey = 'en_US',
            ContactId = c.Id
        );
        insert u;
        testDataMap.put('userWithContactId', u.Id);
        return u;
    }

    // =========================================
    // NEW METHODS FOR ISB PAYMENT TESTING
    // =========================================

    // Test ISB Installment
    public static ISB_Installment__c testInstallment(Id contactId, Id programId, Id programEnrollmentId) {
        ISB_Installment__c inst = new ISB_Installment__c(
            Contact__c = contactId,
            Program__c = programId,
            Program_Enrollment__c = programEnrollmentId,
            Installment_Number__c = '1' ,
            Due_Date__c = Date.today().addDays(30),
            Actual_Amount__c = 1000,
            Pending_Amount__c = 1000,
            Is_Active__c = true
        );
        insert inst;
        testDataMap.put('installmentId', inst.Id);
        return inst;
    }

    // Test ISB Installment with parameters
    public static ISB_Installment__c testInstallment(
        Id contactId,
        Id programId,
        Id programEnrollmentId,
        Decimal actualAmount,
        Decimal pendingAmount,
        Integer installmentNumber
    ) {
        ISB_Installment__c inst = new ISB_Installment__c(
            Contact__c = contactId,
            Program__c = programId,
            Program_Enrollment__c = programEnrollmentId,
            Installment_Number__c = String.valueOf(installmentNumber),
            Due_Date__c = Date.today().addDays(30),
            Actual_Amount__c = actualAmount,
            Pending_Amount__c = pendingAmount,
            Is_Active__c = true
        );
        insert inst;
        testDataMap.put('installmentId_' + installmentNumber, inst.Id);
        return inst;
    }

    // Test ISB Payment
    public static ISB_Payment__c testPayment(Id installmentId, Id customerId) {
        ISB_Payment__c pay = new ISB_Payment__c(
            ISB_Installment__c = installmentId,
            Customer__c = customerId,
            Amount__c = 1000
        );
        insert pay;
        testDataMap.put('paymentId', pay.Id);
        return pay;
    }

    // Test ISB Payment with parameters
    public static ISB_Payment__c testPayment(Id installmentId, Id customerId, Decimal amount) {
        return testPayment(installmentId, customerId, amount, 'Installment 1');
    }

    // Test ISB Payment with type
    public static ISB_Payment__c testPayment(Id installmentId, Id customerId, Decimal amount, String paymentType) {
        ISB_Payment__c pay = new ISB_Payment__c(
            ISB_Installment__c = installmentId,
            Customer__c = customerId,
            Amount__c = amount,
            Payment_Type__c = paymentType
        );
        insert pay;
        testDataMap.put('paymentId_' + amount + '_' + paymentType, pay.Id);
        return pay;
    }

    // Create or get Email Template for Payment Success
    public static EmailTemplate getOrCreatePaymentSuccessTemplate() {
        List<EmailTemplate> existing = [SELECT Id FROM EmailTemplate WHERE DeveloperName = 'Payment_Success_Template' LIMIT 1];
        if (!existing.isEmpty()) {
            return existing[0];
        }

        // Get Public Email Folder
        List<Folder> folders = [SELECT Id FROM Folder WHERE Type = 'Email' AND AccessType = 'Public' LIMIT 1];
        if (folders.isEmpty()) {
            return null; // No public folder available
        }

        EmailTemplate template = new EmailTemplate(
            DeveloperName = 'Payment_Success_Template',
            Name = 'Payment Success Template',
            Subject = 'Payment Receipt',
            Body = 'Here is your receipt.',
            HtmlValue = '<p>Here is your receipt.</p>',
            FolderId = folders[0].Id,
            TemplateType = 'text',
            IsActive = true
        );
        insert template;
        testDataMap.put('emailTemplateId', template.Id);
        return template;
    }

    // Create or get Org-Wide Email Address
    public static OrgWideEmailAddress getOrCreateOrgWideEmail(String displayName, String emailAddress) {
        List<OrgWideEmailAddress> existing = [SELECT Id FROM OrgWideEmailAddress WHERE DisplayName = :displayName LIMIT 1];
        if (!existing.isEmpty()) {
            return existing[0];
        }

        // Note: In test context, we can't insert OrgWideEmailAddress directly
        // Return null if not found
        return null;
    }
    // =========================================
// REST & JSON UTILITIES FOR INTEGRATION TESTS
// =========================================

/**
 * Sets REST context for Apex REST test execution
 */
public static void setupRestContext(String requestBody) {
    RestRequest req = new RestRequest();
    RestResponse res = new RestResponse();

    req.requestUri = '/services/apexrest/v1/gradesync';
    req.httpMethod = 'POST';
    req.requestBody = Blob.valueOf(requestBody);

    RestContext.request = req;
    RestContext.response = res;
}

/**
 * Builds a valid Grade Sync API request map
 * Used for both insert & update scenarios
 */
public static Map<String, Object> buildGradeSyncRequest(
    String studentId,
    String courseOfferingExternalId
) {
    return new Map<String, Object>{
        'StudentId' => studentId,
        'CourseOfferingId' => courseOfferingExternalId,
        'Credits_Attempted' => 3,
        'Credits_Earned' => 3,
        'DurationUnit' => 'Credit Hours',
        'Grade_Letter' => 'A',
        'Marks_Percentage' => 95,
        'NumericGrade' => 9.5,
        'Retake_Taken' => false,
        'Source_System' => 'LMS',
        'UnitsEarned' => 3
    };
}

/**
 * Serializes list of request maps into JSON
 */
public static String toJson(List<Map<String, Object>> payload) {
    return JSON.serialize(payload);
}
// =========================================
// FAKE ID HELPER (NO DML)
// =========================================
public static Id fakeId(Schema.SObjectType sobjectType) {
    return (Id) getFakeId(sobjectType);
}


/**
     * @description Sets up the Razorpay Mock callout.
     * Usage: TestDataFactory.setRazorpayMock();
     */
    public static void setRazorpayMock() {
        Test.setMock(HttpCalloutMock.class, new RazorpayMockInner());
    }

    /**
     * @description Inner class to handle the HttpCalloutMock interface.
     */
    private class RazorpayMockInner implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            // We use 'UPI' (Uppercase) to match your recent test assertion requirements
            res.setBody('{"id":"pay_123", "method":"UPI", "status":"captured"}');
            res.setStatusCode(200);
            return res;
        }
    }


    public static AcademicTermEnrollment createAcademicTermEnrollment(Id termId, Id studentContactId, Id ownerId) {
    AcademicTermEnrollment ate = new AcademicTermEnrollment(
        AcademicTermId = termId,
        LearnerContactId = studentContactId,
        OwnerId = ownerId // Manually set ownership to bypass sharing
    );
    insert ate;
    return ate;
}


public static User createTestPortalUser(Contact con) {
    // 1. Get a guaranteed valid Profile
    Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
    
    String uniqueKey = System.currentTimeMillis() + String.valueOf(Math.abs(Crypto.getRandomInteger()));
    
    // 2. Initialize and set ProfileId IMMEDIATELY in the constructor
    User u = new User(
        FirstName = 'Portal',
        LastName = 'User',
        Email = 'test' + uniqueKey + '@example.com',
        Username = 'test' + uniqueKey + '@example.com',
        Alias = 'ptlusr',
        TimeZoneSidKey = 'America/Los_Angeles',
        LocaleSidKey = 'en_US',
        EmailEncodingKey = 'UTF-8',
        LanguageLocaleKey = 'en_US',
        ProfileId = p.Id // SET HERE - DO NOT SET VIA u.ProfileId = ... later
    );
    
    insert u;
    return u;
}

// Create ISB Installment Reminder Email Template
public static EmailTemplate getOrCreateInstallmentReminderTemplate() {
    List<EmailTemplate> existing = [
        SELECT Id 
        FROM EmailTemplate 
        WHERE DeveloperName = 'ISB_Installment_Reminder' 
        LIMIT 1
    ];
    
    if (!existing.isEmpty()) {
        return existing[0];
    }

    // Get Public Email Folder
    List<Folder> folders = [
        SELECT Id 
        FROM Folder 
        WHERE Type = 'Email' AND AccessType = 'Public' 
        LIMIT 1
    ];
    
    if (folders.isEmpty()) {
        return null; // No public folder available
    }

    EmailTemplate template = new EmailTemplate(
        DeveloperName = 'ISB_Installment_Reminder',
        Name = 'ISB Installment Reminder',
        Subject = 'Payment Reminder - Installment Due',
        Body = 'Dear {!Contact.Name}, your installment payment is due soon.',
        HtmlValue = '<p>Dear {!Contact.Name},</p><p>Your installment payment is due soon.</p>',
        FolderId = folders[0].Id,
        TemplateType = 'text',
        IsActive = true
    );
    insert template;
    testDataMap.put('installmentReminderTemplateId', template.Id);
    return template;
}
}