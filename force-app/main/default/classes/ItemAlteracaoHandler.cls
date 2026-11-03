/**
 * @description Handler da Trigger SubscriptionItemChangeTrigger (Item_Alteracao__c).
 *              Apenas identifica registros afetados, delega ao Service e aplica addError POR REGISTRO
 *              (operacoes parciais allOrNone=false funcionam). Sem DML e sem SOQL proprios.
 *
 *              Pais afetados: insert/delete/undelete = pai do registro; update = pai novo E antigo quando
 *              Solicitacao__c mudou (troca de pai), ou o pai quando Delta_MRR__c mudou. Atualizacoes sem
 *              efeito financeiro nao disparam recalculo.
 */
public with sharing class ItemAlteracaoHandler {
    private final RequestItemService itemService = new RequestItemService();
    private final RequestRecalculationService recalculation = new RequestRecalculationService();

    public void run() {
        switch on Trigger.operationType {
            when BEFORE_INSERT {
                beforeSave((List<Item_Alteracao__c>) Trigger.new, null);
            }
            when BEFORE_UPDATE {
                beforeSave((List<Item_Alteracao__c>) Trigger.new, (Map<Id, Item_Alteracao__c>) Trigger.oldMap);
            }
            when BEFORE_DELETE {
                beforeDelete((List<Item_Alteracao__c>) Trigger.old);
            }
            when AFTER_INSERT {
                afterSave((List<Item_Alteracao__c>) Trigger.new, null);
            }
            when AFTER_UPDATE {
                afterSave((List<Item_Alteracao__c>) Trigger.new, (Map<Id, Item_Alteracao__c>) Trigger.oldMap);
            }
            when AFTER_DELETE {
                afterDelete((List<Item_Alteracao__c>) Trigger.old);
            }
            when AFTER_UNDELETE {
                afterUndelete((List<Item_Alteracao__c>) Trigger.new);
            }
            when else {
                // Demais eventos nao sao tratados.
            }
        }
    }

    public void beforeSave(List<Item_Alteracao__c> items, Map<Id, Item_Alteracao__c> oldById) {
        try {
            applyErrors(items, itemService.prepareForSave(items, oldById));
        } catch (SubscriptionException batchError) {
            failAll(items, batchError.getMessage());
        }
    }

    public void beforeDelete(List<Item_Alteracao__c> oldItems) {
        applyErrors(oldItems, itemService.validateParentEditable(oldItems));
    }

    public void afterSave(List<Item_Alteracao__c> items, Map<Id, Item_Alteracao__c> oldById) {
        Set<Id> parentIds = new Set<Id>();
        for (Item_Alteracao__c item : items) {
            Item_Alteracao__c old = (oldById == null || item.Id == null) ? null : oldById.get(item.Id);
            if (old == null) {
                addIfPresent(parentIds, item.Solicitacao__c);
            } else if (old.Solicitacao__c != item.Solicitacao__c) {
                addIfPresent(parentIds, item.Solicitacao__c);
                addIfPresent(parentIds, old.Solicitacao__c);
            } else if (old.Delta_MRR__c != item.Delta_MRR__c) {
                addIfPresent(parentIds, item.Solicitacao__c);
            }
        }
        recalculation.recalculate(parentIds);
    }

    public void afterDelete(List<Item_Alteracao__c> oldItems) {
        recalculation.recalculate(CollectionUtil.pluckIds(oldItems, Item_Alteracao__c.Solicitacao__c));
    }

    public void afterUndelete(List<Item_Alteracao__c> restored) {
        Map<Integer, String> errors = itemService.validateParentEditable(restored);
        applyErrors(restored, errors);
        if (errors.isEmpty()) {
            recalculation.recalculate(CollectionUtil.pluckIds(restored, Item_Alteracao__c.Solicitacao__c));
        }
    }

    private static void addIfPresent(Set<Id> target, Id value) {
        if (value != null) {
            target.add(value);
        }
    }

    private static void applyErrors(List<Item_Alteracao__c> records, Map<Integer, String> errors) {
        for (Integer index : errors.keySet()) {
            records[index].addError(errors.get(index));
        }
    }

    private static void failAll(List<Item_Alteracao__c> records, String message) {
        for (Item_Alteracao__c record : records) {
            record.addError(message);
        }
    }
}
