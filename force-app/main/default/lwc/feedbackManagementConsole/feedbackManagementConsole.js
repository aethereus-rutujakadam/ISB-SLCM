import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPrograms from '@salesforce/apex/FeedbackManagementController.getPrograms';
import getLocations from '@salesforce/apex/FeedbackManagementController.getLocations';
import getFeedbackScenarios from '@salesforce/apex/FeedbackManagementController.getFeedbackScenarios';

/**
 * @description Main Feedback Management Console LWC
 * Contains tabs for: Trigger Feedback, Template Management, Tracking Dashboard
 */
export default class FeedbackManagementConsole extends LightningElement {
    @track activeTab = 'trigger';
    @track isLoading = false;
    @track error;

    // Shared data across tabs
    @track programs = [];
    @track locations = [];
    @track scenarios = [];

    // Wire programs
    @wire(getPrograms)
    wiredPrograms({ error, data }) {
        if (data) {
            this.programs = data;
        } else if (error) {
            console.error('Error loading programs:', error);
        }
    }

    // Wire locations
    @wire(getLocations)
    wiredLocations({ error, data }) {
        if (data) {
            this.locations = data;
        } else if (error) {
            console.error('Error loading locations:', error);
        }
    }

    // Wire scenarios
    @wire(getFeedbackScenarios)
    wiredScenarios({ error, data }) {
        if (data) {
            this.scenarios = data;
        } else if (error) {
            console.error('Error loading scenarios:', error);
        }
    }

    // Tab navigation
    get tabClass() {
        return 'slds-tabs_default';
    }

    get triggerTabClass() {
        return this.activeTab === 'trigger' 
            ? 'slds-tabs_default__item slds-is-active' 
            : 'slds-tabs_default__item';
    }

    get templateTabClass() {
        return this.activeTab === 'templates' 
            ? 'slds-tabs_default__item slds-is-active' 
            : 'slds-tabs_default__item';
    }

    get trackingTabClass() {
        return this.activeTab === 'tracking' 
            ? 'slds-tabs_default__item slds-is-active' 
            : 'slds-tabs_default__item';
    }

    get isTriggerTab() {
        return this.activeTab === 'trigger';
    }

    get isTemplateTab() {
        return this.activeTab === 'templates';
    }

    get isTrackingTab() {
        return this.activeTab === 'tracking';
    }

    handleTabChange(event) {
        this.activeTab = event.target.value;
    }

    handleTabClick(event) {
        const tabName = event.currentTarget.dataset.tab;
        this.activeTab = tabName;
    }

    // Toast helper
    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }

    // Refresh handler from child components
    handleRefresh() {
        // Refresh wire adapters
        // This can be enhanced to refresh specific data
    }
}