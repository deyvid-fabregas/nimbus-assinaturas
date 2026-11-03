/**
 * @description Selector de Aditivo_Contrato__c (WITH USER_MODE).
 *              Chave_Unica__c = "SolicitacaoId-Ciclo" e a base da idempotencia da aplicacao.
 */
public with sharing class AdditiveSelector {

    public List<Aditivo_Contrato__c> selectByUniqueKeys(Set<String> uniqueKeys) {
        if (CollectionUtil.isNullOrEmpty(uniqueKeys)) {
            return new List<Aditivo_Contrato__c>();
        }
        return [
            SELECT Id, Name, Contrato__c, Solicitacao__c, Chave_Unica__c, Versao_Resultante__c,
                   MRR_Anterior__c, MRR_Novo__c, Data_Efetivacao__c, Order__c
            FROM Aditivo_Contrato__c
            WHERE Chave_Unica__c IN :uniqueKeys
            WITH USER_MODE
        ];
    }

    public List<Aditivo_Contrato__c> selectByRequestIds(Set<Id> requestIds) {
        if (CollectionUtil.isNullOrEmpty(requestIds)) {
            return new List<Aditivo_Contrato__c>();
        }
        return [
            SELECT Id, Name, Contrato__c, Solicitacao__c, Chave_Unica__c, Versao_Resultante__c,
                   MRR_Anterior__c, MRR_Novo__c, Data_Efetivacao__c, Order__c
            FROM Aditivo_Contrato__c
            WHERE Solicitacao__c IN :requestIds
            WITH USER_MODE
        ];
    }

    /** Chave canonica da idempotencia: nunca montar a string em outro lugar. */
    public static String uniqueKey(Id requestId, Decimal cycle) {
        return String.valueOf(requestId) + '-' + String.valueOf(MoneyUtil.zeroIfNull(cycle).intValue());
    }
}
