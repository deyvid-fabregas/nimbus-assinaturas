# Como usar a org e criar planos

Org de trabalho: alias `nimbus-org`. Abrir: `sf org open -o nimbus-org`, depois App Launcher → **Assinaturas**.

## 1. Preparar acessos
```
sf org assign permset --name Assinatura_Administrador -o nimbus-org
sf org assign permset --name Assinatura_Vendedor -o nimbus-org
sf org assign permset --name Assinatura_Aprovador -o nimbus-org
```
Em Setup → Public Groups, adicione aprovadores a `Aprovadores_Gerentes`, `Aprovadores_Diretores` e `Aprovadores_Financeiro`. Sem usuário ativo no grupo do nível, o envio volta a Rascunho.

## 2. Criar planos (catálogo)
- **Pela interface:** aba **Planos de Assinatura** → Novo → preencha nome, produto e preço. Ative o plano.
- **Pela carga de demonstração:** `sf apex run --file scripts/apex/seed-catalog.apex -o nimbus-org` (cria produtos, planos, conta demo e contrato; MRR esperado 2.700,00). Use só em org descartável.

## 3. Fluxo de uma alteração
1. Abra o **Contrato de Assinatura** e use o simulador (`subscriptionChangeSimulator`) para simular e salvar o rascunho.
2. Na solicitação, ação **Enviar para aprovação** (Rascunho → Pendente). O Flow de roteamento classifica pela matriz (automática, Gerente, Diretor, Financeiro ou bloqueio).
3. O aprovador usa **Decidir solicitação** (Aprovada/Rejeitada). Rejeitada pode ser reaberta (**Reabrir**).
4. Com a permissão `Aplicar_Alteracao`, use **Aplicar alteração aprovada**: cria Aditivo e Order de forma atômica e idempotente.

## 4. Rodar testes
- Apex: `sf apex run test -o nimbus-org --test-level RunLocalTests --code-coverage --result-format human --wait 30`
- Jest: `npm install` e `npm test -- --coverage`

Detalhes de implantação em [IMPLANTACAO_NOVA_ORG.md](IMPLANTACAO_NOVA_ORG.md). Os nomes exatos de abas/ações devem ser conferidos na tela, pois a validação visual ainda não foi feita.
