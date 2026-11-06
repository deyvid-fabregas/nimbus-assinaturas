# Segurança da org (verificação parcial)

> A revisão de segurança completa foi interrompida. Este documento só afirma o que foi verificado por busca no código em 06/11/2026. **Não é uma declaração de ausência de lacunas.**

## Verificado
- Apenas **3 classes `without sharing`**, todas escritoras isoladas: `ContractApplyWriter`, `CalculatedFieldWriter`, `AuthorizedSystemWriter`. Elas só executam efeitos colaterais de operações já autorizadas.
- **Sem SOQL dinâmico** (`Database.query` não aparece) e sem `innerHTML`/`lwc:dom` nos LWC.
- **Nenhum Permission Set** usa `modifyAllData` ou `viewAllData`.
- Selectors usam `WITH USER_MODE`/modo usuário; `SecurityGuard` centraliza checagens (100% coberta).
- A regras críticas ficam no servidor: o gate de status (`StatusTransitionContext`) recusa edição direta de status por API; abrir um Flow por URL não contorna permissão, designação, segregação de funções, ciclo ou estado (ver `STATUS.md`).
- Permissões por Custom Permission (`Aprovar_Gerente`, `Aprovar_Diretor`, `Aprovar_Financeiro`, `Aplicar_Alteracao`) combinadas com designação por grupo público.
- `Historico_Decisao__c` é só inserção; falhas técnicas gravam `Log_Tecnico__c` após rollback.

## Limitações conhecidas (de `DECISOES_E_LIMITACOES.md`)
- Execução de Apex arbitrário por um administrador contorna o gate de transição.
- Grupos aninhados e papéis subordinados não são expandidos na designação.
- O sharing dos metadados de demonstração é permissivo; revisar antes de produção.

## Ainda por verificar
- CRUD/FLS nas escritas em modo sistema; mensagens de erro e `Log_Tecnico__c` sem vazamento de dados; Permission Sets por menor privilégio; Flows em modo sistema; `Code Analyzer` (regras de segurança). Executar a revisão e atualizar este arquivo.
