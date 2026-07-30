package com.centinela.scoring.domain.rule;

import com.centinela.scoring.domain.model.HistoricalTransaction;
import com.centinela.scoring.domain.model.RuleHit;
import com.centinela.scoring.domain.model.TransactionEvent;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.Duration;
import java.time.OffsetDateTime;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * Regla de dominio: Velocidad / Frecuencia de transacciones.
 *
 * <p>Se activa si el numero de transacciones en una ventana de tiempo
 * (incluyendo la transaccion actual) supera un umbral maximo permitido.
 *
 * <p><b>Que registra y por que.</b> Saber que se superaron 3 transacciones en 60 minutos
 * basta para <i>decidir</i>, pero no para <i>explicar</i>. La explicacion que exige
 * Semana 3 contrasta lo observado con lo habitual de la cuenta: "3 transacciones en los
 * ultimos 4 minutos, cuando el promedio es de 1 cada 6 horas". Eso obliga a registrar
 * dos cosas mas que la decision no necesita:
 *
 * <ul>
 *   <li>{@code elapsedMinutesInWindow}: el lapso <b>real</b> que abarcan esas
 *       transacciones. La ventana configurada son 60 minutos, pero si las tres ocurrieron
 *       en 4, decir "en los ultimos 60 minutos" seria cierto y a la vez enganoso.</li>
 *   <li>{@code baselineAverageIntervalMinutes}: el intervalo medio entre transacciones
 *       de esta cuenta en el historial disponible. Es el "cuando lo normal es...".</li>
 * </ul>
 *
 * <p>La linea base se omite cuando el historial tiene menos de dos transacciones: con una
 * sola no hay intervalo que promediar, y el explicador no debe afirmar lo que el motor no
 * midio.
 */
public final class VelocityRule implements ScoringRule {

    public static final String DEFAULT_RULE_ID = "velocity";
    public static final String DEFAULT_RULE_NAME = "Velocidad";
    public static final int DEFAULT_POINTS = 30;
    public static final int DEFAULT_WINDOW_MINUTES = 60;
    public static final int DEFAULT_MAX_ALLOWED = 3;

    private static final int MINIMUM_SAMPLE_FOR_BASELINE = 2;

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

        List<HistoricalTransaction> dated = (history == null) ? List.of() : history.stream()
                .filter(h -> h.occurredAt() != null)
                .toList();

        List<HistoricalTransaction> inWindow = dated.stream()
                .filter(h -> !h.occurredAt().isBefore(windowStart) && !h.occurredAt().isAfter(currentTxTime))
                .toList();

        int countInWindow = inWindow.size() + 1; // Incluye la transaccion actual evaluada

        if (countInWindow <= maxAllowed) {
            return Optional.empty();
        }

        Map<String, Object> observedValues = new LinkedHashMap<>();
        observedValues.put("countInWindow", countInWindow);
        observedValues.put("windowMinutes", windowMinutes);
        observedValues.put("maxAllowed", maxAllowed);
        observedValues.put("elapsedMinutesInWindow", elapsedMinutesInWindow(inWindow, currentTxTime));

        baselineAverageIntervalMinutes(dated, currentTxTime).ifPresent(baseline -> {
            observedValues.put("baselineAverageIntervalMinutes", baseline);
            observedValues.put("baselineSampleSize", dated.size());
        });

        return Optional.of(new RuleHit(ruleId, ruleName, points, observedValues));
    }

    /**
     * Lapso real cubierto por las transacciones de la rafaga, de la mas antigua dentro de
     * la ventana hasta la actual. Se redondea hacia arriba a 1 para que una rafaga de
     * segundos no se describa como "en 0 minutos".
     */
    private static long elapsedMinutesInWindow(List<HistoricalTransaction> inWindow, OffsetDateTime currentTxTime) {
        return inWindow.stream()
                .map(HistoricalTransaction::occurredAt)
                .min(Comparator.naturalOrder())
                .map(oldest -> Math.max(1, Duration.between(oldest, currentTxTime).toMinutes()))
                .orElse(0L);
    }

    /**
     * Intervalo medio entre transacciones de la cuenta, en minutos, calculado sobre el
     * historial disponible mas la transaccion actual.
     *
     * @return vacio si no hay al menos dos transacciones historicas o si todas comparten
     *         el mismo instante (intervalo cero, que no describe ninguna cadencia)
     */
    private static Optional<Double> baselineAverageIntervalMinutes(
            List<HistoricalTransaction> dated, OffsetDateTime currentTxTime) {
        if (dated.size() < MINIMUM_SAMPLE_FOR_BASELINE) {
            return Optional.empty();
        }
        OffsetDateTime oldest = dated.stream()
                .map(HistoricalTransaction::occurredAt)
                .min(Comparator.naturalOrder())
                .orElseThrow();

        long spanMinutes = Duration.between(oldest, currentTxTime).toMinutes();
        if (spanMinutes <= 0) {
            return Optional.empty();
        }
        double average = (double) spanMinutes / dated.size();
        return Optional.of(BigDecimal.valueOf(average).setScale(2, RoundingMode.HALF_UP).doubleValue());
    }
}
