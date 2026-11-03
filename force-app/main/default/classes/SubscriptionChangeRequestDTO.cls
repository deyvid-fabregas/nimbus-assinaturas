/**
 * @description Intencao do usuario para simular/salvar uma alteracao contratual (US-01).
 *
 *              CONTRATO ANTI-ADULTERACAO: o servidor le SOMENTE os campos da secao INTENCAO.
 *              Os campos da secao NAO CONFIAVEIS existem para que um cliente adulterado (ou um teste que
 *              simula um) possa envia-los sem erro de desserializacao, mas NUNCA sao lidos: precos, deltas,
 *              totais, nivel de aprovacao e status sao recalculados e definidos no servidor.
 */
public with sharing class SubscriptionChangeRequestDTO {

    // ---------------- INTENCAO (lida pelo servidor) ----------------
    /** Opcional. Informado = editar o Rascunho existente; vazio = criar nova solicitacao. */
    @AuraEnabled public Id requestId;
    @AuraEnabled public Id contractId;
    /** Opcional. Vazio ou igual ao plano atual = sem troca de plano. */
    @AuraEnabled public Id proposedPlanId;
    @AuraEnabled public Date effectiveDate;
    @AuraEnabled public String justification;
    /** Obrigatoria ao CRIAR (salvar duas vezes com a mesma chave devolve a mesma solicitacao). */
    @AuraEnabled public String idempotencyKey;
    @AuraEnabled public List<ItemDTO> items = new List<ItemDTO>();

    // ---------------- NAO CONFIAVEIS (ignorados) ----------------
    @AuraEnabled public String status;
    @AuraEnabled public String approvalLevel;
    @AuraEnabled public Decimal baseMrr;
    @AuraEnabled public Decimal proposedMrr;
    @AuraEnabled public Decimal absoluteVariation;
    @AuraEnabled public Decimal percentVariation;

    public class ItemDTO {
        // INTENCAO
        @AuraEnabled public Id productId;
        /** Adicionar | Alterar Quantidade | Remover (valores de Item_Alteracao__c.Acao__c). */
        @AuraEnabled public String action;
        /** Remover aceita vazio (tratado como zero no servidor). */
        @AuraEnabled public Decimal newQuantity;

        // NAO CONFIAVEIS
        @AuraEnabled public Decimal unitPrice;
        @AuraEnabled public Decimal currentQuantity;
        @AuraEnabled public Decimal deltaMrr;
    }

    /** Atalho de montagem (uso em Controller/testes). */
    public static ItemDTO item(Id productId, String action, Decimal newQuantity) {
        ItemDTO result = new ItemDTO();
        result.productId = productId;
        result.action = action;
        result.newQuantity = newQuantity;
        return result;
    }
}
