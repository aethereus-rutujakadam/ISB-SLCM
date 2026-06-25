import { LightningElement, api, track } from 'lwc';
import getActiveProfessionalMemberships from '@salesforce/apex/ClubMembershipController.getProfessionalMemberships';
import getOtherMemberships from '@salesforce/apex/ClubMembershipController.getOtherMemberships';
import getClubRequests from '@salesforce/apex/ClubMembershipController.getClubRequests';
import getPendingMemberships from '@salesforce/apex/ClubMembershipController.getPendingMemberships';
// Changes made by Diksha: New imports START
import getAvailableClubsForReassignment from '@salesforce/apex/ClubMembershipController.getAvailableClubsForReassignment';
import processClubReassignment from '@salesforce/apex/ClubMembershipController.processClubReassignment';
import cleanupRejectedMemberships from '@salesforce/apex/ClubMembershipController.cleanupRejectedMemberships';
// Changes made by Diksha: New imports END
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class ClubMembershipList extends LightningElement {
    @api contactId;
    @api recordId;
    @track memberships = [];
    @track otherMemberships = [];
    @track sigRequests = [];
    @track pendingMemberships = [];
    @track isLoading = true;
    @track showFlow = false;

    // Changes made by Diksha: New tracking variables START
    @track showReassignModal = false;
    @track availableClubs = [];
    @track selectedNewClubId = '';
    @track currentMembershipToReassign = '';
    // Changes made by Diksha: New tracking variables END

    // Define columns for the datatable - Updated by Diksha to include Reassign button
    columns = [
        { 
            label: 'Club Name', 
            fieldName: 'clubName', 
            type: 'text',
            wrapText: true
        },
        { 
            label: 'Role', 
            fieldName: 'role', 
            type: 'text'
        },
        { 
            label: 'Academic Year', 
            fieldName: 'academicYear', 
            type: 'text'
        },
        { 
            label: 'Status', 
            fieldName: 'status', 
            type: 'text',
            cellAttributes: { 
                class: { fieldName: 'statusClass' } 
            }
        },
        { 
            label: 'Approval Status', 
            fieldName: 'approvalStatus', 
            type: 'text'
        },
        // Changes made by Diksha: Added Reassign button
        {
            type: 'button',
            initialWidth: 120,
            typeAttributes: {
                label: 'Reassign',
                name: 'reassign',
                title: 'Reassign Club',
                variant: 'border-filled',
                iconName: 'utility:change_record_type'
            }
        }
    ];

    // Changes made by Diksha: Columns WITHOUT button
    socialColumns = [
        { label: 'Club Name', fieldName: 'clubName', type: 'text', wrapText: true },
        { label: 'Role', fieldName: 'role', type: 'text' },
        { label: 'Academic Year', fieldName: 'academicYear', type: 'text' },
        { label: 'Status', fieldName: 'status', type: 'text', cellAttributes: { class: { fieldName: 'statusClass' } } },
        { label: 'Approval Status', fieldName: 'approvalStatus', type: 'text' }
    ];

    requestColumns = [
        { 
            label: 'Request Name', 
            fieldName: 'requestName', 
            type: 'text',
            wrapText: true 
        },
        { 
            label: 'Category', 
            fieldName: 'category', 
            type: 'text' 
        },
        { 
            label: 'Created Date', 
            fieldName: 'createdDate', 
            type: 'date' 
        },
        { 
            label: 'Status', 
            fieldName: 'status', 
            type: 'text' 
        }
    ];

    connectedCallback() {
        this.loadAllMemberships();
    }

    loadAllMemberships() {
        this.isLoading = true;
        Promise.all([
            this.loadProfessionalMemberships(),
            this.loadOtherMemberships(),
            this.loadClubRequests(),
            this.loadPendingMemberships()
        ]).then(() => {
            this.isLoading = false;
        }).catch(error => {
            this.isLoading = false;
            console.error('Error loading memberships:', error);
        });
    }

    get effectiveContactId() {
        if (this.contactId) return this.contactId;
        if (this.recordId) return this.recordId;
        return null;
    }

    get hasMemberships() {
        return Array.isArray(this.memberships) && this.memberships.length > 0;
    }

    get hasOtherMemberships() {
        return Array.isArray(this.otherMemberships) && this.otherMemberships.length > 0;
    }

    get hasSigRequests() {
        return Array.isArray(this.sigRequests) && this.sigRequests.length > 0;
    }

    get hasPendingMemberships() {
        return Array.isArray(this.pendingMemberships) && this.pendingMemberships.length > 0;
    }

    loadProfessionalMemberships() {
        return getActiveProfessionalMemberships({ contactId: this.effectiveContactId })
            .then(result => {
                console.log('Professional memberships result:', JSON.stringify(result));
                
                const data = result.memberships || result || [];
                
                this.memberships = data.map(r => ({
                    membershipId: r.membershipId,
                    clubId: r.clubId,
                    clubName: r.clubName || 'N/A',
                    role: r.role || 'N/A',
                    status: r.status || 'N/A',
                    approvalStatus: r.approvalStatus || 'N/A',
                    academicYear: r.academicYear || 'N/A',
                    programEnrollmentId: r.programEnrollmentId,
                    statusClass: this.getStatusClass(r.status)
                }));
                
                if (result.debugMessage) {
                    console.log('Debug (Professional):', result.debugMessage);
                }
            })
            .catch(error => {
                this.memberships = [];
                console.error('Error loading professional memberships:', error);
                
                const errorMessage = error?.body?.message || error?.message || 'Unknown error occurred';
                this.showToast('Error Loading Professional Memberships', errorMessage, 'error');
            });
    }

    loadOtherMemberships() {
        return getOtherMemberships({ contactId: this.effectiveContactId })
            .then(result => {
                const data = result.memberships || result || [];
                
                this.otherMemberships = data.map(r => ({
                    membershipId: r.membershipId,
                    clubId: r.clubId,
                    clubName: r.clubName || 'N/A',
                    role: r.role || 'N/A',
                    status: r.status || 'N/A',
                    approvalStatus: r.approvalStatus || 'N/A',
                    academicYear: r.academicYear || 'N/A',
                    programEnrollmentId: r.programEnrollmentId,
                    statusClass: this.getStatusClass(r.status)
                }));
            })
            .catch(error => {
                this.otherMemberships = [];
                console.error('Error loading other memberships:', error);
            });
    }

    loadClubRequests() {
        return getClubRequests({ contactId: this.effectiveContactId })
            .then(result => {
                console.log('Club requests result:', JSON.stringify(result));
                const data = result.requests || [];
                this.sigRequests = data;
            })
            .catch(error => {
                this.sigRequests = [];
                console.error('Error loading club requests:', error);
            });
    }

    loadPendingMemberships() {
         return getPendingMemberships({ contactId: this.effectiveContactId })
            .then(result => {
                const data = result.memberships || [];
                this.pendingMemberships = data.map(r => ({
                    membershipId: r.membershipId,
                    clubId: r.clubId,
                    clubName: r.clubName || 'N/A',
                    role: r.role || 'N/A',
                    status: r.status || 'N/A',
                    approvalStatus: r.approvalStatus || 'N/A',
                    academicYear: r.academicYear || 'N/A',
                    programEnrollmentId: r.programEnrollmentId,
                    statusClass: this.getStatusClass(r.status)
                }));
            })
            .catch(error => {
                this.pendingMemberships = [];
                console.error('Error loading pending memberships:', error);
            });
    }

    getStatusClass(status) {
        // Add custom CSS classes based on status
        if (!status) return '';
        
        const statusLower = status.toLowerCase();
        if (statusLower.includes('active') || statusLower.includes('approved')) {
            return 'slds-text-color_success';
        } else if (statusLower.includes('pending')) {
            return 'slds-text-color_warning';
        } else if (statusLower.includes('rejected') || statusLower.includes('inactive')) {
            return 'slds-text-color_error';
        }
        return '';
    }

    // Changes made by Diksha: START
    handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;
        if (actionName === 'reassign') {
            this.currentMembershipToReassign = row.membershipId;
            this.fetchAvailableClubs();
        }
    }

    fetchAvailableClubs() {
        this.isLoading = true;
        getAvailableClubsForReassignment({ contactId: this.effectiveContactId })
            .then(result => {
                this.availableClubs = result;
                this.showReassignModal = true;
                this.isLoading = false;
            })
            .catch(error => {
                this.isLoading = false;
                console.error('Error fetching available clubs:', error);
                const msg = error?.body?.message || error?.message || 'Error fetching clubs';
                this.showToast('Error', msg, 'error');
            });
    }

    handleClubChange(event) {
        this.selectedNewClubId = event.detail.value;
    }

    closeReassignModal() {
        this.showReassignModal = false;
        this.selectedNewClubId = '';
    }

    submitReassignment() {
        console.log('contactId',this.effectiveContactId );
        if (!this.selectedNewClubId) {
            this.showToast('Warning', 'Please select a club to reassign to.', 'warning');
            return;
        }
        this.isLoading = true;
        processClubReassignment({
            oldMembershipId: this.currentMembershipToReassign,
            newClubId: this.selectedNewClubId,
            contactId: this.effectiveContactId
        })
        .then(() => {
            this.showToast('Success', 'Club reassignment request submitted. Status is Inactive (Pending Approval).', 'success');
            this.showReassignModal = false;
            this.loadAllMemberships();
        })
        .catch(error => {
            this.isLoading = false;
            // Diksha: Added safer error message display to capture validation rules from Salesforce
            const errorMessage = error?.body?.message || error?.message || 'An unknown error occurred';
            this.showToast('Error', errorMessage, 'error');
        });
    }
    // Changes made by Diksha: END

    async handleApplyClick() {
        console.log('Apply clicked. effectiveContactId:', this.effectiveContactId);
        this.isLoading = true;
        try {
            // Cleanup rejected memberships first so the flow's "Create Records" doesn't hit a duplicate error
            if (this.effectiveContactId || !this.effectiveContactId) { // Call even if null so Apex can try to find by User
                console.log('Calling cleanupRejectedMemberships...');
                await cleanupRejectedMemberships({ contactId: this.effectiveContactId });
                console.log('Cleanup successful.');
            }
            
            this.showFlow = true;
            
            // Use setTimeout to ensure the flow component is rendered
            setTimeout(() => {
                const flow = this.template.querySelector('lightning-flow');
                if (flow) {
                    const inputs = [];
                    
                    // Pass contactId to the flow if available
                    if (this.effectiveContactId) {
                        inputs.push({ 
                            name: 'contactId', 
                            type: 'String', 
                            value: this.effectiveContactId 
                        });
                    }
                    
                    // Start the flow with the API name
                    flow.startFlow('Professional_Club_Registration', inputs);
                    this.isLoading = false;
                } else {
                    this.showToast('Error', 'Flow component not found. Please try again.', 'error');
                    this.showFlow = false;
                    this.isLoading = false;
                }
            }, 200);
        } catch (error) {
            this.isLoading = false;
            console.error('Error during apply cleanup:', error);
            const msg = error?.body?.message || error?.message || 'Error preparing registration';
            this.showToast('Error', msg, 'error');
        }
    }

    handleRequestSIGClick() {
        this.showFlow = true;
        
        // Use setTimeout to ensure the flow component is rendered
        setTimeout(() => {
            const flow = this.template.querySelector('lightning-flow');
            if (flow) {
                const inputs = [];
                
                // Pass contactId to the flow if available
                if (this.effectiveContactId) {
                    inputs.push({ 
                        name: 'contactId', 
                        type: 'String', 
                        value: this.effectiveContactId 
                    });
                }
                
                // Start the SIG request flow
                flow.startFlow('New_SIG_Request_Flow', inputs);
            } else {
                this.showToast('Error', 'Flow component not found. Please try again.', 'error');
                this.showFlow = false;
            }
        }, 200);
    }

    handleFlowStatusChange(event) {
        const status = event?.detail?.status;
        console.log('Flow status:', status);
        
        if (status === 'FINISHED' || status === 'FINISHED_SCREEN') {
            this.showFlow = false;
            // Reload memberships to show newly added registration
            this.loadAllMemberships();
            this.showToast('Success', 'Club registration completed successfully!', 'success');
        }
    }

    closeFlow() {
        this.showFlow = false;
        // Reload in case user made changes before closing
        this.loadAllMemberships();
    }

    showToast(title, message, variant = 'info') {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}