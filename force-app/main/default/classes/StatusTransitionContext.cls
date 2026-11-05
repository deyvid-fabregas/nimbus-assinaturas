/**
 * @description Escopo CONTROLADO de mudanca de status de Solicitacao_Alteracao__c (fecha o contorno por API).
 *
 *              PROBLEMA: Status__c e editavel (envio/cancelamento), entao um usuario poderia, por API/Data Loader,
 *              mover Pendente -> Aprovada sem passar por permissao, designacao e segregacao de funcoes.
 *
 *              MECANISMO: a Trigger (SolicitacaoAlteracaoHandler) so aceita transicoes "gated"
 *              (RequestStateMachine.requiresAuthorizedService / isCompensationTransition) se, NA MESMA transacao,
 *              um service autorizado abriu este escopo para aquele registro E aquele status de destino.
 *              Escopo por (Id da solicitacao, status de destino), com contador (aberturas aninhadas) e fechamento
 *              em finally. Nao e booleano global: abrir para A -> Aprovada nao autoriza B nem A -> Rejeitada.
 *
 *              QUEM PODE ABRIR (regra de analise estatica/code review): SubscriptionDecisionService,
 *              SubscriptionApplyService, ApprovalRoutingService e classes de teste. Nunca Controller/Action/Handler.
 *              Limite conhecido: quem executa Apex arbitrario (Author Apex/Execute Anonymous) pode abrir o escopo;
 *              e o mesmo limite do ControlledWriteContext e se mitiga restringindo essa permissao no org.
 */
public with sharing class StatusTransitionContext {
    private static final Map<String, Integer> OPEN_COUNT = new Map<String, Integer>();

    public class Scope {
        private final Set<String> keys;
        private Boolean closed = false;

        public Scope(Set<String> keys) {
            this.keys = keys;
        }

        public void close() {
            if (closed) {
                return;
            }
            closed = true;
            for (String key : keys) {
                Integer count = OPEN_COUNT.get(key);
                if (count == null || count <= 1) {
                    OPEN_COUNT.remove(key);
                } else {
                    OPEN_COUNT.put(key, count - 1);
                }
            }
        }
    }

    public static Scope open(Set<Id> requestIds, Set<String> targetStatuses, String justification) {
        if (CollectionUtil.isNullOrEmpty(requestIds)
            || CollectionUtil.isNullOrEmpty(targetStatuses)
            || TextUtil.isBlank(justification)) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_BYPASS_INVALIDO,
                'Mudança de status controlada exige solicitações, status de destino e justificativa documentada.'
            );
        }
        Set<String> opened = new Set<String>();
        for (Id requestId : requestIds) {
            for (String target : targetStatuses) {
                String key = keyOf(requestId, target);
                opened.add(key);
                Integer count = OPEN_COUNT.get(key);
                OPEN_COUNT.put(key, count == null ? 1 : count + 1);
            }
        }
        System.debug(LoggingLevel.INFO, 'StatusTransitionContext aberto (' + requestIds.size() + ' solicitação(ões)): ' + justification);
        return new Scope(opened);
    }

    public static Boolean isAuthorized(Id requestId, String targetStatus) {
        return requestId != null && OPEN_COUNT.containsKey(keyOf(requestId, targetStatus));
    }

    private static String keyOf(Id requestId, String targetStatus) {
        return String.valueOf(requestId) + '|' + targetStatus;
    }
}
