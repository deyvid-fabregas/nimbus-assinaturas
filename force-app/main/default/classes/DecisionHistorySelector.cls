/**
 * @description Selector de Historico_Decisao__c (auditoria, somente insercao). WITH USER_MODE.
 */
public with sharing class DecisionHistorySelector {

    public List<Historico_Decisao__c> selectByRequestIds(Set<Id> requestIds) {
        if (CollectionUtil.isNullOrEmpty(requestIds)) {
            return new List<Historico_Decisao__c>();
        }
        return [
            SELECT Id, Solicitacao__c, Ciclo__c, Decisao__c, Nivel__c, Usuario__c, Data_Hora__c, Motivo__c
            FROM Historico_Decisao__c
            WHERE Solicitacao__c IN :requestIds
            WITH USER_MODE
            ORDER BY Data_Hora__c ASC
        ];
    }
}
