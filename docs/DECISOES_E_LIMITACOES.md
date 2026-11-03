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
