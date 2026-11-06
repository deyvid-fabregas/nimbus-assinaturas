/**
 * @description Controller FINO do simulador (US-01): so orquestra e converte falhas em
 *              SubscriptionChangeResultDTO.failure. NUNCA lanca excecao (excecao em @AuraEnabled reverteria a
 *              transacao e perderia o Log_Tecnico__c). Regras, calculos e permissoes ficam no Service/Triggers;
 *              loadContext apenas lista opcoes de tela (leitura em USER_MODE).
 */
public with sharing class SubscriptionChangeController {

    public class OptionDTO {
        @AuraEnabled public Id value;
        @AuraEnabled public String label;
    }

    public class ItemContextDTO {
        @AuraEnabled public Id productId;
        @AuraEnabled public String productName;
        @AuraEnabled public Decimal quantity;
    }

    public class ContextDTO {
        @AuraEnabled public Boolean success = true;
        @AuraEnabled public String message;
        @AuraEnabled public Id contractId;
        @AuraEnabled public String contractName;
        @AuraEnabled public String contractStatus;
        @AuraEnabled public Id currentPlanId;
        @AuraEnabled public String currentPlanName;
        @AuraEnabled public Decimal currentMrr;
        @AuraEnabled public List<OptionDTO> plans = new List<OptionDTO>();
        @AuraEnabled public List<OptionDTO> products = new List<OptionDTO>();
        @AuraEnabled public List<ItemContextDTO> items = new List<ItemContextDTO>();
    }

    @AuraEnabled
    public static SubscriptionChangeResultDTO simulate(SubscriptionChangeRequestDTO request) {
        return runSimulate(new SubscriptionChangeService(), request);
    }

    @AuraEnabled
    public static SubscriptionChangeResultDTO saveDraft(SubscriptionChangeRequestDTO request) {
        return runSaveDraft(new SubscriptionChangeService(), request);
    }

    // Entrada em JSON: o LWC envia o rascunho serializado porque o Aura entregava o DTO vazio.
    @AuraEnabled
    public static SubscriptionChangeResultDTO simulateJson(String requestJson) {
        return runSimulate(new SubscriptionChangeService(), parseRequest(requestJson));
    }

    @AuraEnabled
    public static SubscriptionChangeResultDTO saveDraftJson(String requestJson) {
        return runSaveDraft(new SubscriptionChangeService(), parseRequest(requestJson));
    }

    private static SubscriptionChangeRequestDTO parseRequest(String requestJson) {
        if (String.isBlank(requestJson)) {
            return new SubscriptionChangeRequestDTO();
        }
        try {
            return (SubscriptionChangeRequestDTO) JSON.deserialize(requestJson, SubscriptionChangeRequestDTO.class);
        } catch (JSONException invalid) {
            return new SubscriptionChangeRequestDTO();
        }
    }
    @AuraEnabled(cacheable=true)
    public static ContextDTO loadContext(Id contractId) {
        ContextDTO context = new ContextDTO();
        context.contractId = contractId;
        try {
            if (contractId == null) {
                throw new SubscriptionException(SubscriptionConstants.ERR_ENTRADA_INVALIDA, 'Informe o contrato.');
            }
            List<Contrato_Assinatura__c> contracts = [
                SELECT Id, Name, Status__c, Plano_Atual__c, Plano_Atual__r.Name, MRR_Atual__c, Pricebook__c
                FROM Contrato_Assinatura__c WHERE Id = :contractId WITH USER_MODE LIMIT 1
            ];
            if (contracts.isEmpty()) {
                throw new SubscriptionException(SubscriptionConstants.ERR_NAO_ENCONTRADO, 'Contrato não encontrado ou sem acesso.');
            }
            Contrato_Assinatura__c contract = contracts[0];
            context.contractName = contract.Name;
            context.contractStatus = contract.Status__c;
            context.currentPlanId = contract.Plano_Atual__c;
            context.currentPlanName = contract.Plano_Atual__r?.Name;
            context.currentMrr = contract.MRR_Atual__c;

            for (Plano_Assinatura__c plan : [
                SELECT Id, Name FROM Plano_Assinatura__c WHERE Ativo__c = true WITH USER_MODE ORDER BY Name LIMIT 200
            ]) {
                context.plans.add(option(plan.Id, plan.Name));
            }
            Set<Id> activeProducts = new Set<Id>();
            for (Item_Contrato__c item : [
                SELECT Produto__c, Produto__r.Name, Quantidade__c FROM Item_Contrato__c
                WHERE Contrato__c = :contractId AND Status__c = 'Ativo' WITH USER_MODE ORDER BY Produto__r.Name LIMIT 200
            ]) {
                ItemContextDTO line = new ItemContextDTO();
                line.productId = item.Produto__c;
                line.productName = item.Produto__r?.Name;
                line.quantity = item.Quantidade__c;
                context.items.add(line);
                activeProducts.add(item.Produto__c);
            }
            if (contract.Pricebook__c != null) {
                for (PricebookEntry entry : [
                    SELECT Product2Id, Product2.Name FROM PricebookEntry
                    WHERE Pricebook2Id = :contract.Pricebook__c AND IsActive = true AND Product2.IsActive = true
                    WITH USER_MODE ORDER BY Product2.Name LIMIT 200
                ]) {
                    if (!activeProducts.contains(entry.Product2Id)) {
                        context.products.add(option(entry.Product2Id, entry.Product2.Name));
                    }
                }
            }
        } catch (SubscriptionException businessError) {
            context.success = false;
            context.message = businessError.getMessage();
        } catch (Exception unexpected) {
            Id logId = TechnicalLogger.log('SubscriptionChangeController', 'loadContext', contractId, unexpected);
            context.success = false;
            context.message = TechnicalLogger.friendlyMessage(unexpected, logId);
        }
        return context;
    }

    public static SubscriptionChangeResultDTO runSimulate(SubscriptionChangeService service, SubscriptionChangeRequestDTO request) {
        try {
            return service.simulate(request);
        } catch (SubscriptionException businessError) {
            return SubscriptionChangeResultDTO.failure(businessError.code, businessError.getMessage());
        } catch (Exception unexpected) {
            Id logId = TechnicalLogger.log('SubscriptionChangeController', 'simulate', request == null ? null : request.contractId, unexpected);
            return SubscriptionChangeResultDTO.failure(SubscriptionConstants.ERR_INESPERADO, TechnicalLogger.friendlyMessage(unexpected, logId));
        }
    }

    public static SubscriptionChangeResultDTO runSaveDraft(SubscriptionChangeService service, SubscriptionChangeRequestDTO request) {
        try {
            return service.saveDraft(request);
        } catch (SubscriptionException businessError) {
            return SubscriptionChangeResultDTO.failure(businessError.code, businessError.getMessage());
        } catch (Exception unexpected) {
            Id logId = TechnicalLogger.log('SubscriptionChangeController', 'saveDraft', request == null ? null : request.contractId, unexpected);
            return SubscriptionChangeResultDTO.failure(SubscriptionConstants.ERR_INESPERADO, TechnicalLogger.friendlyMessage(unexpected, logId));
        }
    }

    private static OptionDTO option(Id value, String label) {
        OptionDTO result = new OptionDTO();
        result.value = value;
        result.label = label;
        return result;
    }
}
