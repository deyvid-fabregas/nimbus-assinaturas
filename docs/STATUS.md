# Status do projeto

As Partes 1, 1b, 2 e as entregas 3A e 3B foram concluídas. Nada foi compilado nem implantado em uma org; a validação até aqui foi estática. O primeiro deploy ainda pode revelar incompatibilidades de Apex, permissões ou metadados (riscos conhecidos em [DECISOES_E_LIMITACOES.md](DECISOES_E_LIMITACOES.md)).

## Andamento

| Parte | Escopo | Situação |
|---|---|---|
| 1 | Arquitetura base, domínio/política, Selectors e utilitários | Entregue |
| 1b | Modelo de dados, CMDT, Custom Permissions e Permission Sets | Entregue; sem deploy |
| 2 | US-01 e US-02: simulação, rascunho, itens, snapshot, envio e recálculo | Entregue; sem compilação |
| 3A | Gate de status, roteamento, decisão e reabertura (US-03/US-04) | Entregue; sem compilação |
| 3B | Aplicação transacional (US-06) | Entregue; sem compilação |
| 3C | Record-Triggered Flow, Screen Flows e Flow Tests | Pendente |
| 3D | LWCs, Controller do simulador, Jest, FlexiPages, layouts, tabs e app | Pendente |
| 3E | Documentos finais e pacote completo da Parte 3 | Pendente |
| 4 | Testes e validação integrada | Pendente |

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

## Ainda pendente e riscos de validação

- 3C, 3D, 3E e os testes/validação da Parte 4, conforme o andamento acima.
- Validar em org o acesso a `Group`, `GroupMember` e `UserRole` com `WITH USER_MODE`; `getPopulatedFieldsAsMap()` nos writers; `FOR UPDATE` combinado com `WITH USER_MODE`; quantidade negativa; FLS de Task; e configuração dos campos de Order/OrderItem.
- A `Task.OwnerId` recebe um usuário ativo membro do responsável; a decisão é autorizada pela designação e Custom Permission, não pelo dono da Task.
- A designação considera membros diretos de grupos/filas ou usuários do papel; grupos aninhados e papéis subordinados não são expandidos.

Detalhes das escolhas, limitações e cenários de validação em [DECISOES_E_LIMITACOES.md](DECISOES_E_LIMITACOES.md), [ARQUITETURA.md](ARQUITETURA.md) e [MODELO_DE_DADOS.md](MODELO_DE_DADOS.md).
