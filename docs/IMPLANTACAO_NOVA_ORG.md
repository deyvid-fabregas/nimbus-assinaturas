# Implantação em uma nova org Salesforce

Este roteiro cobre a implantação controlada da base existente. A org de destino ainda precisa ser escolhida e autorizada pelo operador. Os comandos não incluem credenciais; faça a autenticação localmente pelo navegador do Salesforce CLI.

## Antes de começar

- Instale/atualize o Salesforce CLI e confirme com `sf --version`.
- Use uma Scratch Org para desenvolvimento ou uma sandbox autorizada para validação. Não use produção para a primeira implantação.
- O projeto usa Metadata API `62.0` (`sfdx-project.json`).
- O destino deve permitir Orders. A aplicação também depende de quantidade negativa em OrderItem; isso já está habilitado em `config/project-scratch-def.json`, mas precisa ser conferido/configurado em orgs existentes.
- As partes 3C/3D e os testes Apex ainda não foram entregues. Portanto, o deploy atual não representa a solução completa e não habilita a jornada de usuário final.

## Opção A — criar uma Scratch Org

1. Autentique e defina um Dev Hub ativo:

   ```bash
   sf org login web --set-default-dev-hub --alias nimbus-devhub
   ```

2. Crie a Scratch Org a partir da definição do projeto:

   ```bash
   sf org create scratch --target-dev-hub nimbus-devhub --definition-file config/project-scratch-def.json --alias nimbus --duration-days 7 --set-default
   ```

3. Confirme que `nimbus` é o alias de destino antes de implantar:

   ```bash
   sf org list
   ```

Se a organização não tiver Dev Hub habilitado ou não tiver licenças de Scratch Org disponíveis, use uma sandbox autorizada (Opção B).

## Opção B — usar uma org existente

Para sandbox, autentique com o alias escolhido:

```bash
sf org login web --instance-url https://test.salesforce.com --alias nimbus-sandbox
```

Para uma org Developer/Production, use o endpoint correspondente autorizado pelo administrador:

```bash
sf org login web --instance-url https://login.salesforce.com --alias nimbus-destino
```

Não reutilize um alias de destino sem confirmar que ele aponta para a org pretendida. Antes do deploy, confira no Setup se Orders e quantidade negativa estão habilitados e se as configurações existentes não serão substituídas de forma indesejada.

## Preview e deploy

Revise primeiro os componentes que seriam enviados:

```bash
sf project deploy preview --target-org <alias>
```

Se o preview estiver correto e o destino for uma Scratch Org ou sandbox de validação:

```bash
sf project deploy start --target-org <alias>
```

Não implante em produção com esta versão: ela ainda não contém os testes Apex exigidos para validar a aplicação e não passou por uma compilação/deploy em ambiente Salesforce. Se o deploy falhar, corrija a causa indicada pelo Salesforce e repita o preview antes de tentar novamente.

## Configuração após o deploy

1. Atribua ao usuário administrador de configuração:

   ```bash
   sf org assign permset --name Assinatura_Administrador --target-org <alias>
   ```

2. Atribua `Assinatura_Vendedor` e `Assinatura_Aprovador` somente aos usuários que realmente devem receber esses acessos:

   ```bash
   sf org assign permset --name Assinatura_Vendedor --target-org <alias>
   sf org assign permset --name Assinatura_Aprovador --target-org <alias>
   ```

3. Em Setup, adicione os usuários aprovadores aos grupos públicos `Aprovadores_Gerentes`, `Aprovadores_Diretores` e `Aprovadores_Financeiro`, conforme a alçada. A permissão Apex, a Custom Permission e a designação no grupo são controles distintos.
4. Em produção, revise o modelo de sharing e os Permission Sets antes de conceder acesso. Os metadados atuais foram preparados para demonstração e usam sharing permissivo, conforme documentado em `MODELO_DE_DADOS.md`.

## Carga de demonstração (opcional)

Execute somente em uma Scratch Org ou sandbox descartável após revisar o script. Ele cria produtos, planos, uma conta demo e um contrato com itens; não execute em produção.

```bash
sf apex run --file scripts/apex/seed-catalog.apex --target-org <alias>
```

O MRR esperado do contrato demo é 2.700,00. A carga é descrita como idempotente no próprio script.

## Critérios para considerar a implantação validada

- Deploy concluído sem erros e com os componentes esperados.
- Testes Apex adicionados e aprovados; eles ainda não existem nesta entrega.
- Grupos e Permission Sets verificados para cada persona, com menor privilégio.
- Testes de simulação, envio, roteamento, decisão, reabertura e aplicação executados no destino.
- Confirmação de Orders/quantidade negativa e validação dos registros de Order/OrderItem.
- Nenhum teste com dados de demonstração executado em produção.
