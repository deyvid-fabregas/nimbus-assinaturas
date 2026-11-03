/**
 * @description UNICO ponto de escrita em MODO SISTEMA + SEM SHARING da Parte 2 (excecao isolada e minima).
 *
 *              POR QUE sem sharing e sem CRUD/FLS do usuario: grava SOMENTE campos calculados e protegidos
 *              (Solicitacao_Alteracao__c.MRR_Proposto__c / Variacao_*; Contrato_Assinatura__c.MRR_Atual__c).
 *              Esses campos sao somente leitura para todos os Permission Sets (so Service/Trigger escrevem).
 *              Um DML em USER_MODE falharia por FLS, e um DML "with sharing" falharia para quem edita o item
 *              mas nao tem edicao no pai (mesma razao de um roll-up summary ignorar sharing).
 *
 *              GARANTIAS: (1) recebe registros ja montados pelos Services contendo apenas Id + campos
 *              calculados; (2) nao contem regra de negocio nem consulta; (3) nunca e chamado por Controller/
 *              Action. Auditoria: grep por "without sharing" deve listar apenas esta classe.
 */
public without sharing class CalculatedFieldWriter {

    public static void updateRequestTotals(List<Solicitacao_Alteracao__c> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }
        update requests; // NOPMD - modo sistema intencional (ver cabecalho)
    }

    public static void updateContractMrr(List<Contrato_Assinatura__c> contracts) {
        if (contracts == null || contracts.isEmpty()) {
            return;
        }
        update contracts; // NOPMD - modo sistema intencional (ver cabecalho)
    }
}
