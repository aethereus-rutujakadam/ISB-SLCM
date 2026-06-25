/**
 * RegistroPushBatchScheduler
 * ISB-6087 / ISB-6138 — Scheduler for outbound Registro student data sync.
 *
 * To schedule: System.schedule('Registro Push - Daily', '0 0 2 * * ?', new RegistroPushBatchScheduler());
 * Or deploy via Setup > Apex Scheduler.
 */
global class RegistroPushBatchScheduler implements Schedulable {
    global void execute(SchedulableContext sc) {
        Database.executeBatch(new RegistroPushBatch(), 10);
    }
}
