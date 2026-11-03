/**
 * @description Regras SERVER-SIDE de Item_Alteracao__c, aplicadas a TODO canal (LWC, API, Data Loader, Apex).
 *              Chamado pela Trigger (via ItemAlteracaoHandler); devolve erros por INDICE do registro para o
 *              Handler aplicar addError (parcial por registro).
 *
 *              prepareForSave (before insert/update):
 *               A) congelamento: so Rascunho aceita inclusao/edicao (troca de pai valida pai antigo e novo);
 *               B) resolucao: Item_Contrato__c, Produto__c, Quantidade_Atual__c, Preco_Unitario_Mensal__c e
 *                  Delta_MRR__c SAO SOBRESCRITOS a partir do banco (valor enviado pelo cliente e descartado);
 *               C) produto duplicado na solicitacao (no lote e contra itens ja persistidos).
 *              Custo para 200 itens/20 solicitacoes: 1 (pais) + ate 5 (ChangeContextLoader) + 1 (irmaos)
 *              = no maximo 7 SOQL e 0 DML.
 */
public with sharing class RequestItemService {
    private final RequestSelector requestSelector = new RequestSelector();
    private final RequestItemSelector itemSelector = new RequestItemSelector();
    private final ChangeContextLoader loader = new ChangeContextLoader();

    public Map<Integer, String> prepareForSave(List<Item_Alteracao__c> items, Map<Id, Item_Alteracao__c> oldById) {
        Map<Integer, String> errors = new Map<Integer, String>();
        if (items == null || items.isEmpty()) {
            return errors;
        }

        Set<Id> parentIds = new Set<Id>();
        for (Item_Alteracao__c item : items) {
            if (item.Solicitacao__c != null) {
                parentIds.add(item.Solicitacao__c);
            }
            Item_Alteracao__c old = oldFor(item, oldById);
            if (old != null && old.Solicitacao__c != null) {
                parentIds.add(old.Solicitacao__c);
            }
        }
        Map<Id, Solicitacao_Alteracao__c> parents = requestSelector.mapByIds(parentIds);

        // A) congelamento por estado do pai
        for (Integer i = 0; i < items.size(); i++) {
            Item_Alteracao__c item = items[i];
            Solicitacao_Alteracao__c parent = parents.get(item.Solicitacao__c);
            if (parent == null) {
                errors.put(i, 'A solicitação do item não foi encontrada ou você não tem acesso a ela.');
                continue;
            }
            String frozen = RequestStateMachine.itemChangeError(parent.Status__c);
            Item_Alteracao__c old = oldFor(item, oldById);
            if (frozen == null && old != null && old.Solicitacao__c != item.Solicitacao__c) {
                Solicitacao_Alteracao__c oldParent = parents.get(old.Solicitacao__c);
                frozen = oldParent == null ? null : RequestStateMachine.itemChangeError(oldParent.Status__c);
            }
            if (frozen != null) {
                errors.put(i, frozen);
            }
        }

        // Contextos (1 por solicitacao) para os itens que passaram do congelamento
        Map<String, ChangeContextLoader.Spec> specs = new Map<String, ChangeContextLoader.Spec>();
        Set<Id> productsToPrice = new Set<Id>();
        Set<Id> batchItemIds = new Set<Id>();
        for (Integer i = 0; i < items.size(); i++) {
            Item_Alteracao__c item = items[i];
            if (item.Id != null) {
                batchItemIds.add(item.Id);
            }
            if (errors.containsKey(i)) {
                continue;
            }
            Solicitacao_Alteracao__c parent = parents.get(item.Solicitacao__c);
            specs.put(String.valueOf(parent.Id), new ChangeContextLoader.Spec(parent.Contrato__c, parent.Plano_Proposto__c));
            if (item.Acao__c == SubscriptionConstants.ACAO_ADICIONAR && item.Produto__c != null) {
                productsToPrice.add(item.Produto__c);
            }
        }
        if (specs.isEmpty()) {
            return errors;
        }
        Map<String, ChangeContext> contexts = loader.load(specs, productsToPrice);

        // Produtos ja existentes nas solicitacoes (exclui os itens do proprio lote: serao reavaliados)
        Set<Id> requestIdsToCheck = new Set<Id>();
        for (String requestKey : specs.keySet()) {
            requestIdsToCheck.add((Id) requestKey);
        }
        Set<String> persistedKeys = new Set<String>();
        for (Item_Alteracao__c sibling : itemSelector.selectByRequestIds(requestIdsToCheck)) {
            if (!batchItemIds.contains(sibling.Id)) {
                persistedKeys.add(productKey(sibling.Solicitacao__c, sibling.Produto__c));
            }
        }

        // B) resolucao no servidor + C) duplicidade
        Set<String> seenInBatch = new Set<String>();
        for (Integer i = 0; i < items.size(); i++) {
            if (errors.containsKey(i)) {
                continue;
            }
            Item_Alteracao__c item = items[i];
            Solicitacao_Alteracao__c parent = parents.get(item.Solicitacao__c);
            try {
                ChangeContext ctx = contexts.get(String.valueOf(parent.Id));
                if (ctx == null) {
                    throw new SubscriptionException(
                        SubscriptionConstants.ERR_NAO_ENCONTRADO,
                        'O contrato da solicitação não foi encontrado ou você não tem acesso a ele.'
                    );
                }
                ctx.requireResolvedPlans();
                ItemResolutionPolicy.Line line = ItemResolutionPolicy.resolve(
                    item.Acao__c, item.Item_Contrato__c, item.Produto__c, item.Quantidade_Nova__c, ctx
                );
                String key = productKey(parent.Id, line.productId);
                if (persistedKeys.contains(key) || !seenInBatch.add(key)) {
                    throw new SubscriptionException(
                        SubscriptionConstants.ERR_PRODUTO_DUPLICADO,
                        'O mesmo produto não pode aparecer mais de uma vez na solicitação.'
                    );
                }
                item.Item_Contrato__c = line.contractItemId;
                item.Produto__c = line.productId;
                item.Quantidade_Atual__c = line.currentQuantity;
                item.Quantidade_Nova__c = line.newQuantity;
                item.Preco_Unitario_Mensal__c = line.unitPrice;
                item.Delta_MRR__c = line.delta;
            } catch (SubscriptionException businessError) {
                errors.put(i, businessError.getMessage());
            }
        }
        return errors;
    }

    /**
     * before delete / after undelete: itens so podem ser removidos/restaurados em Rascunho.
     * Pai ausente (exclusao em cascata do proprio pai) NAO e erro: a regra do pai ja foi aplicada pela
     * mesma checagem nos itens enquanto ele existia.
     */
    public Map<Integer, String> validateParentEditable(List<Item_Alteracao__c> items) {
        Map<Integer, String> errors = new Map<Integer, String>();
        if (items == null || items.isEmpty()) {
            return errors;
        }
        Map<Id, Solicitacao_Alteracao__c> parents = requestSelector.mapByIds(
            CollectionUtil.pluckIds(items, Item_Alteracao__c.Solicitacao__c)
        );
        for (Integer i = 0; i < items.size(); i++) {
            Solicitacao_Alteracao__c parent = parents.get(items[i].Solicitacao__c);
            if (parent == null) {
                continue;
            }
            String frozen = RequestStateMachine.itemChangeError(parent.Status__c);
            if (frozen != null) {
                errors.put(i, frozen);
            }
        }
        return errors;
    }

    private static Item_Alteracao__c oldFor(Item_Alteracao__c item, Map<Id, Item_Alteracao__c> oldById) {
        return (oldById == null || item.Id == null) ? null : oldById.get(item.Id);
    }

    private static String productKey(Id requestId, Id productId) {
        return String.valueOf(requestId) + '|' + String.valueOf(productId);
    }
}
