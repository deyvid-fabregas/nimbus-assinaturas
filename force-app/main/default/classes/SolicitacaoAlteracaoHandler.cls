/**
 * @description Handler da Trigger SubscriptionRequestTrigger (Solicitacao_Alteracao__c).
 *              Orquestra: estado inicial + snapshot (insert), campos protegidos, MAQUINA DE ESTADOS e envio
 *              (Rascunho -> Pendente) no update. Sem DML. Erros POR REGISTRO (addError).
 *
 *              Campos protegidos:
 *               - SEMPRE imutaveis: Contrato__c, MRR_Base__c, Versao_Contrato_Base__c, Chave_Idempotencia__c.
 *               - Congelados fora de Rascunho (status ANTERIOR diferente de Rascunho): Tipo__c, Plano_Proposto__c,
 *                 Data_Efetivacao__c, MRR_Proposto__c, Variacao_Absoluta__c, Variacao_Percentual__c.
 *               - Livres: Justificativa__c (US-03 CA03 salva Pendente com justificativa nova), e os campos do
 *                 Flow/DecisionService (Nivel_Aprovacao__c, Ciclo_Aprovacao__c, Aprovador__c, Data_Decisao__c,
 *                 Motivo_Rejeicao__c, Status__c por transicao valida).
 *
 *              Recursao: este Handler so VALIDA (nao faz DML nem muda o que o Flow le). Uma atualizacao de campo
 *              feita por Flow na mesma transacao reexecuta a Trigger com Status inalterado, o que nao dispara
 *              maquina de estados nem validacao de envio: nao ha loop e nada e bloqueado indevidamente.
 */
public with sharing class SolicitacaoAlteracaoHandler {
    private static final List<Schema.SObjectField> ALWAYS_IMMUTABLE = new List<Schema.SObjectField>{
        Solicitacao_Alteracao__c.Contrato__c,
        Solicitacao_Alteracao__c.MRR_Base__c,
        Solicitacao_Alteracao__c.Versao_Contrato_Base__c,
        Solicitacao_Alteracao__c.Chave_Idempotencia__c
    };
    private static final List<Schema.SObjectField> FROZEN_OUTSIDE_DRAFT = new List<Schema.SObjectField>{
        Solicitacao_Alteracao__c.Tipo__c,
        Solicitacao_Alteracao__c.Plano_Proposto__c,
        Solicitacao_Alteracao__c.Data_Efetivacao__c,
        Solicitacao_Alteracao__c.MRR_Proposto__c,
        Solicitacao_Alteracao__c.Variacao_Absoluta__c,
        Solicitacao_Alteracao__c.Variacao_Percentual__c
    };

    private final RequestSnapshotService snapshotService = new RequestSnapshotService();
    private final RequestSubmissionService submissionService = new RequestSubmissionService();

    public void run() {
        switch on Trigger.operationType {
            when BEFORE_INSERT {
                beforeInsert((List<Solicitacao_Alteracao__c>) Trigger.new);
            }
            when BEFORE_UPDATE {
                beforeUpdate(
                    (List<Solicitacao_Alteracao__c>) Trigger.new,
                    (Map<Id, Solicitacao_Alteracao__c>) Trigger.oldMap
                );
            }
            when else {
                // Demais eventos nao sao tratados.
            }
        }
    }

    public void beforeInsert(List<Solicitacao_Alteracao__c> records) {
        try {
            Map<Integer, String> errors = snapshotService.prepareNew(records);
            for (Integer index : errors.keySet()) {
                records[index].addError(errors.get(index));
            }
        } catch (SubscriptionException batchError) {
            for (Solicitacao_Alteracao__c record : records) {
                record.addError(batchError.getMessage());
            }
        }
    }

    public void beforeUpdate(List<Solicitacao_Alteracao__c> records, Map<Id, Solicitacao_Alteracao__c> oldById) {
        Set<Id> rejected = new Set<Id>();
        List<Solicitacao_Alteracao__c> submitting = new List<Solicitacao_Alteracao__c>();
        List<Solicitacao_Alteracao__c> draftEdits = new List<Solicitacao_Alteracao__c>();

        for (Solicitacao_Alteracao__c record : records) {
            Solicitacao_Alteracao__c old = oldById.get(record.Id);
            String error = protectedFieldError(record, old);
            if (error == null) {
                error = transitionError(record, old);
            }
            if (error != null) {
                reject(record, error, rejected);
                continue;
            }
            if (record.Status__c != old.Status__c) {
                if (record.Status__c == SubscriptionConstants.REQ_PENDENTE) {
                    submitting.add(record);
                }
            } else if (record.Status__c == SubscriptionConstants.REQ_RASCUNHO
                && (record.Data_Efetivacao__c != old.Data_Efetivacao__c
                    || record.Plano_Proposto__c != old.Plano_Proposto__c)) {
                draftEdits.add(record);
            }
        }

        applyById(draftEdits, rejected, new DraftChecker(snapshotService));
        applyById(submitting, rejected, new SubmissionChecker(submissionService));
    }

    // ------------------------------------------------------------------ privados

    private interface BatchChecker {
        Map<Id, String> check(List<Solicitacao_Alteracao__c> records);
    }

    private class DraftChecker implements BatchChecker {
        private final RequestSnapshotService service;
        DraftChecker(RequestSnapshotService service) {
            this.service = service;
        }
        public Map<Id, String> check(List<Solicitacao_Alteracao__c> records) {
            return service.validateDraftChanges(records);
        }
    }

    private class SubmissionChecker implements BatchChecker {
        private final RequestSubmissionService service;
        SubmissionChecker(RequestSubmissionService service) {
            this.service = service;
        }
        public Map<Id, String> check(List<Solicitacao_Alteracao__c> records) {
            return service.validate(records);
        }
    }

    /** Roda o verificador em lote; erro de configuracao (batch) vira erro em cada registro do grupo. */
    private static void applyById(List<Solicitacao_Alteracao__c> group, Set<Id> rejected, BatchChecker checker) {
        if (group.isEmpty()) {
            return;
        }
        try {
            Map<Id, String> errors = checker.check(group);
            for (Solicitacao_Alteracao__c record : group) {
                String error = errors.get(record.Id);
                if (error != null) {
                    reject(record, error, rejected);
                }
            }
        } catch (SubscriptionException batchError) {
            for (Solicitacao_Alteracao__c record : group) {
                reject(record, batchError.getMessage(), rejected);
            }
        }
    }

    private static void reject(Solicitacao_Alteracao__c record, String message, Set<Id> rejected) {
        if (rejected.add(record.Id)) {
            record.addError(message);
        }
    }

    @TestVisible
    private static final String GATE_MESSAGE =
        'Esta mudança de status só pode ser feita pela ação autorizada de decisão, aplicação ou reabertura. Use a ação correspondente na solicitação.';

    /**
     * Maquina de estados + escopo controlado. Transicoes "gated" (decisao, aplicacao, reabertura) so passam com
     * StatusTransitionContext aberto para este registro e status de destino; a compensacao Pendente -> Rascunho
     * so existe quando um service autorizado a abriu.
     */
    private static String transitionError(Solicitacao_Alteracao__c record, Solicitacao_Alteracao__c old) {
        if (record.Status__c == old.Status__c) {
            return null;
        }
        Boolean authorized = StatusTransitionContext.isAuthorized(record.Id, record.Status__c);
        if (RequestStateMachine.isCompensationTransition(old.Status__c, record.Status__c)) {
            return authorized ? null : RequestStateMachine.transitionError(old.Status__c, record.Status__c);
        }
        String error = RequestStateMachine.transitionError(old.Status__c, record.Status__c);
        if (error != null) {
            return error;
        }
        if (RequestStateMachine.requiresAuthorizedService(old.Status__c, record.Status__c) && !authorized) {
            return GATE_MESSAGE;
        }
        return null;
    }

    private static String protectedFieldError(Solicitacao_Alteracao__c record, Solicitacao_Alteracao__c old) {
        for (Schema.SObjectField field : ALWAYS_IMMUTABLE) {
            if (changed(record, old, field)) {
                return 'O campo "' + field.getDescribe().getLabel() + '" não pode ser alterado após a criação da solicitação.';
            }
        }
        if (old.Status__c != SubscriptionConstants.REQ_RASCUNHO) {
            for (Schema.SObjectField field : FROZEN_OUTSIDE_DRAFT) {
                if (changed(record, old, field)) {
                    return 'O campo "' + field.getDescribe().getLabel()
                        + '" só pode ser alterado enquanto a solicitação está em Rascunho (status atual: "' + old.Status__c + '").';
                }
            }
        }
        return null;
    }

    private static Boolean changed(SObject record, SObject old, Schema.SObjectField field) {
        return record.get(field) != old.get(field);
    }
}
