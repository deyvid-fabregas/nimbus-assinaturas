/**
 * @description Recalculo BULKIFICADO de MRR_Proposto__c, Variacao_Absoluta__c e Variacao_Percentual__c
 *              (escritor unico desses campos). Idempotente: derivado do banco (soma agregada dos deltas),
 *              nunca de incrementos, por isso serve igualmente a insert, update, delete e undelete.
 *
 *              Custo para N solicitacoes (N ate 200): 2 SOQL (pais + agregado de deltas) e 1 DML,
 *              independente de N. Solicitacoes sem itens: delta zero => proposto = base, variacao 0.
 *
 *              Recursao: RecursionGuard por ID + fingerprint (base|delta). Uma reentrada com o MESMO estado
 *              e descartada; estado diferente (reprocessamento legitimo) e aceito.
 *              Somente solicitacoes em Rascunho sao recalculadas: fora dele os itens estao congelados.
 */
public with sharing class RequestRecalculationService {
    @TestVisible private static final String GUARD_SCOPE = 'RequestRecalculation';

    private final RequestSelector requestSelector = new RequestSelector();
    private final RequestItemSelector itemSelector = new RequestItemSelector();

    /** Devolve quantas solicitacoes foram efetivamente atualizadas. */
    public Integer recalculate(Set<Id> requestIds) {
        if (CollectionUtil.isNullOrEmpty(requestIds)) {
            return 0;
        }
        // Pais excluidos (cascata) nao voltam na consulta: simplesmente nao ha o que recalcular.
        Map<Id, Solicitacao_Alteracao__c> requests = requestSelector.mapByIds(requestIds);
        if (requests.isEmpty()) {
            return 0;
        }
        Map<Id, Decimal> deltas = itemSelector.sumDeltaByRequestIds(requests.keySet());

        Map<Id, String> fingerprints = new Map<Id, String>();
        for (Solicitacao_Alteracao__c request : requests.values()) {
            if (request.Status__c == SubscriptionConstants.REQ_RASCUNHO) {
                fingerprints.put(
                    request.Id,
                    String.valueOf(MoneyUtil.zeroIfNull(request.MRR_Base__c)) + '|'
                        + String.valueOf(MoneyUtil.zeroIfNull(deltas.get(request.Id)))
                );
            }
        }
        Set<Id> accepted = RecursionGuard.enter(GUARD_SCOPE, fingerprints);
        try {
            List<Solicitacao_Alteracao__c> changes = new List<Solicitacao_Alteracao__c>();
            for (Id requestId : accepted) {
                Solicitacao_Alteracao__c request = requests.get(requestId);
                Decimal totalDelta = MoneyUtil.round(MoneyUtil.zeroIfNull(deltas.get(requestId)));
                Decimal proposed = MrrCalculator.proposedMrr(request.MRR_Base__c, totalDelta);
                MrrCalculator.Variation variation = MrrCalculator.compute(request.MRR_Base__c, proposed);
                if (isUnchanged(request, variation)) {
                    continue;
                }
                changes.add(
                    new Solicitacao_Alteracao__c(
                        Id = requestId,
                        MRR_Proposto__c = variation.proposedMrr,
                        Variacao_Absoluta__c = variation.absolute,
                        Variacao_Percentual__c = variation.percent
                    )
                );
            }
            CalculatedFieldWriter.updateRequestTotals(changes);
            return changes.size();
        } finally {
            RecursionGuard.exit(GUARD_SCOPE, accepted);
        }
    }

    private static Boolean isUnchanged(Solicitacao_Alteracao__c request, MrrCalculator.Variation variation) {
        return request.MRR_Proposto__c == variation.proposedMrr
            && request.Variacao_Absoluta__c == variation.absolute
            && request.Variacao_Percentual__c == variation.percent;
    }
}
