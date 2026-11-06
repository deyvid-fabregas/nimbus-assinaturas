@IsTest
private class PolicyAndUtilityTest {
    private static ApprovalMatrixPolicy.Result classify(Decimal base, Decimal proposed) {
        return ApprovalMatrixPolicy.classify(
            base, proposed, SubscriptionConfig.approvalRules(), SubscriptionConfig.settings().maxVariationPercent
        );
    }

    // ---------------- Dinheiro / texto / colecoes
    @IsTest
    static void moneyRoundsHalfUp() {
        System.assertEquals(0.13, MoneyUtil.round(0.125));
        System.assertEquals(-0.13, MoneyUtil.round(-0.125));
        System.assertEquals(0.12, MoneyUtil.round(0.124));
        System.assertEquals(null, MoneyUtil.round(null));
        System.assertEquals(0, MoneyUtil.zeroIfNull(null));
        System.assertEquals(5, MoneyUtil.zeroIfNull(5));
        System.assertEquals(25.00, MoneyUtil.multiply(2.5, 10));
        System.assertEquals(0, MoneyUtil.multiply(null, 10));
        System.assertEquals(3.00, MoneyUtil.sum(new List<Decimal>{ 1, 2, null }));
        System.assertEquals(0, MoneyUtil.sum(null));
        System.assertEquals(33.33, MoneyUtil.percentOf(1, 3));
        System.assertEquals(66.67, MoneyUtil.percentOf(2, 3));
        System.assertEquals(null, MoneyUtil.percentOf(1, 0));
        System.assertEquals(null, MoneyUtil.percentOf(1, null));
        System.assertEquals(-10.00, MoneyUtil.percentOf(-1, 10));
    }

    @IsTest
    static void textAndCollections() {
        System.assert(TextUtil.isBlank(null));
        System.assert(TextUtil.isBlank('   '));
        System.assert(!TextUtil.isBlank('a'));
        System.assertEquals(0, TextUtil.meaningfulLength(null));
        System.assertEquals(2, TextUtil.meaningfulLength('  ab  '));
        System.assert(CollectionUtil.isNullOrEmpty((Set<Id>) null));
        System.assert(CollectionUtil.isNullOrEmpty(new Set<String>()));
        System.assert(CollectionUtil.isNullOrEmpty(new List<Account>()));
        System.assert(!CollectionUtil.isNullOrEmpty(new List<Account>{ new Account() }));
        Account acc = TestDataFactory.account('Util');
        List<Account> accs = new List<Account>{ acc, new Account(Name = 'sem id') };
        System.assertEquals(new Set<Id>{ acc.Id }, CollectionUtil.pluckIds(accs, Account.Id));
        System.assertEquals(2, CollectionUtil.pluckStrings(accs, Account.Name).size());
        System.assertEquals(0, CollectionUtil.pluckIds(null, Account.Id).size());
    }

    @IsTest
    static void clockAndConstantsAndException() {
        System.assertEquals(Date.today(), SubscriptionClock.today());
        System.assertNotEquals(null, SubscriptionClock.now());
        SubscriptionClock.todayOverride = Date.newInstance(2030, 1, 15);
        System.assertEquals(Date.newInstance(2030, 1, 15), SubscriptionClock.today());
        SubscriptionClock.nowOverride = Datetime.newInstance(2030, 1, 15, 10, 0, 0);
        System.assertEquals(Datetime.newInstance(2030, 1, 15, 10, 0, 0), SubscriptionClock.now());
        SubscriptionException ex = new SubscriptionException('COD', 'msg');
        System.assertEquals('COD', ex.code);
        System.assertEquals('msg', ex.getMessage());
    }

    @IsTest
    static void configLoadsSettingsAndRules() {
        SubscriptionSettings settings = SubscriptionConfig.settings();
        System.assertEquals(50, settings.maxVariationPercent);
        System.assertEquals(30, settings.effectiveWindowDays);
        System.assertEquals(20, settings.minJustificationLength);
        System.assertEquals(20, settings.minRejectionReasonLength);
        System.assertEquals(13, SubscriptionConfig.approvalRules().size());
        System.assertEquals(13, SubscriptionConfig.approvalRules().size()); // cache
    }

    // ---------------- MRR
    @IsTest
    static void mrrCalculation() {
        System.assertEquals(1000.00, MrrCalculator.itemMrr(10, 100));
        System.assertEquals(0, MrrCalculator.itemMrr(null, 100));
        System.assertEquals(500.00, MrrCalculator.lineDelta(10, 15, 100));
        System.assertEquals(-500.00, MrrCalculator.lineDelta(15, 10, 100));
        System.assertEquals(300.00, MrrCalculator.contractMrr(new List<Decimal>{ 100, 200 }));
        System.assertEquals(1500.00, MrrCalculator.proposedMrr(1000, 500));
        MrrCalculator.Variation v = MrrCalculator.compute(10000, 10500);
        System.assertEquals(500.00, v.absolute);
        System.assertEquals(5.00, v.percent);
        MrrCalculator.Variation zero = MrrCalculator.compute(10000, 10000);
        System.assertEquals(0, zero.absolute);
        System.assertEquals(0.00, zero.percent);
        MrrCalculator.Variation fromZero = MrrCalculator.compute(0, 100);
        System.assertEquals(null, fromZero.percent);
    }

    // ---------------- Alçada
    @IsTest
    static void levelsByPercentAndAbsolute() {
        // base pequena: absoluto baixo; nivel dado pelo percentual
        System.assertEquals(ApprovalMatrixPolicy.Level.AUTOMATICA, classify(10000, 10500).level); // 5% / 500
        System.assertEquals(ApprovalMatrixPolicy.Level.GERENTE, classify(10000, 10501).level); // 5,01%
        System.assertEquals(ApprovalMatrixPolicy.Level.GERENTE, classify(10000, 11500).level); // 15% / 1500 (<2k)
        System.assertEquals(ApprovalMatrixPolicy.Level.DIRETOR, classify(10000, 11501).level); // 15,01%
        System.assertEquals(ApprovalMatrixPolicy.Level.DIRETOR, classify(10000, 13000).level); // 30%
        System.assertEquals(ApprovalMatrixPolicy.Level.FINANCEIRO, classify(10000, 13001).level); // 30,01%
        System.assertEquals(ApprovalMatrixPolicy.Level.FINANCEIRO, classify(10000, 15000).level); // 50%
        ApprovalMatrixPolicy.Result blocked = classify(10000, 15001);
        System.assert(blocked.blocked);
        System.assertEquals(ApprovalMatrixPolicy.Level.BLOQUEADA, blocked.level);
        System.assertEquals(SubscriptionConstants.ERR_VARIACAO_ACIMA_LIMITE, blocked.blockCode);
        System.assertEquals(null, blocked.levelLabel());
        System.assert(!blocked.requiresHumanApproval());
    }

    @IsTest
    static void absoluteDominatesWhenHigher() {
        // base grande: percentual baixo, absoluto alto -> maior entre os dois
        ApprovalMatrixPolicy.Result r2k = classify(1000000, 1002000); // 0,2% / 2.000 -> automatica
        System.assertEquals(ApprovalMatrixPolicy.Level.AUTOMATICA, r2k.level);
        System.assertEquals(ApprovalMatrixPolicy.Level.GERENTE, classify(1000000, 1002001).level);
        System.assertEquals(ApprovalMatrixPolicy.Level.GERENTE, classify(1000000, 1010000).level); // 10k
        System.assertEquals(ApprovalMatrixPolicy.Level.DIRETOR, classify(1000000, 1010001).level);
        System.assertEquals(ApprovalMatrixPolicy.Level.DIRETOR, classify(1000000, 1030000).level); // 30k
        ApprovalMatrixPolicy.Result fin = classify(1000000, 1030001);
        System.assertEquals(ApprovalMatrixPolicy.Level.FINANCEIRO, fin.level);
        System.assertEquals(ApprovalMatrixPolicy.Level.AUTOMATICA, fin.levelByPercent);
        System.assertEquals(ApprovalMatrixPolicy.Level.FINANCEIRO, fin.levelByAbsolute);
        System.assertEquals(SubscriptionConstants.NIVEL_FINANCEIRO, fin.levelLabel());
        System.assertEquals('Aprovadores_Financeiro', fin.responsibleName);
        System.assertEquals(ApprovalMatrixPolicy.Level.FINANCEIRO, classify(1000000, 1100000).level); // 100k
        System.assert(classify(1000000, 1100001).blocked); // > 100k
    }

    @IsTest
    static void reductionsAreNeverAutomatic() {
        ApprovalMatrixPolicy.Result tiny = classify(10000, 9900); // -1%
        System.assertEquals(ApprovalMatrixPolicy.Level.GERENTE, tiny.level);
        System.assertEquals(ApprovalMatrixPolicy.Direction.REDUCAO, tiny.direction);
        System.assert(tiny.requiresHumanApproval());
        System.assertEquals(ApprovalMatrixPolicy.Level.GERENTE, classify(10000, 9000).level); // 10%
        System.assertEquals(ApprovalMatrixPolicy.Level.DIRETOR, classify(10000, 8999).level);
        System.assertEquals(ApprovalMatrixPolicy.Level.DIRETOR, classify(10000, 7500).level); // 25%
        System.assertEquals(ApprovalMatrixPolicy.Level.FINANCEIRO, classify(10000, 7499).level);
        System.assert(classify(10000, 4999).blocked); // > 50%
        // reducao so tem criterio percentual: grande reducao absoluta nao eleva por valor
        System.assertEquals(ApprovalMatrixPolicy.Level.GERENTE, classify(10000000, 9100000).level);
    }

    @IsTest
    static void unchangedAndNullBaseAndMissingMatrix() {
        System.assertEquals(ApprovalMatrixPolicy.Level.AUTOMATICA, classify(10000, 10000).level);
        System.assertEquals(ApprovalMatrixPolicy.Level.AUTOMATICA, classify(0, 100).level); // so absoluto
        try {
            ApprovalMatrixPolicy.classify(100, 200, new List<ApprovalMatrixPolicy.Rule>(), 50);
            System.assert(false, 'deveria lancar');
        } catch (SubscriptionException e) {
            System.assertEquals(SubscriptionConstants.ERR_ALCADA_AUSENTE, e.code);
        }
    }

    @IsTest
    static void conversions() {
        for (ApprovalMatrixPolicy.Level level : new List<ApprovalMatrixPolicy.Level>{
            ApprovalMatrixPolicy.Level.AUTOMATICA, ApprovalMatrixPolicy.Level.GERENTE,
            ApprovalMatrixPolicy.Level.DIRETOR, ApprovalMatrixPolicy.Level.FINANCEIRO
        }) {
            System.assertEquals(level, ApprovalMatrixPolicy.levelFromLabel(ApprovalMatrixPolicy.labelOf(level)));
        }
        System.assertEquals(null, ApprovalMatrixPolicy.labelOf(ApprovalMatrixPolicy.Level.BLOQUEADA));
        System.assertEquals(null, ApprovalMatrixPolicy.levelFromLabel('xyz'));
        System.assertEquals(SubscriptionConstants.PERM_APROVAR_GERENTE, ApprovalMatrixPolicy.customPermissionOf(ApprovalMatrixPolicy.Level.GERENTE));
        System.assertEquals(SubscriptionConstants.PERM_APROVAR_DIRETOR, ApprovalMatrixPolicy.customPermissionOf(ApprovalMatrixPolicy.Level.DIRETOR));
        System.assertEquals(SubscriptionConstants.PERM_APROVAR_FINANCEIRO, ApprovalMatrixPolicy.customPermissionOf(ApprovalMatrixPolicy.Level.FINANCEIRO));
        System.assertEquals(null, ApprovalMatrixPolicy.customPermissionOf(ApprovalMatrixPolicy.Level.AUTOMATICA));
        System.assertEquals(ApprovalMatrixPolicy.Level.DIRETOR, ApprovalMatrixPolicy.levelFromCode('DIRETOR'));
        System.assertEquals(ApprovalMatrixPolicy.Direction.REDUCAO, ApprovalMatrixPolicy.directionFromCode('REDUCAO'));
        System.assertEquals(ApprovalMatrixPolicy.Criterion.ABSOLUTO, ApprovalMatrixPolicy.criterionFromCode('ABSOLUTO'));
        try {
            ApprovalMatrixPolicy.levelFromCode('XX');
            System.assert(false);
        } catch (Exception e) {
            System.assert(true);
        }
    }

    @IsTest
    static void ruleSortingPutsOpenEndedLast() {
        ApprovalMatrixPolicy.Rule open = new ApprovalMatrixPolicy.Rule('a', ApprovalMatrixPolicy.Direction.AUMENTO, ApprovalMatrixPolicy.Criterion.ABSOLUTO, null, ApprovalMatrixPolicy.Level.BLOQUEADA, null, null);
        ApprovalMatrixPolicy.Rule low = new ApprovalMatrixPolicy.Rule('b', ApprovalMatrixPolicy.Direction.AUMENTO, ApprovalMatrixPolicy.Criterion.ABSOLUTO, 10, ApprovalMatrixPolicy.Level.AUTOMATICA, null, null);
        ApprovalMatrixPolicy.Rule high = new ApprovalMatrixPolicy.Rule('c', ApprovalMatrixPolicy.Direction.AUMENTO, ApprovalMatrixPolicy.Criterion.ABSOLUTO, 20, ApprovalMatrixPolicy.Level.GERENTE, 'GRUPO', 'g');
        List<ApprovalMatrixPolicy.Rule> rules = new List<ApprovalMatrixPolicy.Rule>{ open, high, low };
        rules.sort();
        System.assertEquals('b', rules[0].developerName);
        System.assertEquals('c', rules[1].developerName);
        System.assertEquals('a', rules[2].developerName);
        List<ApprovalMatrixPolicy.Rule> same = new List<ApprovalMatrixPolicy.Rule>{ low, low };
        same.sort();
        System.assertEquals(0, low.compareTo(low));
        System.assertEquals(1, open.compareTo(low));
        System.assertEquals(-1, low.compareTo(open));
        System.assertEquals(0, open.compareTo(open));
    }

    // ---------------- Máquina de estados
    @IsTest
    static void stateMachineTransitions() {
        String r = SubscriptionConstants.REQ_RASCUNHO;
        String p = SubscriptionConstants.REQ_PENDENTE;
        String a = SubscriptionConstants.REQ_APROVADA;
        String j = SubscriptionConstants.REQ_REJEITADA;
        String c = SubscriptionConstants.REQ_CANCELADA;
        String ap = SubscriptionConstants.REQ_APLICADA;
        String ex = SubscriptionConstants.REQ_EXPIRADA;
        System.assert(RequestStateMachine.isTransitionAllowed(r, p));
        System.assert(RequestStateMachine.isTransitionAllowed(p, a));
        System.assert(RequestStateMachine.isTransitionAllowed(p, j));
        System.assert(RequestStateMachine.isTransitionAllowed(p, c));
        System.assert(RequestStateMachine.isTransitionAllowed(a, ap));
        System.assert(RequestStateMachine.isTransitionAllowed(a, ex));
        System.assert(RequestStateMachine.isTransitionAllowed(j, r));
        System.assert(!RequestStateMachine.isTransitionAllowed(r, a));
        System.assert(!RequestStateMachine.isTransitionAllowed(r, c));
        System.assert(!RequestStateMachine.isTransitionAllowed(ap, r));
        System.assert(!RequestStateMachine.isTransitionAllowed(c, r));
        System.assert(!RequestStateMachine.isTransitionAllowed(ex, a));
        System.assert(!RequestStateMachine.isTransitionAllowed(j, a));
        System.assertEquals(null, RequestStateMachine.transitionError(r, p));
        System.assertNotEquals(null, RequestStateMachine.transitionError(r, a));
        System.assertEquals(null, RequestStateMachine.transitionError(r, r));
        System.assert(!RequestStateMachine.allowedTargets(p).isEmpty());
        System.assert(RequestStateMachine.allowedTargets(ap).isEmpty());
        try {
            RequestStateMachine.validateTransition(ap, r);
            System.assert(false);
        } catch (SubscriptionException e) {
            System.assertEquals(SubscriptionConstants.ERR_TRANSICAO_INVALIDA, e.code);
        }
        RequestStateMachine.validateTransition(r, p);
        System.assertEquals(null, RequestStateMachine.initialStatusError(r));
        System.assertNotEquals(null, RequestStateMachine.initialStatusError(a));
        System.assert(RequestStateMachine.areItemsEditable(r));
        System.assert(!RequestStateMachine.areItemsEditable(p));
        System.assert(RequestStateMachine.areItemsPermanentlyFrozen(a));
        System.assert(RequestStateMachine.areItemsPermanentlyFrozen(ap));
        System.assert(RequestStateMachine.areItemsPermanentlyFrozen(c));
        System.assert(!RequestStateMachine.areItemsPermanentlyFrozen(j));
        System.assertEquals(null, RequestStateMachine.itemChangeError(r));
        System.assertNotEquals(null, RequestStateMachine.itemChangeError(p));
        System.assertNotEquals(null, RequestStateMachine.itemChangeError(a));
        System.assert(RequestStateMachine.isTerminal(ap));
        System.assert(RequestStateMachine.isTerminal(c));
        System.assert(!RequestStateMachine.isTerminal(p));
        System.assert(RequestStateMachine.requiresAuthorizedService(p, a));
        System.assert(RequestStateMachine.requiresAuthorizedService(p, j));
        System.assert(RequestStateMachine.requiresAuthorizedService(a, ap));
        System.assert(RequestStateMachine.requiresAuthorizedService(a, ex));
        System.assert(RequestStateMachine.requiresAuthorizedService(j, r));
        System.assert(!RequestStateMachine.requiresAuthorizedService(r, p));
        System.assert(RequestStateMachine.isCompensationTransition(p, r));
        System.assert(!RequestStateMachine.isCompensationTransition(r, p));
    }

    // ---------------- Regras de negócio
    @IsTest
    static void changeRequestPolicyRules() {
        ChangeRequestPolicy.requireActiveContract('Ativo');
        assertCode(SubscriptionConstants.ERR_CONTRATO_NAO_ATIVO, 'requireActiveContract', 'Suspenso');
        ChangeRequestPolicy.requireActivePlan(true);
        try {
            ChangeRequestPolicy.requireActivePlan(false);
            System.assert(false);
        } catch (SubscriptionException e) {
            System.assert(true);
        }
        Date today = Date.newInstance(2030, 1, 10);
        ChangeRequestPolicy.requireEffectiveDate(today, today, 30);
        ChangeRequestPolicy.requireEffectiveDate(today.addDays(30), today, 30);
        for (Date bad : new List<Date>{ null, today.addDays(-1), today.addDays(31) }) {
            try {
                ChangeRequestPolicy.requireEffectiveDate(bad, today, 30);
                System.assert(false);
            } catch (SubscriptionException e) {
                System.assertNotEquals(null, e.code);
            }
        }
        ChangeRequestPolicy.requireJustification('x'.repeat(20), 20);
        try {
            ChangeRequestPolicy.requireJustification('curta', 20);
            System.assert(false);
        } catch (SubscriptionException e) {
            System.assert(true);
        }
        ChangeRequestPolicy.requireRejectionReason('y'.repeat(20), 20);
        try {
            ChangeRequestPolicy.requireRejectionReason(null, 20);
            System.assert(false);
        } catch (SubscriptionException e) {
            System.assert(true);
        }
        ChangeRequestPolicy.requireWithinLicenseLimits(10, 1, 20);
        for (Integer total : new List<Integer>{ 0, 21 }) {
            try {
                ChangeRequestPolicy.requireWithinLicenseLimits(total, 1, 20);
                System.assert(false);
            } catch (SubscriptionException e) {
                System.assert(true);
            }
        }
        ChangeRequestPolicy.requireNotBlocked(classify(10000, 10500));
        try {
            ChangeRequestPolicy.requireNotBlocked(classify(10000, 20000));
            System.assert(false);
        } catch (SubscriptionException e) {
            System.assertEquals(SubscriptionConstants.ERR_VARIACAO_ACIMA_LIMITE, e.code);
        }
        System.assert(ChangeRequestPolicy.isVersionStale(2, 1));
        System.assert(!ChangeRequestPolicy.isVersionStale(1, 1));
    }

    private static void assertCode(String code, String method, String status) {
        try {
            ChangeRequestPolicy.requireActiveContract(status);
            System.assert(false);
        } catch (SubscriptionException e) {
            System.assertEquals(code, e.code);
        }
    }

    // ---------------- Escopos / guardas
    @IsTest
    static void controlledWriteContextNestingAndInvalid() {
        Id fake = TestDataFactory.account('ctx').Id;
        System.assert(!ControlledWriteContext.isOpenFor(fake));
        ControlledWriteContext.Scope scopeA = ControlledWriteContext.open(new Set<Id>{ fake }, 'a');
        ControlledWriteContext.Scope scopeB = ControlledWriteContext.open(new Set<Id>{ fake }, 'b');
        System.assert(ControlledWriteContext.isOpenFor(fake));
        scopeB.close();
        scopeB.close();
        System.assert(ControlledWriteContext.isOpenFor(fake));
        scopeA.close();
        System.assert(!ControlledWriteContext.isOpenFor(fake));
        try {
            ControlledWriteContext.open(new Set<Id>(), 'x');
            System.assert(false);
        } catch (SubscriptionException e) {
            System.assertEquals(SubscriptionConstants.ERR_BYPASS_INVALIDO, e.code);
        }
        try {
            ControlledWriteContext.open(new Set<Id>{ fake }, ' ');
            System.assert(false);
        } catch (SubscriptionException e) {
            System.assertEquals(SubscriptionConstants.ERR_BYPASS_INVALIDO, e.code);
        }
    }

    @IsTest
    static void statusTransitionContextScoping() {
        Id fake = TestDataFactory.account('stc').Id;
        System.assert(!StatusTransitionContext.isAuthorized(fake, 'Aprovada'));
        StatusTransitionContext.Scope scope = StatusTransitionContext.open(new Set<Id>{ fake }, new Set<String>{ 'Aprovada' }, 'teste');
        System.assert(StatusTransitionContext.isAuthorized(fake, 'Aprovada'));
        System.assert(!StatusTransitionContext.isAuthorized(fake, 'Rejeitada'));
        scope.close();
        scope.close();
        System.assert(!StatusTransitionContext.isAuthorized(fake, 'Aprovada'));
        try {
            StatusTransitionContext.open(new Set<Id>(), new Set<String>{ 'Aprovada' }, 'x');
            System.assert(false);
        } catch (SubscriptionException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void recursionGuard() {
        Id fake = TestDataFactory.account('rg').Id;
        Set<Id> first = RecursionGuard.enter('S', new Set<Id>{ fake });
        System.assertEquals(1, first.size());
        System.assert(RecursionGuard.isInProgress('S', fake));
        System.assertEquals(0, RecursionGuard.enter('S', new Set<Id>{ fake }).size());
        RecursionGuard.exit('S', first);
        System.assert(!RecursionGuard.isInProgress('S', fake));
        Set<Id> byFp = RecursionGuard.enter('F', new Map<Id, String>{ fake => 'a' });
        System.assertEquals(1, byFp.size());
        System.assertEquals(0, RecursionGuard.enter('F', new Map<Id, String>{ fake => 'a' }).size());
        System.assertEquals(1, RecursionGuard.enter('F', new Map<Id, String>{ fake => 'b' }).size());
        RecursionGuard.exit('F', byFp);
        RecursionGuard.reset();
    }

    @IsTest
    static void technicalLoggerPersistsAndFormats() {
        Id logId = TechnicalLogger.log('Cls', 'm', null, new NullPointerException());
        System.assertNotEquals(null, logId);
        Log_Tecnico__c saved = [SELECT Classe__c, Metodo__c, Mensagem__c FROM Log_Tecnico__c WHERE Id = :logId];
        System.assertEquals('Cls', saved.Classe__c);
        Log_Tecnico__c big = TechnicalLogger.build('C', 'm', null, new SubscriptionException('X', 'z'.repeat(300)));
        System.assert(big.Mensagem__c.length() > 0);
        System.assertEquals(0, TechnicalLogger.persist(new List<Log_Tecnico__c>()).size());
        System.assertEquals(0, TechnicalLogger.persist(null).size());
        // persist nunca lanca, mesmo com registro invalido
        TechnicalLogger.persist(new List<Log_Tecnico__c>{ new Log_Tecnico__c(Classe__c = 'x'.repeat(300)) });
        System.assertEquals('regra', TechnicalLogger.friendlyMessage(new SubscriptionException('C', 'regra'), null));
        String generic = TechnicalLogger.friendlyMessage(new NullPointerException(), logId);
        System.assert(generic.contains(String.valueOf(logId)));
        System.assert(!TechnicalLogger.friendlyMessage(new NullPointerException(), null).contains('Código de referência:'));
        try {
            insert new Contrato_Assinatura__c();
        } catch (DmlException dml) {
            System.assertNotEquals(null, TechnicalLogger.friendlyMessage(dml, null));
        }
    }

    @IsTest
    static void securityGuardChecks() {
        User noPerm = TestDataFactory.user('nop', new List<String>(), new List<String>());
        System.runAs(noPerm) {
            System.assert(!SecurityGuard.hasCustomPermission(SubscriptionConstants.PERM_APLICAR_ALTERACAO));
            try {
                SecurityGuard.requireCustomPermission(SubscriptionConstants.PERM_APLICAR_ALTERACAO, 'sem');
                System.assert(false);
            } catch (SubscriptionException e) {
                System.assertEquals(SubscriptionConstants.ERR_SEM_PERMISSAO, e.code);
            }
            try {
                SecurityGuard.requireCreateable(Solicitacao_Alteracao__c.SObjectType);
                System.assert(false);
            } catch (SubscriptionException e) {
                System.assertEquals(SubscriptionConstants.ERR_SEM_ACESSO, e.code);
            }
            try {
                SecurityGuard.requireReadable(Solicitacao_Alteracao__c.SObjectType);
                System.assert(false);
            } catch (SubscriptionException e) {
                System.assert(true);
            }
            try {
                SecurityGuard.requireUpdateable(Solicitacao_Alteracao__c.SObjectType);
                System.assert(false);
            } catch (SubscriptionException e) {
                System.assert(true);
            }
            try {
                SecurityGuard.requireDeletable(Solicitacao_Alteracao__c.SObjectType);
                System.assert(false);
            } catch (SubscriptionException e) {
                System.assert(true);
            }
        }
        User seller = TestDataFactory.seller();
        System.runAs(seller) {
            System.assert(SecurityGuard.hasCustomPermission(SubscriptionConstants.PERM_APLICAR_ALTERACAO));
            SecurityGuard.requireCustomPermission(SubscriptionConstants.PERM_APLICAR_ALTERACAO, 'ok');
            SecurityGuard.requireCreateable(Solicitacao_Alteracao__c.SObjectType);
            SecurityGuard.requireReadable(Solicitacao_Alteracao__c.SObjectType);
            SecurityGuard.requireUpdateable(Solicitacao_Alteracao__c.SObjectType);
            SObjectAccessDecision decision = SecurityGuard.strip(AccessType.READABLE, new List<SObject>{ new Solicitacao_Alteracao__c() });
            System.assertNotEquals(null, decision);
        }
        User approver = TestDataFactory.approver('Aprovadores_Gerentes');
        System.runAs(approver) {
            System.assert(SecurityGuard.hasCustomPermission(SubscriptionConstants.PERM_APROVAR_GERENTE));
            System.assert(SecurityGuard.hasCustomPermission(SubscriptionConstants.PERM_APROVAR_DIRETOR));
            System.assert(!SecurityGuard.hasCustomPermission(SubscriptionConstants.PERM_APLICAR_ALTERACAO));
        }
    }
}
