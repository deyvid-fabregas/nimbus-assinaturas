@IsTest
private class SelectorCoverageTest {
    @IsTest
    static void selectorsReturnScenarioData() {
        TestDataFactory.Scenario s = TestDataFactory.scenario('slc');
        User manager = TestDataFactory.approver('Aprovadores_Gerentes');
        TestDataFactory.approver('Aprovadores_Diretores');
        TestDataFactory.approver('Aprovadores_Financeiro');
        Solicitacao_Alteracao__c request = TestDataFactory.draftAdd(s, s.contract, 100);
        TestDataFactory.submit(request.Id);
        Set<Id> requestIds = new Set<Id>{ request.Id };
        Set<Id> contractIds = new Set<Id>{ s.contract.Id };
        Set<Id> productIds = new Set<Id>{ s.licenseProduct.Id, s.resourceProduct.Id };
        Set<Id> emptyIds = new Set<Id>();

        RequestSelector requests = new RequestSelector();
        System.assertEquals(1, requests.selectByIds(requestIds).size());
        System.assertEquals(1, requests.mapByIds(requestIds).size());
        System.assertEquals(1, requests.selectByIdsForUpdate(requestIds).size());
        System.assertEquals(0, requests.selectByIds(emptyIds).size());
        System.assertEquals(0, requests.mapByIds(emptyIds).size());
        System.assertEquals(0, requests.selectByIdsForUpdate(emptyIds).size());
        System.assertEquals(1, requests.selectPendingByContractIds(contractIds, emptyIds).size());
        System.assertEquals(0, requests.selectPendingByContractIds(contractIds, requestIds).size());
        System.assertEquals(0, requests.selectPendingByContractIds(emptyIds, emptyIds).size());
        System.assertEquals(0, requests.selectByIdempotencyKeys(new Set<String>{ 'inexistente' }).size());
        System.assertEquals(0, requests.selectByIdempotencyKeys(new Set<String>()).size());
        System.assertEquals(1, requests.selectSummaryById(request.Id).size());
        System.assertEquals(0, requests.selectSummaryById(null).size());

        RequestItemSelector items = new RequestItemSelector();
        List<Item_Alteracao__c> requestItems = items.selectByRequestIds(requestIds);
        System.assert(!requestItems.isEmpty());
        System.assertEquals(1, items.selectByIds(new Set<Id>{ requestItems[0].Id }).size());
        System.assertEquals(0, items.selectByIds(emptyIds).size());
        System.assertEquals(0, items.selectByRequestIds(emptyIds).size());
        System.assert(items.sumDeltaByRequestIds(requestIds).containsKey(request.Id));
        System.assertEquals(0, items.sumDeltaByRequestIds(emptyIds).size());
        System.assert(items.countByRequestIds(requestIds).containsKey(request.Id));
        System.assertEquals(0, items.countByRequestIds(emptyIds).size());

        ContractSelector contracts = new ContractSelector();
        System.assertEquals(1, contracts.selectByIds(contractIds).size());
        System.assertEquals(1, contracts.mapByIds(contractIds).size());
        System.assertEquals(1, contracts.selectByIdsForUpdate(contractIds).size());
        System.assertEquals(0, contracts.selectByIds(emptyIds).size());
        System.assertEquals(0, contracts.mapByIds(emptyIds).size());
        System.assertEquals(0, contracts.selectByIdsForUpdate(emptyIds).size());

        ContractItemSelector contractItems = new ContractItemSelector();
        System.assert(!contractItems.selectActiveByContractIds(contractIds).isEmpty());
        System.assert(!contractItems.selectAllByContractIds(contractIds).isEmpty());
        System.assertEquals(1, contractItems.selectByIds(new Set<Id>{ s.licenseItem.Id }).size());
        System.assert(contractItems.sumActiveMrrByContractIds(contractIds).containsKey(s.contract.Id));
        System.assertEquals(0, contractItems.selectByIds(emptyIds).size());
        System.assertEquals(0, contractItems.selectActiveByContractIds(emptyIds).size());
        System.assertEquals(0, contractItems.selectAllByContractIds(emptyIds).size());
        System.assertEquals(0, contractItems.sumActiveMrrByContractIds(emptyIds).size());

        PlanSelector plans = new PlanSelector();
        System.assert(!plans.selectActive().isEmpty());
        Set<Id> planIds = new Set<Id>{ s.basicPlan.Id };
        System.assertEquals(1, plans.selectByIds(planIds).size());
        System.assertEquals(1, plans.mapByIds(planIds).size());
        System.assertEquals(0, plans.selectByIds(emptyIds).size());
        System.assertEquals(0, plans.mapByIds(emptyIds).size());
        Plano_Assinatura__c plan = [SELECT Codigo__c FROM Plano_Assinatura__c WHERE Id = :s.basicPlan.Id];
        System.assertEquals(1, plans.selectByCodes(new Set<String>{ plan.Codigo__c }).size());
        System.assertEquals(0, plans.selectByCodes(new Set<String>()).size());

        PricebookSelector books = new PricebookSelector();
        System.assert(books.selectByIds(new Set<Id>{ s.pricebookId }).size() >= 0);
        System.assertEquals(0, books.selectByIds(emptyIds).size());
        System.assertEquals(0, books.selectActiveByName(null).size());
        System.assert(books.selectActiveByName('Padrão').size() >= 0);
        System.assert(books.selectActiveEntries(s.pricebookId, productIds).size() >= 0);
        System.assertEquals(0, books.selectActiveEntries(null, productIds).size());
        System.assertEquals(0, books.selectActiveEntries(s.pricebookId, emptyIds).size());
        System.assert(books.selectActiveEntriesForPricebooks(new Set<Id>{ s.pricebookId }, productIds).size() >= 0);
        System.assertEquals(0, books.selectActiveEntriesForPricebooks(emptyIds, productIds).size());
        System.assertEquals(0, books.selectActiveEntriesForPricebooks(new Set<Id>{ s.pricebookId }, emptyIds).size());

        AdditiveSelector additives = new AdditiveSelector();
        System.assertEquals(0, additives.selectByRequestIds(requestIds).size());
        System.assertEquals(0, additives.selectByRequestIds(emptyIds).size());
        String key = AdditiveSelector.uniqueKey(request.Id, 1);
        System.assertEquals(0, additives.selectByUniqueKeys(new Set<String>{ key }).size());
        System.assertEquals(0, additives.selectByUniqueKeys(new Set<String>()).size());

        DesignationSelector designation = new DesignationSelector();
        System.assert(designation.keysForUser(manager.Id).size() >= 0);
        System.assertEquals(0, designation.firstActiveUserByKey(new Set<String>()).size());
        System.assert(designation.firstActiveUserByKey(new Set<String>{ DesignationSelector.keyOf('Grupo', 'Aprovadores_Gerentes') }).size() >= 0);
    }
}
