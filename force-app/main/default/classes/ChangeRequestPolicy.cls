/**
 * @description Regras puras de validacao de uma solicitacao de alteracao (sem DML/SOQL).
 *              Cada metodo lanca SubscriptionException com codigo estavel e mensagem amigavel.
 *              Chamadas pelo Service (US-01) e reaproveitaveis pelo Handler (US-02), garantindo
 *              as MESMAS regras para LWC, API, Data Loader e Execute Anonymous.
 */
public with sharing class ChangeRequestPolicy {

    public static void requireActiveContract(String contractStatus) {
        if (contractStatus != SubscriptionConstants.CTR_ATIVO) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_CONTRATO_NAO_ATIVO,
                'Somente contratos com status Ativo podem ser alterados (status atual: '
                    + (String.isBlank(contractStatus) ? 'não informado' : contractStatus) + ').'
            );
        }
    }

    public static void requireActivePlan(Boolean planIsActive) {
        if (planIsActive != true) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_PLANO_INATIVO,
                'O plano proposto está inativo. Escolha um plano ativo do catálogo.'
            );
        }
    }

    /** Data obrigatoria, nao retroativa e dentro da janela (dias) configurada em metadado. */
    public static void requireEffectiveDate(Date effectiveDate, Date today, Integer windowDays) {
        if (effectiveDate == null) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_DATA_OBRIGATORIA,
                'Informe a data de efetivação da alteração.'
            );
        }
        if (effectiveDate < today) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_DATA_RETROATIVA,
                'A data de efetivação não pode ser anterior a hoje.'
            );
        }
        if (windowDays != null && effectiveDate > today.addDays(windowDays)) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_DATA_FORA_JANELA,
                'A data de efetivação não pode ultrapassar ' + windowDays + ' dias a partir de hoje.'
            );
        }
    }

    public static void requireNoDuplicateProducts(List<Id> productIds) {
        Set<Id> seen = new Set<Id>();
        if (productIds == null) {
            return;
        }
        for (Id productId : productIds) {
            if (productId != null && !seen.add(productId)) {
                throw new SubscriptionException(
                    SubscriptionConstants.ERR_PRODUTO_DUPLICADO,
                    'O mesmo produto não pode aparecer mais de uma vez na solicitação.'
                );
            }
        }
    }

    /**
     * Quantidade inteira. Adicionar/Alterar: >= 1 (Alterar tambem precisa mudar o valor).
     * Remover: quantidade nova obrigatoriamente zero.
     */
    public static void requireValidQuantity(String action, Decimal currentQuantity, Decimal newQuantity) {
        if (action != SubscriptionConstants.ACAO_ADICIONAR
            && action != SubscriptionConstants.ACAO_ALTERAR_QTD
            && action != SubscriptionConstants.ACAO_REMOVER) {
            throw new SubscriptionException(SubscriptionConstants.ERR_ACAO_INVALIDA, 'Ação inválida para o item da solicitação.');
        }
        if (newQuantity == null || newQuantity < 0 || (newQuantity - newQuantity.setScale(0, System.RoundingMode.DOWN)) > 0) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_QUANTIDADE_INVALIDA,
                'A quantidade deve ser um número inteiro positivo.'
            );
        }
        if (action == SubscriptionConstants.ACAO_REMOVER) {
            if (newQuantity != 0) {
                throw new SubscriptionException(
                    SubscriptionConstants.ERR_QUANTIDADE_INVALIDA,
                    'Para remover um item, a quantidade nova deve ser zero.'
                );
            }
            return;
        }
        if (newQuantity < 1) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_QUANTIDADE_INVALIDA,
                'A quantidade deve ser de pelo menos 1. Para retirar o item, use a ação Remover.'
            );
        }
        if (action == SubscriptionConstants.ACAO_ALTERAR_QTD && currentQuantity != null && newQuantity == currentQuantity) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_QUANTIDADE_INVALIDA,
                'A nova quantidade é igual à atual; não há alteração a registrar.'
            );
        }
    }

    /** Total de licencas resultante dentro dos limites do plano (min/max nulos = sem limite). */
    public static void requireWithinLicenseLimits(Decimal totalLicenses, Decimal minLicenses, Decimal maxLicenses) {
        Decimal total = MoneyUtil.zeroIfNull(totalLicenses);
        if (minLicenses != null && total < minLicenses) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_LIMITE_LICENCAS,
                'O plano exige no mínimo ' + minLicenses + ' licença(s); a solicitação resulta em ' + total + '.'
            );
        }
        if (maxLicenses != null && total > maxLicenses) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_LIMITE_LICENCAS,
                'O plano permite no máximo ' + maxLicenses + ' licença(s); a solicitação resulta em ' + total + '.'
            );
        }
    }

    public static void requireJustification(String justification, Integer minLength) {
        if (TextUtil.meaningfulLength(justification) < MoneyUtil.zeroIfNull(minLength)) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_JUSTIFICATIVA_CURTA,
                'Informe uma justificativa com pelo menos ' + minLength + ' caracteres.'
            );
        }
    }

    public static void requireRejectionReason(String reason, Integer minLength) {
        Integer required = minLength == null || minLength < 1 ? 1 : minLength;
        if (TextUtil.meaningfulLength(reason) < required) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_MOTIVO_CURTO,
                'Informe o motivo da rejeição com pelo menos ' + required + ' caracteres (apenas espaços não é válido).'
            );
        }
    }

    public static void requireNotBlocked(ApprovalMatrixPolicy.Result classification) {
        if (classification != null && classification.blocked) {
            throw new SubscriptionException(classification.blockCode, classification.blockMessage);
        }
    }

    /** Controle otimista: versao do contrato mudou desde a simulacao? (nulo conta como zero) */
    public static Boolean isVersionStale(Decimal contractVersion, Decimal baseVersion) {
        return MoneyUtil.zeroIfNull(contractVersion) != MoneyUtil.zeroIfNull(baseVersion);
    }
}
