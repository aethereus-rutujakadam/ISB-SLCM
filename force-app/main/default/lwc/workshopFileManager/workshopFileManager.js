import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';

import getWorkshopFiles from '@salesforce/apex/WorkshopFileManagerController.getWorkshopFiles';
import uploadFiles from '@salesforce/apex/WorkshopFileManagerController.uploadFiles';
import getFileVersions from '@salesforce/apex/WorkshopFileManagerController.getFileVersions';
import getLatestFileVersion from '@salesforce/apex/WorkshopFileManagerController.getLatestFileVersion';
import downloadFile from '@salesforce/apex/WorkshopFileManagerController.downloadFile';
import updateFileAccessScope from '@salesforce/apex/WorkshopFileManagerController.updateFileAccessScope';
import deleteFile from '@salesforce/apex/WorkshopFileManagerController.deleteFile';

const MAX_FILE_SIZE = 5242880;
const ACCEPTED_FORMATS = ['.pdf', '.jpg', '.jpeg', '.png', '.doc', '.docx'];
const ACCESS_OPTIONS = [
    { label: 'Registered Only', value: 'REGISTERED_ONLY' },
    { label: 'All Eligible', value: 'ALL_ELIGIBLE' }
];

export default class WorkshopFileManager extends LightningElement {
    @api recordId;

    @track files = [];
    @track fileVersions = [];
    @track isLoading = true;
    @track showUploadModal = false;
    @track showPreviewModal = false;
    @track showVersionModal = false;
    @track selectedFileData = null;
    @track customFileName = '';
    @track isNewVersion = false;
    @track selectedDocumentId = '';
    @track selectedFileName = '';
    @track previewFile = null;
    @track selectedAccessScope = 'REGISTERED_ONLY';
    @track showAccessModal = false;
    @track selectedAccessDocumentId = '';
    @track selectedAccessFileName = '';

    wiredFilesResult;

    @wire(getWorkshopFiles, { workshopId: '$recordId' })
    wiredFiles(result) {
        this.wiredFilesResult = result;
        const { data, error } = result;

        if (data !== undefined) {
            this.files = data.map((fileRecord) => ({
                ...fileRecord,
                formattedSize: this.formatFileSize(fileRecord.contentSize),
                formattedDate: this.formatDate(fileRecord.uploadedDate),
                iconName: this.getFileIcon(fileRecord.fileExtension),
                hasMultipleVersions: fileRecord.versionCount > 1,
                accessLabel:
                    fileRecord.accessScope === 'ALL_ELIGIBLE' ? 'All Eligible' : 'Registered Only'
            }));
            this.isLoading = false;
        }

        if (error) {
            this.files = [];
            this.isLoading = false;
            this.handleError('Error loading workshop files', error);
        }
    }

    get hasFiles() {
        return this.files.length > 0;
    }

    get hasSelectedFile() {
        return this.selectedFileData !== null;
    }

    get uploadDisabled() {
        return !this.hasSelectedFile || !this.customFileName || this.customFileName.trim() === '';
    }

    get hasVersions() {
        return this.fileVersions.length > 0;
    }

    get acceptedFormats() {
        return ACCEPTED_FORMATS.join(',');
    }

    get accessOptions() {
        return ACCESS_OPTIONS;
    }

    get selectedFileIcon() {
        if (!this.selectedFileData) {
            return 'doctype:unknown';
        }

        const extension = this.selectedFileData.name.split('.').pop().toLowerCase();
        return this.getFileIcon(extension);
    }

    get uploadModalTitle() {
        return this.isNewVersion ? 'Upload New Version' : 'Upload Workshop File';
    }

    get noFilesMessage() {
        return 'Upload the first file for this workshop.';
    }

    async handleRefresh() {
        this.isLoading = true;
        try {
            await refreshApex(this.wiredFilesResult);
        } catch (error) {
            this.handleError('Refresh failed', error);
        } finally {
            this.isLoading = false;
        }
    }

    handleOpenUploadModal() {
        this.isNewVersion = false;
        this.selectedDocumentId = '';
        this.selectedFileName = '';
        this.selectedFileData = null;
        this.customFileName = '';
        this.selectedAccessScope = 'REGISTERED_ONLY';
        this.showUploadModal = true;
    }

    handleCloseUploadModal() {
        this.showUploadModal = false;
        this.selectedFileData = null;
        this.customFileName = '';
        this.isNewVersion = false;
        this.selectedDocumentId = '';
        this.selectedFileName = '';
        this.selectedAccessScope = 'REGISTERED_ONLY';
    }

    handleFileNameChange(event) {
        this.customFileName = event.detail.value;
    }

    handleAccessScopeChange(event) {
        this.selectedAccessScope = event.detail.value;
    }

    handleFileSelection(event) {
        const [file] = event.target.files;
        if (file) {
            this.processFile(file);
        }
    }

    handleDragOver(event) {
        event.preventDefault();
    }

    handleFileDrop(event) {
        event.preventDefault();
        const [file] = event.dataTransfer.files;
        if (file) {
            this.processFile(file);
        }
    }

    processFile(file) {
        if (file.size > MAX_FILE_SIZE) {
            this.showToast('Error', 'File exceeds the 5 MB limit.', 'error');
            return;
        }

        const extension = '.' + file.name.split('.').pop().toLowerCase();
        if (!ACCEPTED_FORMATS.includes(extension)) {
            this.showToast('Error', 'Supported formats are PDF, JPG, PNG, DOC and DOCX.', 'error');
            return;
        }

        const reader = new FileReader();
        reader.onload = () => {
            let fileNameWithoutExtension = file.name;
            const lastDotIndex = fileNameWithoutExtension.lastIndexOf('.');
            if (lastDotIndex !== -1) {
                fileNameWithoutExtension = fileNameWithoutExtension.substring(0, lastDotIndex);
            }

            this.customFileName = fileNameWithoutExtension;
            this.selectedFileData = {
                name: file.name,
                type: file.type,
                size: file.size,
                base64: reader.result.split(',')[1],
                formattedSize: this.formatFileSize(file.size)
            };
        };
        reader.onerror = () => this.showToast('Error', 'Error reading file.', 'error');
        reader.readAsDataURL(file);
    }

    handleRemoveSelectedFile() {
        this.selectedFileData = null;
        this.customFileName = '';
    }

    async handleUploadConfirm() {
        if (this.uploadDisabled) {
            this.showToast('Warning', 'Select a file and provide a file name.', 'warning');
            return;
        }

        this.isLoading = true;
        try {
            const originalExtension = this.selectedFileData.name.split('.').pop();
            const uploadRequest = {
                fileName: `${this.customFileName.trim()}.${originalExtension}`,
                base64Data: this.selectedFileData.base64,
                isNewVersion: this.isNewVersion,
                existingDocumentId: this.selectedDocumentId,
                accessScope: this.selectedAccessScope
            };

            const result = await uploadFiles({
                workshopId: this.recordId,
                files: [uploadRequest]
            });

            this.showToast('Success', result.message, 'success');
            this.handleCloseUploadModal();
            await refreshApex(this.wiredFilesResult);
        } catch (error) {
            this.handleError('Upload failed', error);
        } finally {
            this.isLoading = false;
        }
    }

    handleUploadNewVersion(event) {
        this.isNewVersion = true;
        this.selectedDocumentId = event.currentTarget.dataset.id;
        this.selectedFileName = event.currentTarget.dataset.title;
        this.selectedFileData = null;
        this.customFileName = '';
        this.selectedAccessScope = event.currentTarget.dataset.access || 'REGISTERED_ONLY';
        this.showUploadModal = true;
    }

    async handlePreviewFile(event) {
        const documentId = event.currentTarget.dataset.id;
        const fileRecord = this.files.find((fileItem) => fileItem.id === documentId);
        if (!fileRecord) {
            return;
        }

        this.isLoading = true;
        try {
            const latestVersion = await getLatestFileVersion({ workshopId: this.recordId, contentDocumentId: documentId });
            const base64Data = await downloadFile({
                workshopId: this.recordId,
                contentVersionId: latestVersion.id
            });
            const lowerCaseExtension = (fileRecord.fileExtension || '').toLowerCase();
            const isPdf = lowerCaseExtension === 'pdf';
            const isImage = ['jpg', 'jpeg', 'png', 'gif'].includes(lowerCaseExtension);

            this.previewFile = {
                ...fileRecord,
                base64Url: `data:${this.getMimeType(lowerCaseExtension)};base64,${base64Data}`,
                isPdf,
                isImage,
                canPreview: isPdf || isImage
            };
            this.showPreviewModal = true;
        } catch (error) {
            this.handleError('Preview failed', error);
        } finally {
            this.isLoading = false;
        }
    }

    handleClosePreview() {
        this.showPreviewModal = false;
        this.previewFile = null;
    }

    async handleDownloadFile(event) {
        const contentVersionId = event.currentTarget.dataset.versionid;
        const fileName = event.currentTarget.dataset.title;
        const fileExtension = event.currentTarget.dataset.extension;

        this.isLoading = true;
        try {
            await this.downloadVersionFile(contentVersionId, fileName, fileExtension);
            this.showToast('Success', 'File downloaded.', 'success');
        } catch (error) {
            this.handleError('Download failed', error);
        } finally {
            this.isLoading = false;
        }
    }

    async handleDownloadPreviewFile() {
        if (!this.previewFile) {
            return;
        }

        await this.handleDownloadFile({
            currentTarget: {
                dataset: {
                    versionid: this.previewFile.contentVersionId,
                    title: this.previewFile.title
                }
            }
        });
    }

    async handleViewVersions(event) {
        this.isLoading = true;
        try {
            const versions = await getFileVersions({
                workshopId: this.recordId,
                contentDocumentId: event.currentTarget.dataset.id
            });
            this.fileVersions = versions.map((versionRecord) => ({
                ...versionRecord,
                formattedSize: this.formatFileSize(versionRecord.contentSize),
                formattedDate: this.formatDate(versionRecord.uploadedDate)
            }));
            this.showVersionModal = true;
        } catch (error) {
            this.handleError('Failed to load version history', error);
        } finally {
            this.isLoading = false;
        }
    }

    handleCloseVersionModal() {
        this.showVersionModal = false;
        this.fileVersions = [];
    }

    async handlePreviewVersion(event) {
        const versionId = event.currentTarget.dataset.versionid;
        const versionRecord = this.fileVersions.find((fileVersion) => fileVersion.id === versionId);
        if (!versionRecord) {
            return;
        }

        this.isLoading = true;
        try {
            const base64Data = await downloadFile({
                workshopId: this.recordId,
                contentVersionId: versionId
            });
            const lowerCaseExtension = (versionRecord.fileExtension || '').toLowerCase();
            const isPdf = lowerCaseExtension === 'pdf';
            const isImage = ['jpg', 'jpeg', 'png', 'gif'].includes(lowerCaseExtension);

            this.previewFile = {
                ...versionRecord,
                base64Url: `data:${this.getMimeType(lowerCaseExtension)};base64,${base64Data}`,
                isPdf,
                isImage,
                canPreview: isPdf || isImage
            };
            this.showPreviewModal = true;
            this.handleCloseVersionModal();
        } catch (error) {
            this.handleError('Preview failed', error);
        } finally {
            this.isLoading = false;
        }
    }

    async handleDownloadVersion(event) {
        this.isLoading = true;
        try {
            await this.downloadVersionFile(
                event.currentTarget.dataset.versionid,
                event.currentTarget.dataset.title,
                event.currentTarget.dataset.extension
            );
            this.showToast('Success', 'Version downloaded.', 'success');
        } catch (error) {
            this.handleError('Download failed', error);
        } finally {
            this.isLoading = false;
        }
    }

    async downloadVersionFile(contentVersionId, fileName, fileExtension) {
        const base64Data = await downloadFile({
            workshopId: this.recordId,
            contentVersionId
        });
        const link = document.createElement('a');
        link.href = `data:${this.getMimeType(fileExtension)};base64,${base64Data}`;
        link.download = fileName;
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
    }

    handleOpenAccessModal(event) {
        this.selectedAccessDocumentId = event.currentTarget.dataset.id;
        this.selectedAccessFileName = event.currentTarget.dataset.title;
        this.selectedAccessScope = event.currentTarget.dataset.access || 'REGISTERED_ONLY';
        this.showAccessModal = true;
    }

    handleCloseAccessModal() {
        this.showAccessModal = false;
        this.selectedAccessDocumentId = '';
        this.selectedAccessFileName = '';
    }

    async handleSaveAccessScope() {
        if (!this.selectedAccessDocumentId) {
            return;
        }

        this.isLoading = true;
        try {
            await updateFileAccessScope({
                workshopId: this.recordId,
                contentDocumentId: this.selectedAccessDocumentId,
                accessScope: this.selectedAccessScope
            });
            await refreshApex(this.wiredFilesResult);
            this.handleCloseAccessModal();
            this.showToast('Success', 'File access scope updated.', 'success');
        } catch (error) {
            this.handleError('Access update failed', error);
        } finally {
            this.isLoading = false;
        }
    }

    async handleDeleteFile(event) {
        const contentDocumentId = event.currentTarget.dataset.id;
        if (!contentDocumentId) {
            return;
        }

        this.isLoading = true;
        try {
            await deleteFile({
                workshopId: this.recordId,
                contentDocumentId
            });
            await refreshApex(this.wiredFilesResult);
            this.showToast('Success', 'File deleted successfully.', 'success');
        } catch (error) {
            this.handleError('Delete failed', error);
        } finally {
            this.isLoading = false;
        }
    }

    getFileIcon(extension) {
        const iconMap = {
            pdf: 'doctype:pdf',
            doc: 'doctype:word',
            docx: 'doctype:word',
            png: 'doctype:image',
            jpg: 'doctype:image',
            jpeg: 'doctype:image'
        };

        return iconMap[(extension || '').toLowerCase()] || 'doctype:unknown';
    }

    formatFileSize(bytes) {
        if (!bytes) {
            return '0 Bytes';
        }

        const units = ['Bytes', 'KB', 'MB', 'GB'];
        const unitIndex = Math.floor(Math.log(bytes) / Math.log(1024));
        return `${parseFloat((bytes / 1024 ** unitIndex).toFixed(2))} ${units[unitIndex]}`;
    }

    formatDate(dateValue) {
        if (!dateValue) {
            return '';
        }

        const dateRecord = new Date(dateValue);
        return `${dateRecord.toLocaleDateString()} ${dateRecord.toLocaleTimeString()}`;
    }

    getMimeType(extension) {
        const mimeTypes = {
            pdf: 'application/pdf',
            jpg: 'image/jpeg',
            jpeg: 'image/jpeg',
            png: 'image/png',
            gif: 'image/gif',
            doc: 'application/msword',
            docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
        };

        return mimeTypes[(extension || '').toLowerCase()] || 'application/octet-stream';
    }

    handleError(title, error) {
        const message = error?.body?.message || error?.message || 'An unknown error occurred.';
        this.showToast(title, message, 'error');
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant,
                mode: 'sticky'
            })
        );
    }
}