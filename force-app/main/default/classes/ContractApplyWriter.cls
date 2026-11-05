/**
 * @description ESCRITA ISOLADA (without sharing) das operacoes da APLICACAO de uma alteracao aprovada.
 *              Terceira excecao de modo sistema (junto com CalculatedFieldWriter e AuthorizedSystemWriter).
 *
 *              DECISAO CASO A CASO (por que NAO roda em USER_MODE):
 *               - Item_Contrato__c: so muda pelo fluxo de aplicacao; dar create/edit ao Permission Set abriria a tela
 *                 e a API; a Trigger ja exige ControlledWriteContext aberto (defesa em profundidade, mantida).
 *               - Contrato_Assinatura__c.Versao__c/Plano_Atual__c: Versao__c e protegido (ninguem tem FLS de edicao).
 *               - Aditivo_Contrato__c: so a aplicacao o cria; dar create ao vendedor permitiria forjar aditivos.
 *               - Order/OrderItem: objetos padrao sem permissao de criacao para o vendedor; o pedido e subproduto do aditivo.
 *              O que continua em USER_MODE (no SubscriptionApplyService): Solicitacao_Alteracao__c.Status__c -> Aplicada/Expirada
 *              (sob StatusTransitionContext).
 *
 *              GARANTIAS: sem regra de negocio e sem consulta; copia so campos da lista branca; so e chamada pelo
 *              SubscriptionApplyService DEPOIS de autorizar (Aplicar_Alteracao), travar (FOR UPDATE), revalidar estado e
 *              versao. Itens exigem ControlledWriteContext aberto pelo chamador.
 *
 *              PONTO DE INJECAO DE FALHA: failAtOrderItem so existe para teste (@TestVisible, ignorado fora de Test.isRunningTest()).
 */
public without sharing class ContractApplyWriter {
    @TestVisible private static Integer failAtOrderItem;

    private static final List<String> ITEM_UPDATE_FIELDS = new List<String>{ 'Quantidade__c', 'Status__c' };

    /** Insere itens novos e atualiza (quantidade / status Removido) os existentes. */
    public static void writeItems(List<Item_Contrato__c> toInsert, List<Item_Contrato__c> toUpdate) {
        if (toInsert != null && !toInsert.isEmpty()) {
            List<Item_Contrato__c> safeInserts = new List<Item_Contrato__c>();
            for (Item_Contrato__c item : toInsert) {
                safeInserts.add(
                    new Item_Contrato__c(
                        Contrato__c = item.Contrato__c,
                        Produto__c = item.Produto__c,
                        Tipo__c = item.Tipo__c,
                        Quantidade__c = item.Quantidade__c,
                        Preco_Unitario_Mensal__c = item.Preco_Unitario_Mensal__c,
                        Status__c = item.Status__c
                    )
                );
            }
            insert safeInserts; // NOPMD - modo sistema intencional (ver cabecalho)
        }
        if (toUpdate != null && !toUpdate.isEmpty()) {
            List<Item_Contrato__c> safeUpdates = new List<Item_Contrato__c>();
            for (Item_Contrato__c item : toUpdate) {
                Item_Contrato__c copy = new Item_Contrato__c(Id = item.Id);
                Map<String, Object> populated = item.getPopulatedFieldsAsMap();
                for (String field : ITEM_UPDATE_FIELDS) {
                    if (populated.containsKey(field)) {
                        copy.put(field, populated.get(field));
                    }
                }
                safeUpdates.add(copy);
            }
            update safeUpdates; // NOPMD - modo sistema intencional (ver cabecalho)
        }
    }

    /** Troca de plano (quando houver) e incremento de versao: unicos campos do contrato escritos aqui. */
    public static void updateContract(Id contractId, Id newPlanId, Decimal newVersion) {
        Contrato_Assinatura__c contract = new Contrato_Assinatura__c(Id = contractId, Versao__c = newVersion);
        if (newPlanId != null) {
            contract.Plano_Atual__c = newPlanId;
        }
        update contract; // NOPMD - modo sistema intencional (ver cabecalho)
    }

    /** Cria o pedido e seus itens (um por linha alterada). Devolve o Id do pedido. */
    public static Id insertOrder(Order order, List<OrderItem> items) {
        Order safeOrder = new Order(
            AccountId = order.AccountId,
            EffectiveDate = order.EffectiveDate,
            Status = order.Status,
            Pricebook2Id = order.Pricebook2Id,
            Name = order.Name,
            Description = order.Description
        );
        insert safeOrder; // NOPMD - modo sistema intencional (ver cabecalho)

        List<OrderItem> safeItems = new List<OrderItem>();
        for (OrderItem item : items) {
            safeItems.add(
                new OrderItem(
                    OrderId = safeOrder.Id,
                    PricebookEntryId = item.PricebookEntryId,
                    Quantity = item.Quantity,
                    UnitPrice = item.UnitPrice,
                    Description = item.Description
                )
            );
        }
        if (Test.isRunningTest() && failAtOrderItem != null && safeItems.size() >= failAtOrderItem && failAtOrderItem > 0) {
            List<OrderItem> beforeFailure = new List<OrderItem>();
            for (Integer i = 0; i < failAtOrderItem - 1; i++) {
                beforeFailure.add(safeItems[i]);
            }
            insert beforeFailure; // NOPMD
            throw new DmlException('Falha simulada na criação do OrderItem ' + failAtOrderItem + ' (somente teste).');
        }
        insert safeItems; // NOPMD - modo sistema intencional (ver cabecalho)
        return safeOrder.Id;
    }

    public static Id insertAdditive(Aditivo_Contrato__c additive) {
        Aditivo_Contrato__c safe = new Aditivo_Contrato__c(
            Contrato__c = additive.Contrato__c,
            Solicitacao__c = additive.Solicitacao__c,
            Chave_Unica__c = additive.Chave_Unica__c,
            Versao_Resultante__c = additive.Versao_Resultante__c,
            MRR_Anterior__c = additive.MRR_Anterior__c,
            MRR_Novo__c = additive.MRR_Novo__c,
            Data_Efetivacao__c = additive.Data_Efetivacao__c,
            Order__c = additive.Order__c
        );
        insert safe; // NOPMD - modo sistema intencional (ver cabecalho)
        return safe.Id;
    }
}
