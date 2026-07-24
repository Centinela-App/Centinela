package com.centinela.scoring.domain.rule;

import com.centinela.scoring.domain.model.HistoricalTransaction;
import com.centinela.scoring.domain.model.RuleHit;
import com.centinela.scoring.domain.model.TransactionEvent;

import java.time.OffsetDateTime;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * Regla de dominio: Velocidad / Frecuencia de transacciones.
 *
 * <p>Se activa si el numero de transacciones en una ventana de tiempo
 * (incluyendo la transaccion actual) supera un umbral maximo permitido.
 */
public final class VelocityRule implements ScoringRule {

    public static final String DEFAULT_RULE_ID = "velocity";
    public static final String DEFAULT_RULE_NAME = "Velocidad";
    public static final int DEFAULT_POINTS = 30;
    public static final int DEFAULT_WINDOW_MINUTES = 60;
    public static final int DEFAULT_MAX_ALLOWED = 3;

    private final String ruleId;
    private final String ruleName;
    private final int points;
    private final int windowMinutes;
    private final int maxAllowed;

    public VelocityRule() {
        this(DEFAULT_RULE_ID, DEFAULT_RULE_NAME, DEFAULT_POINTS, DEFAULT_WINDOW_MINUTES, DEFAULT_MAX_ALLOWED);
    }

    public VelocityRule(String ruleId, String ruleName, int points, int windowMinutes, int maxAllowed) {
        this.ruleId = ruleId != null ? ruleId : DEFAULT_RULE_ID;
        this.ruleName = ruleName != null ? ruleName : DEFAULT_RULE_NAME;
        this.points = points;
        this.windowMinutes = windowMinutes;
        this.maxAllowed = maxAllowed;
    }

    @Override
    public String ruleId() {
        return ruleId;
    }

    @Override
    public Optional<RuleHit> evaluate(TransactionEvent transaction, List<HistoricalTransaction> history) {
        if (transaction == null || transaction.occurredAt() == null) {
            return Optional.empty();
        }

        OffsetDateTime currentTxTime = transaction.occurredAt();
        OffsetDateTime windowStart = currentTxTime.minusMinutes(windowMinutes);

        long historyCountInWindow = (history == null) ? 0 : history.stream()
                .filter(h -> h.occurredAt() != null)
                .filter(h -> !h.occurredAt().isBefore(windowStart) && !h.occurredAt().isAfter(currentTxTime))
                .count();

        int countInWindow = (int) historyCountInWindow + 1; // Incluye la transaccion actual evaluada

        if (countInWindow > maxAllowed) {
            Map<String, Object> observedValues = new LinkedHashMap<>();
            observedValues.put("countInWindow", countInWindow);
            observedValues.put("windowMinutes", windowMinutes);
            observedValues.put("maxAllowed", maxAllowed);

            return Optional.of(new RuleHit(ruleId, ruleName, points, observedValues));
        }

        return Optional.empty();
    }
}
