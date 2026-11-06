# Nimbus — Gestão de Assinaturas e Alteração de Planos

Projeto Salesforce em Apex e Flow para simulação, solicitação, aprovação por alçada e aplicação de alterações em contratos de assinatura.

> **Status:** Partes 1, 1b, 2, 3A, 3B e 3C implementadas (Apex, metadados, Flow de roteamento e Screen Flows). Ainda não há compilação, testes nem implantação validados em uma org. Interface (LWC/FlexiPage), testes e documentos finais continuam pendentes; consulte [docs/STATUS.md](docs/STATUS.md).

## Estrutura

| Caminho                           | Conteúdo                                                                           |
|-----------------------------------|------------------------------------------------------------------------------------|
| `force-app/`                      | Apex, triggers, Flows e metadados de dados, configuração e permissões              |
| `force-app/main/default/flows/`   | Flow de roteamento (record-triggered) e Screen Flows de envio, decisão, reabertura e aplicação |
| `config/project-scratch-def.json` | Configuração de Scratch Org com Orders e quantidades negativas habilitados         |
| `scripts/apex/seed-catalog.apex`  | Carga opcional de demonstração (MRR inicial esperado de 2.700,00)                  |
| `docs/`                           | Arquitetura, modelo de dados, decisões, status e implantação                       |

## Jornada coberta

Simulação e rascunho (Apex) → envio (Screen Flow) → roteamento por alçada (Flow + Apex, Task ou aprovação automática) → decisão (Screen Flow + `SubscriptionDecisionService`) → reabertura ou aplicação transacional (Aditivo + Order, atômica e idempotente).

A tela de simulação (LWC), as Lightning Record Pages e o app chegam na entrega 3D.

## Documentação

- [docs/STATUS.md](docs/STATUS.md): andamento, pendências e próximos passos
- [docs/IMPLANTACAO_NOVA_ORG.md](docs/IMPLANTACAO_NOVA_ORG.md): pré-requisitos e roteiro para uma org nova
- [docs/ARQUITETURA.md](docs/ARQUITETURA.md): camadas, responsabilidades e catálogo de componentes
- [docs/MODELO_DE_DADOS.md](docs/MODELO_DE_DADOS.md): objetos, Custom Metadata, Permission Sets e acessos a classes/Flows
- [docs/DECISOES_E_LIMITACOES.md](docs/DECISOES_E_LIMITACOES.md): decisões e limitações conhecidas
- [docs/PARTE1 CODIGO APEX.md](docs/PARTE1%20CODIGO%20APEX.md): documentação da Parte 1

## Início

Use uma Scratch Org ou uma sandbox autorizada e siga [docs/IMPLANTACAO_NOVA_ORG.md](docs/IMPLANTACAO_NOVA_ORG.md). Não implante em produção enquanto os testes Apex obrigatórios e as validações pendentes não forem concluídos.
