/**
 * @description Fotografia (somente leitura apos montada) de tudo que as regras de item precisam para um
 *              contrato: plano atual/proposto, itens ATIVOS e precos de catalogo. Montada em lote por
 *              ChangeContextLoader (unico lugar com SOQL); consumida por dominio PURO (ItemResolutionPolicy,
 *              ChangePlanner). Assim Trigger, Service e submissao usam exatamente as mesmas regras.
 */
public with sharing class ChangeContext {
    public Contrato_Assinatura__c contract;
    public Plano_Assinatura__c currentPlan;
    /** Plano solicitado ja carregado; null se nao solicitado ou nao encontrado (ver requestedPlanId). */
    public Plano_Assinatura__c proposedPlan;
    public Id requestedPlanId;
    public Map<Id, Item_Contrato__c> activeItemsById = new Map<Id, Item_Contrato__c>();
    public Map<Id, Item_Contrato__c> activeItemsByProduct = new Map<Id, Item_Contrato__c>();
    /** Produto -> preco mensal do Pricebook efetivo do contrato (somente produtos consultados). */
    public Map<Id, Decimal> catalogPriceByProduct = new Map<Id, Decimal>();

    public void addActiveItem(Item_Contrato__c item) {
        activeItemsById.put(item.Id, item);
        activeItemsByProduct.put(item.Produto__c, item);
    }

    public Boolean isPlanChange() {
        return proposedPlan != null && currentPlan != null && proposedPlan.Id != currentPlan.Id;
    }

    /** Plano que vale depois da alteracao: o proposto (se houver troca) ou o atual. */
    public Plano_Assinatura__c effectivePlan() {
        return isPlanChange() ? proposedPlan : currentPlan;
    }

    /** MRR do contrato = soma do MRR dos itens ativos (mesma base do agregado usado no snapshot). */
    public Decimal baseMrr() {
        List<Decimal> values = new List<Decimal>();
        for (Item_Contrato__c item : activeItemsById.values()) {
            values.add(item.MRR_Item__c);
        }
        return MrrCalculator.contractMrr(values);
    }

    /** Falha segura: plano atual inacessivel, plano proposto inexistente/inativo. */
    public void requireResolvedPlans() {
        if (currentPlan == null) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_NAO_ENCONTRADO,
                'O plano atual do contrato não foi encontrado ou você não tem acesso a ele.'
            );
        }
        if (requestedPlanId != null && proposedPlan == null) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_PLANO_INATIVO,
                'O plano proposto não existe ou não está disponível para você.'
            );
        }
        if (isPlanChange()) {
            ChangeRequestPolicy.requireActivePlan(proposedPlan.Ativo__c);
        }
    }
}
