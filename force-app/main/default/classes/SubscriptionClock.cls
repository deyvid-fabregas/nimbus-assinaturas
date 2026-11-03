/**
 * @description Relogio injetavel: regras de data (retroatividade, janela, efetivacao) ficam
 *              deterministicas em teste sem depender da data real.
 */
public with sharing class SubscriptionClock {
    @TestVisible private static Date todayOverride;

    public static Date today() {
        return todayOverride != null ? todayOverride : Date.today();
    }
}
