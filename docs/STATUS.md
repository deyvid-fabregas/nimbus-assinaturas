# Status do projeto

**Atualização de 06/11/2026:** o projeto foi implantado com sucesso na org `nimbus-org` (195 componentes, mais 19 da etapa 3D). A etapa 3D (LWC, Jest, FlexiPages, app) foi entregue; Jest com 28 testes e 98,29% de cobertura. Existem 58 testes Apex aprovados (cobertura da execução 86%), mas 31 classes ainda estão abaixo de 90%. Pendentes: cobertura ≥ 90% por classe, validação visual da FlexiPage, 6 Flow Tests, Code Analyzer e revisão de segurança completa. Detalhes em [CONTINUAR_DAQUI.md](CONTINUAR_DAQUI.md), [evidencias/cobertura-apex.md](evidencias/cobertura-apex.md), [SEGURANCA.md](SEGURANCA.md) e [RELATORIO_ERROS_PRE_DEPLOY.md](RELATORIO_ERROS_PRE_DEPLOY.md). As tabelas abaixo são do histórico anterior e podem estar desatualizadas.

As Partes 1, 1b, 2 e as entregas 3A, 3B e 3C foram concluídas. Nada foi compilado nem implantado em uma org; a validação até aqui foi estática (XML bem formado, assinaturas e campos cruzados com o projeto, actions dos Flows conferidas contra o Apex). O primeiro deploy ainda pode revelar incompatibilidades de Apex, Flow, permissões ou metadados (riscos conhecidos em [DECISOES_E_LIMITACOES.md](DECISOES_E_LIMITACOES.md)).

## Andamento

| Parte | Escopo                                                                 | Situação                 |
|-------|------------------------------------------------------------------------|--------------------------|
| 1     | Arquitetura base, domínio/política, Selectors e utilitários            | Entregue                 |
| 1b    | Modelo de dados, CMDT, Custom Permissions e Permission Sets            | Entregue; sem deploy     |
| 2     | US-01 e US-02: simulação, rascunho, itens, snapshot, envio e recálculo | Entregue; sem compilação |
| 3A    | Gate de status, roteamento, decisão e reabertura (US-03/US-04)         | Entregue; sem compilação |
| 3B    | Aplicação transacional (US-06)                                         | Entregue; sem compilação |
| 3C    | Flow de roteamento, Screen Flows e Apex de apoio (resumo, aplicação)   | Entregue; sem deploy     |
| 3D    | LWCs (resumo e simulador), Controller do simulador, Jest, FlexiPages, layouts, tabs e app | Pendente |
| 3E    | Documentos finais (matriz de rastreabilidade, code review, roteiro de demo, testes e evidências) e pacote da Parte 3 | Pendente |
| 4     | Testes Apex/Jest/Flow e validação integrada                            | Pendente                 |

## Parte 3A — entregue

- `StatusTransitionContext` e gate no `SolicitacaoAlteracaoHandler`: decisões, aplicação, expiração e reabertura exigem escopo autorizado por solicitação e status de destino. Edição direta de status por API/Data Loader é recusada; execução de Apex arbitrário continua sendo um limite conhecido.
- `ApprovalRoutingService` e actions invocáveis: classificação por matriz, incremento do ciclo, Task deduplicada por ciclo e aprovação automática. Falha de roteamento é registrada e compensada para Rascunho.
- `SubscriptionDecisionService` e actions: decisão em lote, Custom Permission, designação, segregação de funções, lock, validação do ciclo e reabertura com histórico.
- `AuthorizedSystemWriter`, `DesignationSelector` e campo `Task.Chave_Deduplicacao__c`.

## Parte 3B — entregue

- `SubscriptionApplyService` aplica uma solicitação aprovada por chamada com lock Solicitação → Contrato, revalidação e controle de versão. Versão desatualizada expira a solicitação com histórico.
- Savepoint e rollback preservam a atomicidade; falhas técnicas são registradas após o rollback, deixando a solicitação aprovada e reprocessável.
- `ContractApplyWriter` isola as escritas de itens do contrato, versão/plano, Aditivo, Order e OrderItems. Status permanece em `USER_MODE` sob o gate de transição.
- Lock, versão otimista e chave única do Aditivo protegem contra aplicação duplicada. OrderItems usam quantidade assinada, o que requer quantidade negativa habilitada no org.
- Controller/DTO de aplicação adicionados. O scratch definition habilita quantidade negativa; isso ainda não foi verificado em uma org.

## Parte 3C — entregue

- **Record-Triggered Flow** `Roteamento_Alcada_Solicitacao` (after-save): dispara somente quando `Status__c` muda para Pendente, chama `ApprovalRoutingAction` e, no Fault Path, `ApprovalRoutingFaultAction` (registra o log técnico e desfaz o envio). Não recalcula valores e não contém IDs fixos.
- **Screen Flows:** `Enviar_Solicitacao_Aprovacao`, `Decidir_Solicitacao_Alteracao`, `Reabrir_Solicitacao_Alteracao` e `Aplicar_Alteracao_Aprovada`. Todos usam `recordId` (Quick Action) e delegam as regras ao servidor; abrir o Flow por URL não contorna permissão, designação, segregação, ciclo ou estado.
- **Apex de apoio:** `SubscriptionRequestSummaryService/Action/DTO` (resumo e indicadores de disponibilidade, HTML escapado), `SubscriptionApplyAction`, `TaskSelector` e `RequestSelector.selectSummaryById`.
- **Permission Sets:** class access às novas actions e `flowAccesses` por perfil.
- **Flow Tests declarativos:** não foram gerados. O esquema do metadado não foi verificado em org e a lógica do roteamento está em Apex, então o roteiro dos 6 casos está definido para criação no Flow Builder (e para os testes Apex que disparam o Flow por DML) na Parte 4/3E.

## Próxima etapa: implantação controlada em uma nova org

1. Definir se o destino será uma Scratch Org ou uma sandbox e autorizar um alias Salesforce explicitamente.
2. Conferir Orders e quantidade negativa; criar/confirmar os grupos públicos e associar os aprovadores.
3. Executar o preview, implantar os metadados (incluindo os Flows) e resolver incompatibilidades reportadas pelo primeiro deploy.
4. Atribuir Permission Sets por perfil e só então executar a carga de demonstração, se ela for desejada.
5. Validar manualmente os Flows (roteamento e Screen Flows) e, na Parte 4, executar os testes Apex e de Flow.

Consulte [IMPLANTACAO_NOVA_ORG.md](IMPLANTACAO_NOVA_ORG.md) para os comandos e pré-requisitos. Sem LWC, FlexiPages e app (3D), os Screen Flows ainda não aparecem como botões na página: são acionados por Quick Action criada manualmente ou pela URL do Flow. Não usar em produção até concluir as partes pendentes, os testes e a revisão de segurança/configuração.

## Ainda pendente e riscos de validação

- 3D, 3E e os testes/validação da Parte 4, conforme o andamento acima.
- Validar em org o acesso a `Group`, `GroupMember` e `UserRole` com `WITH USER_MODE`; `getPopulatedFieldsAsMap()` nos writers; `FOR UPDATE` combinado com `WITH USER_MODE`; quantidade negativa; FLS de Task; configuração dos campos de Order/OrderItem; **saídas das actions invocáveis nos Screen Flows** (parâmetros de saída por `@InvocableVariable`); e o comportamento do Flow after-save que atualiza o próprio registro via Apex.
- A `Task.OwnerId` recebe um usuário ativo membro do responsável; a decisão é autorizada pela designação e Custom Permission, não pelo dono da Task.
- A designação considera membros diretos de grupos/filas ou usuários do papel; grupos aninhados e papéis subordinados não são expandidos.

Detalhes das escolhas, limitações e cenários de validação em [DECISOES_E_LIMITACOES.md](DECISOES_E_LIMITACOES.md), [ARQUITETURA.md](ARQUITETURA.md) e [MODELO_DE_DADOS.md](MODELO_DE_DADOS.md).
