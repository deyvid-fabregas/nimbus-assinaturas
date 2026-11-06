# Evidência FlexiPages (etapa 3D)

Deploy parcial: ID 0Afaj00000qbPXnCAM, **Succeeded**, 19 componentes (docs\evidencias\deploy.json).

## Verificado na org (Tooling API)
- Contrato_Assinatura_Record_Page (RecordPage, Contrato_Assinatura__c)
- Solicitacao_Alteracao_Record_Page (RecordPage, Solicitacao_Alteracao__c)

## Ativação
Via `actionOverrides` (View, Flexipage) no app Lightning `Assinaturas`; vale só para esse app, não como default da org nem por profile.

## NÃO verificado
- Renderização visual no navegador (não realizada).
- Comportamento real das regras de visibilidade por Status__c / Custom Permissions e das Quick Actions (Screen Flows) na UI.
- Os Screen Flows referenciados pelas Quick Actions devem existir na org; o deploy passou, mas a execução não foi testada.

## Desvio
`lst:dynamicRelatedList` foi rejeitado repetidamente (propriedades e colunas); usei `force:relatedListContainer`, que exibe as listas do layout (Itens, Solicitações, Aditivos) em vez de componentes separados.

## Erros e correções
1. PermissionSet: "classAccesses duplicated" -> elementos agrupados contiguamente; tabSettings movido ao fim.
2. FlexiPage: "facet Columns2 not used" -> fieldSection.columns recebe facet com flexipage:column cujo body é a facet de fieldInstance.
3. Layout: "no QuickAction named ..." -> actionName com prefixo do objeto (`Solicitacao_Alteracao__c.<Action>`).
4. dynamicRelatedList: propriedades inválidas (relationshipApiName, rowsToDisplay, showActionBar), exigências adicionais e coluna Name inexistente -> fallback para relatedListContainer.
