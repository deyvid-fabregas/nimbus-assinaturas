/**
 * @description US-03: roteamento de alcada de solicitacoes que acabaram de virar Pendente (chamado pelo
 *              Record-Triggered Flow via ApprovalRoutingAction). Bulkificado: 200 solicitacoes = ate 8 SOQL
 *              (config nao conta) e 5 DML (Tasks encerradas, roteamento, Tasks novas, historico, status).
 *
 *              Por solicitacao Pendente:
 *               - classifica pela matriz (ApprovalMatrixPolicy; valores em Matriz_Alcada__mdt, nunca no codigo);
 *               - CICLO: novo ciclo = Ciclo_Aprovacao__c + 1 e encerra Tasks abertas de ciclos anteriores;
 *               - Automatica: historico "Aprovação Automática" + Pendente -> Aprovada sob StatusTransitionContext;
 *               - Humana: UMA Task para um usuario ativo designado ao responsavel (chave APR|Solicitacao|Ciclo).
 *              IDEMPOTENCIA: se ja existe Task aberta do ciclo corrente, ou a solicitacao nao esta Pendente, nao faz nada.
 *
 *              DONO DA TASK: Task so pode pertencer a um usuario; para GRUPO/FILA/PAPEL e usado o membro ativo de menor
 *              nome (deterministico). A autoridade de decidir NAO vem do dono da Task, e sim da designacao + Custom
 *              Permission validadas pelo SubscriptionDecisionService.
 *
 *              FALHA: rollback ao Savepoint, Log_Tecnico__c persistente (gravado apos o rollback) e COMPENSACAO:
 *              a solicitacao volta a Rascunho (aresta so aceita sob StatusTransitionContext), nunca fica Pendente sem rota.
 *              Financeiro NAO e recalculado aqui (so le MRR_* calculados pela Trigger).
 */
public with sharing class ApprovalRoutingService {

    public class Outcome {
        public Id requestId;
        public Boolean success = true;
        public Boolean noOp = false;
        public String code;
        public String message;
        public String approvalLevel;
    }

    private class Plan {
        Id requestId;
        Solicitacao_Alteracao__c request;
        ApprovalMatrixPolicy.Result classification;
        Decimal newCycle;
        Boolean human;
        String ownerKey;
        Id ownerId;
    }

    private final RequestSelector requestSelector = new RequestSelector();
    private final DesignationSelector designation = new DesignationSelector();

    /** Chave canonica de deduplicacao da Task. */
    public static String taskKey(Id requestId, Decimal cycle) {
        return SubscriptionConstants.TASK_KEY_PREFIX + '|' + String.valueOf(requestId) + '|'
            + String.valueOf(MoneyUtil.zeroIfNull(cycle).intValue());
    }

    public Map<Id, Outcome> route(Set<Id> requestIds) {
        Map<Id, Outcome> outcomes = new Map<Id, Outcome>();
        if (CollectionUtil.isNullOrEmpty(requestIds)) {
            return outcomes;
        }
        Savepoint checkpoint = Database.setSavepoint();
        Map<Id, String> toCompensate = new Map<Id, String>();
        try {
            SubscriptionSettings settings = SubscriptionConfig.settings();
            List<ApprovalMatrixPolicy.Rule> rules = SubscriptionConfig.approvalRules();
            Map<Id, Solicitacao_Alteracao__c> requests = requestSelector.mapByIds(requestIds);
            Map<Id, List<Task>> openTasks = groupByRequest(AuthorizedSystemWriter.openRoutingTasks(requestIds));

            List<Plan> plans = new List<Plan>();
            Set<String> ownerKeys = new Set<String>();
            for (Id requestId : requestIds) {
                Outcome outcome = new Outcome();
                outcome.requestId = requestId;
                outcomes.put(requestId, outcome);
                Solicitacao_Alteracao__c request = requests.get(requestId);
                try {
                    Plan plan = buildPlan(request, openTasks.get(requestId), settings, rules);
                    if (plan == null) {
                        outcome.noOp = true;
                        outcome.message = 'Nenhum roteamento necessário: a solicitação não está pendente de roteamento.';
                        continue;
                    }
                    outcome.approvalLevel = plan.classification.levelLabel();
                    plans.add(plan);
                    if (plan.human) {
                        ownerKeys.add(plan.ownerKey);
                    }
                } catch (SubscriptionException businessError) {
                    fail(outcome, businessError.code, businessError.getMessage());
                    if (request != null && request.Status__c == SubscriptionConstants.REQ_PENDENTE) {
                        toCompensate.put(requestId, businessError.getMessage());
                    }
                }
            }

            Map<String, Id> owners = designation.firstActiveUserByKey(ownerKeys);
            List<Plan> ready = new List<Plan>();
            for (Plan plan : plans) {
                if (plan.human) {
                    plan.ownerId = owners.get(plan.ownerKey);
                    if (plan.ownerId == null) {
                        String message = 'Não há usuário ativo designado para o responsável "'
                            + plan.classification.responsibleName + '". Contate o administrador.';
                        fail(outcomes.get(plan.requestId), SubscriptionConstants.ERR_NAO_DESIGNADO, message);
                        toCompensate.put(plan.requestId, message);
                        continue;
                    }
                }
                ready.add(plan);
            }
            apply(ready, openTasks);
            for (Plan plan : ready) {
                outcomes.get(plan.requestId).message = 'Solicitação roteada: ' + plan.classification.levelLabel() + '.';
            }
        } catch (Exception unexpected) {
            Database.rollback(checkpoint);
            Id logId = TechnicalLogger.log('ApprovalRoutingService', 'route', null, unexpected);
            String friendly = TechnicalLogger.friendlyMessage(unexpected, logId);
            for (Id requestId : requestIds) {
                Outcome outcome = outcomes.get(requestId);
                if (outcome == null) {
                    outcome = new Outcome();
                    outcome.requestId = requestId;
                    outcomes.put(requestId, outcome);
                }
                if (!outcome.noOp) {
                    fail(outcome, SubscriptionConstants.ERR_INESPERADO, friendly);
                    toCompensate.put(requestId, friendly);
                }
            }
        }
        compensate(toCompensate);
        return outcomes;
    }

    /**
     * Desfaz o envio (Pendente -> Rascunho) das solicitacoes que falharam no roteamento e grava um Log_Tecnico__c
     * por solicitacao. Usada pelo proprio route() e pelo caminho de falha (Fault) do Flow. Idempotente: so atua
     * em solicitacoes ainda Pendentes. Nunca lanca excecao (compensacao e melhor esforco, com log).
     */
    public Set<Id> compensate(Map<Id, String> reasonByRequestId) {
        Set<Id> compensated = new Set<Id>();
        if (reasonByRequestId == null || reasonByRequestId.isEmpty()) {
            return compensated;
        }
        List<Log_Tecnico__c> logs = new List<Log_Tecnico__c>();
        for (Id requestId : reasonByRequestId.keySet()) {
            logs.add(
                TechnicalLogger.build(
                    'ApprovalRoutingService', 'compensate', requestId, 'RoutingFailure', reasonByRequestId.get(requestId), null
                )
            );
        }
        TechnicalLogger.persist(logs);
        try {
            List<Solicitacao_Alteracao__c> reverts = new List<Solicitacao_Alteracao__c>();
            for (Solicitacao_Alteracao__c request : requestSelector.selectByIds(reasonByRequestId.keySet())) {
                if (request.Status__c == SubscriptionConstants.REQ_PENDENTE) {
                    reverts.add(new Solicitacao_Alteracao__c(Id = request.Id, Status__c = SubscriptionConstants.REQ_RASCUNHO));
                    compensated.add(request.Id);
                }
            }
            if (!reverts.isEmpty()) {
                StatusTransitionContext.Scope scope = StatusTransitionContext.open(
                    compensated,
                    new Set<String>{ SubscriptionConstants.REQ_RASCUNHO },
                    'Compensação de falha de roteamento (ApprovalRoutingService)'
                );
                try {
                    AuthorizedSystemWriter.updateRouting(reverts);
                } finally {
                    scope.close();
                }
            }
        } catch (Exception compensationFailure) {
            TechnicalLogger.log('ApprovalRoutingService', 'compensate', null, compensationFailure);
            compensated.clear();
        }
        return compensated;
    }

    // ------------------------------------------------------------------ privados

    private Plan buildPlan(
        Solicitacao_Alteracao__c request,
        List<Task> existingOpenTasks,
        SubscriptionSettings settings,
        List<ApprovalMatrixPolicy.Rule> rules
    ) {
        if (request == null) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_NAO_ENCONTRADO,
                'A solicitação não foi encontrada ou você não tem acesso a ela.'
            );
        }
        if (request.Status__c != SubscriptionConstants.REQ_PENDENTE) {
            return null;
        }
        Decimal cycle = MoneyUtil.zeroIfNull(request.Ciclo_Aprovacao__c);
        if (cycle > 0 && hasTask(existingOpenTasks, taskKey(request.Id, cycle))) {
            return null; // ja roteada neste envio (reprocessamento do Flow)
        }
        ApprovalMatrixPolicy.Result classification = ApprovalMatrixPolicy.classify(
            request.MRR_Base__c, request.MRR_Proposto__c, rules, settings.maxVariationPercent
        );
        ChangeRequestPolicy.requireNotBlocked(classification);

        Plan plan = new Plan();
        plan.requestId = request.Id;
        plan.request = request;
        plan.classification = classification;
        plan.newCycle = cycle + 1;
        plan.human = classification.requiresHumanApproval();
        if (plan.human) {
            if (TextUtil.isBlank(classification.responsibleType) || TextUtil.isBlank(classification.responsibleName)) {
                throw new SubscriptionException(
                    SubscriptionConstants.ERR_ALCADA_AUSENTE,
                    'A matriz de alçada não define o responsável do nível "' + classification.levelLabel() + '". Contate o administrador.'
                );
            }
            plan.ownerKey = DesignationSelector.keyOf(classification.responsibleType, classification.responsibleName);
        }
        return plan;
    }

    private void apply(List<Plan> ready, Map<Id, List<Task>> openTasks) {
        if (ready.isEmpty()) {
            return;
        }
        Datetime now = SubscriptionClock.now();
        List<Solicitacao_Alteracao__c> routingUpdates = new List<Solicitacao_Alteracao__c>();
        List<Solicitacao_Alteracao__c> approvals = new List<Solicitacao_Alteracao__c>();
        List<Task> toInsert = new List<Task>();
        List<Task> toComplete = new List<Task>();
        List<Historico_Decisao__c> history = new List<Historico_Decisao__c>();
        Set<Id> autoApprovedIds = new Set<Id>();

        for (Plan plan : ready) {
            routingUpdates.add(
                new Solicitacao_Alteracao__c(
                    Id = plan.requestId,
                    Nivel_Aprovacao__c = plan.classification.levelLabel(),
                    Ciclo_Aprovacao__c = plan.newCycle
                )
            );
            List<Task> previous = openTasks.get(plan.requestId);
            if (previous != null) {
                toComplete.addAll(previous);
            }
            if (plan.human) {
                toInsert.add(buildTask(plan));
            } else {
                autoApprovedIds.add(plan.requestId);
                approvals.add(
                    new Solicitacao_Alteracao__c(
                        Id = plan.requestId, Status__c = SubscriptionConstants.REQ_APROVADA, Data_Decisao__c = now
                    )
                );
                history.add(
                    new Historico_Decisao__c(
                        Solicitacao__c = plan.requestId,
                        Ciclo__c = plan.newCycle,
                        Decisao__c = SubscriptionConstants.DEC_AUTOMATICA,
                        Nivel__c = plan.classification.levelLabel(),
                        Usuario__c = UserInfo.getUserId(),
                        Data_Hora__c = now
                    )
                );
            }
        }
        AuthorizedSystemWriter.completeTasks(toComplete);
        AuthorizedSystemWriter.updateRouting(routingUpdates);
        AuthorizedSystemWriter.insertTasks(toInsert);
        AuthorizedSystemWriter.insertHistory(history);
        if (!approvals.isEmpty()) {
            StatusTransitionContext.Scope scope = StatusTransitionContext.open(
                autoApprovedIds,
                new Set<String>{ SubscriptionConstants.REQ_APROVADA },
                'Aprovação automática pela matriz de alçada (ApprovalRoutingService)'
            );
            try {
                AuthorizedSystemWriter.updateRouting(approvals);
            } finally {
                scope.close();
            }
        }
    }

    private static Task buildTask(Plan plan) {
        Solicitacao_Alteracao__c request = plan.request;
        return new Task(
            WhatId = plan.requestId,
            OwnerId = plan.ownerId,
            Subject = 'Aprovar alteração contratual ' + request.Name + ' (' + plan.classification.levelLabel() + ')',
            Description = 'Solicitação ' + request.Name + ' - ciclo ' + plan.newCycle.intValue()
                + '. MRR atual: ' + request.MRR_Base__c + ' | MRR proposto: ' + request.MRR_Proposto__c
                + ' | variação: ' + request.Variacao_Absoluta__c + ' (' + request.Variacao_Percentual__c + '%).'
                + ' Decida pela ação "Decidir solicitação" na própria solicitação.',
            Status = SubscriptionConstants.TASK_STATUS_OPEN,
            Priority = SubscriptionConstants.TASK_PRIORITY_NORMAL,
            Chave_Deduplicacao__c = taskKey(plan.requestId, plan.newCycle)
        );
    }

    private static Map<Id, List<Task>> groupByRequest(List<Task> tasks) {
        Map<Id, List<Task>> grouped = new Map<Id, List<Task>>();
        for (Task task : tasks) {
            List<Task> bucket = grouped.get(task.WhatId);
            if (bucket == null) {
                bucket = new List<Task>();
                grouped.put(task.WhatId, bucket);
            }
            bucket.add(task);
        }
        return grouped;
    }

    private static Boolean hasTask(List<Task> tasks, String key) {
        if (tasks == null) {
            return false;
        }
        for (Task task : tasks) {
            if (task.Chave_Deduplicacao__c == key) {
                return true;
            }
        }
        return false;
    }

    private static void fail(Outcome outcome, String code, String message) {
        outcome.success = false;
        outcome.code = code;
        outcome.message = message;
    }
}
