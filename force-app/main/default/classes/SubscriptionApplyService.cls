/**
 * @description US-06: aplicacao ATOMICA de uma alteracao aprovada ao contrato. Gera itens atualizados, Aditivo e
 *              Order recorrente (um OrderItem por linha alterada) sem duplicar, mesmo sob concorrencia.
 *
 *              ORDEM DE LOCKS (unica do modulo): Solicitacao -> Contrato (FOR UPDATE), estado revalidado DEPOIS do lock.
 *              BARREIRAS contra duplicidade (de proposito mais de uma, cada uma cobre uma falha diferente):
 *               1) lock pessimista: serializa chamadas concorrentes da mesma solicitacao/contrato;
 *               2) versionamento otimista (Contrato.Versao__c x Versao_Contrato_Base__c): detecta outro aditivo aplicado
 *                  depois da simulacao (a solicitacao vira Expirada);
 *               3) Aditivo_Contrato__c.Chave_Unica__c (SolicitacaoId-Ciclo, External ID unico): ultima barreira, vale ate
 *                  para chamadas que nao passaram pelo lock (DUPLICATE_VALUE => devolve o resultado existente).
 *
 *              ATOMICIDADE: Savepoint no inicio; qualquer erro => Database.rollback (itens, plano, versao, Aditivo, Order e
 *              OrderItems voltam). Depois do rollback grava-se Log_Tecnico__c (persiste) e devolve-se mensagem amigavel; a
 *              solicitacao continua Aprovada e pode ser reprocessada. Nao lanca excecao (ver Controller).
 *              Excecao deliberada ao rollback: versao desatualizada MARCA a solicitacao Expirada (com historico) e commita.
 *
 *              ESCRITAS: Status -> Aplicada/Expirada em USER_MODE sob StatusTransitionContext; itens, contrato, Aditivo e
 *              Order via ContractApplyWriter (isolada; justificativa no cabecalho dela) com ControlledWriteContext aberto.
 *
 *              Limites (1 solicitacao, ate 200 itens): ~12 SOQL e ~10 DML, sem SOQL/DML em loop. Contratos com milhares de
 *              itens exigiriam Queueable/Batch (ver RESPOSTAS_CODE_REVIEW.md).
 */
public virtual with sharing class SubscriptionApplyService {
    private final RequestSelector requestSelector = new RequestSelector();
    private final ContractSelector contractSelector = new ContractSelector();
    private final ContractItemSelector contractItemSelector = new ContractItemSelector();
    private final RequestItemSelector requestItemSelector = new RequestItemSelector();
    private final PlanSelector planSelector = new PlanSelector();
    private final AdditiveSelector additives = new AdditiveSelector();
    private final PricebookResolver pricebookResolver = new PricebookResolver();

    public virtual SubscriptionApplyResultDTO apply(Id requestId) {
        if (requestId == null) {
            return SubscriptionApplyResultDTO.failure(null, SubscriptionConstants.ERR_ENTRADA_INVALIDA, 'Informe a solicitação a aplicar.');
        }
        Savepoint checkpoint = Database.setSavepoint();
        try {
            SecurityGuard.requireCustomPermission(
                SubscriptionConstants.PERM_APLICAR_ALTERACAO,
                'Você não possui a permissão necessária para aplicar alterações de assinatura.'
            );
            SecurityGuard.requireUpdateable(Solicitacao_Alteracao__c.SObjectType);

            // 1) lock da solicitacao e idempotencia
            List<Solicitacao_Alteracao__c> lockedRequests = requestSelector.selectByIdsForUpdate(new Set<Id>{ requestId });
            if (lockedRequests.isEmpty()) {
                throw new SubscriptionException(
                    SubscriptionConstants.ERR_NAO_ENCONTRADO,
                    'A solicitação não foi encontrada ou você não tem acesso a ela.'
                );
            }
            Solicitacao_Alteracao__c request = lockedRequests[0];
            String uniqueKey = AdditiveSelector.uniqueKey(request.Id, request.Ciclo_Aprovacao__c);
            List<Aditivo_Contrato__c> existing = additives.selectByUniqueKeys(new Set<String>{ uniqueKey });
            if (!existing.isEmpty()) {
                return alreadyApplied(request.Id, existing[0]);
            }

            // 2) estado da solicitacao (depois do lock)
            requireApprovedStatus(request);

            // 3) lock do contrato e revalidacao
            List<Contrato_Assinatura__c> lockedContracts = contractSelector.selectByIdsForUpdate(new Set<Id>{ request.Contrato__c });
            if (lockedContracts.isEmpty()) {
                throw new SubscriptionException(
                    SubscriptionConstants.ERR_NAO_ENCONTRADO,
                    'O contrato da solicitação não foi encontrado ou você não tem acesso a ele.'
                );
            }
            Contrato_Assinatura__c contract = lockedContracts[0];
            ChangeRequestPolicy.requireActiveContract(contract.Status__c);
            if (request.Data_Efetivacao__c == null || request.Data_Efetivacao__c > SubscriptionClock.today()) {
                throw new SubscriptionException(
                    SubscriptionConstants.ERR_DATA_EFETIVACAO_FUTURA,
                    'A alteração só pode ser aplicada a partir da data de efetivação'
                        + (request.Data_Efetivacao__c == null ? '.' : ' (' + request.Data_Efetivacao__c.format() + ').')
                );
            }

            // 4) controle otimista de concorrencia
            if (ChangeRequestPolicy.isVersionStale(contract.Versao__c, request.Versao_Contrato_Base__c)) {
                return expire(request, contract);
            }

            // 5) montagem das mudancas (sem DML)
            List<Item_Alteracao__c> lines = requestItemSelector.selectByRequestIds(new Set<Id>{ request.Id });
            if (lines.isEmpty()) {
                throw new SubscriptionException(
                    SubscriptionConstants.ERR_SEM_ALTERACAO,
                    'A solicitação não possui itens para aplicar.'
                );
            }
            Set<Id> planIds = new Set<Id>{ contract.Plano_Atual__c };
            if (request.Plano_Proposto__c != null) {
                planIds.add(request.Plano_Proposto__c);
            }
            Map<Id, Plano_Assinatura__c> plans = planSelector.mapByIds(planIds);
            Plano_Assinatura__c effectivePlan = plans.get(request.Plano_Proposto__c != null ? request.Plano_Proposto__c : contract.Plano_Atual__c);
            if (effectivePlan == null) {
                throw new SubscriptionException(
                    SubscriptionConstants.ERR_NAO_ENCONTRADO,
                    'O plano da solicitação não foi encontrado ou você não tem acesso a ele.'
                );
            }
            if (request.Plano_Proposto__c != null) {
                ChangeRequestPolicy.requireActivePlan(effectivePlan.Ativo__c);
            }
            Map<Id, Item_Contrato__c> activeItems = new Map<Id, Item_Contrato__c>(
                contractItemSelector.selectActiveByContractIds(new Set<Id>{ contract.Id })
            );
            List<Item_Contrato__c> toInsert = new List<Item_Contrato__c>();
            List<Item_Contrato__c> toUpdate = new List<Item_Contrato__c>();
            Boolean stale = buildItemChanges(lines, activeItems, contract, effectivePlan, toInsert, toUpdate);
            if (stale) {
                return expire(request, contract);
            }

            // 6) precos do Order (Pricebook + PricebookEntry), em lote
            Id pricebookId = pricebookResolver.resolvePricebookIds(new List<Contrato_Assinatura__c>{ contract }).get(contract.Id);
            if (pricebookId == null) {
                throw new SubscriptionException(
                    SubscriptionConstants.ERR_PRECO_AUSENTE,
                    'O contrato não possui Pricebook e o Pricebook padrão configurado não foi encontrado. Contate o administrador.'
                );
            }
            Set<Id> productIds = new Set<Id>();
            for (Item_Alteracao__c line : lines) {
                productIds.add(line.Produto__c);
            }
            Map<Id, PricebookEntry> entries = pricebookResolver.resolveEntries(pricebookId, productIds);
            requireAllPrices(lines, entries);

            // 7) escrita atomica
            Decimal newVersion = MoneyUtil.zeroIfNull(contract.Versao__c) + 1;
            ControlledWriteContext.Scope itemScope = ControlledWriteContext.open(
                new Set<Id>{ contract.Id }, 'Aplicação da alteração ' + request.Name + ' (SubscriptionApplyService)'
            );
            try {
                ContractApplyWriter.writeItems(toInsert, toUpdate);
            } finally {
                itemScope.close();
            }
            requireConsistentMrr(contract.Id, request);
            ContractApplyWriter.updateContract(contract.Id, request.Plano_Proposto__c, newVersion);

            Id orderId = ContractApplyWriter.insertOrder(buildOrder(contract, request, pricebookId, newVersion), buildOrderItems(lines, entries));
            Id additiveId = ContractApplyWriter.insertAdditive(
                new Aditivo_Contrato__c(
                    Contrato__c = contract.Id,
                    Solicitacao__c = request.Id,
                    Chave_Unica__c = uniqueKey,
                    Versao_Resultante__c = newVersion,
                    MRR_Anterior__c = contract.MRR_Atual__c,
                    MRR_Novo__c = request.MRR_Proposto__c,
                    Data_Efetivacao__c = request.Data_Efetivacao__c,
                    Order__c = orderId
                )
            );
            setStatus(request.Id, SubscriptionConstants.REQ_APLICADA);

            SubscriptionApplyResultDTO result = new SubscriptionApplyResultDTO();
            result.success = true;
            result.requestId = request.Id;
            result.status = SubscriptionConstants.REQ_APLICADA;
            result.additiveId = additiveId;
            result.orderId = orderId;
            result.contractVersion = newVersion;
            result.newMrr = request.MRR_Proposto__c;
            result.message = 'Alteração aplicada ao contrato (versão ' + newVersion.intValue() + ').';
            return result;
        } catch (SubscriptionException businessError) {
            Database.rollback(checkpoint);
            return SubscriptionApplyResultDTO.failure(requestId, businessError.code, businessError.getMessage());
        } catch (DmlException dmlError) {
            Database.rollback(checkpoint);
            SubscriptionApplyResultDTO concurrent = resultIfDuplicateKey(requestId, dmlError);
            if (concurrent != null) {
                return concurrent;
            }
            return unexpected(requestId, dmlError);
        } catch (Exception unknownError) {
            Database.rollback(checkpoint);
            return unexpected(requestId, unknownError);
        }
    }

    // ------------------------------------------------------------------ regras

    private static void requireApprovedStatus(Solicitacao_Alteracao__c request) {
        if (request.Status__c == SubscriptionConstants.REQ_APROVADA) {
            return;
        }
        String reason;
        if (request.Status__c == SubscriptionConstants.REQ_PENDENTE) {
            reason = 'está pendente de decisão do aprovador';
        } else if (request.Status__c == SubscriptionConstants.REQ_REJEITADA) {
            reason = 'foi rejeitada';
        } else if (request.Status__c == SubscriptionConstants.REQ_CANCELADA) {
            reason = 'foi cancelada';
        } else if (request.Status__c == SubscriptionConstants.REQ_EXPIRADA) {
            reason = 'expirou; refaça a simulação';
        } else if (request.Status__c == SubscriptionConstants.REQ_APLICADA) {
            reason = 'já foi aplicada';
        } else {
            reason = 'ainda não foi enviada para aprovação';
        }
        throw new SubscriptionException(
            SubscriptionConstants.ERR_STATUS_NAO_APLICAVEL,
            'Somente solicitações Aprovadas podem ser aplicadas: esta solicitação ' + reason + '.'
        );
    }

    /** Devolve true quando algum item de contrato referenciado nao esta mais como na simulacao (alteracao concorrente). */
    private static Boolean buildItemChanges(
        List<Item_Alteracao__c> lines,
        Map<Id, Item_Contrato__c> activeItems,
        Contrato_Assinatura__c contract,
        Plano_Assinatura__c effectivePlan,
        List<Item_Contrato__c> toInsert,
        List<Item_Contrato__c> toUpdate
    ) {
        for (Item_Alteracao__c line : lines) {
            if (line.Acao__c == SubscriptionConstants.ACAO_ADICIONAR) {
                toInsert.add(
                    new Item_Contrato__c(
                        Contrato__c = contract.Id,
                        Produto__c = line.Produto__c,
                        Tipo__c = line.Produto__c == effectivePlan.Produto__c
                            ? SubscriptionConstants.ITEM_TIPO_LICENCA
                            : SubscriptionConstants.ITEM_TIPO_RECURSO,
                        Quantidade__c = line.Quantidade_Nova__c,
                        Preco_Unitario_Mensal__c = line.Preco_Unitario_Mensal__c,
                        Status__c = SubscriptionConstants.ITEM_ATIVO
                    )
                );
                continue;
            }
            Item_Contrato__c current = activeItems.get(line.Item_Contrato__c);
            if (current == null || current.Quantidade__c != line.Quantidade_Atual__c) {
                return true;
            }
            if (line.Acao__c == SubscriptionConstants.ACAO_ALTERAR_QTD) {
                toUpdate.add(new Item_Contrato__c(Id = current.Id, Quantidade__c = line.Quantidade_Nova__c));
            } else {
                toUpdate.add(new Item_Contrato__c(Id = current.Id, Status__c = SubscriptionConstants.ITEM_REMOVIDO));
            }
        }
        return false;
    }

    private static void requireAllPrices(List<Item_Alteracao__c> lines, Map<Id, PricebookEntry> entries) {
        Set<String> missing = new Set<String>();
        for (Item_Alteracao__c line : lines) {
            if (!entries.containsKey(line.Produto__c)) {
                missing.add(line.Produto__r.Name);
            }
        }
        if (!missing.isEmpty()) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_PRECO_AUSENTE,
                'Não há entrada de preço ativa no Pricebook do contrato para: ' + String.join(new List<String>(missing), ', ')
                    + '. Solicite o cadastro e tente novamente; a solicitação continua Aprovada.'
            );
        }
    }

    /** Integridade: o MRR do contrato (recalculado pela Trigger dos itens) deve igualar o MRR proposto aprovado. */
    private void requireConsistentMrr(Id contractId, Solicitacao_Alteracao__c request) {
        List<Contrato_Assinatura__c> reloaded = contractSelector.selectByIds(new Set<Id>{ contractId });
        Decimal actual = reloaded.isEmpty() ? null : MoneyUtil.round(MoneyUtil.zeroIfNull(reloaded[0].MRR_Atual__c));
        if (actual == null || actual != MoneyUtil.round(MoneyUtil.zeroIfNull(request.MRR_Proposto__c))) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_TOTAIS_DESATUALIZADOS,
                'O MRR resultante não confere com o MRR aprovado. Nada foi aplicado; refaça a simulação.'
            );
        }
    }

    private static Order buildOrder(Contrato_Assinatura__c contract, Solicitacao_Alteracao__c request, Id pricebookId, Decimal newVersion) {
        return new Order(
            AccountId = contract.Account__c,
            EffectiveDate = request.Data_Efetivacao__c,
            Status = SubscriptionConstants.ORDER_STATUS_DRAFT,
            Pricebook2Id = pricebookId,
            Name = 'Aditivo ' + contract.Name + ' v' + newVersion.intValue(),
            Description = 'Pedido recorrente mensal gerado pela solicitação ' + request.Name
                + '. Quantidades são variações (positivas = acréscimo, negativas = redução) a partir de '
                + String.valueOf(request.Data_Efetivacao__c) + '.'
        );
    }

    /** Um OrderItem por linha: Quantity = variacao de quantidade (assinada); UnitPrice = preco mensal da linha. */
    private static List<OrderItem> buildOrderItems(List<Item_Alteracao__c> lines, Map<Id, PricebookEntry> entries) {
        List<OrderItem> items = new List<OrderItem>();
        for (Item_Alteracao__c line : lines) {
            Decimal currentQuantity = MoneyUtil.zeroIfNull(line.Quantidade_Atual__c);
            Decimal newQuantity = MoneyUtil.zeroIfNull(line.Quantidade_Nova__c);
            items.add(
                new OrderItem(
                    PricebookEntryId = entries.get(line.Produto__c).Id,
                    Quantity = newQuantity - currentQuantity,
                    UnitPrice = line.Preco_Unitario_Mensal__c,
                    Description = line.Acao__c + ' (de ' + currentQuantity.intValue() + ' para ' + newQuantity.intValue() + ')'
                )
            );
        }
        return items;
    }

    // ------------------------------------------------------------------ expiracao, idempotencia, erros

    /** Versao desatualizada: marca Expirada com historico e COMMITA (nada do contrato foi alterado). */
    private SubscriptionApplyResultDTO expire(Solicitacao_Alteracao__c request, Contrato_Assinatura__c contract) {
        setStatus(request.Id, SubscriptionConstants.REQ_EXPIRADA);
        AuthorizedSystemWriter.insertHistory(
            new List<Historico_Decisao__c>{
                new Historico_Decisao__c(
                    Solicitacao__c = request.Id,
                    Ciclo__c = request.Ciclo_Aprovacao__c,
                    Decisao__c = SubscriptionConstants.DEC_EXPIRADA,
                    Nivel__c = request.Nivel_Aprovacao__c,
                    Usuario__c = UserInfo.getUserId(),
                    Data_Hora__c = SubscriptionClock.now(),
                    Motivo__c = 'O contrato mudou desde a simulação (versão ' + MoneyUtil.zeroIfNull(contract.Versao__c).intValue()
                        + ' no contrato; ' + MoneyUtil.zeroIfNull(request.Versao_Contrato_Base__c).intValue() + ' na simulação).'
                )
            }
        );
        SubscriptionApplyResultDTO result = SubscriptionApplyResultDTO.failure(
            request.Id,
            SubscriptionConstants.ERR_VERSAO_DESATUALIZADA,
            'A solicitação expirou porque o contrato foi alterado por outro aditivo depois da simulação. Faça uma nova simulação.'
        );
        result.status = SubscriptionConstants.REQ_EXPIRADA;
        return result;
    }

    private static void setStatus(Id requestId, String targetStatus) {
        StatusTransitionContext.Scope scope = StatusTransitionContext.open(
            new Set<Id>{ requestId }, new Set<String>{ targetStatus }, 'Aplicação da alteração (SubscriptionApplyService)'
        );
        try {
            Database.update(new Solicitacao_Alteracao__c(Id = requestId, Status__c = targetStatus), true, AccessLevel.USER_MODE);
        } finally {
            scope.close();
        }
    }

    private SubscriptionApplyResultDTO alreadyApplied(Id requestId, Aditivo_Contrato__c additive) {
        SubscriptionApplyResultDTO result = new SubscriptionApplyResultDTO();
        result.success = true;
        result.alreadyApplied = true;
        result.requestId = requestId;
        result.status = SubscriptionConstants.REQ_APLICADA;
        result.additiveId = additive.Id;
        result.orderId = additive.Order__c;
        result.contractVersion = additive.Versao_Resultante__c;
        result.newMrr = additive.MRR_Novo__c;
        result.message = 'Esta alteração já havia sido aplicada; o resultado existente foi devolvido.';
        return result;
    }

    /** Ultima barreira: indice unico de Chave_Unica__c violado por chamada concorrente => devolve o existente. */
    private SubscriptionApplyResultDTO resultIfDuplicateKey(Id requestId, DmlException error) {
        if (error.getNumDml() == 0 || error.getDmlType(0) != StatusCode.DUPLICATE_VALUE) {
            return null;
        }
        List<Solicitacao_Alteracao__c> reloaded = requestSelector.selectByIds(new Set<Id>{ requestId });
        if (reloaded.isEmpty()) {
            return null;
        }
        List<Aditivo_Contrato__c> existing = additives.selectByUniqueKeys(
            new Set<String>{ AdditiveSelector.uniqueKey(requestId, reloaded[0].Ciclo_Aprovacao__c) }
        );
        return existing.isEmpty() ? null : alreadyApplied(requestId, existing[0]);
    }

    /** Log persistente (gravado APOS o rollback) + mensagem amigavel; a solicitacao segue Aprovada e reprocessavel. */
    private static SubscriptionApplyResultDTO unexpected(Id requestId, Exception error) {
        Id logId = TechnicalLogger.log('SubscriptionApplyService', 'apply', requestId, error);
        SubscriptionApplyResultDTO result = SubscriptionApplyResultDTO.failure(
            requestId, SubscriptionConstants.ERR_INESPERADO, TechnicalLogger.friendlyMessage(error, logId)
        );
        result.message += ' A solicitação continua Aprovada e pode ser aplicada novamente.';
        return result;
    }
}
