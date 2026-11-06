@IsTest
private class SubscriptionChangeTest {
    private static SubscriptionChangeRequestDTO dto(TestDataFactory.Scenario s, String action, Id productId, Decimal qty) {
        SubscriptionChangeRequestDTO d = new SubscriptionChangeRequestDTO();
        d.contractId = s.contract.Id;
        d.effectiveDate = TestDataFactory.effectiveDate();
        d.justification = TestDataFactory.justification();
        d.idempotencyKey = 'KEY-' + String.valueOf(Crypto.getRandomLong());
        d.items.add(SubscriptionChangeRequestDTO.item(productId, action, qty));
        return d;
    }

    @IsTest
    static void simulateAddResourceAutomatic() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('sim');
        SubscriptionChangeResultDTO r = SubscriptionChangeController.simulate(dto(s, SubscriptionConstants.ACAO_ADICIONAR, s.resourceProduct.Id, 50));
        System.assertEquals(true, r.success, '' + r.message);
        System.assertEquals(10000, r.baseMrr);
        System.assertEquals(10500, r.proposedMrr);
        System.assertEquals(500, r.absoluteVariation);
        System.assertEquals(5, r.percentVariation);
        System.assertEquals(SubscriptionConstants.NIVEL_AUTOMATICA, r.approvalLevel);
        System.assertEquals(false, r.blocked);
        System.assertEquals(1, r.lines.size());
        System.assertEquals(0, [SELECT COUNT() FROM Solicitacao_Alteracao__c]);
    }

    @IsTest
    static void simulateLevelsAndBlocked() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('lev');
        SubscriptionChangeResultDTO mgr = SubscriptionChangeController.simulate(dto(s, SubscriptionConstants.ACAO_ADICIONAR, s.resourceProduct.Id, 100));
        System.assertEquals(SubscriptionConstants.NIVEL_GERENTE, mgr.approvalLevel);
        SubscriptionChangeResultDTO dir = SubscriptionChangeController.simulate(dto(s, SubscriptionConstants.ACAO_ADICIONAR, s.resourceProduct.Id, 200));
        System.assertEquals(SubscriptionConstants.NIVEL_DIRETOR, dir.approvalLevel);
        SubscriptionChangeResultDTO fin = SubscriptionChangeController.simulate(dto(s, SubscriptionConstants.ACAO_ADICIONAR, s.resourceProduct.Id, 400));
        System.assertEquals(SubscriptionConstants.NIVEL_FINANCEIRO, fin.approvalLevel);
        SubscriptionChangeResultDTO blocked = SubscriptionChangeController.simulate(dto(s, SubscriptionConstants.ACAO_ADICIONAR, s.resourceProduct.Id, 600));
        System.assertEquals(true, blocked.blocked, 'bloqueada acima de 50%');
    }

    @IsTest
    static void reductionAndRemoval() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('red');
        SubscriptionChangeResultDTO small = SubscriptionChangeController.simulate(dto(s, SubscriptionConstants.ACAO_ALTERAR_QTD, s.licenseProduct.Id, 95));
        System.assertEquals(-500, small.absoluteVariation);
        System.assertNotEquals(SubscriptionConstants.NIVEL_AUTOMATICA, small.approvalLevel, 'reducao nunca automatica');
        SubscriptionChangeResultDTO big = SubscriptionChangeController.simulate(dto(s, SubscriptionConstants.ACAO_ALTERAR_QTD, s.licenseProduct.Id, 60));
        System.assertEquals(SubscriptionConstants.NIVEL_FINANCEIRO, big.approvalLevel);
        System.assertEquals(SubscriptionConstants.ERR_LIMITE_LICENCAS, SubscriptionChangeController.simulate(dto(s, SubscriptionConstants.ACAO_REMOVER, s.licenseProduct.Id, 0)).errorCode);
        ControlledWriteContext.Scope scope = ControlledWriteContext.open(new Set<Id>{ s.contract.Id }, 'Seed');
        try {
            insert new Item_Contrato__c(
                Contrato__c = s.contract.Id, Produto__c = s.resourceProduct.Id, Tipo__c = SubscriptionConstants.ITEM_TIPO_RECURSO,
                Quantidade__c = 20, Preco_Unitario_Mensal__c = 10, Status__c = SubscriptionConstants.ITEM_ATIVO
            );
        } finally {
            scope.close();
        }
        SubscriptionChangeResultDTO removal = SubscriptionChangeController.simulate(dto(s, SubscriptionConstants.ACAO_REMOVER, s.resourceProduct.Id, 0));
        System.assertEquals(-200, removal.absoluteVariation);
        SubscriptionChangeResultDTO noQty = SubscriptionChangeController.simulate(dto(s, SubscriptionConstants.ACAO_REMOVER, s.resourceProduct.Id, null));
        System.assertEquals(-200, noQty.absoluteVariation);
    }

    @IsTest
    static void simulateNegativeCases() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('neg');
        System.assertEquals(SubscriptionConstants.ERR_QUANTIDADE_INVALIDA, SubscriptionChangeController.simulate(dto(s, SubscriptionConstants.ACAO_ADICIONAR, s.resourceProduct.Id, -5)).errorCode);
        System.assertEquals(SubscriptionConstants.ERR_QUANTIDADE_INVALIDA, SubscriptionChangeController.simulate(dto(s, SubscriptionConstants.ACAO_ADICIONAR, s.resourceProduct.Id, 1.5)).errorCode);
        System.assertEquals(SubscriptionConstants.ERR_QUANTIDADE_INVALIDA, SubscriptionChangeController.simulate(dto(s, SubscriptionConstants.ACAO_ADICIONAR, s.resourceProduct.Id, 0)).errorCode);
        System.assertEquals(SubscriptionConstants.ERR_QUANTIDADE_INVALIDA, SubscriptionChangeController.simulate(dto(s, SubscriptionConstants.ACAO_ALTERAR_QTD, s.licenseProduct.Id, 100)).errorCode);
        System.assertEquals(SubscriptionConstants.ERR_QUANTIDADE_INVALIDA, SubscriptionChangeController.simulate(dto(s, SubscriptionConstants.ACAO_REMOVER, s.licenseProduct.Id, 3)).errorCode);
        System.assertEquals(SubscriptionConstants.ERR_ACAO_INVALIDA, SubscriptionChangeController.simulate(dto(s, 'Inexistente', s.licenseProduct.Id, 3)).errorCode);
        System.assertEquals(SubscriptionConstants.ERR_PRODUTO_DUPLICADO, SubscriptionChangeController.simulate(dto(s, SubscriptionConstants.ACAO_ADICIONAR, s.licenseProduct.Id, 3)).errorCode);
        System.assertEquals(SubscriptionConstants.ERR_ITEM_NAO_ENCONTRADO, SubscriptionChangeController.simulate(dto(s, SubscriptionConstants.ACAO_ALTERAR_QTD, s.resourceProduct.Id, 3)).errorCode);
        System.assertEquals(SubscriptionConstants.ERR_ENTRADA_INVALIDA, SubscriptionChangeController.simulate(dto(s, SubscriptionConstants.ACAO_ADICIONAR, null, 3)).errorCode);

        Product2 noPrice = TestDataFactory.product('Sem preco', false, 0);
        System.assertEquals(SubscriptionConstants.ERR_PRECO_AUSENTE, SubscriptionChangeController.simulate(dto(s, SubscriptionConstants.ACAO_ADICIONAR, noPrice.Id, 3)).errorCode);

        SubscriptionChangeRequestDTO badDate = dto(s, SubscriptionConstants.ACAO_ADICIONAR, s.resourceProduct.Id, 3);
        badDate.effectiveDate = SubscriptionClock.today().addDays(-1);
        System.assertEquals(SubscriptionConstants.ERR_DATA_RETROATIVA, SubscriptionChangeController.simulate(badDate).errorCode);
        badDate.effectiveDate = SubscriptionClock.today().addDays(400);
        System.assertEquals(SubscriptionConstants.ERR_DATA_FORA_JANELA, SubscriptionChangeController.simulate(badDate).errorCode);

        SubscriptionChangeRequestDTO noContract = dto(s, SubscriptionConstants.ACAO_ADICIONAR, s.resourceProduct.Id, 3);
        noContract.contractId = null;
        System.assertEquals(false, SubscriptionChangeController.simulate(noContract).success);
        System.assertEquals(false, SubscriptionChangeController.simulate(null).success);
        System.assertEquals(false, SubscriptionChangeController.saveDraft(null).success);
    }

    @IsTest
    static void saveDraftAndIdempotency() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('sav');
        SubscriptionChangeRequestDTO d = dto(s, SubscriptionConstants.ACAO_ADICIONAR, s.resourceProduct.Id, 50);
        SubscriptionChangeResultDTO first = SubscriptionChangeController.saveDraft(d);
        System.assertEquals(true, first.success, '' + first.message);
        System.assertEquals(false, first.reusedExisting);
        System.assertNotEquals(null, first.requestId);
        Solicitacao_Alteracao__c saved = TestDataFactory.reload(first.requestId);
        System.assertEquals(SubscriptionConstants.REQ_RASCUNHO, saved.Status__c);
        System.assertEquals(10000, saved.MRR_Base__c);
        System.assertEquals(10500, saved.MRR_Proposto__c);

        SubscriptionChangeResultDTO again = SubscriptionChangeController.saveDraft(d);
        System.assertEquals(true, again.success);
        System.assertEquals(true, again.reusedExisting);
        System.assertEquals(first.requestId, again.requestId);
        System.assertEquals(1, [SELECT COUNT() FROM Solicitacao_Alteracao__c]);

        SubscriptionChangeRequestDTO noKey = dto(s, SubscriptionConstants.ACAO_ADICIONAR, s.resourceProduct.Id, 50);
        noKey.idempotencyKey = null;
        System.assertEquals(SubscriptionConstants.ERR_CHAVE_IDEMPOTENCIA, SubscriptionChangeController.saveDraft(noKey).errorCode);
    }

    @IsTest
    static void editDraftReplacesItems() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('edt');
        SubscriptionChangeResultDTO first = SubscriptionChangeController.saveDraft(dto(s, SubscriptionConstants.ACAO_ADICIONAR, s.resourceProduct.Id, 50));
        SubscriptionChangeRequestDTO edit = dto(s, SubscriptionConstants.ACAO_ADICIONAR, s.resourceProduct.Id, 100);
        edit.requestId = first.requestId;
        SubscriptionChangeResultDTO second = SubscriptionChangeController.saveDraft(edit);
        System.assertEquals(true, second.success, '' + second.message);
        System.assertEquals(first.requestId, second.requestId);
        Solicitacao_Alteracao__c saved = TestDataFactory.reload(first.requestId);
        System.assertEquals(10, saved.Variacao_Percentual__c.intValue());
        System.assertEquals(1, [SELECT COUNT() FROM Item_Alteracao__c WHERE Solicitacao__c = :first.requestId]);

        TestDataFactory.approver('Aprovadores_Gerentes');
        TestDataFactory.submit(first.requestId);
        SubscriptionChangeRequestDTO late = dto(s, SubscriptionConstants.ACAO_ADICIONAR, s.resourceProduct.Id, 20);
        late.requestId = first.requestId;
        System.assertEquals(false, SubscriptionChangeController.saveDraft(late).success);

        SubscriptionChangeRequestDTO missing = dto(s, SubscriptionConstants.ACAO_ADICIONAR, s.resourceProduct.Id, 20);
        missing.requestId = s.contract.Id;
        System.assertEquals(false, SubscriptionChangeController.saveDraft(missing).success);
    }

    @IsTest
    static void saveDraftValidations() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('val');
        SubscriptionChangeRequestDTO shortJust = dto(s, SubscriptionConstants.ACAO_ADICIONAR, s.resourceProduct.Id, 50);
        shortJust.justification = 'curta';
        System.assertEquals(SubscriptionConstants.ERR_JUSTIFICATIVA_CURTA, SubscriptionChangeController.saveDraft(shortJust).errorCode);
        SubscriptionChangeRequestDTO noDate = dto(s, SubscriptionConstants.ACAO_ADICIONAR, s.resourceProduct.Id, 50);
        noDate.effectiveDate = null;
        System.assertEquals(SubscriptionConstants.ERR_DATA_OBRIGATORIA, SubscriptionChangeController.saveDraft(noDate).errorCode);
        SubscriptionChangeResultDTO blocked = SubscriptionChangeController.saveDraft(dto(s, SubscriptionConstants.ACAO_ADICIONAR, s.resourceProduct.Id, 600));
        System.assertEquals(false, blocked.success);
        System.assertEquals(0, [SELECT COUNT() FROM Solicitacao_Alteracao__c]);
        SubscriptionChangeRequestDTO empty = dto(s, SubscriptionConstants.ACAO_ADICIONAR, s.resourceProduct.Id, 50);
        empty.items.clear();
        System.assertEquals(false, SubscriptionChangeController.saveDraft(empty).success);
        SubscriptionChangeRequestDTO dup = dto(s, SubscriptionConstants.ACAO_ADICIONAR, s.resourceProduct.Id, 5);
        dup.items.add(SubscriptionChangeRequestDTO.item(s.resourceProduct.Id, SubscriptionConstants.ACAO_ADICIONAR, 6));
        System.assertEquals(false, SubscriptionChangeController.saveDraft(dup).success);
    }

    @IsTest
    static void inactiveContractAndPlanChange() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('pln');
        Product2 premiumProduct = TestDataFactory.product('Premium', true, 150);
        Plano_Assinatura__c premium = TestDataFactory.plan('PRE-pln', 2, 150, premiumProduct);
        SubscriptionChangeRequestDTO d = dto(s, SubscriptionConstants.ACAO_ALTERAR_QTD, s.licenseProduct.Id, 110);
        d.proposedPlanId = premium.Id;
        SubscriptionChangeResultDTO r = SubscriptionChangeController.simulate(d);
        System.assertNotEquals(null, r);
        SubscriptionChangeRequestDTO same = dto(s, SubscriptionConstants.ACAO_ADICIONAR, s.resourceProduct.Id, 10);
        same.proposedPlanId = s.basicPlan.Id;
        System.assertNotEquals(null, SubscriptionChangeController.simulate(same));
        SubscriptionChangeRequestDTO invalidPlan = dto(s, SubscriptionConstants.ACAO_ADICIONAR, s.resourceProduct.Id, 10);
        invalidPlan.proposedPlanId = s.contract.Id;
        System.assertEquals(false, SubscriptionChangeController.simulate(invalidPlan).success);

        premium.Ativo__c = false;
        update premium;
        d.proposedPlanId = premium.Id;
        System.assertEquals(false, SubscriptionChangeController.simulate(d).success);

        Contrato_Assinatura__c c = new Contrato_Assinatura__c(Id = s.contract.Id, Status__c = 'Encerrado');
        update c;
        System.assertEquals(SubscriptionConstants.ERR_CONTRATO_NAO_ATIVO, SubscriptionChangeController.simulate(dto(s, SubscriptionConstants.ACAO_ADICIONAR, s.resourceProduct.Id, 3)).errorCode);
    }

    @IsTest
    static void loadContext() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('ctx');
        SubscriptionChangeController.ContextDTO ctx = SubscriptionChangeController.loadContext(s.contract.Id);
        System.assertEquals(true, ctx.success, '' + ctx.message);
        System.assertEquals(s.contract.Id, ctx.contractId);
        System.assert(!ctx.items.isEmpty());
        System.assert(!ctx.plans.isEmpty());
        System.assertEquals(false, SubscriptionChangeController.loadContext(null).success);
        System.assertEquals(false, SubscriptionChangeController.loadContext(s.account.Id).success);
    }

    @IsTest
    static void sellerCanSaveDraftAndViewerCannot() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('sec');
        User seller = TestDataFactory.seller();
        User noAccess = TestDataFactory.user('semps', new List<String>(), new List<String>());
        SubscriptionChangeRequestDTO d = dto(s, SubscriptionConstants.ACAO_ADICIONAR, s.resourceProduct.Id, 50);
        System.runAs(seller) {
            SubscriptionChangeResultDTO r = SubscriptionChangeController.saveDraft(d);
            System.assertEquals(true, r.success, '' + r.message);
        }
        System.runAs(noAccess) {
            SubscriptionChangeResultDTO r = SubscriptionChangeController.saveDraft(dto(s, SubscriptionConstants.ACAO_ADICIONAR, s.resourceProduct.Id, 50));
            System.assertEquals(false, r.success);
            System.assertEquals(false, SubscriptionChangeController.simulate(d).success);
        }
    }

    @IsTest
    static void unexpectedFailureRollsBackAndLogs() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('exc');
        SubscriptionChangeRequestDTO d = dto(s, SubscriptionConstants.ACAO_ADICIONAR, s.resourceProduct.Id, 50);
        d.idempotencyKey = 'K'.rightPad(400, 'x');
        SubscriptionChangeResultDTO r = SubscriptionChangeController.saveDraft(d);
        System.assertEquals(false, r.success);
        System.assertEquals(0, [SELECT COUNT() FROM Solicitacao_Alteracao__c]);
        System.assert([SELECT COUNT() FROM Log_Tecnico__c] >= 1, 'log sobrevive ao rollback');
    }
}
