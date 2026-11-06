/**
 * @description Resumo de uma solicitacao para tela (Screen Flows e, na 3D, o LWC subscriptionRequestSummary).
 *              Os indicadores can* sao CONVENIENCIA de UX calculados no servidor; cada acao revalida tudo no servidor
 *              (SubscriptionDecisionService, SubscriptionApplyService, Trigger de envio).
 */
public with sharing class SubscriptionRequestSummaryDTO {
    @AuraEnabled public Id requestId;
    @AuraEnabled public String name;
    @AuraEnabled public String status;
    @AuraEnabled public String requestType;
    @AuraEnabled public String contractName;
    @AuraEnabled public String currentPlanName;
    @AuraEnabled public String proposedPlanName;
    @AuraEnabled public Decimal cycle;
    @AuraEnabled public String approvalLevel;
    @AuraEnabled public String expectedResponsible;
    @AuraEnabled public Date effectiveDate;
    @AuraEnabled public String justification;
    @AuraEnabled public String rejectionReason;
    @AuraEnabled public String requesterName;
    @AuraEnabled public String approverName;
    @AuraEnabled public Datetime decisionDate;
    @AuraEnabled public Decimal baseMrr;
    @AuraEnabled public Decimal proposedMrr;
    @AuraEnabled public Decimal absoluteVariation;
    @AuraEnabled public Decimal percentVariation;
    @AuraEnabled public Decimal waitingHours;
    @AuraEnabled public List<Line> lines = new List<Line>();

    @AuraEnabled public Boolean canSubmit = false;
    @AuraEnabled public Boolean canDecide = false;
    @AuraEnabled public Boolean canApply = false;
    @AuraEnabled public Boolean canReopen = false;
    /** Motivo amigavel quando a acao relevante ao estado atual nao esta disponivel ao usuario. */
    @AuraEnabled public String unavailableReason;

    public class Line {
        @AuraEnabled public String productName;
        @AuraEnabled public String action;
        @AuraEnabled public Decimal currentQuantity;
        @AuraEnabled public Decimal newQuantity;
        @AuraEnabled public Decimal unitPrice;
        @AuraEnabled public Decimal deltaMrr;
    }
}
