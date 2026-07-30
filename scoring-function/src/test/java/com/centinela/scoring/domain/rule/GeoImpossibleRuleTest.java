package com.centinela.scoring.domain.rule;

import com.centinela.scoring.domain.model.HistoricalTransaction;
import com.centinela.scoring.domain.model.RuleHit;
import com.centinela.scoring.domain.model.TransactionEvent;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * TEST-S2-012: Regla geo-imposible se activa.
 * Escenario Gherkin: Ubicaciones incompatibles.
 */
class GeoImpossibleRuleTest {

    @Test
    @DisplayName("TEST-S2-012 & Gherkin: Debe activarse y registrar distancia y tiempo observados ante ubicaciones incompatibles")
    void debeActivarseYRegistrarDistanciaYTiempoObservados() {
        // Given - Dos transacciones de una cuenta con distancia/tiempo imposibles (NYC -> Tokio en 10 minutos)
        GeoImpossibleRule rule = new GeoImpossibleRule("geo-impossible", "Geo-Imposible", 40, 800.0);

        OffsetDateTime prevTime = OffsetDateTime.parse("2024-01-15T12:00:00Z");
        OffsetDateTime currentTime = OffsetDateTime.parse("2024-01-15T12:10:00Z"); // 10 minutos despues

        // Tokio: lat 35.6762, lon 139.6503
        TransactionEvent currentTx = new TransactionEvent(
                "tx-tokyo",
                "acc-001",
                BigDecimal.valueOf(150.0),
                "USD",
                currentTime,
                new TransactionEvent.EventLocation("JP", "Tokyo", BigDecimal.valueOf(35.6762), BigDecimal.valueOf(139.6503)),
                new TransactionEvent.EventMerchant("Tokyo Store", "retail")
        );

        // Nueva York: lat 40.7128, lon -74.0060
        List<HistoricalTransaction> history = List.of(
                new HistoricalTransaction(
                        "tx-nyc",
                        BigDecimal.valueOf(100.0),
                        prevTime,
                        BigDecimal.valueOf(40.7128),
                        BigDecimal.valueOf(-74.0060)
                )
        );

        // When - Se evalua la regla geo-imposible
        Optional<RuleHit> result = rule.evaluate(currentTx, history);

        // Then - Se activa y registra distancia y tiempo observados
        assertThat(result).isPresent();
        RuleHit hit = result.get();

        assertThat(hit.ruleId()).isEqualTo("geo-impossible");
        assertThat(hit.points()).isEqualTo(40);

        assertThat(hit.observedValues())
                .containsKey("distanceKm")
                .containsKey("timeMinutes")
                .containsKey("calculatedSpeedKmh");

        double distanceKm = (double) hit.observedValues().get("distanceKm");
        long timeMinutes = (long) hit.observedValues().get("timeMinutes");

        assertThat(distanceKm).isGreaterThan(10000.0); // NYC a Tokio es > 10,000 km
        assertThat(timeMinutes).isEqualTo(10L);
    }

    @Test
    @DisplayName("No debe activarse cuando la distancia/tiempo es razonable (ej. misma ciudad)")
    void noDebeActivarseCuandoDistanciaYTiempoSonRazonables() {
        GeoImpossibleRule rule = new GeoImpossibleRule("geo-impossible", "Geo-Imposible", 40, 800.0);

        OffsetDateTime prevTime = OffsetDateTime.parse("2024-01-15T12:00:00Z");
        OffsetDateTime currentTime = OffsetDateTime.parse("2024-01-15T12:30:00Z");

        // 2 km de distancia en 30 min (velocidad ~4 km/h)
        TransactionEvent currentTx = new TransactionEvent(
                "tx-2",
                "acc-001",
                BigDecimal.valueOf(50.0),
                "USD",
                currentTime,
                new TransactionEvent.EventLocation("US", "NYC", BigDecimal.valueOf(40.7130), BigDecimal.valueOf(-74.0065)),
                new TransactionEvent.EventMerchant("Cafe", "food")
        );

        List<HistoricalTransaction> history = List.of(
                new HistoricalTransaction("tx-1", BigDecimal.valueOf(20.0), prevTime, BigDecimal.valueOf(40.7128), BigDecimal.valueOf(-74.0060))
        );

        Optional<RuleHit> result = rule.evaluate(currentTx, history);

        assertThat(result).isEmpty();
    }
}
