/**
 * @description Controle de recursao por CONJUNTO DE IDS + ESTADO (fingerprint), por escopo.
 *
 *              Por que nao um Boolean estatico: um flag global ("ja rodei") bloqueia operacoes
 *              legitimas na mesma transacao (2o lote do mesmo DML, update de Flow, dados diferentes)
 *              e deixa passar recursao quando o flag e resetado no lugar errado.
 *
 *              Semantica: enter() devolve apenas os Ids que NAO estao em processamento com o MESMO
 *              fingerprint. Se o estado do registro mudou (fingerprint diferente) o reprocessamento
 *              e legitimo e e aceito. exit() libera os Ids, permitindo novas operacoes legitimas
 *              depois que a anterior terminou. O limite de profundidade de triggers da plataforma
 *              (16) continua sendo a rede de seguranca contra fingerprints que nunca estabilizam.
 *
 *              Uso: Set<Id> mine = RecursionGuard.enter('scope', ids);
 *                   try { ... } finally { RecursionGuard.exit('scope', mine); }
 */
public with sharing class RecursionGuard {
    private static final Map<String, Map<Id, String>> IN_PROGRESS = new Map<String, Map<Id, String>>();

    public static Set<Id> enter(String scope, Set<Id> recordIds) {
        Map<Id, String> fingerprints = new Map<Id, String>();
        if (recordIds != null) {
            for (Id recordId : recordIds) {
                fingerprints.put(recordId, '');
            }
        }
        return enter(scope, fingerprints);
    }

    public static Set<Id> enter(String scope, Map<Id, String> fingerprints) {
        Set<Id> accepted = new Set<Id>();
        if (fingerprints == null || fingerprints.isEmpty()) {
            return accepted;
        }
        Map<Id, String> active = IN_PROGRESS.get(scope);
        if (active == null) {
            active = new Map<Id, String>();
            IN_PROGRESS.put(scope, active);
        }
        for (Id recordId : fingerprints.keySet()) {
            String fingerprint = fingerprints.get(recordId) == null ? '' : fingerprints.get(recordId);
            String current = active.get(recordId);
            if (current != null && current.equals(fingerprint)) {
                continue;
            }
            active.put(recordId, fingerprint);
            accepted.add(recordId);
        }
        return accepted;
    }

    public static void exit(String scope, Set<Id> recordIds) {
        Map<Id, String> active = IN_PROGRESS.get(scope);
        if (active == null || recordIds == null) {
            return;
        }
        for (Id recordId : recordIds) {
            active.remove(recordId);
        }
    }

    public static Boolean isInProgress(String scope, Id recordId) {
        Map<Id, String> active = IN_PROGRESS.get(scope);
        return active != null && active.containsKey(recordId);
    }

    @TestVisible
    private static void reset() {
        IN_PROGRESS.clear();
    }
}
