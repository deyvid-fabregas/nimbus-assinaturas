@IsTest
private class ApprovalFlowTest {
    private static Solicitacao_Alteracao__c draft(TestDataFactory.Scenario s, Integer resourceQty) {
        Contrato_Assinatura__c contract = TestDataFactory.contract(s, TestDataFactory.account('C' + resourceQty), 100);
        return TestDataFactory.draftAdd(s, contract, resourceQty);
    }

    private static Solicitacao_Alteracao__c submitted(Solicitacao_Alteracao__c request) {
        TestDataFactory.submit(request.Id);
        return TestDataFactory.reload(request.Id);
    }

    @IsTest
    static void routingByLevelCreatesTaskForDesignatedGroup() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('lvl');
        User manager = TestDataFactory.approver('Aprovadores_Gerentes');
        TestDataFactory.approver('Aprovadores_Diretores');
        TestDataFactory.approver('Aprovadores_Financeiro');

        Solicitacao_Alteracao__c auto = draft(s, 50);
        System.assertEquals(500, auto.Variacao_Absoluta__c);
        auto = submitted(auto);
        System.assertEquals(SubscriptionConstants.REQ_APROVADA, auto.Status__c);
        System.assertEquals(SubscriptionConstants.NIVEL_AUTOMATICA, auto.Nivel_Aprovacao__c);
        System.assertEquals(1, [SELECT COUNT() FROM Historico_Decisao__c WHERE Solicitacao__c = :auto.Id AND Decisao__c = :SubscriptionConstants.DEC_AUTOMATICA]);

        Solicitacao_Alteracao__c mgr = submitted(draft(s, 100));
        System.assertEquals(SubscriptionConstants.REQ_PENDENTE, mgr.Status__c);
        System.assertEquals(SubscriptionConstants.NIVEL_GERENTE, mgr.Nivel_Aprovacao__c);
        System.assertEquals(1, mgr.Ciclo_Aprovacao__c);
        List<Task> tasks = [SELECT OwnerId FROM Task WHERE WhatId = :mgr.Id];
        System.assertEquals(1, tasks.size());
        System.assertEquals(manager.Id, tasks[0].OwnerId);

    }

    @IsTest
    static void routingDirectorAndFinanceLevels() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('lv2');
        TestDataFactory.approver('Aprovadores_Diretores');
        TestDataFactory.approver('Aprovadores_Financeiro');
        System.assertEquals(SubscriptionConstants.NIVEL_DIRETOR, submitted(draft(s, 200)).Nivel_Aprovacao__c);
        System.assertEquals(SubscriptionConstants.NIVEL_FINANCEIRO, submitted(draft(s, 400)).Nivel_Aprovacao__c);
    }

    @IsTest
    static void blockedAboveLimitCannotBeSubmitted() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('blk');
        Solicitacao_Alteracao__c big = draft(s, 600);
        try {
            TestDataFactory.submit(big.Id);
            System.assert(false, 'deveria bloquear');
        } catch (DmlException e) {
            System.assert(true);
        }
        System.assertEquals(SubscriptionConstants.REQ_RASCUNHO, TestDataFactory.reload(big.Id).Status__c);
    }

    @IsTest
    static void noDesignatedUserCompensatesAndLogs() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('nod');
        Solicitacao_Alteracao__c request = draft(s, 100);
        TestDataFactory.submit(request.Id);
        Solicitacao_Alteracao__c after = TestDataFactory.reload(request.Id);
        System.assertEquals(SubscriptionConstants.REQ_RASCUNHO, after.Status__c);
        System.assert([SELECT COUNT() FROM Log_Tecnico__c] >= 1);
        System.assertEquals(0, [SELECT COUNT() FROM Task WHERE WhatId = :request.Id]);
    }

    @IsTest
    static void routingIsIdempotentAndResubmitStartsNewCycle() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('idm');
        TestDataFactory.approver('Aprovadores_Gerentes');
        Solicitacao_Alteracao__c request = submitted(draft(s, 100));
        Map<Id, ApprovalRoutingService.Outcome> again = new ApprovalRoutingService().route(new Set<Id>{ request.Id });
        System.assertEquals(true, again.get(request.Id).noOp);
        System.assertEquals(1, [SELECT COUNT() FROM Task WHERE WhatId = :request.Id]);
        System.assertEquals(1, TestDataFactory.reload(request.Id).Ciclo_Aprovacao__c);
    }

    @IsTest
    static void decisionRulesAndPermissions() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('dec');
        User manager = TestDataFactory.approver('Aprovadores_Gerentes');
        User director = TestDataFactory.approver('Aprovadores_Diretores');
        User outsider = TestDataFactory.seller();
        Solicitacao_Alteracao__c request = submitted(draft(s, 100));
        Decimal cycle = request.Ciclo_Aprovacao__c;
        SubscriptionDecisionService service = new SubscriptionDecisionService();

        System.runAs(outsider) {
            System.assertEquals(SubscriptionConstants.ERR_SEM_PERMISSAO, service.approve(request.Id, cycle).code);
        }
        System.runAs(director) {
            SubscriptionDecisionService.Outcome o = service.approve(request.Id, cycle);
            System.assertEquals(false, o.success);
        }
        System.runAs(manager) {
            System.assertEquals(SubscriptionConstants.ERR_CICLO_DESATUALIZADO, service.approve(request.Id, cycle + 5).code);
            System.assertEquals(SubscriptionConstants.ERR_MOTIVO_CURTO, service.reject(request.Id, cycle, 'curto').code);
            System.assertEquals(SubscriptionConstants.ERR_ENTRADA_INVALIDA, service.approve(null, cycle).code);
            System.assertEquals(SubscriptionConstants.ERR_ENTRADA_INVALIDA, service.decide(new List<SubscriptionDecisionService.Input>{ new SubscriptionDecisionService.Input() })[0].code);
            SubscriptionDecisionService.Input bad = new SubscriptionDecisionService.Input();
            bad.requestId = request.Id;
            bad.cycle = cycle;
            bad.decision = 'Xyz';
            System.assertEquals(false, service.decide(new List<SubscriptionDecisionService.Input>{ bad })[0].success);
            System.assertEquals(0, service.decide(new List<SubscriptionDecisionService.Input>()).size());
            System.assertEquals(0, service.decide(null).size());

            SubscriptionDecisionService.Outcome ok = service.approve(request.Id, cycle);
            System.assertEquals(true, ok.success, ok.message);
            SubscriptionDecisionService.Outcome dup = service.approve(request.Id, cycle);
            System.assertEquals(true, dup.alreadyResolved);
        }
        System.assertEquals(SubscriptionConstants.REQ_APROVADA, TestDataFactory.reload(request.Id).Status__c);
        System.assertEquals(1, [SELECT COUNT() FROM Historico_Decisao__c WHERE Solicitacao__c = :request.Id AND Decisao__c = :SubscriptionConstants.DEC_APROVADA]);
    }

    @IsTest
    static void rejectReopenAndResubmit() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('rej');
        User manager = TestDataFactory.approver('Aprovadores_Gerentes');
        User seller = TestDataFactory.seller();
        Solicitacao_Alteracao__c request = submitted(draft(s, 100));
        SubscriptionDecisionService service = new SubscriptionDecisionService();
        System.runAs(manager) {
            SubscriptionDecisionService.Outcome o = service.reject(request.Id, request.Ciclo_Aprovacao__c, 'Motivo de rejeicao com mais de vinte caracteres');
            System.assertEquals(true, o.success, o.message);
        }
        System.assertEquals(SubscriptionConstants.REQ_REJEITADA, TestDataFactory.reload(request.Id).Status__c);
        {
            System.assertEquals(true, service.reopen(request.Id).success);
            System.assertEquals(SubscriptionConstants.ERR_JA_DECIDIDA, service.reopen(request.Id).code);
        }
        System.assertEquals(SubscriptionConstants.REQ_RASCUNHO, TestDataFactory.reload(request.Id).Status__c);
        Solicitacao_Alteracao__c second = submitted(TestDataFactory.reload(request.Id));
        System.assertEquals(2, second.Ciclo_Aprovacao__c);
        System.assertEquals(2, [SELECT COUNT() FROM Task WHERE WhatId = :request.Id]);
        System.assertEquals(1, new SubscriptionDecisionService().reopen(new List<Id>()).size() + 1);
    }

    @IsTest
    static void segregationOfDuties() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('seg');
        User manager = TestDataFactory.approver('Aprovadores_Gerentes');
        Solicitacao_Alteracao__c request;
        System.runAs(manager) {
            request = submitted(draft(s, 100));
            SubscriptionDecisionService.Outcome o = new SubscriptionDecisionService().approve(request.Id, request.Ciclo_Aprovacao__c);
            System.assertEquals(SubscriptionConstants.ERR_SEGREGACAO_FUNCOES, o.code);
        }
    }

    @IsTest
    static void invocableActions() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('act');
        User manager = TestDataFactory.approver('Aprovadores_Gerentes');
        User seller = TestDataFactory.seller();
        Solicitacao_Alteracao__c request = submitted(draft(s, 100));
        System.assertEquals(0, SubscriptionDecisionAction.decide(null).size());
        System.assertEquals(0, SubscriptionReopenAction.reopen(new List<SubscriptionReopenAction.Request>()).size());
        System.runAs(manager) {
            SubscriptionDecisionAction.Request r = new SubscriptionDecisionAction.Request();
            r.requestId = request.Id;
            r.cycle = request.Ciclo_Aprovacao__c;
            r.decision = SubscriptionConstants.REQ_REJEITADA;
            r.reason = 'Motivo de rejeicao com mais de vinte caracteres';
            List<SubscriptionDecisionAction.Result> res = SubscriptionDecisionAction.decide(new List<SubscriptionDecisionAction.Request>{ r, null });
            System.assertEquals(true, res[0].success, res[0].message);
            System.assertEquals(false, res[1].success);
        }
        {
            SubscriptionReopenAction.Request rr = new SubscriptionReopenAction.Request();
            rr.requestId = request.Id;
            List<SubscriptionReopenAction.Result> out = SubscriptionReopenAction.reopen(new List<SubscriptionReopenAction.Request>{ rr });
            System.assertEquals(true, out[0].success, out[0].message);
            System.assertEquals(false, SubscriptionReopenAction.reopen(new List<SubscriptionReopenAction.Request>{ null })[0].success);
        }
    }

    @IsTest
    static void routingActionsAndFault() {
        System.assertEquals(0, ApprovalRoutingAction.route(null).size());
        TestDataFactory.Scenario s = TestDataFactory.scenario('rac');
        Solicitacao_Alteracao__c request = draft(s, 100);
        ApprovalRoutingFaultAction.Request fault = new ApprovalRoutingFaultAction.Request();
        fault.requestId = request.Id;
        fault.errorMessage = 'falha simulada';
        System.assertEquals(0, ApprovalRoutingFaultAction.compensate(null).size());
        ApprovalRoutingFaultAction.compensate(new List<ApprovalRoutingFaultAction.Request>{ fault, null });
        System.assert([SELECT COUNT() FROM Log_Tecnico__c] >= 1);
        ApprovalRoutingAction.Request req = new ApprovalRoutingAction.Request();
        req.requestId = request.Id;
        ApprovalRoutingAction.route(new List<ApprovalRoutingAction.Request>{ req, null });
    }

    @IsTest
    static void bulkSubmit200() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('blk200');
        TestDataFactory.approver('Aprovadores_Gerentes');
        List<Contrato_Assinatura__c> contracts = TestDataFactory.contracts(s, 200);
        List<Solicitacao_Alteracao__c> requests = new List<Solicitacao_Alteracao__c>();
        for (Contrato_Assinatura__c c : contracts) {
            requests.add(new Solicitacao_Alteracao__c(
                Contrato__c = c.Id, Status__c = SubscriptionConstants.REQ_RASCUNHO, Data_Efetivacao__c = TestDataFactory.effectiveDate(),
                Justificativa__c = TestDataFactory.justification(), Chave_Idempotencia__c = 'B-' + c.Id
            ));
        }
        insert requests;
        List<Item_Alteracao__c> items = new List<Item_Alteracao__c>();
        for (Solicitacao_Alteracao__c r : requests) {
            items.add(new Item_Alteracao__c(Solicitacao__c = r.Id, Produto__c = s.resourceProduct.Id, Acao__c = SubscriptionConstants.ACAO_ADICIONAR, Quantidade_Nova__c = 100));
        }
        insert items;
        List<Solicitacao_Alteracao__c> toSubmit = new List<Solicitacao_Alteracao__c>();
        for (Solicitacao_Alteracao__c r : requests) {
            toSubmit.add(new Solicitacao_Alteracao__c(Id = r.Id, Status__c = SubscriptionConstants.REQ_PENDENTE));
        }
        Test.startTest();
        update toSubmit;
        Test.stopTest();
        System.assertEquals(200, [SELECT COUNT() FROM Solicitacao_Alteracao__c WHERE Status__c = :SubscriptionConstants.REQ_PENDENTE AND Nivel_Aprovacao__c = :SubscriptionConstants.NIVEL_GERENTE]);
        System.assertEquals(200, [SELECT COUNT() FROM Task WHERE WhatId IN :requests]);
    }
}
