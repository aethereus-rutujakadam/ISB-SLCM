/**
 * RegistroPushBatch
 * ISB-6087 / ISB-6138 — Scheduled outbound sync of Incoming Exchange student data to Registro.
 *
 * OI-06 NOTE: Registro API authentication spec is pending. Update endpoint URL, auth header,
 * and payload structure once OI-06 is resolved.
 *
 * Idempotency: PE records with Registro_Sync_Status__c = 'Not Synced' or 'Failed' are queried.
 * After each attempt the status is updated to 'Synced' or 'Failed'.
 */
public class RegistroPushBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful {

    // OI-06: Replace with actual Registro endpoint + auth header
    private static final String REGISTRO_API_ENDPOINT = 'callout:Registro_Named_Credential/api/v1/incoming-students';

    private Integer successCount = 0;
    private Integer failureCount = 0;

    // ── Batchable interface ───────────────────────────────────────────────

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id,
                   PGID__c,
                   Status,
                   Sub_Status__c,
                   Registro_Sync_Status__c,
                   Registro_Last_Synced__c,
                   Contact.FirstName,
                   Contact.LastName,
                   Contact.Email,
                   Contact.Exchange_Type__c,
                   ProgramId,
                   Program.Name
            FROM   ProgramEnrollment
            WHERE  Sub_Status__c = 'Incoming Exchange'
              AND  (Registro_Sync_Status__c = 'Not Synced' OR Registro_Sync_Status__c = 'Failed')
              AND  PGID__c != null
        ]);
    }

    public void execute(Database.BatchableContext bc, List<ProgramEnrollment> scope) {
        List<ProgramEnrollment> toUpdate = new List<ProgramEnrollment>();

        for (ProgramEnrollment pe : scope) {
            String payload = buildPayload(pe);
            Boolean syncedOk = callRegistroAPI(pe.Id, payload);

            toUpdate.add(new ProgramEnrollment(
                Id                      = pe.Id,
                Registro_Sync_Status__c = syncedOk ? 'Synced' : 'Failed',
                Registro_Last_Synced__c = Datetime.now()
            ));

            if (syncedOk) successCount++;
            else          failureCount++;
        }

        if (!toUpdate.isEmpty()) {
            Database.update(toUpdate, false);
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug(LoggingLevel.INFO,
            'RegistroPushBatch complete. Success: ' + successCount + ', Failed: ' + failureCount);
        // TODO (OI-09): Send summary notification email to system admin when failures > 0
    }

    // ── Helpers ───────────────────────────────────────────────────────────

    private String buildPayload(ProgramEnrollment pe) {
        Map<String, Object> payload = new Map<String, Object>{
            'pgid'        => pe.PGID__c,
            'firstName'   => pe.Contact.FirstName,
            'lastName'    => pe.Contact.LastName,
            'email'       => pe.Contact.Email,
            'exchangeType'=> 'Incoming',
            'programName' => pe.Program != null ? pe.Program.Name : null,
            'status'      => String.valueOf(pe.Status),
            'subStatus'   => pe.Sub_Status__c,
            'syncedAt'    => String.valueOf(Datetime.now())
        };
        return JSON.serialize(payload);
    }

    private Boolean callRegistroAPI(Id peId, String jsonBody) {
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(REGISTRO_API_ENDPOINT);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('Accept', 'application/json');
            // OI-06: Add authentication header here, e.g.:
            // req.setHeader('Authorization', 'Bearer ' + getRegistroToken());
            req.setBody(jsonBody);
            req.setTimeout(30000);

            Http http     = new Http();
            HttpResponse res = http.send(req);

            if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
                return true;
            } else {
                System.debug(LoggingLevel.WARN,
                    'RegistroPushBatch API error for PE ' + peId
                    + ': HTTP ' + res.getStatusCode() + ' — ' + res.getBody());
                return false;
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'RegistroPushBatch callout exception for PE ' + peId + ': ' + e.getMessage());
            return false;
        }
    }
}
