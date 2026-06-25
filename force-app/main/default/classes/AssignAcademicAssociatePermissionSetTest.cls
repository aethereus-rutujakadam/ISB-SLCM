@isTest
public class AssignAcademicAssociatePermissionSetTest {

    @isTest
    static void testAssignPermissionSetSuccess() {
        // Setup User
        User u = TestDataFactory.testUser('testaa', 'testaa' + Datetime.now().getTime() + '@example.com');
        
        // Ensure Permission Set Group exists
        ensurePermissionSetGroupExists();
        
        // Prepare Input
        AssignAcademicAssociatePermissionSet.InputWrapper input = new AssignAcademicAssociatePermissionSet.InputWrapper();
        input.userId = u.Id;
        
        Test.startTest();
        AssignAcademicAssociatePermissionSet.assignPermissionSet(new List<AssignAcademicAssociatePermissionSet.InputWrapper>{input});
        Test.stopTest();
        
        // Verify Assignment
        String psgName = System.Label.Academic_Associate_Permission_Name;
        PermissionSetGroup psg = [SELECT Id FROM PermissionSetGroup WHERE DeveloperName = :psgName LIMIT 1];
        List<PermissionSetAssignment> assignments = [SELECT Id FROM PermissionSetAssignment WHERE AssigneeId = :u.Id AND PermissionSetGroupId = :psg.Id];
        System.assertEquals(1, assignments.size(), 'Permission Set Group should be assigned');
    }

    @isTest
    static void testAssignPermissionSetDuplicate() {
        // Setup User
        User u = TestDataFactory.testUser('testdup', 'testdup' + Datetime.now().getTime() + '@example.com');
        
        // Ensure Permission Set Group exists
        ensurePermissionSetGroupExists();
        String psgName = System.Label.Academic_Associate_Permission_Name;
        PermissionSetGroup psg = [SELECT Id FROM PermissionSetGroup WHERE DeveloperName = :psgName LIMIT 1];
        
        // Manually assign first
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetGroupId = psg.Id);
        
        // Prepare Input
        AssignAcademicAssociatePermissionSet.InputWrapper input = new AssignAcademicAssociatePermissionSet.InputWrapper();
        input.userId = u.Id;
        
        Test.startTest();
        AssignAcademicAssociatePermissionSet.assignPermissionSet(new List<AssignAcademicAssociatePermissionSet.InputWrapper>{input});
        Test.stopTest();
        
        // Verify still 1 assignment (no error)
        List<PermissionSetAssignment> assignments = [SELECT Id FROM PermissionSetAssignment WHERE AssigneeId = :u.Id AND PermissionSetGroupId = :psg.Id];
        System.assertEquals(1, assignments.size(), 'Should remain 1 assignment');
    }

    @isTest
    static void testAssignPermissionSetNullInput() {
        Test.startTest();
        AssignAcademicAssociatePermissionSet.assignPermissionSet(null);
        AssignAcademicAssociatePermissionSet.assignPermissionSet(new List<AssignAcademicAssociatePermissionSet.InputWrapper>());
        Test.stopTest();
        // Should not throw exception
    }
    
    @isTest
    static void testAssignPermissionSetNullUserId() {
         // Prepare Input with null Id
        AssignAcademicAssociatePermissionSet.InputWrapper input = new AssignAcademicAssociatePermissionSet.InputWrapper();
        input.userId = null;
        
        Test.startTest();
        AssignAcademicAssociatePermissionSet.assignPermissionSet(new List<AssignAcademicAssociatePermissionSet.InputWrapper>{input});
        Test.stopTest();
        // Should not throw exception
    }

    // Helper to ensure PSG exists
    private static void ensurePermissionSetGroupExists() {
        String psgName = System.Label.Academic_Associate_Permission_Name;
        List<PermissionSetGroup> psgList = [SELECT Id, Status FROM PermissionSetGroup WHERE DeveloperName = :psgName];
        if (psgList.isEmpty()) {
            PermissionSetGroup psg = new PermissionSetGroup(
                MasterLabel = 'Academic Associate Permission Set Group', 
                DeveloperName = psgName
            );
            insert psg;
            
            // In tests, sometimes a PSG needs a component to be valid for assignment
            PermissionSet ps = new PermissionSet(
                Label = 'Dummy PS for Test', 
                Name = 'Dummy_PS_for_Test'
            );
            insert ps;
            
            insert new PermissionSetGroupComponent(
                PermissionSetGroupId = psg.Id,
                PermissionSetId = ps.Id
            );
            
            Test.calculatePermissionSetGroup(psg.Id);
        } else if (psgList[0].Status != 'Updated') {
            Test.calculatePermissionSetGroup(psgList[0].Id);
        }
    }
}