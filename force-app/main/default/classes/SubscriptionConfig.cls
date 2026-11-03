/**
 * @description Ponto unico de leitura de configuracao (Custom Metadata). Usa getAll(), que NAO
 *              consome SOQL, e guarda o resultado em cache estatico (1 leitura por transacao).
 *              Nenhum limite, alcada, responsavel ou Pricebook e codificado em Apex.
 *              Em testes, os overrides permitem injetar configuracao sem depender dos registros do org.
 */
public with sharing class SubscriptionConfig {
    @TestVisible private static SubscriptionSettings settingsOverride;
    @TestVisible private static List<ApprovalMatrixPolicy.Rule> rulesOverride;

    private static SubscriptionSettings cachedSettings;
    private static List<ApprovalMatrixPolicy.Rule> cachedRules;

    public static SubscriptionSettings settings() {
        if (settingsOverride != null) {
            return settingsOverride;
        }
        if (cachedSettings == null) {
            cachedSettings = loadSettings();
        }
        return cachedSettings;
    }

    public static List<ApprovalMatrixPolicy.Rule> approvalRules() {
        if (rulesOverride != null) {
            return rulesOverride;
        }
        if (cachedRules == null) {
            cachedRules = loadRules();
        }
        return cachedRules;
    }

    private static SubscriptionSettings loadSettings() {
        List<Parametro_Assinatura__mdt> active = new List<Parametro_Assinatura__mdt>();
        for (Parametro_Assinatura__mdt record : Parametro_Assinatura__mdt.getAll().values()) {
            if (record.Ativo__c == true) {
                active.add(record);
            }
        }
        if (active.size() != 1) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_CONFIG_AUSENTE,
                'Os parâmetros de assinatura não estão configurados corretamente (é necessário exatamente um registro ativo). Contate o administrador.'
            );
        }
        Parametro_Assinatura__mdt p = active[0];
        if (p.Variacao_Maxima_Percentual__c == null
            || p.Janela_Efetivacao_Dias__c == null
            || p.Tamanho_Minimo_Justificativa__c == null
            || p.Tamanho_Minimo_Motivo_Rejeicao__c == null) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_CONFIG_AUSENTE,
                'Há parâmetros de assinatura obrigatórios sem valor. Contate o administrador.'
            );
        }
        return new SubscriptionSettings(
            p.Variacao_Maxima_Percentual__c,
            p.Janela_Efetivacao_Dias__c.intValue(),
            p.Tamanho_Minimo_Justificativa__c.intValue(),
            p.Tamanho_Minimo_Motivo_Rejeicao__c.intValue(),
            p.Pricebook_Padrao_Nome__c
        );
    }

    private static List<ApprovalMatrixPolicy.Rule> loadRules() {
        List<ApprovalMatrixPolicy.Rule> rules = new List<ApprovalMatrixPolicy.Rule>();
        for (Matriz_Alcada__mdt record : Matriz_Alcada__mdt.getAll().values()) {
            if (record.Ativo__c != true) {
                continue;
            }
            try {
                rules.add(
                    new ApprovalMatrixPolicy.Rule(
                        record.DeveloperName,
                        ApprovalMatrixPolicy.directionFromCode(record.Direcao__c),
                        ApprovalMatrixPolicy.criterionFromCode(record.Criterio__c),
                        record.Limite_Superior__c,
                        ApprovalMatrixPolicy.levelFromCode(record.Nivel__c),
                        record.Responsavel_Tipo__c,
                        record.Responsavel_Nome__c
                    )
                );
            } catch (Exception invalidRecord) {
                throw new SubscriptionException(
                    SubscriptionConstants.ERR_ALCADA_AUSENTE,
                    'A matriz de alçada possui um registro inválido (' + record.DeveloperName + '). Contate o administrador.'
                );
            }
        }
        if (rules.isEmpty()) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_ALCADA_AUSENTE,
                'A matriz de alçada não está configurada. Contate o administrador.'
            );
        }
        return rules;
    }
}
