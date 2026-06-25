import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

export default class RaiseCaseComponent extends NavigationMixin(LightningElement) {
    @api recordId; // Kept for backward compatibility but not used
    @api showButton;
    
    get showRaiseCase() {
        return this.showButton !== false;
    }
    
    disableRaiseCaseButton = false;

    navigateToRaiseCase() {
        // Navigate to the community page
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: {
                url: '/caseloaform'
            }
        });
    }
}