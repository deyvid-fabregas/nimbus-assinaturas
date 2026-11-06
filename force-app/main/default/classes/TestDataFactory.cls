/**
 * @description Fabrica de dados de teste (somente @IsTest). Sem SeeAllData e sem Ids fixos.
 *              Cenario padrao: contrato Ativo com 100 licencas a R$ 100 (MRR base = 10.000,00).
 */
@IsTest
public class TestDataFactory {
    public static final Decimal LICENSE_PRICE = 100;
    public static final Integer LICENSE_QTY = 100;
    public static final Decimal RESOURCE_PRICE = 10;

    public class Scenario {
        public Account account;
        public Product2 licenseProduct;
        public Product2 resourceProduct;
        public Plano_Assinatura__c basicPlan;
        public Contrato_Assinatura__c contract;
        public Item_Contrato__c licenseItem;
        public Id pricebookId;
    }

    public static Account account(String name) {
        Account record = new Account(Name = name);
        insert record;
        return record;
    }

    public static Product2 product(String name, Boolean withPrice, Decimal price) {
        Product2 product = new Product2(Name = name, IsActive = true);
        insert product;
        if (withPrice) {
            insert new PricebookEntry(
                Pricebook2Id = Test.getStandardPricebookId(), Product2Id = product.Id, UnitPrice = price, IsActive = true
            );
        }
        return product;
    }

    public static Plano_Assinatura__c plan(String code, Integer level, Decimal basePrice, Product2 product) {
        Plano_Assinatura__c plan = new Plano_Assinatura__c(
            Name = 'Plano ' + code,
            Codigo__c = code,
            Nivel__c = level,
            Preco_Base_Mensal__c = basePrice,
            Licencas_Minimas__c = 1,
            Licencas_Maximas__c = 100000,
            Ativo__c = true,
            Produto__c = product.Id
        );
        insert plan;
        return plan;
    }

    /** O runner de teste recebe o PS Administrador (FLS dos campos custom); nao concede Custom Permissions. */
    public static void grantRunner() {
        Id runnerId = UserInfo.getUserId();
        if ([SELECT COUNT() FROM PermissionSetAssignment WHERE AssigneeId = :runnerId AND PermissionSet.Name = 'Assinatura_Administrador'] > 0) {
            return;
        }
        for (PermissionSet ps : [SELECT Id FROM PermissionSet WHERE Name = 'Assinatura_Administrador']) {
            insert new PermissionSetAssignment(AssigneeId = runnerId, PermissionSetId = ps.Id);
        }
    }

    public static Scenario scenario(String suffix) {
        grantRunner();
        Scenario s = new Scenario();
        s.pricebookId = Test.getStandardPricebookId();
        s.account = account('Conta ' + suffix);
        s.licenseProduct = product('Licenca ' + suffix, true, LICENSE_PRICE);
        s.resourceProduct = product('Recurso ' + suffix, true, RESOURCE_PRICE);
        s.basicPlan = plan('BAS-' + suffix, 1, LICENSE_PRICE, s.licenseProduct);
        s.contract = contract(s, s.account, LICENSE_QTY);
        s.licenseItem = [SELECT Id, Quantidade__c, Preco_Unitario_Mensal__c FROM Item_Contrato__c WHERE Contrato__c = :s.contract.Id LIMIT 1];
        return s;
    }

    /** Contrato Ativo com um item de licenca (escrita aberta via ControlledWriteContext). */
    public static Contrato_Assinatura__c contract(Scenario s, Account account, Integer licenseQty) {
        Contrato_Assinatura__c contract = new Contrato_Assinatura__c(
            Account__c = account.Id,
            Plano_Atual__c = s.basicPlan.Id,
            Status__c = 'Ativo',
            Periodicidade__c = 'Mensal',
            Data_Inicio__c = Date.today().addMonths(-1),
            Pricebook__c = s.pricebookId
        );
        insert contract;
        ControlledWriteContext.Scope scope = ControlledWriteContext.open(new Set<Id>{ contract.Id }, 'Seed de teste');
        try {
            insert new Item_Contrato__c(
                Contrato__c = contract.Id,
                Produto__c = s.licenseProduct.Id,
                Tipo__c = SubscriptionConstants.ITEM_TIPO_LICENCA,
                Quantidade__c = licenseQty,
                Preco_Unitario_Mensal__c = LICENSE_PRICE,
                Status__c = SubscriptionConstants.ITEM_ATIVO
            );
        } finally {
            scope.close();
        }
        return contract;
    }

    /** Insere contratos adicionais em lote (1 item de licenca cada). */
    public static List<Contrato_Assinatura__c> contracts(Scenario s, Integer count) {
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < count; i++) {
            accounts.add(new Account(Name = 'Bulk ' + i));
        }
        insert accounts;
        List<Contrato_Assinatura__c> list1 = new List<Contrato_Assinatura__c>();
        for (Account acc : accounts) {
            list1.add(new Contrato_Assinatura__c(
                Account__c = acc.Id, Plano_Atual__c = s.basicPlan.Id, Status__c = 'Ativo', Periodicidade__c = 'Mensal',
                Data_Inicio__c = Date.today().addMonths(-1), Pricebook__c = s.pricebookId
            ));
        }
        insert list1;
        Set<Id> ids = new Map<Id, Contrato_Assinatura__c>(list1).keySet();
        ControlledWriteContext.Scope scope = ControlledWriteContext.open(ids, 'Seed de teste em lote');
        try {
            List<Item_Contrato__c> items = new List<Item_Contrato__c>();
            for (Contrato_Assinatura__c c : list1) {
                items.add(new Item_Contrato__c(
                    Contrato__c = c.Id, Produto__c = s.licenseProduct.Id, Tipo__c = SubscriptionConstants.ITEM_TIPO_LICENCA,
                    Quantidade__c = LICENSE_QTY, Preco_Unitario_Mensal__c = LICENSE_PRICE, Status__c = SubscriptionConstants.ITEM_ATIVO
                ));
            }
            insert items;
        } finally {
            scope.close();
        }
        return list1;
    }

    public static Date effectiveDate() {
        return SubscriptionClock.today().addDays(5);
    }

    public static String justification() {
        return 'Justificativa de teste com mais de vinte caracteres.';
    }

    /** Rascunho com um item "Adicionar recurso" de qty unidades (delta MRR = qty x preco do recurso). */
    public static Solicitacao_Alteracao__c draftAdd(Scenario s, Contrato_Assinatura__c contract, Integer qty) {
        return draftWithItems(contract, new List<Item_Alteracao__c>{
            new Item_Alteracao__c(
                Produto__c = s.resourceProduct.Id, Acao__c = SubscriptionConstants.ACAO_ADICIONAR, Quantidade_Nova__c = qty
            )
        });
    }

    public static Solicitacao_Alteracao__c draftWithItems(Contrato_Assinatura__c contract, List<Item_Alteracao__c> items) {
        Solicitacao_Alteracao__c request = new Solicitacao_Alteracao__c(
            Contrato__c = contract.Id,
            Status__c = SubscriptionConstants.REQ_RASCUNHO,
            Data_Efetivacao__c = effectiveDate(),
            Justificativa__c = justification(),
            Chave_Idempotencia__c = 'K-' + String.valueOf(Crypto.getRandomLong())
        );
        insert request;
        for (Item_Alteracao__c item : items) {
            item.Solicitacao__c = request.Id;
        }
        insert items;
        return reload(request.Id);
    }

    public static Solicitacao_Alteracao__c reload(Id requestId) {
        return [
            SELECT Id, Name, Status__c, Nivel_Aprovacao__c, Ciclo_Aprovacao__c, MRR_Base__c, MRR_Proposto__c,
                   Variacao_Absoluta__c, Variacao_Percentual__c, Contrato__c, CreatedById, Data_Efetivacao__c,
                   Versao_Contrato_Base__c, Tipo__c, Motivo_Rejeicao__c
            FROM Solicitacao_Alteracao__c WHERE Id = :requestId
        ];
    }

    public static void submit(Id requestId) {
        update new Solicitacao_Alteracao__c(Id = requestId, Status__c = SubscriptionConstants.REQ_PENDENTE);
    }

    /** Usuario ativo com os Permission Sets e grupos publicos indicados (DML de setup isolada em runAs). */
    public static User user(String alias, List<String> permissionSets, List<String> groups) {
        User admin = new User(Id = UserInfo.getUserId());
        User created;
        System.runAs(admin) {
            Profile profile = [SELECT Id FROM Profile WHERE UserType = 'Standard' AND Name IN ('Standard User', 'Usuário padrão', 'Usuario padrao') LIMIT 1];
            String uniq = alias + String.valueOf(Crypto.getRandomLong()).replace('-', 'x').left(8);
            created = new User(
                Alias = alias.left(8), Email = uniq + '@nimbus-test.example.com', Username = uniq + '@nimbus-test.example.com',
                LastName = 'Teste ' + alias, ProfileId = profile.Id, EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US',
                LocaleSidKey = 'en_US', TimeZoneSidKey = 'America/Sao_Paulo', IsActive = true
            );
            insert created;
            List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
            for (PermissionSet ps : [SELECT Id FROM PermissionSet WHERE Name IN :permissionSets]) {
                assignments.add(new PermissionSetAssignment(AssigneeId = created.Id, PermissionSetId = ps.Id));
            }
            insert assignments;
            List<GroupMember> members = new List<GroupMember>();
            for (Group grp : [SELECT Id FROM Group WHERE Type = 'Regular' AND DeveloperName IN :groups]) {
                members.add(new GroupMember(GroupId = grp.Id, UserOrGroupId = created.Id));
            }
            insert members;
        }
        return created;
    }

    public static User seller() {
        return user('vend', new List<String>{ 'Assinatura_Vendedor' }, new List<String>());
    }

    public static User approver(String group1) {
        return user('apr', new List<String>{ 'Assinatura_Aprovador' }, new List<String>{ group1 });
    }

    public static User administrator() {
        return user('adm', new List<String>{ 'Assinatura_Administrador' }, new List<String>());
    }
}
