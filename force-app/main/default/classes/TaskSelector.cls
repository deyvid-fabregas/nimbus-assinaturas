/**
 * @description Selector de Task (somente campos padrao, WITH USER_MODE). Usado para o "tempo em espera" da solicitacao
 *              Pendente: criacao da Task de roteamento aberta mais recente. Nao filtra por Chave_Deduplicacao__c porque o
 *              campo nao tem FLS em Permission Set (so o roteamento o escreve/le em modo sistema).
 */
public with sharing class TaskSelector {
    public List<Task> selectOpenByRequestId(Id requestId) {
        if (requestId == null) {
            return new List<Task>();
        }
        return [
            SELECT Id, CreatedDate
            FROM Task
            WHERE WhatId = :requestId AND IsClosed = false
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
    }
}
