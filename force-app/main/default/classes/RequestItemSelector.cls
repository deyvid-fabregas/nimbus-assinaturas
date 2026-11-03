/**
 * @description Selector de Item_Alteracao__c (WITH USER_MODE).
 */
public with sharing class RequestItemSelector {

    public List<Item_Alteracao__c> selectByIds(Set<Id> itemIds) {
        if (CollectionUtil.isNullOrEmpty(itemIds)) {
            return new List<Item_Alteracao__c>();
        }
        return [
            SELECT Id, Solicitacao__c, Item_Contrato__c, Produto__c, Acao__c,
                   Quantidade_Atual__c, Quantidade_Nova__c, Preco_Unitario_Mensal__c, Delta_MRR__c
            FROM Item_Alteracao__c
            WHERE Id IN :itemIds
            WITH USER_MODE
        ];
    }

    public List<Item_Alteracao__c> selectByRequestIds(Set<Id> requestIds) {
        if (CollectionUtil.isNullOrEmpty(requestIds)) {
            return new List<Item_Alteracao__c>();
        }
        return [
            SELECT Id, Solicitacao__c, Item_Contrato__c, Produto__c, Produto__r.Name, Acao__c,
                   Quantidade_Atual__c, Quantidade_Nova__c, Preco_Unitario_Mensal__c, Delta_MRR__c
            FROM Item_Alteracao__c
            WHERE Solicitacao__c IN :requestIds
            WITH USER_MODE
        ];
    }

    /**
     * Soma de Delta_MRR__c por solicitacao, agregada no banco: 1 SOQL para qualquer numero de pais
     * (200 solicitacoes = 1 consulta). Solicitacoes sem itens nao aparecem (tratar como zero).
     * Usada pelo recalculo APOS o DML dos itens, entao ja reflete insert/update/delete/undelete.
     */
    public Map<Id, Decimal> sumDeltaByRequestIds(Set<Id> requestIds) {
        Map<Id, Decimal> totals = new Map<Id, Decimal>();
        if (CollectionUtil.isNullOrEmpty(requestIds)) {
            return totals;
        }
        for (AggregateResult row : [
            SELECT Solicitacao__c requestId, SUM(Delta_MRR__c) total
            FROM Item_Alteracao__c
            WHERE Solicitacao__c IN :requestIds
            WITH USER_MODE
            GROUP BY Solicitacao__c
        ]) {
            totals.put((Id) row.get('requestId'), (Decimal) row.get('total'));
        }
        return totals;
    }

    /** Quantidade de itens por solicitacao, agregada no banco (1 SOQL). Sem itens = ausente (tratar como zero). */
    public Map<Id, Integer> countByRequestIds(Set<Id> requestIds) {
        Map<Id, Integer> counts = new Map<Id, Integer>();
        if (CollectionUtil.isNullOrEmpty(requestIds)) {
            return counts;
        }
        for (AggregateResult row : [
            SELECT Solicitacao__c requestId, COUNT(Id) total
            FROM Item_Alteracao__c
            WHERE Solicitacao__c IN :requestIds
            WITH USER_MODE
            GROUP BY Solicitacao__c
        ]) {
            counts.put((Id) row.get('requestId'), Integer.valueOf(row.get('total')));
        }
        return counts;
    }
}
