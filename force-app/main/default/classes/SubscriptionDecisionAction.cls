/**
 * @description Acao invocavel do Screen Flow de decisao (aprovar/rejeitar). Apenas converte entrada/saida:
 *              toda regra (permissao, designacao, segregacao, ciclo, lock, idempotencia) esta no
 *              SubscriptionDecisionService. Nao lanca excecao; devolve resultado estruturado.
 */
public with sharing class SubscriptionDecisionAction {

    public class Request {
        @InvocableVariable(label='Solicitação (Id)' required=true)
        public Id requestId;
        @InvocableVariable(label='Ciclo exibido na tela' required=true)
        public Decimal cycle;
        @InvocableVariable(label='Decisão (Aprovada ou Rejeitada)' required=true)
        public String decision;
        @InvocableVariable(label='Motivo da rejeição')
        public String reason;
    }

    public class Result {
        @InvocableVariable(label='Solicitação (Id)')
        public Id requestId;
        @InvocableVariable(label='Sucesso')
        public Boolean success;
        @InvocableVariable(label='Já decidida')
        public Boolean alreadyResolved;
        @InvocableVariable(label='Código')
        public String code;
        @InvocableVariable(label='Mensagem')
        public String message;
        @InvocableVariable(label='Status')
        public String status;
    }

    @InvocableMethod(
        label='Decidir solicitação de alteração'
        description='Aprova ou rejeita validando permissão, designação, segregação de funções, estado e ciclo no servidor.'
        category='Assinaturas'
    )
    public static List<Result> decide(List<Request> requests) {
        List<Result> results = new List<Result>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }
        List<SubscriptionDecisionService.Input> inputs = new List<SubscriptionDecisionService.Input>();
        for (Request request : requests) {
            SubscriptionDecisionService.Input input = new SubscriptionDecisionService.Input();
            if (request != null) {
                input.requestId = request.requestId;
                input.cycle = request.cycle;
                input.decision = request.decision;
                input.reason = request.reason;
            }
            inputs.add(input);
        }
        List<SubscriptionDecisionService.Outcome> outcomes = new SubscriptionDecisionService().decide(inputs);
        for (SubscriptionDecisionService.Outcome outcome : outcomes) {
            Result result = new Result();
            result.requestId = outcome.requestId;
            result.success = outcome.success;
            result.alreadyResolved = outcome.alreadyResolved;
            result.code = outcome.code;
            result.message = outcome.message;
            result.status = outcome.status;
            results.add(result);
        }
        return results;
    }
}
