/**
 * @description Politica PURA (sem DML/SOQL) da matriz de alcada. As faixas NUNCA ficam no codigo:
 *              chegam como lista de Rule, montada por SubscriptionConfig a partir de Matriz_Alcada__mdt.
 *
 *              Algoritmo:
 *              1) direcao = REDUCAO se a variacao absoluta < 0, senao AUMENTO (zero conta como AUMENTO).
 *              2) para cada criterio (PERCENTUAL, ABSOLUTO) usa-se o MODULO da variacao e a PRIMEIRA
 *                 faixa (ordenada por limite superior asc., faixa aberta por ultimo) em que valor <= limite
 *                 (limites inclusivos). Criterio sem regras para a direcao nao se aplica (ex.: reducao nao
 *                 tem criterio absoluto). Percentual indefinido (base zero) nao se aplica.
 *              3) nivel exigido = o MAIOR entre os dois criterios.
 *              4) invariante de negocio: REDUCAO nunca e Automatica (piso = Gerente de Contas).
 *              5) teto Parametro_Assinatura__mdt.Variacao_Maxima_Percentual__c: acima dele -> BLOQUEADA,
 *                 mesmo que a matriz fosse mais permissiva.
 *              6) valor que excede todas as faixas limitadas -> BLOQUEADA (falha segura).
 */
public with sharing class ApprovalMatrixPolicy {

    /** Ordem das constantes = severidade crescente (ordinal() e usado para comparar). */
    public enum Level { AUTOMATICA, GERENTE, DIRETOR, FINANCEIRO, BLOQUEADA }
    public enum Direction { AUMENTO, REDUCAO }
    public enum Criterion { PERCENTUAL, ABSOLUTO }

    public class Rule implements Comparable {
        public String developerName;
        public Direction direction;
        public Criterion criterion;
        /** Limite superior INCLUSIVO; null = faixa aberta (sem limite). */
        public Decimal upperLimit;
        public Level level;
        public String responsibleType;
        public String responsibleName;

        public Rule(
            String developerName,
            Direction direction,
            Criterion criterion,
            Decimal upperLimit,
            Level level,
            String responsibleType,
            String responsibleName
        ) {
            this.developerName = developerName;
            this.direction = direction;
            this.criterion = criterion;
            this.upperLimit = upperLimit;
            this.level = level;
            this.responsibleType = responsibleType;
            this.responsibleName = responsibleName;
        }

        public Integer compareTo(Object other) {
            Rule o = (Rule) other;
            if (upperLimit == null && o.upperLimit == null) {
                return 0;
            }
            if (upperLimit == null) {
                return 1;
            }
            if (o.upperLimit == null) {
                return -1;
            }
            if (upperLimit == o.upperLimit) {
                return 0;
            }
            return upperLimit < o.upperLimit ? -1 : 1;
        }
    }

    public class Result {
        public Level level;
        public Level levelByPercent;
        public Level levelByAbsolute;
        public Direction direction;
        public MrrCalculator.Variation variation;
        public Boolean blocked = false;
        public String blockCode;
        public String blockMessage;
        /** GRUPO | FILA | PAPEL (valor de Matriz_Alcada__mdt.Responsavel_Tipo__c); null se automatica/bloqueada. */
        public String responsibleType;
        /** DeveloperName do grupo, fila ou papel responsavel. */
        public String responsibleName;

        public Boolean requiresHumanApproval() {
            return !blocked && level != ApprovalMatrixPolicy.Level.AUTOMATICA;
        }

        /** Rotulo da picklist Solicitacao_Alteracao__c.Nivel_Aprovacao__c (null quando bloqueada). */
        public String levelLabel() {
            return ApprovalMatrixPolicy.labelOf(level);
        }
    }

    public static Result classify(
        Decimal baseMrr,
        Decimal proposedMrr,
        List<Rule> rules,
        Decimal maxVariationPercent
    ) {
        MrrCalculator.Variation variation = MrrCalculator.compute(baseMrr, proposedMrr);
        Direction direction = variation.absolute < 0 ? ApprovalMatrixPolicy.Direction.REDUCAO : ApprovalMatrixPolicy.Direction.AUMENTO;
        Decimal percentMagnitude = variation.percent == null ? null : Math.abs(variation.percent);
        Decimal absoluteMagnitude = Math.abs(variation.absolute);

        Level byPercent = levelFor(direction, ApprovalMatrixPolicy.Criterion.PERCENTUAL, percentMagnitude, rules);
        Level byAbsolute = levelFor(direction, ApprovalMatrixPolicy.Criterion.ABSOLUTO, absoluteMagnitude, rules);
        if (byPercent == null && byAbsolute == null) {
            throw new SubscriptionException(
                SubscriptionConstants.ERR_ALCADA_AUSENTE,
                'A matriz de alçada não está configurada para esta variação. Contate o administrador.'
            );
        }

        Level required = maxOf(byPercent, byAbsolute);
        if (direction == ApprovalMatrixPolicy.Direction.REDUCAO && required == ApprovalMatrixPolicy.Level.AUTOMATICA) {
            required = ApprovalMatrixPolicy.Level.GERENTE;
        }

        Result result = new Result();
        result.variation = variation;
        result.direction = direction;
        result.levelByPercent = byPercent;
        result.levelByAbsolute = byAbsolute;

        Boolean aboveCeiling = maxVariationPercent != null
            && percentMagnitude != null
            && percentMagnitude > maxVariationPercent;
        if (aboveCeiling || required == ApprovalMatrixPolicy.Level.BLOQUEADA) {
            result.level = ApprovalMatrixPolicy.Level.BLOQUEADA;
            result.blocked = true;
            result.blockCode = SubscriptionConstants.ERR_VARIACAO_ACIMA_LIMITE;
            result.blockMessage = 'A variação de MRR'
                + (variation.percent == null ? '' : ' (' + variation.percent + '%)')
                + ' excede o limite permitido para alteração. Abra um novo contrato ou conduza uma negociação específica.';
            return result;
        }

        result.level = required;
        Rule responsible = responsibleFor(required, direction, rules);
        if (responsible != null) {
            result.responsibleType = responsible.responsibleType;
            result.responsibleName = responsible.responsibleName;
        }
        return result;
    }

    private static Level levelFor(Direction direction, Criterion criterion, Decimal magnitude, List<Rule> rules) {
        List<Rule> candidates = new List<Rule>();
        if (rules != null) {
            for (Rule rule : rules) {
                if (rule.direction == direction && rule.criterion == criterion) {
                    candidates.add(rule);
                }
            }
        }
        if (candidates.isEmpty() || magnitude == null) {
            return null;
        }
        candidates.sort();
        for (Rule rule : candidates) {
            if (rule.upperLimit == null || magnitude <= rule.upperLimit) {
                return rule.level;
            }
        }
        return ApprovalMatrixPolicy.Level.BLOQUEADA;
    }

    private static Level maxOf(Level a, Level b) {
        if (a == null) {
            return b;
        }
        if (b == null) {
            return a;
        }
        return a.ordinal() >= b.ordinal() ? a : b;
    }

    /** Prefere a regra da mesma direcao; senao qualquer regra do nivel com responsavel preenchido. */
    private static Rule responsibleFor(Level level, Direction direction, List<Rule> rules) {
        Rule fallback = null;
        if (rules == null) {
            return null;
        }
        for (Rule rule : rules) {
            if (rule.level != level || TextUtil.isBlank(rule.responsibleName)) {
                continue;
            }
            if (rule.direction == direction) {
                return rule;
            }
            if (fallback == null) {
                fallback = rule;
            }
        }
        return fallback;
    }

    // ---- Conversoes (codigos do metadado <-> enum <-> rotulo da picklist) ----

    public static String labelOf(Level level) {
        if (level == ApprovalMatrixPolicy.Level.AUTOMATICA) {
            return SubscriptionConstants.NIVEL_AUTOMATICA;
        }
        if (level == ApprovalMatrixPolicy.Level.GERENTE) {
            return SubscriptionConstants.NIVEL_GERENTE;
        }
        if (level == ApprovalMatrixPolicy.Level.DIRETOR) {
            return SubscriptionConstants.NIVEL_DIRETOR;
        }
        if (level == ApprovalMatrixPolicy.Level.FINANCEIRO) {
            return SubscriptionConstants.NIVEL_FINANCEIRO;
        }
        return null;
    }

    /** Aceita o rotulo da picklist; devolve null se nao reconhecido. */
    public static Level levelFromLabel(String label) {
        if (label == SubscriptionConstants.NIVEL_AUTOMATICA) {
            return ApprovalMatrixPolicy.Level.AUTOMATICA;
        }
        if (label == SubscriptionConstants.NIVEL_GERENTE) {
            return ApprovalMatrixPolicy.Level.GERENTE;
        }
        if (label == SubscriptionConstants.NIVEL_DIRETOR) {
            return ApprovalMatrixPolicy.Level.DIRETOR;
        }
        if (label == SubscriptionConstants.NIVEL_FINANCEIRO) {
            return ApprovalMatrixPolicy.Level.FINANCEIRO;
        }
        return null;
    }

    /** Nome da Custom Permission que habilita decidir o nivel; null para Automatica/Bloqueada. */
    public static String customPermissionOf(Level level) {
        if (level == ApprovalMatrixPolicy.Level.GERENTE) {
            return SubscriptionConstants.PERM_APROVAR_GERENTE;
        }
        if (level == ApprovalMatrixPolicy.Level.DIRETOR) {
            return SubscriptionConstants.PERM_APROVAR_DIRETOR;
        }
        if (level == ApprovalMatrixPolicy.Level.FINANCEIRO) {
            return SubscriptionConstants.PERM_APROVAR_FINANCEIRO;
        }
        return null;
    }

    public static Level levelFromCode(String code) {
        return ApprovalMatrixPolicy.Level.valueOf(code);
    }

    public static Direction directionFromCode(String code) {
        return ApprovalMatrixPolicy.Direction.valueOf(code);
    }

    public static Criterion criterionFromCode(String code) {
        return ApprovalMatrixPolicy.Criterion.valueOf(code);
    }
}
