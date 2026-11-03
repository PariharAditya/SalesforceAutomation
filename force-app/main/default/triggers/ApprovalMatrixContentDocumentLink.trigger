trigger ApprovalMatrixContentDocumentLink on ContentDocumentLink (after insert) {
    Set<Id> candidateDocumentIds = new Set<Id>();
    for (ContentDocumentLink link : Trigger.new) {
        if (link.LinkedEntityId != null &&
            link.LinkedEntityId.getSObjectType() == Approval_Matrix_Request__c.SObjectType) {
            candidateDocumentIds.add(link.ContentDocumentId);
        }
    }

    if (candidateDocumentIds.isEmpty()) {
        return;
    }

    if (!candidateDocumentIds.isEmpty()) {
        System.enqueueJob(new ApprovalMatrixTxtQueueable(candidateDocumentIds));
    }
}
