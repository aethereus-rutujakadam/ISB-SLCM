import { LightningElement } from 'lwc';
import SHEETJS from '@salesforce/resourceUrl/SheetJS';
import { loadScript } from 'lightning/platformResourceLoader';
import processCatalogData from '@salesforce/apex/AwardCatalogUploadController.processCatalogData';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { NavigationMixin } from 'lightning/navigation';

export default class AwardCatalogUploader extends NavigationMixin(LightningElement) {

    fileName;
    fileData = [];
    errorData = [];
    columns = [];
    sheetLoaded = false;
    isLoading = false;

    get recordsCount() {
        return this.fileData.length;
    }
    get isSubmitDisabled() {
        return this.isLoading || this.fileData.length === 0;
    }

    renderedCallback() {
        if (this.sheetLoaded) return;
        loadScript(this, SHEETJS).then(() => { this.sheetLoaded = true; });
    }

    handleFileChange(event) {
        const file = event.target.files[0];
        if (!file) return;

        this.fileName = file.name;
        const reader = new FileReader();

        reader.onload = e => {
            const data = new Uint8Array(e.target.result);
            const workbook = window.XLSX.read(data, { type: 'array' });
            const sheet = workbook.Sheets[workbook.SheetNames[0]];
            const json = window.XLSX.utils.sheet_to_json(sheet);

            this.fileData = json.map((r, i) => ({ id: i, ...r }));
            this.columns = Object.keys(this.fileData[0])
                .filter(key => key !== 'id')
                .map(col => ({
                    label: col,
                    fieldName: col,
                    type: 'text'
                }));
        };

        reader.readAsArrayBuffer(file);
    }

    handleSubmit() {
        this.isLoading = true;
        processCatalogData({ records: this.fileData })
            .then(result => {

                this.errorData = result.errorRecords || [];

                this.showToast('Success', `${result.successCount} records uploaded successfully`, 'success');

                // ✅ Close popup
                this.dispatchEvent(new CloseActionScreenEvent());

                // ✅ Redirect to Award Catalog list view + Refresh page
                setTimeout(() => {
                    this[NavigationMixin.Navigate]({
                        type: 'standard__objectPage',
                        attributes: {
                            objectApiName: 'Award_Catalog__c',
                            actionName: 'list'
                        },
                        state: {
                            filterName: 'Recent'
                        }
                    });
                }, 300);

            })
            .catch(error => {
                this.showToast('Error', error.body?.message || error.message, 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    downloadErrorReport() {
        let csv = 'Award Catalog Name,Award Recipient Type,Category,Active,Description,Error\n';
        this.errorData.forEach(r => {
            csv += `"${r['Award Catalog Name']}","${r['Award Recipient Type']}","${r['Category']}","${r['Active']}","${r['Description']}","${r.Error}"\n`;
        });

        const blob = new Blob([csv], { type: 'text/csv' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = 'AwardCatalogErrorReport.csv';
        a.click();
        URL.revokeObjectURL(url);
    }

    resetForm() {
        this.fileName = null;
        this.fileData = [];
        this.errorData = [];
        this.columns = [];
        const input = this.template.querySelector('lightning-input[type="file"]');
        if (input) input.value = null;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}