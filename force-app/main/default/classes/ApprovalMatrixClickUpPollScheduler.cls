public without sharing class ApprovalMatrixClickUpPollScheduler implements Schedulable {
    public void execute(SchedulableContext context) {
        System.enqueueJob(new ApprovalMatrixClickUpSyncQueueable());
    }
}
