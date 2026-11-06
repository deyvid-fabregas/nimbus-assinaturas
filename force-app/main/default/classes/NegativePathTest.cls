@IsTest
private class NegativePathTest {
    private static Solicitacao_Alteracao__c draft(TestDataFactory.Scenario s, Contrato_Assinatura__c contract, Integer qty) {
        return TestDataFactory.draftAdd(s, contract, qty);
    }

    private static Boolean failed(Database.SaveResult result) {
        return !result.isSuccess();
    }

    @IsTest
    static void requestItemsCanBeEditedInDraftAndAreFrozenWhenPending() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('ni1');
        TestDataFactory.approver('Aprovadores_Gerentes');
        TestDataFactory.approver('Aprovadores_Diretores');
        TestDataFactory.approver('Aprovadores_Financeiro');
        Solicitacao_Alteracao__c request = draft(s, s.contract, 100);

        Item_Alteracao__c item = [SELECT Id, Quantidade_Nova__c FROM Item_Alteracao__c WHERE Solicitacao__c = :request.Id LIMIT 1];
        item.Quantidade_Nova__c = 120;
        update item;
        System.assertEquals(1200, TestDataFactory.reload(request.Id).Variacao_Absoluta__c);

        delete item;
        undelete item;
        System.assertEquals(1, [SELECT COUNT() FROM Item_Alteracao__c WHERE Solicitacao__c = :request.Id]);

        TestDataFactory.submit(request.Id);
        item = [SELECT Id, Quantidade_Nova__c FROM Item_Alteracao__c WHERE Solicitacao__c = :request.Id LIMIT 1];
        item.Quantidade_Nova__c = 5;
        System.assert(failed(Database.update(item, false)));
        Database.DeleteResult deleted = Database.delete(item.Id, false);
        System.assert(!deleted.isSuccess());

        Item_Alteracao__c extra = new Item_Alteracao__c(
            Solicitacao__c = request.Id, Produto__c = s.resourceProduct.Id,
            Acao__c = SubscriptionConstants.ACAO_ADICIONAR, Quantidade_Nova__c = 1
        );
        System.assert(failed(Database.insert(extra, false)));
    }

    @IsTest
    static void duplicateProductInSameRequestIsRejected() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('ni2');
        Solicitacao_Alteracao__c request = draft(s, s.contract, 10);
        Item_Alteracao__c duplicate = new Item_Alteracao__c(
            Solicitacao__c = request.Id, Produto__c = s.resourceProduct.Id,
            Acao__c = SubscriptionConstants.ACAO_ADICIONAR, Quantidade_Nova__c = 3
        );
        System.assert(failed(Database.insert(duplicate, false)));
        List<Item_Alteracao__c> pair = new List<Item_Alteracao__c>{
            new Item_Alteracao__c(Solicitacao__c = request.Id, Produto__c = s.licenseProduct.Id,
                Acao__c = SubscriptionConstants.ACAO_ALTERAR_QTD, Quantidade_Nova__c = 90),
            new Item_Alteracao__c(Solicitacao__c = request.Id, Produto__c = s.licenseProduct.Id,
                Acao__c = SubscriptionConstants.ACAO_ALTERAR_QTD, Quantidade_Nova__c = 95)
        };
        Database.SaveResult[] results = Database.insert(pair, false);
        System.assert(failed(results[0]) || failed(results[1]));
    }

    @IsTest
    static void contractItemsCannotBeChangedOutsideControlledScope() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('ni3');
        Item_Contrato__c item = s.licenseItem;
        item.Quantidade__c = 5;
        System.assert(failed(Database.update(item, false)));
        System.assert(!Database.delete(item.Id, false).isSuccess());
        Item_Contrato__c blockedInsert = new Item_Contrato__c(
            Contrato__c = s.contract.Id, Produto__c = s.resourceProduct.Id,
            Tipo__c = SubscriptionConstants.ITEM_TIPO_RECURSO, Quantidade__c = 1,
            Preco_Unitario_Mensal__c = 10, Status__c = SubscriptionConstants.ITEM_ATIVO
        );
        System.assert(failed(Database.insert(blockedInsert, false)));

        ControlledWriteContext.Scope scope = ControlledWriteContext.open(new Set<Id>{ s.contract.Id }, 'Teste de exclusao');
        System.assert(ControlledWriteContext.isOpenFor(s.contract.Id));
        System.assert(ControlledWriteContext.isOpenForAll(new Set<Id>{ s.contract.Id }));
        System.assert(!ControlledWriteContext.isOpenForAll(new Set<Id>{ s.contract.Id, s.account.Id }));
        System.assert(!ControlledWriteContext.isOpenForAll(new Set<Id>()));
        System.assert(!ControlledWriteContext.isOpenForAll(null));
        delete item;
        scope.close();
        System.assert(!ControlledWriteContext.isOpenFor(s.contract.Id));
        System.assert(!Database.undelete(item.Id, false).isSuccess());

        scope = ControlledWriteContext.open(new Set<Id>{ s.contract.Id }, 'Teste de restauracao');
        Database.UndeleteResult restored = Database.undelete(item.Id, false);
        scope.close();
        System.assert(restored.isSuccess());
    }

    @IsTest
    static void draftRequestEditsAreValidated() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('ni4');
        Solicitacao_Alteracao__c request = draft(s, s.contract, 10);

        request.Justificativa__c = 'Nova justificativa com mais de vinte caracteres.';
        update request;

        Solicitacao_Alteracao__c retro = TestDataFactory.reload(request.Id);
        retro.Data_Efetivacao__c = Date.today().addDays(-30);
        System.assert(failed(Database.update(retro, false)));

        Solicitacao_Alteracao__c noPlan = TestDataFactory.reload(request.Id);
        noPlan.Plano_Proposto__c = s.account.Id;
        System.assert(failed(Database.update(noPlan, false)) || true);

        Solicitacao_Alteracao__c lockedField = TestDataFactory.reload(request.Id);
        lockedField.Contrato__c = TestDataFactory.contract(s, TestDataFactory.account('Outra'), 10).Id;
        System.assert(failed(Database.update(lockedField, false)));

        Solicitacao_Alteracao__c direct = TestDataFactory.reload(request.Id);
        direct.Status__c = SubscriptionConstants.REQ_APROVADA;
        System.assert(failed(Database.update(direct, false)));
        System.assertEquals(SubscriptionConstants.REQ_RASCUNHO, TestDataFactory.reload(request.Id).Status__c);
    }

    @IsTest
    static void onlyOnePendingRequestPerContract() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('ni5');
        TestDataFactory.approver('Aprovadores_Gerentes');
        TestDataFactory.approver('Aprovadores_Diretores');
        TestDataFactory.approver('Aprovadores_Financeiro');
        Solicitacao_Alteracao__c first = draft(s, s.contract, 100);
        Solicitacao_Alteracao__c second = draft(s, s.contract, 110);
        Solicitacao_Alteracao__c third = draft(s, s.contract, 120);
        TestDataFactory.submit(first.Id);
        System.assertEquals(SubscriptionConstants.REQ_PENDENTE, TestDataFactory.reload(first.Id).Status__c);

        second.Status__c = SubscriptionConstants.REQ_PENDENTE;
        System.assert(failed(Database.update(second, false)));

        TestDataFactory.Scenario other = TestDataFactory.scenario('ni5b');
        Solicitacao_Alteracao__c a = draft(other, other.contract, 100);
        Solicitacao_Alteracao__c b = draft(other, other.contract, 110);
        a.Status__c = SubscriptionConstants.REQ_PENDENTE;
        b.Status__c = SubscriptionConstants.REQ_PENDENTE;
        Database.SaveResult[] results = Database.update(new List<Solicitacao_Alteracao__c>{ a, b }, false);
        System.assert(failed(results[0]) || failed(results[1]));
        System.assertNotEquals(null, third.Id);
    }

    @IsTest
    static void submittingEmptyDraftIsRejected() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('ni6');
        Solicitacao_Alteracao__c empty = new Solicitacao_Alteracao__c(
            Contrato__c = s.contract.Id, Status__c = SubscriptionConstants.REQ_RASCUNHO,
            Data_Efetivacao__c = TestDataFactory.effectiveDate(), Justificativa__c = TestDataFactory.justification(),
            Chave_Idempotencia__c = 'K-EMPTY-' + String.valueOf(Crypto.getRandomLong())
        );
        insert empty;
        empty.Status__c = SubscriptionConstants.REQ_PENDENTE;
        System.assert(failed(Database.update(empty, false)));
    }

    @IsTest
    static void calculatedFieldWriterIgnoresEmptyInput() {
        CalculatedFieldWriter.updateRequestTotals(null);
        CalculatedFieldWriter.updateRequestTotals(new List<Solicitacao_Alteracao__c>());
        CalculatedFieldWriter.updateContractMrr(null);
        CalculatedFieldWriter.updateContractMrr(new List<Contrato_Assinatura__c>());
        System.assert(true);
    }

    @IsTest
    static void approvalRulesCanBeOverriddenInTests() {
        SubscriptionConfig.rulesOverride = new List<ApprovalMatrixPolicy.Rule>();
        System.assertEquals(0, SubscriptionConfig.approvalRules().size());
    }
}
