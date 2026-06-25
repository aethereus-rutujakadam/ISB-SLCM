import { LightningElement, api, wire, track } from 'lwc';
import getRelationships from '@salesforce/apex/ISBContactRelationshipController.getRelationships';

const MAX_ROWS = 5;

const COLUMNS = [
    { 
        label: '#', 
        fieldName: 'rowNumber', 
        type: 'number', 
        initialWidth: 30, // Narrow column for numbering
        cellAttributes: { alignment: 'left' } 
    },
    { 
        label: 'Name', 
        fieldName: 'Name_of_the_Person_c__c', 
        type: 'button', 
        typeAttributes: { 
            label: { fieldName: 'Name_of_the_Person_c__c' }, 
            name: 'view_details', 
            variant: 'base' 
        },
        cellAttributes: {
             // Matching Salesforce bold blue link style
            class: 'slds-text-heading_small slds-p-vertical_xxx-small'
        }
    },
    { label: 'Relation Type', fieldName: 'Type_c__c', type: 'text' },
    { label: 'Email', fieldName: 'Email_c__c', type: 'email' },
    { label: 'Country Code', fieldName: 'Mobile_Phone_Code_c__c', type: 'text' },
    { label: 'Mobile Number', fieldName: 'Mobile_No_c__c', type: 'text' },
];

const SECTION_CONFIG = [
    {
        title: 'Relationship Details',
        fields: [
            { key: 'Name_of_the_Person_c__c',        label: 'Name' },
            { key: 'Type_c__c',                       label: 'Relation Type' },
            { key: 'Email_c__c',                      label: 'Email' },
            { key: 'Mobile_Phone_Code_c__c',          label: 'Country Code' },
            { key: 'Country_Name_c__c',               label: 'Country' },
            { key: 'State_Name_c__c',                 label: 'State' },
            { key: 'Postal_Code_c__c',                label: 'Postal Code' },
            { key: 'Mobile_No_c__c',                  label: 'Mobile No' },
            { key: 'Street_c__c',                     label: 'Street' },
        ]
    }
];

export default class IsbContactRelationship extends LightningElement {
    @api recordId;
    @track _allRelationships = [];
    @track displayedRelationships = [];
    @track selectedRecord = null;
    @track isModalOpen = false;
    @track isLoading = true;
    columns = COLUMNS;

    @wire(getRelationships, { recordId: '$recordId' })
    wiredRelationships({ error, data }) {
        this.isLoading = false;
        if (data) {
            this._allRelationships = data.map((rec, idx) => ({ ...rec, rowNumber: idx + 1 }));
            this.displayedRelationships = this._allRelationships.slice(0, MAX_ROWS);
        } else if (error) {
            console.error('Error fetching relationships:', error);
            this._allRelationships = [];
            this.displayedRelationships = [];
        }
    }

    get hasData() {
        return this.displayedRelationships && this.displayedRelationships.length > 0;
    }

    get totalCount() {
        return this._allRelationships.length;
    }

    get cardTitle() {
        return `Relationships (${this.totalCount})`;
    }

    get hasMore() {
        return this._allRelationships.length > MAX_ROWS;
    }

    get modalSections() {
        if (!this.selectedRecord) return [];
        return SECTION_CONFIG.map(section => ({
            title: section.title,
            fields: section.fields.map(f => ({
                key: f.key,
                label: f.label,
                value: (this.selectedRecord[f.key] !== null && this.selectedRecord[f.key] !== undefined)
                    ? String(this.selectedRecord[f.key])
                    : '—'
            }))
        }));
    }

    handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;
        if (actionName === 'view_details') {
            this.selectedRecord = row;
            this.isModalOpen = true;
        }
    }

    closeModal() {
        this.isModalOpen = false;
        this.selectedRecord = null;
    }

    handleViewAll() {
        this.displayedRelationships = this._allRelationships;
    }
}