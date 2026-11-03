/**
 * @description Handler da Trigger SubscriptionContractItemTrigger (Item_Contrato__c).
 *              1) BLOQUEIA qualquer insert/update/delete/undelete fora do ControlledWriteContext (aberto so pelo
 *                 SubscriptionApplyService e por classes de teste): regra "itens de contrato so mudam pelo fluxo
 *                 de aplicacao", valida inclusive para API/Data Loader.
 *              2) before: MRR_Item__c = Quantidade x Preco (escritor unico, nunca informado externamente).
 *              3) after: recalcula MRR_Atual__c dos contratos afetados (ContractMrrService).
 *
 *              Carga inicial: itens de contratos novos tambem exigem o escopo aberto (ver DECISOES_E_LIMITACOES.md).
 */
public with sharing class ItemContratoHandler {
    @TestVisible
    private static final String BLOCKED_MESSAGE =
        'Os itens do contrato só podem ser alterados pela aplicação de uma solicitação de alteração aprovada. Edição direta não é permitida.';

    private final ContractMrrService mrrService = new ContractMrrService();

    public void run() {
        switch on Trigger.operationType {
            when BEFORE_INSERT {
                beforeSave((List<Item_Contrato__c>) Trigger.new, null);
            }
            when BEFORE_UPDATE {
                beforeSave((List<Item_Contrato__c>) Trigger.new, (Map<Id, Item_Contrato__c>) Trigger.oldMap);
            }
            when BEFORE_DELETE {
                beforeDelete((List<Item_Contrato__c>) Trigger.old);
            }
            when AFTER_INSERT {
                afterSave((List<Item_Contrato__c>) Trigger.new, null);
            }
            when AFTER_UPDATE {
                afterSave((List<Item_Contrato__c>) Trigger.new, (Map<Id, Item_Contrato__c>) Trigger.oldMap);
            }
            when AFTER_DELETE {
                afterDelete((List<Item_Contrato__c>) Trigger.old);
            }
            when AFTER_UNDELETE {
                afterUndelete((List<Item_Contrato__c>) Trigger.new);
            }
            when else {
                // Demais eventos nao sao tratados.
            }
        }
    }

    public void beforeSave(List<Item_Contrato__c> items, Map<Id, Item_Contrato__c> oldById) {
        for (Item_Contrato__c item : items) {
            if (item.Contrato__c == null) {
                continue; // a obrigatoriedade do master-detail e validada pela plataforma
            }
            Item_Contrato__c old = (oldById == null || item.Id == null) ? null : oldById.get(item.Id);
            Boolean allowed = ControlledWriteContext.isOpenFor(item.Contrato__c)
                && (old == null || ControlledWriteContext.isOpenFor(old.Contrato__c));
            if (!allowed) {
                item.addError(BLOCKED_MESSAGE);
                continue;
            }
            item.MRR_Item__c = MrrCalculator.itemMrr(item.Quantidade__c, item.Preco_Unitario_Mensal__c);
        }
    }

    public void beforeDelete(List<Item_Contrato__c> oldItems) {
        for (Item_Contrato__c item : oldItems) {
            if (!ControlledWriteContext.isOpenFor(item.Contrato__c)) {
                item.addError(BLOCKED_MESSAGE);
            }
        }
    }

    public void afterSave(List<Item_Contrato__c> items, Map<Id, Item_Contrato__c> oldById) {
        Set<Id> contractIds = new Set<Id>();
        for (Item_Contrato__c item : items) {
            contractIds.add(item.Contrato__c);
            Item_Contrato__c old = (oldById == null || item.Id == null) ? null : oldById.get(item.Id);
            if (old != null) {
                contractIds.add(old.Contrato__c);
            }
        }
        recalculateOpen(contractIds);
    }

    public void afterDelete(List<Item_Contrato__c> oldItems) {
        recalculateOpen(CollectionUtil.pluckIds(oldItems, Item_Contrato__c.Contrato__c));
    }

    public void afterUndelete(List<Item_Contrato__c> restored) {
        for (Item_Contrato__c item : restored) {
            if (!ControlledWriteContext.isOpenFor(item.Contrato__c)) {
                item.addError(BLOCKED_MESSAGE);
            }
        }
        recalculateOpen(CollectionUtil.pluckIds(restored, Item_Contrato__c.Contrato__c));
    }

    /** So recalcula contratos cuja escrita foi autorizada (as demais foram barradas no before). */
    private void recalculateOpen(Set<Id> contractIds) {
        Set<Id> open = new Set<Id>();
        for (Id contractId : contractIds) {
            if (ControlledWriteContext.isOpenFor(contractId)) {
                open.add(contractId);
            }
        }
        mrrService.recalculate(open);
    }
}
