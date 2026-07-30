package com.centinela.scoring.domain.rule;

import com.centinela.scoring.domain.model.HistoricalTransaction;
import com.centinela.scoring.domain.model.RuleHit;
import com.centinela.scoring.domain.model.TransactionEvent;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.Duration;
import java.time.OffsetDateTime;
import java.time.format.DateTimeFormatter;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * Regla de dominio: Geo-Imposible.
 *
 * <p>Se activa cuando la distancia y el tiempo transcurrido entre la transaccion
 * actual y la ultima transaccion registrada implican una velocidad de desplazamiento
 * fisicamente imposible (ej. &gt; 800 km/h).
 *
 * <p><b>Que registra y por que.</b> La decision se toma con coordenadas; la explicacion
 * se da con nombres. "La transaccion anterior se origino en Medellin hace 11 minutos;
 * esta se origina en Madrid, a 8.000 km" exige que el motor guarde las ciudades de ambos
 * extremos, no solo la distancia resultante. Tambien se registra el identificador de la
 * transaccion anterior: sin el, un analista que quiera auditar la comparacion no tiene
 * como localizar el otro extremo.
 *
 * <p>Las ciudades se omiten si el dato no viene en el evento o en el historial. El
 * explicador degrada a la formulacion por distancia en vez de inventar un topónimo.
 */
public final class GeoImpossibleRule implements ScoringRule {

    public static final String DEFAULT_RULE_ID = "geo-impossible";
    public static final String DEFAULT_RULE_NAME = "Geo-Imposible";
    public static final int DEFAULT_POINTS = 40;
    public static final double DEFAULT_MAX_SPEED_KMH = 800.0; // km/h

    private static final double EARTH_RADIUS_KM = 6371.0;

    private final String ruleId;
    private final String ruleName;
    private final int points;
    private final double maxSpeedKmh;

    public GeoImpossibleRule() {
        this(DEFAULT_RULE_ID, DEFAULT_RULE_NAME, DEFAULT_POINTS, DEFAULT_MAX_SPEED_KMH);
    }

    public GeoImpossibleRule(String ruleId, String ruleName, int points, double maxSpeedKmh) {
        this.ruleId = ruleId != null ? ruleId : DEFAULT_RULE_ID;
        this.ruleName = ruleName != null ? ruleName : DEFAULT_RULE_NAME;
        this.points = points;
        this.maxSpeedKmh = maxSpeedKmh;
    }

    @Override
    public String ruleId() {
        return ruleId;
    }

    @Override
    public Optional<RuleHit> evaluate(TransactionEvent transaction, List<HistoricalTransaction> history) {
        if (transaction == null || transaction.location() == null || history == null || history.isEmpty()) {
            return Optional.empty();
        }

        TransactionEvent.EventLocation currentLocation = transaction.location();
        if (currentLocation.latitude() == null || currentLocation.longitude() == null || transaction.occurredAt() == null) {
            return Optional.empty();
        }

        // Buscar la transaccion mas reciente en el historial previa a la actual
        Optional<HistoricalTransaction> previousTx = history.stream()
                .filter(h -> h.occurredAt() != null && h.latitude() != null && h.longitude() != null)
                .filter(h -> !h.occurredAt().isAfter(transaction.occurredAt()))
                .max(Comparator.comparing(HistoricalTransaction::occurredAt));

        if (previousTx.isEmpty()) {
            return Optional.empty();
        }

        HistoricalTransaction prev = previousTx.get();
        OffsetDateTime currentTxTime = transaction.occurredAt();
        OffsetDateTime prevTxTime = prev.occurredAt();

        long secondsElapsed = Math.abs(Duration.between(prevTxTime, currentTxTime).getSeconds());
        long timeMinutes = Math.max(1, secondsElapsed / 60);

        double distanceKm = calculateHaversineDistanceKm(
                currentLocation.latitude().doubleValue(),
                currentLocation.longitude().doubleValue(),
                prev.latitude().doubleValue(),
                prev.longitude().doubleValue()
        );

        double hoursElapsed = Math.max(secondsElapsed / 3600.0, 0.0001);
        double calculatedSpeedKmh = distanceKm / hoursElapsed;

        if (calculatedSpeedKmh <= maxSpeedKmh) {
            return Optional.empty();
        }

        Map<String, Object> observedValues = new LinkedHashMap<>();
        observedValues.put("distanceKm", round(distanceKm));
        observedValues.put("timeMinutes", timeMinutes);
        observedValues.put("calculatedSpeedKmh", round(calculatedSpeedKmh));
        observedValues.put("maxSpeedKmh", maxSpeedKmh);

        putIfPresent(observedValues, "previousCity", prev.city());
        putIfPresent(observedValues, "previousCountryCode", prev.countryCode());
        putIfPresent(observedValues, "previousTransactionId", prev.transactionId());
        observedValues.put("previousOccurredAt", DateTimeFormatter.ISO_OFFSET_DATE_TIME.format(prevTxTime));

        putIfPresent(observedValues, "currentCity", currentLocation.city());
        putIfPresent(observedValues, "currentCountryCode", currentLocation.countryCode());

        return Optional.of(new RuleHit(ruleId, ruleName, points, observedValues));
    }

    /**
     * {@code Map.copyOf} en {@code RuleHit} rechaza valores nulos, y un campo ausente no
     * es lo mismo que un campo vacio: si el dato no existe, la clave no debe existir.
     */
    private static void putIfPresent(Map<String, Object> target, String key, String value) {
        if (value != null && !value.isBlank()) {
            target.put(key, value);
        }
    }

    private static double round(double value) {
        return BigDecimal.valueOf(value).setScale(2, RoundingMode.HALF_UP).doubleValue();
    }

    private static double calculateHaversineDistanceKm(double lat1, double lon1, double lat2, double lon2) {
        double dLat = Math.toRadians(lat2 - lat1);
        double dLon = Math.toRadians(lon2 - lon1);

        double radLat1 = Math.toRadians(lat1);
        double radLat2 = Math.toRadians(lat2);

        double a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
                + Math.sin(dLon / 2) * Math.sin(dLon / 2) * Math.cos(radLat1) * Math.cos(radLat2);
        double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

        return EARTH_RADIUS_KM * c;
    }
}
