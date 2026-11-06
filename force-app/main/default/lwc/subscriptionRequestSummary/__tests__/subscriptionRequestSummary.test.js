import { createElement } from 'lwc';
import SubscriptionRequestSummary from 'c/subscriptionRequestSummary';
import getSummary from '@salesforce/apex/SubscriptionRequestSummaryController.getSummary';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { registerRefreshHandler, unregisterRefreshHandler } from 'lightning/refresh';

jest.mock(
    '@salesforce/apex/SubscriptionRequestSummaryController.getSummary',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    'lightning/uiRecordApi',
    () => ({ notifyRecordUpdateAvailable: jest.fn(() => Promise.resolve()) }),
    { virtual: true }
);
jest.mock(
    'lightning/refresh',
    () => {
        class RefreshEvent extends CustomEvent {
            constructor() {
                super('lightning__refresh', { bubbles: true, composed: true });
            }
        }
        return {
            RefreshEvent,
            registerRefreshHandler: jest.fn(() => 'handler-1'),
            unregisterRefreshHandler: jest.fn()
        };
    },
    { virtual: true }
);

const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

const baseSummary = (overrides = {}) => ({
    requestId: 'a01000000000001AAA',
    name: 'SOL-0001',
    status: 'Pendente',
    cycle: 1,
    contractName: 'CT-0001',
    currentPlanName: 'Basic',
    proposedPlanName: 'Pro',
    baseMrr: 1000,
    proposedMrr: 1200,
    absoluteVariation: 200,
    percentVariation: 20,
    approvalLevel: 'Gerente',
    expectedResponsible: 'Gerente Comercial',
    requesterName: 'Ana',
    effectiveDate: '2030-01-01',
    justification: 'Crescimento do cliente',
    lines: [
        { productName: 'Licença', action: 'Alterar Quantidade', currentQuantity: 5, newQuantity: 8, deltaMrr: 300 },
        { productName: 'Suporte', action: 'Remover', currentQuantity: 1, newQuantity: 0, deltaMrr: -100 }
    ],
    canSubmit: false,
    canDecide: false,
    canApply: false,
    canReopen: false,
    ...overrides
});

const mount = async (recordId = 'a01000000000001AAA') => {
    const element = createElement('c-subscription-request-summary', { is: SubscriptionRequestSummary });
    element.recordId = recordId;
    document.body.appendChild(element);
    await flushPromises();
    return element;
};

describe('c-subscription-request-summary', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('renderiza o resumo devolvido pelo servidor', async () => {
        getSummary.mockResolvedValue(baseSummary());
        const element = await mount();

        expect(getSummary).toHaveBeenCalledWith({ requestId: 'a01000000000001AAA' });
        expect(element.shadowRoot.querySelector('[data-id="name"]').textContent).toBe('SOL-0001');
        expect(element.shadowRoot.querySelector('[data-id="level"]').textContent).toBe('Gerente');
        expect(element.shadowRoot.querySelector('[data-id="proposed-plan"]').textContent).toBe('Pro');
        expect(element.shadowRoot.querySelector('lightning-badge').label).toBe('Pendente');
    });

    it('mostra a tabela de itens com caption acessível e cabeçalhos com scope', async () => {
        getSummary.mockResolvedValue(baseSummary());
        const element = await mount();

        const table = element.shadowRoot.querySelector('[data-id="lines"]');
        expect(table.querySelector('caption').textContent).toBe('Itens da solicitação');
        expect(table.querySelectorAll('tbody tr').length).toBe(2);
        table.querySelectorAll('thead th').forEach((th) => expect(th.getAttribute('scope')).toBe('col'));
    });

    it('não exibe tabela, plano proposto nem motivo quando não há dados', async () => {
        getSummary.mockResolvedValue(baseSummary({ lines: [], proposedPlanName: null, percentVariation: null }));
        const element = await mount();

        expect(element.shadowRoot.querySelector('[data-id="lines"]')).toBeNull();
        expect(element.shadowRoot.querySelector('[data-id="proposed-plan"]')).toBeNull();
        expect(element.shadowRoot.querySelector('[data-id="rejection"]')).toBeNull();
    });

    it('exibe o motivo da rejeição quando existe', async () => {
        getSummary.mockResolvedValue(baseSummary({ status: 'Rejeitada', rejectionReason: 'Fora da política' }));
        const element = await mount();

        expect(element.shadowRoot.querySelector('[data-id="rejection"]').textContent).toBe('Fora da política');
    });

    it('mostra apenas os botões liberados pelos indicadores do servidor', async () => {
        getSummary.mockResolvedValue(baseSummary({ canDecide: true, canReopen: true }));
        const element = await mount();

        const labels = Array.from(element.shadowRoot.querySelectorAll('lightning-button')).map((b) => b.label);
        expect(labels).toEqual(['Decidir', 'Reabrir']);
        expect(element.shadowRoot.querySelector('[data-id="reason"]')).toBeNull();
    });

    it('exibe o motivo de indisponibilidade quando nenhuma ação está liberada', async () => {
        getSummary.mockResolvedValue(baseSummary({ unavailableReason: 'Sem permissão para decidir.' }));
        const element = await mount();

        expect(element.shadowRoot.querySelectorAll('lightning-button').length).toBe(0);
        expect(element.shadowRoot.querySelector('[data-id="reason"]').textContent).toBe('Sem permissão para decidir.');
    });

    it('exibe erro do servidor em role=alert', async () => {
        getSummary.mockRejectedValue({ body: { message: 'Solicitação não encontrada.' } });
        const element = await mount();

        const alert = element.shadowRoot.querySelector('[data-id="error"]');
        expect(alert.getAttribute('role')).toBe('alert');
        expect(alert.textContent).toBe('Solicitação não encontrada.');
        expect(element.shadowRoot.querySelector('[data-id="name"]')).toBeNull();
    });

    it('usa mensagem padrão quando o erro não tem corpo', async () => {
        getSummary.mockRejectedValue({});
        const element = await mount();

        expect(element.shadowRoot.querySelector('[data-id="error"]').textContent).toContain('Não foi possível');
    });

    it('usa error.message quando não há body', async () => {
        getSummary.mockRejectedValue({ message: 'falha de rede' });
        const element = await mount();

        expect(element.shadowRoot.querySelector('[data-id="error"]').textContent).toBe('falha de rede');
    });

    it('não chama o servidor sem recordId', async () => {
        await mount(null);

        expect(getSummary).not.toHaveBeenCalled();
    });

    it('registra e remove o handler de refresh', async () => {
        getSummary.mockResolvedValue(baseSummary());
        await mount();
        expect(registerRefreshHandler).toHaveBeenCalledTimes(1);

        document.body.removeChild(document.body.firstChild);
        expect(unregisterRefreshHandler).toHaveBeenCalledWith('handler-1');
    });

    it('recarrega pelo handler de refresh e pelo método público', async () => {
        getSummary.mockResolvedValue(baseSummary());
        const element = await mount();
        const handler = registerRefreshHandler.mock.calls[0][1];

        await handler();
        await element.refresh();
        expect(getSummary).toHaveBeenCalledTimes(3);
    });

    it('abre o Screen Flow correto com recordId e fecha pelo botão', async () => {
        getSummary.mockResolvedValue(baseSummary({ canApply: true }));
        const element = await mount();

        element.shadowRoot.querySelector('lightning-button[data-action="apply"]').click();
        await flushPromises();

        const flow = element.shadowRoot.querySelector('lightning-flow');
        expect(flow.flowApiName).toBe('Aplicar_Alteracao_Aprovada');
        expect(flow.flowInputVariables).toEqual([{ name: 'recordId', type: 'String', value: 'a01000000000001AAA' }]);
        const dialog = element.shadowRoot.querySelector('[data-id="flow-panel"]');
        expect(dialog.getAttribute('role')).toBe('dialog');
        expect(dialog.getAttribute('aria-label')).toBe('Aplicar alteração');

        element.shadowRoot.querySelector('[data-id="close-flow"]').click();
        await flushPromises();
        expect(element.shadowRoot.querySelector('lightning-flow')).toBeNull();
    });

    it('ao finalizar o Flow notifica o cache, recarrega e dispara eventos', async () => {
        getSummary.mockResolvedValueOnce(baseSummary({ canDecide: true }));
        getSummary.mockResolvedValueOnce(baseSummary({ status: 'Aprovada' }));
        const element = await mount();
        const completed = jest.fn();
        const refreshed = jest.fn();
        element.addEventListener('flowcompleted', completed);
        element.addEventListener('lightning__refresh', refreshed);

        element.shadowRoot.querySelector('lightning-button[data-action="decide"]').click();
        await flushPromises();
        element.shadowRoot
            .querySelector('lightning-flow')
            .dispatchEvent(new CustomEvent('statuschange', { detail: { status: 'FINISHED' } }));
        await flushPromises();

        expect(notifyRecordUpdateAvailable).toHaveBeenCalledWith([{ recordId: 'a01000000000001AAA' }]);
        expect(getSummary).toHaveBeenCalledTimes(2);
        expect(completed).toHaveBeenCalledTimes(1);
        expect(completed.mock.calls[0][0].detail.status).toBe('Aprovada');
        expect(refreshed).toHaveBeenCalledTimes(1);
        expect(element.shadowRoot.querySelector('lightning-flow')).toBeNull();
    });

    it('ignora mudanças de status do Flow que não são final e tolera falha ao notificar', async () => {
        getSummary.mockResolvedValue(baseSummary({ canSubmit: true }));
        notifyRecordUpdateAvailable.mockRejectedValueOnce(new Error('cache'));
        const element = await mount();

        element.shadowRoot.querySelector('lightning-button[data-action="submit"]').click();
        await flushPromises();
        const flow = element.shadowRoot.querySelector('lightning-flow');
        flow.dispatchEvent(new CustomEvent('statuschange', { detail: { status: 'STARTED' } }));
        await flushPromises();
        expect(element.shadowRoot.querySelector('lightning-flow')).not.toBeNull();
        expect(notifyRecordUpdateAvailable).not.toHaveBeenCalled();

        flow.dispatchEvent(new CustomEvent('statuschange', { detail: { status: 'FINISHED_SCREEN' } }));
        await flushPromises();
        expect(element.shadowRoot.querySelector('lightning-flow')).toBeNull();
    });
});
