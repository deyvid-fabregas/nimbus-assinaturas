trigger SubscriptionItemChangeTrigger on Item_Alteracao__c (
    before insert, before update, before delete,
    after insert, after update, after delete, after undelete
) {
    new ItemAlteracaoHandler().run();
}
