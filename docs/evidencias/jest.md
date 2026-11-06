# Evidência Jest (etapa 3D)

Comando: `npm test -- --coverage` (@salesforce/sfdx-lwc-jest)

Resultado: 2 suites, 28 testes, todos passando.

| Arquivo | % Stmts | % Branch | % Funcs | % Lines |
|---|---|---|---|---|
| Todos | 98.29 | 87.25 | 98.61 | 98.12 |
| subscriptionChangeSimulator.js | 98.16 | 84.61 | 97.72 | 97.97 |
| subscriptionRequestSummary.js | 98.5 | 91.89 | 100 | 98.36 |

Limite configurado em jest.config.js: 80% statements.

## Erros e correções
1. Pasta `__tests__` ausente -> criada.
2. devDependency eslint não usada -> removida.
3. Teste "não chama o servidor sem recordId" falhava: `mount(undefined)` aciona o parâmetro default -> `mount(null)`.
4. O "NativeCommandError" do PowerShell é apenas ruído de stderr do jest.
