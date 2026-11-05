/**
 * @description Caminho de falha (Fault) do Record-Triggered Flow de roteamento: registra Log_Tecnico__c e desfaz o
 *              envio (Pendente -> Rascunho) para que a solicitacao nao fique Pendente sem rota. Idempotente.
 */
public with sharing class ApprovalRoutingFaultAction {

    public class Request {
        @InvocableVariable(label='Solicitação (Id)' required=true)
        public Id requestId;
        @InvocableVariable(label='Mensagem de erro do Flow')
        public String errorMessage;
    }

    public class Result {
        @InvocableVariable(label='Solicitação (Id)')
        public Id requestId;
        @InvocableVariable(label='Envio desfeito')
        public Boolean compensated;
    }

    @InvocableMethod(
        label='Compensar falha de roteamento'
        description='Registra o erro técnico e devolve a solicitação para Rascunho.'
        category='Assinaturas'
    )
    public static List<Result> compensate(List<Request> requests) {
        List<Result> results = new List<Result>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }
        Map<Id, String> reasons = new Map<Id, String>();
        for (Request request : requests) {
            if (request != null && request.requestId != null) {
                reasons.put(
                    request.requestId,
                    TextUtil.isBlank(request.errorMessage) ? 'Falha não detalhada no Flow de roteamento.' : request.errorMessage
                );
            }
        }
        Set<Id> compensated = new ApprovalRoutingService().compensate(reasons);
        for (Request request : requests) {
            Result result = new Result();
            result.requestId = request == null ? null : request.requestId;
            result.compensated = result.requestId != null && compensated.contains(result.requestId);
            results.add(result);
        }
        return results;
    }
}
