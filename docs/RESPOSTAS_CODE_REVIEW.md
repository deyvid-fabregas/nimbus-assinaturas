# Respostas às perguntas de code review (PDF, seção 11)

Cada resposta aponta para as classes, Flows e metadados que implementam a decisão. Os termos "Service", "Handler" e "Selector" seguem [ARQUITETURA.md](ARQUITETURA.md).

## 1. Por que a validação em JavaScript e na FlexiPage não impede alterações por API, e quais camadas garantem as mesmas regras?

JavaScript e FlexiPage só controlam o que o usuário **vê**. Quem chama a API REST, o Data Loader ou um Apex anônimo não passa por eles. Por isso a interface nunca é a fonte da regra. As camadas que valem são:

| Camada | Regra garantida |
|---|---|
| Triggers (`SubscriptionRequestTrigger`, `SubscriptionItemChangeTrigger`, `SubscriptionContractItemTrigger`) | Snapshot do contrato, preço e MRR calculados no servidor, campos congelados fora de Rascunho, itens de contrato só mudam pelo fluxo de aplicação |
| `RequestStateMachine` + `SolicitacaoAlteracaoHandler` | Transições válidas. Decidir, aplicar, expirar e reabrir exigem `StatusTransitionContext` aberto por um Service autorizado |
| `RequestSubmissionService` | Revalida data, justificativa, itens, totais, limites de licença e bloqueio da matriz no envio |
| `SubscriptionDecisionService` | Custom Permission do nível, designação (grupo/fila/papel), segregação de funções, ciclo e estado |
| `SubscriptionApplyService` | Estado, versão, idempotência e atomicidade da aplicação |
| Permission Sets e FLS/CRUD | Acesso a objetos, campos, classes e Flows |

Abrir um Screen Flow por URL também não contorna nada: o Flow só chama Apex, e o Apex valida de novo.

## 2. Como a Trigger bulkificada identifica todos os pais afetados por insert, update, delete e undelete, e qual o custo para 200 registros?

`ItemAlteracaoHandler` despacha por `Trigger.operationType` e coleta o `Solicitacao__c` pai de `Trigger.new` **e** de `Trigger.old`, conforme a operação. Assim, insert e undelete usam o novo, delete usa o antigo, e update usa os dois (cobre troca de pai/reparenting). Os pais viram um `Set<Id>`.

O recálculo é **derivado do banco** (soma agregada), nunca incremental, e por isso serve igual para as quatro operações:

- `RequestRecalculationService`: 2 SOQL (pais + agregado de deltas) e 1 DML, para qualquer N até 200.
- `ContractMrrService`: 2 SOQL e no máximo 1 DML por lote.

Sem SOQL ou DML em loop. Os custos estão documentados nos comentários das classes e exercitados nos testes em massa.

## 3. Por que recursão por variável estática booleana é perigosa, e qual estratégia foi adotada?

Um `static Boolean jaRodei` bloqueia operações legítimas na mesma transação (segundo lote do mesmo DML, update vindo de um Flow, registros diferentes) e, se for resetado no lugar errado, deixa a recursão passar. Também esconde bugs, porque o segundo processamento simplesmente não acontece.

`RecursionGuard` controla por **conjunto de Ids + fingerprint do estado**, por escopo:

- `enter(escopo, ids)` devolve só os Ids que **não** estão em processamento com o mesmo fingerprint.
- Se o estado mudou (fingerprint diferente), o reprocessamento é aceito.
- `exit()` roda em `finally` e libera os Ids.
- O limite de 16 níveis de Trigger da plataforma continua como rede de segurança.

Além disso, os recálculos são idempotentes (derivados do banco), então reprocessar nunca soma duas vezes.

## 4. Por que o Record-Triggered Flow não deve replicar os cálculos da Trigger, e como o ownership foi documentado?

Dois automatismos escrevendo o mesmo campo geram corrida e resultados dependentes de ordem de execução. Cada campo calculado tem **um único escritor**:

| Campos | Escritor único |
|---|---|
| `MRR_Item__c`, `MRR_Atual__c` | `ItemContratoHandler` / `ContractMrrService` |
| `MRR_Proposto__c`, `Variacao_Absoluta__c`, `Variacao_Percentual__c` | `RequestRecalculationService` |
| `MRR_Base__c`, `Versao_Contrato_Base__c` | `RequestSnapshotService` (before insert) |
| `Status__c`, `Ciclo_Aprovacao__c`, Task de aprovação | `ApprovalRoutingService` (chamado pelo Flow) e `SubscriptionDecisionService` |

O Flow `Roteamento_Alcada_Solicitacao` dispara somente quando `Status__c` **muda** para Pendente, apenas **lê** os valores financeiros e delega a classificação ao Apex. O ownership está em [MODELO_DE_DADOS.md](MODELO_DE_DADOS.md), [ARQUITETURA.md](ARQUITETURA.md) e nos cabeçalhos de cada classe.

## 5. Como garantir que reprocessar o Flow ou reenviar a solicitação não gere nova Task, e como o ciclo resolve o reenvio legítimo?

- Cada Task tem a chave `APR|<SolicitacaoId>|<Ciclo>` (`Task.Chave_Deduplicacao__c`, `ApprovalRoutingService.taskKey`).
- Se já existe Task **aberta** do ciclo corrente, ou a solicitação não está Pendente, o roteamento não faz nada.
- Reenvio legítimo (Rejeitada → Rascunho → Pendente): o novo ciclo é `Ciclo_Aprovacao__c + 1`, o que gera uma chave nova e permite uma nova Task. As Tasks abertas de ciclos anteriores são encerradas.
- O Flow só dispara quando o `Status__c` muda para Pendente, então um update qualquer não reroteia.

## 6. Como a alçada de quem decide é validada independentemente da FlexiPage e do Screen Flow, e como se impede decidir sobre tela desatualizada?

Tudo em `SubscriptionDecisionService`, no servidor:

1. Custom Permission do nível exigido (`Aprovar_Gerente`, `Aprovar_Diretor`, `Aprovar_Financeiro`).
2. Designação: o usuário precisa ser membro do grupo/fila/papel configurado na `Matriz_Alcada__mdt` para o nível.
3. Segregação: quem criou a solicitação (`CreatedById`) não decide. Foi comprovado na org: o solicitante vê "Quem criou a solicitação não pode decidi-la".
4. Estado Pendente **e ciclo igual ao ciclo exibido na tela**. Se a tela está desatualizada (outro usuário já decidiu, ou houve reenvio), a decisão é recusada.
5. Rejeição exige motivo com tamanho mínimo.

Um lock `FOR UPDATE` e a revalidação depois do lock tratam duplo clique e concorrência: a segunda chamada recebe `SOLICITACAO_JA_DECIDIDA`, sem nova transição nem novo histórico. A transição de status só passa pelo gate da Trigger se o Service abriu o `StatusTransitionContext`.

## 7. Como os dados permanecem íntegros quando a terceira linha do Order falha, e por que o log sobrevive ao rollback?

`SubscriptionApplyService.apply` abre um `Savepoint` e faz toda a escrita (itens, plano, versão, Aditivo, Order e OrderItems) em uma única transação. Qualquer erro executa `Database.rollback`, e nada fica pela metade. Há um teste que força falha real de DML em um `OrderItem` e confere que tudo voltou.

O log sobrevive porque `TechnicalLogger.persist` é chamado **depois** do rollback e **sem propagar exceção**. O DML do log ocorre após o ponto de reversão e a transação termina com sucesso. Se a exceção escapasse do `@AuraEnabled`, a transação inteira (inclusive o log) seria revertida, por isso Controllers e Actions sempre capturam e devolvem um resultado amigável. A solicitação continua Aprovada e pode ser reprocessada.

## 8. Como o desenho impede dois Aditivos e dois Orders sob requisições simultâneas? Por que mais de uma barreira?

| Barreira | O que cobre | Limitação se fosse a única |
|---|---|---|
| Lock pessimista (`FOR UPDATE`, ordem Solicitação → Contrato) | Serializa chamadas concorrentes da mesma solicitação/contrato | Não detecta outro aditivo aplicado **depois da simulação**; não protege quem não usa o lock |
| Versionamento otimista (`Contrato.Versao__c` × `Versao_Contrato_Base__c`) | Detecta que o contrato mudou desde a simulação; a solicitação vira Expirada | Não impede duplicidade entre duas chamadas simultâneas com a mesma versão |
| Unicidade (`Aditivo_Contrato__c.Chave_Unica__c` = `SolicitacaoId-Ciclo`, External ID único) | Última barreira, vale mesmo sem lock. Em `DUPLICATE_VALUE` devolve o resultado existente | Só detecta no momento do insert, já tendo gasto processamento |

Cada uma cobre uma falha diferente, e o estado é revalidado **depois** do lock. A combinação garante que, mesmo que uma barreira falhe, as outras evitam a duplicidade.

## 9. Que limites de plataforma tornariam a solução frágil com milhares de itens, e como evoluir?

Hoje, para 1 solicitação com até 200 itens, a aplicação gasta cerca de 12 SOQL e 10 DML, sem operações em loop. Com milhares de itens:

- **DML e linhas por transação** (10.000 linhas de DML): itens, OrderItems e histórico estourariam.
- **Heap e CPU**: montar todas as mudanças em memória e recalcular agregados fica caro.
- **Locks em registro pai**: o lock do contrato por mais tempo causa contenção (`UNABLE_TO_LOCK_ROW`) com outras operações.
- **SOQL com muitas linhas**: o agregado de MRR e a leitura de itens.

Evolução proposta: processar em **Queueable encadeado ou Batch** por blocos de itens, com a solicitação em estado "Em aplicação" e idempotência por bloco (a chave única já existe); reduzir leituras com agregados SOQL em vez de listas completas; manter o lock do contrato só na fase de confirmação; e notificar o resultado por Platform Event.

## 10. Decisões sobre `with sharing`, `USER_MODE` e `stripInaccessible`; onde o modo sistema é inevitável?

- Todas as classes de negócio são `with sharing`, e as consultas e DMLs expostos usam `USER_MODE` (CRUD/FLS e compartilhamento do usuário).
- `SecurityGuard` usa `stripInaccessible` onde é preciso devolver dados parciais ao usuário em vez de falhar.
- O **modo sistema** é restrito a três classes, cada uma com justificativa no cabeçalho:
  - `CalculatedFieldWriter` (`without sharing`): grava campos calculados protegidos (somente leitura para todos), como um roll-up summary.
  - `AuthorizedSystemWriter`: histórico de decisão e encerramento de Task, efeitos de uma operação **já autorizada** pelo Service.
  - `ContractApplyWriter`: escritas de itens, contrato, Aditivo e Order da aplicação, sob `ControlledWriteContext`.
- `TechnicalLogger` grava o log em modo sistema de propósito: o usuário que sofreu a falha pode não ter permissão de criar `Log_Tecnico__c`, e a falha não pode se perder. Grava apenas log, nunca dado de negócio.

O sharing do modelo é Public Read/Write e o acesso é por Permission Sets (ver [DECISOES_E_LIMITACOES.md](DECISOES_E_LIMITACOES.md)); em produção seria endurecido.

## 11. O que mudaria com novos níveis de aprovação, novas moedas ou pro rata?

- **Novos níveis:** são dados, não código. Uma nova linha na `Matriz_Alcada__mdt`, um grupo público e uma Custom Permission. Só `RequestStateMachine` e as constantes precisariam de ajuste se o nível alterasse a ordem de aprovação. A etapa sequencial (bônus do PDF) exigiria estado intermediário e histórico por etapa em `Historico_Decisao__c`.
- **Novas moedas:** `MoneyUtil` concentra o arredondamento (HALF_UP), mas hoje assume uma única moeda. Seria preciso habilitar Multi-Currency, converter pela taxa de câmbio antes de comparar com os limites da matriz, e decidir a moeda de referência da alçada.
- **Pro rata:** seria uma nova política (`ProRataPolicy`) usada em `ContractApplyWriter` para precificar os OrderItems do período corrente, com regra de arredondamento documentada. O `ChangePlanner` não mudaria, porque a simulação trabalha com MRR mensal.

Essas mudanças ficam localizadas porque as regras estão em Policies e Services pequenos, a matriz é configuração e o escritor de cada campo é único.
