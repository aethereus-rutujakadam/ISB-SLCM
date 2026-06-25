/**
 * Synchronizes Advisor User.IsActive values with linked Advisor Contact Active_Status__c changes.
 */
public without sharing class AdvisorUserStatusSyncQueue implements Queueable {

    private Map<Id, Boolean> desiredIsActiveByUserId;

    /**
     * @param desiredIsActiveByUserId map of User Id to desired IsActive value.
     */
    public AdvisorUserStatusSyncQueue(Map<Id, Boolean> desiredIsActiveByUserId) {
        this.desiredIsActiveByUserId =
            desiredIsActiveByUserId == null ? new Map<Id, Boolean>() : desiredIsActiveByUserId;
    }

    /**
     * Executes user activation/deactivation updates in async context to avoid mixed DML from Contact trigger.
     */
    public void execute(QueueableContext qc) {
        System.debug('--- AdvisorUserStatusSyncQueue Started ---');
        if (desiredIsActiveByUserId.isEmpty()) {
            System.debug('No linked users to sync. Exiting.');
            return;
        }

        List<User> usersToUpdate = buildUsersToUpdate();

        System.debug('Users requiring status update: ' + usersToUpdate.size());
        if (!usersToUpdate.isEmpty()) {
            Database.SaveResult[] srList = Database.update(usersToUpdate, false);
            logSaveResults(srList, usersToUpdate);
        }

        System.debug('--- AdvisorUserStatusSyncQueue Completed ---');
    }

    private List<User> buildUsersToUpdate() {
        List<User> usersToUpdate = new List<User>();
        for (User u : [
            SELECT Id, IsActive
            FROM User
            WHERE Id IN :desiredIsActiveByUserId.keySet()
        ]) {
            Boolean desiredIsActive = desiredIsActiveByUserId.get(u.Id);
            if (desiredIsActive == null || u.IsActive == desiredIsActive) {
                continue;
            }

            usersToUpdate.add(new User(
                Id = u.Id,
                IsActive = desiredIsActive
            ));
        }
        return usersToUpdate;
    }

    private void logSaveResults(Database.SaveResult[] srList, List<User> usersToUpdate) {
        for (Integer i = 0; i < srList.size(); i++) {
            if (srList[i].isSuccess()) {
                System.debug('Updated User status: ' + usersToUpdate[i].Id + ' => IsActive=' + usersToUpdate[i].IsActive);
                continue;
            }

            for (Database.Error err : srList[i].getErrors()) {
                System.debug('Failed to update User ' + usersToUpdate[i].Id + ': ' + err.getMessage());
            }
        }
    }
}