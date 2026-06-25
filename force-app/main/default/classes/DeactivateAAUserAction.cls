public without sharing class DeactivateAAUserAction {

    // ---------- WRAPPER CLASSES ----------
    public class Request {
        @InvocableVariable(required=true)
        public Id contactId;   // Each element contains a Contact Id
    }

    public class Response {
        @InvocableVariable
        public String resultMessage;

        @InvocableVariable
        public Boolean success;
    }

    // ---------- INVOCABLE METHOD ----------
    @InvocableMethod(label='Deactivate and Freeze User')
    public static List<Response> deactivateUsers(List<Request> requests) {

        List<Response> output = new List<Response>();

        try {
            // Collect Contact IDs from the flow
            Set<Id> contactIds = new Set<Id>();
            for (Request req : requests) {
                if (req.contactId != null) {
                    contactIds.add(req.contactId);
                }
            }

            if (contactIds.isEmpty()) {
                Response r = new Response();
                r.success = false;
                r.resultMessage = 'No Contact IDs received from Flow.';
                output.add(r);
                return output;
            }

            // Query the contacts + linked user
            List<Contact> contactsWithUser = [
                SELECT Id, Linked_User_Id__c
                FROM Contact
                WHERE Id IN :contactIds
                AND Linked_User_Id__c != null
            ];

            if (contactsWithUser.isEmpty()) {
                Response r = new Response();
                r.success = false;
                r.resultMessage = 'No linked User IDs found for the provided Contacts.';
                output.add(r);
                return output;
            }

            // Collect User IDs
            List<Id> userIds = new List<Id>();
            for (Contact c : contactsWithUser) {
                userIds.add(c.Linked_User_Id__c);
            }

            // Call async method
            deactivateUserAsync(userIds);

            Response r = new Response();
            r.success = true;
            r.resultMessage = 'Deactivation started successfully for ' + userIds.size() + ' user(s).';
            output.add(r);
        }
        catch (Exception ex) {
            Response r = new Response();
            r.success = false;
            r.resultMessage = 'Error: ' + ex.getMessage();
            output.add(r);
        }

        return output;
    }

    // ---------- FUTURE METHOD ----------
    @future
    private static void deactivateUserAsync(List<Id> userIds) {
        try {
            List<User> usersToDeactivate = [
                SELECT Id, IsActive
                FROM User
                WHERE Id IN :userIds
            ];

            for (User u : usersToDeactivate) {
                u.IsActive = false;
            }

            update usersToDeactivate;
        }
        catch (Exception e) {
            // Cannot return errors from @future, so log them
            System.debug('Error deactivating users: ' + e.getMessage());
        }
    }
}