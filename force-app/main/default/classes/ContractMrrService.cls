/**
 * @description Mantem Contrato_Assinatura__c.MRR_Atual__c = soma do MRR dos itens ATIVOS (escritor unico,
 *              acionado pela Trigger de Item_Contrato__c). Derivado do banco (agregado), nunca incremental.
 *              Custo: 2 SOQL e no maximo 1 DML para qualquer quantidade de contratos do lote.
 */
public with sharing class ContractMrrService {
    private final ContractSelector contractSelector = new ContractSelector();
    private final ContractItemSelector itemSelector = new ContractItemSelector();

    /** Devolve quantos contratos tiveram MRR_Atual__c atualizado. */
    public Integer recalculate(Set<Id> contractIds) {
        if (CollectionUtil.isNullOrEmpty(contractIds)) {
            return 0;
        }
        Map<Id, Contrato_Assinatura__c> contracts = contractSelector.mapByIds(contractIds);
        if (contracts.isEmpty()) {
            return 0;
        }
        Map<Id, Decimal> totals = itemSelector.sumActiveMrrByContractIds(contracts.keySet());
        List<Contrato_Assinatura__c> changes = new List<Contrato_Assinatura__c>();
        for (Contrato_Assinatura__c contract : contracts.values()) {
            Decimal expected = MoneyUtil.round(MoneyUtil.zeroIfNull(totals.get(contract.Id)));
            if (contract.MRR_Atual__c == null || contract.MRR_Atual__c != expected) {
                changes.add(new Contrato_Assinatura__c(Id = contract.Id, MRR_Atual__c = expected));
            }
        }
        CalculatedFieldWriter.updateContractMrr(changes);
        return changes.size();
    }
}
