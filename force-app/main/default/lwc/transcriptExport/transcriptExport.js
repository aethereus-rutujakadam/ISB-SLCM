import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getTranscripts from '@salesforce/apex/TranscriptExportController.getTranscripts';

export default class TranscriptExport extends NavigationMixin(LightningElement) {

    @track viewType = 'Interim';
    @track records = [];

    get viewOptions() {
        return [
            { label: 'Interim', value: 'Interim' },
            { label: 'Final', value: 'Final' }
        ];
    }

    handleViewChange(event) {
        this.viewType = event.detail.value;
    }

    @wire(getTranscripts, { viewType: '$viewType' })
    wiredData({ error, data }) {
        if (data) {
            this.records = data;
        } else if (error) {
            console.error('Error loading transcripts:', error);
        }
    }

    exportCSV() {

        if (!this.records || this.records.length === 0) {
            alert('No transcript records found to export.');
            return;
        }

        let csv =
            'Student,Program,Academic Term,Academic Session,Course,Credits,Grade,Grade Points,Term GPA,Credits Earned Till Term,CGPA,Total Credits\n';

        this.records.forEach(rec => {
            csv += `"${rec.Student__r?.Name || ''}",`;
            csv += `"${rec.Program__r?.Name || ''}",`;
            csv += `"${rec.Academic_Term__r?.Name || ''}",`;
            csv += `"${rec.Academic_Session__r?.Name || ''}",`;
            csv += `"${rec.Course__r?.Name || ''}",`;
            csv += `"${rec.Credits__c || ''}",`;
            csv += `"${rec.Grade__c || ''}",`;
            csv += `"${rec.Grade_Points__c || ''}",`;
            csv += `"${rec.Term_GPA__c || ''}",`;
            csv += `"${rec.Credits_Earned_Till_Term__c || ''}",`;
            csv += `"${rec.CGPA__c || ''}",`;
            csv += `"${rec.Total_Credits__c || ''}"\n`;
        });

        // Download CSV
        const element = document.createElement('a');
        element.href = 'data:text/csv;charset=utf-8,' + encodeURI(csv);

        const timestamp = new Date().toISOString().replace(/[:.-]/g, '');
        element.download = `Transcript_${this.viewType}_${timestamp}.csv`;

        document.body.appendChild(element);
        element.click();
        document.body.removeChild(element);

        // Redirect After Download
        this.navigateToTranscriptListView();
    }

    navigateToTranscriptListView() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Transcript__c',
                actionName: 'list'
            }
        });
    }
}