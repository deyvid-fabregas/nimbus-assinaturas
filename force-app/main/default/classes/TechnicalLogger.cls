/**
 * @description Log tecnico persistente (Log_Tecnico__c) que SOBREVIVE ao rollback.
 *
 *              Como sobrevive: o Service executa Database.rollback(savepoint) e, DEPOIS do rollback,
 *              chama persist(). O DML do log acontece apos o ponto de reversao e a excecao e tratada
 *              (nao propagada), portanto a transacao e confirmada com o log dentro.
 *              Se a excecao fosse propagada a transacao inteira seria revertida junto com o log;
 *              por isso Controllers/Actions sempre capturam, logam e devolvem resultado amigavel.
 *
 *              MODO SISTEMA (justificado): o DML do log roda em modo sistema de proposito. O usuario
 *              que sofreu a falha pode nao ter permissao de criar Log_Tecnico__c e a falha nao pode
 *              ser perdida por falta de permissao. E o unico DML em modo sistema desta classe, nunca
 *              grava dados de negocio e nunca lanca excecao (falha de log nao pode mascarar o erro real).
 */
public with sharing class TechnicalLogger {
    private static final Integer MAX_TEXT = 32000;
    private static final Integer MAX_SHORT = 255;

    public static final String GENERIC_MESSAGE =
        'Não foi possível concluir a operação. Tente novamente; se o problema persistir, informe o código de referência ao suporte.';

    public static Log_Tecnico__c build(String className, String methodName, Id relatedRecordId, Exception ex) {
        return build(
            className,
            methodName,
            relatedRecordId,
            ex == null ? null : ex.getTypeName(),
            ex == null ? null : ex.getMessage(),
            ex == null ? null : ex.getStackTraceString()
        );
    }

    public static Log_Tecnico__c build(
        String className,
        String methodName,
        Id relatedRecordId,
        String exceptionType,
        String message,
        String stackTrace
    ) {
        return new Log_Tecnico__c(
            Classe__c = clip(className, MAX_SHORT),
            Metodo__c = clip(methodName, MAX_SHORT),
            Registro_Relacionado__c = relatedRecordId == null ? null : String.valueOf(relatedRecordId),
            Tipo_Excecao__c = clip(exceptionType, MAX_SHORT),
            Mensagem__c = clip(message, MAX_TEXT),
            Stack_Trace__c = clip(stackTrace, MAX_TEXT),
            Usuario__c = UserInfo.getUserId(),
            Data_Hora__c = Datetime.now()
        );
    }

    /** Atalho: constroi, persiste e devolve o Id do log (ou null se nao foi possivel gravar). */
    public static Id log(String className, String methodName, Id relatedRecordId, Exception ex) {
        List<Id> ids = persist(new List<Log_Tecnico__c>{ build(className, methodName, relatedRecordId, ex) });
        return ids.isEmpty() ? null : ids[0];
    }

    /** Persiste em lote (1 DML). Nunca lanca excecao. Chamar SEMPRE apos o Database.rollback. */
    public static List<Id> persist(List<Log_Tecnico__c> logs) {
        List<Id> savedIds = new List<Id>();
        if (logs == null || logs.isEmpty()) {
            return savedIds;
        }
        try {
            List<Database.SaveResult> results = Database.insert(logs, false);
            for (Database.SaveResult result : results) {
                if (result.isSuccess()) {
                    savedIds.add(result.getId());
                } else {
                    System.debug(LoggingLevel.ERROR, 'TechnicalLogger: falha ao gravar log: ' + result.getErrors());
                }
            }
        } catch (Exception loggingFailure) {
            System.debug(LoggingLevel.ERROR, 'TechnicalLogger: excecao ao gravar log: ' + loggingFailure.getMessage());
        }
        return savedIds;
    }

    /**
     * Mensagem segura para o usuario final: erros de negocio e regras de validacao (addError)
     * sao nossos e amigaveis; qualquer outra coisa vira mensagem generica + codigo de referencia.
     */
    public static String friendlyMessage(Exception ex, Id logId) {
        if (ex instanceof SubscriptionException) {
            return ex.getMessage();
        }
        if (ex instanceof DmlException) {
            DmlException dmlEx = (DmlException) ex;
            if (dmlEx.getNumDml() > 0 && dmlEx.getDmlType(0) == StatusCode.FIELD_CUSTOM_VALIDATION_EXCEPTION) {
                return dmlEx.getDmlMessage(0);
            }
        }
        return logId == null ? GENERIC_MESSAGE : GENERIC_MESSAGE + ' Código de referência: ' + logId + '.';
    }

    private static String clip(String value, Integer maxLength) {
        if (value == null) {
            return null;
        }
        return value.length() > maxLength ? value.left(maxLength) : value;
    }
}
