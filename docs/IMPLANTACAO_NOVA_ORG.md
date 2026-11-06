# Implantação em uma nova org Salesforce

Este roteiro cobre a implantação controlada da base existente. A org de destino ainda precisa ser escolhida e autorizada pelo operador. Os comandos não incluem credenciais; faça a autenticação localmente pelo navegador do Salesforce CLI.

## Antes de começar

- Instale/atualize o Salesforce CLI e confirme com `sf --version`.
- Use uma Scratch Org para desenvolvimento ou uma sandbox autorizada para validação. Não use produção para a primeira implantação.
- O projeto usa Metadata API `62.0` (`sfdx-project.json`).
- O destino deve permitir Orders. A aplicação também depende de quantidade negativa em OrderItem; isso já está habilitado em `config/project-scratch-def.json`, mas precisa ser conferido/configurado em orgs existentes.
- O deploy inclui **5 Flows ativos** (`force-app/main/default/flows`). O Flow de roteamento dispara em toda atualização de `Solicitacao_Alteracao__c` que muda o status para Pendente.
- As entregas 3D (LWC, FlexiPages, app) e os testes Apex/Jest/Flow ainda não foram feitos. Portanto, o deploy atual não representa a solução completa e não oferece a interface final de usuário.

## Opção A — criar uma Scratch Org

1. Autentique e defina um Dev Hub ativo:

   ```
   sf org login web --set-default-dev-hub --alias nimbus-devhub
   ```
2. Crie a Scratch Org a partir da definição do projeto:

   ```
   sf org create scratch --target-dev-hub nimbus-devhub --definition-file config/project-scratch-def.json --alias nimbus --duration-days 7 --set-default
   ```
3. Confirme que `nimbus` é o alias de destino antes de implantar:

   ```
   sf org list
   ```

Se a organização não tiver Dev Hub habilitado ou não tiver licenças de Scratch Org disponíveis, use uma sandbox autorizada (Opção B).

## Opção B — usar uma org existente

Para sandbox, autentique com o alias escolhido:

```
sf org login web --instance-url https://test.salesforce.com --alias nimbus-sandbox
```

Para uma org Developer/Production, use o endpoint correspondente autorizado pelo administrador:

```
sf org login web --instance-url https://login.salesforce.com --alias nimbus-destino
```

Não reutilize um alias de destino sem confirmar que ele aponta para a org pretendida. Antes do deploy, confira no Setup se Orders e quantidade negativa estão habilitados e se as configurações existentes não serão substituídas de forma indesejada.

## Preview e deploy

Revise primeiro os componentes que seriam enviados:

```
sf project deploy preview --target-org <alias>
```

Se o preview estiver correto e o destino for uma Scratch Org ou sandbox de validação:

```
sf project deploy start --target-org <alias>
```

Não implante em produção com esta versão: ela ainda não contém os testes Apex exigidos para validar a aplicação e não passou por uma compilação/deploy em ambiente Salesforce. Se o deploy falhar, corrija a causa indicada pelo Salesforce e repita o preview antes de tentar novamente. Erros comuns esperados no primeiro deploy: ordem de dependência entre objetos e Flows (reimplante em duas etapas: `objects`, depois o restante), nomes de parâmetros das actions invocáveis nos Flows e configuração de Orders.

## Configuração após o deploy

1. Atribua ao usuário administrador de configuração:

   ```
   sf org assign permset --name Assinatura_Administrador --target-org <alias>
   ```
2. Atribua `Assinatura_Vendedor` e `Assinatura_Aprovador` somente aos usuários que realmente devem receber esses acessos:

   ```
   sf org assign permset --name Assinatura_Vendedor --target-org <alias>
   sf org assign permset --name Assinatura_Aprovador --target-org <alias>
   ```
3. Em Setup, adicione os usuários aprovadores aos grupos públicos `Aprovadores_Gerentes`, `Aprovadores_Diretores` e `Aprovadores_Financeiro`, conforme a alçada. A permissão Apex, a Custom Permission e a designação no grupo são controles distintos. **Sem ao menos um usuário ativo no grupo do nível, o roteamento falha e o envio é desfeito (volta a Rascunho).**
4. Em produção, revise o modelo de sharing e os Permission Sets antes de conceder acesso. Os metadados atuais foram preparados para demonstração e usam sharing permissivo, conforme documentado em `MODELO_DE_DADOS.md`.

## Ações dos Flows nos registros (até a entrega 3D)

Enquanto as Lightning Record Pages não existem, crie manualmente em Setup → Object Manager → Solicitação de Alteração → Buttons, Links and Actions uma **Quick Action do tipo Flow** para cada Screen Flow e adicione-as ao layout:

| Flow                              | Uso                         | Quem usa                   |
|-----------------------------------|-----------------------------|----------------------------|
| `Enviar_Solicitacao_Aprovacao`    | Rascunho → Pendente         | Vendedor                   |
| `Decidir_Solicitacao_Alteracao`   | Aprovar ou rejeitar         | Aprovador designado        |
| `Reabrir_Solicitacao_Alteracao`   | Rejeitada → Rascunho        | Solicitante ou aprovador   |
| `Aplicar_Alteracao_Aprovada`      | Aplicar alteração aprovada  | Quem tem `Aplicar_Alteracao` |

As quatro disponibilizam apenas o que o servidor permite; a ação continua validada no Apex mesmo que o botão apareça para quem não deveria.

## Carga de demonstração (opcional)

Execute somente em uma Scratch Org ou sandbox descartável após revisar o script. Ele cria produtos, planos, uma conta demo e um contrato com itens; não execute em produção.

```
sf apex run --file scripts/apex/seed-catalog.apex --target-org <alias>
```

O MRR esperado do contrato demo é 2.700,00. A carga é descrita como idempotente no próprio script.

## Critérios para considerar a implantação validada

- Deploy concluído sem erros e com os componentes esperados (incluindo os 5 Flows ativos).
- Testes Apex adicionados e aprovados; eles ainda não existem nesta entrega.
- Grupos e Permission Sets verificados para cada persona, com menor privilégio.
- Testes de simulação, envio, roteamento, decisão, reabertura e aplicação executados no destino.
- Confirmação de Orders/quantidade negativa e validação dos registros de Order/OrderItem.
- Nenhum teste com dados de demonstração executado em produção.
