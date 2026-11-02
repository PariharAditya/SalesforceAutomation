import { LightningElement, wire, track } from 'lwc';
import getAccounts from '@salesforce/apex/AccountController.getAccounts';
import createAccount from '@salesforce/apex/AccountController.createAccount';
import deleteAccount from '@salesforce/apex/AccountController.deleteAccount';
import updateAccount from '@salesforce/apex/AccountController.updateAccount';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';

export default class AccountList extends LightningElement {
    @track accounts;
    @track error;
    @track isLoading = false;

    // Create form fields
    accountName = '';
    accountIndustry = '';
    accountPhone = '';
    accountDescription = '';
    accountSite = '';

    // Edit form state
    @track editRecordId = null;
    @track editName = '';
    @track editIndustry = '';
    @track editPhone = '';
    @track editDescription = '';
    @track editSite = '';

    // Wire service to get accounts automatically
    @wire(getAccounts)
    wiredAccounts(result) {
        this.wiredAccountsResult = result;
        if (result.data) {
            this.accounts = result.data;
            this.error = undefined;
        } else if (result.error) {
            this.error = result.error;
            this.accounts = undefined;
            this.showToast('Error', 'Error loading accounts', 'error');
        }
    }

    // Handle input changes
    handleNameChange(event) {
        this.accountName = event.target.value;
    }

    handleIndustryChange(event) {
        this.accountIndustry = event.target.value;
    }

    handlePhoneChange(event) {
        this.accountPhone = event.target.value;
    }

    handleDescriptionChange(event) {
        this.accountDescription = event.target.value;
    }

    handleSiteChange(event) {
        this.accountSite = event.target.value;
    }

    // Create new account
    handleCreateAccount() {
        if (!this.accountName) {
            this.showToast('Error', 'Account name is required', 'error');
            return;
        }

        this.isLoading = true;

        createAccount({
            name: this.accountName,
            industry: this.accountIndustry,
            phone: this.accountPhone,
            description: this.accountDescription,
            site: this.accountSite
        })
            .then(result => {
                this.showToast('Success', 'Account created successfully', 'success');
                // Clear form
                this.accountName = '';
                this.accountIndustry = '';
                this.accountPhone = '';
                this.accountDescription = '';
                this.accountSite = '';
                // Refresh the account list
                return refreshApex(this.wiredAccountsResult);
            })
            .catch(error => {
                this.showToast('Error', error.body.message, 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // Delete account
    handleDeleteAccount(event) {
        const accountId = event.target.dataset.id;

        if (confirm('Are you sure you want to delete this account?')) {
            this.isLoading = true;

            deleteAccount({ accountId })
                .then(() => {
                    this.showToast('Success', 'Account deleted successfully', 'success');
                    return refreshApex(this.wiredAccountsResult);
                })
                .catch(error => {
                    this.showToast('Error', error.body?.message || 'Delete failed', 'error');
                })
                .finally(() => {
                    this.isLoading = false;
                });
        }
    }

    // Reactive flag updated per rendered row via data-current-id in template
    isEditingThisRow = false;

    // Update row-scoped flag on render; set true only for the card whose data-current-id matches editRecordId
    renderedCallback() {
        // Find the currently rendered card element and compute flag
        const current = this.template.querySelector('lightning-card[data-current-id]');
        if (current) {
            const currentId = current.dataset.currentId;
            this.isEditingThisRow = this.editRecordId === currentId;
        } else {
            this.isEditingThisRow = false;
        }
    }

    // Begin editing a specific row
    handleStartEdit(event) {
        const accountId = event.target.dataset.id;
        const record = this.accounts.find(a => a.Id === accountId);
        if (!record) {
            this.showToast('Error', 'Account not found in the current list', 'error');
            return;
        }
        this.editRecordId = accountId;
        this.editName = record.Name || '';
        this.editIndustry = record.Industry || '';
        this.editPhone = record.Phone || '';
        this.editDescription = record.Description || '';
        this.editSite = record.Site || '';
    }

    handleEditFieldChange(event) {
        const field = event.target.name;
        const value = event.target.value;
        if (field === 'editName') this.editName = value;
        if (field === 'editIndustry') this.editIndustry = value;
        if (field === 'editPhone') this.editPhone = value;
        if (field === 'editDescription') this.editDescription = value;
        if (field === 'editSite') this.editSite = value;
    }

    handleCancelEdit() {
        this.editRecordId = null;
        this.editName = '';
        this.editIndustry = '';
        this.editPhone = '';
        this.editDescription = '';
        this.editSite = '';
    }

    // Save updates for a specific account
    handleSaveEdit() {
        if (!this.editRecordId) {
            this.showToast('Error', 'No record selected for update', 'error');
            return;
        }
        // Basic validation example
        if (!this.editName) {
            this.showToast('Error', 'Name is required', 'error');
            return;
        }

        this.isLoading = true;
        updateAccount({
            accountId: this.editRecordId,
            name: this.editName,
            industry: this.editIndustry,
            phone: this.editPhone,
            description: this.editDescription,
            site: this.editSite
        })
            .then(() => {
                this.showToast('Success', 'Account updated successfully', 'success');
                this.handleCancelEdit();
                return refreshApex(this.wiredAccountsResult);
            })
            .catch(error => {
                this.showToast('Error', error.body?.message || 'Update failed', 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // Show toast notification
    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(event);
    }
}