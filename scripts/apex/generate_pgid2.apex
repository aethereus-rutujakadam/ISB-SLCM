String peId = '11X72000000f6cXEAQ';
ProgramEnrollment pe = [SELECT Id, PGID__c, ContactId FROM ProgramEnrollment WHERE Id = :peId LIMIT 1];

pe.PGID__c = null;
update pe;

Contact c = new Contact(Id = pe.ContactId, New_Admit_Email__c = null);
update c;

System.debug('--- CLEARED OLD VALUES ---');

List<ProgramEnrollment> pes = [
    SELECT Id, PGID__c
    FROM ProgramEnrollment WHERE Id = :peId
];

PGIDGeneratorService.generatePGIDs(pes);

ProgramEnrollment updatedPe = [SELECT Id, PGID__c, Contact.New_Admit_Email__c FROM ProgramEnrollment WHERE Id = :peId LIMIT 1];
System.debug('--- NEW PGID ---');
System.debug(updatedPe.PGID__c);
System.debug('--- NEW EMAIL ---');
System.debug(updatedPe.Contact.New_Admit_Email__c);
