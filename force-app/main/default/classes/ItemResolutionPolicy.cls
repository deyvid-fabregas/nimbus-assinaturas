/**
 * @description Dominio PURO (sem SOQL/DML): resolve UMA linha de alteracao no servidor.
 *              Dado (acao, item/produto, quantidade nova) e o ChangeContext, devolve quantidade atual,
 *              preco unitario e delta. NUNCA confia em preco/delta/quantidade atual vindos do cliente.
 *
 *              Origem do preco:
 *              - Alterar Quantidade / Remover: preco do proprio Item_Contrato__c ativo (preco contratado).
 *              - Adicionar de produto do PLANO efetivo: Preco_Base_Mensal__c do plano (preco por licenca).
 *              - Adicionar de outro produto (recurso adicional): PricebookEntry do Pricebook do contrato.
 */
public with sharing class ItemResolutionPolicy {

    public class Line {
        public Id contractItemId;
        public Id productId;
        public String action;
        public Decimal currentQuantity;
        public Decimal newQuantity;
        public Decimal unitPrice;
        public Decimal delta;
    }

    public static Line resolve(
        String action,
        Id contractItemId,
        Id productId,
        Decimal newQuantity,
        ChangeContext ctx
    ) {
        if (action != SubscriptionConstants.ACAO_ADICIONAR
            && action != SubscriptionConstants.ACAO_ALTERAR_QTD
            && action != SubscriptionConstants.ACAO_REMOVER) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_ACAO_INVALIDA,
                'Ação inválida para o item da solicitação.'
            );
        }
        // Remover sem quantidade informada equivale a zero.
        Decimal targetQuantity = (action == SubscriptionConstants.ACAO_REMOVER && newQuantity == null) ? 0 : newQuantity;

        Line line = action == SubscriptionConstants.ACAO_ADICIONAR
            ? resolveAddition(productId, targetQuantity, ctx)
            : resolveExisting(action, contractItemId, productId, targetQuantity, ctx);
        line.action = action;
        line.newQuantity = targetQuantity;
        line.delta = MrrCalculator.lineDelta(line.currentQuantity, targetQuantity, line.unitPrice);
        return line;
    }

    /** Converte um Item_Alteracao__c ja persistido em Line (usado na validacao de envio). */
    public static Line fromItem(Item_Alteracao__c item) {
        Line line = new Line();
        line.contractItemId = item.Item_Contrato__c;
        line.productId = item.Produto__c;
        line.action = item.Acao__c;
        line.currentQuantity = item.Quantidade_Atual__c;
        line.newQuantity = item.Quantidade_Nova__c;
        line.unitPrice = item.Preco_Unitario_Mensal__c;
        line.delta = item.Delta_MRR__c;
        return line;
    }

    private static Line resolveExisting(
        String action,
        Id contractItemId,
        Id productId,
        Decimal targetQuantity,
        ChangeContext ctx
    ) {
        Item_Contrato__c item = null;
        if (contractItemId != null) {
            item = ctx.activeItemsById.get(contractItemId);
        } else if (productId != null) {
            item = ctx.activeItemsByProduct.get(productId);
        }
        if (item == null || (productId != null && productId != item.Produto__c)) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_ITEM_NAO_ENCONTRADO,
                'O item informado não existe ou não está ativo neste contrato.'
            );
        }
        ChangeRequestPolicy.requireValidQuantity(action, item.Quantidade__c, targetQuantity);

        Line line = new Line();
        line.contractItemId = item.Id;
        line.productId = item.Produto__c;
        line.currentQuantity = item.Quantidade__c;
        line.unitPrice = item.Preco_Unitario_Mensal__c;
        return line;
    }

    private static Line resolveAddition(Id productId, Decimal targetQuantity, ChangeContext ctx) {
        if (productId == null) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_ENTRADA_INVALIDA,
                'Informe o produto do item a adicionar.'
            );
        }
        if (ctx.activeItemsByProduct.containsKey(productId)) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_PRODUTO_DUPLICADO,
                'Este produto já faz parte do contrato. Use "Alterar Quantidade" para ajustá-lo.'
            );
        }
        ChangeRequestPolicy.requireValidQuantity(SubscriptionConstants.ACAO_ADICIONAR, 0, targetQuantity);

        Line line = new Line();
        line.contractItemId = null;
        line.productId = productId;
        line.currentQuantity = 0;
        line.unitPrice = priceFor(productId, ctx);
        return line;
    }

    private static Decimal priceFor(Id productId, ChangeContext ctx) {
        Plano_Assinatura__c plan = ctx.effectivePlan();
        Decimal price = (plan != null && plan.Produto__c == productId)
            ? plan.Preco_Base_Mensal__c
            : ctx.catalogPriceByProduct.get(productId);
        if (price == null || price <= 0) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_PRECO_AUSENTE,
                'Não há preço mensal válido cadastrado para este produto no Pricebook do contrato. Solicite o cadastro da entrada de preço.'
            );
        }
        return MoneyUtil.round(price);
    }
}
