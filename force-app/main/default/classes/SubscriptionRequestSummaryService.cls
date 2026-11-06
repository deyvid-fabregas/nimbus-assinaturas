/**
 * @description Monta o resumo da solicitacao (US-04/US-05) com SOQL em USER_MODE: 1 consulta da solicitacao com nomes,
 *              1 dos itens, 1 da Task aberta (tempo em espera) e 2 da designacao do usuario = 5 SOQL, sem DML.
 *              Os indicadores can* espelham as regras do servidor apenas para esconder/mostrar acoes; nunca autorizam nada.
 */
public with sharing class SubscriptionRequestSummaryService {
    private final RequestSelector requestSelector = new RequestSelector();
    private final RequestItemSelector itemSelector = new RequestItemSelector();
    private final TaskSelector taskSelector = new TaskSelector();
    private final DesignationSelector designation = new DesignationSelector();

    public SubscriptionRequestSummaryDTO build(Id requestId) {
        List<Solicitacao_Alteracao__c> found = requestSelector.selectSummaryById(requestId);
        if (found.isEmpty()) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_NAO_ENCONTRADO,
                'A solicitação não foi encontrada ou você não tem acesso a ela.'
            );
        }
        Solicitacao_Alteracao__c request = found[0];
        SubscriptionRequestSummaryDTO dto = new SubscriptionRequestSummaryDTO();
        dto.requestId = request.Id;
        dto.name = request.Name;
        dto.status = request.Status__c;
        dto.requestType = request.Tipo__c;
        dto.contractName = request.Contrato__r.Name;
        dto.currentPlanName = request.Contrato__r.Plano_Atual__r.Name;
        dto.proposedPlanName = request.Plano_Proposto__r == null ? null : request.Plano_Proposto__r.Name;
        dto.cycle = request.Ciclo_Aprovacao__c;
        dto.approvalLevel = request.Nivel_Aprovacao__c;
        dto.effectiveDate = request.Data_Efetivacao__c;
        dto.justification = request.Justificativa__c;
        dto.rejectionReason = request.Motivo_Rejeicao__c;
        dto.requesterName = request.CreatedBy.Name;
        dto.approverName = request.Aprovador__r == null ? null : request.Aprovador__r.Name;
        dto.decisionDate = request.Data_Decisao__c;
        dto.baseMrr = request.MRR_Base__c;
        dto.proposedMrr = request.MRR_Proposto__c;
        dto.absoluteVariation = request.Variacao_Absoluta__c;
        dto.percentVariation = request.Variacao_Percentual__c;

        for (Item_Alteracao__c item : itemSelector.selectByRequestIds(new Set<Id>{ request.Id })) {
            SubscriptionRequestSummaryDTO.Line line = new SubscriptionRequestSummaryDTO.Line();
            line.productName = item.Produto__r.Name;
            line.action = item.Acao__c;
            line.currentQuantity = item.Quantidade_Atual__c;
            line.newQuantity = item.Quantidade_Nova__c;
            line.unitPrice = item.Preco_Unitario_Mensal__c;
            line.deltaMrr = item.Delta_MRR__c;
            dto.lines.add(line);
        }

        ApprovalMatrixPolicy.Level level = ApprovalMatrixPolicy.levelFromLabel(request.Nivel_Aprovacao__c);
        List<ApprovalMatrixPolicy.Rule> rules = SubscriptionConfig.approvalRules();
        dto.expectedResponsible = responsibleLabel(level, rules);

        if (request.Status__c == SubscriptionConstants.REQ_PENDENTE) {
            List<Task> tasks = taskSelector.selectOpenByRequestId(request.Id);
            if (!tasks.isEmpty()) {
                Decimal elapsedMillis = Decimal.valueOf(SubscriptionClock.now().getTime() - tasks[0].CreatedDate.getTime());
                dto.waitingHours = (elapsedMillis / 3600000).setScale(1, RoundingMode.HALF_UP);
            }
        }
        applyAvailability(dto, request, level, rules);
        return dto;
    }

    private void applyAvailability(
        SubscriptionRequestSummaryDTO dto,
        Solicitacao_Alteracao__c request,
        ApprovalMatrixPolicy.Level level,
        List<ApprovalMatrixPolicy.Rule> rules
    ) {
        Id me = UserInfo.getUserId();
        Boolean isRequester = request.CreatedById == me;
        Boolean humanLevel = level != null
            && level != ApprovalMatrixPolicy.Level.AUTOMATICA
            && level != ApprovalMatrixPolicy.Level.BLOQUEADA;
        String permission = humanLevel ? ApprovalMatrixPolicy.customPermissionOf(level) : null;
        Boolean hasLevelPermission = permission != null && SecurityGuard.hasCustomPermission(permission);

        if (request.Status__c == SubscriptionConstants.REQ_RASCUNHO) {
            dto.canSubmit = true;
        } else if (request.Status__c == SubscriptionConstants.REQ_PENDENTE) {
            if (!humanLevel) {
                dto.unavailableReason = 'A solicitação ainda não foi roteada para um aprovador.';
            } else if (!hasLevelPermission) {
                dto.unavailableReason = 'Você não possui a permissão necessária para decidir este nível de alçada.';
            } else if (!isDesignated(level, rules)) {
                dto.unavailableReason = 'Você não está designado como aprovador deste nível.';
            } else if (isRequester) {
                dto.unavailableReason = 'Quem criou a solicitação não pode decidi-la.';
            } else {
                dto.canDecide = true;
            }
        } else if (request.Status__c == SubscriptionConstants.REQ_APROVADA) {
            if (!SecurityGuard.hasCustomPermission(SubscriptionConstants.PERM_APLICAR_ALTERACAO)) {
                dto.unavailableReason = 'Você não possui a permissão para aplicar alterações de assinatura.';
            } else if (request.Data_Efetivacao__c == null || request.Data_Efetivacao__c > SubscriptionClock.today()) {
                dto.unavailableReason = 'A alteração só pode ser aplicada a partir da data de efetivação'
                    + (request.Data_Efetivacao__c == null ? '.' : ' (' + request.Data_Efetivacao__c.format() + ').');
            } else {
                dto.canApply = true;
            }
        } else if (request.Status__c == SubscriptionConstants.REQ_REJEITADA) {
            if (isRequester || hasLevelPermission) {
                dto.canReopen = true;
            } else {
                dto.unavailableReason = 'Somente o solicitante ou um aprovador do nível pode reabrir a solicitação.';
            }
        }
    }

    private Boolean isDesignated(ApprovalMatrixPolicy.Level level, List<ApprovalMatrixPolicy.Rule> rules) {
        Set<String> myKeys = designation.keysForUser(UserInfo.getUserId());
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

    private static String responsibleLabel(ApprovalMatrixPolicy.Level level, List<ApprovalMatrixPolicy.Rule> rules) {
        if (level == null) {
            return null;
        }
        for (ApprovalMatrixPolicy.Rule rule : rules) {
            if (rule.level == level && !TextUtil.isBlank(rule.responsibleName)) {
                return rule.responsibleName + ' (' + rule.responsibleType + ')';
            }
        }
        return null;
    }
}
