# Parte 1 — Código Apex completo
Cole cada bloco em `force-app/main/default/classes/<Nome>.cls` (o `-meta.xml` usa apiVersion 62.0, status Active). O zip já contém tudo organizado.

---

## SubscriptionConstants.cls

```apex
/**
 * @description Constantes de dominio do modulo de assinaturas: valores de picklist,
 *              nomes de Custom Permissions e codigos de erro.
 *              NAO contem parametros de negocio (limites, aliquotas, pricebook): esses vivem em
 *              Custom Metadata (Parametro_Assinatura__mdt / Matriz_Alcada__mdt).
 *              Os valores precisam coincidir com os valores de API das picklists.
 */
public with sharing class SubscriptionConstants {
    private SubscriptionConstants() {}

    // Contrato_Assinatura__c.Status__c
    public static final String CTR_RASCUNHO = 'Rascunho';
    public static final String CTR_ATIVO = 'Ativo';
    public static final String CTR_SUSPENSO = 'Suspenso';
    public static final String CTR_ENCERRADO = 'Encerrado';

    // Solicitacao_Alteracao__c.Status__c
    public static final String REQ_RASCUNHO = 'Rascunho';
    public static final String REQ_PENDENTE = 'Pendente';
    public static final String REQ_APROVADA = 'Aprovada';
    public static final String REQ_REJEITADA = 'Rejeitada';
    public static final String REQ_CANCELADA = 'Cancelada';
    public static final String REQ_APLICADA = 'Aplicada';
    public static final String REQ_EXPIRADA = 'Expirada';

    // Solicitacao_Alteracao__c.Tipo__c
    public static final String TIPO_UPGRADE = 'Upgrade';
    public static final String TIPO_DOWNGRADE = 'Downgrade';
    public static final String TIPO_ADICAO_LICENCAS = 'Adição de Licenças';
    public static final String TIPO_REDUCAO_LICENCAS = 'Redução de Licenças';
    public static final String TIPO_RECURSO_ADICIONAL = 'Recurso Adicional';
    public static final String TIPO_MISTO = 'Misto';

    // Solicitacao_Alteracao__c.Nivel_Aprovacao__c (rotulos da picklist)
    public static final String NIVEL_AUTOMATICA = 'Automática';
    public static final String NIVEL_GERENTE = 'Gerente de Contas';
    public static final String NIVEL_DIRETOR = 'Diretor Comercial';
    public static final String NIVEL_FINANCEIRO = 'Financeiro';

    // Item_Contrato__c.Status__c e Tipo__c
    public static final String ITEM_ATIVO = 'Ativo';
    public static final String ITEM_REMOVIDO = 'Removido';
    public static final String ITEM_TIPO_LICENCA = 'Licença';
    public static final String ITEM_TIPO_RECURSO = 'Recurso Adicional';

    // Item_Alteracao__c.Acao__c
    public static final String ACAO_ADICIONAR = 'Adicionar';
    public static final String ACAO_ALTERAR_QTD = 'Alterar Quantidade';
    public static final String ACAO_REMOVER = 'Remover';

    // Historico_Decisao__c.Decisao__c
    public static final String DEC_AUTOMATICA = 'Aprovação Automática';
    public static final String DEC_APROVADA = 'Aprovada';
    public static final String DEC_REJEITADA = 'Rejeitada';
    public static final String DEC_REABERTA = 'Reaberta';
    public static final String DEC_EXPIRADA = 'Expirada';

    // Custom Permissions (nomes de API)
    public static final String PERM_APROVAR_GERENTE = 'Aprovar_Gerente';
    public static final String PERM_APROVAR_DIRETOR = 'Aprovar_Diretor';
    public static final String PERM_APROVAR_FINANCEIRO = 'Aprovar_Financeiro';
    public static final String PERM_APLICAR_ALTERACAO = 'Aplicar_Alteracao';

    // Codigos de erro (estaveis; a UI/testes dependem do codigo, nunca do texto)
    public static final String ERR_CONTRATO_NAO_ATIVO = 'CONTRATO_NAO_ATIVO';
    public static final String ERR_PLANO_INATIVO = 'PLANO_INATIVO';
    public static final String ERR_PRODUTO_DUPLICADO = 'PRODUTO_DUPLICADO';
    public static final String ERR_ACAO_INVALIDA = 'ACAO_INVALIDA';
    public static final String ERR_QUANTIDADE_INVALIDA = 'QUANTIDADE_INVALIDA';
    public static final String ERR_LIMITE_LICENCAS = 'LIMITE_LICENCAS';
    public static final String ERR_VARIACAO_ACIMA_LIMITE = 'VARIACAO_ACIMA_LIMITE';
    public static final String ERR_DATA_OBRIGATORIA = 'DATA_OBRIGATORIA';
    public static final String ERR_DATA_RETROATIVA = 'DATA_RETROATIVA';
    public static final String ERR_DATA_FORA_JANELA = 'DATA_FORA_JANELA';
    public static final String ERR_JUSTIFICATIVA_CURTA = 'JUSTIFICATIVA_CURTA';
    public static final String ERR_MOTIVO_CURTO = 'MOTIVO_CURTO';
    public static final String ERR_TRANSICAO_INVALIDA = 'TRANSICAO_INVALIDA';
    public static final String ERR_STATUS_INICIAL_INVALIDO = 'STATUS_INICIAL_INVALIDO';
    public static final String ERR_ITENS_BLOQUEADOS = 'ITENS_BLOQUEADOS';
    public static final String ERR_CONFIG_AUSENTE = 'CONFIG_AUSENTE';
    public static final String ERR_ALCADA_AUSENTE = 'ALCADA_AUSENTE';
    public static final String ERR_SEM_ACESSO = 'SEM_ACESSO';
    public static final String ERR_SEM_PERMISSAO = 'SEM_PERMISSAO';
    public static final String ERR_BYPASS_INVALIDO = 'BYPASS_INVALIDO';
    public static final String ERR_INESPERADO = 'ERRO_INESPERADO';
}
```

---

## SubscriptionException.cls

```apex
/**
 * @description Excecao de negocio do modulo. A mensagem e SEMPRE amigavel e acionavel
 *              (pode ser exibida ao usuario). O codigo e estavel e serve para logica/testes.
 *              Falhas inesperadas (nao SubscriptionException) devem ir para TechnicalLogger.
 */
public class SubscriptionException extends Exception {
    public String code { get; private set; }

    public SubscriptionException(String code, String message) {
        this(message);
        this.code = code;
    }
}
```

---

## MoneyUtil.cls

```apex
/**
 * @description UNICO ponto de arredondamento monetario do modulo.
 *              Regra: Decimal, 2 casas, HALF_UP. Proibido Double para dinheiro.
 *              Percentuais seguem a mesma regra e sao expressos em pontos percentuais
 *              (18.00 significa 18%), formato esperado por campos Percent do Salesforce.
 */
public with sharing class MoneyUtil {
    public static final Integer SCALE = 2;

    public static Decimal round(Decimal value) {
        return value == null ? null : value.setScale(SCALE, System.RoundingMode.HALF_UP);
    }

    public static Decimal zeroIfNull(Decimal value) {
        return value == null ? 0 : value;
    }

    /** Quantidade x preco, arredondado. Nulos contam como zero. */
    public static Decimal multiply(Decimal quantity, Decimal unitPrice) {
        return round(zeroIfNull(quantity) * zeroIfNull(unitPrice));
    }

    public static Decimal sum(List<Decimal> values) {
        Decimal total = 0;
        if (values != null) {
            for (Decimal value : values) {
                total += zeroIfNull(value);
            }
        }
        return round(total);
    }

    /**
     * Parte sobre base, em pontos percentuais, com UM unico arredondamento (HALF_UP, 2 casas).
     * Retorna NULL quando a base e zero: percentual indefinido (ver ARQUITETURA.md).
     */
    public static Decimal percentOf(Decimal part, Decimal base) {
        Decimal safeBase = zeroIfNull(base);
        if (safeBase == 0) {
            return null;
        }
        return (zeroIfNull(part) * 100).divide(safeBase.abs(), SCALE, System.RoundingMode.HALF_UP);
    }
}
```

---

## TextUtil.cls

```apex
/**
 * @description Utilitarios de texto para validacoes server-side (justificativa, motivo de rejeicao).
 *              Texto formado apenas por espacos (inclusive NBSP e zero-width) e considerado vazio.
 */
public with sharing class TextUtil {
    private static final String INVISIBLE = '[\\s\\u00A0\\u200B\\uFEFF]+';

    public static Boolean isBlank(String value) {
        return value == null || value.replaceAll(INVISIBLE, '').length() == 0;
    }

    /** Tamanho do texto sem espacos nas pontas; zero se for "em branco". */
    public static Integer meaningfulLength(String value) {
        return isBlank(value) ? 0 : value.trim().length();
    }
}
```

---

## CollectionUtil.cls

```apex
/**
 * @description Helpers de colecao usados por Selectors, Handlers e Services (todos bulk-safe).
 */
public with sharing class CollectionUtil {
    public static Boolean isNullOrEmpty(Set<Id> values) {
        return values == null || values.isEmpty();
    }

    public static Boolean isNullOrEmpty(Set<String> values) {
        return values == null || values.isEmpty();
    }

    public static Boolean isNullOrEmpty(List<SObject> values) {
        return values == null || values.isEmpty();
    }

    /** Ids nao nulos de um campo de lookup/Id, sem consultar o banco. */
    public static Set<Id> pluckIds(List<SObject> records, Schema.SObjectField field) {
        Set<Id> result = new Set<Id>();
        if (records == null) {
            return result;
        }
        for (SObject record : records) {
            Object value = record.get(field);
            if (value != null) {
                result.add((Id) value);
            }
        }
        return result;
    }

    public static Set<String> pluckStrings(List<SObject> records, Schema.SObjectField field) {
        Set<String> result = new Set<String>();
        if (records == null) {
            return result;
        }
        for (SObject record : records) {
            Object value = record.get(field);
            if (value != null) {
                result.add(String.valueOf(value));
            }
        }
        return result;
    }
}
```

---

## SubscriptionClock.cls

```apex
/**
 * @description Relogio injetavel: regras de data (retroatividade, janela, efetivacao) ficam
 *              deterministicas em teste sem depender da data real.
 */
public with sharing class SubscriptionClock {
    @TestVisible private static Date todayOverride;

    public static Date today() {
        return todayOverride != null ? todayOverride : Date.today();
    }
}
```

---

## SecurityGuard.cls

```apex
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
```

---

## TechnicalLogger.cls

```apex
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
```

---

## RecursionGuard.cls

```apex
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
```

---

## ControlledWriteContext.cls

```apex
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
```

---

## SubscriptionSettings.cls

```apex
/**
 * @description Value object imutavel com os parametros de negocio (Parametro_Assinatura__mdt).
 *              Permite que Policies e Services sejam testados sem Custom Metadata real.
 */
public with sharing class SubscriptionSettings {
    /** Teto de variacao percentual (modulo), em pontos percentuais. Acima disso a submissao e bloqueada. */
    public final Decimal maxVariationPercent;
    /** Janela maxima, em dias a partir de hoje, para a data de efetivacao. */
    public final Integer effectiveWindowDays;
    public final Integer minJustificationLength;
    public final Integer minRejectionReasonLength;
    /** Nome do Pricebook2 padrao usado quando o contrato nao define Pricebook__c. */
    public final String defaultPricebookName;

    public SubscriptionSettings(
        Decimal maxVariationPercent,
        Integer effectiveWindowDays,
        Integer minJustificationLength,
        Integer minRejectionReasonLength,
        String defaultPricebookName
    ) {
        this.maxVariationPercent = maxVariationPercent;
        this.effectiveWindowDays = effectiveWindowDays;
        this.minJustificationLength = minJustificationLength;
        this.minRejectionReasonLength = minRejectionReasonLength;
        this.defaultPricebookName = defaultPricebookName;
    }
}
```

---

## SubscriptionConfig.cls

```apex
/**
 * @description Ponto unico de leitura de configuracao (Custom Metadata). Usa getAll(), que NAO
 *              consome SOQL, e guarda o resultado em cache estatico (1 leitura por transacao).
 *              Nenhum limite, alcada, responsavel ou Pricebook e codificado em Apex.
 *              Em testes, os overrides permitem injetar configuracao sem depender dos registros do org.
 */
public with sharing class SubscriptionConfig {
    @TestVisible private static SubscriptionSettings settingsOverride;
    @TestVisible private static List<ApprovalMatrixPolicy.Rule> rulesOverride;

    private static SubscriptionSettings cachedSettings;
    private static List<ApprovalMatrixPolicy.Rule> cachedRules;

    public static SubscriptionSettings settings() {
        if (settingsOverride != null) {
            return settingsOverride;
        }
        if (cachedSettings == null) {
            cachedSettings = loadSettings();
        }
        return cachedSettings;
    }

    public static List<ApprovalMatrixPolicy.Rule> approvalRules() {
        if (rulesOverride != null) {
            return rulesOverride;
        }
        if (cachedRules == null) {
            cachedRules = loadRules();
        }
        return cachedRules;
    }

    private static SubscriptionSettings loadSettings() {
        List<Parametro_Assinatura__mdt> active = new List<Parametro_Assinatura__mdt>();
        for (Parametro_Assinatura__mdt record : Parametro_Assinatura__mdt.getAll().values()) {
            if (record.Ativo__c == true) {
                active.add(record);
            }
        }
        if (active.size() != 1) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_CONFIG_AUSENTE,
                'Os parâmetros de assinatura não estão configurados corretamente (é necessário exatamente um registro ativo). Contate o administrador.'
            );
        }
        Parametro_Assinatura__mdt p = active[0];
        if (p.Variacao_Maxima_Percentual__c == null
            || p.Janela_Efetivacao_Dias__c == null
            || p.Tamanho_Minimo_Justificativa__c == null
            || p.Tamanho_Minimo_Motivo_Rejeicao__c == null) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_CONFIG_AUSENTE,
                'Há parâmetros de assinatura obrigatórios sem valor. Contate o administrador.'
            );
        }
        return new SubscriptionSettings(
            p.Variacao_Maxima_Percentual__c,
            p.Janela_Efetivacao_Dias__c.intValue(),
            p.Tamanho_Minimo_Justificativa__c.intValue(),
            p.Tamanho_Minimo_Motivo_Rejeicao__c.intValue(),
            p.Pricebook_Padrao_Nome__c
        );
    }

    private static List<ApprovalMatrixPolicy.Rule> loadRules() {
        List<ApprovalMatrixPolicy.Rule> rules = new List<ApprovalMatrixPolicy.Rule>();
        for (Matriz_Alcada__mdt record : Matriz_Alcada__mdt.getAll().values()) {
            if (record.Ativo__c != true) {
                continue;
            }
            try {
                rules.add(
                    new ApprovalMatrixPolicy.Rule(
                        record.DeveloperName,
                        ApprovalMatrixPolicy.directionFromCode(record.Direcao__c),
                        ApprovalMatrixPolicy.criterionFromCode(record.Criterio__c),
                        record.Limite_Superior__c,
                        ApprovalMatrixPolicy.levelFromCode(record.Nivel__c),
                        record.Responsavel_Tipo__c,
                        record.Responsavel_Nome__c
                    )
                );
            } catch (Exception invalidRecord) {
                throw new SubscriptionException(
                    SubscriptionConstants.ERR_ALCADA_AUSENTE,
                    'A matriz de alçada possui um registro inválido (' + record.DeveloperName + '). Contate o administrador.'
                );
            }
        }
        if (rules.isEmpty()) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_ALCADA_AUSENTE,
                'A matriz de alçada não está configurada. Contate o administrador.'
            );
        }
        return rules;
    }
}
```

---

## MrrCalculator.cls

```apex
/**
 * @description Dominio puro (sem SOQL/DML) para calculo de MRR e variacoes.
 *              MRR do item = Quantidade x Preco Unitario Mensal (arredondado, MoneyUtil).
 *              MRR do contrato = soma dos MRR dos itens ATIVOS.
 *              Variacao absoluta = proposto - base (positivo = aumento).
 *              Variacao percentual = absoluta / base, em pontos percentuais; NULL quando a base e zero
 *              e a variacao nao e zero (percentual indefinido); 0.00 quando ambos sao zero.
 */
public with sharing class MrrCalculator {

    public class Variation {
        public Decimal baseMrr { get; set; }
        public Decimal proposedMrr { get; set; }
        public Decimal absolute { get; set; }
        public Decimal percent { get; set; }
    }

    public static Decimal itemMrr(Decimal quantity, Decimal unitPrice) {
        return MoneyUtil.multiply(quantity, unitPrice);
    }

    /** Delta de uma linha: MRR(quantidade nova) - MRR(quantidade atual), ao mesmo preco unitario. */
    public static Decimal lineDelta(Decimal currentQuantity, Decimal newQuantity, Decimal unitPrice) {
        return MoneyUtil.round(itemMrr(newQuantity, unitPrice) - itemMrr(currentQuantity, unitPrice));
    }

    public static Decimal contractMrr(List<Decimal> activeItemMrrs) {
        return MoneyUtil.sum(activeItemMrrs);
    }

    public static Decimal proposedMrr(Decimal baseMrr, Decimal totalDelta) {
        return MoneyUtil.round(MoneyUtil.zeroIfNull(baseMrr) + MoneyUtil.zeroIfNull(totalDelta));
    }

    public static Variation compute(Decimal baseMrr, Decimal proposedMrr) {
        Variation result = new Variation();
        result.baseMrr = MoneyUtil.round(MoneyUtil.zeroIfNull(baseMrr));
        result.proposedMrr = MoneyUtil.round(MoneyUtil.zeroIfNull(proposedMrr));
        result.absolute = MoneyUtil.round(result.proposedMrr - result.baseMrr);
        if (result.absolute == 0) {
            result.percent = 0.00;
        } else {
            result.percent = MoneyUtil.percentOf(result.absolute, result.baseMrr);
        }
        return result;
    }
}
```

---

## ApprovalMatrixPolicy.cls

```apex
/**
 * @description Politica PURA (sem DML/SOQL) da matriz de alcada. As faixas NUNCA ficam no codigo:
 *              chegam como lista de Rule, montada por SubscriptionConfig a partir de Matriz_Alcada__mdt.
 *
 *              Algoritmo:
 *              1) direcao = REDUCAO se a variacao absoluta < 0, senao AUMENTO (zero conta como AUMENTO).
 *              2) para cada criterio (PERCENTUAL, ABSOLUTO) usa-se o MODULO da variacao e a PRIMEIRA
 *                 faixa (ordenada por limite superior asc., faixa aberta por ultimo) em que valor <= limite
 *                 (limites inclusivos). Criterio sem regras para a direcao nao se aplica (ex.: reducao nao
 *                 tem criterio absoluto). Percentual indefinido (base zero) nao se aplica.
 *              3) nivel exigido = o MAIOR entre os dois criterios.
 *              4) invariante de negocio: REDUCAO nunca e Automatica (piso = Gerente de Contas).
 *              5) teto Parametro_Assinatura__mdt.Variacao_Maxima_Percentual__c: acima dele -> BLOQUEADA,
 *                 mesmo que a matriz fosse mais permissiva.
 *              6) valor que excede todas as faixas limitadas -> BLOQUEADA (falha segura).
 */
public with sharing class ApprovalMatrixPolicy {

    /** Ordem das constantes = severidade crescente (ordinal() e usado para comparar). */
    public enum Level { AUTOMATICA, GERENTE, DIRETOR, FINANCEIRO, BLOQUEADA }
    public enum Direction { AUMENTO, REDUCAO }
    public enum Criterion { PERCENTUAL, ABSOLUTO }

    public class Rule implements Comparable {
        public String developerName;
        public Direction direction;
        public Criterion criterion;
        /** Limite superior INCLUSIVO; null = faixa aberta (sem limite). */
        public Decimal upperLimit;
        public Level level;
        public String responsibleType;
        public String responsibleName;

        public Rule(
            String developerName,
            Direction direction,
            Criterion criterion,
            Decimal upperLimit,
            Level level,
            String responsibleType,
            String responsibleName
        ) {
            this.developerName = developerName;
            this.direction = direction;
            this.criterion = criterion;
            this.upperLimit = upperLimit;
            this.level = level;
            this.responsibleType = responsibleType;
            this.responsibleName = responsibleName;
        }

        public Integer compareTo(Object other) {
            Rule o = (Rule) other;
            if (upperLimit == null && o.upperLimit == null) {
                return 0;
            }
            if (upperLimit == null) {
                return 1;
            }
            if (o.upperLimit == null) {
                return -1;
            }
            if (upperLimit == o.upperLimit) {
                return 0;
            }
            return upperLimit < o.upperLimit ? -1 : 1;
        }
    }

    public class Result {
        public Level level;
        public Level levelByPercent;
        public Level levelByAbsolute;
        public Direction direction;
        public MrrCalculator.Variation variation;
        public Boolean blocked = false;
        public String blockCode;
        public String blockMessage;
        /** GRUPO | FILA | PAPEL (valor de Matriz_Alcada__mdt.Responsavel_Tipo__c); null se automatica/bloqueada. */
        public String responsibleType;
        /** DeveloperName do grupo, fila ou papel responsavel. */
        public String responsibleName;

        public Boolean requiresHumanApproval() {
            return !blocked && level != Level.AUTOMATICA;
        }

        /** Rotulo da picklist Solicitacao_Alteracao__c.Nivel_Aprovacao__c (null quando bloqueada). */
        public String levelLabel() {
            return ApprovalMatrixPolicy.labelOf(level);
        }
    }

    public static Result classify(
        Decimal baseMrr,
        Decimal proposedMrr,
        List<Rule> rules,
        Decimal maxVariationPercent
    ) {
        MrrCalculator.Variation variation = MrrCalculator.compute(baseMrr, proposedMrr);
        Direction direction = variation.absolute < 0 ? Direction.REDUCAO : Direction.AUMENTO;
        Decimal percentMagnitude = variation.percent == null ? null : Math.abs(variation.percent);
        Decimal absoluteMagnitude = Math.abs(variation.absolute);

        Level byPercent = levelFor(direction, Criterion.PERCENTUAL, percentMagnitude, rules);
        Level byAbsolute = levelFor(direction, Criterion.ABSOLUTO, absoluteMagnitude, rules);
        if (byPercent == null && byAbsolute == null) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_ALCADA_AUSENTE,
                'A matriz de alçada não está configurada para esta variação. Contate o administrador.'
            );
        }

        Level required = maxOf(byPercent, byAbsolute);
        if (direction == Direction.REDUCAO && required == Level.AUTOMATICA) {
            required = Level.GERENTE;
        }

        Result result = new Result();
        result.variation = variation;
        result.direction = direction;
        result.levelByPercent = byPercent;
        result.levelByAbsolute = byAbsolute;

        Boolean aboveCeiling = maxVariationPercent != null
            && percentMagnitude != null
            && percentMagnitude > maxVariationPercent;
        if (aboveCeiling || required == Level.BLOQUEADA) {
            result.level = Level.BLOQUEADA;
            result.blocked = true;
            result.blockCode = SubscriptionConstants.ERR_VARIACAO_ACIMA_LIMITE;
            result.blockMessage = 'A variação de MRR'
                + (variation.percent == null ? '' : ' (' + variation.percent + '%)')
                + ' excede o limite permitido para alteração. Abra um novo contrato ou conduza uma negociação específica.';
            return result;
        }

        result.level = required;
        Rule responsible = responsibleFor(required, direction, rules);
        if (responsible != null) {
            result.responsibleType = responsible.responsibleType;
            result.responsibleName = responsible.responsibleName;
        }
        return result;
    }

    private static Level levelFor(Direction direction, Criterion criterion, Decimal magnitude, List<Rule> rules) {
        List<Rule> candidates = new List<Rule>();
        if (rules != null) {
            for (Rule rule : rules) {
                if (rule.direction == direction && rule.criterion == criterion) {
                    candidates.add(rule);
                }
            }
        }
        if (candidates.isEmpty() || magnitude == null) {
            return null;
        }
        candidates.sort();
        for (Rule rule : candidates) {
            if (rule.upperLimit == null || magnitude <= rule.upperLimit) {
                return rule.level;
            }
        }
        return Level.BLOQUEADA;
    }

    private static Level maxOf(Level a, Level b) {
        if (a == null) {
            return b;
        }
        if (b == null) {
            return a;
        }
        return a.ordinal() >= b.ordinal() ? a : b;
    }

    /** Prefere a regra da mesma direcao; senao qualquer regra do nivel com responsavel preenchido. */
    private static Rule responsibleFor(Level level, Direction direction, List<Rule> rules) {
        Rule fallback = null;
        if (rules == null) {
            return null;
        }
        for (Rule rule : rules) {
            if (rule.level != level || TextUtil.isBlank(rule.responsibleName)) {
                continue;
            }
            if (rule.direction == direction) {
                return rule;
            }
            if (fallback == null) {
                fallback = rule;
            }
        }
        return fallback;
    }

    // ---- Conversoes (codigos do metadado <-> enum <-> rotulo da picklist) ----

    public static String labelOf(Level level) {
        if (level == Level.AUTOMATICA) {
            return SubscriptionConstants.NIVEL_AUTOMATICA;
        }
        if (level == Level.GERENTE) {
            return SubscriptionConstants.NIVEL_GERENTE;
        }
        if (level == Level.DIRETOR) {
            return SubscriptionConstants.NIVEL_DIRETOR;
        }
        if (level == Level.FINANCEIRO) {
            return SubscriptionConstants.NIVEL_FINANCEIRO;
        }
        return null;
    }

    /** Aceita o rotulo da picklist; devolve null se nao reconhecido. */
    public static Level levelFromLabel(String label) {
        if (label == SubscriptionConstants.NIVEL_AUTOMATICA) {
            return Level.AUTOMATICA;
        }
        if (label == SubscriptionConstants.NIVEL_GERENTE) {
            return Level.GERENTE;
        }
        if (label == SubscriptionConstants.NIVEL_DIRETOR) {
            return Level.DIRETOR;
        }
        if (label == SubscriptionConstants.NIVEL_FINANCEIRO) {
            return Level.FINANCEIRO;
        }
        return null;
    }

    /** Nome da Custom Permission que habilita decidir o nivel; null para Automatica/Bloqueada. */
    public static String customPermissionOf(Level level) {
        if (level == Level.GERENTE) {
            return SubscriptionConstants.PERM_APROVAR_GERENTE;
        }
        if (level == Level.DIRETOR) {
            return SubscriptionConstants.PERM_APROVAR_DIRETOR;
        }
        if (level == Level.FINANCEIRO) {
            return SubscriptionConstants.PERM_APROVAR_FINANCEIRO;
        }
        return null;
    }

    public static Level levelFromCode(String code) {
        return Level.valueOf(code);
    }

    public static Direction directionFromCode(String code) {
        return Direction.valueOf(code);
    }

    public static Criterion criterionFromCode(String code) {
        return Criterion.valueOf(code);
    }
}
```

---

## RequestStateMachine.cls

```apex
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
}
```

---

## ChangeRequestPolicy.cls

```apex
/**
 * @description Regras puras de validacao de uma solicitacao de alteracao (sem DML/SOQL).
 *              Cada metodo lanca SubscriptionException com codigo estavel e mensagem amigavel.
 *              Chamadas pelo Service (US-01) e reaproveitaveis pelo Handler (US-02), garantindo
 *              as MESMAS regras para LWC, API, Data Loader e Execute Anonymous.
 */
public with sharing class ChangeRequestPolicy {

    public static void requireActiveContract(String contractStatus) {
        if (contractStatus != SubscriptionConstants.CTR_ATIVO) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_CONTRATO_NAO_ATIVO,
                'Somente contratos com status Ativo podem ser alterados (status atual: '
                    + (String.isBlank(contractStatus) ? 'não informado' : contractStatus) + ').'
            );
        }
    }

    public static void requireActivePlan(Boolean planIsActive) {
        if (planIsActive != true) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_PLANO_INATIVO,
                'O plano proposto está inativo. Escolha um plano ativo do catálogo.'
            );
        }
    }

    /** Data obrigatoria, nao retroativa e dentro da janela (dias) configurada em metadado. */
    public static void requireEffectiveDate(Date effectiveDate, Date today, Integer windowDays) {
        if (effectiveDate == null) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_DATA_OBRIGATORIA,
                'Informe a data de efetivação da alteração.'
            );
        }
        if (effectiveDate < today) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_DATA_RETROATIVA,
                'A data de efetivação não pode ser anterior a hoje.'
            );
        }
        if (windowDays != null && effectiveDate > today.addDays(windowDays)) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_DATA_FORA_JANELA,
                'A data de efetivação não pode ultrapassar ' + windowDays + ' dias a partir de hoje.'
            );
        }
    }

    public static void requireNoDuplicateProducts(List<Id> productIds) {
        Set<Id> seen = new Set<Id>();
        if (productIds == null) {
            return;
        }
        for (Id productId : productIds) {
            if (productId != null && !seen.add(productId)) {
                throw new SubscriptionException(
                    SubscriptionConstants.ERR_PRODUTO_DUPLICADO,
                    'O mesmo produto não pode aparecer mais de uma vez na solicitação.'
                );
            }
        }
    }

    /**
     * Quantidade inteira. Adicionar/Alterar: >= 1 (Alterar tambem precisa mudar o valor).
     * Remover: quantidade nova obrigatoriamente zero.
     */
    public static void requireValidQuantity(String action, Decimal currentQuantity, Decimal newQuantity) {
        if (action != SubscriptionConstants.ACAO_ADICIONAR
            && action != SubscriptionConstants.ACAO_ALTERAR_QTD
            && action != SubscriptionConstants.ACAO_REMOVER) {
            throw new SubscriptionException(SubscriptionConstants.ERR_ACAO_INVALIDA, 'Ação inválida para o item da solicitação.');
        }
        if (newQuantity == null || newQuantity < 0 || (newQuantity - newQuantity.setScale(0, System.RoundingMode.DOWN)) > 0) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_QUANTIDADE_INVALIDA,
                'A quantidade deve ser um número inteiro positivo.'
            );
        }
        if (action == SubscriptionConstants.ACAO_REMOVER) {
            if (newQuantity != 0) {
                throw new SubscriptionException(
                    SubscriptionConstants.ERR_QUANTIDADE_INVALIDA,
                    'Para remover um item, a quantidade nova deve ser zero.'
                );
            }
            return;
        }
        if (newQuantity < 1) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_QUANTIDADE_INVALIDA,
                'A quantidade deve ser de pelo menos 1. Para retirar o item, use a ação Remover.'
            );
        }
        if (action == SubscriptionConstants.ACAO_ALTERAR_QTD && currentQuantity != null && newQuantity == currentQuantity) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_QUANTIDADE_INVALIDA,
                'A nova quantidade é igual à atual; não há alteração a registrar.'
            );
        }
    }

    /** Total de licencas resultante dentro dos limites do plano (min/max nulos = sem limite). */
    public static void requireWithinLicenseLimits(Decimal totalLicenses, Decimal minLicenses, Decimal maxLicenses) {
        Decimal total = MoneyUtil.zeroIfNull(totalLicenses);
        if (minLicenses != null && total < minLicenses) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_LIMITE_LICENCAS,
                'O plano exige no mínimo ' + minLicenses + ' licença(s); a solicitação resulta em ' + total + '.'
            );
        }
        if (maxLicenses != null && total > maxLicenses) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_LIMITE_LICENCAS,
                'O plano permite no máximo ' + maxLicenses + ' licença(s); a solicitação resulta em ' + total + '.'
            );
        }
    }

    public static void requireJustification(String justification, Integer minLength) {
        if (TextUtil.meaningfulLength(justification) < MoneyUtil.zeroIfNull(minLength)) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_JUSTIFICATIVA_CURTA,
                'Informe uma justificativa com pelo menos ' + minLength + ' caracteres.'
            );
        }
    }

    public static void requireRejectionReason(String reason, Integer minLength) {
        Integer required = minLength == null || minLength < 1 ? 1 : minLength;
        if (TextUtil.meaningfulLength(reason) < required) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_MOTIVO_CURTO,
                'Informe o motivo da rejeição com pelo menos ' + required + ' caracteres (apenas espaços não é válido).'
            );
        }
    }

    public static void requireNotBlocked(ApprovalMatrixPolicy.Result classification) {
        if (classification != null && classification.blocked) {
            throw new SubscriptionException(classification.blockCode, classification.blockMessage);
        }
    }

    /** Controle otimista: versao do contrato mudou desde a simulacao? (nulo conta como zero) */
    public static Boolean isVersionStale(Decimal contractVersion, Decimal baseVersion) {
        return MoneyUtil.zeroIfNull(contractVersion) != MoneyUtil.zeroIfNull(baseVersion);
    }
}
```

---

## ContractSelector.cls

```apex
/**
 * @description Selector de Contrato_Assinatura__c. TODA consulta SOQL do objeto vive aqui.
 *              WITH USER_MODE: aplica sharing + CRUD + FLS do usuario em execucao.
 *              Consultas FOR UPDATE: sem ORDER BY (a plataforma nao permite) e so com campos do proprio
 *              objeto (menor superficie de lock e leitura). A ordem de lock do modulo e sempre:
 *              Solicitacao -> Contrato, para evitar deadlock entre aplicacoes concorrentes.
 */
public with sharing class ContractSelector {

    public List<Contrato_Assinatura__c> selectByIds(Set<Id> contractIds) {
        if (CollectionUtil.isNullOrEmpty(contractIds)) {
            return new List<Contrato_Assinatura__c>();
        }
        return [
            SELECT
                Id, Name, Account__c, Plano_Atual__c, Plano_Atual__r.Nivel__c, Plano_Atual__r.Codigo__c,
                Status__c, Periodicidade__c, Data_Inicio__c, Data_Fim__c, Pricebook__c,
                MRR_Atual__c, Versao__c, Gerente_Conta__c
            FROM Contrato_Assinatura__c
            WHERE Id IN :contractIds
            WITH USER_MODE
        ];
    }

    public Map<Id, Contrato_Assinatura__c> mapByIds(Set<Id> contractIds) {
        return new Map<Id, Contrato_Assinatura__c>(selectByIds(contractIds));
    }

    /** Bloqueio pessimista (FOR UPDATE). Revalidar o estado SEMPRE depois do lock. */
    public List<Contrato_Assinatura__c> selectByIdsForUpdate(Set<Id> contractIds) {
        if (CollectionUtil.isNullOrEmpty(contractIds)) {
            return new List<Contrato_Assinatura__c>();
        }
        return [
            SELECT
                Id, Name, Account__c, Plano_Atual__c, Status__c, Pricebook__c, MRR_Atual__c, Versao__c
            FROM Contrato_Assinatura__c
            WHERE Id IN :contractIds
            WITH USER_MODE
            FOR UPDATE
        ];
    }
}
```

---

## ContractItemSelector.cls

```apex
/**
 * @description Selector de Item_Contrato__c (WITH USER_MODE).
 */
public with sharing class ContractItemSelector {

    public List<Item_Contrato__c> selectByIds(Set<Id> itemIds) {
        if (CollectionUtil.isNullOrEmpty(itemIds)) {
            return new List<Item_Contrato__c>();
        }
        return [
            SELECT Id, Contrato__c, Produto__c, Produto__r.Name, Tipo__c, Quantidade__c,
                   Preco_Unitario_Mensal__c, MRR_Item__c, Status__c
            FROM Item_Contrato__c
            WHERE Id IN :itemIds
            WITH USER_MODE
        ];
    }

    /** Itens ATIVOS dos contratos informados (1 consulta para o lote inteiro). */
    public List<Item_Contrato__c> selectActiveByContractIds(Set<Id> contractIds) {
        if (CollectionUtil.isNullOrEmpty(contractIds)) {
            return new List<Item_Contrato__c>();
        }
        String activeStatus = SubscriptionConstants.ITEM_ATIVO;
        return [
            SELECT Id, Contrato__c, Produto__c, Produto__r.Name, Tipo__c, Quantidade__c,
                   Preco_Unitario_Mensal__c, MRR_Item__c, Status__c
            FROM Item_Contrato__c
            WHERE Contrato__c IN :contractIds AND Status__c = :activeStatus
            WITH USER_MODE
        ];
    }

    /** Todos os itens (ativos e removidos) dos contratos; usado na aplicacao para reconciliar produtos. */
    public List<Item_Contrato__c> selectAllByContractIds(Set<Id> contractIds) {
        if (CollectionUtil.isNullOrEmpty(contractIds)) {
            return new List<Item_Contrato__c>();
        }
        return [
            SELECT Id, Contrato__c, Produto__c, Tipo__c, Quantidade__c,
                   Preco_Unitario_Mensal__c, MRR_Item__c, Status__c
            FROM Item_Contrato__c
            WHERE Contrato__c IN :contractIds
            WITH USER_MODE
        ];
    }

    /**
     * Soma do MRR dos itens ATIVOS por contrato, agregada no banco (1 SOQL, sem trazer linhas).
     * Contratos sem itens ativos nao aparecem no mapa (tratar como zero).
     */
    public Map<Id, Decimal> sumActiveMrrByContractIds(Set<Id> contractIds) {
        Map<Id, Decimal> totals = new Map<Id, Decimal>();
        if (CollectionUtil.isNullOrEmpty(contractIds)) {
            return totals;
        }
        String activeStatus = SubscriptionConstants.ITEM_ATIVO;
        for (AggregateResult row : [
            SELECT Contrato__c contractId, SUM(MRR_Item__c) total
            FROM Item_Contrato__c
            WHERE Contrato__c IN :contractIds AND Status__c = :activeStatus
            WITH USER_MODE
            GROUP BY Contrato__c
        ]) {
            totals.put((Id) row.get('contractId'), (Decimal) row.get('total'));
        }
        return totals;
    }
}
```

---

## PlanSelector.cls

```apex
/**
 * @description Selector do catalogo Plano_Assinatura__c (WITH USER_MODE).
 */
public with sharing class PlanSelector {

    public List<Plano_Assinatura__c> selectActive() {
        return [
            SELECT Id, Name, Codigo__c, Nivel__c, Produto__c, Preco_Base_Mensal__c,
                   Licencas_Minimas__c, Licencas_Maximas__c, Ativo__c
            FROM Plano_Assinatura__c
            WHERE Ativo__c = true
            WITH USER_MODE
            ORDER BY Nivel__c ASC, Name ASC
            LIMIT 500
        ];
    }

    /** Inclui planos inativos: a validacao "plano proposto inativo" precisa enxerga-los. */
    public List<Plano_Assinatura__c> selectByIds(Set<Id> planIds) {
        if (CollectionUtil.isNullOrEmpty(planIds)) {
            return new List<Plano_Assinatura__c>();
        }
        return [
            SELECT Id, Name, Codigo__c, Nivel__c, Produto__c, Preco_Base_Mensal__c,
                   Licencas_Minimas__c, Licencas_Maximas__c, Ativo__c
            FROM Plano_Assinatura__c
            WHERE Id IN :planIds
            WITH USER_MODE
        ];
    }

    public Map<Id, Plano_Assinatura__c> mapByIds(Set<Id> planIds) {
        return new Map<Id, Plano_Assinatura__c>(selectByIds(planIds));
    }

    public List<Plano_Assinatura__c> selectByCodes(Set<String> codes) {
        if (CollectionUtil.isNullOrEmpty(codes)) {
            return new List<Plano_Assinatura__c>();
        }
        return [
            SELECT Id, Name, Codigo__c, Nivel__c, Produto__c, Preco_Base_Mensal__c,
                   Licencas_Minimas__c, Licencas_Maximas__c, Ativo__c
            FROM Plano_Assinatura__c
            WHERE Codigo__c IN :codes
            WITH USER_MODE
        ];
    }
}
```

---

## RequestSelector.cls

```apex
/**
 * @description Selector de Solicitacao_Alteracao__c (WITH USER_MODE).
 *              "Solicitante" = CreatedById (o Owner pode mudar e nao representa quem pediu).
 */
public with sharing class RequestSelector {

    public List<Solicitacao_Alteracao__c> selectByIds(Set<Id> requestIds) {
        if (CollectionUtil.isNullOrEmpty(requestIds)) {
            return new List<Solicitacao_Alteracao__c>();
        }
        return [
            SELECT
                Id, Name, Contrato__c, Tipo__c, Plano_Proposto__c, Status__c, Nivel_Aprovacao__c,
                MRR_Base__c, MRR_Proposto__c, Variacao_Absoluta__c, Variacao_Percentual__c,
                Data_Efetivacao__c, Versao_Contrato_Base__c, Ciclo_Aprovacao__c, Chave_Idempotencia__c,
                Justificativa__c, Aprovador__c, Data_Decisao__c, Motivo_Rejeicao__c,
                CreatedById, CreatedDate, LastModifiedDate
            FROM Solicitacao_Alteracao__c
            WHERE Id IN :requestIds
            WITH USER_MODE
        ];
    }

    public Map<Id, Solicitacao_Alteracao__c> mapByIds(Set<Id> requestIds) {
        return new Map<Id, Solicitacao_Alteracao__c>(selectByIds(requestIds));
    }

    /** Bloqueio pessimista para decisao/aplicacao. Revalidar status e ciclo DEPOIS do lock. */
    public List<Solicitacao_Alteracao__c> selectByIdsForUpdate(Set<Id> requestIds) {
        if (CollectionUtil.isNullOrEmpty(requestIds)) {
            return new List<Solicitacao_Alteracao__c>();
        }
        return [
            SELECT
                Id, Name, Contrato__c, Tipo__c, Plano_Proposto__c, Status__c, Nivel_Aprovacao__c,
                MRR_Base__c, MRR_Proposto__c, Data_Efetivacao__c, Versao_Contrato_Base__c,
                Ciclo_Aprovacao__c, CreatedById
            FROM Solicitacao_Alteracao__c
            WHERE Id IN :requestIds
            WITH USER_MODE
            FOR UPDATE
        ];
    }

    /**
     * Solicitacoes PENDENTES dos contratos, excluindo os Ids informados (os do proprio lote).
     * Base da regra "no maximo uma Pendente por contrato" contra registros ja persistidos.
     */
    public List<Solicitacao_Alteracao__c> selectPendingByContractIds(Set<Id> contractIds, Set<Id> excludeRequestIds) {
        if (CollectionUtil.isNullOrEmpty(contractIds)) {
            return new List<Solicitacao_Alteracao__c>();
        }
        Set<Id> excluded = excludeRequestIds == null ? new Set<Id>() : excludeRequestIds;
        String pending = SubscriptionConstants.REQ_PENDENTE;
        return [
            SELECT Id, Name, Contrato__c, Status__c, Ciclo_Aprovacao__c
            FROM Solicitacao_Alteracao__c
            WHERE Contrato__c IN :contractIds AND Status__c = :pending AND Id NOT IN :excluded
            WITH USER_MODE
        ];
    }

    /** Idempotencia do simulador: mesma Chave_Idempotencia__c devolve a solicitacao ja criada. */
    public List<Solicitacao_Alteracao__c> selectByIdempotencyKeys(Set<String> keys) {
        if (CollectionUtil.isNullOrEmpty(keys)) {
            return new List<Solicitacao_Alteracao__c>();
        }
        return [
            SELECT Id, Name, Contrato__c, Status__c, MRR_Base__c, MRR_Proposto__c,
                   Versao_Contrato_Base__c, Chave_Idempotencia__c
            FROM Solicitacao_Alteracao__c
            WHERE Chave_Idempotencia__c IN :keys
            WITH USER_MODE
        ];
    }
}
```

---

## RequestItemSelector.cls

```apex
/**
 * @description Selector de Item_Alteracao__c (WITH USER_MODE).
 */
public with sharing class RequestItemSelector {

    public List<Item_Alteracao__c> selectByIds(Set<Id> itemIds) {
        if (CollectionUtil.isNullOrEmpty(itemIds)) {
            return new List<Item_Alteracao__c>();
        }
        return [
            SELECT Id, Solicitacao__c, Item_Contrato__c, Produto__c, Acao__c,
                   Quantidade_Atual__c, Quantidade_Nova__c, Preco_Unitario_Mensal__c, Delta_MRR__c
            FROM Item_Alteracao__c
            WHERE Id IN :itemIds
            WITH USER_MODE
        ];
    }

    public List<Item_Alteracao__c> selectByRequestIds(Set<Id> requestIds) {
        if (CollectionUtil.isNullOrEmpty(requestIds)) {
            return new List<Item_Alteracao__c>();
        }
        return [
            SELECT Id, Solicitacao__c, Item_Contrato__c, Produto__c, Produto__r.Name, Acao__c,
                   Quantidade_Atual__c, Quantidade_Nova__c, Preco_Unitario_Mensal__c, Delta_MRR__c
            FROM Item_Alteracao__c
            WHERE Solicitacao__c IN :requestIds
            WITH USER_MODE
        ];
    }

    /**
     * Soma de Delta_MRR__c por solicitacao, agregada no banco: 1 SOQL para qualquer numero de pais
     * (200 solicitacoes = 1 consulta). Solicitacoes sem itens nao aparecem (tratar como zero).
     * Usada pelo recalculo APOS o DML dos itens, entao ja reflete insert/update/delete/undelete.
     */
    public Map<Id, Decimal> sumDeltaByRequestIds(Set<Id> requestIds) {
        Map<Id, Decimal> totals = new Map<Id, Decimal>();
        if (CollectionUtil.isNullOrEmpty(requestIds)) {
            return totals;
        }
        for (AggregateResult row : [
            SELECT Solicitacao__c requestId, SUM(Delta_MRR__c) total
            FROM Item_Alteracao__c
            WHERE Solicitacao__c IN :requestIds
            WITH USER_MODE
            GROUP BY Solicitacao__c
        ]) {
            totals.put((Id) row.get('requestId'), (Decimal) row.get('total'));
        }
        return totals;
    }
}
```

---

## DecisionHistorySelector.cls

```apex
/**
 * @description Selector de Historico_Decisao__c (auditoria, somente insercao). WITH USER_MODE.
 */
public with sharing class DecisionHistorySelector {

    public List<Historico_Decisao__c> selectByRequestIds(Set<Id> requestIds) {
        if (CollectionUtil.isNullOrEmpty(requestIds)) {
            return new List<Historico_Decisao__c>();
        }
        return [
            SELECT Id, Solicitacao__c, Ciclo__c, Decisao__c, Nivel__c, Usuario__c, Data_Hora__c, Motivo__c
            FROM Historico_Decisao__c
            WHERE Solicitacao__c IN :requestIds
            WITH USER_MODE
            ORDER BY Data_Hora__c ASC
        ];
    }
}
```

---

## AdditiveSelector.cls

```apex
/**
 * @description Selector de Aditivo_Contrato__c (WITH USER_MODE).
 *              Chave_Unica__c = "SolicitacaoId-Ciclo" e a base da idempotencia da aplicacao.
 */
public with sharing class AdditiveSelector {

    public List<Aditivo_Contrato__c> selectByUniqueKeys(Set<String> uniqueKeys) {
        if (CollectionUtil.isNullOrEmpty(uniqueKeys)) {
            return new List<Aditivo_Contrato__c>();
        }
        return [
            SELECT Id, Name, Contrato__c, Solicitacao__c, Chave_Unica__c, Versao_Resultante__c,
                   MRR_Anterior__c, MRR_Novo__c, Data_Efetivacao__c, Order__c
            FROM Aditivo_Contrato__c
            WHERE Chave_Unica__c IN :uniqueKeys
            WITH USER_MODE
        ];
    }

    public List<Aditivo_Contrato__c> selectByRequestIds(Set<Id> requestIds) {
        if (CollectionUtil.isNullOrEmpty(requestIds)) {
            return new List<Aditivo_Contrato__c>();
        }
        return [
            SELECT Id, Name, Contrato__c, Solicitacao__c, Chave_Unica__c, Versao_Resultante__c,
                   MRR_Anterior__c, MRR_Novo__c, Data_Efetivacao__c, Order__c
            FROM Aditivo_Contrato__c
            WHERE Solicitacao__c IN :requestIds
            WITH USER_MODE
        ];
    }

    /** Chave canonica da idempotencia: nunca montar a string em outro lugar. */
    public static String uniqueKey(Id requestId, Decimal cycle) {
        return String.valueOf(requestId) + '-' + String.valueOf(MoneyUtil.zeroIfNull(cycle).intValue());
    }
}
```

---

## PricebookSelector.cls

```apex
/**
 * @description Selector de Pricebook2 / PricebookEntry (WITH USER_MODE).
 *              LIMITACAO CONHECIDA: em orgs com multi-moeda, PricebookEntry existe uma vez por moeda e
 *              seria preciso filtrar por CurrencyIsoCode (campo inexistente em orgs single-currency, por
 *              isso nao referenciado aqui). Registrado em DECISOES_E_LIMITACOES.md.
 */
public with sharing class PricebookSelector {

    public List<Pricebook2> selectActiveByName(String pricebookName) {
        if (String.isBlank(pricebookName)) {
            return new List<Pricebook2>();
        }
        return [
            SELECT Id, Name, IsActive, IsStandard
            FROM Pricebook2
            WHERE Name = :pricebookName AND IsActive = true
            WITH USER_MODE
            LIMIT 1
        ];
    }

    public List<Pricebook2> selectByIds(Set<Id> pricebookIds) {
        if (CollectionUtil.isNullOrEmpty(pricebookIds)) {
            return new List<Pricebook2>();
        }
        return [
            SELECT Id, Name, IsActive, IsStandard
            FROM Pricebook2
            WHERE Id IN :pricebookIds
            WITH USER_MODE
        ];
    }

    /** Entradas de preco ATIVAS do pricebook para os produtos informados (1 consulta para o lote). */
    public List<PricebookEntry> selectActiveEntries(Id pricebookId, Set<Id> productIds) {
        if (pricebookId == null || CollectionUtil.isNullOrEmpty(productIds)) {
            return new List<PricebookEntry>();
        }
        return [
            SELECT Id, Pricebook2Id, Product2Id, UnitPrice, IsActive
            FROM PricebookEntry
            WHERE Pricebook2Id = :pricebookId AND Product2Id IN :productIds AND IsActive = true
            WITH USER_MODE
        ];
    }
}
```
