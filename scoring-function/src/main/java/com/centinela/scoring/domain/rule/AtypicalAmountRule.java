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
 *
 * <p><b>Que registra y por que.</b> La frase objetivo — "el monto de $4.200.000 supera en
 * 84x el promedio historico de la cuenta ($50.000)" — necesita el multiplicador
 * <i>observado</i>, no el configurado. El umbral de la regla puede ser 3x mientras lo
 * observado es 84x: informar el primero como si fuera el segundo tergiversa el hallazgo.
 * Tambien se registra el tamano de la muestra, porque un promedio calculado sobre dos
 * transacciones no merece la misma confianza que uno sobre cincuenta.
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

        if (transaction.amount().compareTo(thresholdAmount) <= 0) {
            return Optional.empty();
        }

        Map<String, Object> observedValues = new LinkedHashMap<>();
        observedValues.put("currentAmount", transaction.amount().doubleValue());
        observedValues.put("averageAmount", average.doubleValue());
        observedValues.put("multiplierThreshold", multiplierThreshold);
        observedValues.put("historySampleSize", validAmounts.size());

        observedMultiplier(transaction.amount(), average)
                .ifPresent(observed -> observedValues.put("observedMultiplier", observed));
        if (transaction.currency() != null && !transaction.currency().isBlank()) {
            observedValues.put("currency", transaction.currency());
        }

        return Optional.of(new RuleHit(ruleId, ruleName, points, observedValues));
    }

    /**
     * Cuantas veces el monto actual supera al promedio.
     *
     * @return vacio si el promedio es cero — la division seria indefinida y "infinitas
     *         veces el promedio" no es una afirmacion que el explicador deba emitir
     */
    private static Optional<Double> observedMultiplier(BigDecimal currentAmount, BigDecimal average) {
        if (average.compareTo(BigDecimal.ZERO) == 0) {
            return Optional.empty();
        }
        return Optional.of(currentAmount.divide(average, 2, RoundingMode.HALF_UP).doubleValue());
    }
}
