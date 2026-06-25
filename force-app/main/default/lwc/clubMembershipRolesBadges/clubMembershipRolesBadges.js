import { LightningElement, api, track } from 'lwc';
import getClubMembershipRoles from '@salesforce/apex/ClubMembershipRolesController.getClubMembershipRoles';
import getProfessionalMemberships from '@salesforce/apex/ClubMembershipController.getProfessionalMemberships';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class ClubMembershipRolesBadges extends LightningElement {
    @api contactId;
    @api recordId;
    @track roles = [];
    @track otherMemberships = [];
    @track professionalCount = 0;
    @track isLoading = true;

    connectedCallback() {
        this.isLoading = true;
        Promise.all([
            this.loadRoles(),
            this.loadProfessionalCount()
        ])
        .then(() => {
            this.isLoading = false;
        })
        .catch(error => {
            this.isLoading = false;
            console.error('Error loading roles/count:', error);
        });
    }

    get effectiveContactId() {
        if (this.contactId) return this.contactId;
        if (this.recordId) return this.recordId;
        return null;
    }

    get hasRoles() {
        return Array.isArray(this.roles) && this.roles.length > 0;
    }

    loadRoles() {
        return getClubMembershipRoles({ contactId: this.effectiveContactId })
            .then(result => {
                console.log('Roles result:', JSON.stringify(result));

                // Create badges for each membership with club name and role
                this.roles = [];

                if (result.memberships && Array.isArray(result.memberships)) {
                    result.memberships.forEach((membership, index) => {
                        if (membership.role && membership.clubName) {
                            const label = membership.clubName + ' - ' + membership.role;
                            this.roles.push({
                                label: label,
                                title: label,
                                badgeClass: this.getBadgeClass(index)
                            });
                        }
                    });
                }

                if (result.debugMessage) {
                    console.log('Debug:', result.debugMessage);
                }
            })
            .catch(error => {
                this.roles = [];
                console.error('Error loading roles:', error);

                const errorMessage = error?.body?.message || error?.message || 'Unknown error occurred';
                this.showToast('Error Loading Roles', errorMessage, 'error');
            });
    }

    loadProfessionalCount() {
        return getProfessionalMemberships({ contactId: this.effectiveContactId })
            .then(result => {
                // The Apex returns a MembershipResponse with 'count' and memberships
                if (result && typeof result.count === 'number') {
                    this.professionalCount = result.count;
                } else if (result && Array.isArray(result.memberships)) {
                    this.professionalCount = result.memberships.length;
                } else {
                    this.professionalCount = 0;
                }
            })
            .catch(error => {
                this.professionalCount = 0;
                console.error('Error loading professional membership count:', error);
            });
    }

    getBadgeClass(index) {
        // Array of colorful badge classes using SLDS
        const badgeClasses = [
            'slds-badge slds-theme_success',      // Green
            'slds-badge slds-theme_info',         // Blue
            'slds-badge slds-theme_warning',      // Orange
            'slds-badge slds-theme_error',        // Red
            'slds-badge slds-theme_offline',      // Gray
            'slds-badge slds-theme_default'       // Default
        ];
        
        // Cycle through colors if more roles than colors
        return badgeClasses[index % badgeClasses.length];
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