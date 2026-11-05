/**
 * @description ESCRITA EM MODO SISTEMA (without sharing) para efeitos colaterais de operacoes JA AUTORIZADAS.
 *              Segunda (e ultima da Parte 3, junto com CalculatedFieldWriter) excecao isolada de privilegio.
 *
 *              POR QUE existe:
 *               - Historico_Decisao__c e somente insercao e o vendedor/aprovador nao tem "create" em todos os casos
 *                 (reabertura pelo solicitante, aprovacao automatica pelo Flow): o historico nao pode depender de FLS
 *                 de quem clica, senao a auditoria falharia ou seria contornavel.
 *               - Task de roteamento pertence ao aprovador designado (outro usuario) e e encerrada por quem decide;
 *                 o dono e a visibilidade da Task nao sao do usuario corrente.
 *               - Campos de roteamento (Nivel_Aprovacao__c, Ciclo_Aprovacao__c) sao do Flow/roteamento e somente
 *                 leitura para todos os Permission Sets.
 *
 *              GARANTIAS: nenhum metodo decide nada (sem regra de negocio); cada metodo copia SOMENTE campos da lista
 *              branca para um novo registro; so e chamado por Services/Actions apos autorizar (permissao, designacao,
 *              segregacao). A mudanca de Status__c continua sujeita ao gate da Trigger (StatusTransitionContext).
 *              Auditoria: grep "without sharing" deve listar apenas CalculatedFieldWriter e esta classe.
 */
public without sharing class AuthorizedSystemWriter {
    private static final List<String> ROUTING_FIELDS = new List<String>{
        'Nivel_Aprovacao__c', 'Ciclo_Aprovacao__c', 'Status__c', 'Data_Decisao__c'
    };

    /** Historico (somente insercao). */
    public static void insertHistory(List<Historico_Decisao__c> entries) {
        if (entries == null || entries.isEmpty()) {
            return;
        }
        List<Historico_Decisao__c> safe = new List<Historico_Decisao__c>();
        for (Historico_Decisao__c entry : entries) {
            safe.add(
                new Historico_Decisao__c(
                    Solicitacao__c = entry.Solicitacao__c,
                    Ciclo__c = entry.Ciclo__c,
                    Decisao__c = entry.Decisao__c,
                    Nivel__c = entry.Nivel__c,
                    Usuario__c = entry.Usuario__c,
                    Data_Hora__c = entry.Data_Hora__c,
                    Motivo__c = entry.Motivo__c
                )
            );
        }
        insert safe; // NOPMD - modo sistema intencional (ver cabecalho)
    }

    /**
     * Atualiza SOMENTE os campos de roteamento ja preenchidos (Nivel_Aprovacao__c, Ciclo_Aprovacao__c, Status__c,
     * Data_Decisao__c). Alterar Status__c exige StatusTransitionContext aberto pelo chamador.
     */
    public static void updateRouting(List<Solicitacao_Alteracao__c> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }
        List<Solicitacao_Alteracao__c> safe = new List<Solicitacao_Alteracao__c>();
        for (Solicitacao_Alteracao__c request : requests) {
            Solicitacao_Alteracao__c copy = new Solicitacao_Alteracao__c(Id = request.Id);
            Map<String, Object> populated = request.getPopulatedFieldsAsMap();
            for (String field : ROUTING_FIELDS) {
                if (populated.containsKey(field)) {
                    copy.put(field, populated.get(field));
                }
            }
            safe.add(copy);
        }
        update safe; // NOPMD - modo sistema intencional (ver cabecalho)
    }

    /** Tasks de roteamento ABERTAS das solicitacoes (leitura sem sharing, necessaria para deduplicar de verdade). */
    public static List<Task> openRoutingTasks(Set<Id> requestIds) {
        if (requestIds == null || requestIds.isEmpty()) {
            return new List<Task>();
        }
        String keyPattern = SubscriptionConstants.TASK_KEY_PREFIX + '|%';
        return [
            SELECT Id, WhatId, OwnerId, Chave_Deduplicacao__c
            FROM Task
            WHERE WhatId IN :requestIds AND IsClosed = false AND Chave_Deduplicacao__c LIKE :keyPattern
        ];
    }

    public static void insertTasks(List<Task> tasks) {
        if (tasks == null || tasks.isEmpty()) {
            return;
        }
        List<Task> safe = new List<Task>();
        for (Task task : tasks) {
            safe.add(
                new Task(
                    WhatId = task.WhatId,
                    OwnerId = task.OwnerId,
                    Subject = task.Subject,
                    Description = task.Description,
                    Status = task.Status,
                    Priority = task.Priority,
                    Chave_Deduplicacao__c = task.Chave_Deduplicacao__c
                )
            );
        }
        insert safe; // NOPMD - modo sistema intencional (ver cabecalho)
    }

    /** Encerra Tasks (somente Status = Completed). */
    public static void completeTasks(List<Task> tasks) {
        if (tasks == null || tasks.isEmpty()) {
            return;
        }
        List<Task> safe = new List<Task>();
        for (Task task : tasks) {
            safe.add(new Task(Id = task.Id, Status = SubscriptionConstants.TASK_STATUS_COMPLETED));
        }
        update safe; // NOPMD - modo sistema intencional (ver cabecalho)
    }
}
