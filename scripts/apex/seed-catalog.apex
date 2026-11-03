// Carga de DEMONSTRACAO (idempotente): produtos, pricebook padrao, planos e um contrato Ativo com itens.
// Execucao: sf apex run --file scripts/apex/seed-catalog.apex --target-org <alias>
// Itens de contrato so podem ser gravados com o ControlledWriteContext aberto (regra US-02);
// este script e uma das tres excecoes permitidas (ApplyService, testes, seeds) e justifica o uso abaixo.

Pricebook2 standard = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1];

Map<String, Decimal> productPrices = new Map<String, Decimal>{
    'NIM-LIC-BAS' => 120, 'NIM-LIC-INT' => 180, 'NIM-LIC-ENT' => 250,
    'NIM-ADD-ANA' => 1500, 'NIM-ADD-SUP' => 2500, 'NIM-ADD-API' => 800
};
Map<String, String> productNames = new Map<String, String>{
    'NIM-LIC-BAS' => 'Licença Nimbus Básico', 'NIM-LIC-INT' => 'Licença Nimbus Intermediário',
    'NIM-LIC-ENT' => 'Licença Nimbus Enterprise', 'NIM-ADD-ANA' => 'Módulo Analytics',
    'NIM-ADD-SUP' => 'Suporte Premium', 'NIM-ADD-API' => 'Pacote de API Extra'
};

Map<String, Product2> productsByCode = new Map<String, Product2>();
for (Product2 existing : [SELECT Id, ProductCode FROM Product2 WHERE ProductCode IN :productPrices.keySet()]) {
    productsByCode.put(existing.ProductCode, existing);
}
List<Product2> newProducts = new List<Product2>();
for (String code : productPrices.keySet()) {
    if (!productsByCode.containsKey(code)) {
        Product2 product = new Product2(Name = productNames.get(code), ProductCode = code, IsActive = true);
        newProducts.add(product);
        productsByCode.put(code, product);
    }
}
insert newProducts;

Set<Id> productsWithEntry = new Set<Id>();
for (PricebookEntry entry : [SELECT Product2Id FROM PricebookEntry WHERE Pricebook2Id = :standard.Id]) {
    productsWithEntry.add(entry.Product2Id);
}
List<PricebookEntry> entries = new List<PricebookEntry>();
for (String code : productPrices.keySet()) {
    Product2 product = productsByCode.get(code);
    if (!productsWithEntry.contains(product.Id)) {
        entries.add(new PricebookEntry(
            Pricebook2Id = standard.Id, Product2Id = product.Id, UnitPrice = productPrices.get(code), IsActive = true
        ));
    }
}
insert entries;

Map<String, Plano_Assinatura__c> plans = new Map<String, Plano_Assinatura__c>();
for (Plano_Assinatura__c existing : [SELECT Id, Codigo__c FROM Plano_Assinatura__c WHERE Codigo__c LIKE 'NIM-%']) {
    plans.put(existing.Codigo__c, existing);
}
if (plans.isEmpty()) {
    List<Plano_Assinatura__c> newPlans = new List<Plano_Assinatura__c>{
        new Plano_Assinatura__c(Name = 'Básico', Codigo__c = 'NIM-BAS', Nivel__c = 1, Produto__c = productsByCode.get('NIM-LIC-BAS').Id,
            Preco_Base_Mensal__c = 120, Licencas_Minimas__c = 1, Licencas_Maximas__c = 50, Ativo__c = true),
        new Plano_Assinatura__c(Name = 'Intermediário', Codigo__c = 'NIM-INT', Nivel__c = 2, Produto__c = productsByCode.get('NIM-LIC-INT').Id,
            Preco_Base_Mensal__c = 180, Licencas_Minimas__c = 10, Licencas_Maximas__c = 200, Ativo__c = true),
        new Plano_Assinatura__c(Name = 'Enterprise', Codigo__c = 'NIM-ENT', Nivel__c = 3, Produto__c = productsByCode.get('NIM-LIC-ENT').Id,
            Preco_Base_Mensal__c = 250, Licencas_Minimas__c = 50, Licencas_Maximas__c = 1000, Ativo__c = true)
    };
    insert newPlans;
    for (Plano_Assinatura__c plan : newPlans) {
        plans.put(plan.Codigo__c, plan);
    }
}

List<Contrato_Assinatura__c> demo = [SELECT Id FROM Contrato_Assinatura__c WHERE Account__r.Name = 'Cliente Demo Nimbus' LIMIT 1];
if (demo.isEmpty()) {
    Account account = new Account(Name = 'Cliente Demo Nimbus');
    insert account;
    Contrato_Assinatura__c contract = new Contrato_Assinatura__c(
        Account__c = account.Id, Plano_Atual__c = plans.get('NIM-BAS').Id, Status__c = 'Ativo', Periodicidade__c = 'Mensal',
        Data_Inicio__c = Date.today(), Data_Fim__c = Date.today().addYears(1), Pricebook__c = standard.Id,
        Gerente_Conta__c = UserInfo.getUserId()
    );
    insert contract;

    ControlledWriteContext.Scope scope = ControlledWriteContext.open(
        new Set<Id>{ contract.Id }, 'Carga inicial de demonstracao (scripts/apex/seed-catalog.apex)'
    );
    try {
        insert new List<Item_Contrato__c>{
            new Item_Contrato__c(Contrato__c = contract.Id, Produto__c = productsByCode.get('NIM-LIC-BAS').Id, Tipo__c = 'Licença',
                Quantidade__c = 10, Preco_Unitario_Mensal__c = 120, Status__c = 'Ativo'),
            new Item_Contrato__c(Contrato__c = contract.Id, Produto__c = productsByCode.get('NIM-ADD-ANA').Id, Tipo__c = 'Recurso Adicional',
                Quantidade__c = 1, Preco_Unitario_Mensal__c = 1500, Status__c = 'Ativo')
        };
    } finally {
        scope.close();
    }
}
System.debug('Seed concluido. MRR esperado do contrato demo: 2700.00');
