import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getPublishedPosts from '@salesforce/apex/StudentPostController.getPublishedPosts';
import getMyPosts from '@salesforce/apex/StudentPostController.getMyPosts';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const IMAGE_EXTS = ['png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp', 'svg'];

const COLUMNS = [
    { label: 'Title',             fieldName: 'Title',                type: 'text' },
    {
        label: 'Status',
        fieldName: 'Status',
        type: 'text',
        cellAttributes: { class: { fieldName: 'statusClass' } }
    },
    { label: 'Submitted Date',    fieldName: 'CreatedDateFormatted', type: 'text' },
    { label: 'Reviewer Comments', fieldName: 'ReviewerComments',     type: 'text', wrapText: true },
    {
        type: 'button',
        typeAttributes: {
            label:        'View Details',
            name:         'view_details',
            variant:      'base',
            iconName:     'utility:preview',
            iconPosition: 'left'
        },
        fixedWidth: 140
    }
];

export default class StudentPostPublisher extends NavigationMixin(LightningElement) {
    @api flowName = 'Student_Post_publishing_flow';

    // Published posts feed
    @track posts          = [];
    @track isLoadingPosts = true;

    // My Posts modal
    @track showMyPostsModal = false;
    @track isLoadingMyPosts = false;
    @track myPosts          = [];
    @track modalView        = 'list'; // 'list' | 'detail'
    @track selectedPost     = null;

    // File preview modal — key: previewSrc is bound directly to <img src={previewSrc}>
    @track showFilePreview    = false;
    @track previewSrc         = '';   // rendition URL — bound directly to <img>
    @track previewFileName    = '';
    @track previewDoctypeIcon = 'doctype:attachment';
    @track previewIsPdf       = false; // true when file is PDF (show "Open PDF" button)
    @track previewContentDocId = '';
    @track previewVersionId   = '';

    // Flow
    showFlow    = false;
    flowStarted = false;

    columns = COLUMNS;

    get isListView() {
        return this.modalView === 'list';
    }

    // ── Lifecycle ──────────────────────────────────────────────────

    connectedCallback() {
        this.loadPosts();
    }

    renderedCallback() {
        // Start flow once lightning-flow is in the DOM
        if (this.showFlow && !this.flowStarted) {
            const flowEl = this.template.querySelector('lightning-flow');
            if (flowEl) {
                try {
                    flowEl.startFlow(this.flowName);
                    this.flowStarted = true;
                } catch (e) {
                    this.showFlow    = false;
                    this.flowStarted = false;
                    console.error('Failed to start flow', e);
                }
            }
        }
    }

    // ── Private helpers ────────────────────────────────────────────

    _getInitials(name) {
        if (!name) return '??';
        const parts = name.trim().split(/\s+/);
        if (parts.length >= 2) return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
        return parts[0].substring(0, 2).toUpperCase();
    }

    _getFileGridClass(total) {
        if (total === 1) return 'file-grid-item file-grid-full';
        if (total === 2) return 'file-grid-item file-grid-half';
        return 'file-grid-item file-grid-third';
    }

    _getFileExt(title) {
        return (title || '').split('.').pop().toLowerCase();
    }

    _getDoctypeIcon(title) {
        const ext = this._getFileExt(title);
        if (IMAGE_EXTS.includes(ext))          return 'doctype:image';
        if (ext === 'pdf')                      return 'doctype:pdf';
        if (['doc','docx'].includes(ext))       return 'doctype:word';
        if (['xls','xlsx'].includes(ext))       return 'doctype:excel';
        if (['ppt','pptx'].includes(ext))       return 'doctype:ppt';
        if (['txt','log'].includes(ext))        return 'doctype:txt';
        if (ext === 'csv')                      return 'doctype:csv';
        if (['zip','rar','7z'].includes(ext))   return 'doctype:zip';
        if (['mp4','mov','avi'].includes(ext))  return 'doctype:video';
        return 'doctype:attachment';
    }

    /**
     * Compute the preview src URL per the reference approach:
     *  PNG  → rendition=ORIGINAL_Png  (full-resolution PNG served as image)
     *  JPG  → rendition=ORIGINAL_Jpg  (full-resolution JPG served as image)
     *  PDF  → rendition=THUMB720BY480 (Salesforce renders first page as image)
     *  All other image/doc types → rendition=THUMB720BY480
     *
     * These rendition URLs are same-origin and can be bound DIRECTLY to
     * <img src={previewSrc}> — no renderedCallback setAttribute needed.
     */
    _getPreviewSrc(fileExt, versionId) {
        if (!versionId) return '';
        const base = `/sfc/servlet.shepherd/version/renditionDownload?versionId=${versionId}`;
        
        if (fileExt === 'png') {
            return `${base}&rendition=ORIGINAL_Png`;
        }
        if (fileExt === 'jpg' || fileExt === 'jpeg') {
            return `${base}&rendition=ORIGINAL_Jpg`;
        }
        return `${base}&rendition=THUMB720BY480`;
    }

    /**
     * Fix images in rich text. In Experience Cloud, /servlet/rtaImage URLs often fail.
     * We replace them with /sfc/servlet.shepherd/version/download/ URLs using the
     * files related to the post.
     */
    _fixRichTextImages(body, files) {
        if (!body || !files || files.length === 0) return body;
        let fixedBody = body;
        
        files.forEach(file => {
            if (file.ContentVersionId) {
                // Prepend or match URLs ending in /servlet/rtaImage
                const rtaRegex = new RegExp(`[^"']*servlet/rtaImage\\?.*refid=(${file.ContentDocumentId}|${file.ContentVersionId})[^"']*`, 'gi');
                // Replace with working community download URL
                fixedBody = fixedBody.replace(rtaRegex, `/sfc/servlet.shepherd/version/download/${file.ContentVersionId}`);
            }
        });
        return fixedBody;
    }

    _mapFiles(rawFiles, totalCount) {
        const gridClass = this._getFileGridClass(totalCount);
        return (rawFiles || []).map(f => {
            const ext   = this._getFileExt(f.Title);
            const isPdf = ext === 'pdf';
            const isImage = IMAGE_EXTS.includes(ext);
            return {
                ...f,
                isPdf,
                isImage,
                // ThumbUrl  — ONLY show thumbnails for images to avoid broken icons for documents/PDFs
                ThumbUrl: (isImage && f.ContentVersionId)
                    ? `/sfc/servlet.shepherd/version/renditionDownload?rendition=THUMB720BY480&versionId=${f.ContentVersionId}`
                    : '',
                previewSrc: this._getPreviewSrc(ext, f.ContentVersionId),
                DoctypeIcon: this._getDoctypeIcon(f.Title),
                gridClass
            };
        });
    }

    _statusMeta(status) {
        switch (status) {
            case 'Published':
            case 'Approved':  return { statusClass: 'slds-text-color_success' };
            case 'Rejected':  return { statusClass: 'slds-text-color_error' };
            case 'Pending':   return { statusClass: 'slds-text-color_weak' };
            default:          return { statusClass: '' };
        }
    }

    // ── Data loading ───────────────────────────────────────────────

    loadPosts() {
        this.isLoadingPosts = true;
        getPublishedPosts()
            .then(result => {
                const rows = Array.isArray(result) ? result : [];
                this.posts = rows.map(p => {
                    const mappedFiles = this._mapFiles(p.Files, (p.Files || []).length);
                    return {
                        Id: p.Id,
                        Title: p.Title,
                        Body:  this._fixRichTextImages(p.Body || '', mappedFiles),
                        CreatedByName: p.CreatedByName || 'Unknown',
                        Initials: this._getInitials(p.CreatedByName),
                        Files: mappedFiles,
                        PublishedOn: p.PublishedOn
                            ? new Date(p.PublishedOn).toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' })
                            : '',
                        CreatedDateFormatted: p.CreatedDate ? new Date(p.CreatedDate).toLocaleString() : ''
                    };
                });
                this.isLoadingPosts = false;
            })
            .catch(error => {
                this.isLoadingPosts = false;
                this.posts = [];
                const msg = error?.body?.message || error?.message || 'Error loading posts';
                this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: msg, variant: 'error' }));
            });
    }

    loadMyPosts() {
        this.isLoadingMyPosts = true;
        getMyPosts()
            .then(result => {
                const rows = Array.isArray(result) ? result : [];
                this.myPosts = rows.map(p => {
                    const mappedFiles = this._mapFiles(p.Files, (p.Files || []).length);
                    return {
                        ...p,
                        ...this._statusMeta(p.Status),
                        Body: this._fixRichTextImages(p.Body || '', mappedFiles),
                        CreatedDateFormatted: p.CreatedDate ? new Date(p.CreatedDate).toLocaleString() : '',
                        Files: mappedFiles
                    };
                });
                this.isLoadingMyPosts = false;
            })
            .catch(error => {
                this.isLoadingMyPosts = false;
                this.myPosts = [];
                const msg = error?.body?.message || error?.message || 'Error loading your posts';
                this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: msg, variant: 'error' }));
            });
    }

    // ── Flow ──────────────────────────────────────────────────────

    handleOpenFlow() { this.showFlow = true;  this.flowStarted = false; }
    closeFlow()      { this.showFlow = false; this.flowStarted = false; }

    handleFlowStatusChange(event) {
        if (['FINISHED','FINISHED_SCREEN','ERROR'].includes(event.detail.status)) {
            this.showFlow    = false;
            this.flowStarted = false;
            this.loadPosts();
        }
    }

    // ── File preview modal ────────────────────────────────────────
    //
    // Pattern from reference (salesforcebolt.com):
    //   1. Pre-compute previewSrc rendition URL per file in _mapFiles
    //   2. On chip/thumbnail click → set this.previewSrc = file.previewSrc
    //   3. Template: <img src={previewSrc} /> — directly bound, works for all image types
    //   4. For PDFs: THUMB720BY480 gives a first-page image preview
    //      Plus an "Open PDF" button → window.open() to view in browser tab

    _openFilePreviewFromList(contentDocId, postList) {
        for (const post of postList) {
            const file = (post.Files || []).find(f => f.ContentDocumentId === contentDocId);
            if (file) {
                this.previewSrc          = file.previewSrc   || '';
                this.previewFileName     = file.Title        || 'Attachment';
                this.previewDoctypeIcon  = file.DoctypeIcon  || 'doctype:attachment';
                this.previewIsPdf        = file.isPdf        || false;
                this.previewContentDocId = file.ContentDocumentId || '';
                this.previewVersionId    = file.ContentVersionId  || '';
                this.showFilePreview     = true;
                return;
            }
        }
    }

    // Thumbnail click on published post feed card
    handleFilePreview(event) {
        const id = event.currentTarget.dataset.id;
        if (id) this._openFilePreviewFromList(id, this.posts);
    }

    // Fallback when thumbnail image fails to load — replace with file icon placeholder
    handleThumbError(event) {
        const img = event.target;
        const container = img.parentElement;
        if (container) {
            img.style.display = 'none';
            // Check if placeholder already exists to avoid duplicate inserts
            if (!container.querySelector('.post-file-placeholder')) {
                const placeholder = document.createElement('div');
                placeholder.classList.add('post-file-placeholder');
                placeholder.innerHTML = `<span class="post-file-name">${img.alt || 'File'}</span>`;
                container.insertBefore(placeholder, img);
            }
        }
    }

    // Attachment chip click inside My Posts detail view
    handleAttachmentClick(event) {
        const id = event.currentTarget.dataset.id;
        if (id) this._openFilePreviewFromList(id, this.myPosts);
    }

    closeFilePreview() {
        this.showFilePreview     = false;
        this.previewSrc          = '';
        this.previewFileName     = '';
        this.previewIsPdf        = false;
        this.previewDoctypeIcon  = 'doctype:attachment';
        this.previewContentDocId = '';
        this.previewVersionId    = '';
    }

    // Download the file (opens in new tab / triggers browser download)
    handleDownload() {
        if (this.previewContentDocId) {
            window.open(`/sfc/servlet.shepherd/document/download/${this.previewContentDocId}`, '_blank');
        }
    }

    // For PDFs — open the actual PDF in a new browser tab
    handleOpenPdf() {
        if (this.previewVersionId) {
            window.open(`/sfc/servlet.shepherd/version/download/${this.previewVersionId}`, '_blank');
        }
    }

    // ── My Posts modal ────────────────────────────────────────────

    handleOpenMyPosts() {
        this.showMyPostsModal = true;
        this.modalView        = 'list';
        this.selectedPost     = null;
        this.loadMyPosts();
    }

    closeMyPostsModal() {
        this.showMyPostsModal = false;
        this.modalView        = 'list';
        this.selectedPost     = null;
    }

    handleRowAction(event) {
        if (event.detail.action.name === 'view_details') {
            this.selectedPost = event.detail.row;
            this.modalView    = 'detail';
        }
    }

    handleBackToList() {
        this.modalView    = 'list';
        this.selectedPost = null;
    }
}