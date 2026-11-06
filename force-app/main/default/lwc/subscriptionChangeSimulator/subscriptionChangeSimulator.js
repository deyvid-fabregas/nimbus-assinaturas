import { LightningElement, api, wire } from 'lwc';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { RefreshEvent } from 'lightning/refresh';
import loadContext from '@salesforce/apex/SubscriptionChangeController.loadContext';
import simulate from '@salesforce/apex/SubscriptionChangeController.simulateJson';
import saveDraft from '@salesforce/apex/SubscriptionChangeController.saveDraftJson';

// A tela só envia INTENÇÃO; preços, deltas, totais e nível vêm do servidor.
export default class SubscriptionChangeSimulator extends LightningElement {
    @api recordId;

    context;
    contextError;
    proposedPlanId = '';
    effectiveDate;
    justification = '';
    items = [];
    addedProductId = '';
    result;
    savedRequestId;
    idempotencyKey;
    isBusy = false;
    feedback;

    @wire(loadContext, { contractId: '$recordId' })
    wiredContext({ data, error }) {
        if (data) {
            if (data.success) {
                this.context = data;
                this.contextError = undefined;
                this.items = (data.items || []).map((item) => ({
                    productId: item.productId,
                    productName: item.productName,
                    currentQuantity: item.quantity,
                    newQuantity: item.quantity,
                    added: false
                }));
            } else {
                this.context = undefined;
                this.contextError = data.message;
            }
        } else if (error) {
            this.context = undefined;
            this.contextError = this.reduceError(error);
        }
    }

    reduceError(error) {
        const body = error && error.body;
        if (body && typeof body.message === 'string') {
            return body.message;
        }
        return (error && error.message) || 'Não foi possível carregar o contrato.';
    }

    get hasContext() {
        return !!this.context;
    }

    get planOptions() {
        const none = { label: 'Manter plano atual', value: '' };
        return [none, ...(this.context ? this.context.plans : []).map((p) => ({ label: p.label, value: p.value }))];
    }

    get productOptions() {
        const used = new Set(this.items.map((i) => i.productId));
        return (this.context ? this.context.products : [])
            .filter((p) => !used.has(p.value))
            .map((p) => ({ label: p.label, value: p.value }));
    }

    get hasProductOptions() {
        return this.productOptions.length > 0;
    }

    get hasItems() {
        return this.items.length > 0;
    }

    get disableActions() {
        return this.isBusy || !this.context;
    }

    get hasResult() {
        return !!this.result;
    }

    get resultIsError() {
        return !!this.result && this.result.success === false;
    }

    get resultIsBlocked() {
        return !!this.result && this.result.success !== false && this.result.blocked === true;
    }

    get resultIsOk() {
        return !!this.result && this.result.success !== false && !this.result.blocked;
    }

    get resultLines() {
        const names = {};
        this.items.forEach((i) => {
            names[i.productId] = i.productName;
        });
        return ((this.result && this.result.lines) || []).map((line, index) => ({
            ...line,
            key: `${index}-${line.productId}`,
            productName: names[line.productId] || line.productId
        }));
    }

    get hasResultLines() {
        return this.resultLines.length > 0;
    }

    get hasPercent() {
        return !!this.result && this.result.percentVariation !== null && this.result.percentVariation !== undefined;
    }

    get percentValue() {
        return this.result.percentVariation / 100;
    }

    get hasSavedRequest() {
        return !!this.savedRequestId;
    }

    handlePlanChange(event) {
        this.proposedPlanId = event.detail.value;
    }

    handleDateChange(event) {
        this.effectiveDate = event.detail.value;
    }

    handleJustificationChange(event) {
        this.justification = event.detail.value;
    }

    handleQuantityChange(event) {
        const productId = event.target.dataset.product;
        const value = event.detail.value;
        this.items = this.items.map((item) =>
            item.productId === productId ? { ...item, newQuantity: value === '' ? null : Number(value) } : item
        );
    }

    handleAddedProductChange(event) {
        this.addedProductId = event.detail.value;
    }

    handleAddProduct() {
        if (!this.addedProductId) {
            return;
        }
        const option = this.context.products.find((p) => p.value === this.addedProductId);
        this.items = [
            ...this.items,
            {
                productId: this.addedProductId,
                productName: option ? option.label : this.addedProductId,
                currentQuantity: 0,
                newQuantity: 1,
                added: true
            }
        ];
        this.addedProductId = '';
    }

    handleRemoveAdded(event) {
        const productId = event.target.dataset.product;
        this.items = this.items.filter((item) => item.productId !== productId);
    }

    buildRequest() {
        const changed = [];
        this.items.forEach((item) => {
            if (item.added) {
                changed.push({ productId: item.productId, action: 'Adicionar', newQuantity: item.newQuantity });
            } else if (item.newQuantity === null || item.newQuantity === 0) {
                changed.push({ productId: item.productId, action: 'Remover', newQuantity: 0 });
            } else if (item.newQuantity !== item.currentQuantity) {
                changed.push({ productId: item.productId, action: 'Alterar Quantidade', newQuantity: item.newQuantity });
            }
        });
        return {
            requestId: this.savedRequestId,
            contractId: this.recordId,
            proposedPlanId: this.proposedPlanId || null,
            effectiveDate: this.effectiveDate,
            justification: this.justification,
            idempotencyKey: this.ensureKey(),
            items: changed
        };
    }

    ensureKey() {
        if (!this.idempotencyKey) {
            this.idempotencyKey = `${this.recordId}-${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;
        }
        return this.idempotencyKey;
    }

    async handleSimulate(event) {
        if (event && event.preventDefault) {
            event.preventDefault();
        }
        await this.run(simulate, false);
    }

    async handleSave() {
        await this.run(saveDraft, true);
    }

    async run(method, persist) {
        this.isBusy = true;
        this.feedback = undefined;
        try {
            this.result = await method({ requestJson: JSON.stringify(this.buildRequest()) });
        } catch (error) {
            this.result = { success: false, message: this.reduceError(error) };
        } finally {
            this.isBusy = false;
        }
        if (persist && this.result.success !== false && this.result.requestId) {
            this.savedRequestId = this.result.requestId;
            this.feedback = this.result.reusedExisting
                ? 'Rascunho já existente devolvido (mesma chave de idempotência).'
                : 'Rascunho salvo.';
            await this.afterSave();
        }
    }

    async afterSave() {
        try {
            await notifyRecordUpdateAvailable([{ recordId: this.recordId }, { recordId: this.savedRequestId }]);
        } catch (e) {
            // falha de cache não invalida o rascunho salvo
        }
        this.dispatchEvent(new RefreshEvent());
        this.dispatchEvent(new CustomEvent('draftsaved', { detail: { requestId: this.savedRequestId, contractId: this.recordId } }));
    }
}
