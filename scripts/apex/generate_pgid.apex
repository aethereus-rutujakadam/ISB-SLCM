List<ProgramEnrollment> peList = [SELECT Id, PGID__c FROM ProgramEnrollment WHERE Id = '11X72000000f6cXEAQ'];
PGIDGeneratorService.generatePGIDs(peList);
