/**
 * @description Selector do catalogo Plano_Assinatura__c (WITH USER_MODE).
 */
public with sharing class PlanSelector {

    public List<Plano_Assinatura__c> selectActive() {
        return [
            SELECT Id, Name, Codigo__c, Nivel__c, Produto__c, Preco_Base_Mensal__c,
                   Licencas_Minimas__c, Licencas_Maximas__c, Ativo__c
            FROM Plano_Assinatura__c
            WHERE Ativo__c = true
            WITH USER_MODE
            ORDER BY Nivel__c ASC, Name ASC
            LIMIT 500
        ];
    }

    /** Inclui planos inativos: a validacao "plano proposto inativo" precisa enxerga-los. */
    public List<Plano_Assinatura__c> selectByIds(Set<Id> planIds) {
        if (CollectionUtil.isNullOrEmpty(planIds)) {
            return new List<Plano_Assinatura__c>();
        }
        return [
            SELECT Id, Name, Codigo__c, Nivel__c, Produto__c, Preco_Base_Mensal__c,
                   Licencas_Minimas__c, Licencas_Maximas__c, Ativo__c
            FROM Plano_Assinatura__c
            WHERE Id IN :planIds
            WITH USER_MODE
        ];
    }

    public Map<Id, Plano_Assinatura__c> mapByIds(Set<Id> planIds) {
        return new Map<Id, Plano_Assinatura__c>(selectByIds(planIds));
    }

    public List<Plano_Assinatura__c> selectByCodes(Set<String> codes) {
        if (CollectionUtil.isNullOrEmpty(codes)) {
            return new List<Plano_Assinatura__c>();
        }
        return [
            SELECT Id, Name, Codigo__c, Nivel__c, Produto__c, Preco_Base_Mensal__c,
                   Licencas_Minimas__c, Licencas_Maximas__c, Ativo__c
            FROM Plano_Assinatura__c
            WHERE Codigo__c IN :codes
            WITH USER_MODE
        ];
    }
}
