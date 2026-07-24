package com.centinela.scoring.domain.rule;

import com.centinela.scoring.domain.model.HistoricalTransaction;
import com.centinela.scoring.domain.model.RuleHit;
import com.centinela.scoring.domain.model.TransactionEvent;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Optional;

/**
 * Regla de dominio: Monto Atipico.
 *
 * <p>Se activa si el monto de la transaccion actual excede significativamente
 * el promedio del historial de la cuenta (monto observado vs. promedio).
 */
public final class AtypicalAmountRule implements ScoringRule {

    public static final String DEFAULT_RULE_ID = "atypical-amount";
    public static final String DEFAULT_RULE_NAME = "Monto Atípico";
    public static final int DEFAULT_POINTS = 25;
    public static final double DEFAULT_MULTIPLIER_THRESHOLD = 3.0;

    private final String ruleId;
    private final String ruleName;
    private final int points;
    private final double multiplierThreshold;

    public AtypicalAmountRule() {
        this(DEFAULT_RULE_ID, DEFAULT_RULE_NAME, DEFAULT_POINTS, DEFAULT_MULTIPLIER_THRESHOLD);
    }

    public AtypicalAmountRule(String ruleId, String ruleName, int points, double multiplierThreshold) {
        this.ruleId = ruleId != null ? ruleId : DEFAULT_RULE_ID;
        this.ruleName = ruleName != null ? ruleName : DEFAULT_RULE_NAME;
        this.points = points;
        this.multiplierThreshold = multiplierThreshold;
    }

    @Override
    public String ruleId() {
        return ruleId;
    }

    @Override
    public Optional<RuleHit> evaluate(TransactionEvent transaction, List<HistoricalTransaction> history) {
        if (transaction == null || transaction.amount() == null || history == null || history.isEmpty()) {
            return Optional.empty();
        }

        List<BigDecimal> validAmounts = history.stream()
                .map(HistoricalTransaction::amount)
                .filter(Objects::nonNull)
                .toList();

        if (validAmounts.isEmpty()) {
            return Optional.empty();
        }

        BigDecimal sum = validAmounts.stream().reduce(BigDecimal.ZERO, BigDecimal::add);
        BigDecimal average = sum.divide(BigDecimal.valueOf(validAmounts.size()), 2, RoundingMode.HALF_UP);

        BigDecimal thresholdAmount = average.multiply(BigDecimal.valueOf(multiplierThreshold));

        if (transaction.amount().compareTo(thresholdAmount) > 0) {
            Map<String, Object> observedValues = new LinkedHashMap<>();
            observedValues.put("currentAmount", transaction.amount().doubleValue());
            observedValues.put("averageAmount", average.doubleValue());
            observedValues.put("multiplierThreshold", multiplierThreshold);

            return Optional.of(new RuleHit(ruleId, ruleName, points, observedValues));
        }

        return Optional.empty();
    }
}
