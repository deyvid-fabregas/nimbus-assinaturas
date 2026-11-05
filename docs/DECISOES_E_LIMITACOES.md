# Decisões de projeto e limitações conhecidas

> Este arquivo não estava no zip enviado. As decisões e limitações da **Parte 1** continuam em
> `ARQUITETURA.md` (seções 7 e 8); aqui ficam as da **Parte 2** e as de partes seguintes.

## Parte 2 — decisões

1. **Snapshot da solicitação é da Trigger, não do Service.** `MRR_Base__c` e `Versao_Contrato_Base__c` são
   sobrescritos no `before insert` a partir do contrato. Motivo: a base alimenta o percentual; se qualquer canal
   pudesse informá-la, bastaria uma base maior para cair numa alçada mais baixa. Consequência: um rascunho
   cujo contrato mudou de versão não pode ser re-simulado em cima do mesmo registro (o Service recusa com
   `VERSAO_DESATUALIZADA`; crie nova simulação).
2. **Troca de plano vira linhas** (premissa 1 de `ARQUITETURA.md`): remove a licença do plano atual e adiciona a
   do plano proposto (produto do plano, `Preco_Base_Mensal__c`, mesma quantidade ou a pedida via “Alterar
   Quantidade” na licença atual). Exige produtos distintos e níveis diferentes entre os planos.
3. **Origem do preço** (`ItemResolutionPolicy`): item existente → preço contratado; produto do plano efetivo →
   `Preco_Base_Mensal__c`; demais produtos → `PricebookEntry` do pricebook do contrato (ou do padrão por nome
   em `Parametro_Assinatura__mdt`). O cliente nunca informa preço; a Trigger recalcula mesmo que o Service já tenha calculado.
4. **Mesmas regras em todos os canais.** O Service simula e valida com `ChangePlanner`; as Triggers revalidam e
   resolvem os valores. No envio (Rascunho → Pendente) `RequestSubmissionService` reaplica data, justificativa,
   itens, coerência dos totais, consistência da troca de plano, limites de licença e bloqueio da matriz.
5. **Uma Pendente por contrato:** lock `FOR UPDATE` dos contratos antes de ler as pendentes (serializa envios
   concorrentes) + decisão em lote (primeira solicitação válida ganha; as demais recebem `addError`).
6. **Campos congelados** fora de Rascunho: `Tipo__c`, `Plano_Proposto__c`, `Data_Efetivacao__c`, totais.
   `Justificativa__c` permanece editável porque US-03 CA03 salva uma Pendente com justificativa nova.
7. **`CalculatedFieldWriter` é `without sharing` e em modo sistema** — única exceção da Parte 2: grava só
   campos calculados protegidos (somente leitura para todos os Permission Sets), como um roll-up summary.
8. **Itens de contrato:** qualquer escrita sem `ControlledWriteContext` aberto é bloqueada, inclusive
   inserção na carga inicial. Scripts de seed (`scripts/apex`) devem abrir o escopo com justificativa
   (regra de análise estática: `ControlledWriteContext.open` só em `SubscriptionApplyService`, testes e seeds).
9. **Tipo da solicitação** (`Tipo__c`): derivado no Service (upgrade/downgrade pelo nível; licença vs. recurso
   pelo produto do plano efetivo); é informativo e não entra na matriz de alçada.
10. **Log técnico:** o Service faz rollback ao `Savepoint`, grava o log e lança `SubscriptionException`. O
    Controller (Parte 3) deve capturar e devolver `SubscriptionChangeResultDTO.failure(...)`: se a exceção
    escapar do `@AuraEnabled`, a transação inteira (inclusive o log) é revertida.

## Parte 2 — limitações conhecidas

- **Não compilado nem executado:** o projeto não tem os metadados de objetos/campos/CMDT/Permission Sets
  (Parte 1b) e não houve org disponível; a verificação foi estática (assinaturas e balanceamento).
- Exige **reparenting habilitado** no master-detail `Item_Alteracao__c.Solicitacao__c` (troca de pai, US-02 CA02).
- Exclusão de contrato com itens é bloqueada (cascata passa pelo bloqueio de `Item_Contrato__c`).
- `PricebookResolver` não valida se o `Pricebook2` do contrato está ativo (apenas a entrada de preço).
- Lock `FOR UPDATE` em lote de 200 contratos pode gerar contenção; a ordem de aquisição é da plataforma.
- Solicitações criadas por API com `Plano_Proposto__c` e linhas inconsistentes só são barradas **no envio**.
- Planos de mesmo nível ou com o mesmo produto são recusados na troca de plano.
- `Tipo__c` pode ser informado por quem tem FLS de edição (campo informativo).

## Parte 1b — decisões

1. **Sharing Public Read/Write + Permission Sets** como controle de acesso (ver `MODELO_DE_DADOS.md`); simplifica a demonstração
   com vendedor, aprovador e usuário sem permissão. Endurecer em produção.
2. **Aprovadores por grupo público** na matriz (`Responsavel_Tipo__c = GRUPO`); fila e papel já são aceitos pelo metadado.
3. **Um único `Assinatura_Aprovador`** com as três Custom Permissions; o nível é diferenciado pelo grupo.
4. `Aplicar_Alteracao` fica em `Assinatura_Vendedor` (persona “gerente de contas” da US-06).

## Lacuna identificada (a tratar na Parte 3)

- **Autoridade de decisão na Trigger:** a máquina de estados permite `Pendente → Aprovada/Rejeitada` para qualquer usuário com
  edição de `Status__c`; hoje só o `SubscriptionDecisionService` (Parte 3) checa Custom Permission, designação e
  segregação. Para “independente da UI/API”, as transições de decisão e de aplicação devem exigir um escopo controlado
  (como o `ControlledWriteContext`) aberto apenas pelo Service/Invocable, ou o `Status__c` deixar de ser editável fora dele.

---

# Parte 3 — Entrega 3A (autorização de status, roteamento e decisão)

## Fechamento da lacuna do `Status__c` (US-02/US-04/US-06)

**Mecanismo:** `StatusTransitionContext` (escopo por *Id da solicitação + status de destino*, com contador e `close()` em
`finally`) + gate no `SolicitacaoAlteracaoHandler`. A Trigger só aceita transições “gated” — destino Aprovada, Rejeitada,
Aplicada, Expirada, ou Rejeitada → Rascunho (reabertura) — se, **na mesma transação**, um service autorizado abriu o escopo
para aquele registro **e** aquele destino. A lista vive em `RequestStateMachine.requiresAuthorizedService` (fonte única).
Rascunho → Pendente (validado por `RequestSubmissionService`) e Pendente → Cancelada continuam abertos ao usuário.

**Por que este desenho:** FLS não distingue transições (quem edita `Status__c` para enviar também poderia aprovar);
validação só no Service deixa a API aberta; um booleano global autorizaria registros e destinos não pretendidos. O escopo
é por registro e por destino, e vale também para Data Loader/Bulk API/`Database.update(allOrNone=false)` (erro por registro).

**Quem pode abrir:** `SubscriptionDecisionService`, `ApprovalRoutingService`, `SubscriptionApplyService` (3B) e testes.
Regra de análise estática: `StatusTransitionContext.open` / `ControlledWriteContext.open` fora dessas classes é violação.

**Como um usuário malicioso tentaria burlar e por que falha**

| Tentativa | Resultado |
|---|---|
| `Database.update` / API / Data Loader com `Status__c = 'Aprovada'` | Trigger recusa (`GATE_MESSAGE`), por registro |
| Aprovar a própria solicitação via Screen Flow ou URL direta do Flow | `SubscriptionDecisionService` recusa (`SEGREGACAO_FUNCOES`) |
| Aprovador de outro nível (tem a Custom Permission, não está no grupo) | Recusado (`NAO_DESIGNADO`) |
| Reabrir direto (Rejeitada → Rascunho) sem histórico | Recusado pelo gate |
| Forjar `Nivel_Aprovacao__c`/`Ciclo_Aprovacao__c` | Campos somente leitura nos Permission Sets; ciclo divergente é recusado na decisão |
| Abrir o escopo por Apex anônimo | **Possível** para quem tem Author Apex/Execute Anonymous (limite conhecido, igual ao `ControlledWriteContext`; mitigar restringindo essa permissão) |

## Decisões novas (requerem sua confirmação)

1. **Aresta de compensação Pendente → Rascunho**, fora da tabela do usuário e aceita **somente** com escopo aberto. Usada quando o
   roteamento falha, para não deixar a solicitação Pendente sem rota (“sem estado inconsistente” da US-03). Alternativa:
   manter Pendente + reprocessamento manual (descartada por deixar estado visível sem aprovador).
2. **Dono da Task = um usuário ativo membro do responsável** (menor nome; deterministico), porque `Task.OwnerId` não aceita
   grupo/papel. A autoridade de decidir é a **designação + Custom Permission**, não o dono da Task.
3. **Designação = membro direto** de grupo público/fila ou usuário com o papel (sem grupos aninhados nem “papel e subordinados”).
4. **Segunda decisão (duplo clique):** `success=false`, código `SOLICITACAO_JA_DECIDIDA`, `alreadyResolved=true`, mensagem amigável;
   nenhuma transição nem histórico novo.
5. **Reabertura:** autorizada ao solicitante ou a quem tem a Custom Permission do nível da solicitação.
6. **`AuthorizedSystemWriter` (`without sharing`)**: histórico (somente inserção), Task de roteamento e campos de roteamento são
   efeitos de operações **já autorizadas**; cada método copia só campos da lista branca. Junto com `CalculatedFieldWriter` é a
   única exceção de modo sistema (grep `without sharing` deve listar apenas as duas).
7. **Chave de deduplicação da Task:** `Task.Chave_Deduplicacao__c = APR|<SolicitacaoId>|<Ciclo>` (texto 80, sem unicidade: Task não a
   suporta); a deduplicação é por consulta sem sharing + ciclo; reprocessar o Flow sobre solicitação já roteada é no-op.

## Limitações (3A)

- Nada foi implantado em org. Pontos de maior risco no primeiro `sf project deploy start`: `Group`/`GroupMember`/`UserRole` em
  `WITH USER_MODE` (ver 3A no relatório), `Task.Chave_Deduplicacao__c` sem FLS em Permission Set, `getPopulatedFieldsAsMap()`
  em `AuthorizedSystemWriter`, e a combinação `FOR UPDATE` + `WITH USER_MODE` já usada desde a Parte 1.
- O Record-Triggered Flow que chama `ApprovalRoutingAction`, o Screen Flow de decisão, a aplicação (US-06), FlexiPages, LWC,
  layouts, tabs e app **ainda não existem** (entregas 3B–3D).

---

# Parte 3 — Entrega 3B (aplicação transacional, US-06)

## Escritas da aplicação: USER_MODE × escrita isolada (caso a caso)

| Escrita | Modo | Justificativa |
|---|---|---|
| `Solicitacao_Alteracao__c.Status__c` → Aplicada / Expirada | **USER_MODE** sob `StatusTransitionContext` | O vendedor tem FLS de edição de `Status__c`; o gate da Trigger garante que só o service autorizado faz a transição |
| `Item_Contrato__c` (insert, quantidade, status Removido) | **Isolada** (`ContractApplyWriter`) + `ControlledWriteContext` aberto | Dar create/edit ao Permission Set abriria tela e API; a Trigger continua exigindo o escopo (defesa em profundidade) |
| `Contrato_Assinatura__c.Versao__c` / `Plano_Atual__c` | **Isolada** | `Versao__c` é protegido (ninguém tem FLS de edição); trocar plano é efeito da aplicação |
| `Aditivo_Contrato__c` | **Isolada** | Só a aplicação o cria; permitir create ao vendedor permitiria forjar aditivos |
| `Order` / `OrderItem` | **Isolada** | Objetos padrão sem create para o vendedor; o pedido é subproduto do aditivo |
| `Historico_Decisao__c` (Expirada) | **Isolada** (`AuthorizedSystemWriter`) | Histórico é somente inserção, independente de FLS de quem clica |

Resultado para `Assinatura_Vendedor`: **nenhuma** permissão de escrita nova; apenas leitura de `Order`/`OrderItem` (link do pedido na
página, US-05) e acesso ao `SubscriptionApplyController`. `without sharing`: `CalculatedFieldWriter`, `AuthorizedSystemWriter`,
`ContractApplyWriter` (três, todas com cabeçalho de justificativa; grep deve listar só elas).

## Regras e barreiras

- Ordem de locks: **Solicitação → Contrato** (`FOR UPDATE`), estado revalidado depois do lock; checagem de status → contrato Ativo →
  data de efetivação ≤ hoje → versão.
- Três barreiras anti-duplicidade: lock pessimista, versionamento otimista (`Versao__c` × `Versao_Contrato_Base__c`, vira Expirada com
  histórico e **commita**) e `Aditivo_Contrato__c.Chave_Unica__c` (`SolicitacaoId-Ciclo`, DUPLICATE_VALUE devolve o resultado existente).
- Atomicidade: `Savepoint` + `Database.rollback` ao primeiro erro (itens, plano, versão, Aditivo, Order e OrderItems voltam);
  `Log_Tecnico__c` gravado **depois** do rollback; a solicitação segue Aprovada e reprocessável. O Controller nunca lança.
- Integridade extra: depois de gravar os itens, o MRR recalculado pela Trigger precisa igualar `MRR_Proposto__c`; senão aborta e reverte.
- **OrderItem**: `Quantity` = variação assinada (nova − atual; remover = −atual) e `UnitPrice` = preço mensal da linha, de modo que o total do
  Order = ΔMRR. Exige **quantidade negativa habilitada** (`enableNegativeQuantity` no scratch def) — *não provado em org*.
- Injeção de falha de teste: `ContractApplyWriter.failAtOrderItem` (`@TestVisible`, só vale com `Test.isRunningTest()`); falha no n-ésimo OrderItem.
- Pricebook: do contrato ou o padrão por nome (CMDT); falta de `PricebookEntry` lista os produtos sem preço e não aplica nada.

## Limitações (3B)

- Aplica **uma solicitação por chamada** (Controller); aplicação em lote/agendada é o bônus da seção 12 do desafio.
- Contratos com milhares de itens: o service lê todos os itens ativos (1 SOQL) e grava em poucos DML, mas heap/CPU e *row locks* do
  contrato tornam o desenho frágil; evolução: Queueable por lotes de itens e leitura agregada (ver RESPOSTAS_CODE_REVIEW.md, 3E).
- Não há pro rata: o Order registra variações mensais cheias a partir da data de efetivação.
- Troca de plano exige produtos distintos entre planos (decisão da Parte 2).
