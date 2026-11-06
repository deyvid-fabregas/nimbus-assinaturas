/**
 * @description Selector de Solicitacao_Alteracao__c (WITH USER_MODE).
 *              "Solicitante" = CreatedById (o Owner pode mudar e nao representa quem pediu).
 */
public with sharing class RequestSelector {

    public List<Solicitacao_Alteracao__c> selectByIds(Set<Id> requestIds) {
        if (CollectionUtil.isNullOrEmpty(requestIds)) {
            return new List<Solicitacao_Alteracao__c>();
        }
        return [
            SELECT
                Id, Name, Contrato__c, Tipo__c, Plano_Proposto__c, Status__c, Nivel_Aprovacao__c,
                MRR_Base__c, MRR_Proposto__c, Variacao_Absoluta__c, Variacao_Percentual__c,
                Data_Efetivacao__c, Versao_Contrato_Base__c, Ciclo_Aprovacao__c, Chave_Idempotencia__c,
                Justificativa__c, Aprovador__c, Data_Decisao__c, Motivo_Rejeicao__c,
                CreatedById, CreatedDate, LastModifiedDate
            FROM Solicitacao_Alteracao__c
            WHERE Id IN :requestIds
            WITH USER_MODE
        ];
    }

    public Map<Id, Solicitacao_Alteracao__c> mapByIds(Set<Id> requestIds) {
        return new Map<Id, Solicitacao_Alteracao__c>(selectByIds(requestIds));
    }

    /** Bloqueio pessimista para decisao/aplicacao. Revalidar status e ciclo DEPOIS do lock. */
    public List<Solicitacao_Alteracao__c> selectByIdsForUpdate(Set<Id> requestIds) {
        if (CollectionUtil.isNullOrEmpty(requestIds)) {
            return new List<Solicitacao_Alteracao__c>();
        }
        return [
            SELECT
                Id, Name, Contrato__c, Tipo__c, Plano_Proposto__c, Status__c, Nivel_Aprovacao__c,
                MRR_Base__c, MRR_Proposto__c, Data_Efetivacao__c, Versao_Contrato_Base__c,
                Ciclo_Aprovacao__c, CreatedById
            FROM Solicitacao_Alteracao__c
            WHERE Id IN :requestIds
            WITH USER_MODE
            FOR UPDATE
        ];
    }

    /**
     * Solicitacoes PENDENTES dos contratos, excluindo os Ids informados (os do proprio lote).
     * Base da regra "no maximo uma Pendente por contrato" contra registros ja persistidos.
     */
    public List<Solicitacao_Alteracao__c> selectPendingByContractIds(Set<Id> contractIds, Set<Id> excludeRequestIds) {
        if (CollectionUtil.isNullOrEmpty(contractIds)) {
            return new List<Solicitacao_Alteracao__c>();
        }
        Set<Id> excluded = excludeRequestIds == null ? new Set<Id>() : excludeRequestIds;
        String pending = SubscriptionConstants.REQ_PENDENTE;
        return [
            SELECT Id, Name, Contrato__c, Status__c, Ciclo_Aprovacao__c
            FROM Solicitacao_Alteracao__c
            WHERE Contrato__c IN :contractIds AND Status__c = :pending AND Id NOT IN :excluded
            WITH USER_MODE
        ];
    }

    /** Idempotencia do simulador: mesma Chave_Idempotencia__c devolve a solicitacao ja criada. */
    public List<Solicitacao_Alteracao__c> selectByIdempotencyKeys(Set<String> keys) {
        if (CollectionUtil.isNullOrEmpty(keys)) {
            return new List<Solicitacao_Alteracao__c>();
        }
        return [
            SELECT Id, Name, Contrato__c, Status__c, MRR_Base__c, MRR_Proposto__c,
                   Versao_Contrato_Base__c, Chave_Idempotencia__c
            FROM Solicitacao_Alteracao__c
            WHERE Chave_Idempotencia__c IN :keys
            WITH USER_MODE
        ];
    }

    /** Solicitacao com nomes relacionados para exibicao (resumo/Screen Flows). Consulta unica por Id. */
    public List<Solicitacao_Alteracao__c> selectSummaryById(Id requestId) {
        if (requestId == null) {
            return new List<Solicitacao_Alteracao__c>();
        }
        return [
            SELECT
                Id, Name, Contrato__c, Contrato__r.Name, Contrato__r.Plano_Atual__r.Name,
                Plano_Proposto__r.Name, Tipo__c, Status__c, Nivel_Aprovacao__c,
                MRR_Base__c, MRR_Proposto__c, Variacao_Absoluta__c, Variacao_Percentual__c,
                Data_Efetivacao__c, Ciclo_Aprovacao__c, Justificativa__c,
                Aprovador__c, Aprovador__r.Name, Data_Decisao__c, Motivo_Rejeicao__c,
                CreatedById, CreatedBy.Name
            FROM Solicitacao_Alteracao__c
            WHERE Id = :requestId
            WITH USER_MODE
        ];
    }
}
