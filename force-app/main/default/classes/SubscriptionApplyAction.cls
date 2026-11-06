/**
 * @description Acao invocavel do Screen Flow de aplicacao: apenas delega ao SubscriptionApplyService (permissao
 *              Aplicar_Alteracao, locks, versao, idempotencia e atomicidade estao la). Nao lanca excecao.
 */
public with sharing class SubscriptionApplyAction {

    public class Request {
        @InvocableVariable(label='Solicitação (Id)' required=true)
        public Id requestId;
    }

    public class Result {
        @InvocableVariable(label='Sucesso')
        public Boolean success;
        @InvocableVariable(label='Já aplicada')
        public Boolean alreadyApplied;
        @InvocableVariable(label='Código')
        public String code;
        @InvocableVariable(label='Mensagem')
        public String message;
        @InvocableVariable(label='Status')
        public String status;
        @InvocableVariable(label='Aditivo (Id)')
        public Id additiveId;
        @InvocableVariable(label='Pedido (Id)')
        public Id orderId;
    }

    @InvocableMethod(
        label='Aplicar alteração aprovada'
        description='Aplica a alteração aprovada ao contrato gerando Aditivo e Pedido de forma atômica e idempotente.'
        category='Assinaturas'
    )
    public static List<Result> apply(List<Request> requests) {
        List<Result> results = new List<Result>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }
        if (requests.size() > 1) {
            // Aplicacao e atomica por solicitacao (locks e DML proprios): nao ha aplicacao em lote.
            for (Request ignored : requests) {
                Result rejected = new Result();
                rejected.success = false;
                rejected.alreadyApplied = false;
                rejected.code = SubscriptionConstants.ERR_ENTRADA_INVALIDA;
                rejected.message = 'Aplique uma solicitação por vez.';
                results.add(rejected);
            }
            return results;
        }
        SubscriptionApplyResultDTO outcome = SubscriptionApplyController.runApply(
            new SubscriptionApplyService(), requests[0] == null ? null : requests[0].requestId
        );
        Result result = new Result();
        result.success = outcome.success;
        result.alreadyApplied = outcome.alreadyApplied;
        result.code = outcome.code;
        result.message = outcome.message;
        result.status = outcome.status;
        result.additiveId = outcome.additiveId;
        result.orderId = outcome.orderId;
        results.add(result);
        return results;
    }
}
