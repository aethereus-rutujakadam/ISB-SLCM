import { LightningElement, api, wire } from 'lwc';
import getEducationHistory from '@salesforce/apex/EducationHistoryController.getEducationHistory';
 
export default class EducationHistoryDisplay extends LightningElement {
    @api recordId;
    records = [];
    error;
 
    @wire(getEducationHistory, { programEnrollmentId: '$recordId' })
    wiredHistory({ error, data }) {
        if (data) {
            this.records = data.map(record => {
                // Primary Title: Institute
                const title = record.InstituteForDegreeLevel_c__c || record.Institute_Name_c__c || record.hed_Educational_Institution_Name_c__c || record.CertificationInstitute_Name_c__c || 'Education Record';
               
                // Secondary Subtitle: Degree
                const subtitle = record.Degree_Level_c__c || record.Degree_Name_c__c || record.hed_Degree_Earned_c__c || '';

                // Metadata list
                const details = [];
                const detailMapping = [
                    // Primary fields in desired display order
                    { key: 'Degree_Name_c__c', label: 'Degree Name', isDateField: false },
                    { key: 'Specialization_c__c', label: 'Specialization', isDateField: false },
                    { key: 'Field_Of_Study_Name_c__c', label: 'Field of Study Name', isDateField: false },
                    { key: 'Start_Date__c', label: 'Start Date', isDateField: true },
                    { key: 'End_Date__c', label: 'End Date', isDateField: true },
                    { key: 'hed_GPA_c__c', label: 'GPA/Score', isDateField: false },
                    { key: 'City_Name_c__c', label: 'City', isDateField: false },
                    // Rest of fields
                    { key: 'Degree_Level_c__c ', label: 'Degree Level', isDateField: false },
                    { key: 'Certification_Name_c__c', label: 'Certification', isDateField: false },
                    { key: 'hed_Academic_Certification_c__c', label: 'Academic Certification', isDateField: false },
                    { key: 'CAS_Specialisation_c__c', label: 'CAS Specialization', isDateField: false },
                    { key: 'Other_Field_of_Study_c__c', label: 'Other Field of Study', isDateField: false },
                    { key: 'Enrollment_Type_c__c', label: 'Enrollment Type', isDateField: false },
                    { key: 'PG_Degree_c__c', label: 'PG Degree', isDateField: false },
                    { key: 'PG_Diploma_duration_in_months_c__c', label: 'PG Diploma Duration (Months)', isDateField: false },
                    { key: 'Other_Degree_Earned_c__c', label: 'Other Degree Earned', isDateField: false },
                    { key: 'Country_Name_c__c', label: 'Country', isDateField: false },
                    { key: 'State_Name_c__c', label: 'State', isDateField: false },
                    { key: 'Course_Duration_c__c', label: 'Duration', isDateField: false },
                    { key: 'Current_Year_c__c', label: 'Current Year', isDateField: false },
                    { key: 'hed_Graduation_Date_c__c', label: 'Graduation Date', isDateField: false },
                    { key: 'Percentage_Or_GPA_c__c', label: 'Percentage/GPA', isDateField: false },
                    { key: 'GPA_Scale_c__c', label: 'GPA Scale', isDateField: false },
                    { key: 'hed_GPA_Scale_Reporting_c__c', label: 'GPA Scale Reporting', isDateField: false },
                    { key: 'hed_GPA_Scale_Type_c__c', label: 'GPA Scale Type', isDateField: false },
                    { key: 'First_Year_GPA_c__c', label: 'First Year GPA', isDateField: false },
                    { key: 'First_Year_GPA_Scale_Reporting_c__c', label: 'First Year GPA Scale', isDateField: false },
                    { key: 'Second_Year_GPA_c__c', label: 'Second Year GPA', isDateField: false },
                    { key: 'Third_Year_GPA_c__c', label: 'Third Year GPA', isDateField: false },
                    { key: 'Fifth_Year_GPA_c__c', label: 'Fifth Year GPA', isDateField: false },
                    { key: 'Fifth_Year_GPA_Scale_Reporting_c__c', label: 'Fifth Year GPA Scale', isDateField: false },
                    { key: 'randa_Converted_GPA_c__c', label: 'Converted GPA', isDateField: false },
                    { key: 'hed_Credits_Earned_c__c', label: 'Credits Earned', isDateField: false },
                    { key: 'hed_Class_Rank_c__c', label: 'Class Rank', isDateField: false },
                    { key: 'hed_Class_Rank_Scale_c__c', label: 'Class Rank Scale', isDateField: false },
                    { key: 'hed_Class_Rank_Type_c__c', label: 'Class Rank Type', isDateField: false },
                    { key: 'hed_Class_Percentile_c__c', label: 'Class Percentile', isDateField: false },
                    { key: 'hed_Class_Size_c__c', label: 'Class Size', isDateField: false },
                    { key: 'Dual_Degree_Name_c__c', label: 'Dual Degree', isDateField: false },
                    { key: 'Board_Name_c__c', label: 'Board', isDateField: false },
                    { key: 'Other_University_c__c', label: 'Other University', isDateField: false },
                    { key: 'Other_Institute_c__c', label: 'Other Institute', isDateField: false },
                    { key: 'hed_Credentialing_Identifier_c__c', label: 'Credentialing Identifier', isDateField: false },
                    { key: 'Gap_in_Education_c__c', label: 'Gap in Education', isDateField: false },
                    { key: 'hed_Details_c__c', label: 'Details', isDateField: false },
                    { key: 'RPA_Verified_c__c', label: 'RPA Verified', isDateField: false },
                    { key: 'Verified_by_CAS_c__c', label: 'Verified by CAS', isDateField: false },
                    { key: 'hed_Status_c__c', label: 'Status', isDateField: false },
                    { key: 'hed_Verification_Status_c__c', label: 'Verification Status', isDateField: false },
                    { key: 'hed_Verification_Status_Date_c__c', label: 'Verification Status Date', isDateField: false }
                ];
 
                detailMapping.forEach(mapping => {
                    let value = record[mapping.key];
                   
                    // Handle booleans
                    if (typeof value === 'boolean') {
                        value = value ? 'Yes' : 'No';
                    }
 
                    // Format GPA/Score to 2 decimal places
                    if (mapping.key === 'hed_GPA_c__c' && value) {
                        value = parseFloat(value).toFixed(2);
                    }
 
                    if (value && value !== '' && value !== 'N/A') {
                        details.push({
                            id: mapping.key,
                            label: mapping.label,
                            value: value,
                            isDateField: mapping.isDateField || false
                        });
                    }
                });

                // Extract date fields to render separately in parallel
                let startDateField = null;
                let endDateField = null;
                const nonDateDetails = details.filter(field => {
                    if (field.id === 'Start_Date__c') {
                        startDateField = field;
                        return false;
                    } else if (field.id === 'End_Date__c') {
                        endDateField = field;
                        return false;
                    }
                    return true;
                });
 
                return {
                    Id: record.Id__c || record.Id,
                    title: title,
                    subtitle: subtitle,
                    startDateField: startDateField,
                    endDateField: endDateField,
                    details: nonDateDetails
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