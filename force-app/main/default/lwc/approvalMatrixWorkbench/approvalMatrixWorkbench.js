import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getRequests from '@salesforce/apex/ApprovalMatrixVerificationController.getRequests';
import REQUEST_OBJECT from '@salesforce/schema/Approval_Matrix_Request__c';
import TASK_ID_FIELD from '@salesforce/schema/Approval_Matrix_Request__c.ClickUp_Task_Id__c';

const COLUMNS = [
    { label: 'Request', fieldName: 'Name' },
    { label: 'ClickUp Task Id', fieldName: 'ClickUp_Task_Id__c' },
    { label: 'Type', fieldName: 'Record_Type__c' },
    { label: 'Status', fieldName: 'Status__c' },
    { label: 'Lines', fieldName: 'Line_Count__c', type: 'number' },
    { label: 'Errors', fieldName: 'Error_Count__c', type: 'number' },
    { label: 'Processing issue', fieldName: 'Processing_Error__c', wrapText: true }
];

export default class ApprovalMatrixWorkbench extends LightningElement {
    requestObject = REQUEST_OBJECT;
    taskIdField = TASK_ID_FIELD;
    columns = COLUMNS;
    acceptedFormats = ['.txt'];
    selectedRequestId;
    uploadRequestId;
    wiredRequests;
    requests = [];
    error;
    isSaving = false;

    @wire(getRequests)
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

    handleRequestCreated(event) {
        this.uploadRequestId = event.detail.id;
        this.selectedRequestId = event.detail.id;
        this.showToast(
            'Request created. Attach its TXT file below to start parsing.',
            'Request ready',
            'success'
        );
        refreshApex(this.wiredRequests);
    }

    handleRequestCreateError(event) {
        this.showToast(this.reduceError(event.detail), 'Could not create request', 'error');
    }

    handleSelection(event) {
        const selected = event.detail.selectedRows;
        this.selectedRequestId = selected.length ? selected[0].Id : undefined;
        this.uploadRequestId = this.selectedRequestId;
    }

    handleUploadFinished() {
        this.showToast('TXT file uploaded. Parsing will run automatically.', 'File received', 'success');
        refreshApex(this.wiredRequests);
    }

    handleUploadError(event) {
        this.showToast(this.reduceError(event.detail), 'Could not upload TXT file', 'error');
    }

    async handleRefresh() {
        this.isSaving = true;
        try {
            await refreshApex(this.wiredRequests);
        } catch (error) {
            this.showToast(this.reduceError(error), 'Could not refresh requests', 'error');
        } finally {
            this.isSaving = false;
        }
    }

    get selectedRequestLabel() {
        return this.requests.find((request) => request.Id === this.uploadRequestId)?.Name || '';
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
