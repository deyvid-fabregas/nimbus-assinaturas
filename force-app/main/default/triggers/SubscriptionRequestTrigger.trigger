trigger SubscriptionRequestTrigger on Solicitacao_Alteracao__c (before insert, before update) {
    new SolicitacaoAlteracaoHandler().run();
}
