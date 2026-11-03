# Nimbus — Gestão de Assinaturas e Alteração de Planos

Projeto Salesforce (Apex, Flows, LWC) do desafio Nível 3: simulação, solicitação, aprovação por alçada e aplicação de alterações em contratos de assinatura.

> **Status:** em andamento. Partes 1, 1b e 2 entregues, sem deploy validado em org. Veja [docs/STATUS.md](docs/STATUS.md).

## Estrutura

| Caminho | Conteúdo |
|---|---|
| `force-app/` | Apex (domínio, services, selectors, handlers, triggers) e metadados (objetos, CMDT, Permission Sets) |
| `config/project-scratch-def.json` | Definição da Scratch Org (Orders habilitado) |
| `scripts/apex/seed-catalog.apex` | Seed de produtos, planos e contrato demo (MRR 2.700,00) |
| `docs/` | Documentação do projeto |

## Documentação

- [STATUS.md](docs/STATUS.md): andamento por parte, pendências e próximos passos
- [ARQUITETURA.md](docs/ARQUITETURA.md): camadas, ownership, catálogo de classes, orçamento de SOQL/DML
- [MODELO_DE_DADOS.md](docs/MODELO_DE_DADOS.md): objetos, CMDT, Permission Sets e comandos de deploy
- [DECISOES_E_LIMITACOES.md](docs/DECISOES_E_LIMITACOES.md): decisões de projeto e limitações conhecidas
- [PARTE1 CODIGO APEX.md](docs/PARTE1%20CODIGO%20APEX.md): código da Parte 1

## Início rápido

```bash
sf org create scratch -f config/project-scratch-def.json -a nimbus -d
sf project deploy start
sf apex run -f scripts/apex/seed-catalog.apex
```

Detalhes de deploy e atribuição de Permission Sets em [MODELO_DE_DADOS.md](docs/MODELO_DE_DADOS.md).
