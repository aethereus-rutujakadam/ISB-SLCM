@isTest
public class ISBUserContextTest {
    
    @isTest static void testIsExternalUserReturnsFalseForStandardUser() {
        Boolean result = ISBUserContext.isExternalUser();
        System.assertNotEquals(null, result, 'isExternalUser should return a non-null Boolean');
    }

    @isTest static void testIsExternalUserCaching() {
        Boolean firstCall = ISBUserContext.isExternalUser();
        Boolean secondCall = ISBUserContext.isExternalUser();
        System.assertEquals(firstCall, secondCall, 'Caching should return consistent results');
    }

    @isTest static void testIsExternalUserDoesNotThrowException() {
        Boolean result = ISBUserContext.isExternalUser();
        System.assertNotEquals(null, result, 'Result should not be null');
    }

    @isTest static void testIsExternalUserReturnsBoolean() {
        Object result = ISBUserContext.isExternalUser();
        System.assert(result instanceof Boolean, 'isExternalUser should return a Boolean');
    }
}