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

    // ---- Parte 2 (US-01 / US-02) ----
    public static final String ERR_NAO_ENCONTRADO = 'REGISTRO_NAO_ENCONTRADO';
    public static final String ERR_ENTRADA_INVALIDA = 'ENTRADA_INVALIDA';
    public static final String ERR_SEM_ALTERACAO = 'SEM_ALTERACAO';
    public static final String ERR_ITEM_NAO_ENCONTRADO = 'ITEM_NAO_ENCONTRADO';
    public static final String ERR_PRECO_AUSENTE = 'PRECO_AUSENTE';
    public static final String ERR_PLANO_INVALIDO = 'PLANO_INVALIDO';
    public static final String ERR_CHAVE_IDEMPOTENCIA = 'CHAVE_IDEMPOTENCIA_OBRIGATORIA';
    public static final String ERR_SOLICITACAO_NAO_EDITAVEL = 'SOLICITACAO_NAO_EDITAVEL';
    public static final String ERR_VERSAO_DESATUALIZADA = 'VERSAO_DESATUALIZADA';
    public static final String ERR_PENDENTE_EXISTENTE = 'PENDENTE_EXISTENTE';
    public static final String ERR_TOTAIS_DESATUALIZADOS = 'TOTAIS_DESATUALIZADOS';
    public static final String ERR_CAMPO_PROTEGIDO = 'CAMPO_PROTEGIDO';
}
