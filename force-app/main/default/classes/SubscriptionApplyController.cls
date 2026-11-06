/**
 * @description Controller FINO da aplicacao (US-06): orquestra e NUNCA lanca excecao, para que o Log_Tecnico__c
 *              gravado pelo service sobreviva (excecao nao tratada em @AuraEnabled reverteria a transacao inteira).
 *              A permissao Aplicar_Alteracao e todas as regras sao verificadas no SubscriptionApplyService.
 */
public with sharing class SubscriptionApplyController {

    @AuraEnabled
    public static SubscriptionApplyResultDTO apply(Id requestId) {
        return runApply(new SubscriptionApplyService(), requestId);
    }

    /** Executa a aplicacao garantindo que nenhuma excecao escape (reuso pela SubscriptionApplyAction). */
    public static SubscriptionApplyResultDTO runApply(SubscriptionApplyService service, Id requestId) {
        try {
            return service.apply(requestId);
        } catch (Exception unexpected) {
            Id logId = TechnicalLogger.log('SubscriptionApplyController', 'apply', requestId, unexpected);
            return SubscriptionApplyResultDTO.failure(
                requestId, SubscriptionConstants.ERR_INESPERADO, TechnicalLogger.friendlyMessage(unexpected, logId)
            );
        }
    }
}
