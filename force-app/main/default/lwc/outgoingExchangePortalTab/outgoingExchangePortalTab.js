import { LightningElement, wire, track } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import getExchangeCourses from '@salesforce/apex/OutgoingExchangePortalController.getExchangeCourses';
import getOutgoingCaseForContact from '@salesforce/apex/OutgoingExchangePortalController.getOutgoingCaseForContact';
import Id from '@salesforce/user/Id';
import CONTACT_ID_FIELD from '@salesforce/schema/User.ContactId';

const COLUMNS = [
    { label: 'Course Code', fieldName: 'Course_Code__c' },
    { label: 'Course Name', fieldName: 'Course_Name__c' },
    { label: 'Contact Hours', fieldName: 'Contact_Hours__c', type: 'number' },
    { label: 'Partner Credits', fieldName: 'Partner_Credits__c', type: 'number' },
    { label: 'ISB Credits', fieldName: 'ISB_Credits__c', type: 'number' },
    { label: 'Status', fieldName: 'Status__c' }
];

export default class OutgoingExchangePortalTab extends LightningElement {
    userId = Id;
    contactId;
    @track exchangeCase;
    @track courses = [];
    isLoading = true;
    columns = COLUMNS;

    @wire(getRecord, { recordId: '$userId', fields: [CONTACT_ID_FIELD] })
    wiredUser({ data, error }) {
        if (data) {
            this.contactId = data.fields.ContactId.value;
            this.loadExchangeCase();
        } else if (error) {
            this.isLoading = false;
        }
    }

    loadExchangeCase() {
        getOutgoingCaseForContact({ contactId: this.contactId })
            .then(result => {
                this.exchangeCase = result;
                if (result) {
                    this.loadCourses(result.Id);
                } else {
                    this.isLoading = false;
                }
            })
            .catch(() => { this.isLoading = false; });
    }

    loadCourses(caseId) {
        // Query by ProgramEnrollment__c — get PE from case
        // For portal simplicity, use contactId-based lookup via controller
        getExchangeCourses({ programEnrollmentId: this.exchangeCase.ProgramEnrollment__c })
            .then(result => {
                this.courses = result;
                this.isLoading = false;
            })
            .catch(() => { this.isLoading = false; });
    }

    get exchangeSchoolName() {
        return this.exchangeCase && this.exchangeCase.Exchange_School_Partner__r
            ? this.exchangeCase.Exchange_School_Partner__r.Name
            : '';
    }

    get isTranscriptDispatched() {
        return this.exchangeCase && this.exchangeCase.Transcript_Dispatched__c;
    }

    get formattedDispatchDate() {
        if (!this.exchangeCase || !this.exchangeCase.Dispatch_Date__c) return '';
        return new Date(this.exchangeCase.Dispatch_Date__c).toLocaleDateString();
    }

    get hasCourses() {
        return this.courses && this.courses.length > 0;
    }
}