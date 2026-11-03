import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getRequest from '@salesforce/apex/ApprovalMatrixVerificationController.getRequest';
import approveSelected from '@salesforce/apex/ApprovalMatrixVerificationController.approveSelected';
import rejectRequest from '@salesforce/apex/ApprovalMatrixVerificationController.rejectRequest';

const COLUMNS = [
    { label: 'Line', fieldName: 'Name', initialWidth: 120 },
    { label: 'Product / Group', fieldName: 'productLabel', wrapText: true },
    { label: 'Raw TXT row', fieldName: 'Raw_Input__c', wrapText: true },
    { label: 'Mapped No Approval', fieldName: 'Mapped_No_Approval_Value__c', type: 'currency' },
    { label: 'Mapped RSM', fieldName: 'Mapped_RSM_Price_Value__c', type: 'currency' },
    { label: 'Mapped NSM', fieldName: 'Mapped_NSM_Price_Value__c', type: 'currency' },
    { label: 'Sales Discount', fieldName: 'Sales_Discount__c', type: 'number' },
    { label: 'Discount %', fieldName: 'Discount_Percentage__c', type: 'number' },
    { label: 'Discount Max', fieldName: 'Discount_Max__c', type: 'number' },
    { label: 'Above Policy %', fieldName: 'Above_Policy_Discount_Percentage__c', type: 'number' },
    { label: 'Approval Level', fieldName: 'Approval_Level__c', type: 'number' },
    { label: 'Approval Max', fieldName: 'Approval_Max__c', type: 'number' },
    { label: 'Approval > Max', fieldName: 'Approval_grt_max__c', type: 'number' },
    { label: 'Above Policy Level', fieldName: 'Above_Policy_Level__c', type: 'number' },
    { label: 'Matches', fieldName: 'Matched_Product_Count__c', type: 'number' },
    { label: 'Existing count', fieldName: 'Existing_Matrix_Count__c', type: 'number' },
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

export default class ApprovalMatrixVerification extends LightningElement {
    @api recordId;

    columns = COLUMNS;
    selectedLineIds = [];
    rejectionReason = '';
    wiredRequestResult;
    requestView;
    error;
    isSaving = false;

    @wire(getRequest, { requestId: '$recordId' })
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
            productLabel: line.Product_Code__c ||
                [line.Division__c, line.Category__c, line.Brand__c].filter(Boolean).join(' / '),
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
