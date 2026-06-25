@IsTest
private class StudentDashboardControllerTest {

    @TestSetup
    static void setup() {
        // ============================================================
        // PRE-SETUP
        // ============================================================
        User roleUser = TestDataFactory.testUser('roleuser', 'role@test.com');
        UserRole r;
        try { r = [SELECT Id FROM UserRole LIMIT 1]; } 
        catch (Exception e) { r = new UserRole(Name='TestRole'); insert r; }
        roleUser.UserRoleId = r.Id;
        update roleUser;

        Contact student;
        Enrollment_Session__c es;
        ProgramEnrollment pe;
        AcademicSession session;
        AcademicTerm term;
        CourseOffering co;
        User portalUser; 

        // ============================================================
        // STEP 1: NON-SETUP DML (Run as Role User)
        // ============================================================
        System.runAs(roleUser) {
            Account acc = TestDataFactory.testAccount('Student Account');

            Id studentRTId = [SELECT Id FROM RecordType WHERE SObjectType='Contact' AND DeveloperName='Student' LIMIT 1].Id;
            String uniqueEmail = 'teststudent.' + Datetime.now().getTime() + '@example.com';
            student = new Contact(
                FirstName = 'Test',
                LastName = 'Student',
                Email = uniqueEmail,
                AccountId = acc.Id,
                RecordTypeId = studentRTId,
                hed__Preferred_Email__c = 'VF Email ID',
                VF_Email_ID__c = uniqueEmail
            );
            insert student;

            Program program = TestDataFactory.testProgram();
            pe = TestDataFactory.testProgramEnrollment(student, program);
            pe.CGPA__c = 3.75; 
            pe.Status = 'Registered';
            update pe;

            // Manually insert an Academic Probation case to block automated creation which fails due to Flow/Queue issues
            try {
                Id probationRtId = [SELECT Id FROM RecordType WHERE SObjectType='Case' AND DeveloperName='Academic_Probation' LIMIT 1].Id;
                insert new Case(
                    Subject = 'Blocker Case',
                    Status = 'New',
                    ContactId = student.Id,
                    RecordTypeId = probationRtId,
                    OwnerId = roleUser.Id, // Assign to User instead of Queue to satisfy Flow requirements
                    Program__c = program.Id
                );
            } catch(Exception e) {
                System.debug('Probation Case Blocker skipped: ' + e.getMessage());
            }

            term = TestDataFactory.testAcademicTerm(program.Id);
            session = new AcademicSession(
                Name = 'Fall 2025 Test',
                AcademicTermId = term.Id
            );
            insert session;

            es = TestDataFactory.createEnrollmentSession(
                pe.Id,
                session.Id,
                'Registered'
            );
            
            // Learning Data
            Learning lrn = TestDataFactory.testLearning();
            LearningCourse lc = TestDataFactory.testLearningCourse(lrn.Id);
            
            co = new CourseOffering(
                Name = 'Test Course Offering',
                IsActive = true,
                AcademicSessionId = session.Id,
                LearningCourseId = lc.Id,
                Academic_Term__c = term.Id
            );
            insert co;
            
            // Attendance (Set to 'Present' to avoid Flow Errors)
            TestDataFactory.createCourseAttendance(student.Id, co.Id, 'Present', Date.today(), es.Id, pe.Id);
            TestDataFactory.createCourseAttendance(student.Id, co.Id, 'Present', Date.today().addDays(-1), es.Id, pe.Id);
            TestDataFactory.createCourseAttendance(student.Id, co.Id, 'Absent', Date.today().addDays(-2), es.Id, pe.Id);
        }

        // ============================================================
        // STEP 2: SETUP DML (Create User Manually)
        // ============================================================
        System.runAs(new User(Id = UserInfo.getUserId())) {
            
            // 1. Get Profile
            Profile p = [SELECT Id FROM Profile WHERE Name = 'Customer Community Plus User' LIMIT 1];
            
            // 2. Create User MANUALLY to guarantee ContactId is set
            String uniqueKey = String.valueOf(System.currentTimeMillis());
            portalUser = new User(
                FirstName = 'Portal',
                LastName = 'User',
                Email = 'portaluser' + uniqueKey + '@test.com',
                Username = 'portaluser' + uniqueKey + '@test.com',
                Alias = 'puser',
                TimeZoneSidKey = 'America/Los_Angeles',
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                ProfileId = p.Id,
                LanguageLocaleKey = 'en_US',
                ContactId = student.Id // <--- EXPLICIT ASSIGNMENT
            );
            insert portalUser;
        }

        // ============================================================
        // STEP 3: NON-SETUP DML (Tasks/Cases)
        // ============================================================
        System.runAs(roleUser) { 
            insert new Task(
                Subject = 'Test Task',
                OwnerId = portalUser.Id,
                Status = 'Not Started',
                Priority = 'Normal'
            );
            
            Case c = TestDataFactory.testStudentCase(student, portalUser);
            c.OwnerId = portalUser.Id; 
            update c;
        }
    }

    @IsTest
    static void test_getStudentDashboardData_Success() {
        // Query user and explicitly verify ContactId before running
        List<User> portalUsers = [SELECT Id, ContactId FROM User WHERE Alias = 'puser' LIMIT 1];
        
        System.assert(!portalUsers.isEmpty(), 'Portal User was not found!');
        System.assert(portalUsers[0].ContactId != null, 'Portal User has no ContactId!');

        Test.startTest();
        System.runAs(portalUsers[0]) {
            Map<String, Object> data = StudentDashboardController.getStudentDashboardData();
            System.assertNotEquals(null, data);
            System.assert(data.containsKey('profile'));
            System.assert(data.containsKey('attendance'));
        }
        Test.stopTest();
    }

    @IsTest
    static void test_getDetailedAttendanceData_Success() {
        List<Contact> students = [SELECT Id FROM Contact WHERE FirstName = 'Test' AND LastName = 'Student' LIMIT 1];
        System.assert(!students.isEmpty(), 'Student Contact not found!');
        
        Test.startTest();
        Map<String, Object> data = StudentDashboardController.getDetailedAttendanceData(students[0].Id);
        System.assertNotEquals(null, data);
        
        Map<String, Object> summary = (Map<String, Object>)data.get('summary');
        System.assertEquals(3, summary.get('totalScheduled'));
        System.assertEquals(2, summary.get('totalAttended')); 
        Test.stopTest();
    }

    @IsTest
    static void test_getDetailedAttendanceData_AsUser() {
        List<User> portalUsers = [SELECT Id, ContactId FROM User WHERE Alias = 'puser' LIMIT 1];
        
        System.assert(!portalUsers.isEmpty(), 'Portal User not found!');
        System.assert(portalUsers[0].ContactId != null, 'Portal User has no ContactId!');

        Test.startTest();
        System.runAs(portalUsers[0]) {
            Map<String, Object> data = StudentDashboardController.getDetailedAttendanceData(null);
            System.assertNotEquals(null, data);
        }
        Test.stopTest();
    }
}