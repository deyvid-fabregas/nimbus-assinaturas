/**
 * @description US-04: decisao do aprovador (aprovar/rejeitar) e reabertura de solicitacao rejeitada.
 *              TODA a autoridade e validada AQUI, no servidor, independentemente de tela, Flow ou FlexiPage:
 *               1) Custom Permission do nivel exigido (Aprovar_Gerente/Diretor/Financeiro);
 *               2) DESIGNACAO: usuario membro do grupo/fila/papel configurado na Matriz_Alcada__mdt para o nivel;
 *               3) SEGREGACAO: quem criou a solicitacao (CreatedById) nao a decide;
 *               4) estado Pendente e CICLO igual ao da tela (decisao sobre tela desatualizada e recusada);
 *               5) rejeicao exige motivo com tamanho minimo configuravel, sem aceitar so espacos.
 *
 *              CONCORRENCIA/IDEMPOTENCIA: lock FOR UPDATE da solicitacao e REVALIDACAO do estado depois do lock.
 *              A segunda chamada (duplo clique) ve o estado ja decidido e recebe SOLICITACAO_JA_DECIDIDA com mensagem
 *              amigavel, sem nova transicao nem novo historico. Duplicatas dentro do mesmo lote tambem sao tratadas.
 *
 *              BULK: N decisoes = 5 SOQL (lock, designacao x2, tasks, usuario) e ate 4 DML. Falha por registro nao
 *              afeta os demais; falha inesperada reverte o lote inteiro (Savepoint), grava Log_Tecnico__c e devolve
 *              mensagem generica com codigo de referencia (nunca stack trace). NAO lanca excecao.
 *
 *              ESCRITA: Status/Aprovador/Data/Motivo em USER_MODE sob StatusTransitionContext (gate da Trigger);
 *              historico e encerramento de Task via AuthorizedSystemWriter (efeitos de operacao ja autorizada).
 */
public with sharing class SubscriptionDecisionService {

    public class Input {
        public Id requestId;
        /** Ciclo exibido na tela; deve coincidir com Ciclo_Aprovacao__c atual. */
        public Decimal cycle;
        /** Aprovada | Rejeitada (valores de Status__c). */
        public String decision;
        public String reason;
    }

    public class Outcome {
        public Id requestId;
        public Boolean success = false;
        public Boolean alreadyResolved = false;
        public String code;
        public String message;
        public String status;
    }

    private class Staged {
        Solicitacao_Alteracao__c request;
        String target;
        String reason;
        Outcome outcome;
    }

    private final RequestSelector requestSelector = new RequestSelector();
    private final DesignationSelector designation = new DesignationSelector();

    // ------------------------------------------------------------------ conveniencia (1 registro)

    public Outcome approve(Id requestId, Decimal cycle) {
        return decide(new List<Input>{ input(requestId, cycle, SubscriptionConstants.REQ_APROVADA, null) })[0];
    }

    public Outcome reject(Id requestId, Decimal cycle, String reason) {
        return decide(new List<Input>{ input(requestId, cycle, SubscriptionConstants.REQ_REJEITADA, reason) })[0];
    }

    public Outcome reopen(Id requestId) {
        return reopen(new List<Id>{ requestId })[0];
    }

    // ------------------------------------------------------------------ decisao (bulk)

    public List<Outcome> decide(List<Input> inputs) {
        List<Outcome> outcomes = new List<Outcome>();
        if (inputs == null || inputs.isEmpty()) {
            return outcomes;
        }
        Set<Id> ids = new Set<Id>();
        for (Input item : inputs) {
            Outcome outcome = new Outcome();
            outcome.requestId = item == null ? null : item.requestId;
            outcomes.add(outcome);
            if (outcome.requestId != null) {
                ids.add(outcome.requestId);
            }
        }
        Savepoint checkpoint = Database.setSavepoint();
        try {
            SecurityGuard.requireUpdateable(Solicitacao_Alteracao__c.SObjectType);
            SubscriptionSettings settings = SubscriptionConfig.settings();
            List<ApprovalMatrixPolicy.Rule> rules = SubscriptionConfig.approvalRules();
            Map<Id, Solicitacao_Alteracao__c> locked = new Map<Id, Solicitacao_Alteracao__c>(
                requestSelector.selectByIdsForUpdate(ids)
            );
            Set<String> myKeys = designation.keysForUser(UserInfo.getUserId());

            List<Staged> staged = new List<Staged>();
            Set<Id> stagedIds = new Set<Id>();
            for (Integer i = 0; i < inputs.size(); i++) {
                Outcome outcome = outcomes[i];
                try {
                    Staged item = validate(inputs[i], locked, stagedIds, myKeys, settings, rules, outcome);
                    stagedIds.add(item.request.Id);
                    staged.add(item);
                } catch (SubscriptionException businessError) {
                    outcome.success = false;
                    outcome.code = businessError.code;
                    outcome.message = businessError.getMessage();
                    outcome.alreadyResolved = businessError.code == SubscriptionConstants.ERR_JA_DECIDIDA;
                }
            }
            applyDecisions(staged);
            for (Staged item : staged) {
                item.outcome.success = true;
                item.outcome.status = item.target;
                item.outcome.message = item.target == SubscriptionConstants.REQ_APROVADA
                    ? 'Solicitação aprovada.'
                    : 'Solicitação rejeitada.';
            }
        } catch (Exception unexpected) {
            Database.rollback(checkpoint);
            failAll(outcomes, unexpected, 'decide', ids);
        }
        return outcomes;
    }

    // ------------------------------------------------------------------ reabertura (bulk)

    /**
     * Rejeitada -> Rascunho com historico "Reaberta". Autorizado: o solicitante (CreatedById) ou quem tem a Custom
     * Permission do nivel da solicitacao. Idempotente: solicitacao que ja voltou a Rascunho devolve mensagem amigavel.
     */
    public List<Outcome> reopen(List<Id> requestIds) {
        List<Outcome> outcomes = new List<Outcome>();
        if (requestIds == null || requestIds.isEmpty()) {
            return outcomes;
        }
        Set<Id> ids = new Set<Id>();
        for (Id requestId : requestIds) {
            Outcome outcome = new Outcome();
            outcome.requestId = requestId;
            outcomes.add(outcome);
            if (requestId != null) {
                ids.add(requestId);
            }
        }
        Savepoint checkpoint = Database.setSavepoint();
        try {
            SecurityGuard.requireUpdateable(Solicitacao_Alteracao__c.SObjectType);
            Map<Id, Solicitacao_Alteracao__c> locked = new Map<Id, Solicitacao_Alteracao__c>(
                requestSelector.selectByIdsForUpdate(ids)
            );
            List<Staged> staged = new List<Staged>();
            Set<Id> stagedIds = new Set<Id>();
            for (Integer i = 0; i < requestIds.size(); i++) {
                Outcome outcome = outcomes[i];
                try {
                    Staged item = validateReopen(requestIds[i], locked, stagedIds, outcome);
                    stagedIds.add(item.request.Id);
                    staged.add(item);
                } catch (SubscriptionException businessError) {
                    outcome.success = false;
                    outcome.code = businessError.code;
                    outcome.message = businessError.getMessage();
                    outcome.alreadyResolved = businessError.code == SubscriptionConstants.ERR_JA_DECIDIDA;
                }
            }
            applyReopen(staged);
            for (Staged item : staged) {
                item.outcome.success = true;
                item.outcome.status = SubscriptionConstants.REQ_RASCUNHO;
                item.outcome.message = 'Solicitação reaberta como Rascunho.';
            }
        } catch (Exception unexpected) {
            Database.rollback(checkpoint);
            failAll(outcomes, unexpected, 'reopen', ids);
        }
        return outcomes;
    }

    // ------------------------------------------------------------------ validacao

    private Staged validate(
        Input input,
        Map<Id, Solicitacao_Alteracao__c> locked,
        Set<Id> stagedIds,
        Set<String> myKeys,
        SubscriptionSettings settings,
        List<ApprovalMatrixPolicy.Rule> rules,
        Outcome outcome
    ) {
        if (input == null || input.requestId == null) {
            throw new SubscriptionException(SubscriptionConstants.ERR_ENTRADA_INVALIDA, 'Informe a solicitação a decidir.');
        }
        if (input.decision != SubscriptionConstants.REQ_APROVADA && input.decision != SubscriptionConstants.REQ_REJEITADA) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_ENTRADA_INVALIDA,
                'Decisão inválida. Escolha aprovar ou rejeitar.'
            );
        }
        Solicitacao_Alteracao__c request = locked.get(input.requestId);
        if (request == null) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_NAO_ENCONTRADO,
                'A solicitação não foi encontrada ou você não tem acesso a ela.'
            );
        }
        outcome.status = request.Status__c;
        // Revalidacao do estado DEPOIS do lock (duplo clique / chamadas concorrentes / duplicata no lote).
        if (request.Status__c != SubscriptionConstants.REQ_PENDENTE || stagedIds.contains(request.Id)) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_JA_DECIDIDA,
                'Esta solicitação já foi decidida'
                    + (stagedIds.contains(request.Id) ? '' : ' (status atual: ' + request.Status__c + ')')
                    + '. Nenhuma alteração foi feita.'
            );
        }
        if (input.cycle == null || request.Ciclo_Aprovacao__c != input.cycle) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_CICLO_DESATUALIZADO,
                'A tela está desatualizada: a solicitação foi reenviada em um novo ciclo. Recarregue e decida novamente.'
            );
        }
        ApprovalMatrixPolicy.Level level = ApprovalMatrixPolicy.levelFromLabel(request.Nivel_Aprovacao__c);
        if (level == null || level == ApprovalMatrixPolicy.Level.AUTOMATICA || level == ApprovalMatrixPolicy.Level.BLOQUEADA) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_DECISAO_NAO_APLICAVEL,
                'Esta solicitação não está roteada para um aprovador humano.'
            );
        }
        SecurityGuard.requireCustomPermission(
            ApprovalMatrixPolicy.customPermissionOf(level),
            'Você não possui a permissão necessária para decidir solicitações do nível "' + request.Nivel_Aprovacao__c + '".'
        );
        if (!isDesignated(level, rules, myKeys)) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_NAO_DESIGNADO,
                'Você não está designado como aprovador do nível "' + request.Nivel_Aprovacao__c + '".'
            );
        }
        if (request.CreatedById == UserInfo.getUserId()) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_SEGREGACAO_FUNCOES,
                'Quem criou a solicitação não pode decidi-la. Peça a outro aprovador designado.'
            );
        }
        if (input.decision == SubscriptionConstants.REQ_REJEITADA) {
            ChangeRequestPolicy.requireRejectionReason(input.reason, settings.minRejectionReasonLength);
        }
        Staged staged = new Staged();
        staged.request = request;
        staged.target = input.decision;
        staged.reason = input.reason == null ? null : input.reason.trim();
        staged.outcome = outcome;
        return staged;
    }

    private Staged validateReopen(
        Id requestId,
        Map<Id, Solicitacao_Alteracao__c> locked,
        Set<Id> stagedIds,
        Outcome outcome
    ) {
        if (requestId == null) {
            throw new SubscriptionException(SubscriptionConstants.ERR_ENTRADA_INVALIDA, 'Informe a solicitação a reabrir.');
        }
        Solicitacao_Alteracao__c request = locked.get(requestId);
        if (request == null) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_NAO_ENCONTRADO,
                'A solicitação não foi encontrada ou você não tem acesso a ela.'
            );
        }
        outcome.status = request.Status__c;
        if (stagedIds.contains(request.Id) || request.Status__c == SubscriptionConstants.REQ_RASCUNHO) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_JA_DECIDIDA,
                'Esta solicitação já foi reaberta e está em Rascunho. Nenhuma alteração foi feita.'
            );
        }
        if (request.Status__c != SubscriptionConstants.REQ_REJEITADA) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_TRANSICAO_INVALIDA,
                'Somente solicitações Rejeitadas podem ser reabertas (status atual: ' + request.Status__c + ').'
            );
        }
        Boolean isRequester = request.CreatedById == UserInfo.getUserId();
        ApprovalMatrixPolicy.Level level = ApprovalMatrixPolicy.levelFromLabel(request.Nivel_Aprovacao__c);
        String permission = level == null ? null : ApprovalMatrixPolicy.customPermissionOf(level);
        if (!isRequester && !SecurityGuard.hasCustomPermission(permission)) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_SEM_PERMISSAO,
                'Somente o solicitante ou um aprovador do nível da solicitação pode reabri-la.'
            );
        }
        Staged staged = new Staged();
        staged.request = request;
        staged.target = SubscriptionConstants.REQ_RASCUNHO;
        staged.outcome = outcome;
        return staged;
    }

    /** Designado = membro (grupo/fila/papel) de QUALQUER regra ativa que resolva para o nivel. */
    private static Boolean isDesignated(
        ApprovalMatrixPolicy.Level level,
        List<ApprovalMatrixPolicy.Rule> rules,
        Set<String> myKeys
    ) {
        for (ApprovalMatrixPolicy.Rule rule : rules) {
            if (rule.level == level
                && !TextUtil.isBlank(rule.responsibleType)
                && !TextUtil.isBlank(rule.responsibleName)
                && myKeys.contains(DesignationSelector.keyOf(rule.responsibleType, rule.responsibleName))) {
                return true;
            }
        }
        return false;
    }

    // ------------------------------------------------------------------ escrita

    private void applyDecisions(List<Staged> staged) {
        if (staged.isEmpty()) {
            return;
        }
        Datetime now = SubscriptionClock.now();
        Id me = UserInfo.getUserId();
        List<Solicitacao_Alteracao__c> approvals = new List<Solicitacao_Alteracao__c>();
        List<Solicitacao_Alteracao__c> rejections = new List<Solicitacao_Alteracao__c>();
        Set<Id> approvedIds = new Set<Id>();
        Set<Id> rejectedIds = new Set<Id>();
        List<Historico_Decisao__c> history = new List<Historico_Decisao__c>();
        Set<Id> allIds = new Set<Id>();

        for (Staged item : staged) {
            Solicitacao_Alteracao__c change = new Solicitacao_Alteracao__c(
                Id = item.request.Id, Status__c = item.target, Aprovador__c = me, Data_Decisao__c = now
            );
            if (item.target == SubscriptionConstants.REQ_REJEITADA) {
                change.Motivo_Rejeicao__c = item.reason;
                rejections.add(change);
                rejectedIds.add(item.request.Id);
            } else {
                approvals.add(change);
                approvedIds.add(item.request.Id);
            }
            allIds.add(item.request.Id);
            history.add(
                new Historico_Decisao__c(
                    Solicitacao__c = item.request.Id,
                    Ciclo__c = item.request.Ciclo_Aprovacao__c,
                    Decisao__c = item.target,
                    Nivel__c = item.request.Nivel_Aprovacao__c,
                    Usuario__c = me,
                    Data_Hora__c = now,
                    Motivo__c = item.target == SubscriptionConstants.REQ_REJEITADA ? item.reason : null
                )
            );
        }
        updateUnderScope(approvals, approvedIds, SubscriptionConstants.REQ_APROVADA);
        updateUnderScope(rejections, rejectedIds, SubscriptionConstants.REQ_REJEITADA);
        AuthorizedSystemWriter.insertHistory(history);
        AuthorizedSystemWriter.completeTasks(AuthorizedSystemWriter.openRoutingTasks(allIds));
    }

    private void applyReopen(List<Staged> staged) {
        if (staged.isEmpty()) {
            return;
        }
        Datetime now = SubscriptionClock.now();
        Id me = UserInfo.getUserId();
        List<Solicitacao_Alteracao__c> changes = new List<Solicitacao_Alteracao__c>();
        Set<Id> ids = new Set<Id>();
        List<Historico_Decisao__c> history = new List<Historico_Decisao__c>();
        for (Staged item : staged) {
            changes.add(new Solicitacao_Alteracao__c(Id = item.request.Id, Status__c = SubscriptionConstants.REQ_RASCUNHO));
            ids.add(item.request.Id);
            history.add(
                new Historico_Decisao__c(
                    Solicitacao__c = item.request.Id,
                    Ciclo__c = item.request.Ciclo_Aprovacao__c,
                    Decisao__c = SubscriptionConstants.DEC_REABERTA,
                    Nivel__c = item.request.Nivel_Aprovacao__c,
                    Usuario__c = me,
                    Data_Hora__c = now
                )
            );
        }
        updateUnderScope(changes, ids, SubscriptionConstants.REQ_RASCUNHO);
        AuthorizedSystemWriter.insertHistory(history);
    }

    /** Escopo exatamente (solicitacoes, UM status de destino), fechado em finally. */
    private static void updateUnderScope(List<Solicitacao_Alteracao__c> changes, Set<Id> ids, String targetStatus) {
        if (changes.isEmpty()) {
            return;
        }
        StatusTransitionContext.Scope scope = StatusTransitionContext.open(
            ids, new Set<String>{ targetStatus }, 'Decisão/reabertura autorizada (SubscriptionDecisionService)'
        );
        try {
            Database.update(changes, true, AccessLevel.USER_MODE);
        } finally {
            scope.close();
        }
    }

    private static void failAll(List<Outcome> outcomes, Exception error, String method, Set<Id> ids) {
        Boolean business = error instanceof SubscriptionException;
        Id logId = business ? null : TechnicalLogger.log('SubscriptionDecisionService', method, firstId(ids), error);
        String code = business ? ((SubscriptionException) error).code : SubscriptionConstants.ERR_INESPERADO;
        String message = TechnicalLogger.friendlyMessage(error, logId);
        for (Outcome outcome : outcomes) {
            outcome.success = false;
            outcome.alreadyResolved = false;
            outcome.code = code;
            outcome.message = message;
        }
    }

    private static Id firstId(Set<Id> ids) {
        for (Id value : ids) {
            return value;
        }
        return null;
    }

    private static Input input(Id requestId, Decimal cycle, String decision, String reason) {
        Input result = new Input();
        result.requestId = requestId;
        result.cycle = cycle;
        result.decision = decision;
        result.reason = reason;
        return result;
    }
}
