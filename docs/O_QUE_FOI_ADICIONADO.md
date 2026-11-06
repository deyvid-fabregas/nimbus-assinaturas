# O que foi adicionado e para que serve

## Etapa 3D (interface)
| Item | Para que serve |
|---|---|
| LWC `subscriptionChangeSimulator` | Simular troca de plano/itens no contrato, chamando o Apex (regras no servidor) |
| LWC `subscriptionRequestSummary` | Resumo acessível da solicitação, com indicadores de disponibilidade das ações |
| `SubscriptionChangeController`, `SubscriptionRequestSummaryController` | Pontos `@AuraEnabled` dos LWC |
| FlexiPages `Solicitacao_Alteracao_Record_Page`, `Contrato_Assinatura_Record_Page` | Páginas de registro com componentes e ações por estado |
| 4 Quick Actions de Screen Flow | Enviar, decidir, reabrir e aplicar a partir da página |
| App `Assinaturas`, 3 tabs, 2 layouts | Navegação e ativação das páginas |
| `package.json`, `jest.config.js` | Execução dos testes Jest (cobertura mínima 80%) |

## Validação na org (06/11/2026)
| Item | Para que serve |
|---|---|
| `SubscriptionChangeController.simulateJson` / `saveDraftJson` | Recebem a requisição como JSON e desserializam no servidor (o DTO chegava vazio pelo Aura) |
| `SubscriptionChangeJsonTest` | Testa as ações JSON, incluindo JSON inválido |
| `actionOverrides` nos objetos `Contrato_Assinatura__c` e `Solicitacao_Alteracao__c` | Abrem as FlexiPages ao visualizar o registro |
| `userPermissions` `RunFlow` nos Permission Sets | Permite abrir os Screen Flows (enviar, decidir, reabrir, aplicar) |
| `scripts/apex/seed-contracts.apex` | Cria 6 contas e 6 contratos Ativos de demonstração (idempotente) |
| Usuário `aprovador.nimbus@...` | Segundo usuário para decidir (o solicitante não pode decidir a própria solicitação) |
| `docs/RESPOSTAS_CODE_REVIEW.md` | Respostas às 11 perguntas de code review do PDF |
| `docs/evidencias/jornada-validada.md` e `evidencias/img/` | Capturas da jornada completa, recortadas sem a barra do navegador |

## Testes Apex
`TestDataFactory`, `PolicyAndUtilityTest`, `ApprovalFlowTest`, `SubscriptionChangeTest`, `SubscriptionApplyTest`: 77 testes (incluindo `SummaryAndSelectorTest`, `SelectorCoverageTest`, `NegativePathTest`, `DecisionAndSummaryStatesTest`) que cobrem alçada, estados, roteamento, simulação e aplicação. Resultado em [evidencias/cobertura-apex.md](evidencias/cobertura-apex.md).

## Documentos
`COMO_USAR_A_ORG.md`, `RESPOSTAS_CODE_REVIEW.md`, `SEGURANCA.md`, `RELATORIO_ERROS_PRE_DEPLOY.md`, `CONTINUAR_DAQUI.md`, e evidências em `docs/evidencias/` (`jest.md`, `flexipage.md`, `cobertura-apex.md`, `deploy.json`).
