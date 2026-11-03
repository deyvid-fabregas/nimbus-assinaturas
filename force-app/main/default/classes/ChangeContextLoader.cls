/**
 * @description UNICO ponto que monta ChangeContext (consultas em LOTE via Selectors).
 *              Custo fixo, independente do numero de solicitacoes do lote:
 *              contratos (1) + planos (1) + itens ativos (1) + [pricebook padrao (0-1) + entradas (0-1),
 *              somente quando ha produtos a precificar]  => no maximo 5 SOQL.
 *              Chave do mapa e livre (Id da solicitacao em Trigger; 'draft' no Service) para o mesmo
 *              carregador servir simulacao (sem registro) e lote de Trigger.
 */
public with sharing class ChangeContextLoader {

    public class Spec {
        public Id contractId;
        public Id proposedPlanId;

        public Spec(Id contractId, Id proposedPlanId) {
            this.contractId = contractId;
            this.proposedPlanId = proposedPlanId;
        }
    }

    private final ContractSelector contractSelector = new ContractSelector();
    private final PlanSelector planSelector = new PlanSelector();
    private final ContractItemSelector itemSelector = new ContractItemSelector();
    private final PricebookResolver pricebookResolver = new PricebookResolver();

    /** Chaves cujo contrato nao e encontrado/acessivel ficam AUSENTES do resultado (chamador trata). */
    public Map<String, ChangeContext> load(Map<String, Spec> specs, Set<Id> productIdsToPrice) {
        Map<String, ChangeContext> result = new Map<String, ChangeContext>();
        if (specs == null || specs.isEmpty()) {
            return result;
        }
        Set<Id> contractIds = new Set<Id>();
        Set<Id> planIds = new Set<Id>();
        for (Spec spec : specs.values()) {
            if (spec.contractId != null) {
                contractIds.add(spec.contractId);
            }
            if (spec.proposedPlanId != null) {
                planIds.add(spec.proposedPlanId);
            }
        }
        Map<Id, Contrato_Assinatura__c> contracts = contractSelector.mapByIds(contractIds);
        for (Contrato_Assinatura__c contract : contracts.values()) {
            if (contract.Plano_Atual__c != null) {
                planIds.add(contract.Plano_Atual__c);
            }
        }
        Map<Id, Plano_Assinatura__c> plans = planSelector.mapByIds(planIds);

        Map<Id, List<Item_Contrato__c>> itemsByContract = new Map<Id, List<Item_Contrato__c>>();
        for (Item_Contrato__c item : itemSelector.selectActiveByContractIds(contracts.keySet())) {
            List<Item_Contrato__c> bucket = itemsByContract.get(item.Contrato__c);
            if (bucket == null) {
                bucket = new List<Item_Contrato__c>();
                itemsByContract.put(item.Contrato__c, bucket);
            }
            bucket.add(item);
        }
        Map<Id, Map<Id, Decimal>> prices = pricebookResolver.resolveUnitPrices(contracts.values(), productIdsToPrice);

        for (String key : specs.keySet()) {
            Spec spec = specs.get(key);
            Contrato_Assinatura__c contract = contracts.get(spec.contractId);
            if (contract == null) {
                continue;
            }
            ChangeContext ctx = new ChangeContext();
            ctx.contract = contract;
            ctx.currentPlan = plans.get(contract.Plano_Atual__c);
            ctx.requestedPlanId = spec.proposedPlanId;
            ctx.proposedPlan = spec.proposedPlanId == null ? null : plans.get(spec.proposedPlanId);
            List<Item_Contrato__c> activeItems = itemsByContract.get(contract.Id);
            if (activeItems != null) {
                for (Item_Contrato__c item : activeItems) {
                    ctx.addActiveItem(item);
                }
            }
            Map<Id, Decimal> contractPrices = prices.get(contract.Id);
            if (contractPrices != null) {
                ctx.catalogPriceByProduct = contractPrices;
            }
            result.put(key, ctx);
        }
        return result;
    }
}
