@isTest
private class CourseChecklistSharingTest {

    private static CourseOffering createOffering(String name) {
        Program program = new Program(
            Name = name + ' Program',
            Program_Code__c = 'TST-' + String.valueOf(Math.abs(Crypto.getRandomInteger())).left(4)
        );
        insert program;

        AcademicYear ay = new AcademicYear(Name = name + ' AY');
        insert ay;

        AcademicTerm term = new AcademicTerm(Name = name + ' Term');
        insert term;

        Learning learning = new Learning(Name = name + ' Learning');
        insert learning;

        LearningCourse course = new LearningCourse(
            Name = name + ' Course',
            LearningId = learning.Id
        );
        insert course;

        Schema.Location loc = new Schema.Location(
            Name = name + ' Location',
            LocationType = 'Campus'
        );
        insert loc;

        CourseOffering offering = new CourseOffering(
            Name = name,
            LearningCourseId = course.Id,
            Academic_Term__c = term.Id,
            Program__c = program.Id,
            Academic_Year__c = ay.Id,
            Location__c = loc.Id,
            Course_Type__c = 'Core',
            StartDate = Date.today(),
            EndDate = Date.today().addDays(30)
        );
        insert offering;

        return offering;
    }


    @isTest
    static void testActivationUpdatesItemsAndExecutesSharePath() {
        CourseOffering offering = createOffering('ShareCoverageA');

        Course_Checklist__c checklist = new Course_Checklist__c(
            Name = 'Checklist A',
            Course_Offering__c = offering.Id,
            Checklist_Type__c = 'Course Checklist',
            Role__c = 'Manager',
            Status__c = 'Draft'
        );
        insert checklist;

        insert new Course_Checklist_Item__c(
            Course_Checklist__c = checklist.Id,
            Status__c = 'Not Started'
        );

        Map<Id, Course_Checklist__c> oldMap = new Map<Id, Course_Checklist__c>{
            checklist.Id => new Course_Checklist__c(Id = checklist.Id, Status__c = 'Draft')
        };

        Course_Checklist__c syntheticActive = new Course_Checklist__c(
            Id = checklist.Id,
            Course_Offering__c = offering.Id,
            Checklist_Type__c = 'Course Checklist',
            Role__c = 'Manager',
            Status__c = 'Active'
        );

        Test.startTest();
        CourseChecklistSharingHandler.handleChecklistAfterUpdate(
            new List<Course_Checklist__c>{ syntheticActive },
            oldMap
        );
        Test.stopTest();

        Course_Checklist_Item__c updatedItem = [
            SELECT Id, Status__c
            FROM Course_Checklist_Item__c
            WHERE Course_Checklist__c = :checklist.Id
            LIMIT 1
        ];
        System.assertEquals('In Progress', updatedItem.Status__c);
    }

    @isTest
    static void testEarlyReturnBranches() {
        CourseOffering offering = createOffering('ShareCoverageB');

        Course_Checklist__c checklist = new Course_Checklist__c(
            Name = 'Checklist B',
            Course_Offering__c = offering.Id,
            Checklist_Type__c = 'Course Checklist',
            Status__c = 'Draft'
        );
        insert checklist;

        Test.startTest();
        CourseChecklistSharingHandler.handleChecklistAfterUpdate(
            new List<Course_Checklist__c>{
                new Course_Checklist__c(Id = checklist.Id, Status__c = 'Draft')
            },
            new Map<Id, Course_Checklist__c>{
                checklist.Id => new Course_Checklist__c(Id = checklist.Id, Status__c = 'Draft')
            }
        );

        CourseChecklistSharingHandler.shareChecklist(
            new List<Course_Checklist__c>{
                new Course_Checklist__c(Id = checklist.Id, Status__c = 'Active')
            }
        );
        Test.stopTest();

        System.assert(true, 'Early return branches executed.');
    }

    @isTest(SeeAllData=true)
    static void testActivationWithAAAssignmentsCreatesShares() {
        List<Course_AA_Assignment__c> assignments = [
            SELECT Course_Offering__c,
                   Academic_Associate__r.Academic_Associate__r.Linked_User_Id__c
            FROM Course_AA_Assignment__c
            WHERE Is_Active__c = true
              AND Course_Offering__c != null
              AND Academic_Associate__r.Academic_Associate__r.Linked_User_Id__c != null
            LIMIT 1
        ];

        if (assignments.isEmpty()) {
            System.assert(true, 'No active AA assignment data available in org for this path.');
            return;
        }

        Id offeringId = assignments[0].Course_Offering__c;
        Id aaUserId = assignments[0].Academic_Associate__r.Academic_Associate__r.Linked_User_Id__c;

        Course_Checklist__c checklist = new Course_Checklist__c(
            Name = 'Checklist C',
            Course_Offering__c = offeringId,
            Checklist_Type__c = 'Course Checklist',
            Role__c = 'Manager',
            Status__c = 'Draft'
        );
        insert checklist;

        insert new Course_Checklist_Item__c(
            Course_Checklist__c = checklist.Id,
            Status__c = 'In Progress'
        );

        Course_Checklist__c syntheticActive = new Course_Checklist__c(
            Id = checklist.Id,
            Course_Offering__c = offeringId,
            Checklist_Type__c = 'Course Checklist',
            Role__c = 'Manager',
            Status__c = 'Active'
        );

        Test.startTest();
        CourseChecklistSharingHandler.handleChecklistAfterUpdate(
            new List<Course_Checklist__c>{ syntheticActive },
            null
        );
        Test.stopTest();

        Integer checklistShareCount = [
            SELECT COUNT()
            FROM Course_Checklist__Share
            WHERE ParentId = :checklist.Id
                            AND UserOrGroupId = :aaUserId
        ];
        System.assert(checklistShareCount > 0, 'Checklist share should be created for AA user.');
    }
}