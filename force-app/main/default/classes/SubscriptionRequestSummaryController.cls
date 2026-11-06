/**
 * @description Controller minimo do LWC subscriptionRequestSummary. Somente leitura; os indicadores can* sao
 *              conveniencia de UX e cada acao revalida tudo no servidor. Falhas voltam como AuraHandledException
 *              (nao ha DML a perder).
 */
public with sharing class SubscriptionRequestSummaryController {

    @AuraEnabled(cacheable=false)
    public static SubscriptionRequestSummaryDTO getSummary(Id requestId) {
        return load(new SubscriptionRequestSummaryService(), requestId);
    }

    public static SubscriptionRequestSummaryDTO load(SubscriptionRequestSummaryService service, Id requestId) {
        try {
            return service.build(requestId);
        } catch (SubscriptionException businessError) {
            throw friendly(businessError.getMessage());
        } catch (Exception unexpected) {
            throw friendly(TechnicalLogger.friendlyMessage(unexpected, null));
        }
    }

    private static AuraHandledException friendly(String message) {
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }
}
