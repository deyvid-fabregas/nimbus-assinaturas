// Carga de DEMONSTRACAO adicional (idempotente): varias contas e contratos ativos com itens.
// Pre-requisito: scripts/apex/seed-catalog.apex ja executado (produtos, pricebook e planos NIM-*).
// Execucao: sf apex run --file scripts/apex/seed-contracts.apex --target-org <alias>
// Itens de contrato so podem ser gravados com o ControlledWriteContext aberto (regra US-02);
// este script e uma das tres excecoes permitidas (ApplyService, testes, seeds).

Pricebook2 standard = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
Map<String, Plano_Assinatura__c> plans = new Map<String, Plano_Assinatura__c>();
for (Plano_Assinatura__c p : [SELECT Id, Codigo__c FROM Plano_Assinatura__c WHERE Codigo__c LIKE 'NIM-%']) {
    plans.put(p.Codigo__c, p);
}
Map<String, Product2> products = new Map<String, Product2>();
for (Product2 p : [SELECT Id, ProductCode FROM Product2 WHERE ProductCode LIKE 'NIM-%']) {
    products.put(p.ProductCode, p);
}
String licenca = 'Licen\u00E7a';
String recurso = 'Recurso Adicional';

// nome da conta | plano | codigo do produto de licenca | licencas | preco | meses ate o fim | recurso adicional (ou vazio)
List<List<Object>> specs = new List<List<Object>>{
    new List<Object>{ 'Acme Tecnologia Ltda', 'NIM-BAS', 'NIM-LIC-BAS', 20, 120, 12, '' },
    new List<Object>{ 'Globex Servicos S.A.', 'NIM-INT', 'NIM-LIC-INT', 60, 180, 24, 'NIM-ADD-ANA' },
    new List<Object>{ 'Initech Sistemas', 'NIM-ENT', 'NIM-LIC-ENT', 150, 250, 12, 'NIM-ADD-SUP' },
    new List<Object>{ 'Umbrella Saude', 'NIM-INT', 'NIM-LIC-INT', 35, 180, 6, 'NIM-ADD-API' },
    new List<Object>{ 'Stark Industrias', 'NIM-ENT', 'NIM-LIC-ENT', 300, 250, 36, 'NIM-ADD-ANA' },
    new List<Object>{ 'Wayne Logistica', 'NIM-BAS', 'NIM-LIC-BAS', 8, 120, 12, '' }
};

Set<String> names = new Set<String>();
for (List<Object> s : specs) { names.add((String) s[0]); }
Set<String> existing = new Set<String>();
for (Contrato_Assinatura__c c : [SELECT Account__r.Name FROM Contrato_Assinatura__c WHERE Account__r.Name IN :names]) {
    existing.add(c.Account__r.Name);
}
Map<String, Account> accounts = new Map<String, Account>();
for (Account a : [SELECT Id, Name FROM Account WHERE Name IN :names]) { accounts.put(a.Name, a); }

List<Account> newAccounts = new List<Account>();
for (String n : names) {
    if (!accounts.containsKey(n)) { newAccounts.add(new Account(Name = n)); }
}
insert newAccounts;
for (Account a : newAccounts) { accounts.put(a.Name, a); }

Map<String, Decimal> addOnPrice = new Map<String, Decimal>{ 'NIM-ADD-ANA' => 1500, 'NIM-ADD-SUP' => 2500, 'NIM-ADD-API' => 800 };
List<Contrato_Assinatura__c> contracts = new List<Contrato_Assinatura__c>();
List<List<Object>> toCreate = new List<List<Object>>();
for (List<Object> s : specs) {
    String accountName = (String) s[0];
    if (existing.contains(accountName)) { continue; }
    contracts.add(new Contrato_Assinatura__c(
        Account__c = accounts.get(accountName).Id, Plano_Atual__c = plans.get((String) s[1]).Id, Status__c = 'Ativo',
        Periodicidade__c = 'Mensal', Data_Inicio__c = Date.today().addMonths(-3), Data_Fim__c = Date.today().addMonths((Integer) s[5]),
        Pricebook__c = standard.Id, Gerente_Conta__c = UserInfo.getUserId()
    ));
    toCreate.add(s);
}
insert contracts;

List<Item_Contrato__c> items = new List<Item_Contrato__c>();
Set<Id> contractIds = new Set<Id>();
for (Integer i = 0; i < contracts.size(); i++) {
    List<Object> s = toCreate[i];
    Id contractId = contracts[i].Id;
    contractIds.add(contractId);
    items.add(new Item_Contrato__c(
        Contrato__c = contractId, Produto__c = products.get((String) s[2]).Id, Tipo__c = licenca,
        Quantidade__c = (Integer) s[3], Preco_Unitario_Mensal__c = (Integer) s[4], Status__c = 'Ativo'
    ));
    String addOn = (String) s[6];
    if (String.isNotBlank(addOn)) {
        items.add(new Item_Contrato__c(
            Contrato__c = contractId, Produto__c = products.get(addOn).Id, Tipo__c = recurso,
            Quantidade__c = 1, Preco_Unitario_Mensal__c = addOnPrice.get(addOn), Status__c = 'Ativo'
        ));
    }
}
ControlledWriteContext.Scope scope = ControlledWriteContext.open(contractIds, 'Carga de demonstracao (scripts/apex/seed-contracts.apex)');
try {
    insert items;
} finally {
    scope.close();
}
System.debug('Seed de contratos concluido: ' + contracts.size() + ' contratos novos.');
