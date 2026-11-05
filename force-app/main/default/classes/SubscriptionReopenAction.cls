/**
 * @description Acao invocavel (Screen Flow/Quick Action) de reabertura: Rejeitada -> Rascunho com historico
 *              "Reaberta". Regras de autorizacao no SubscriptionDecisionService.reopen. Nao lanca excecao.
 */
public with sharing class SubscriptionReopenAction {

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
        @InvocableVariable(label='Status')
        public String status;
    }

    @InvocableMethod(
        label='Reabrir solicitação rejeitada'
        description='Devolve a solicitação rejeitada para Rascunho e registra a reabertura no histórico.'
        category='Assinaturas'
    )
    public static List<Result> reopen(List<Request> requests) {
        List<Result> results = new List<Result>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }
        List<Id> ids = new List<Id>();
        for (Request request : requests) {
            ids.add(request == null ? null : request.requestId);
        }
        List<SubscriptionDecisionService.Outcome> outcomes = new SubscriptionDecisionService().reopen(ids);
        for (SubscriptionDecisionService.Outcome outcome : outcomes) {
            Result result = new Result();
            result.requestId = outcome.requestId;
            result.success = outcome.success;
            result.code = outcome.code;
            result.message = outcome.message;
            result.status = outcome.status;
            results.add(result);
        }
        return results;
    }
}
