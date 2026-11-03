import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getClickUpRequests from '@salesforce/apex/ApprovalMatrixVerificationController.getClickUpRequests';
import getClickUpSyncStatus from '@salesforce/apex/ApprovalMatrixVerificationController.getClickUpSyncStatus';
import syncClickUpNow from '@salesforce/apex/ApprovalMatrixVerificationController.syncClickUpNow';

const COLUMNS = [
    { label: 'Request', fieldName: 'Name' },
    { label: 'ClickUp Task Id', fieldName: 'ClickUp_Task_Id__c' },
    {
        label: 'ClickUp task',
        fieldName: 'ClickUp_Task_Url__c',
        type: 'url',
        typeAttributes: {
            label: { fieldName: 'ClickUp_Task_Id__c' },
            target: '_blank'
        }
    },
    { label: 'Status', fieldName: 'Status__c' },
    { label: 'Lines', fieldName: 'Line_Count__c', type: 'number' },
    { label: 'Errors', fieldName: 'Error_Count__c', type: 'number' },
    { label: 'Processing issue', fieldName: 'Processing_Error__c', wrapText: true }
];

export default class ApprovalMatrixClickupWorkbench extends LightningElement {
    columns = COLUMNS;
    selectedRequestId;
    wiredRequests;
    wiredSyncStatus;
    requests = [];
    syncStatus;
    error;
    isSaving = false;

    @wire(getClickUpRequests)
    wiredRequestList(result) {
        this.wiredRequests = result;
        if (result.data) {
            this.requests = result.data;
            this.error = undefined;
        } else if (result.error) {
            this.requests = [];
            this.error = this.reduceError(result.error);
        }
    }

    @wire(getClickUpSyncStatus)
    wiredSyncStatusResult(result) {
        this.wiredSyncStatus = result;
        if (result.data) {
            this.syncStatus = result.data;
        } else if (result.error) {
            this.error = this.reduceError(result.error);
        }
    }

    handleSelection(event) {
        const selected = event.detail.selectedRows;
        this.selectedRequestId = selected.length ? selected[0].Id : undefined;
    }

    async handleRefresh() {
        this.isSaving = true;
        try {
            await refreshApex(this.wiredRequests);
            await refreshApex(this.wiredSyncStatus);
        } catch (error) {
            this.showToast(this.reduceError(error), 'Could not refresh requests', 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async handleSync() {
        this.isSaving = true;
        try {
            const jobId = await syncClickUpNow();
            this.showToast(
                `ClickUp sync queued (${jobId}). Refresh shortly to see new requests.`,
                'Sync started',
                'success'
            );
        } catch (error) {
            this.showToast(this.reduceError(error), 'Could not start ClickUp sync', 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async handleRequestUpdated() {
        await this.handleRefresh();
    }

    get hasSelection() {
        return Boolean(this.selectedRequestId);
    }

    showToast(message, title, variant) {
        this.dispatchEvent(new ShowToastEvent({ message, title, variant }));
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.body?.message || error?.message || 'An unexpected error occurred.';
    }
}
