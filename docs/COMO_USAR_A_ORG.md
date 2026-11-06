# Como usar a org e criar planos

Org de trabalho: alias `nimbus-org`. Abrir: `sf org open -o nimbus-org`, depois App Launcher → **Assinaturas**.

## 1. Preparar acessos
```
sf org assign permset --name Assinatura_Administrador -o nimbus-org
sf org assign permset --name Assinatura_Vendedor -o nimbus-org
sf org assign permset --name Assinatura_Aprovador -o nimbus-org
```
Em Setup → Public Groups, adicione aprovadores a `Aprovadores_Gerentes`, `Aprovadores_Diretores` e `Aprovadores_Financeiro`. Sem usuário ativo no grupo do nível, o envio volta a Rascunho.

**Dois usuários são necessários.** Quem cria a solicitação não pode decidi-la (regra do servidor). Crie um segundo usuário (Standard User), atribua `Assinatura_Aprovador`, inclua-o nos três grupos e defina a senha (Setup → Users, ou `System.setPassword` em Apex anônimo). Entre com ele em uma janela anônima.

## 2. Criar planos (catálogo)
- **Pela interface:** aba **Planos de Assinatura** → Novo → preencha nome, produto e preço. Ative o plano.
- **Pela carga de demonstração:** `sf apex run --file scripts/apex/seed-catalog.apex -o nimbus-org` (cria produtos, planos, conta demo e contrato; MRR esperado 2.700,00), depois `sf apex run --file scripts/apex/seed-contracts.apex -o nimbus-org` (6 contas e 6 contratos Ativos). Use só em org descartável. Ambos são idempotentes.

## 3. Fluxo de uma alteração
Use o app **Assinaturas** (não o Sales). Capturas de cada passo em [evidencias/jornada-validada.md](evidencias/jornada-validada.md).
1. Em **Contratos de Assinatura** (visualização **All**), abra um contrato e use o simulador (`subscriptionChangeSimulator`) para simular e **Salvar rascunho**. O simulador mostra o limite do plano, a variação de MRR e o nível previsto.
2. Abra a solicitação (aba **Solicitações de Alteração**, visualização **All**) e use **Enviar para aprovação** (Rascunho → Pendente). O Flow de roteamento classifica pela matriz (automática, Gerente, Diretor, Financeiro ou bloqueio).
3. Com o **segundo usuário**, abra a solicitação e use **Decidir solicitação** (Aprovar/Rejeitar; rejeição exige motivo). Rejeitada pode ser reaberta (**Reabrir**).
4. Com o usuário que tem `Aplicar_Alteracao`, use **Aplicar alteração aprovada** (a data de efetivação precisa ter chegado): cria Aditivo e Order de forma atômica e idempotente.

Faixas de alçada (aumento de MRR): ≤ 5% ou ≤ R$ 2.000 é automática; acima de 50% é bloqueada; as demais dependem de % e R$ na `Matriz_Alcada__mdt`. Confie no "Nível previsto" mostrado na tela.

## 4. Rodar testes
- Apex: `sf apex run test -o nimbus-org --test-level RunLocalTests --code-coverage --result-format human --wait 30`
- Jest: `npm install` e `npm test -- --coverage`

Detalhes de implantação em [IMPLANTACAO_NOVA_ORG.md](IMPLANTACAO_NOVA_ORG.md).
