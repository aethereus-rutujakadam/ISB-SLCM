import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { updateRecord } from 'lightning/uiRecordApi';

import fetchEraduationEligibilty from '@salesforce/apex/GraduationEligibilityLwcController.fetchEligibiltystatus';
import GRADUATION_ELIGILITIY_OBJECT from '@salesforce/schema/Graduation_Eligibility__c';
import ELIGIBILITY_STATUS from '@salesforce/schema/Graduation_Eligibility__c.Eligibility_Status__c';
import { getPicklistValues, getObjectInfo } from 'lightning/uiObjectInfoApi';
import sendGraduationEmailsApex from '@salesforce/apex/GraduationEligibilityLwcController.sendGraduationEmails';

const columns = [
    {
        label: 'Name',
        fieldName: 'enrollmentUrl',
        type: 'url',
        typeAttributes: {
            label: { fieldName: 'Name' },
            target: '_blank'
        }
    },
    {
        label: 'Finance Clearance',
        fieldName: 'Finance_Clearance__c',
        type: 'text',
        editable: false
    },

    {
        label: 'CGPA',
        fieldName: 'CGPA__c',
        type: 'number',
        editable: false
    },
    {
        label: 'Eligibility Status', fieldName: 'Eligibility_Status__c', type: 'picklistColumn', editable: true, typeAttributes: {
            placeholder: 'Choose Type', options: { fieldName: 'pickListOptions' },
            value: { fieldName: 'Eligibility_Status__c' },
            context: { fieldName: 'Id' }
        }
    },
    {
        label: 'Disciplinary Hold',
        fieldName: 'Disciplinary_Hold__c',
        type: 'boolean',
        editable: true
    },
    {
        label: 'Notes',
        fieldName: 'Notes__c',
        type: 'text',
        editable: true,
        wrapText: true
    }
];

export default class GraduationEligibilityExport extends LightningElement {
    @api recordId;
    @track data = [];
    @track isLoading = false;
    @track error = null;
    @track isSaving = false;
    actualRecordId;
    hasAttemptedLoad = false;
    wiredEligibilitiesResult;
    statusPicklistValues = [];
    columns = columns;
    showSpinner = false;
    @track accountData;
    @track draftValues = [];
    lastSavedData = [];
    @track pickListOptions;

    connectedCallback() {
        console.log('recordId...' + this.recordId);
        if (this.recordId) {
            this.loadData();
        }

    }

    loadData() {
        this.isLoading = true;

        fetchEraduationEligibilty({
            recordId: this.recordId,
            pickList: this.pickListOptions
        })
            .then(result => {
                console.log('Apex data:', JSON.stringify(result));
                this.data = result.map(row => ({
                    Id: row.Id,
                    Name: row.Name,
                    enrollmentUrl: row.Program_Enrollment__c
                        ? `/lightning/r/Program_Enrollment__c/${row.Program_Enrollment__c}/view`
                        : null,
                    AcademicYearName: row.Academic_Year__r ? row.Academic_Year__r.Name : '',
                    ProgramName: row.Program__r ? row.Program__r.Name : '',
                    ContactName:
                        (row.Program_Enrollment__r &&
                            row.Program_Enrollment__r.Contact &&
                            row.Program_Enrollment__r.Contact.Name) ||
                        (row.Contact && row.Contact.Name) ||
                        '',
                    Eligibility_Status__c: row.Eligibility_Status__c,
                    Finance_Clearance__c: row.Finance_Clearance__c,
                    Notes__c: row.Notes__c,
                    CGPA__c: row.CGPA__c,
                    Disciplinary_Hold__c: row.Disciplinary_Hold__c,
                    pickListOptions: this.pickListOptions
                }));
                console.log('Mapped data:', JSON.stringify(this.data));
            })
            .catch(error => {
                this.error = error.body?.message || error.message;
                console.error('Error loading data:', this.error);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    @wire(getObjectInfo, { objectApiName: GRADUATION_ELIGILITIY_OBJECT })
    objectInfo;

    @wire(getPicklistValues, {
        recordTypeId: "$objectInfo.data.defaultRecordTypeId",
        fieldApiName: ELIGIBILITY_STATUS
    })

    wirePickList({ error, data }) {
        if (data) {
            this.pickListOptions = data.values;
        } else if (error) {
            console.log(error);
        }
    }


    //    handleCellChange(event) {
    //         console.log('Cell Change:', JSON.stringify(event.detail.draftValues));
    //         this.draftValues = event.detail.draftValues;
    //     }

    handleCellChange(event) {
        const updated = event.detail.draftValues;

        updated.forEach(newItem => {
            let existingItem = this.draftValues.find(d => d.Id === newItem.Id);
            if (existingItem) {
                Object.assign(existingItem, newItem);
            } else {
                this.draftValues.push(newItem);
            }
        });
    }


    handleSelection(event) {
        console.log(event.detail)
    }

    async handleSave(event) {
        console.log('Inside save');
        // const draftValues = event.detail.draftValues;
        const draftValues = this.draftValues;

        // Validation: Check if Disciplinary_Hold__c is true, then Notes__c is mandatory
        for (let draft of draftValues) {
            const originalRecord = this.data.find(d => d.Id === draft.Id);
            const isDisciplinaryHold = draft.Disciplinary_Hold__c !== undefined
                ? draft.Disciplinary_Hold__c
                : originalRecord?.Disciplinary_Hold__c;

            const notes = draft.Notes__c !== undefined
                ? draft.Notes__c
                : originalRecord?.Notes__c;

            const eligibilityStatus = draft.Eligibility_Status__c !== undefined
                ? draft.Eligibility_Status__c
                : originalRecord?.Eligibility_Status__c;

            const isFinanceCleared = originalRecord?.Finance_Clearance__c === 'Cleared';

console.log('isFinanceCleared ',isFinanceCleared);
            if (eligibilityStatus === 'Approved' && !isFinanceCleared) {
                this.showToast(
                    'Error',
                    'Eligibility Status cannot be marked as Approved unless Finance Clearance is Cleared.',
                    'error'
                );
                return;
            }

            if (eligibilityStatus === 'Approved' && isDisciplinaryHold) {
                this.showToast(
                    'Error',
                    'Eligibility Status cannot be marked as Approved when Disciplinary Hold is checked.',
                    'error'
                );
                return;
            }


            if (isDisciplinaryHold && (!notes || notes.trim() === '')) {
                this.showToast('Error', 'Notes are mandatory when Disciplinary Hold is checked', 'error');
                return;
            }
        }

        try {
            const updatePromises = draftValues.map(draft => {
                const fields = { Id: draft.Id };
                if (draft.Eligibility_Status__c !== undefined)
                    fields.Eligibility_Status__c = draft.Eligibility_Status__c;
                if (draft.Notes__c !== undefined) fields.Notes__c = draft.Notes__c;
                if (draft.Disciplinary_Hold__c !== undefined)
                    fields.Disciplinary_Hold__c = draft.Disciplinary_Hold__c;
                return updateRecord({ fields });
            });

            await Promise.all(updatePromises);

            this.showToast('Success', 'Records updated successfully', 'success');
            this.draftValues = [];
            this.loadData(); // Refresh
        } catch (error) {
            this.showToast('Error', error.body?.message || error.message, 'error');
        } finally {
            this.isSaving = false;
        }
    }

    handleCancel(event) {
        console.log('inside caancel');
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    get hasData() {
        return this.data && this.data.length > 0;
    }

    get showNoData() {
        return !this.isLoading && (!this.data || this.data.length === 0) && !this.error;
    }


    exportToExcel() {
        console.log('exportToExcel ');
        console.log('hasData', this.hasData);
        if (!this.hasData) {
            this.showToast('Warning', 'No data to export', 'warning');
            return;
        }

        const csv = this.convertToCSV(this.data);
        const hiddenElement = document.createElement('a');
        hiddenElement.href = 'data:text/csv;charset=utf-8,' + encodeURI(csv);
        hiddenElement.target = '_self';
        const timestamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, -5);
        hiddenElement.download = `graduation_eligibility_export_${timestamp}.csv`;
        document.body.appendChild(hiddenElement);
        hiddenElement.click();
        document.body.removeChild(hiddenElement);

        this.showToast('Success', 'File exported successfully', 'success');
    }

    convertToCSV(data) {
        if (!data || !data.length) return '';

        const columnDelimiter = ',';
        const lineDelimiter = '\n';
        const headers = ['Name', 'Finance Clearance', 'CGPA', 'Eligibility Status', 'Disciplinary Hold', 'Notes'];
        const keys = ['Name', 'Finance_Clearance__c', 'CGPA__c', 'Eligibility_Status__c', 'Disciplinary_Hold__c', 'Notes__c'];

        let result = headers.join(columnDelimiter) + lineDelimiter;

        data.forEach(item => {
            const row = keys.map(key => {
                let value = item[key] || '';
                value = value.toString().replace(/"/g, '""');
                return `"${value}"`;
            }).join(columnDelimiter);
            result += row + lineDelimiter;
        });

        return result;
    }
    sendGraduationEmails() {
        sendGraduationEmailsApex({ recordId: this.recordId })
            .then(result => {
                this.showToast('Success', result, 'success');
            })
            .catch(error => {
                this.showToast('Error', error.body.message, 'error');
            });
    }
}