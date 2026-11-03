/**
 * @description UNICO ponto de arredondamento monetario do modulo.
 *              Regra: Decimal, 2 casas, HALF_UP. Proibido Double para dinheiro.
 *              Percentuais seguem a mesma regra e sao expressos em pontos percentuais
 *              (18.00 significa 18%), formato esperado por campos Percent do Salesforce.
 */
public with sharing class MoneyUtil {
    public static final Integer SCALE = 2;

    public static Decimal round(Decimal value) {
        return value == null ? null : value.setScale(SCALE, System.RoundingMode.HALF_UP);
    }

    public static Decimal zeroIfNull(Decimal value) {
        return value == null ? 0 : value;
    }

    /** Quantidade x preco, arredondado. Nulos contam como zero. */
    public static Decimal multiply(Decimal quantity, Decimal unitPrice) {
        return round(zeroIfNull(quantity) * zeroIfNull(unitPrice));
    }

    public static Decimal sum(List<Decimal> values) {
        Decimal total = 0;
        if (values != null) {
            for (Decimal value : values) {
                total += zeroIfNull(value);
            }
        }
        return round(total);
    }

    /**
     * Parte sobre base, em pontos percentuais, com UM unico arredondamento (HALF_UP, 2 casas).
     * Retorna NULL quando a base e zero: percentual indefinido (ver ARQUITETURA.md).
     */
    public static Decimal percentOf(Decimal part, Decimal base) {
        Decimal safeBase = zeroIfNull(base);
        if (safeBase == 0) {
            return null;
        }
        return (zeroIfNull(part) * 100).divide(safeBase.abs(), SCALE, System.RoundingMode.HALF_UP);
    }
}
