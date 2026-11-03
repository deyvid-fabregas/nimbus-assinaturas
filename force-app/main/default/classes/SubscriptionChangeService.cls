/**
 * @description US-01: simulacao (sem DML) e gravacao de Rascunho de alteracao contratual.
 *              O cliente envia apenas INTENCAO (SubscriptionChangeRequestDTO). Tudo que e valor (preco, delta,
 *              totais, tipo, nivel previsto) e calculado AQUI e, na gravacao, REVALIDADO pelas Triggers
 *              (RequestItemService/RequestSnapshotService), que e quem garante as regras para API/Data Loader.
 *
 *              Contrato de erros: lanca SubscriptionException (mensagem amigavel + codigo estavel). Falha
 *              inesperada: rollback ao Savepoint, TechnicalLogger.log (apos o rollback) e SubscriptionException
 *              com mensagem generica + codigo de referencia. O CONTROLLER deve CAPTURAR e devolver o resultado
 *              (SubscriptionChangeResultDTO.failure); se a excecao escapar do @AuraEnabled a plataforma reverte
 *              a transacao inteira e o log se perde.
 *
 *              Idempotencia: mesma Chave_Idempotencia__c devolve a solicitacao existente (pre-checagem) e, sob
 *              concorrencia, o indice unico do External ID e a barreira final (DUPLICATE_VALUE => devolve a
 *              existente). Edicao (requestId informado) so em Rascunho; substitui os itens (delete + insert).
 *
 *              Seguranca: with sharing; DML em USER_MODE (CRUD/FLS do usuario nos campos de INTENCAO). Campos
 *              calculados sao escritos pelas Triggers/CalculatedFieldWriter, nunca por este Service.
 */
public with sharing class SubscriptionChangeService {
    private static final String DRAFT_KEY = 'draft';

    private final ChangeContextLoader loader = new ChangeContextLoader();
    private final RequestSelector requestSelector = new RequestSelector();
    private final RequestItemSelector requestItemSelector = new RequestItemSelector();

    public class Evaluation {
        public ChangeContext context;
        public ChangePlanner.Plan plan;
        public ApprovalMatrixPolicy.Result classification;
    }

    // ------------------------------------------------------------------ simulacao

    /** Previa: valida, calcula e devolve MRR/variacoes/nivel previsto. Nada e gravado. */
    public SubscriptionChangeResultDTO simulate(SubscriptionChangeRequestDTO dto) {
        requireDto(dto);
        SecurityGuard.requireReadable(Contrato_Assinatura__c.SObjectType);
        Evaluation evaluation = evaluate(dto, false);

        SubscriptionChangeResultDTO result = new SubscriptionChangeResultDTO();
        result.contractId = dto.contractId;
        result.proposedPlanId = evaluation.context.isPlanChange() ? dto.proposedPlanId : null;
        result.effectiveDate = dto.effectiveDate;
        result.requestType = evaluation.plan.requestType;
        result.baseMrr = evaluation.classification.variation.baseMrr;
        result.proposedMrr = evaluation.classification.variation.proposedMrr;
        result.absoluteVariation = evaluation.classification.variation.absolute;
        result.percentVariation = evaluation.classification.variation.percent;
        applyClassification(result, evaluation.classification);
        for (ItemResolutionPolicy.Line line : evaluation.plan.lines) {
            result.lines.add(toLineDto(line));
        }
        return result;
    }

    // ------------------------------------------------------------------ gravacao

    public SubscriptionChangeResultDTO saveDraft(SubscriptionChangeRequestDTO dto) {
        requireDto(dto);
        SecurityGuard.requireCreateable(Solicitacao_Alteracao__c.SObjectType);
        SecurityGuard.requireCreateable(Item_Alteracao__c.SObjectType);

        String key = TextUtil.isBlank(dto.idempotencyKey) ? null : dto.idempotencyKey.trim();
        Solicitacao_Alteracao__c editing = null;
        if (dto.requestId == null) {
            if (key == null) {
                throw new SubscriptionException(
                    SubscriptionConstants.ERR_CHAVE_IDEMPOTENCIA,
                    'Informe a chave de idempotência para salvar a solicitação.'
                );
            }
            Solicitacao_Alteracao__c existing = findByKey(key);
            if (existing != null) {
                return buildPersisted(existing.Id, true);
            }
        } else {
            editing = loadEditableDraft(dto);
        }

        Savepoint checkpoint = Database.setSavepoint();
        try {
            Evaluation evaluation = evaluate(dto, true);
            if (editing != null
                && ChangeRequestPolicy.isVersionStale(evaluation.context.contract.Versao__c, editing.Versao_Contrato_Base__c)) {
                throw new SubscriptionException(
                    SubscriptionConstants.ERR_VERSAO_DESATUALIZADA,
                    'O contrato foi alterado desde a criação deste rascunho. Faça uma nova simulação.'
                );
            }
            Id requestId = persist(dto, evaluation, key, editing);
            return buildPersisted(requestId, false);
        } catch (SubscriptionException businessError) {
            Database.rollback(checkpoint);
            throw businessError;
        } catch (DmlException dmlError) {
            Database.rollback(checkpoint);
            if (dto.requestId == null && isDuplicateKey(dmlError)) {
                Solicitacao_Alteracao__c winner = findByKey(key);
                if (winner != null) {
                    return buildPersisted(winner.Id, true);
                }
            }
            throw unexpected(dmlError, dto);
        } catch (Exception unknownError) {
            Database.rollback(checkpoint);
            throw unexpected(unknownError, dto);
        }
    }

    // ------------------------------------------------------------------ avaliacao (sem DML)

    @TestVisible
    private Evaluation evaluate(SubscriptionChangeRequestDTO dto, Boolean forSave) {
        SubscriptionSettings settings = SubscriptionConfig.settings();
        Set<Id> productsToPrice = new Set<Id>();
        for (SubscriptionChangeRequestDTO.ItemDTO item : dto.items) {
            if (item != null && item.action == SubscriptionConstants.ACAO_ADICIONAR && item.productId != null) {
                productsToPrice.add(item.productId);
            }
        }
        Map<String, ChangeContextLoader.Spec> specs = new Map<String, ChangeContextLoader.Spec>{
            DRAFT_KEY => new ChangeContextLoader.Spec(dto.contractId, dto.proposedPlanId)
        };
        ChangeContext ctx = loader.load(specs, productsToPrice).get(DRAFT_KEY);
        if (ctx == null) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_NAO_ENCONTRADO,
                'O contrato não foi encontrado ou você não tem acesso a ele.'
            );
        }
        ChangeRequestPolicy.requireActiveContract(ctx.contract.Status__c);
        if (forSave || dto.effectiveDate != null) {
            ChangeRequestPolicy.requireEffectiveDate(dto.effectiveDate, SubscriptionClock.today(), settings.effectiveWindowDays);
        }
        if (forSave) {
            ChangeRequestPolicy.requireJustification(dto.justification, settings.minJustificationLength);
        }

        Evaluation evaluation = new Evaluation();
        evaluation.context = ctx;
        evaluation.plan = ChangePlanner.plan(dto.items, ctx);
        evaluation.classification = ApprovalMatrixPolicy.classify(
            evaluation.plan.baseMrr,
            evaluation.plan.proposedMrr,
            SubscriptionConfig.approvalRules(),
            settings.maxVariationPercent
        );
        if (forSave) {
            ChangeRequestPolicy.requireNotBlocked(evaluation.classification);
        }
        return evaluation;
    }

    // ------------------------------------------------------------------ persistencia

    private Id persist(
        SubscriptionChangeRequestDTO dto,
        Evaluation evaluation,
        String key,
        Solicitacao_Alteracao__c editing
    ) {
        Id planId = evaluation.context.isPlanChange() ? dto.proposedPlanId : null;
        Id requestId;
        if (editing == null) {
            // Snapshot (MRR_Base__c / Versao_Contrato_Base__c), status e totais iniciais: Trigger before insert.
            Solicitacao_Alteracao__c request = new Solicitacao_Alteracao__c(
                Contrato__c = dto.contractId,
                Plano_Proposto__c = planId,
                Tipo__c = evaluation.plan.requestType,
                Data_Efetivacao__c = dto.effectiveDate,
                Justificativa__c = dto.justification,
                Chave_Idempotencia__c = key,
                Status__c = SubscriptionConstants.REQ_RASCUNHO
            );
            Database.insert(request, true, AccessLevel.USER_MODE);
            requestId = request.Id;
        } else {
            requestId = editing.Id;
            List<Item_Alteracao__c> previous = requestItemSelector.selectByRequestIds(new Set<Id>{ requestId });
            if (!previous.isEmpty()) {
                Database.delete(previous, true, AccessLevel.USER_MODE);
            }
            Solicitacao_Alteracao__c changes = new Solicitacao_Alteracao__c(
                Id = requestId,
                Plano_Proposto__c = planId,
                Tipo__c = evaluation.plan.requestType,
                Data_Efetivacao__c = dto.effectiveDate,
                Justificativa__c = dto.justification
            );
            Database.update(changes, true, AccessLevel.USER_MODE);
        }

        // Somente INTENCAO; Quantidade_Atual__c, preco e delta sao resolvidos pela Trigger.
        List<Item_Alteracao__c> items = new List<Item_Alteracao__c>();
        for (ItemResolutionPolicy.Line line : evaluation.plan.lines) {
            items.add(
                new Item_Alteracao__c(
                    Solicitacao__c = requestId,
                    Item_Contrato__c = line.contractItemId,
                    Produto__c = line.productId,
                    Acao__c = line.action,
                    Quantidade_Nova__c = line.newQuantity
                )
            );
        }
        Database.insert(items, true, AccessLevel.USER_MODE);
        return requestId;
    }

    private Solicitacao_Alteracao__c loadEditableDraft(SubscriptionChangeRequestDTO dto) {
        List<Solicitacao_Alteracao__c> found = requestSelector.selectByIds(new Set<Id>{ dto.requestId });
        if (found.isEmpty()) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_NAO_ENCONTRADO,
                'A solicitação não foi encontrada ou você não tem acesso a ela.'
            );
        }
        Solicitacao_Alteracao__c request = found[0];
        if (request.Contrato__c != dto.contractId) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_ENTRADA_INVALIDA,
                'A solicitação informada pertence a outro contrato.'
            );
        }
        if (request.Status__c != SubscriptionConstants.REQ_RASCUNHO) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_SOLICITACAO_NAO_EDITAVEL,
                request.Status__c == SubscriptionConstants.REQ_REJEITADA
                    ? 'Reabra a solicitação rejeitada (voltando-a para Rascunho) antes de editá-la.'
                    : 'Somente solicitações em Rascunho podem ser editadas (status atual: ' + request.Status__c + ').'
            );
        }
        return request;
    }

    private Solicitacao_Alteracao__c findByKey(String key) {
        List<Solicitacao_Alteracao__c> found = requestSelector.selectByIdempotencyKeys(new Set<String>{ key });
        return found.isEmpty() ? null : found[0];
    }

    // ------------------------------------------------------------------ resultado (sempre do que foi PERSISTIDO)

    private SubscriptionChangeResultDTO buildPersisted(Id requestId, Boolean reused) {
        Solicitacao_Alteracao__c request = requestSelector.selectByIds(new Set<Id>{ requestId })[0];
        SubscriptionSettings settings = SubscriptionConfig.settings();

        SubscriptionChangeResultDTO result = new SubscriptionChangeResultDTO();
        result.reusedExisting = reused;
        result.requestId = request.Id;
        result.requestName = request.Name;
        result.status = request.Status__c;
        result.requestType = request.Tipo__c;
        result.contractId = request.Contrato__c;
        result.proposedPlanId = request.Plano_Proposto__c;
        result.effectiveDate = request.Data_Efetivacao__c;
        result.baseMrr = request.MRR_Base__c;
        result.proposedMrr = request.MRR_Proposto__c;
        result.absoluteVariation = request.Variacao_Absoluta__c;
        result.percentVariation = request.Variacao_Percentual__c;
        applyClassification(
            result,
            ApprovalMatrixPolicy.classify(
                request.MRR_Base__c, request.MRR_Proposto__c, SubscriptionConfig.approvalRules(), settings.maxVariationPercent
            )
        );
        for (Item_Alteracao__c item : requestItemSelector.selectByRequestIds(new Set<Id>{ requestId })) {
            result.lines.add(toLineDto(ItemResolutionPolicy.fromItem(item)));
        }
        return result;
    }

    private static void applyClassification(SubscriptionChangeResultDTO result, ApprovalMatrixPolicy.Result classification) {
        result.approvalLevel = classification.levelLabel();
        result.responsibleType = classification.responsibleType;
        result.responsibleName = classification.responsibleName;
        result.blocked = classification.blocked;
        result.blockMessage = classification.blockMessage;
    }

    private static SubscriptionChangeResultDTO.LineDTO toLineDto(ItemResolutionPolicy.Line line) {
        SubscriptionChangeResultDTO.LineDTO dto = new SubscriptionChangeResultDTO.LineDTO();
        dto.contractItemId = line.contractItemId;
        dto.productId = line.productId;
        dto.action = line.action;
        dto.currentQuantity = line.currentQuantity;
        dto.newQuantity = line.newQuantity;
        dto.unitPrice = line.unitPrice;
        dto.deltaMrr = line.delta;
        return dto;
    }

    // ------------------------------------------------------------------ erros

    private static void requireDto(SubscriptionChangeRequestDTO dto) {
        if (dto == null || dto.contractId == null) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_ENTRADA_INVALIDA,
                'Informe o contrato da alteração.'
            );
        }
        if (dto.items == null) {
            dto.items = new List<SubscriptionChangeRequestDTO.ItemDTO>();
        }
    }

    private static Boolean isDuplicateKey(DmlException error) {
        return error.getNumDml() > 0 && error.getDmlType(0) == StatusCode.DUPLICATE_VALUE;
    }

    private static Boolean isBusinessRule(Exception error) {
        if (error instanceof DmlException) {
            DmlException dml = (DmlException) error;
            return dml.getNumDml() > 0 && dml.getDmlType(0) == StatusCode.FIELD_CUSTOM_VALIDATION_EXCEPTION;
        }
        return false;
    }

    /** Regra de negocio barrada pela Trigger => mensagem amigavel; qualquer outra coisa => log persistente. */
    private static SubscriptionException unexpected(Exception error, SubscriptionChangeRequestDTO dto) {
        if (isBusinessRule(error)) {
            return new SubscriptionException(
                SubscriptionConstants.ERR_ENTRADA_INVALIDA,
                TechnicalLogger.friendlyMessage(error, null)
            );
        }
        Id logId = TechnicalLogger.log('SubscriptionChangeService', 'saveDraft', dto == null ? null : dto.contractId, error);
        return new SubscriptionException(SubscriptionConstants.ERR_INESPERADO, TechnicalLogger.friendlyMessage(error, logId));
    }
}
