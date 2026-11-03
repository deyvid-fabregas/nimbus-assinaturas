/**
 * @description Dominio puro (sem SOQL/DML) para calculo de MRR e variacoes.
 *              MRR do item = Quantidade x Preco Unitario Mensal (arredondado, MoneyUtil).
 *              MRR do contrato = soma dos MRR dos itens ATIVOS.
 *              Variacao absoluta = proposto - base (positivo = aumento).
 *              Variacao percentual = absoluta / base, em pontos percentuais; NULL quando a base e zero
 *              e a variacao nao e zero (percentual indefinido); 0.00 quando ambos sao zero.
 */
public with sharing class MrrCalculator {

    public class Variation {
        public Decimal baseMrr { get; set; }
        public Decimal proposedMrr { get; set; }
        public Decimal absolute { get; set; }
        public Decimal percent { get; set; }
    }

    public static Decimal itemMrr(Decimal quantity, Decimal unitPrice) {
        return MoneyUtil.multiply(quantity, unitPrice);
    }

    /** Delta de uma linha: MRR(quantidade nova) - MRR(quantidade atual), ao mesmo preco unitario. */
    public static Decimal lineDelta(Decimal currentQuantity, Decimal newQuantity, Decimal unitPrice) {
        return MoneyUtil.round(itemMrr(newQuantity, unitPrice) - itemMrr(currentQuantity, unitPrice));
    }

    public static Decimal contractMrr(List<Decimal> activeItemMrrs) {
        return MoneyUtil.sum(activeItemMrrs);
    }

    public static Decimal proposedMrr(Decimal baseMrr, Decimal totalDelta) {
        return MoneyUtil.round(MoneyUtil.zeroIfNull(baseMrr) + MoneyUtil.zeroIfNull(totalDelta));
    }

    public static Variation compute(Decimal baseMrr, Decimal proposedMrr) {
        Variation result = new Variation();
        result.baseMrr = MoneyUtil.round(MoneyUtil.zeroIfNull(baseMrr));
        result.proposedMrr = MoneyUtil.round(MoneyUtil.zeroIfNull(proposedMrr));
        result.absolute = MoneyUtil.round(result.proposedMrr - result.baseMrr);
        if (result.absolute == 0) {
            result.percent = 0.00;
        } else {
            result.percent = MoneyUtil.percentOf(result.absolute, result.baseMrr);
        }
        return result;
    }
}
