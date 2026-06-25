global class CreateAcademicAssociateContact implements Schedulable {
    global void execute(SchedulableContext sc) {
        Id recordTypeId = '012C4000000xt0eIAA';
        Contact c = new Contact(
            FirstName = 'Sumit',
            LastName = 'Goyal',
            RecordTypeId = recordTypeId
        );
        insert c;
        // Abort after first run
        System.abortJob(sc.getTriggerId());
    }
}