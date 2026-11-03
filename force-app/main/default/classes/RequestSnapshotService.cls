/**
 * @description Regras SERVER-SIDE de criacao/edicao de Solicitacao_Alteracao__c em Rascunho (todos os canais).
 *
 *              prepareNew (before insert):
 *               - estado inicial somente Rascunho; contrato obrigatoriamente ATIVO; plano proposto ativo;
 *                 data de efetivacao valida (nao retroativa, dentro da janela configurada);
 *               - SNAPSHOT AUTORITATIVO: MRR_Base__c e Versao_Contrato_Base__c sao SOBRESCRITOS a partir do
 *                 contrato (soma agregada dos itens ativos). Um vendedor nao pode informar uma base menor
 *                 para reduzir o percentual de variacao e cair numa alcada mais baixa.
 *               - MRR_Proposto__c nasce igual a base, variacoes zero (o recalculo e do item).
 *              Custo: 3 SOQL (contratos, soma de MRR, planos) e 0 DML para qualquer tamanho de lote.
 */
public with sharing class RequestSnapshotService {
    private final ContractSelector contractSelector = new ContractSelector();
    private final ContractItemSelector itemSelector = new ContractItemSelector();
    private final PlanSelector planSelector = new PlanSelector();

    public Map<Integer, String> prepareNew(List<Solicitacao_Alteracao__c> records) {
        Map<Integer, String> errors = new Map<Integer, String>();
        if (records == null || records.isEmpty()) {
            return errors;
        }
        SubscriptionSettings settings = SubscriptionConfig.settings();
        Set<Id> contractIds = CollectionUtil.pluckIds(records, Solicitacao_Alteracao__c.Contrato__c);
        Map<Id, Contrato_Assinatura__c> contracts = contractSelector.mapByIds(contractIds);
        Map<Id, Decimal> mrrByContract = itemSelector.sumActiveMrrByContractIds(contractIds);
        Map<Id, Plano_Assinatura__c> plans = planSelector.mapByIds(
            CollectionUtil.pluckIds(records, Solicitacao_Alteracao__c.Plano_Proposto__c)
        );

        for (Integer i = 0; i < records.size(); i++) {
            Solicitacao_Alteracao__c record = records[i];
            try {
                String statusError = RequestStateMachine.initialStatusError(record.Status__c);
                if (statusError != null) {
                    throw new SubscriptionException(SubscriptionConstants.ERR_STATUS_INICIAL_INVALIDO, statusError);
                }
                Contrato_Assinatura__c contract = contracts.get(record.Contrato__c);
                if (contract == null) {
                    throw new SubscriptionException(
                        SubscriptionConstants.ERR_NAO_ENCONTRADO,
                        'O contrato não foi encontrado ou você não tem acesso a ele.'
                    );
                }
                ChangeRequestPolicy.requireActiveContract(contract.Status__c);
                requirePlan(record.Plano_Proposto__c, plans);
                ChangeRequestPolicy.requireEffectiveDate(
                    record.Data_Efetivacao__c, SubscriptionClock.today(), settings.effectiveWindowDays
                );

                Decimal base = MoneyUtil.round(MoneyUtil.zeroIfNull(mrrByContract.get(contract.Id)));
                record.Status__c = SubscriptionConstants.REQ_RASCUNHO;
                record.MRR_Base__c = base;
                record.Versao_Contrato_Base__c = MoneyUtil.zeroIfNull(contract.Versao__c);
                record.MRR_Proposto__c = base;
                record.Variacao_Absoluta__c = 0;
                record.Variacao_Percentual__c = 0;
            } catch (SubscriptionException businessError) {
                errors.put(i, businessError.getMessage());
            }
        }
        return errors;
    }

    /**
     * before update de um Rascunho que continua Rascunho: revalida data e plano quando mudaram.
     * Chave do resultado = Id da solicitacao.
     */
    public Map<Id, String> validateDraftChanges(List<Solicitacao_Alteracao__c> records) {
        Map<Id, String> errors = new Map<Id, String>();
        if (records == null || records.isEmpty()) {
            return errors;
        }
        SubscriptionSettings settings = SubscriptionConfig.settings();
        Map<Id, Plano_Assinatura__c> plans = planSelector.mapByIds(
            CollectionUtil.pluckIds(records, Solicitacao_Alteracao__c.Plano_Proposto__c)
        );
        for (Solicitacao_Alteracao__c record : records) {
            try {
                requirePlan(record.Plano_Proposto__c, plans);
                ChangeRequestPolicy.requireEffectiveDate(
                    record.Data_Efetivacao__c, SubscriptionClock.today(), settings.effectiveWindowDays
                );
            } catch (SubscriptionException businessError) {
                errors.put(record.Id, businessError.getMessage());
            }
        }
        return errors;
    }

    private static void requirePlan(Id planId, Map<Id, Plano_Assinatura__c> plans) {
        if (planId == null) {
            return;
        }
        Plano_Assinatura__c plan = plans.get(planId);
        ChangeRequestPolicy.requireActivePlan(plan != null && plan.Ativo__c == true);
    }
}
