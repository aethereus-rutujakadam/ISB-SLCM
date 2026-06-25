import { LightningElement, api, wire } from 'lwc';
import getEmploymentHistory from '@salesforce/apex/EmploymentHistoryController.getEmploymentHistory';

export default class EmploymentHistoryDisplay extends LightningElement {
    @api recordId;
    records = [];
    error;

    @wire(getEmploymentHistory, { programEnrollmentId: '$recordId' })
    wiredHistory({ error, data }) {
        if (data) {
            this.records = data.map(record => {
                // Primary Title: Organization
                const title = record.Organization_Name_c__c || record.Company_Name_c__c || 'Employment Record';
                
                // Secondary Title: Designation
                const subtitle = record.Designation_Name_c__c || record.Employment_Designation__c || '';

                // Metadata list
                const details = [];
                const detailMapping = [
                    { key: 'hed_Primary_c__c', label: 'Primary Role' },
                    { key: 'Division_Business_Unit_Office_c__c', label: 'Division/Unit' },
                    { key: 'Industry_Name_c__c', label: 'Industry' },
                    { key: 'Function_Name_c__c', label: 'Function' },
                    { key: 'Job_Location_City_Town_c__c', label: 'Location' },
                    { key: 'hed_Start_Date__c', label: 'Started' },
                    { key: 'hed_EndDate_c__c', label: 'Ended' },
                    { key: 'Type_of_Employment_c__c', label: 'Employment Type' },
                    { key: 'Experience_in_Months_c__c', label: 'Experience (Months)' },
                    { key: 'Compensation_End_Amount_c__c', label: 'CTC/Salary' },
                    { key: 'Number_of_Reportees_c__c', label: 'Team Size' },
                    { key: 'Reporting_Manager_Name_c__c', label: 'Manager' },
                    { key: 'Nature_of_the_Firm_c__c', label: 'Nature of Firm' },
                    { key: 'Reason_for_Leaving_c__c', label: 'Reason for Leaving' },
                    { key: 'hed_Status_c__c', label: 'Verification Status' },
                    { key: 'hed_StartDate_c__c', label: 'Start Date' },
                    { key: 'End_Date__c', label: 'End Date' },
                ];

                detailMapping.forEach(mapping => {
                    let value = record[mapping.key];
                    
                    // Handle booleans
                    if (typeof value === 'boolean') {
                        value = value ? 'Yes' : 'No';
                    }

                    if (value && value !== '' && value !== 'N/A') {
                        details.push({
                            id: mapping.key,
                            label: mapping.label,
                            value: value
                        });
                    }
                });

                return {
                    Id: record.Id__c || record.Id,
                    title: title,
                    subtitle: subtitle,
                    details: details
                };
            });
            this.error = undefined;
        } else if (error) {
            this.error = error.body ? error.body.message : error.message;
            this.records = [];
        }
    }

    get hasRecords() {
        return this.records && this.records.length > 0;
    }
}