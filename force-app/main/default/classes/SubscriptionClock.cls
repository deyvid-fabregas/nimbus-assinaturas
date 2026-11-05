/**
 * @description Relogio injetavel: regras de data (retroatividade, janela, efetivacao) ficam
 *              deterministicas em teste sem depender da data real.
 */
public with sharing class SubscriptionClock {
    @TestVisible private static Date todayOverride;

    public static Date today() {
        return todayOverride != null ? todayOverride : Date.today();
    }

    @TestVisible private static Datetime nowOverride;

    /** Instante corrente (data/hora de decisao e de historico); injetavel em teste. */
    public static Datetime now() {
        return nowOverride != null ? nowOverride : Datetime.now();
    }
}
