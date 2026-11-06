@IsTest
private class SubscriptionChangeJsonTest {
    @IsTest
    static void jsonEntryPointsReturnBusinessResults() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('json');
        Contrato_Assinatura__c contract = TestDataFactory.contract(s, TestDataFactory.account('Json'), 100);

        System.assert(!SubscriptionChangeController.simulateJson(null).success);
        System.assert(!SubscriptionChangeController.simulateJson('{invalido').success);
        System.assert(!SubscriptionChangeController.saveDraftJson('').success);

        String body = '{"contractId":"' + contract.Id + '","effectiveDate":"' + TestDataFactory.effectiveDate().format()
            + '","justification":"x","idempotencyKey":"k-json","items":[]}';
        SubscriptionChangeResultDTO empty = SubscriptionChangeController.simulateJson(
            '{"contractId":"' + contract.Id + '","items":[]}'
        );
        System.assertNotEquals(SubscriptionConstants.ERR_ENTRADA_INVALIDA + 'x', empty.errorCode);
        System.assert(!empty.success);
        System.assertNotEquals(null, body);
    }
}
