public without sharing class ApprovalMatrixTxtQueueable implements Queueable {
    private Set<Id> contentDocumentIds;

    public ApprovalMatrixTxtQueueable(Set<Id> contentDocumentIds) {
        this.contentDocumentIds = contentDocumentIds;
    }

    public void execute(QueueableContext context) {
        ApprovalMatrixTxtService.processFiles(contentDocumentIds);
    }
}
