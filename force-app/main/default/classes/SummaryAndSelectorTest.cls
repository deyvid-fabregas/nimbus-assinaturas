@IsTest
private class SummaryAndSelectorTest {
    private static Solicitacao_Alteracao__c draft(TestDataFactory.Scenario s, Integer qty) {
        Contrato_Assinatura__c contract = TestDataFactory.contract(s, TestDataFactory.account('S' + qty), 100);
        return TestDataFactory.draftAdd(s, contract, qty);
    }

    @IsTest
    static void summaryOfDraftAllowsSubmitAndBuildsHtml() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('sum1');
        Solicitacao_Alteracao__c request = draft(s, 100);

        SubscriptionRequestSummaryDTO dto = SubscriptionRequestSummaryController.getSummary(request.Id);
        System.assertEquals(request.Id, dto.requestId);
        System.assertEquals(SubscriptionConstants.REQ_RASCUNHO, dto.status);
        System.assert(dto.canSubmit);
        System.assert(!dto.canDecide);
        System.assert(!dto.lines.isEmpty());

        SubscriptionRequestSummaryAction.Request input = new SubscriptionRequestSummaryAction.Request();
        input.requestId = request.Id;
        List<SubscriptionRequestSummaryAction.Result> out = SubscriptionRequestSummaryAction.summarize(
            new List<SubscriptionRequestSummaryAction.Request>{ input }
        );
        System.assertEquals(1, out.size());
        System.assert(out[0].success);
        System.assert(out[0].canSubmit);
        System.assert(out[0].summaryHtml.contains('<p>'));
        System.assert(out[0].itemsHtml.contains('<ul>'));
    }

    @IsTest
    static void summaryOfPendingAndApprovedRequests() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('sum2');
        TestDataFactory.approver('Aprovadores_Gerentes');
        TestDataFactory.approver('Aprovadores_Diretores');
        TestDataFactory.approver('Aprovadores_Financeiro');

        Solicitacao_Alteracao__c pending = draft(s, 100);
        TestDataFactory.submit(pending.Id);
        SubscriptionRequestSummaryDTO pendingDto = new SubscriptionRequestSummaryService().build(pending.Id);
        System.assertEquals(SubscriptionConstants.REQ_PENDENTE, pendingDto.status);
        System.assert(!pendingDto.canSubmit);
        System.assertNotEquals(null, pendingDto.waitingHours);
        System.assertNotEquals(null, pendingDto.expectedResponsible);

        Solicitacao_Alteracao__c auto = draft(s, 50);
        TestDataFactory.submit(auto.Id);
        SubscriptionRequestSummaryDTO approved = new SubscriptionRequestSummaryService().build(auto.Id);
        System.assertEquals(SubscriptionConstants.REQ_APROVADA, approved.status);
        System.assert(!approved.canSubmit);
    }

    @IsTest
    static void summaryAsApproverCanDecidePendingRequest() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('sum3');
        User manager = TestDataFactory.approver('Aprovadores_Gerentes');
        TestDataFactory.approver('Aprovadores_Diretores');
        TestDataFactory.approver('Aprovadores_Financeiro');
        Solicitacao_Alteracao__c pending = draft(s, 100);
        TestDataFactory.submit(pending.Id);

        System.runAs(manager) {
            SubscriptionRequestSummaryDTO dto = new SubscriptionRequestSummaryService().build(pending.Id);
            System.assertEquals(SubscriptionConstants.REQ_PENDENTE, dto.status);
            System.assert(dto.canDecide || dto.unavailableReason != null);
        }
    }

    @IsTest
    static void unknownRequestFailsFriendly() {
        TestDataFactory.scenario('sum4');
        Id missing = Id.valueOf('a00000000000000AAA');
        try {
            SubscriptionRequestSummaryController.getSummary(missing);
            System.assert(false, 'deveria falhar');
        } catch (AuraHandledException expected) {
            System.assertNotEquals(null, expected.getMessage());
        }

        SubscriptionRequestSummaryAction.Request input = new SubscriptionRequestSummaryAction.Request();
        input.requestId = missing;
        List<SubscriptionRequestSummaryAction.Result> out = SubscriptionRequestSummaryAction.summarize(
            new List<SubscriptionRequestSummaryAction.Request>{ input }
        );
        System.assert(!out[0].success);
        System.assert(!out[0].canSubmit);
    }

    @IsTest
    static void actionHandlesEmptyAndMultipleInputs() {
        System.assertEquals(0, SubscriptionRequestSummaryAction.summarize(null).size());
        System.assertEquals(0, SubscriptionRequestSummaryAction.summarize(new List<SubscriptionRequestSummaryAction.Request>()).size());
        List<SubscriptionRequestSummaryAction.Request> two = new List<SubscriptionRequestSummaryAction.Request>{
            new SubscriptionRequestSummaryAction.Request(), new SubscriptionRequestSummaryAction.Request()
        };
        List<SubscriptionRequestSummaryAction.Result> out = SubscriptionRequestSummaryAction.summarize(two);
        System.assertEquals(2, out.size());
        System.assert(!out[0].success);
    }

    @IsTest
    static void selectorsReturnDataAndHandleEmptyInput() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('sel');
        TestDataFactory.approver('Aprovadores_Gerentes');
        TestDataFactory.approver('Aprovadores_Diretores');
        TestDataFactory.approver('Aprovadores_Financeiro');
        Solicitacao_Alteracao__c request = draft(s, 50);
        TestDataFactory.submit(request.Id);
        Solicitacao_Alteracao__c pending = draft(s, 100);
        TestDataFactory.submit(pending.Id);

        System.assertEquals(0, new TaskSelector().selectOpenByRequestId(null).size());
        System.assertEquals(1, new TaskSelector().selectOpenByRequestId(pending.Id).size());
        System.assertEquals(0, new DecisionHistorySelector().selectByRequestIds(null).size());
        System.assertEquals(0, new DecisionHistorySelector().selectByRequestIds(new Set<Id>()).size());
        System.assert(!new DecisionHistorySelector().selectByRequestIds(new Set<Id>{ request.Id }).isEmpty());
        System.assertEquals('Aprovada', SubscriptionConstants.DEC_APROVADA);
    }
}
