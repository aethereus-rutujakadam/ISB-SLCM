public without sharing class ISBContactUserProvisioningBusinessQueue implements Queueable {

    private Map<Id, Id> createdUserIdByContactId;
    private Map<Id, Id> existingUserIdByContactId;
    private Set<Id> contactsToRevert;
    private Id activatedByUserId;

    public ISBContactUserProvisioningBusinessQueue(
        Map<Id, Id> createdUserIdByContactId,
        Map<Id, Id> existingUserIdByContactId,
        Set<Id> contactsToRevert,
        Id activatedByUserId
    ) {
        this.createdUserIdByContactId = createdUserIdByContactId;
        this.existingUserIdByContactId = existingUserIdByContactId;
        this.contactsToRevert = contactsToRevert;
        this.activatedByUserId = activatedByUserId;
    }

    public void execute(QueueableContext qc) {
        System.debug('--- ISBContactUserProvisioningBusinessQueue Started ---');
        System.debug('Existing Users to link: ' + existingUserIdByContactId.size());
        System.debug('Newly created Users to link: ' + createdUserIdByContactId.size());
        System.debug('Contacts to revert (Failed/Invalid data): ' + contactsToRevert.size());
        
        List<Contact> contactsToUpdate = new List<Contact>();

        for (Id contactId : existingUserIdByContactId.keySet()) {
            System.debug('Preparing to link existing User Id ' + existingUserIdByContactId.get(contactId) + ' to Contact ' + contactId);
            contactsToUpdate.add(new Contact(
                Id = contactId,
                Linked_User_Id__c = String.valueOf(existingUserIdByContactId.get(contactId))
            ));
        }

        for (Id contactId : createdUserIdByContactId.keySet()) {
            System.debug('Preparing to link newly created User Id ' + createdUserIdByContactId.get(contactId) + ' to Contact ' + contactId);
            contactsToUpdate.add(new Contact(
                Id = contactId,
                Linked_User_Id__c = String.valueOf(createdUserIdByContactId.get(contactId)),
                Activated_By__c = activatedByUserId,
                Activation_Date__c = System.now()
            ));
        }

        for (Id contactId : contactsToRevert) {
            System.debug('Preparing to revert Active Status to Inactive for Contact ' + contactId);
            contactsToUpdate.add(new Contact(
                Id = contactId,
                Active_Status__c = 'Inactive'
            ));
        }

        System.debug('Total Contact updates to commit: ' + contactsToUpdate.size());
        if (!contactsToUpdate.isEmpty()) {
            Database.SaveResult[] srList = Database.update(contactsToUpdate, false);
            for (Integer i = 0; i < srList.size(); i++) {
                if (srList[i].isSuccess()) {
                    System.debug('Successfully updated Contact ID: ' + contactsToUpdate[i].Id);
                } else {
                    System.debug('ERROR updating Contact ID: ' + contactsToUpdate[i].Id + ' - ' + srList[i].getErrors()[0].getMessage());
                }
            }
        }
        System.debug('--- ISBContactUserProvisioningBusinessQueue Completed ---');
    }
}