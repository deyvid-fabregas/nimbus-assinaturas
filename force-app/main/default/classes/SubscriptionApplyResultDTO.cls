/**
 * @description Resultado da aplicacao (US-06). Nunca contem stack trace; mensagens sao acionaveis.
 */
public with sharing class SubscriptionApplyResultDTO {
    @AuraEnabled public Boolean success = false;
    /** True quando o Aditivo ja existia (segunda chamada): devolve o resultado existente, sem criar nada. */
    @AuraEnabled public Boolean alreadyApplied = false;
    @AuraEnabled public String code;
    @AuraEnabled public String message;
    @AuraEnabled public Id requestId;
    @AuraEnabled public String status;
    @AuraEnabled public Id additiveId;
    @AuraEnabled public Id orderId;
    @AuraEnabled public Decimal contractVersion;
    @AuraEnabled public Decimal newMrr;

    public static SubscriptionApplyResultDTO failure(Id requestId, String code, String message) {
        SubscriptionApplyResultDTO result = new SubscriptionApplyResultDTO();
        result.requestId = requestId;
        result.code = code;
        result.message = message;
        return result;
    }
}
