trigger SubscriptionContractItemTrigger on Item_Contrato__c (
    before insert, before update, before delete,
    after insert, after update, after delete, after undelete
) {
    new ItemContratoHandler().run();
}
