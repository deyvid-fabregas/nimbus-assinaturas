/**
 * @description Resolve Pricebook efetivo e precos unitarios em LOTE (sem SOQL em loop).
 *              Pricebook efetivo do contrato = Contrato.Pricebook__c; se vazio, o Pricebook padrao pelo NOME
 *              configurado em Parametro_Assinatura__mdt (nada hardcoded).
 *              Antecipado para a Parte 2 porque o preco de recursos adicionais (US-01) vem daqui; a Parte 3
 *              (SubscriptionApplyService/OrderItem) reutiliza esta classe.
 *
 *              Limitacao: nao valida se o Pricebook2 do contrato esta ativo (a entrada ativa e exigida).
 */
public with sharing class PricebookResolver {
    private final PricebookSelector pricebooks = new PricebookSelector();

    /** contractId -> pricebookId efetivo. Contrato sem pricebook resolvivel fica ausente do mapa. */
    public Map<Id, Id> resolvePricebookIds(List<Contrato_Assinatura__c> contracts) {
        Map<Id, Id> result = new Map<Id, Id>();
        if (contracts == null || contracts.isEmpty()) {
            return result;
        }
        Boolean needsDefault = false;
        for (Contrato_Assinatura__c contract : contracts) {
            if (contract.Pricebook__c == null) {
                needsDefault = true;
            }
        }
        Id defaultPricebookId = null;
        if (needsDefault) {
            List<Pricebook2> found = pricebooks.selectActiveByName(SubscriptionConfig.settings().defaultPricebookName);
            defaultPricebookId = found.isEmpty() ? null : found[0].Id;
        }
        for (Contrato_Assinatura__c contract : contracts) {
            Id effective = contract.Pricebook__c != null ? contract.Pricebook__c : defaultPricebookId;
            if (effective != null) {
                result.put(contract.Id, effective);
            }
        }
        return result;
    }

    /** contractId -> (productId -> preco mensal). Produto sem entrada ativa fica ausente. */
    public Map<Id, Map<Id, Decimal>> resolveUnitPrices(List<Contrato_Assinatura__c> contracts, Set<Id> productIds) {
        Map<Id, Map<Id, Decimal>> result = new Map<Id, Map<Id, Decimal>>();
        if (contracts == null || contracts.isEmpty() || CollectionUtil.isNullOrEmpty(productIds)) {
            return result;
        }
        Map<Id, Id> pricebookByContract = resolvePricebookIds(contracts);
        Set<Id> pricebookIds = new Set<Id>(pricebookByContract.values());

        Map<Id, Map<Id, Decimal>> pricesByPricebook = new Map<Id, Map<Id, Decimal>>();
        for (PricebookEntry entry : pricebooks.selectActiveEntriesForPricebooks(pricebookIds, productIds)) {
            Map<Id, Decimal> bucket = pricesByPricebook.get(entry.Pricebook2Id);
            if (bucket == null) {
                bucket = new Map<Id, Decimal>();
                pricesByPricebook.put(entry.Pricebook2Id, bucket);
            }
            bucket.put(entry.Product2Id, entry.UnitPrice);
        }
        for (Id contractId : pricebookByContract.keySet()) {
            Map<Id, Decimal> prices = pricesByPricebook.get(pricebookByContract.get(contractId));
            result.put(contractId, prices == null ? new Map<Id, Decimal>() : prices);
        }
        return result;
    }

    /** Entradas de preco ATIVAS (com Id, necessario ao OrderItem) do pricebook para os produtos; produto sem entrada fica ausente. */
    public Map<Id, PricebookEntry> resolveEntries(Id pricebookId, Set<Id> productIds) {
        Map<Id, PricebookEntry> result = new Map<Id, PricebookEntry>();
        for (PricebookEntry entry : pricebooks.selectActiveEntries(pricebookId, productIds)) {
            result.put(entry.Product2Id, entry);
        }
        return result;
    }
}
