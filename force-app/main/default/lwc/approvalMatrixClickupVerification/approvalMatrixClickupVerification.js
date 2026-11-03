import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getClickUpRequest from '@salesforce/apex/ApprovalMatrixVerificationController.getClickUpRequest';
import approveSelected from '@salesforce/apex/ApprovalMatrixVerificationController.approveSelected';
import rejectRequest from '@salesforce/apex/ApprovalMatrixVerificationController.rejectRequest';

const COLUMNS = [
    { label: 'Line', fieldName: 'Name', initialWidth: 120 },
    { label: 'Item', fieldName: 'Product_Code__c' },
    { label: 'GM', fieldName: 'GM__c', type: 'number' },
    { label: 'AGM', fieldName: 'AGM__c', type: 'number' },
    { label: 'RM', fieldName: 'RM__c', type: 'number' },
    { label: 'Raw ClickUp row', fieldName: 'Raw_Input__c', wrapText: true },
    { label: 'Product matches', fieldName: 'Matched_Product_Count__c', type: 'number' },
    { label: 'Existing matrix count', fieldName: 'Existing_Matrix_Count__c', type: 'number' },
    { label: 'Existing matrix values', fieldName: 'Existing_Matrix_Summary__c', wrapText: true },
    {
        label: 'Status',
        fieldName: 'Line_Status__c',
        cellAttributes: { class: { fieldName: 'statusClass' } }
    },
    {
        label: 'Error',
        fieldName: 'Error_Message__c',
        wrapText: true,
        cellAttributes: { class: { fieldName: 'errorClass' } }
    },
    {
        label: 'Warning',
        fieldName: 'Warnings__c',
        wrapText: true,
        cellAttributes: { class: { fieldName: 'warningClass' } }
    }
];

export default class ApprovalMatrixClickupVerification extends LightningElement {
    @api recordId;

    columns = COLUMNS;
    selectedLineIds = [];
    rejectionReason = '';
    wiredRequestResult;
    requestView;
    error;
    isSaving = false;

    @wire(getClickUpRequest, { requestId: '$recordId' })
    wiredRequest(result) {
        this.wiredRequestResult = result;
        if (result.data) {
            this.requestView = result.data;
            this.error = undefined;
        } else if (result.error) {
            this.error = this.reduceError(result.error);
            this.requestView = undefined;
        }
    }

    get rows() {
        return (this.requestView?.lines || []).map((line) => ({
            ...line,
            statusClass: line.Line_Status__c === 'Error' ? 'slds-text-color_error' : '',
            errorClass: line.Error_Message__c ? 'slds-text-color_error' : '',
            warningClass: line.Warnings__c ? 'slds-text-color_warning' : ''
        }));
    }

    get disabledRowIds() {
        return this.rows
            .filter((line) => line.Line_Status__c !== 'Valid')
            .map((line) => line.Id);
    }

    get hasValidRows() {
        return this.rows.some((line) => line.Line_Status__c === 'Valid');
    }

    get canVerify() {
        const status = this.requestView?.requestRecord?.Status__c;
        return status === 'Pending Verification' || status === 'Validation Error' ||
            status === 'Error';
    }

    get approvalDisabled() {
        return this.isSaving || !this.canVerify || !this.hasValidRows;
    }

    get rejectDisabled() {
        return this.isSaving || !this.canVerify || !this.rejectionReason.trim();
    }

    handleSelection(event) {
        this.selectedLineIds = event.detail.selectedRows
            .filter((row) => row.Line_Status__c === 'Valid')
            .map((row) => row.Id);
    }

    handleReasonChange(event) {
        this.rejectionReason = event.detail.value;
    }

    async handleApproveSelected() {
        await this.approve(this.selectedLineIds);
    }

    async handleApproveAll() {
        const validIds = this.rows
            .filter((line) => line.Line_Status__c === 'Valid')
            .map((line) => line.Id);
        await this.approve(validIds);
    }

    async approve(lineIds) {
        if (!lineIds.length) {
            this.showToast('Select at least one valid line.', 'No lines selected', 'warning');
            return;
        }
        this.isSaving = true;
        try {
            await approveSelected({ requestId: this.recordId, selectedLineIds: lineIds });
            this.showToast('Selected lines were processed.', 'Approval complete', 'success');
            this.selectedLineIds = [];
            await refreshApex(this.wiredRequestResult);
            this.dispatchEvent(new CustomEvent('requestupdated'));
        } catch (error) {
            this.showToast(this.reduceError(error), 'Could not approve request', 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async handleReject() {
        this.isSaving = true;
        try {
            await rejectRequest({
                requestId: this.recordId,
                reason: this.rejectionReason
            });
            this.showToast('The request was rejected.', 'Request rejected', 'success');
            this.rejectionReason = '';
            await refreshApex(this.wiredRequestResult);
            this.dispatchEvent(new CustomEvent('requestupdated'));
        } catch (error) {
            this.showToast(this.reduceError(error), 'Could not reject request', 'error');
        } finally {
            this.isSaving = false;
        }
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
