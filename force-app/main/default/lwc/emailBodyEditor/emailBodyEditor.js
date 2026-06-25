import { LightningElement, api, track } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';

export default class EmailBodyEditor extends LightningElement {

    // Input from Flow - the rendered HTML from RenderEmailTemplateAction
    @api htmlBody = '';

    // Output back to Flow - the edited HTML
    @api editedHtmlBody = '';

    @track _value = '';

    connectedCallback() {
        // Initialize editor with the HTML body passed from flow
        this._value = this.htmlBody || '';
        this.editedHtmlBody = this._value;
    }

    handleChange(event) {
        this._value = event.target.value;
        this.editedHtmlBody = this._value;

        // Notify flow of the updated value
        const attributeChangeEvent = new FlowAttributeChangeEvent('editedHtmlBody', this._value);
        this.dispatchEvent(attributeChangeEvent);
    }
}