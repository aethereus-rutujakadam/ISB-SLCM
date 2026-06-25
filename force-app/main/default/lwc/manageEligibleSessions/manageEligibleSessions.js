import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { getRecord } from 'lightning/uiRecordApi';
import getEligibleSessionsData from '@salesforce/apex/ManageEligibleSessionsController.getEligibleSessionsData';
import createEligibleTerms from '@salesforce/apex/ManageEligibleSessionsController.createEligibleTerms';

const FIELDS = ['ISB_Fees_Master__c.Id'];

export default class ManageEligibleSessions extends LightningElement {
    @api recordId;
    
    @track academicTermName;
    @track uniqueSessions = [];
    @track selectedSessionIds = [];
    @track isLoading = true;
    @track hasError = false;
    @track errorMessage = '';
    @track existingTerms = [];
    @track existingRecordCount = 0;
    @track showExistingWarning = false;

    @wire(getEligibleSessionsData, { feesMasterId: '$recordId' })
    wiredSessionsData({ error, data }) {
        this.isLoading = true;
        if (data) {
            try {
                this.academicTermName = data.academicTermName;
                this.uniqueSessions = this.deduplicateSessions(data.sessions);
                this.existingTerms = data.existingTerms || [];
                this.existingRecordCount = this.existingTerms.length;
                this.showExistingWarning = this.existingRecordCount > 0;
                
                // Pre-select sessions that already have eligible terms
                const existingSessionIds = data.existingSessionIds || [];
                if (existingSessionIds.length > 0) {
                    this.uniqueSessions = this.uniqueSessions.map(session => {
                        if (existingSessionIds.includes(session.id)) {
                            session.selected = true;
                        }
                        return session;
                    });
                }
                
                this.isLoading = false;
                this.hasError = false;
            } catch (err) {
                this.handleError('Error processing session data', err);
            }
        } else if (error) {
            this.handleError('Error loading sessions', error);
        }
    }

    deduplicateSessions(sessions) {
        const sessionMap = new Map();
        sessions.forEach(session => {
            // Keep only first occurrence of each name
            if (!sessionMap.has(session.Name)) {
                sessionMap.set(session.Name, {
                    id: session.Id,
                    name: session.Name,
                    selected: false,
                    location: session.Location__c || ''
                });
            }
        });
        return Array.from(sessionMap.values()).sort((a, b) => a.name.localeCompare(b.name));
    }

    handleSessionSelect(event) {
        const sessionId = event.currentTarget.dataset.id;
        const session = this.uniqueSessions.find(s => s.id === sessionId);
        if (session) {
            session.selected = !session.selected;
            // Force reactivity
            this.uniqueSessions = [...this.uniqueSessions];
        }
    }

    handleSave() {
        this.selectedSessionIds = this.uniqueSessions
            .filter(s => s.selected)
            .map(s => s.id);

        if (this.selectedSessionIds.length === 0) {
            this.showToast('Warning', 'Please select at least one academic session', 'warning');
            return;
        }

        this.isLoading = true;
        createEligibleTerms({
            feesMasterId: this.recordId,
            sessionIds: this.selectedSessionIds
        })
        .then(() => {
            this.showToast('Success', 'Eligible Academic Sessions have been successfully configured', 'success');
            this.isLoading = false;
            
            // Close the modal popup first
            this.dispatchEvent(new CloseActionScreenEvent());
            
            // Reload page AFTER modal closes
            setTimeout(() => {
                window.location.reload();
            }, 1500);
        })
        .catch(error => {
            this.handleError('Error saving sessions', error);
            this.isLoading = false;
        });
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    handleError(title, error) {
        this.hasError = true;
        this.errorMessage = error?.body?.message || error?.message || 'An error occurred';
        this.showToast(title, this.errorMessage, 'error');
        this.isLoading = false;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }

    get selectedCount() {
        return this.uniqueSessions.filter(s => s.selected).length;
    }

    get buttonDisabled() {
        return this.isLoading || this.hasError || this.selectedCount === 0;
    }
}