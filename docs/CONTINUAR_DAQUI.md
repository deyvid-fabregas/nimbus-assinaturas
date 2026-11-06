# Onde paramos e o que falta

Data: 06/11/2026. Org de trabalho: alias `nimbus-org` (usuário `deyvidfabregas41@empathetic-goat-e3uxf8.com`). Repositório: `deyvid-fabregas/nimbus-assinaturas`.

## Já feito
- Deploy completo de `force-app` na `nimbus-org`: **Succeeded** (Apex, Flows, objetos, Permission Sets, LWC, FlexiPages, app).
- LWC `subscriptionChangeSimulator` e `subscriptionRequestSummary`; Jest: 28 testes, 98,29% de statements.
- Duas FlexiPages existem na org: `Solicitacao_Alteracao_Record_Page` e `Contrato_Assinatura_Record_Page`.
- Testes Apex: 58 passando, 0 falhas, cobertura da execução 86%.
- Documentos novos e atualizados (ver abaixo).

## Falta fazer (em ordem)
1. **Cobertura Apex ≥ 90% por classe.** 31 classes abaixo (tabela em [evidencias/cobertura-apex.md](evidencias/cobertura-apex.md)). Prioridade:
   - 0%: `SubscriptionRequestSummaryService/Action/Controller/DTO`, `TaskSelector`, `DecisionHistorySelector`, `SubscriptionConstants`.
   - 40–65%: `PricebookSelector`, `PlanSelector`, `AdditiveSelector`, `ContractItemSelector`, `ItemAlteracaoHandler`, `RequestSnapshotService`, `ItemContratoHandler`.
   - 70–89%: demais selectors, `SubscriptionConfig`, `RequestItemService`, `ChangePlanner`, `SubscriptionDecisionService`, `ApprovalRoutingService` etc.
   - Comando: `sf apex run test -o nimbus-org --test-level RunLocalTests --code-coverage --result-format json --wait 30`. Os testes ficam em `force-app/main/default/classes/*Test.cls`; use `TestDataFactory`, sem `SeeAllData=true`.
2. **Validar a FlexiPage visualmente**: abrir `sf org open -o nimbus-org`, abrir o app `Assinaturas` e conferir os 5 estados, a visibilidade por Custom Permission e as Quick Actions. Tirar capturas de tela (evidência exigida no PDF). Atribuir os Permission Sets ao usuário e popular os grupos de aprovadores antes.
3. **Flow Tests declarativos (mínimo 6)**: ainda não existem. Roteiro dos casos em `STATUS.md`.
4. **Code Analyzer** (`sf code-analyzer run`): ainda não executado; PDF exige zero violações críticas.
5. **Revisão de segurança completa**: a revisão automática foi interrompida. Ver [SEGURANCA.md](SEGURANCA.md) (parcial).
6. **Confirmar com o PDF os possíveis desvios** listados em [RELATORIO_ERROS_PRE_DEPLOY.md](RELATORIO_ERROS_PRE_DEPLOY.md) (lookups `Produto__c` opcionais; edição de `Log_Tecnico__c` ao administrador; `relatedListContainer` na FlexiPage).
7. Ao concluir: atualizar números em `docs/` e README, e publicar no GitHub.

## Observações de ambiente
- `minha_nova_org` contém o projeto Nível 2 (conflita com este): não usar para o Nível 3.
- Nenhuma organização do GitHub foi informada; o destino continua sendo o repositório pessoal acima.
- A pasta local não é repositório git; para publicar, clonar o repositório, copiar as mudanças e fazer commit/push. Commits **sem** trailer de coautoria do Copilot.
- O PowerShell exibe `NativeCommandError` ao rodar `sf`/`jest` por causa do stderr; não é falha real.
