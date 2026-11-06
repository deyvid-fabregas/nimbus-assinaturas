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

## Testes Apex
`TestDataFactory`, `PolicyAndUtilityTest`, `ApprovalFlowTest`, `SubscriptionChangeTest`, `SubscriptionApplyTest`: 58 testes que cobrem alçada, estados, roteamento, simulação e aplicação. Resultado em [evidencias/cobertura-apex.md](evidencias/cobertura-apex.md).

## Documentos
`COMO_USAR_A_ORG.md`, `SEGURANCA.md`, `RELATORIO_ERROS_PRE_DEPLOY.md`, `CONTINUAR_DAQUI.md`, e evidências em `docs/evidencias/` (`jest.md`, `flexipage.md`, `cobertura-apex.md`, `deploy.json`).
