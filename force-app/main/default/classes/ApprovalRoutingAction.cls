/**
 * @description Acao invocavel (Record-Triggered Flow, after-save) que classifica a alcada e roteia a solicitacao.
 *              Bulkificada: um unico acionamento do service para todos os registros do lote do Flow.
 *              NAO lanca excecao: falhas viram Result.success = false (o service ja logou e compensou), para que o
 *              Log_Tecnico__c nao seja revertido junto com a transacao.
 */
public with sharing class ApprovalRoutingAction {

    public class Request {
        @InvocableVariable(label='Solicitação (Id)' required=true)
        public Id requestId;
    }

    public class Result {
        @InvocableVariable(label='Solicitação (Id)')
        public Id requestId;
        @InvocableVariable(label='Sucesso')
        public Boolean success;
        @InvocableVariable(label='Código')
        public String code;
        @InvocableVariable(label='Mensagem')
        public String message;
        @InvocableVariable(label='Nível de aprovação')
        public String approvalLevel;
    }

    @InvocableMethod(
        label='Rotear aprovação da solicitação'
        description='Classifica a alçada pela matriz, cria a Task do aprovador ou aprova automaticamente.'
        category='Assinaturas'
    )
    public static List<Result> route(List<Request> requests) {
        List<Result> results = new List<Result>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }
        Set<Id> ids = new Set<Id>();
        for (Request request : requests) {
            if (request != null && request.requestId != null) {
                ids.add(request.requestId);
            }
        }
        Map<Id, ApprovalRoutingService.Outcome> outcomes = new Map<Id, ApprovalRoutingService.Outcome>();
        String unexpectedMessage = null;
        try {
            outcomes = new ApprovalRoutingService().route(ids);
        } catch (Exception unexpected) {
            Id logId = TechnicalLogger.log('ApprovalRoutingAction', 'route', null, unexpected);
            unexpectedMessage = TechnicalLogger.friendlyMessage(unexpected, logId);
        }
        for (Request request : requests) {
            Result result = new Result();
            result.requestId = request == null ? null : request.requestId;
            ApprovalRoutingService.Outcome outcome = result.requestId == null ? null : outcomes.get(result.requestId);
            if (outcome != null) {
                result.success = outcome.success;
                result.code = outcome.code;
                result.message = outcome.message;
                result.approvalLevel = outcome.approvalLevel;
            } else {
                result.success = false;
                result.code = SubscriptionConstants.ERR_INESPERADO;
                result.message = unexpectedMessage == null ? 'Solicitação não informada.' : unexpectedMessage;
            }
            results.add(result);
        }
        return results;
    }
}
