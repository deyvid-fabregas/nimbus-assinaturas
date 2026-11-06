# Cobertura Apex por classe

Execução em 06/11/2026 na org `nimbus-org`: `sf apex run test --test-level RunLocalTests --code-coverage`.

- Testes executados: **58**, aprovados: **58**, falhas: **0**.
- Cobertura da execução: **86%**; cobertura geral da org: **80%**.
- Classes e triggers com dados de cobertura: 64; **33 já estão em ≥ 90%** e **31 ainda estão abaixo**.

> **Meta do PDF (US-07): ≥ 90% em CADA classe. Ainda NÃO atingida.** Ver [CONTINUAR_DAQUI.md](../CONTINUAR_DAQUI.md).

Os testes existentes ficam em `TestDataFactory`, `PolicyAndUtilityTest`, `ApprovalFlowTest`, `SubscriptionChangeTest` e `SubscriptionApplyTest`.

| Classe / Trigger | Linhas cobertas/total | % |
|---|---|---|
| SubscriptionRequestSummaryDTO | 0/5 | 0% |
| SubscriptionConstants | 0/1 | 0% |
| TaskSelector | 0/5 | 0% |
| SubscriptionRequestSummaryController | 0/13 | 0% |
| SubscriptionRequestSummaryService | 0/97 | 0% |
| DecisionHistorySelector | 0/5 | 0% |
| SubscriptionRequestSummaryAction | 0/74 | 0% |
| PricebookSelector | 8/20 | 40% |
| PlanSelector | 7/14 | 50% |
| AdditiveSelector | 6/12 | 50% |
| ContractItemSelector | 14/26 | 54% |
| ItemAlteracaoHandler | 33/53 | 62% |
| RequestSnapshotService | 36/58 | 62% |
| ItemContratoHandler | 34/53 | 64% |
| RequestItemSelector | 20/28 | 71% |
| RequestSelector | 21/29 | 72% |
| SubscriptionConfig | 43/59 | 73% |
| CalculatedFieldWriter | 6/8 | 75% |
| RequestItemService | 74/98 | 76% |
| ControlledWriteContext | 25/32 | 78% |
| DesignationSelector | 61/78 | 78% |
| ChangePlanner | 96/122 | 79% |
| RequestSubmissionService | 66/84 | 79% |
| SolicitacaoAlteracaoHandler | 71/88 | 81% |
| ContractSelector | 10/12 | 83% |
| SubscriptionDecisionService | 224/259 | 86% |
| SubscriptionChangeController | 62/72 | 86% |
| ApprovalRoutingService | 171/200 | 86% |
| RequestRecalculationService | 34/39 | 87% |
| ContractMrrService | 14/16 | 88% |
| ChangeContext | 23/26 | 88% |
| PricebookResolver | 36/40 | 90% |
| ApprovalRoutingAction | 26/29 | 90% |
| SubscriptionChangeService | 183/204 | 90% |
| SubscriptionApplyService | 224/246 | 91% |
| RecursionGuard | 32/34 | 94% |
| ItemResolutionPolicy | 65/68 | 96% |
| AuthorizedSystemWriter | 55/57 | 96% |
| TechnicalLogger | 44/46 | 96% |
| ChangeContextLoader | 48/50 | 96% |
| CollectionUtil | 23/24 | 96% |
| StatusTransitionContext | 31/32 | 97% |
| ChangeRequestPolicy | 80/82 | 98% |
| ApprovalMatrixPolicy | 122/125 | 98% |
| RequestStateMachine | 58/59 | 98% |
| SubscriptionItemChangeTrigger | 1/1 | 100% |
| SubscriptionContractItemTrigger | 1/1 | 100% |
| SubscriptionRequestTrigger | 1/1 | 100% |
| SubscriptionChangeResultDTO | 10/10 | 100% |
| SubscriptionDecisionAction | 24/24 | 100% |
| ContractApplyWriter | 67/67 | 100% |
| SubscriptionApplyController | 9/9 | 100% |
| SecurityGuard | 24/24 | 100% |
| SubscriptionChangeRequestDTO | 7/7 | 100% |
| SubscriptionSettings | 6/6 | 100% |
| SubscriptionApplyAction | 25/25 | 100% |
| SubscriptionApplyResultDTO | 8/8 | 100% |
| ApprovalRoutingFaultAction | 17/17 | 100% |
| SubscriptionReopenAction | 17/17 | 100% |
| MrrCalculator | 21/21 | 100% |
| MoneyUtil | 18/18 | 100% |
| SubscriptionException | 4/4 | 100% |
| TextUtil | 4/4 | 100% |
| SubscriptionClock | 4/4 | 100% |

Notas: `SubscriptionConstants` tem 1 linha executável (provável classe só de constantes); verificar se o 0% é real. As classes de resumo da solicitação (Summary*) não têm nenhum teste ainda.
