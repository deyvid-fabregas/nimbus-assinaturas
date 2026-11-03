/**
 * @description Selector de Item_Contrato__c (WITH USER_MODE).
 */
public with sharing class ContractItemSelector {

    public List<Item_Contrato__c> selectByIds(Set<Id> itemIds) {
        if (CollectionUtil.isNullOrEmpty(itemIds)) {
            return new List<Item_Contrato__c>();
        }
        return [
            SELECT Id, Contrato__c, Produto__c, Produto__r.Name, Tipo__c, Quantidade__c,
                   Preco_Unitario_Mensal__c, MRR_Item__c, Status__c
            FROM Item_Contrato__c
            WHERE Id IN :itemIds
            WITH USER_MODE
        ];
    }

    /** Itens ATIVOS dos contratos informados (1 consulta para o lote inteiro). */
    public List<Item_Contrato__c> selectActiveByContractIds(Set<Id> contractIds) {
        if (CollectionUtil.isNullOrEmpty(contractIds)) {
            return new List<Item_Contrato__c>();
        }
        String activeStatus = SubscriptionConstants.ITEM_ATIVO;
        return [
            SELECT Id, Contrato__c, Produto__c, Produto__r.Name, Tipo__c, Quantidade__c,
                   Preco_Unitario_Mensal__c, MRR_Item__c, Status__c
            FROM Item_Contrato__c
            WHERE Contrato__c IN :contractIds AND Status__c = :activeStatus
            WITH USER_MODE
        ];
    }

    /** Todos os itens (ativos e removidos) dos contratos; usado na aplicacao para reconciliar produtos. */
    public List<Item_Contrato__c> selectAllByContractIds(Set<Id> contractIds) {
        if (CollectionUtil.isNullOrEmpty(contractIds)) {
            return new List<Item_Contrato__c>();
        }
        return [
            SELECT Id, Contrato__c, Produto__c, Tipo__c, Quantidade__c,
                   Preco_Unitario_Mensal__c, MRR_Item__c, Status__c
            FROM Item_Contrato__c
            WHERE Contrato__c IN :contractIds
            WITH USER_MODE
        ];
    }

    /**
     * Soma do MRR dos itens ATIVOS por contrato, agregada no banco (1 SOQL, sem trazer linhas).
     * Contratos sem itens ativos nao aparecem no mapa (tratar como zero).
     */
    public Map<Id, Decimal> sumActiveMrrByContractIds(Set<Id> contractIds) {
        Map<Id, Decimal> totals = new Map<Id, Decimal>();
        if (CollectionUtil.isNullOrEmpty(contractIds)) {
            return totals;
        }
        String activeStatus = SubscriptionConstants.ITEM_ATIVO;
        for (AggregateResult row : [
            SELECT Contrato__c contractId, SUM(MRR_Item__c) total
            FROM Item_Contrato__c
            WHERE Contrato__c IN :contractIds AND Status__c = :activeStatus
            WITH USER_MODE
            GROUP BY Contrato__c
        ]) {
            totals.put((Id) row.get('contractId'), (Decimal) row.get('total'));
        }
        return totals;
    }
}
