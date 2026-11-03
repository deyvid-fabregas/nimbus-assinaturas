/**
 * @description Verificacoes de seguranca reutilizaveis (CRUD, Custom Permission, stripInaccessible).
 *              Complementa -- nao substitui -- WITH USER_MODE nas consultas e AccessLevel.USER_MODE
 *              nos DMLs. Toda mensagem lancada e amigavel (sem detalhes internos).
 *              Custom Permissions sao avaliadas para o USUARIO EM EXECUCAO
 *              (FeatureManagement.checkPermission), funcionando com System.runAs em testes.
 */
public with sharing class SecurityGuard {

    public static Boolean hasCustomPermission(String developerName) {
        return String.isNotBlank(developerName) && FeatureManagement.checkPermission(developerName);
    }

    public static void requireCustomPermission(String developerName, String friendlyMessage) {
        if (!hasCustomPermission(developerName)) {
            throw new SubscriptionException(SubscriptionConstants.ERR_SEM_PERMISSAO, friendlyMessage);
        }
    }

    public static void requireReadable(Schema.SObjectType sObjectType) {
        if (!sObjectType.getDescribe().isAccessible()) {
            throw deny('visualizar', sObjectType);
        }
    }

    public static void requireCreateable(Schema.SObjectType sObjectType) {
        if (!sObjectType.getDescribe().isCreateable()) {
            throw deny('criar', sObjectType);
        }
    }

    public static void requireUpdateable(Schema.SObjectType sObjectType) {
        if (!sObjectType.getDescribe().isUpdateable()) {
            throw deny('editar', sObjectType);
        }
    }

    public static void requireDeletable(Schema.SObjectType sObjectType) {
        if (!sObjectType.getDescribe().isDeletable()) {
            throw deny('excluir', sObjectType);
        }
    }

    /**
     * Remove campos sem FLS do tipo de acesso informado. Uso tipico: sanitizar registros montados
     * a partir de DTOs antes de um DML em modo sistema (casos isolados e justificados).
     */
    public static SObjectAccessDecision strip(System.AccessType accessType, List<SObject> records) {
        return Security.stripInaccessible(accessType, records == null ? new List<SObject>() : records);
    }

    private static SubscriptionException deny(String verb, Schema.SObjectType sObjectType) {
        return new SubscriptionException(
            SubscriptionConstants.ERR_SEM_ACESSO,
            'Você não tem permissão para ' + verb + ' registros de "' + sObjectType.getDescribe().getLabelPlural()
                + '". Solicite o Permission Set adequado ao administrador.'
        );
    }
}
