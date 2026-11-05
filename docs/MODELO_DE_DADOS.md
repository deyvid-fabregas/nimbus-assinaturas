# Modelo de dados e permissões (Parte 1b)

Metadados em formato source (`force-app/main/default`). Nomes de API exatamente como o desafio os define; os campos
auxiliares estão marcados abaixo. Gerados e validados estaticamente (XML bem formado; todo campo usado no Apex existe;
valores de picklist coincidem com `SubscriptionConstants`). **Ainda não implantados em uma org.**

## Implantação (Scratch Org)

```bash
sf org create scratch -f config/project-scratch-def.json -a nimbus -d
sf project deploy start -o nimbus
sf org assign permset -n Assinatura_Administrador -o nimbus
sf apex run -f scripts/apex/seed-catalog.apex -o nimbus     # carga de demonstração (MRR do contrato demo = 2.700,00)
```

O `project-scratch-def.json` habilita **Orders** (necessário para `Aditivo_Contrato__c.Order__c` e para a Parte 3).
Se o deploy acusar ordem de dependência, implante primeiro `objects`, depois `customMetadata`/`permissionsets`.

## Objetos

| Objeto | Nome | Sharing | Observações |
|---|---|---|---|
| `Plano_Assinatura__c` | Texto | Public RW¹ | Validações: preço > 0, nível 1–3, mínimo ≤ máximo |
| `Contrato_Assinatura__c` | `CTR-{000000}` | Public RW¹ | `Account__c` e `Plano_Atual__c` obrigatórios (exclusão restrita); validação fim > início |
| `Item_Contrato__c` | `ITC-{0000000}` | Controlado pelo pai | **Master-Detail** de `Contrato_Assinatura__c`; quantidade ≥ 1 e preço > 0 |
| `Solicitacao_Alteracao__c` | `SOL-{000000}` | Public RW¹ | `Contrato__c` obrigatório com exclusão restrita; **atividades habilitadas** (Task do roteamento); `Data_Efetivacao__c` obrigatória; `Chave_Idempotencia__c` External ID único |
| `Item_Alteracao__c` | `ALT-{0000000}` | Controlado pelo pai | Master-Detail de `Solicitacao_Alteracao__c` com **reparenting habilitado** (troca de pai, US-02 CA02); zero só para Remover |
| `Historico_Decisao__c` | `HIS-{0000000}` | Controlado pelo pai | Master-Detail; somente inserção (Permission Sets sem edit/delete) |
| `Aditivo_Contrato__c` | `ADT-{000000}` | Public RW¹ | `Chave_Unica__c` External ID único e obrigatório; lookup para `Order` |
| `Log_Tecnico__c` | `LOG-{0000000}` | Public RW¹ | Campos auxiliares: `Classe__c`, `Metodo__c`, `Registro_Relacionado__c`, `Tipo_Excecao__c`, `Mensagem__c`, `Stack_Trace__c` |

¹ O acesso efetivo é decidido por **CRUD/FLS dos Permission Sets** (usuário sem eles não lê nem grava nada); `with sharing`
no Apex continua valendo. Em produção, endureça o OWD e use sharing rules por `Gerente_Conta__c`.

Campos calculados e protegidos (somente leitura em todos os Permission Sets): `MRR_Atual__c`, `Versao__c`, `MRR_Item__c`,
`MRR_Base__c`, `MRR_Proposto__c`, `Variacao_*`, `Versao_Contrato_Base__c`, `Quantidade_Atual__c`,
`Preco_Unitario_Mensal__c` e `Delta_MRR__c` de `Item_Alteracao__c`, `Ciclo_Aprovacao__c`, `Nivel_Aprovacao__c`.

## Custom Metadata (com carga)

* `Parametro_Assinatura__mdt` — registro **Padrão** ativo: variação máxima 50 %, janela de efetivação 30 dias,
  justificativa mínima 20, motivo de rejeição mínimo 20, Pricebook padrão `Standard Price Book`.
* `Matriz_Alcada__mdt` — 13 registros (`Aumento_Pct_*`, `Aumento_Abs_*`, `Reducao_Pct_*`) idênticos à tabela da seção 5 do desafio;
  faixa aberta = sem `Limite_Superior__c`. Responsáveis por **grupo público** (`DeveloperName`): `Aprovadores_Gerentes`,
  `Aprovadores_Diretores`, `Aprovadores_Financeiro` (criados em `groups/`; adicione os usuários aprovadores a eles).

## Custom Permissions e Permission Sets

| Permission Set | Custom Permissions | Objetos |
|---|---|---|
| `Assinatura_Vendedor` | `Aplicar_Alteracao` | Lê catálogo/contratos/aditivos/histórico; cria e edita solicitações; CRUD de `Item_Alteracao__c` |
| `Assinatura_Aprovador` | `Aprovar_Gerente`, `Aprovar_Diretor`, `Aprovar_Financeiro` | Lê tudo; edita decisão da solicitação; insere `Historico_Decisao__c` |
| `Assinatura_Administrador` | — | CRUD de plano e contrato; lê itens/aditivos; histórico só inserção; lê e exclui `Log_Tecnico__c`; **não** decide nem aplica |

A **designação** do aprovador (grupo da matriz) é separada da **Custom Permission**: o servidor exige as duas (US-04).
Os três níveis compartilham `Assinatura_Aprovador`; quem diferencia o nível é a participação no grupo.
Para segregar por nível, crie um Permission Set por Custom Permission.

## Limitações e pendências

* Sem page layouts, tabs, app ou FlexiPages (Parte 3). Permissões de classes Apex expostas (Controllers/Invocables) e do
  `Task` de roteamento (campo de deduplicação) também ficam para a Parte 3.
* `Assinatura_Vendedor` ainda **não** concede as escritas da aplicação (`Aditivo_Contrato__c`, `Order`, `OrderItem`, edição de
  `Contrato_Assinatura__c.Versao__c`/`Plano_Atual__c`): a Parte 3 decide quais ficam em `USER_MODE` e quais em escrita isolada.
* Campos obrigatórios e master-detail não recebem FLS (regra da plataforma): ficam editáveis para quem tem create/edit no objeto.
* `Variacao_Percentual__c` usa precisão 18,2 (base pequena pode gerar percentuais enormes).
* Picklists são *restricted*; valores com acento são valores de API (devem coincidir com `SubscriptionConstants`).

## Atualização (Parte 3 — 3A)

* **`Task.Chave_Deduplicacao__c`** (Text 80): chave `APR|<SolicitacaoId>|<Ciclo>` da Task de roteamento. Escrita apenas por
  `AuthorizedSystemWriter`; sem FLS em Permission Set (não é editável por usuário).
* **Class access** adicionado: `Assinatura_Vendedor` (`ApprovalRoutingAction`, `ApprovalRoutingFaultAction`,
  `SubscriptionReopenAction`), `Assinatura_Aprovador` (`SubscriptionDecisionAction`, `SubscriptionReopenAction`),
  `Assinatura_Administrador` (as quatro). Controllers/LWC e `SubscriptionApplyController` entram em 3B/3D.
* Pendências mantidas: escritas da aplicação (Aditivo, Order, `Versao__c`) → 3B; layouts, tabs, app e FlexiPages → 3D.

## Atualização (Parte 3 — 3B)

* `Assinatura_Vendedor`, `Assinatura_Aprovador` e `Assinatura_Administrador`: leitura de `Order` e `OrderItem`.
* `Assinatura_Vendedor`: class access a `SubscriptionApplyController`. **Nenhuma** permissão de escrita nova (a aplicação grava por
  `ContractApplyWriter`; ver `DECISOES_E_LIMITACOES.md`).
* Scratch org: `orderSettings.enableNegativeQuantity = true` (necessário para OrderItem de redução/remoção).
