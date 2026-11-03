/**
 * @description Resultado de simular/salvar (US-01). Todos os valores vem do SERVIDOR.
 *              success/errorCode/message permitem que o Controller devolva falhas sem lancar excecao
 *              (excecao nao tratada no @AuraEnabled reverte a transacao inteira, inclusive o Log_Tecnico__c).
 */
public with sharing class SubscriptionChangeResultDTO {
    @AuraEnabled public Boolean success = true;
    @AuraEnabled public String errorCode;
    @AuraEnabled public String message;
    /** True quando a mesma Chave_Idempotencia__c ja existia e a solicitacao existente foi devolvida. */
    @AuraEnabled public Boolean reusedExisting = false;

    @AuraEnabled public Id requestId;
    @AuraEnabled public String requestName;
    @AuraEnabled public String status;
    @AuraEnabled public String requestType;
    @AuraEnabled public Id contractId;
    @AuraEnabled public Id proposedPlanId;
    @AuraEnabled public Date effectiveDate;

    @AuraEnabled public Decimal baseMrr;
    @AuraEnabled public Decimal proposedMrr;
    @AuraEnabled public Decimal absoluteVariation;
    /** Pontos percentuais (18.00 = 18%); null quando a base e zero e ha variacao. */
    @AuraEnabled public Decimal percentVariation;

    /** Nivel PREVISTO (rotulo da picklist). A persistencia do nivel e do Flow de roteamento (US-03). */
    @AuraEnabled public String approvalLevel;
    @AuraEnabled public String responsibleType;
    @AuraEnabled public String responsibleName;
    @AuraEnabled public Boolean blocked = false;
    @AuraEnabled public String blockMessage;

    @AuraEnabled public List<LineDTO> lines = new List<LineDTO>();

    public class LineDTO {
        @AuraEnabled public Id contractItemId;
        @AuraEnabled public Id productId;
        @AuraEnabled public String action;
        @AuraEnabled public Decimal currentQuantity;
        @AuraEnabled public Decimal newQuantity;
        @AuraEnabled public Decimal unitPrice;
        @AuraEnabled public Decimal deltaMrr;
    }

    public static SubscriptionChangeResultDTO failure(String code, String message) {
        SubscriptionChangeResultDTO result = new SubscriptionChangeResultDTO();
        result.success = false;
        result.errorCode = code;
        result.message = message;
        return result;
    }
}
