/**
 * @description Bypass CONTROLADO para escrita em Item_Contrato__c (e demais campos protegidos).
 *
 *              Regra do desafio: itens de contrato so podem mudar pelo fluxo de aplicacao
 *              (SubscriptionApplyService). A Trigger de Item_Contrato__c bloqueia qualquer escrita,
 *              exceto quando o Contrato do item esta "aberto" aqui.
 *
 *              Garantias:
 *              1) ESCOPO DE TRANSACAO: estado estatico, que a plataforma zera ao fim da transacao.
 *              2) ESCOPO DE REGISTRO: abre apenas para os Ids de contrato informados, nunca global.
 *              3) JUSTIFICATIVA obrigatoria (texto documentado no ponto de chamada e no README).
 *              4) FECHAMENTO em finally: Scope.close() e idempotente e aceita aninhamento (contador).
 *
 *              Limite honesto: Apex nao tem "friend class"; a restricao a SubscriptionApplyService e
 *              feita por convencao + code review + regra de analise estatica (grep/PMD) que falha o
 *              build se open() aparecer fora dessa classe e das classes de teste.
 *
 *              Uso: ControlledWriteContext.Scope scope = ControlledWriteContext.open(contractIds, 'motivo');
 *                   try { ...DML... } finally { scope.close(); }
 */
public with sharing class ControlledWriteContext {
    private static final Map<Id, Integer> OPEN_COUNT = new Map<Id, Integer>();

    public class Scope {
        private final Set<Id> contractIds;
        private Boolean closed = false;

        public Scope(Set<Id> contractIds) {
            this.contractIds = contractIds;
        }

        public void close() {
            if (closed) {
                return;
            }
            closed = true;
            for (Id contractId : contractIds) {
                Integer count = OPEN_COUNT.get(contractId);
                if (count == null || count <= 1) {
                    OPEN_COUNT.remove(contractId);
                } else {
                    OPEN_COUNT.put(contractId, count - 1);
                }
            }
        }
    }

    public static Scope open(Set<Id> contractIds, String justification) {
        if (CollectionUtil.isNullOrEmpty(contractIds) || TextUtil.isBlank(justification)) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_BYPASS_INVALIDO,
                'Escrita controlada exige contratos e justificativa documentada.'
            );
        }
        Set<Id> opened = new Set<Id>(contractIds);
        for (Id contractId : opened) {
            Integer count = OPEN_COUNT.get(contractId);
            OPEN_COUNT.put(contractId, count == null ? 1 : count + 1);
        }
        System.debug(LoggingLevel.INFO, 'ControlledWriteContext aberto (' + opened.size() + ' contrato(s)): ' + justification);
        return new Scope(opened);
    }

    public static Boolean isOpenFor(Id contractId) {
        return contractId != null && OPEN_COUNT.containsKey(contractId);
    }

    /** True somente se TODOS os contratos informados estao abertos (uso em lote na Trigger). */
    public static Boolean isOpenForAll(Set<Id> contractIds) {
        if (CollectionUtil.isNullOrEmpty(contractIds)) {
            return false;
        }
        for (Id contractId : contractIds) {
            if (!OPEN_COUNT.containsKey(contractId)) {
                return false;
            }
        }
        return true;
    }
}
