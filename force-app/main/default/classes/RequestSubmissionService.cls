/**
 * @description Validacao SERVER-SIDE do envio (Rascunho -> Pendente) para TODOS os canais.
 *              Chamado pela Trigger apenas para registros cuja transicao para Pendente ja foi validada pela
 *              RequestStateMachine. Devolve erros por Id da solicitacao (o Handler aplica addError).
 *
 *              UMA Pendente por contrato (lote e concorrencia):
 *               1) lock pessimista dos contratos envolvidos (FOR UPDATE) ANTES de olhar as pendentes, o que
 *                  serializa envios concorrentes do mesmo contrato (a 2a transacao espera e entao enxerga a
 *                  Pendente commitada pela 1a). Ordem de lock do modulo: Solicitacao -> Contrato.
 *                  Limite: o lock e por linha de contrato; em lote a ordem de aquisicao e da plataforma.
 *               2) pendentes ja persistidas bloqueiam todo o lote daquele contrato;
 *               3) dentro do lote, a primeira solicitacao VALIDA do contrato e aceita; as demais recebem erro.
 *
 *              Conteudo exigido no envio: contrato Ativo, data valida, justificativa, ao menos 1 item, totais
 *              coerentes com a soma dos itens (detecta edicao manual dos campos calculados), consistencia da
 *              troca de plano, limites de licencas e ausencia de bloqueio pela matriz de alcada.
 *              Custo para 200 solicitacoes: no maximo 10 SOQL (lock, pendentes, contagem, soma, itens e
 *              ate 5 do ChangeContextLoader) e 0 DML.
 */
public with sharing class RequestSubmissionService {
    private final ContractSelector contractSelector = new ContractSelector();
    private final RequestSelector requestSelector = new RequestSelector();
    private final RequestItemSelector itemSelector = new RequestItemSelector();
    private final ChangeContextLoader loader = new ChangeContextLoader();

    public Map<Id, String> validate(List<Solicitacao_Alteracao__c> requests) {
        Map<Id, String> errors = new Map<Id, String>();
        if (requests == null || requests.isEmpty()) {
            return errors;
        }
        SubscriptionSettings settings = SubscriptionConfig.settings();
        List<ApprovalMatrixPolicy.Rule> rules = SubscriptionConfig.approvalRules();
        Set<Id> requestIds = new Map<Id, Solicitacao_Alteracao__c>(requests).keySet();
        Set<Id> contractIds = CollectionUtil.pluckIds(requests, Solicitacao_Alteracao__c.Contrato__c);

        // 1) lock dos contratos e 2) pendentes persistidas
        Map<Id, Contrato_Assinatura__c> locked = new Map<Id, Contrato_Assinatura__c>(
            contractSelector.selectByIdsForUpdate(contractIds)
        );
        Set<Id> contractsWithPending = new Set<Id>();
        for (Solicitacao_Alteracao__c pending : requestSelector.selectPendingByContractIds(contractIds, requestIds)) {
            contractsWithPending.add(pending.Contrato__c);
        }

        Map<Id, Integer> itemCounts = itemSelector.countByRequestIds(requestIds);
        Map<Id, Decimal> deltas = itemSelector.sumDeltaByRequestIds(requestIds);
        Map<Id, List<ItemResolutionPolicy.Line>> linesByRequest = loadLines(requestIds);

        Map<String, ChangeContextLoader.Spec> specs = new Map<String, ChangeContextLoader.Spec>();
        for (Solicitacao_Alteracao__c request : requests) {
            specs.put(String.valueOf(request.Id), new ChangeContextLoader.Spec(request.Contrato__c, request.Plano_Proposto__c));
        }
        Map<String, ChangeContext> contexts = loader.load(specs, new Set<Id>());

        Set<Id> acceptedContracts = new Set<Id>();
        for (Solicitacao_Alteracao__c request : requests) {
            try {
                checkContent(
                    request,
                    locked.get(request.Contrato__c),
                    contexts.get(String.valueOf(request.Id)),
                    itemCounts,
                    deltas,
                    linesByRequest,
                    settings,
                    rules
                );
                if (contractsWithPending.contains(request.Contrato__c)) {
                    throw new SubscriptionException(
                        SubscriptionConstants.ERR_PENDENTE_EXISTENTE,
                        'Já existe uma solicitação Pendente para este contrato. Conclua ou cancele a anterior antes de enviar outra.'
                    );
                }
                if (!acceptedContracts.add(request.Contrato__c)) {
                    throw new SubscriptionException(
                        SubscriptionConstants.ERR_PENDENTE_EXISTENTE,
                        'Outra solicitação deste contrato foi enviada na mesma operação. Só uma solicitação Pendente por contrato é permitida.'
                    );
                }
            } catch (SubscriptionException businessError) {
                errors.put(request.Id, businessError.getMessage());
            }
        }
        return errors;
    }

    private static void checkContent(
        Solicitacao_Alteracao__c request,
        Contrato_Assinatura__c lockedContract,
        ChangeContext ctx,
        Map<Id, Integer> itemCounts,
        Map<Id, Decimal> deltas,
        Map<Id, List<ItemResolutionPolicy.Line>> linesByRequest,
        SubscriptionSettings settings,
        List<ApprovalMatrixPolicy.Rule> rules
    ) {
        if (lockedContract == null || ctx == null) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_NAO_ENCONTRADO,
                'O contrato da solicitação não foi encontrado ou você não tem acesso a ele.'
            );
        }
        ChangeRequestPolicy.requireActiveContract(lockedContract.Status__c);
        ChangeRequestPolicy.requireEffectiveDate(
            request.Data_Efetivacao__c, SubscriptionClock.today(), settings.effectiveWindowDays
        );
        ChangeRequestPolicy.requireJustification(request.Justificativa__c, settings.minJustificationLength);

        Integer count = itemCounts.get(request.Id);
        if (count == null || count == 0) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_SEM_ALTERACAO,
                'Adicione ao menos uma alteração antes de enviar a solicitação para aprovação.'
            );
        }
        Decimal expectedProposed = MrrCalculator.proposedMrr(request.MRR_Base__c, deltas.get(request.Id));
        if (MoneyUtil.round(MoneyUtil.zeroIfNull(request.MRR_Proposto__c)) != expectedProposed) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_TOTAIS_DESATUALIZADOS,
                'Os totais da solicitação não conferem com seus itens. Salve a simulação novamente antes de enviar.'
            );
        }

        ctx.requireResolvedPlans();
        List<ItemResolutionPolicy.Line> lines = linesByRequest.get(request.Id);
        if (lines == null) {
            lines = new List<ItemResolutionPolicy.Line>();
        }
        ChangePlanner.validatePlanSwapConsistency(ctx, lines);
        ChangePlanner.validateLicenseLimits(ctx, lines);

        ApprovalMatrixPolicy.Result classification = ApprovalMatrixPolicy.classify(
            request.MRR_Base__c, expectedProposed, rules, settings.maxVariationPercent
        );
        ChangeRequestPolicy.requireNotBlocked(classification);
    }

    private Map<Id, List<ItemResolutionPolicy.Line>> loadLines(Set<Id> requestIds) {
        Map<Id, List<ItemResolutionPolicy.Line>> result = new Map<Id, List<ItemResolutionPolicy.Line>>();
        for (Item_Alteracao__c item : itemSelector.selectByRequestIds(requestIds)) {
            List<ItemResolutionPolicy.Line> bucket = result.get(item.Solicitacao__c);
            if (bucket == null) {
                bucket = new List<ItemResolutionPolicy.Line>();
                result.put(item.Solicitacao__c, bucket);
            }
            bucket.add(ItemResolutionPolicy.fromItem(item));
        }
        return result;
    }
}
