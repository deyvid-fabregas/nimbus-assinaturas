import { createElement } from 'lwc';
import SubscriptionChangeSimulator from 'c/subscriptionChangeSimulator';
import simulate from '@salesforce/apex/SubscriptionChangeController.simulateJson';
import saveDraft from '@salesforce/apex/SubscriptionChangeController.saveDraftJson';
import loadContext from '@salesforce/apex/SubscriptionChangeController.loadContext';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';

jest.mock(
    '@salesforce/apex/SubscriptionChangeController.loadContext',
    () => {
        const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);
jest.mock('@salesforce/apex/SubscriptionChangeController.simulateJson', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/SubscriptionChangeController.saveDraftJson', () => ({ default: jest.fn() }), { virtual: true });
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
        return { RefreshEvent };
    },
    { virtual: true }
);

const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

const CONTEXT = {
    success: true,
    contractId: 'a00000000000001AAA',
    contractName: 'CT-0001',
    contractStatus: 'Ativo',
    currentPlanName: 'Basic',
    plans: [{ value: 'a02000000000001AAA', label: 'Pro' }],
    products: [{ value: '01t000000000002AAA', label: 'Extra' }],
    items: [{ productId: '01t000000000001AAA', productName: 'Licença', quantity: 5 }]
};

const okResult = (overrides = {}) => ({
    success: true,
    blocked: false,
    baseMrr: 500,
    proposedMrr: 800,
    absoluteVariation: 300,
    percentVariation: 60,
    approvalLevel: 'Gerente',
    responsibleName: 'Gerente Comercial',
    lines: [{ productId: '01t000000000001AAA', action: 'Alterar Quantidade', newQuantity: 8, deltaMrr: 300 }],
    ...overrides
});

const mount = async (context = CONTEXT) => {
    const element = createElement('c-subscription-change-simulator', { is: SubscriptionChangeSimulator });
    element.recordId = 'a00000000000001AAA';
    document.body.appendChild(element);
    loadContext.emit(context);
    await flushPromises();
    return element;
};

const setQuantity = async (element, productId, value) => {
    const input = element.shadowRoot.querySelector(`lightning-input[data-product="${productId}"]`);
    input.dispatchEvent(new CustomEvent('change', { detail: { value } }));
    await flushPromises();
};

describe('c-subscription-change-simulator', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('renderiza contrato, itens e opções vindos do servidor', async () => {
        const element = await mount();

        expect(element.shadowRoot.querySelector('[data-id="contract-info"]').textContent).toContain('CT-0001');
        expect(element.shadowRoot.querySelectorAll('[data-id="item-row"]').length).toBe(1);
        expect(element.shadowRoot.querySelector('[data-id="plan"]').options.map((o) => o.label)).toEqual([
            'Manter plano atual',
            'Pro'
        ]);
    });

    it('mostra erro de contexto em role=alert e desabilita ações', async () => {
        const element = await mount({ success: false, message: 'Contrato não encontrado.' });

        expect(element.shadowRoot.querySelector('[data-id="context-error"]').getAttribute('role')).toBe('alert');
        expect(element.shadowRoot.querySelector('[data-id="simulate"]')).toBeNull();
    });

    it('simula enviando somente a intenção (itens alterados) e exibe valores do servidor', async () => {
        simulate.mockResolvedValue(okResult());
        const element = await mount();
        await setQuantity(element, '01t000000000001AAA', 8);
        element.shadowRoot
            .querySelector('[data-id="justification"]')
            .dispatchEvent(new CustomEvent('change', { detail: { value: 'Mais licenças' } }));
        element.shadowRoot
            .querySelector('[data-id="date"]')
            .dispatchEvent(new CustomEvent('change', { detail: { value: '2030-01-01' } }));
        element.shadowRoot
            .querySelector('[data-id="plan"]')
            .dispatchEvent(new CustomEvent('change', { detail: { value: 'a02000000000001AAA' } }));

        element.shadowRoot.querySelector('[data-id="simulate"]').click();
        await flushPromises();

        const request = JSON.parse(simulate.mock.calls[0][0].requestJson);
        expect(request.items).toEqual([{ productId: '01t000000000001AAA', action: 'Alterar Quantidade', newQuantity: 8 }]);
        expect(request.proposedPlanId).toBe('a02000000000001AAA');
        expect(request.justification).toBe('Mais licenças');
        expect(request.effectiveDate).toBe('2030-01-01');
        expect(request).not.toHaveProperty('proposedMrr');
        expect(element.shadowRoot.querySelector('[data-id="level"]').textContent).toBe('Gerente');
        expect(element.shadowRoot.querySelectorAll('[data-id="result-lines"] tbody tr').length).toBe(1);
        expect(saveDraft).not.toHaveBeenCalled();
    });

    it('quantidade zero ou vazia vira Remover', async () => {
        simulate.mockResolvedValue(okResult());
        const element = await mount();
        await setQuantity(element, '01t000000000001AAA', '');

        element.shadowRoot.querySelector('[data-id="simulate"]').click();
        await flushPromises();

        expect(JSON.parse(simulate.mock.calls[0][0].requestJson).items).toEqual([
            { productId: '01t000000000001AAA', action: 'Remover', newQuantity: 0 }
        ]);
    });

    it('sem alterações envia lista de itens vazia e plano nulo', async () => {
        simulate.mockResolvedValue(okResult({ lines: [], percentVariation: null }));
        const element = await mount();

        element.shadowRoot.querySelector('[data-id="simulate"]').click();
        await flushPromises();

        const request = JSON.parse(simulate.mock.calls[0][0].requestJson);
        expect(request.items).toEqual([]);
        expect(request.proposedPlanId).toBeNull();
        expect(element.shadowRoot.querySelector('[data-id="result-lines"]')).toBeNull();
    });

    it('adiciona e remove produto novo', async () => {
        simulate.mockResolvedValue(okResult());
        const element = await mount();

        element.shadowRoot.querySelector('[data-id="add-button"]').click();
        await flushPromises();
        expect(element.shadowRoot.querySelectorAll('[data-id="item-row"]').length).toBe(1);

        element.shadowRoot
            .querySelector('[data-id="add-product"]')
            .dispatchEvent(new CustomEvent('change', { detail: { value: '01t000000000002AAA' } }));
        await flushPromises();
        element.shadowRoot.querySelector('[data-id="add-button"]').click();
        await flushPromises();
        expect(element.shadowRoot.querySelectorAll('[data-id="item-row"]').length).toBe(2);
        expect(element.shadowRoot.querySelector('[data-id="add-product"]')).toBeNull();

        element.shadowRoot.querySelector('[data-id="simulate"]').click();
        await flushPromises();
        expect(JSON.parse(simulate.mock.calls[0][0].requestJson).items).toEqual([
            { productId: '01t000000000002AAA', action: 'Adicionar', newQuantity: 1 }
        ]);

        element.shadowRoot.querySelector('[data-id="remove-added"]').click();
        await flushPromises();
        expect(element.shadowRoot.querySelectorAll('[data-id="item-row"]').length).toBe(1);
    });

    it('exibe falha de negócio devolvida pelo servidor', async () => {
        simulate.mockResolvedValue({ success: false, errorCode: 'DATA_RETROATIVA', message: 'Data retroativa.' });
        const element = await mount();

        element.shadowRoot.querySelector('[data-id="simulate"]').click();
        await flushPromises();

        expect(element.shadowRoot.querySelector('[data-id="result-error"]').textContent).toBe('Data retroativa.');
        expect(element.shadowRoot.querySelector('[data-id="result"]')).toBeNull();
    });

    it('exibe bloqueio do servidor sem mostrar totais', async () => {
        simulate.mockResolvedValue(okResult({ blocked: true, blockMessage: 'Variação acima do limite.' }));
        const element = await mount();

        element.shadowRoot.querySelector('[data-id="simulate"]').click();
        await flushPromises();

        expect(element.shadowRoot.querySelector('[data-id="result-blocked"]').textContent).toBe('Variação acima do limite.');
        expect(element.shadowRoot.querySelector('[data-id="result"]')).toBeNull();
    });

    it('trata exceção de rede como erro amigável', async () => {
        simulate.mockRejectedValue({ body: { message: 'Falha' } });
        const element = await mount();

        element.shadowRoot.querySelector('[data-id="simulate"]').click();
        await flushPromises();

        expect(element.shadowRoot.querySelector('[data-id="result-error"]').textContent).toBe('Falha');
    });

    it('salva rascunho, notifica o cache, dispara eventos e reutiliza requestId e chave', async () => {
        saveDraft.mockResolvedValue(okResult({ requestId: 'a01000000000009AAA', reusedExisting: false }));
        const element = await mount();
        const saved = jest.fn();
        const refreshed = jest.fn();
        element.addEventListener('draftsaved', saved);
        element.addEventListener('lightning__refresh', refreshed);

        element.shadowRoot.querySelector('[data-id="save"]').click();
        await flushPromises();
        element.shadowRoot.querySelector('[data-id="save"]').click();
        await flushPromises();

        const first = JSON.parse(saveDraft.mock.calls[0][0].requestJson);
        const second = JSON.parse(saveDraft.mock.calls[1][0].requestJson);
        expect(first.requestId).toBeUndefined();
        expect(first.idempotencyKey).toBeTruthy();
        expect(second.requestId).toBe('a01000000000009AAA');
        expect(second.idempotencyKey).toBe(first.idempotencyKey);
        expect(notifyRecordUpdateAvailable).toHaveBeenCalledWith([
            { recordId: 'a00000000000001AAA' },
            { recordId: 'a01000000000009AAA' }
        ]);
        expect(saved).toHaveBeenCalledTimes(2);
        expect(refreshed).toHaveBeenCalledTimes(2);
        expect(element.shadowRoot.querySelector('[data-id="feedback"]').textContent).toBe('Rascunho salvo.');
    });

    it('informa quando o servidor devolve rascunho existente (idempotência)', async () => {
        saveDraft.mockResolvedValue(okResult({ requestId: 'a01000000000009AAA', reusedExisting: true }));
        notifyRecordUpdateAvailable.mockRejectedValueOnce(new Error('cache'));
        const element = await mount();

        element.shadowRoot.querySelector('[data-id="save"]').click();
        await flushPromises();

        expect(element.shadowRoot.querySelector('[data-id="feedback"]').textContent).toContain('já existente');
    });

    it('não considera salvo quando o servidor devolve falha', async () => {
        saveDraft.mockResolvedValue({ success: false, message: 'Justificativa curta.' });
        const element = await mount();
        const saved = jest.fn();
        element.addEventListener('draftsaved', saved);

        element.shadowRoot.querySelector('[data-id="save"]').click();
        await flushPromises();

        expect(saved).not.toHaveBeenCalled();
        expect(notifyRecordUpdateAvailable).not.toHaveBeenCalled();
        expect(element.shadowRoot.querySelector('[data-id="result-error"]').textContent).toBe('Justificativa curta.');
    });

    it('trata erro do wire de contexto', async () => {
        const element = createElement('c-subscription-change-simulator', { is: SubscriptionChangeSimulator });
        element.recordId = 'a00000000000001AAA';
        document.body.appendChild(element);
        loadContext.error({ message: 'sem acesso' });
        await flushPromises();

        expect(element.shadowRoot.querySelector('[data-id="context-error"]').textContent).toBe('sem acesso');
    });
});
