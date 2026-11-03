/**
 * @description Selector de Contrato_Assinatura__c. TODA consulta SOQL do objeto vive aqui.
 *              WITH USER_MODE: aplica sharing + CRUD + FLS do usuario em execucao.
 *              Consultas FOR UPDATE: sem ORDER BY (a plataforma nao permite) e so com campos do proprio
 *              objeto (menor superficie de lock e leitura). A ordem de lock do modulo e sempre:
 *              Solicitacao -> Contrato, para evitar deadlock entre aplicacoes concorrentes.
 */
public with sharing class ContractSelector {

    public List<Contrato_Assinatura__c> selectByIds(Set<Id> contractIds) {
        if (CollectionUtil.isNullOrEmpty(contractIds)) {
            return new List<Contrato_Assinatura__c>();
        }
        return [
            SELECT
                Id, Name, Account__c, Plano_Atual__c, Plano_Atual__r.Nivel__c, Plano_Atual__r.Codigo__c,
                Status__c, Periodicidade__c, Data_Inicio__c, Data_Fim__c, Pricebook__c,
                MRR_Atual__c, Versao__c, Gerente_Conta__c
            FROM Contrato_Assinatura__c
            WHERE Id IN :contractIds
            WITH USER_MODE
        ];
    }

    public Map<Id, Contrato_Assinatura__c> mapByIds(Set<Id> contractIds) {
        return new Map<Id, Contrato_Assinatura__c>(selectByIds(contractIds));
    }

    /** Bloqueio pessimista (FOR UPDATE). Revalidar o estado SEMPRE depois do lock. */
    public List<Contrato_Assinatura__c> selectByIdsForUpdate(Set<Id> contractIds) {
        if (CollectionUtil.isNullOrEmpty(contractIds)) {
            return new List<Contrato_Assinatura__c>();
        }
        return [
            SELECT
                Id, Name, Account__c, Plano_Atual__c, Status__c, Pricebook__c, MRR_Atual__c, Versao__c
            FROM Contrato_Assinatura__c
            WHERE Id IN :contractIds
            WITH USER_MODE
            FOR UPDATE
        ];
    }
}
