/**
 * @description Maquina de estados de Solicitacao_Alteracao__c (dominio puro: sem DML, sem SOQL).
 *              E a UNICA definicao de transicoes validas; a Trigger apenas a consulta e aplica addError.
 *
 *              Rascunho  -> Pendente
 *              Pendente  -> Aprovada | Rejeitada | Cancelada
 *              Aprovada  -> Aplicada | Expirada
 *              Rejeitada -> Rascunho
 *              Cancelada, Aplicada, Expirada: terminais.
 *              Qualquer outra transicao e bloqueada (ex.: Rejeitada -> Aprovada, Rascunho -> Cancelada).
 *
 *              Quem ESCREVE cada transicao esta no documento de ownership (ARQUITETURA.md); esta classe
 *              so valida, nunca grava.
 */
public with sharing class RequestStateMachine {

    private static final Map<String, Set<String>> ALLOWED = new Map<String, Set<String>>{
        SubscriptionConstants.REQ_RASCUNHO => new Set<String>{ SubscriptionConstants.REQ_PENDENTE },
        SubscriptionConstants.REQ_PENDENTE => new Set<String>{
            SubscriptionConstants.REQ_APROVADA,
            SubscriptionConstants.REQ_REJEITADA,
            SubscriptionConstants.REQ_CANCELADA
        },
        SubscriptionConstants.REQ_APROVADA => new Set<String>{
            SubscriptionConstants.REQ_APLICADA,
            SubscriptionConstants.REQ_EXPIRADA
        },
        SubscriptionConstants.REQ_REJEITADA => new Set<String>{ SubscriptionConstants.REQ_RASCUNHO }
    };

    /** Estados em que os itens NUNCA podem ser alterados por nenhum canal. */
    private static final Set<String> ITEMS_PERMANENTLY_FROZEN = new Set<String>{
        SubscriptionConstants.REQ_APROVADA,
        SubscriptionConstants.REQ_APLICADA,
        SubscriptionConstants.REQ_CANCELADA
    };

    /** Mesma situacao nao e transicao: sempre permitida (a Trigger so avalia quando o status muda). */
    public static Boolean isTransitionAllowed(String fromStatus, String toStatus) {
        if (fromStatus == toStatus) {
            return true;
        }
        Set<String> targets = ALLOWED.get(fromStatus);
        return targets != null && targets.contains(toStatus);
    }

    public static Set<String> allowedTargets(String fromStatus) {
        Set<String> targets = ALLOWED.get(fromStatus);
        return targets == null ? new Set<String>() : new Set<String>(targets);
    }

    /** Mensagem amigavel se a transicao for invalida; null se valida. Ideal para addError por registro. */
    public static String transitionError(String fromStatus, String toStatus) {
        if (isTransitionAllowed(fromStatus, toStatus)) {
            return null;
        }
        return 'Transição de status não permitida: de "' + fromStatus + '" para "' + toStatus + '".';
    }

    public static void validateTransition(String fromStatus, String toStatus) {
        String error = transitionError(fromStatus, toStatus);
        if (error != null) {
            throw new SubscriptionException(SubscriptionConstants.ERR_TRANSICAO_INVALIDA, error);
        }
    }

    /** Solicitacao nova so pode nascer em Rascunho (status vazio assume o default da picklist). */
    public static String initialStatusError(String status) {
        if (String.isBlank(status) || status == SubscriptionConstants.REQ_RASCUNHO) {
            return null;
        }
        return 'Uma nova solicitação deve ser criada em "Rascunho" (status informado: "' + status + '").';
    }

    public static Boolean areItemsEditable(String requestStatus) {
        return requestStatus == SubscriptionConstants.REQ_RASCUNHO;
    }

    public static Boolean areItemsPermanentlyFrozen(String requestStatus) {
        return ITEMS_PERMANENTLY_FROZEN.contains(requestStatus);
    }

    /** Mensagem amigavel se os itens nao puderem ser incluidos/editados/excluidos; null se puderem. */
    public static String itemChangeError(String requestStatus) {
        if (areItemsEditable(requestStatus)) {
            return null;
        }
        if (areItemsPermanentlyFrozen(requestStatus)) {
            return 'Os itens de uma solicitação "' + requestStatus + '" não podem mais ser alterados.';
        }
        return 'Os itens só podem ser alterados enquanto a solicitação está em Rascunho (status atual: "'
            + requestStatus + '").';
    }

    public static Boolean isTerminal(String status) {
        return !ALLOWED.containsKey(status);
    }

    // ---- Parte 3: transicoes que exigem service autorizado (ver StatusTransitionContext) ----

    private static final Set<String> AUTHORIZED_TARGETS = new Set<String>{
        SubscriptionConstants.REQ_APROVADA,
        SubscriptionConstants.REQ_REJEITADA,
        SubscriptionConstants.REQ_APLICADA,
        SubscriptionConstants.REQ_EXPIRADA
    };

    /**
     * True quando a mudanca de status so pode ser feita por um service autorizado: decisao (Aprovada/Rejeitada),
     * aplicacao (Aplicada/Expirada) e reabertura (Rejeitada -> Rascunho, que exige historico "Reaberta").
     * Rascunho -> Pendente (envio, validado pela Trigger) e Pendente -> Cancelada continuam abertos ao usuario.
     */
    public static Boolean requiresAuthorizedService(String fromStatus, String toStatus) {
        if (fromStatus == toStatus) {
            return false;
        }
        return AUTHORIZED_TARGETS.contains(toStatus)
            || (fromStatus == SubscriptionConstants.REQ_REJEITADA && toStatus == SubscriptionConstants.REQ_RASCUNHO);
    }

    /**
     * Aresta de COMPENSACAO (Pendente -> Rascunho): nao pertence a tabela de transicoes do usuario; so e aceita
     * pela Trigger quando um service autorizado a abriu (falha de roteamento desfaz o envio).
     */
    public static Boolean isCompensationTransition(String fromStatus, String toStatus) {
        return fromStatus == SubscriptionConstants.REQ_PENDENTE && toStatus == SubscriptionConstants.REQ_RASCUNHO;
    }
}
