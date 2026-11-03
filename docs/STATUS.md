# Status do projeto

Nada foi compilado nem executado em org até aqui. A verificação foi estática (assinaturas contra a Parte 1, chaves/parênteses balanceados, ausência de SOQL/DML em loop, XMLs bem formados, campos e valores de picklist coerentes com `SubscriptionConstants`). Espere ajustes no primeiro deploy.

## Andamento

| Parte | Escopo | Situação |
|---|---|---|
| 1 | Arquitetura base, domínio/política, Selectors, utilitários | Entregue |
| 2 | US-01 (simulação/rascunho) e US-02 (itens, snapshot, envio, recálculo) | Entregue, sem compilar |
| 1b | Modelo de dados, CMDT, Custom Permissions, Permission Sets | Entregue, sem deploy |
| 3 | US-03 a US-06 (decisão, roteamento, aplicação), Invocables, Flows, Controllers, LWC | Pendente |
| 4 | Testes | Pendente |

## Parte 2 — entregue

- **US-01:** `SubscriptionChangeRequestDTO`, `SubscriptionChangeResultDTO`, `SubscriptionChangeService` (`simulate`, `saveDraft`; idempotente pela chave, com Savepoint, edição só de Rascunho), domínio puro (`ChangeContext`, `ItemResolutionPolicy`, `ChangePlanner`), `ChangeContextLoader`, `PricebookResolver`.
- **US-02:** triggers `SubscriptionItemChangeTrigger`, `SubscriptionRequestTrigger`, `SubscriptionContractItemTrigger` com Handlers; `RequestItemService` (congela itens fora de Rascunho, preço e delta no servidor, barra produto duplicado); `RequestSnapshotService`; `RequestSubmissionService` (lock `FOR UPDATE`, uma Pendente por contrato); `RequestRecalculationService` (2 SOQL e 1 DML para 200 itens, CA01 ≤ 5 / ≤ 3); `ContractMrrService`; `CalculatedFieldWriter`.
- **Edições:** `SubscriptionConstants` (+12 códigos de erro), `PricebookSelector` e `RequestItemSelector` (+1 método cada).

## Parte 1b — entregue

- 8 objetos: `Plano_Assinatura__c`, `Contrato_Assinatura__c`, `Item_Contrato__c`, `Solicitacao_Alteracao__c`, `Item_Alteracao__c`, `Historico_Decisao__c`, `Aditivo_Contrato__c`, `Log_Tecnico__c`. `Item_Alteracao__c.Solicitacao__c` com reparenting habilitado; `Solicitacao_Alteracao__c` com atividades habilitadas.
- CMDT `Parametro_Assinatura__mdt` e `Matriz_Alcada__mdt` (13 linhas) com grupos públicos `Aprovadores_Gerentes`, `Aprovadores_Diretores`, `Aprovadores_Financeiro`.
- 4 Custom Permissions e 3 Permission Sets: `Assinatura_Vendedor`, `Assinatura_Aprovador`, `Assinatura_Administrador`.
- Apoio: `config/project-scratch-def.json`, `.forceignore`, `scripts/apex/seed-catalog.apex`.

## Decisões fora do plano original

Detalhes em [DECISOES_E_LIMITACOES.md](DECISOES_E_LIMITACOES.md).

- `SubscriptionContractItemTrigger` criada (exigida pela US-02; também mantém `MRR_Atual__c`).
- `PricebookResolver` antecipado da Parte 3 (preço dos recursos adicionais da US-01).
- Snapshot (`MRR_Base__c`, `Versao_Contrato_Base__c`) gravado pela Trigger de insert, não pelo Service, para que nenhum canal informe a base e reduza a alçada.
- `CalculatedFieldWriter` é `without sharing`, único da Parte 2; grava só campos calculados protegidos.
- Bloqueio de itens de contrato vale também para carga inicial; seeds precisam abrir o `ControlledWriteContext`.
- Sharing: objetos em Public Read/Write; controle real por Permission Sets.
- Um único `Assinatura_Aprovador`; o nível é diferenciado pela participação no grupo da matriz.
- `Aplicar_Alteracao` fica em `Assinatura_Vendedor` (US-06).

## Pendências

- Page layouts, tabs, app e FlexiPages.
- Acesso às classes Apex expostas.
- Campo de deduplicação da Task.
- Escritas da aplicação no `Assinatura_Vendedor` (Aditivo, Order, `Versao__c`), conforme o `SubscriptionApplyService`.
- Controller e LWC do simulador (US-01): o Controller deve capturar a exceção e devolver `SubscriptionChangeResultDTO.failure(...)`; se escapar do `@AuraEnabled`, o log técnico é revertido.
- Ação de envio para aprovação (Rascunho → Pendente), na Parte 3.

## Lacuna de segurança (tratar na Parte 3)

A máquina de estados permite `Pendente → Aprovada/Rejeitada` a qualquer usuário com edição de `Status__c`. Só o `SubscriptionDecisionService` checa permissão, designação e segregação de funções; edição direta por API as contorna. Proposta: escopo controlado nos moldes do `ControlledWriteContext` para as transições de decisão e aplicação.

## Próximo passo

Validar deploy em Scratch Org, depois Parte 3 (US-03 a US-06).
