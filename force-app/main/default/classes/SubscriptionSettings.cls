/**
 * @description Value object imutavel com os parametros de negocio (Parametro_Assinatura__mdt).
 *              Permite que Policies e Services sejam testados sem Custom Metadata real.
 */
public with sharing class SubscriptionSettings {
    /** Teto de variacao percentual (modulo), em pontos percentuais. Acima disso a submissao e bloqueada. */
    public final Decimal maxVariationPercent;
    /** Janela maxima, em dias a partir de hoje, para a data de efetivacao. */
    public final Integer effectiveWindowDays;
    public final Integer minJustificationLength;
    public final Integer minRejectionReasonLength;
    /** Nome do Pricebook2 padrao usado quando o contrato nao define Pricebook__c. */
    public final String defaultPricebookName;

    public SubscriptionSettings(
        Decimal maxVariationPercent,
        Integer effectiveWindowDays,
        Integer minJustificationLength,
        Integer minRejectionReasonLength,
        String defaultPricebookName
    ) {
        this.maxVariationPercent = maxVariationPercent;
        this.effectiveWindowDays = effectiveWindowDays;
        this.minJustificationLength = minJustificationLength;
        this.minRejectionReasonLength = minRejectionReasonLength;
        this.defaultPricebookName = defaultPricebookName;
    }
}
