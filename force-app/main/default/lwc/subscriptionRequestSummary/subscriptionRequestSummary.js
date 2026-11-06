import { LightningElement, api } from 'lwc';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { RefreshEvent, registerRefreshHandler, unregisterRefreshHandler } from 'lightning/refresh';
import getSummary from '@salesforce/apex/SubscriptionRequestSummaryController.getSummary';

const FLOWS = {
    submit: { apiName: 'Enviar_Solicitacao_Aprovacao', label: 'Enviar para aprovação', variant: 'brand' },
    decide: { apiName: 'Decidir_Solicitacao_Alteracao', label: 'Decidir', variant: 'brand' },
    apply: { apiName: 'Aplicar_Alteracao_Aprovada', label: 'Aplicar alteração', variant: 'brand' },
    reopen: { apiName: 'Reabrir_Solicitacao_Alteracao', label: 'Reabrir', variant: 'neutral' }
};

const FINISHED = ['FINISHED', 'FINISHED_SCREEN'];

export default class SubscriptionRequestSummary extends LightningElement {
    @api recordId;

    summary;
    errorMessage;
    isLoading = false;
    activeFlow;
    refreshHandlerId;

    connectedCallback() {
        this.refreshHandlerId = registerRefreshHandler(this, () => this.load());
        this.load();
    }

    disconnectedCallback() {
        unregisterRefreshHandler(this.refreshHandlerId);
    }

    @api
    refresh() {
        return this.load();
    }

    async load() {
        if (!this.recordId) {
            return;
        }
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            this.summary = await getSummary({ requestId: this.recordId });
        } catch (error) {
            this.summary = undefined;
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    reduceError(error) {
        const body = error && error.body;
        if (body && typeof body.message === 'string') {
            return body.message;
        }
        if (error && typeof error.message === 'string') {
            return error.message;
        }
        return 'Não foi possível carregar o resumo da solicitação.';
    }

    get hasSummary() {
        return !!this.summary;
    }

    get hasLines() {
        return !!(this.summary && this.summary.lines && this.summary.lines.length);
    }

    get lines() {
        return (this.summary.lines || []).map((line, index) => ({
            ...line,
            key: `${index}-${line.productName}`,
            deltaClass: line.deltaMrr < 0 ? 'slds-text-color_error' : ''
        }));
    }

    get actions() {
        if (!this.summary) {
            return [];
        }
        const flags = {
            submit: this.summary.canSubmit,
            decide: this.summary.canDecide,
            apply: this.summary.canApply,
            reopen: this.summary.canReopen
        };
        return Object.keys(FLOWS)
            .filter((key) => flags[key])
            .map((key) => ({ key, ...FLOWS[key] }));
    }

    get hasActions() {
        return this.actions.length > 0;
    }

    get showUnavailableReason() {
        return !this.hasActions && !!(this.summary && this.summary.unavailableReason);
    }

    get hasRejectionReason() {
        return !!(this.summary && this.summary.rejectionReason);
    }

    get hasPercentVariation() {
        return !!(this.summary && this.summary.percentVariation !== null && this.summary.percentVariation !== undefined);
    }

    get percentValue() {
        return this.summary.percentVariation / 100;
    }

    get proposedPlanChanged() {
        return !!(this.summary && this.summary.proposedPlanName);
    }

    get isFlowOpen() {
        return !!this.activeFlow;
    }

    get flowTitle() {
        return this.activeFlow ? this.activeFlow.label : '';
    }

    get flowInputs() {
        return [{ name: 'recordId', type: 'String', value: this.recordId }];
    }

    handleAction(event) {
        const key = event.currentTarget.dataset.action;
        this.activeFlow = FLOWS[key];
    }

    handleCloseFlow() {
        this.activeFlow = undefined;
    }

    async handleFlowStatusChange(event) {
        const status = event.detail && event.detail.status;
        if (FINISHED.includes(status)) {
            this.activeFlow = undefined;
            await this.afterFlow();
        }
    }

    async afterFlow() {
        try {
            await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        } catch (e) {
            // a falha em notificar o cache não deve esconder o resultado do Flow
        }
        await this.load();
        this.dispatchEvent(new RefreshEvent());
        this.dispatchEvent(
            new CustomEvent('flowcompleted', { detail: { recordId: this.recordId, status: this.summary && this.summary.status } })
        );
    }
}
