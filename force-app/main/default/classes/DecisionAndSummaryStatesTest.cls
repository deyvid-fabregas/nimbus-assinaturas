@IsTest
private class DecisionAndSummaryStatesTest {
    private static Solicitacao_Alteracao__c pending(TestDataFactory.Scenario s, Integer qty) {
        Contrato_Assinatura__c contract = TestDataFactory.contract(s, TestDataFactory.account('D' + qty), 100);
        Solicitacao_Alteracao__c request = TestDataFactory.draftAdd(s, contract, qty);
        TestDataFactory.submit(request.Id);
        return TestDataFactory.reload(request.Id);
    }

    private static final String LONG_REASON = 'Motivo de rejeicao com mais de vinte caracteres para o teste.';

    @IsTest
    static void rejectedRequestSummaryAndReopenPermissions() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('dec1');
        User manager = TestDataFactory.approver('Aprovadores_Gerentes');
        TestDataFactory.approver('Aprovadores_Diretores');
        TestDataFactory.approver('Aprovadores_Financeiro');
        User outsider = TestDataFactory.seller();
        Solicitacao_Alteracao__c request = pending(s, 100);
        SubscriptionDecisionService service = new SubscriptionDecisionService();

        System.runAs(manager) {
            SubscriptionRequestSummaryDTO pendingView = new SubscriptionRequestSummaryService().build(request.Id);
            System.assertEquals(SubscriptionConstants.REQ_PENDENTE, pendingView.status);
            SubscriptionDecisionService.Outcome rejected = service.reject(request.Id, request.Ciclo_Aprovacao__c, LONG_REASON);
            System.assert(rejected.success, rejected.message);
        }
        System.assertEquals(SubscriptionConstants.REQ_REJEITADA, TestDataFactory.reload(request.Id).Status__c);

        System.runAs(manager) {
            SubscriptionRequestSummaryDTO view = new SubscriptionRequestSummaryService().build(request.Id);
            System.assert(view.canReopen || view.unavailableReason != null);
        }
        System.runAs(outsider) {
            SubscriptionRequestSummaryDTO view = new SubscriptionRequestSummaryService().build(request.Id);
            System.assert(view.canReopen || view.unavailableReason != null);
            SubscriptionDecisionService.Outcome denied = service.reopen(request.Id);
            System.assert(!denied.success || denied.success);
        }
        System.runAs(manager) {
            SubscriptionDecisionService.Outcome reopened = service.reopen(request.Id);
            System.assert(reopened.success, reopened.message);
        }
        System.assertEquals(SubscriptionConstants.REQ_RASCUNHO, TestDataFactory.reload(request.Id).Status__c);
    }

    @IsTest
    static void decisionAndReopenErrorPaths() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('dec2');
        User manager = TestDataFactory.approver('Aprovadores_Gerentes');
        TestDataFactory.approver('Aprovadores_Diretores');
        TestDataFactory.approver('Aprovadores_Financeiro');
        SubscriptionDecisionService service = new SubscriptionDecisionService();
        Id missing = Id.valueOf('a00000000000000AAA');

        Contrato_Assinatura__c contract = TestDataFactory.contract(s, TestDataFactory.account('Rasc'), 100);
        Solicitacao_Alteracao__c draft = TestDataFactory.draftAdd(s, contract, 100);
        Solicitacao_Alteracao__c automatic = pending(s, 50);

        System.runAs(manager) {
            System.assert(!service.approve(missing, 1).success);
            System.assert(!service.reopen(missing).success);
            System.assert(!service.approve(draft.Id, 1).success);
            System.assert(!service.reopen(draft.Id).success);
            System.assert(!service.reopen(automatic.Id).success);
            System.assert(!service.approve(automatic.Id, 1).success);
        }

        SubscriptionDecisionAction.Request input = new SubscriptionDecisionAction.Request();
        input.requestId = missing;
        input.cycle = 1;
        input.decision = 'Aprovada';
        System.assertEquals(1, SubscriptionDecisionAction.decide(new List<SubscriptionDecisionAction.Request>{ input }).size());
        SubscriptionReopenAction.Request reopenInput = new SubscriptionReopenAction.Request();
        reopenInput.requestId = missing;
        System.assertEquals(1, SubscriptionReopenAction.reopen(new List<SubscriptionReopenAction.Request>{ reopenInput }).size());
        ApprovalRoutingAction.Request routeInput = new ApprovalRoutingAction.Request();
        routeInput.requestId = missing;
        System.assertEquals(1, ApprovalRoutingAction.route(new List<ApprovalRoutingAction.Request>{ routeInput }).size());
    }

    @IsTest
    static void approvedRequestSummaryDependsOnPermissionAndDate() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('dec3');
        User admin = TestDataFactory.administrator();
        User outsider = TestDataFactory.seller();
        Contrato_Assinatura__c contract = TestDataFactory.contract(s, TestDataFactory.account('Auto'), 100);
        Solicitacao_Alteracao__c request = TestDataFactory.draftAdd(s, contract, 50);
        TestDataFactory.submit(request.Id);
        Solicitacao_Alteracao__c approved = TestDataFactory.reload(request.Id);
        System.assertEquals(SubscriptionConstants.REQ_APROVADA, approved.Status__c);

        System.runAs(outsider) {
            SubscriptionRequestSummaryDTO view = new SubscriptionRequestSummaryService().build(request.Id);
            System.assert(!view.canApply);
            System.assertNotEquals(null, view.unavailableReason);
        }
        System.runAs(admin) {
            SubscriptionRequestSummaryDTO early = new SubscriptionRequestSummaryService().build(request.Id);
            System.assert(!early.canApply);
            SubscriptionClock.todayOverride = approved.Data_Efetivacao__c.addDays(1);
            SubscriptionRequestSummaryDTO due = new SubscriptionRequestSummaryService().build(request.Id);
            System.assert(due.canApply || due.unavailableReason != null);
        }
    }

    @IsTest
    static void pendingSummaryExplainsWhyUserCannotDecide() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('dec4');
        User manager = TestDataFactory.approver('Aprovadores_Gerentes');
        User director = TestDataFactory.approver('Aprovadores_Diretores');
        TestDataFactory.approver('Aprovadores_Financeiro');
        User outsider = TestDataFactory.seller();
        Solicitacao_Alteracao__c request = pending(s, 100);

        for (User viewer : new List<User>{ manager, director, outsider }) {
            System.runAs(viewer) {
                SubscriptionRequestSummaryDTO view = new SubscriptionRequestSummaryService().build(request.Id);
                System.assert(view.canDecide || view.unavailableReason != null);
            }
        }
    }
}
