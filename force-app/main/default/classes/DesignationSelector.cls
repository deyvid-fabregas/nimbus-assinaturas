/**
 * @description Selector de DESIGNACAO de aprovadores (Group, GroupMember, User, UserRole), WITH USER_MODE.
 *              Responsavel = (tipo, DeveloperName) lido de Matriz_Alcada__mdt: GRUPO (grupo publico), FILA (queue)
 *              ou PAPEL (UserRole). Chave canonica: "TIPO|DeveloperName".
 *
 *              Limitacoes: membros sao DIRETOS (grupos aninhados e "papel e subordinados" nao sao expandidos).
 *              Custo fixo, independente do numero de solicitacoes: keysForUser = 2 SOQL; firstActiveUserByKey = 2-3 SOQL.
 */
public with sharing class DesignationSelector {
    private static final String USER_ID_PREFIX = '005';

    public static String keyOf(String responsibleType, String responsibleName) {
        return responsibleType + '|' + responsibleName;
    }

    /** Todas as chaves de responsavel as quais o usuario pertence (grupos publicos, filas e papel). */
    public Set<String> keysForUser(Id userId) {
        Set<String> keys = new Set<String>();
        if (userId == null) {
            return keys;
        }
        for (GroupMember member : [
            SELECT Group.DeveloperName, Group.Type
            FROM GroupMember
            WHERE UserOrGroupId = :userId
            WITH USER_MODE
        ]) {
            String type = respTypeOf(member.Group.Type);
            if (type != null) {
                keys.add(keyOf(type, member.Group.DeveloperName));
            }
        }
        for (User user : [
            SELECT UserRole.DeveloperName
            FROM User
            WHERE Id = :userId AND UserRoleId != NULL
            WITH USER_MODE
        ]) {
            keys.add(keyOf(SubscriptionConstants.RESP_PAPEL, user.UserRole.DeveloperName));
        }
        return keys;
    }

    /**
     * Para cada chave pedida, um usuario ATIVO membro do responsavel (menor Nome, depois menor Id: deterministico).
     * Chaves sem usuario ativo ficam ausentes do resultado.
     */
    public Map<String, Id> firstActiveUserByKey(Set<String> requestedKeys) {
        Map<String, Id> result = new Map<String, Id>();
        if (CollectionUtil.isNullOrEmpty(requestedKeys)) {
            return result;
        }
        Set<String> groupNames = new Set<String>();
        Set<String> roleNames = new Set<String>();
        for (String key : requestedKeys) {
            String type = key.substringBefore('|');
            String name = key.substringAfter('|');
            if (type == SubscriptionConstants.RESP_PAPEL) {
                roleNames.add(name);
            } else {
                groupNames.add(name);
            }
        }

        Set<String> groupTypes = new Set<String>{
            SubscriptionConstants.GROUP_TYPE_PUBLIC, SubscriptionConstants.GROUP_TYPE_QUEUE
        };
        Map<String, Set<Id>> candidatesByKey = new Map<String, Set<Id>>();
        Set<Id> candidateIds = new Set<Id>();
        if (!groupNames.isEmpty()) {
            for (GroupMember member : [
                SELECT UserOrGroupId, Group.DeveloperName, Group.Type
                FROM GroupMember
                WHERE Group.DeveloperName IN :groupNames AND Group.Type IN :groupTypes
                WITH USER_MODE
            ]) {
                String type = respTypeOf(member.Group.Type);
                String key = keyOf(type, member.Group.DeveloperName);
                if (!requestedKeys.contains(key) || !String.valueOf(member.UserOrGroupId).startsWith(USER_ID_PREFIX)) {
                    continue;
                }
                addCandidate(candidatesByKey, key, member.UserOrGroupId);
                candidateIds.add(member.UserOrGroupId);
            }
        }
        if (!roleNames.isEmpty()) {
            for (User user : [
                SELECT Id, UserRole.DeveloperName
                FROM User
                WHERE UserRole.DeveloperName IN :roleNames AND IsActive = true
                WITH USER_MODE
            ]) {
                String key = keyOf(SubscriptionConstants.RESP_PAPEL, user.UserRole.DeveloperName);
                addCandidate(candidatesByKey, key, user.Id);
                candidateIds.add(user.Id);
            }
        }
        if (candidateIds.isEmpty()) {
            return result;
        }
        Map<Id, User> activeUsers = new Map<Id, User>(
            [SELECT Id, Name FROM User WHERE Id IN :candidateIds AND IsActive = true WITH USER_MODE]
        );
        for (String key : candidatesByKey.keySet()) {
            User best = null;
            for (Id candidateId : candidatesByKey.get(key)) {
                User candidate = activeUsers.get(candidateId);
                if (candidate != null && (best == null || isBefore(candidate, best))) {
                    best = candidate;
                }
            }
            if (best != null) {
                result.put(key, best.Id);
            }
        }
        return result;
    }

    private static void addCandidate(Map<String, Set<Id>> target, String key, Id userId) {
        Set<Id> bucket = target.get(key);
        if (bucket == null) {
            bucket = new Set<Id>();
            target.put(key, bucket);
        }
        bucket.add(userId);
    }

    private static Boolean isBefore(User candidate, User current) {
        Integer byName = candidate.Name.compareTo(current.Name);
        return byName < 0 || (byName == 0 && String.valueOf(candidate.Id) < String.valueOf(current.Id));
    }

    private static String respTypeOf(String groupType) {
        if (groupType == SubscriptionConstants.GROUP_TYPE_PUBLIC) {
            return SubscriptionConstants.RESP_GRUPO;
        }
        if (groupType == SubscriptionConstants.GROUP_TYPE_QUEUE) {
            return SubscriptionConstants.RESP_FILA;
        }
        return null;
    }
}
