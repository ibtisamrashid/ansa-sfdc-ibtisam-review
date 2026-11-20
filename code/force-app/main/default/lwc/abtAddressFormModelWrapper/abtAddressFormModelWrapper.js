import { LightningElement, api } from 'lwc';

export default class AbtModal extends LightningElement {
    @api title = '';

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }
}