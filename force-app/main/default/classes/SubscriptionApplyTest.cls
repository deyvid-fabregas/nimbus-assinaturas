@IsTest
private class SubscriptionApplyTest {

    private static Contrato_Assinatura__c newContract(TestDataFactory.Scenario s, String label) {
        return TestDataFactory.contract(s, TestDataFactory.account('Conta ' + label), TestDataFactory.LICENSE_QTY);
    }

    /** Resource de 50 unidades (5%, R$ 500): aprovacao automatica. */
    private static Solicitacao_Alteracao__c approvedRequest(TestDataFactory.Scenario s, Contrato_Assinatura__c contract, Integer qty) {
        Solicitacao_Alteracao__c r = TestDataFactory.draftAdd(s, contract, qty);
        TestDataFactory.submit(r.Id);
        Solicitacao_Alteracao__c reloaded = TestDataFactory.reload(r.Id);
        System.assertEquals(SubscriptionConstants.REQ_APROVADA, reloaded.Status__c);
        return reloaded;
    }

    private static Solicitacao_Alteracao__c pendingRequest(Solicitacao_Alteracao__c draft) {
        TestDataFactory.submit(draft.Id);
        Solicitacao_Alteracao__c reloaded = TestDataFactory.reload(draft.Id);
        System.assertEquals(SubscriptionConstants.REQ_PENDENTE, reloaded.Status__c);
        return reloaded;
    }

    private static Solicitacao_Alteracao__c approvedByGroup(String group1, Solicitacao_Alteracao__c draft) {
        User approver = TestDataFactory.approver(group1);
        Solicitacao_Alteracao__c pending = pendingRequest(draft);
        System.runAs(approver) {
            SubscriptionDecisionService.Outcome o = new SubscriptionDecisionService().approve(pending.Id, pending.Ciclo_Aprovacao__c);
            System.assertEquals(true, o.success, o.message);
        }
        Solicitacao_Alteracao__c reloaded = TestDataFactory.reload(pending.Id);
        System.assertEquals(SubscriptionConstants.REQ_APROVADA, reloaded.Status__c);
        return reloaded;
    }

    private static void applicableToday() {
        SubscriptionClock.todayOverride = TestDataFactory.effectiveDate().addDays(1);
    }

    private static SubscriptionApplyResultDTO applyAs(User user, Id requestId) {
        SubscriptionApplyResultDTO out;
        System.runAs(user) {
            out = new SubscriptionApplyService().apply(requestId);
        }
        return out;
    }

    private static String describe(SubscriptionApplyResultDTO out) {
        String text = out.code + ': ' + out.message;
        for (Log_Tecnico__c log : [SELECT Mensagem__c, Stack_Trace__c FROM Log_Tecnico__c LIMIT 1]) {
            text += ' | ' + log.Mensagem__c + ' | ' + log.Stack_Trace__c;
        }
        return text;
    }

    private static Contrato_Assinatura__c contractState(Id contractId) {
        return [SELECT Id, MRR_Atual__c, Versao__c, Plano_Atual__c FROM Contrato_Assinatura__c WHERE Id = :contractId];
    }

    private static Solicitacao_Alteracao__c planChangeDraft(TestDataFactory.Scenario s, Plano_Assinatura__c target, Integer licenses) {
        SubscriptionChangeRequestDTO dto = new SubscriptionChangeRequestDTO();
        dto.contractId = s.contract.Id;
        dto.proposedPlanId = target.Id;
        dto.effectiveDate = TestDataFactory.effectiveDate();
        dto.justification = TestDataFactory.justification();
        dto.idempotencyKey = 'PLN-' + String.valueOf(Crypto.getRandomLong());
        dto.items.add(SubscriptionChangeRequestDTO.item(s.licenseProduct.Id, SubscriptionConstants.ACAO_ALTERAR_QTD, licenses));
        SubscriptionChangeResultDTO saved = new SubscriptionChangeService().saveDraft(dto);
        System.assertEquals(true, saved.success, '' + saved.message);
        return TestDataFactory.reload(saved.requestId);
    }

    @IsTest
    static void appliesApprovedRequestAndIsIdempotent() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('apl');
        User seller = TestDataFactory.seller();
        Solicitacao_Alteracao__c r = approvedRequest(s, s.contract, 50);
        applicableToday();

        SubscriptionApplyResultDTO first = applyAs(seller, r.Id);
        System.assertEquals(true, first.success, '' + first.message);
        System.assertEquals(false, first.alreadyApplied);
        System.assertEquals(SubscriptionConstants.REQ_APLICADA, first.status);
        System.assertEquals(1, first.contractVersion);
        System.assertEquals(10500, first.newMrr);
        System.assertNotEquals(null, first.orderId);
        System.assertNotEquals(null, first.additiveId);

        Contrato_Assinatura__c contract = contractState(s.contract.Id);
        System.assertEquals(10500, contract.MRR_Atual__c);
        System.assertEquals(1, contract.Versao__c);
        System.assertEquals(SubscriptionConstants.REQ_APLICADA, TestDataFactory.reload(r.Id).Status__c);

        Aditivo_Contrato__c additive = [
            SELECT Chave_Unica__c, Versao_Resultante__c, MRR_Anterior__c, MRR_Novo__c, Order__c
            FROM Aditivo_Contrato__c WHERE Solicitacao__c = :r.Id
        ];
        System.assertEquals(AdditiveSelector.uniqueKey(r.Id, r.Ciclo_Aprovacao__c), additive.Chave_Unica__c);
        System.assertEquals(1, additive.Versao_Resultante__c);
        System.assertEquals(10000, additive.MRR_Anterior__c);
        System.assertEquals(10500, additive.MRR_Novo__c);
        System.assertEquals(first.orderId, additive.Order__c);

        List<OrderItem> orderItems = [SELECT Quantity, UnitPrice FROM OrderItem WHERE OrderId = :first.orderId];
        System.assertEquals(1, orderItems.size());
        System.assertEquals(50, orderItems[0].Quantity);
        System.assertEquals(10, orderItems[0].UnitPrice);
        System.assertEquals(SubscriptionConstants.ORDER_STATUS_DRAFT, [SELECT Status FROM Order WHERE Id = :first.orderId].Status);
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Item_Contrato__c WHERE Contrato__c = :s.contract.Id AND Tipo__c = :SubscriptionConstants.ITEM_TIPO_RECURSO AND Quantidade__c = 50]
        );

        SubscriptionApplyResultDTO second;
        System.runAs(seller) {
            second = SubscriptionApplyController.apply(r.Id);
        }
        System.assertEquals(true, second.success);
        System.assertEquals(true, second.alreadyApplied);
        System.assertEquals(first.additiveId, second.additiveId);
        System.assertEquals(first.orderId, second.orderId);
        System.assertEquals(1, second.contractVersion);
        System.assertEquals(1, [SELECT COUNT() FROM Aditivo_Contrato__c WHERE Solicitacao__c = :r.Id]);
        System.assertEquals(1, [SELECT COUNT() FROM Order]);
        System.assertEquals(1, contractState(s.contract.Id).Versao__c);
    }

    @IsTest
    static void appliesQuantityChange() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('qty');
        User seller = TestDataFactory.seller();
        Solicitacao_Alteracao__c draft = TestDataFactory.draftWithItems(s.contract, new List<Item_Alteracao__c>{
            new Item_Alteracao__c(Produto__c = s.licenseProduct.Id, Acao__c = SubscriptionConstants.ACAO_ALTERAR_QTD, Quantidade_Nova__c = 110)
        });
        Solicitacao_Alteracao__c r = approvedByGroup('Aprovadores_Gerentes', draft);
        applicableToday();

        SubscriptionApplyResultDTO out = applyAs(seller, r.Id);
        System.assertEquals(true, out.success, describe(out));
        System.assertEquals(11000, contractState(s.contract.Id).MRR_Atual__c);
        System.assertEquals(110, [SELECT Quantidade__c FROM Item_Contrato__c WHERE Id = :s.licenseItem.Id].Quantidade__c);
        OrderItem line = [SELECT Quantity, UnitPrice, Description FROM OrderItem WHERE OrderId = :out.orderId];
        System.assertEquals(10, line.Quantity);
        System.assertEquals(100, line.UnitPrice);
        System.assert(line.Description.contains('de 100 para 110'), line.Description);
    }

    @IsTest
    static void appliesRemoval() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('rem');
        User seller = TestDataFactory.seller();
        ControlledWriteContext.Scope scope = ControlledWriteContext.open(new Set<Id>{ s.contract.Id }, 'Seed de teste');
        try {
            insert new Item_Contrato__c(
                Contrato__c = s.contract.Id, Produto__c = s.resourceProduct.Id, Tipo__c = SubscriptionConstants.ITEM_TIPO_RECURSO,
                Quantidade__c = 20, Preco_Unitario_Mensal__c = TestDataFactory.RESOURCE_PRICE, Status__c = SubscriptionConstants.ITEM_ATIVO
            );
        } finally {
            scope.close();
        }
        Solicitacao_Alteracao__c draft = TestDataFactory.draftWithItems(s.contract, new List<Item_Alteracao__c>{
            new Item_Alteracao__c(Produto__c = s.resourceProduct.Id, Acao__c = SubscriptionConstants.ACAO_REMOVER, Quantidade_Nova__c = 0)
        });
        Solicitacao_Alteracao__c r = approvedByGroup('Aprovadores_Gerentes', draft);
        applicableToday();

        SubscriptionApplyResultDTO out = applyAs(seller, r.Id);
        System.assertEquals(true, out.success, describe(out));
        System.assertEquals(10000, contractState(s.contract.Id).MRR_Atual__c);
        System.assertEquals(
            SubscriptionConstants.ITEM_REMOVIDO,
            [SELECT Status__c FROM Item_Contrato__c WHERE Contrato__c = :s.contract.Id AND Produto__c = :s.resourceProduct.Id].Status__c
        );
        System.assertEquals(-20, [SELECT Quantity FROM OrderItem WHERE OrderId = :out.orderId].Quantity);
    }

    @IsTest
    static void appliesPlanUpgradeAndKeepsApprovalMatrix() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('upg');
        User seller = TestDataFactory.seller();
        Product2 premiumProduct = TestDataFactory.product('Premium upg', true, 150);
        Plano_Assinatura__c premium = TestDataFactory.plan('PRE-upg', 2, 150, premiumProduct);
        Solicitacao_Alteracao__c draft = planChangeDraft(s, premium, 80);
        System.assertEquals(2000, draft.Variacao_Absoluta__c);
        System.assertEquals(20, draft.Variacao_Percentual__c);
        System.assertEquals(SubscriptionConstants.TIPO_UPGRADE, draft.Tipo__c);

        Solicitacao_Alteracao__c r = approvedByGroup('Aprovadores_Diretores', draft);
        System.assertEquals(SubscriptionConstants.NIVEL_DIRETOR, r.Nivel_Aprovacao__c);
        applicableToday();

        SubscriptionApplyResultDTO out = applyAs(seller, r.Id);
        System.assertEquals(true, out.success, describe(out));
        Contrato_Assinatura__c contract = contractState(s.contract.Id);
        System.assertEquals(premium.Id, contract.Plano_Atual__c);
        System.assertEquals(12000, contract.MRR_Atual__c);
        System.assertEquals(
            SubscriptionConstants.ITEM_REMOVIDO,
            [SELECT Status__c FROM Item_Contrato__c WHERE Id = :s.licenseItem.Id].Status__c
        );
        Item_Contrato__c newLicense = [
            SELECT Tipo__c, Quantidade__c FROM Item_Contrato__c
            WHERE Contrato__c = :s.contract.Id AND Produto__c = :premiumProduct.Id AND Status__c = :SubscriptionConstants.ITEM_ATIVO
        ];
        System.assertEquals(SubscriptionConstants.ITEM_TIPO_LICENCA, newLicense.Tipo__c);
        System.assertEquals(80, newLicense.Quantidade__c);
        System.assertEquals(2, [SELECT COUNT() FROM OrderItem WHERE OrderId = :out.orderId]);
    }

    @IsTest
    static void inactiveProposedPlanBlocksApplyAndKeepsApproved() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('ina');
        User seller = TestDataFactory.seller();
        Product2 premiumProduct = TestDataFactory.product('Premium ina', true, 150);
        Plano_Assinatura__c premium = TestDataFactory.plan('PRE-ina', 2, 150, premiumProduct);
        Solicitacao_Alteracao__c r = approvedByGroup('Aprovadores_Diretores', planChangeDraft(s, premium, 80));
        premium.Ativo__c = false;
        update premium;
        applicableToday();

        SubscriptionApplyResultDTO out = applyAs(seller, r.Id);
        System.assertEquals(false, out.success);
        System.assertEquals(SubscriptionConstants.ERR_PLANO_INATIVO, out.code);
        System.assertEquals(SubscriptionConstants.REQ_APROVADA, TestDataFactory.reload(r.Id).Status__c);
        System.assertEquals(s.basicPlan.Id, contractState(s.contract.Id).Plano_Atual__c);
        System.assertEquals(0, [SELECT COUNT() FROM Aditivo_Contrato__c]);
    }

    @IsTest
    static void actionAppliesAndRejectsBatch() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('act');
        User seller = TestDataFactory.seller();
        Solicitacao_Alteracao__c r = approvedRequest(s, s.contract, 50);
        applicableToday();
        SubscriptionApplyAction.Request req = new SubscriptionApplyAction.Request();
        req.requestId = r.Id;
        List<SubscriptionApplyAction.Request> batch200 = new List<SubscriptionApplyAction.Request>();
        for (Integer i = 0; i < 200; i++) {
            batch200.add(req);
        }
        System.runAs(seller) {
            List<SubscriptionApplyAction.Result> res = SubscriptionApplyAction.apply(new List<SubscriptionApplyAction.Request>{ req });
            System.assertEquals(true, res[0].success, '' + res[0].message);
            System.assertEquals(SubscriptionConstants.REQ_APLICADA, res[0].status);
            System.assertNotEquals(null, res[0].additiveId);
            System.assertNotEquals(null, res[0].orderId);
            System.assertEquals(0, SubscriptionApplyAction.apply(null).size());
            System.assertEquals(0, SubscriptionApplyAction.apply(new List<SubscriptionApplyAction.Request>()).size());

            List<SubscriptionApplyAction.Result> again = SubscriptionApplyAction.apply(new List<SubscriptionApplyAction.Request>{ req });
            System.assertEquals(true, again[0].alreadyApplied);

            List<SubscriptionApplyAction.Result> many = SubscriptionApplyAction.apply(batch200);
            System.assertEquals(200, many.size());
            for (SubscriptionApplyAction.Result item : many) {
                System.assertEquals(false, item.success);
                System.assertEquals(SubscriptionConstants.ERR_ENTRADA_INVALIDA, item.code);
            }
            List<SubscriptionApplyAction.Result> nullReq = SubscriptionApplyAction.apply(new List<SubscriptionApplyAction.Request>{ null });
            System.assertEquals(false, nullReq[0].success);
            System.assertEquals(SubscriptionConstants.ERR_ENTRADA_INVALIDA, nullReq[0].code);
        }
        System.assertEquals(1, [SELECT COUNT() FROM Aditivo_Contrato__c]);
    }

    @IsTest
    static void failsForNullNotFoundDraftAndFutureDate() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('neg');
        User seller = TestDataFactory.seller();
        System.assertEquals(SubscriptionConstants.ERR_ENTRADA_INVALIDA, applyAs(seller, null).code);
        System.assertEquals(SubscriptionConstants.ERR_NAO_ENCONTRADO, applyAs(seller, s.contract.Id).code);

        Solicitacao_Alteracao__c draft = TestDataFactory.draftAdd(s, s.contract, 50);
        SubscriptionApplyResultDTO notSent = applyAs(seller, draft.Id);
        System.assertEquals(SubscriptionConstants.ERR_STATUS_NAO_APLICAVEL, notSent.code);
        System.assert(notSent.message.contains('ainda não foi enviada'), notSent.message);

        TestDataFactory.submit(draft.Id);
        SubscriptionApplyResultDTO future = applyAs(seller, draft.Id);
        System.assertEquals(SubscriptionConstants.ERR_DATA_EFETIVACAO_FUTURA, future.code);
        System.assertEquals(SubscriptionConstants.REQ_APROVADA, TestDataFactory.reload(draft.Id).Status__c);
        System.assertEquals(0, [SELECT COUNT() FROM Aditivo_Contrato__c]);
    }

    @IsTest
    static void statusMessagesForEachState() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('sts');
        User manager = TestDataFactory.approver('Aprovadores_Gerentes');
        User seller = TestDataFactory.seller();

        Solicitacao_Alteracao__c pending = pendingRequest(TestDataFactory.draftAdd(s, newContract(s, 'p'), 100));

        Solicitacao_Alteracao__c rejected = pendingRequest(TestDataFactory.draftAdd(s, newContract(s, 'r'), 100));
        System.runAs(manager) {
            System.assertEquals(true, new SubscriptionDecisionService().reject(
                rejected.Id, rejected.Ciclo_Aprovacao__c, 'Motivo de rejeicao com mais de vinte caracteres'
            ).success);
        }

        Solicitacao_Alteracao__c cancelled = pendingRequest(TestDataFactory.draftAdd(s, newContract(s, 'c'), 100));
        update new Solicitacao_Alteracao__c(Id = cancelled.Id, Status__c = SubscriptionConstants.REQ_CANCELADA);
        applicableToday();

        Map<Id, String> expectations = new Map<Id, String>{
            pending.Id => 'pendente de decisão',
            rejected.Id => 'foi rejeitada',
            cancelled.Id => 'foi cancelada'
        };
        for (Id requestId : expectations.keySet()) {
            SubscriptionApplyResultDTO out = applyAs(seller, requestId);
            System.assertEquals(SubscriptionConstants.ERR_STATUS_NAO_APLICAVEL, out.code, out.message);
            System.assert(out.message.contains(expectations.get(requestId)), out.message);
        }
    }

    @IsTest
    static void appliedAndExpiredRequestsCannotBeAppliedAgain() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('ape');
        User seller = TestDataFactory.seller();
        Solicitacao_Alteracao__c applied = approvedRequest(s, s.contract, 50);
        Contrato_Assinatura__c expiredContract = newContract(s, 'e');
        Solicitacao_Alteracao__c expired = approvedRequest(s, expiredContract, 50);
        applicableToday();

        System.assertEquals(true, applyAs(seller, applied.Id).success);
        delete [SELECT Id FROM Aditivo_Contrato__c WHERE Solicitacao__c = :applied.Id];
        SubscriptionApplyResultDTO appliedAgain = applyAs(seller, applied.Id);
        System.assertEquals(SubscriptionConstants.ERR_STATUS_NAO_APLICAVEL, appliedAgain.code);
        System.assert(appliedAgain.message.contains('já foi aplicada'), appliedAgain.message);

        ContractApplyWriter.updateContract(expiredContract.Id, null, 9);
        System.assertEquals(SubscriptionConstants.ERR_VERSAO_DESATUALIZADA, applyAs(seller, expired.Id).code);
        SubscriptionApplyResultDTO expiredAgain = applyAs(seller, expired.Id);
        System.assertEquals(SubscriptionConstants.ERR_STATUS_NAO_APLICAVEL, expiredAgain.code);
        System.assert(expiredAgain.message.contains('expirou'), expiredAgain.message);
    }

    @IsTest
    static void staleContractVersionExpiresRequest() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('stl');
        User seller = TestDataFactory.seller();
        Solicitacao_Alteracao__c r = approvedRequest(s, s.contract, 50);
        ContractApplyWriter.updateContract(s.contract.Id, null, 7);
        applicableToday();

        SubscriptionApplyResultDTO out = applyAs(seller, r.Id);
        System.assertEquals(false, out.success);
        System.assertEquals(SubscriptionConstants.ERR_VERSAO_DESATUALIZADA, out.code);
        System.assertEquals(SubscriptionConstants.REQ_EXPIRADA, out.status);
        System.assertEquals(SubscriptionConstants.REQ_EXPIRADA, TestDataFactory.reload(r.Id).Status__c);
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Historico_Decisao__c WHERE Solicitacao__c = :r.Id AND Decisao__c = :SubscriptionConstants.DEC_EXPIRADA]
        );
        System.assertEquals(7, contractState(s.contract.Id).Versao__c);
        System.assertEquals(0, [SELECT COUNT() FROM Aditivo_Contrato__c]);
    }

    @IsTest
    static void staleItemQuantityExpiresRequest() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('sti');
        User seller = TestDataFactory.seller();
        Solicitacao_Alteracao__c draft = TestDataFactory.draftWithItems(s.contract, new List<Item_Alteracao__c>{
            new Item_Alteracao__c(Produto__c = s.licenseProduct.Id, Acao__c = SubscriptionConstants.ACAO_ALTERAR_QTD, Quantidade_Nova__c = 110)
        });
        Solicitacao_Alteracao__c r = approvedByGroup('Aprovadores_Gerentes', draft);
        ControlledWriteContext.Scope scope = ControlledWriteContext.open(new Set<Id>{ s.contract.Id }, 'Alteracao concorrente simulada');
        try {
            update new Item_Contrato__c(Id = s.licenseItem.Id, Quantidade__c = 90);
        } finally {
            scope.close();
        }
        applicableToday();

        SubscriptionApplyResultDTO out = applyAs(seller, r.Id);
        System.assertEquals(SubscriptionConstants.ERR_VERSAO_DESATUALIZADA, out.code);
        System.assertEquals(SubscriptionConstants.REQ_EXPIRADA, TestDataFactory.reload(r.Id).Status__c);
        System.assertEquals(90, [SELECT Quantidade__c FROM Item_Contrato__c WHERE Id = :s.licenseItem.Id].Quantidade__c);
    }

    @IsTest
    static void inactiveContractBlocksApply() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('cls');
        User seller = TestDataFactory.seller();
        Solicitacao_Alteracao__c r = approvedRequest(s, s.contract, 50);
        update new Contrato_Assinatura__c(Id = s.contract.Id, Status__c = SubscriptionConstants.CTR_ENCERRADO);
        applicableToday();

        SubscriptionApplyResultDTO out = applyAs(seller, r.Id);
        System.assertEquals(SubscriptionConstants.ERR_CONTRATO_NAO_ATIVO, out.code);
        System.assertEquals(SubscriptionConstants.REQ_APROVADA, TestDataFactory.reload(r.Id).Status__c);
    }

    @IsTest
    static void inconsistentMrrRollsBackEverything() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('mrr');
        User seller = TestDataFactory.seller();
        Solicitacao_Alteracao__c r = approvedRequest(s, s.contract, 50);
        ControlledWriteContext.Scope scope = ControlledWriteContext.open(new Set<Id>{ s.contract.Id }, 'Preco alterado fora do fluxo (simulado)');
        try {
            update new Item_Contrato__c(Id = s.licenseItem.Id, Preco_Unitario_Mensal__c = 101);
        } finally {
            scope.close();
        }
        applicableToday();

        SubscriptionApplyResultDTO out = applyAs(seller, r.Id);
        System.assertEquals(false, out.success);
        System.assertEquals(SubscriptionConstants.ERR_TOTAIS_DESATUALIZADOS, out.code);
        System.assertEquals(SubscriptionConstants.REQ_APROVADA, TestDataFactory.reload(r.Id).Status__c);
        System.assertEquals(0, [SELECT COUNT() FROM Item_Contrato__c WHERE Contrato__c = :s.contract.Id AND Tipo__c = :SubscriptionConstants.ITEM_TIPO_RECURSO]);
        System.assertEquals(0, [SELECT COUNT() FROM Aditivo_Contrato__c]);
        System.assertEquals(0, contractState(s.contract.Id).Versao__c);
    }

    @IsTest
    static void missingPriceKeepsRequestApprovedAndRollsBack() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('prc');
        User seller = TestDataFactory.seller();
        Solicitacao_Alteracao__c r = approvedRequest(s, s.contract, 50);
        delete [SELECT Id FROM PricebookEntry WHERE Product2Id = :s.resourceProduct.Id];
        applicableToday();

        SubscriptionApplyResultDTO out = applyAs(seller, r.Id);
        System.assertEquals(SubscriptionConstants.ERR_PRECO_AUSENTE, out.code, '' + out.message);
        System.assertEquals(SubscriptionConstants.REQ_APROVADA, TestDataFactory.reload(r.Id).Status__c);
        System.assertEquals(0, [SELECT COUNT() FROM Aditivo_Contrato__c]);
        System.assertEquals(0, [SELECT COUNT() FROM Order]);
    }

    @IsTest
    static void failureInSecondOrderItemRollsBackAndLogs() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('rbk');
        User seller = TestDataFactory.seller();
        Product2 second = TestDataFactory.product('Recurso 2 rbk', true, 10);
        Solicitacao_Alteracao__c draft = TestDataFactory.draftWithItems(s.contract, new List<Item_Alteracao__c>{
            new Item_Alteracao__c(Produto__c = s.resourceProduct.Id, Acao__c = SubscriptionConstants.ACAO_ADICIONAR, Quantidade_Nova__c = 20),
            new Item_Alteracao__c(Produto__c = second.Id, Acao__c = SubscriptionConstants.ACAO_ADICIONAR, Quantidade_Nova__c = 20)
        });
        Solicitacao_Alteracao__c r = approvedRequest(draft);
        applicableToday();
        ContractApplyWriter.failAtOrderItem = 2;

        SubscriptionApplyResultDTO out = applyAs(seller, r.Id);
        System.assertEquals(false, out.success);
        System.assertEquals(SubscriptionConstants.ERR_INESPERADO, out.code);
        System.assert(out.message.contains('continua Aprovada'), out.message);
        System.assertEquals(SubscriptionConstants.REQ_APROVADA, TestDataFactory.reload(r.Id).Status__c);
        System.assertEquals(0, [SELECT COUNT() FROM Aditivo_Contrato__c]);
        System.assertEquals(0, [SELECT COUNT() FROM Order]);
        System.assertEquals(0, [SELECT COUNT() FROM OrderItem]);
        System.assertEquals(0, [SELECT COUNT() FROM Item_Contrato__c WHERE Contrato__c = :s.contract.Id AND Tipo__c = :SubscriptionConstants.ITEM_TIPO_RECURSO]);
        System.assertEquals(0, contractState(s.contract.Id).Versao__c);
        System.assertEquals(1, [SELECT COUNT() FROM Log_Tecnico__c]);

        ContractApplyWriter.failAtOrderItem = null;
        SubscriptionApplyResultDTO retry = applyAs(seller, r.Id);
        System.assertEquals(true, retry.success, '' + retry.message);
    }

    private static Solicitacao_Alteracao__c approvedRequest(Solicitacao_Alteracao__c draft) {
        TestDataFactory.submit(draft.Id);
        Solicitacao_Alteracao__c reloaded = TestDataFactory.reload(draft.Id);
        System.assertEquals(SubscriptionConstants.REQ_APROVADA, reloaded.Status__c);
        return reloaded;
    }

    @IsTest
    static void deniedWithoutApplyPermission() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('den');
        Solicitacao_Alteracao__c r = approvedRequest(s, s.contract, 50);
        applicableToday();
        User approver = TestDataFactory.approver('Aprovadores_Gerentes');
        User administrator = TestDataFactory.administrator();
        User noAccess = TestDataFactory.user('semps', new List<String>(), new List<String>());
        for (User denied : new List<User>{ approver, administrator, noAccess }) {
            SubscriptionApplyResultDTO out = applyAs(denied, r.Id);
            System.assertEquals(false, out.success);
            System.assertEquals(SubscriptionConstants.ERR_SEM_PERMISSAO, out.code, denied.Alias + ': ' + out.message);
        }
        System.assertEquals(0, [SELECT COUNT() FROM Aditivo_Contrato__c]);
        System.assertEquals(SubscriptionConstants.REQ_APROVADA, TestDataFactory.reload(r.Id).Status__c);
    }

    @IsTest
    static void unexpectedErrorIsCaughtByController() {
        SubscriptionApplyResultDTO out = SubscriptionApplyController.runApply(new ThrowingService(), UserInfo.getUserId());
        System.assertEquals(false, out.success);
        System.assertEquals(SubscriptionConstants.ERR_INESPERADO, out.code);
        System.assertEquals(1, [SELECT COUNT() FROM Log_Tecnico__c]);
        List<SubscriptionApplyAction.Result> viaAction = SubscriptionApplyAction.apply(new List<SubscriptionApplyAction.Request>{ null });
        System.assertEquals(false, viaAction[0].success);
    }

    @IsTest
    static void resultDtoFailureFactory() {
        SubscriptionApplyResultDTO out = SubscriptionApplyResultDTO.failure(UserInfo.getUserId(), 'COD', 'msg');
        System.assertEquals(false, out.success);
        System.assertEquals(false, out.alreadyApplied);
        System.assertEquals('COD', out.code);
        System.assertEquals('msg', out.message);
        System.assertEquals(UserInfo.getUserId(), out.requestId);
    }

    private class ThrowingService extends SubscriptionApplyService {
        public override SubscriptionApplyResultDTO apply(Id requestId) {
            throw new NullPointerException();
        }
    }
}
