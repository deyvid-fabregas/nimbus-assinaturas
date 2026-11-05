# Nimbus — Gestão de Assinaturas e Alteração de Planos

Projeto Salesforce em Apex para simulação, solicitação, aprovação por alçada e aplicação de alterações em contratos de assinatura.

> **Status:** Partes 1, 1b, 2, 3A e 3B implementadas. Ainda não há compilação, testes nem implantação validados em uma org. As partes de Flows, interface e testes continuam pendentes; consulte [docs/STATUS.md](docs/STATUS.md).

## Estrutura

| Caminho | Conteúdo |
|---|---|
| `force-app/` | Apex, triggers e metadados de dados, configuração e permissões |
| `config/project-scratch-def.json` | Configuração de Scratch Org com Orders e quantidades negativas habilitados |
| `scripts/apex/seed-catalog.apex` | Carga opcional de demonstração (MRR inicial esperado de 2.700,00) |
| `docs/` | Arquitetura, modelo de dados, decisões, status e implantação |

## Documentação

- [docs/STATUS.md](docs/STATUS.md): andamento, pendências e próximos passos
- [docs/IMPLANTACAO_NOVA_ORG.md](docs/IMPLANTACAO_NOVA_ORG.md): pré-requisitos e roteiro para uma org nova
- [docs/ARQUITETURA.md](docs/ARQUITETURA.md): camadas, responsabilidades e catálogo de componentes
- [docs/MODELO_DE_DADOS.md](docs/MODELO_DE_DADOS.md): objetos, Custom Metadata e Permission Sets
- [docs/DECISOES_E_LIMITACOES.md](docs/DECISOES_E_LIMITACOES.md): decisões e limitações conhecidas
- [docs/PARTE1%20CODIGO%20APEX.md](docs/PARTE1%20CODIGO%20APEX.md): documentação da Parte 1

## Início

Use uma Scratch Org ou uma sandbox autorizada e siga [docs/IMPLANTACAO_NOVA_ORG.md](docs/IMPLANTACAO_NOVA_ORG.md). Não implante em produção enquanto os testes Apex obrigatórios e as validações pendentes não forem concluídos.
