public class AwardAutoNumberHandler {

    public static void handleEvents(List<Award> newRecords, Boolean isBefore, Boolean isAfter) {

        if (isBefore) {
            handleBeforeInsert(newRecords);
        }

        if (isAfter) {
            handleAfterInsert(newRecords);
        }
    }

    // ===============================================
    // BEFORE INSERT – AUTO NUMBER LOGIC
    // ===============================================
  private static void handleBeforeInsert(List<Award> newRecords) {
    Award_Counter__c counter;

    // Fetch the existing counter record
    List<Award_Counter__c> counterList = [
        SELECT Id, Last_Number__c FROM Award_Counter__c LIMIT 1
    ];

    if (counterList.isEmpty()) {
        counter = new Award_Counter__c(Last_Number__c = 0);
        insert counter;     // New counter created
    } else {
        counter = counterList[0];   // Use existing counter
    }

    if (counter.Last_Number__c == null) {
        counter.Last_Number__c = 0;
    }

    Integer nextNumber = Integer.valueOf(counter.Last_Number__c);

    for (Award a : newRecords) {
        if (String.isBlank(a.Name)) {
            nextNumber++;
            a.Name = 'Awd-' + String.valueOf(nextNumber).leftPad(3, '0');
        }
    }

    counter.Last_Number__c = nextNumber;

    try {
        update counter;
    } catch (Exception ex) {
        System.debug('ERROR while updating Award Counter: ' + ex.getMessage());
        throw new DmlException('Failed to update Award Counter: ' + ex.getMessage());
    }
}
    // ===============================================
    // AFTER INSERT – APPROVAL CALL
    // ===============================================
    private static void handleAfterInsert(List<Award> newRecords) {

        for (Award aw : newRecords) {
            try {
                Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
                req.setComments('Approval Request Submitted Automatically');
                req.setObjectId(aw.Id);
                req.setSubmitterId(aw.OwnerId);

                // Approval API Name
                req.setProcessDefinitionNameOrId('Award_Approval_for_Academic_and_Leader');

                // Optional depending on process criteria
                req.setSkipEntryCriteria(true);

                if (!Test.isRunningTest()) {
                    Approval.ProcessResult result = Approval.process(req);
                    System.debug('Approval Started for Award: ' + aw.Id + ' RESULT=' + result);
                }

            } catch (Exception e) {
                System.debug('Error submitting award approval for ID: ' + aw.Id + ' | Error: ' + e.getMessage());
                throw e;
            }
        }
    }
}