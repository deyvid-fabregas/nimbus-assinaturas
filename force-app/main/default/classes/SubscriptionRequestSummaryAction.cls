/**
 * @description Acao invocavel dos Screen Flows: devolve o resumo da solicitacao ja formatado (HTML escapado) e os
 *              indicadores de disponibilidade. Nao decide nada: as acoes continuam validando tudo no servidor.
 *              Nao lanca excecao; falhas voltam em success = false com mensagem amigavel.
 */
public with sharing class SubscriptionRequestSummaryAction {

    public class Request {
        @InvocableVariable(label='Solicitação (Id)' required=true)
        public Id requestId;
    }

    public class Result {
        @InvocableVariable(label='Sucesso')
        public Boolean success;
        @InvocableVariable(label='Mensagem')
        public String message;
        @InvocableVariable(label='Status')
        public String status;
        @InvocableVariable(label='Ciclo')
        public Decimal cycle;
        @InvocableVariable(label='Resumo (HTML)')
        public String summaryHtml;
        @InvocableVariable(label='Itens (HTML)')
        public String itemsHtml;
        @InvocableVariable(label='Pode enviar')
        public Boolean canSubmit;
        @InvocableVariable(label='Pode decidir')
        public Boolean canDecide;
        @InvocableVariable(label='Pode aplicar')
        public Boolean canApply;
        @InvocableVariable(label='Pode reabrir')
        public Boolean canReopen;
        @InvocableVariable(label='Motivo de indisponibilidade')
        public String unavailableReason;
    }

    @InvocableMethod(
        label='Obter resumo da solicitação'
        description='Resumo financeiro e indicadores de disponibilidade das ações para a solicitação.'
        category='Assinaturas'
    )
    public static List<Result> summarize(List<Request> requests) {
        List<Result> results = new List<Result>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }
        if (requests.size() > 1) {
            // Acao de TELA: um resumo por interview. Evita SOQL por registro em acionamentos em lote.
            for (Request ignored : requests) {
                Result rejected = new Result();
                rejected.success = false;
                rejected.canSubmit = false;
                rejected.canDecide = false;
                rejected.canApply = false;
                rejected.canReopen = false;
                rejected.message = 'O resumo atende uma solicitação por vez.';
                results.add(rejected);
            }
            return results;
        }
        results.add(summarizeOne(new SubscriptionRequestSummaryService(), requests[0]));
        return results;
    }

    private static Result summarizeOne(SubscriptionRequestSummaryService service, Request request) {
        Result result = new Result();
        result.canSubmit = false;
        result.canDecide = false;
        result.canApply = false;
        result.canReopen = false;
        try {
            SubscriptionRequestSummaryDTO dto = service.build(request == null ? null : request.requestId);
            result.success = true;
            result.status = dto.status;
            result.cycle = dto.cycle;
            result.summaryHtml = summaryHtml(dto);
            result.itemsHtml = itemsHtml(dto);
            result.canSubmit = dto.canSubmit;
            result.canDecide = dto.canDecide;
            result.canApply = dto.canApply;
            result.canReopen = dto.canReopen;
            result.unavailableReason = dto.unavailableReason;
        } catch (SubscriptionException businessError) {
            result.success = false;
            result.message = businessError.getMessage();
        } catch (Exception unexpected) {
            Id logId = TechnicalLogger.log('SubscriptionRequestSummaryAction', 'summarize', request == null ? null : request.requestId, unexpected);
            result.success = false;
            result.message = TechnicalLogger.friendlyMessage(unexpected, logId);
        }
        return result;
    }

    private static String summaryHtml(SubscriptionRequestSummaryDTO dto) {
        List<String> rows = new List<String>();
        rows.add('<b>Solicitação:</b> ' + esc(dto.name) + ' &middot; <b>Status:</b> ' + esc(dto.status)
            + ' &middot; <b>Ciclo:</b> ' + (dto.cycle == null ? '-' : String.valueOf(dto.cycle.intValue())));
        rows.add('<b>Contrato:</b> ' + esc(dto.contractName) + ' &middot; <b>Plano atual:</b> ' + esc(dto.currentPlanName)
            + (dto.proposedPlanName == null ? '' : ' &rarr; <b>Plano proposto:</b> ' + esc(dto.proposedPlanName)));
        rows.add('<b>MRR atual:</b> ' + money(dto.baseMrr) + ' &middot; <b>MRR proposto:</b> ' + money(dto.proposedMrr)
            + ' &middot; <b>Variação:</b> ' + money(dto.absoluteVariation)
            + (dto.percentVariation == null ? '' : ' (' + String.valueOf(dto.percentVariation) + '%)'));
        rows.add('<b>Nível de aprovação:</b> ' + esc(dto.approvalLevel)
            + ' &middot; <b>Aprovador esperado:</b> ' + esc(dto.expectedResponsible));
        rows.add('<b>Solicitante:</b> ' + esc(dto.requesterName) + ' &middot; <b>Efetivação:</b> '
            + (dto.effectiveDate == null ? '-' : dto.effectiveDate.format()));
        rows.add('<b>Justificativa:</b> ' + esc(dto.justification));
        if (!TextUtil.isBlank(dto.rejectionReason)) {
            rows.add('<b>Motivo da rejeição:</b> ' + esc(dto.rejectionReason));
        }
        return '<p>' + String.join(rows, '</p><p>') + '</p>';
    }

    private static String itemsHtml(SubscriptionRequestSummaryDTO dto) {
        if (dto.lines.isEmpty()) {
            return '<p><i>Nenhum item na solicitação.</i></p>';
        }
        List<String> items = new List<String>();
        for (SubscriptionRequestSummaryDTO.Line line : dto.lines) {
            items.add('<li>' + esc(line.productName) + ' &ndash; ' + esc(line.action) + ': '
                + (line.currentQuantity == null ? '0' : String.valueOf(line.currentQuantity.intValue()))
                + ' &rarr; ' + (line.newQuantity == null ? '0' : String.valueOf(line.newQuantity.intValue()))
                + ' &times; ' + money(line.unitPrice) + ' = <b>' + money(line.deltaMrr) + '</b> /mês</li>');
        }
        return '<p><b>Itens alterados</b></p><ul>' + String.join(items, '') + '</ul>';
    }

    private static String esc(String value) {
        return value == null ? '-' : value.escapeHtml4();
    }

    private static String money(Decimal value) {
        return value == null ? '-' : 'R$ ' + value.setScale(2, RoundingMode.HALF_UP).format();
    }
}
