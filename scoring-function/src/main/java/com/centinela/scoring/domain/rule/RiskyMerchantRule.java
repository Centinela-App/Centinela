package com.centinela.scoring.domain.rule;

import com.centinela.scoring.domain.model.HistoricalTransaction;
import com.centinela.scoring.domain.model.RuleHit;
import com.centinela.scoring.domain.model.TransactionEvent;

import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.stream.Collectors;

/**
 * Regla de dominio: Comercio o Categoria de Riesgo.
 *
 * <p>Se activa si el nombre o la categoria del comercio de la transaccion
 * coincide con la lista de comercios o categorias marcadas de riesgo.
 */
public final class RiskyMerchantRule implements ScoringRule {

    public static final String DEFAULT_RULE_ID = "risky-merchant";
    public static final String DEFAULT_RULE_NAME = "Comercio de Riesgo";
    public static final int DEFAULT_POINTS = 35;

    private final String ruleId;
    private final String ruleName;
    private final int points;
    private final Set<String> riskyMerchants;
    private final Set<String> riskyCategories;

    public RiskyMerchantRule(Set<String> riskyMerchants, Set<String> riskyCategories) {
        this(DEFAULT_RULE_ID, DEFAULT_RULE_NAME, DEFAULT_POINTS, riskyMerchants, riskyCategories);
    }

    public RiskyMerchantRule(String ruleId, String ruleName, int points, Set<String> riskyMerchants, Set<String> riskyCategories) {
        this.ruleId = ruleId != null ? ruleId : DEFAULT_RULE_ID;
        this.ruleName = ruleName != null ? ruleName : DEFAULT_RULE_NAME;
        this.points = points;
        this.riskyMerchants = normalizeSet(riskyMerchants);
        this.riskyCategories = normalizeSet(riskyCategories);
    }

    @Override
    public String ruleId() {
        return ruleId;
    }

    @Override
    public Optional<RuleHit> evaluate(TransactionEvent transaction, List<HistoricalTransaction> history) {
        if (transaction == null || transaction.merchant() == null) {
            return Optional.empty();
        }

        String merchantName = transaction.merchant().name() != null ? transaction.merchant().name().trim() : "";
        String merchantCategory = transaction.merchant().category() != null ? transaction.merchant().category().trim() : "";

        boolean matchMerchant = !merchantName.isEmpty() && riskyMerchants.contains(merchantName.toLowerCase());
        boolean matchCategory = !merchantCategory.isEmpty() && riskyCategories.contains(merchantCategory.toLowerCase());

        if (matchMerchant || matchCategory) {
            Map<String, Object> observedValues = new LinkedHashMap<>();
            observedValues.put("merchantName", merchantName);
            observedValues.put("merchantCategory", merchantCategory);
            observedValues.put("matchedRiskFactor", matchMerchant ? "MERCHANT_NAME" : "MERCHANT_CATEGORY");

            return Optional.of(new RuleHit(ruleId, ruleName, points, observedValues));
        }

        return Optional.empty();
    }

    private static Set<String> normalizeSet(Set<String> input) {
        if (input == null || input.isEmpty()) {
            return Collections.emptySet();
        }
        return input.stream()
                .filter(s -> s != null && !s.isBlank())
                .map(String::trim)
                .map(String::toLowerCase)
                .collect(Collectors.toUnmodifiableSet());
    }
}
