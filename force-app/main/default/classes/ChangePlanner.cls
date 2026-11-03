/**
 * @description Dominio PURO (sem SOQL/DML): transforma a INTENCAO do usuario em linhas resolvidas pelo
 *              servidor e valida as regras de CONJUNTO (duplicidade, troca de plano, limites de licencas).
 *
 *              TROCA DE PLANO (premissa 1 de ARQUITETURA.md): como MRR = soma dos itens ativos, upgrade/
 *              downgrade vira linhas: Remover a licenca do plano atual + Adicionar a licenca do plano novo
 *              (produto do plano, Preco_Base_Mensal__c, mesma quantidade ou a pedida via "Alterar Quantidade"
 *              na licenca atual). A linha de licenca do plano novo e gerada aqui; o cliente nao a envia.
 *
 *              Reaproveitado pela Trigger de envio (validatePlanSwapConsistency / validateLicenseLimits)
 *              para garantir as mesmas regras quando o rascunho nasce por API/Data Loader.
 */
public with sharing class ChangePlanner {

    public class Plan {
        public List<ItemResolutionPolicy.Line> lines = new List<ItemResolutionPolicy.Line>();
        public String requestType;
        public Boolean planChanged = false;
        public Decimal baseMrr;
        public Decimal totalDelta;
        public Decimal proposedMrr;
    }

    public static Plan plan(List<SubscriptionChangeRequestDTO.ItemDTO> intents, ChangeContext ctx) {
        ctx.requireResolvedPlans();
        List<SubscriptionChangeRequestDTO.ItemDTO> safeIntents = intents == null
            ? new List<SubscriptionChangeRequestDTO.ItemDTO>()
            : intents;
        validateShape(safeIntents);

        Plan result = new Plan();
        Set<String> categories = new Set<String>();
        result.planChanged = ctx.isPlanChange();
        if (result.planChanged) {
            planWithPlanChange(safeIntents, ctx, result, categories);
        } else {
            planWithoutPlanChange(safeIntents, ctx, result, categories);
        }
        if (result.lines.isEmpty()) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_SEM_ALTERACAO,
                'Informe ao menos uma alteração (troca de plano, licenças ou recursos adicionais).'
            );
        }
        validateLicenseLimits(ctx, result.lines);

        List<Decimal> deltas = new List<Decimal>();
        for (ItemResolutionPolicy.Line line : result.lines) {
            deltas.add(line.delta);
        }
        result.baseMrr = ctx.baseMrr();
        result.totalDelta = MoneyUtil.sum(deltas);
        result.proposedMrr = MrrCalculator.proposedMrr(result.baseMrr, result.totalDelta);
        result.requestType = categories.size() == 1
            ? new List<String>(categories)[0]
            : SubscriptionConstants.TIPO_MISTO;
        return result;
    }

    /**
     * Quantidade de licencas resultante (produto do plano efetivo) dentro dos limites do plano efetivo.
     * So avalia quando alguma linha toca a licenca (ou ha troca de plano, que sempre a toca).
     */
    public static void validateLicenseLimits(ChangeContext ctx, List<ItemResolutionPolicy.Line> lines) {
        Plano_Assinatura__c plan = ctx.effectivePlan();
        if (plan == null || plan.Produto__c == null || lines == null) {
            return;
        }
        Item_Contrato__c existing = ctx.activeItemsByProduct.get(plan.Produto__c);
        Decimal quantity = existing == null ? 0 : MoneyUtil.zeroIfNull(existing.Quantidade__c);
        Boolean touched = false;
        for (ItemResolutionPolicy.Line line : lines) {
            if (line.productId == plan.Produto__c) {
                touched = true;
                quantity = line.action == SubscriptionConstants.ACAO_REMOVER
                    ? 0
                    : MoneyUtil.zeroIfNull(line.newQuantity);
            }
        }
        if (touched) {
            ChangeRequestPolicy.requireWithinLicenseLimits(quantity, plan.Licencas_Minimas__c, plan.Licencas_Maximas__c);
        }
    }

    /** Com troca de plano, as linhas precisam conter a saida da licenca atual e a entrada da licenca nova. */
    public static void validatePlanSwapConsistency(ChangeContext ctx, List<ItemResolutionPolicy.Line> lines) {
        if (!ctx.isPlanChange()) {
            return;
        }
        Boolean hasAddition = false;
        Boolean hasRemoval = false;
        if (lines != null) {
            for (ItemResolutionPolicy.Line line : lines) {
                if (line.action == SubscriptionConstants.ACAO_ADICIONAR && line.productId == ctx.proposedPlan.Produto__c) {
                    hasAddition = true;
                }
                if (line.action == SubscriptionConstants.ACAO_REMOVER && line.productId == ctx.currentPlan.Produto__c) {
                    hasRemoval = true;
                }
            }
        }
        if (!hasAddition || !hasRemoval) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_PLANO_INVALIDO,
                'A troca de plano exige remover a licença do plano atual e adicionar a do plano proposto. Refaça a simulação.'
            );
        }
    }

    // ------------------------------------------------------------------ privados

    private static void validateShape(List<SubscriptionChangeRequestDTO.ItemDTO> intents) {
        List<Id> productIds = new List<Id>();
        for (SubscriptionChangeRequestDTO.ItemDTO intent : intents) {
            if (intent == null || intent.productId == null) {
                throw new SubscriptionException(
                    SubscriptionConstants.ERR_ENTRADA_INVALIDA,
                    'Informe o produto de cada item da solicitação.'
                );
            }
            productIds.add(intent.productId);
        }
        ChangeRequestPolicy.requireNoDuplicateProducts(productIds);
    }

    private static void planWithoutPlanChange(
        List<SubscriptionChangeRequestDTO.ItemDTO> intents,
        ChangeContext ctx,
        Plan result,
        Set<String> categories
    ) {
        Id licenseProductId = ctx.currentPlan.Produto__c;
        for (SubscriptionChangeRequestDTO.ItemDTO intent : intents) {
            ItemResolutionPolicy.Line line = ItemResolutionPolicy.resolve(
                intent.action, null, intent.productId, intent.newQuantity, ctx
            );
            result.lines.add(line);
            if (licenseProductId != null && line.productId == licenseProductId) {
                categories.add(
                    line.newQuantity > line.currentQuantity
                        ? SubscriptionConstants.TIPO_ADICAO_LICENCAS
                        : SubscriptionConstants.TIPO_REDUCAO_LICENCAS
                );
            } else {
                categories.add(SubscriptionConstants.TIPO_RECURSO_ADICIONAL);
            }
        }
    }

    private static void planWithPlanChange(
        List<SubscriptionChangeRequestDTO.ItemDTO> intents,
        ChangeContext ctx,
        Plan result,
        Set<String> categories
    ) {
        Plano_Assinatura__c current = ctx.currentPlan;
        Plano_Assinatura__c proposed = ctx.proposedPlan;
        if (current.Produto__c == null || proposed.Produto__c == null || current.Produto__c == proposed.Produto__c) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_PLANO_INVALIDO,
                'Para trocar de plano, o plano atual e o proposto precisam ter produtos distintos cadastrados.'
            );
        }
        if (current.Nivel__c == proposed.Nivel__c) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_PLANO_INVALIDO,
                'O plano proposto tem o mesmo nível do plano atual. Escolha um plano de nível diferente (upgrade ou downgrade).'
            );
        }
        Item_Contrato__c currentLicense = ctx.activeItemsByProduct.get(current.Produto__c);
        if (currentLicense == null) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_PLANO_INVALIDO,
                'O contrato não possui item de licença do plano atual; não é possível trocar de plano.'
            );
        }

        Decimal desiredLicenses = currentLicense.Quantidade__c;
        for (SubscriptionChangeRequestDTO.ItemDTO intent : intents) {
            if (intent.productId == proposed.Produto__c) {
                throw new SubscriptionException(
                    SubscriptionConstants.ERR_PRODUTO_DUPLICADO,
                    'A licença do novo plano é gerada automaticamente; não a informe como item.'
                );
            }
            if (intent.productId == current.Produto__c) {
                if (intent.action != SubscriptionConstants.ACAO_ALTERAR_QTD) {
                    throw new SubscriptionException(
                        SubscriptionConstants.ERR_ACAO_INVALIDA,
                        'Ao trocar de plano, a licença só pode ter a quantidade ajustada (Alterar Quantidade).'
                    );
                }
                desiredLicenses = intent.newQuantity;
                continue;
            }
            result.lines.add(
                ItemResolutionPolicy.resolve(intent.action, null, intent.productId, intent.newQuantity, ctx)
            );
            categories.add(SubscriptionConstants.TIPO_RECURSO_ADICIONAL);
        }

        result.lines.add(
            ItemResolutionPolicy.resolve(
                SubscriptionConstants.ACAO_REMOVER, currentLicense.Id, current.Produto__c, 0, ctx
            )
        );
        result.lines.add(
            ItemResolutionPolicy.resolve(
                SubscriptionConstants.ACAO_ADICIONAR, null, proposed.Produto__c, desiredLicenses, ctx
            )
        );
        categories.add(
            proposed.Nivel__c > current.Nivel__c
                ? SubscriptionConstants.TIPO_UPGRADE
                : SubscriptionConstants.TIPO_DOWNGRADE
        );
    }
}
