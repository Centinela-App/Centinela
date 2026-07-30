package com.centinela.scoring.application.service;

import com.centinela.scoring.application.config.ScoringThresholdProvider;
import com.centinela.scoring.domain.model.HistoricalTransaction;
import com.centinela.scoring.domain.model.RuleHit;
import com.centinela.scoring.domain.model.Score;
import com.centinela.scoring.domain.model.TransactionEvent;
import com.centinela.scoring.domain.rule.AtypicalAmountRule;
import com.centinela.scoring.domain.rule.GeoImpossibleRule;
import com.centinela.scoring.domain.rule.RiskyMerchantRule;
import com.centinela.scoring.domain.rule.ScoringRule;
import com.centinela.scoring.domain.rule.VelocityRule;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.Clock;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.List;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Cobertura de pruebas integradas y unitarias para ScoreTransactionService:
 * - TEST-S2-014: Umbral cambia sin redespliegue (Gherkin: Umbral en caliente)
 * - TEST-S2-015: Detalle de activacion con valores observados (Gherkin: Detalle de activacion)
 * - Suma total de puntos de las reglas activadas
 */
class ScoreTransactionServiceTest {

    private final Clock fixedClock = Clock.fixed(Instant.parse("2024-01-15T12:00:00Z"), ZoneOffset.UTC);
    private final OffsetDateTime now = OffsetDateTime.parse("2024-01-15T12:00:00Z");

    @Nested
    @DisplayName("TEST-S2-014: Umbral cambia sin redespliegue (Escenario Gherkin: Umbral en caliente)")
    class UmbralEnCalienteTest {

        @Test
        @DisplayName("TEST-S2-014: Una misma transaccion cruza o no el umbral segun el nuevo valor dinámico")
        void debeCambiarComportamientoAlModificarUmbralEnCaliente() {
            // Given - Un umbral configurable dinamico mediante Supplier (sin redesplegar ni recompilar)
            AtomicInteger dynamicThreshold = new AtomicInteger(50);
            ScoringThresholdProvider provider = new ScoringThresholdProvider(
                    dynamicThreshold::get,
                    () -> Set.of("Casino Royal"),
                    () -> Set.of("gambling")
            );

            List<ScoringRule> rules = List.of(
                    new VelocityRule("velocity", "Velocidad", 30, 60, 3),
                    new RiskyMerchantRule("risky-merchant", "Comercio de Riesgo", 35, Set.of("Casino Royal"), Set.of("gambling"))
            );

            ScoreTransactionService service = new ScoreTransactionService(rules, provider, fixedClock);

            // Transaccion que activa ambas reglas -> Score total = 30 + 35 = 65 puntos
            TransactionEvent transaction = new TransactionEvent(
                    "tx-hot-001",
                    "acc-hot",
                    BigDecimal.valueOf(100.0),
                    "USD",
                    now,
                    new TransactionEvent.EventLocation("US", "Vegas", BigDecimal.valueOf(36.16), BigDecimal.valueOf(-115.13)),
                    new TransactionEvent.EventMerchant("Casino Royal", "gambling")
            );

            List<HistoricalTransaction> history = List.of(
                    new HistoricalTransaction("tx-h1", BigDecimal.valueOf(50.0), now.minusMinutes(10), BigDecimal.valueOf(36.16), BigDecimal.valueOf(-115.13)),
                    new HistoricalTransaction("tx-h2", BigDecimal.valueOf(50.0), now.minusMinutes(20), BigDecimal.valueOf(36.16), BigDecimal.valueOf(-115.13)),
                    new HistoricalTransaction("tx-h3", BigDecimal.valueOf(50.0), now.minusMinutes(30), BigDecimal.valueOf(36.16), BigDecimal.valueOf(-115.13))
            );

            // When - Primer calculo con umbral = 50 -> Score (65) >= Umbral (50) -> Cruza umbral
            Score scoreInitial = service.executeScoring(transaction, history);
            assertThat(scoreInitial.totalScore()).isEqualTo(65);
            assertThat(scoreInitial.totalScore() >= provider.getThreshold()).isTrue();

            // When - Se cambia el umbral en caliente a 70 sin redesplegar
            dynamicThreshold.set(70);

            // Then - La misma transaccion con Score (65) < Umbral (70) -> Ya NO cruza el umbral
            Score scoreSecond = service.executeScoring(transaction, history);
            assertThat(scoreSecond.totalScore()).isEqualTo(65);
            assertThat(scoreSecond.totalScore() >= provider.getThreshold()).isFalse();
        }
    }

    @Nested
    @DisplayName("TEST-S2-015: Detalle de activacion (Escenario Gherkin: Detalle de activacion)")
    class DetalleActivacionTest {

        @Test
        @DisplayName("TEST-S2-015: Regla activada contiene valores concretos observados y no solo su id")
        void debeContenerValoresConcretosObservados() {
            List<ScoringRule> rules = List.of(
                    new VelocityRule("velocity", "Velocidad", 30, 60, 2),
                    new AtypicalAmountRule("atypical-amount", "Monto Atípico", 25, 3.0),
                    new GeoImpossibleRule("geo-impossible", "Geo-Imposible", 40, 800.0),
                    new RiskyMerchantRule("risky-merchant", "Comercio de Riesgo", 35, Set.of("BetCrypto"), Set.of("crypto"))
            );

            ScoringThresholdProvider provider = new ScoringThresholdProvider(() -> 50, () -> Set.of("BetCrypto"), () -> Set.of("crypto"));
            ScoreTransactionService service = new ScoreTransactionService(rules, provider, fixedClock);

            // Transaccion en Tokio (lat 35.67, lon 139.65) por 5,000 USD en BetCrypto
            TransactionEvent transaction = new TransactionEvent(
                    "tx-detail-001",
                    "acc-detail",
                    BigDecimal.valueOf(5000.0),
                    "USD",
                    now,
                    new TransactionEvent.EventLocation("JP", "Tokyo", BigDecimal.valueOf(35.6762), BigDecimal.valueOf(139.6503)),
                    new TransactionEvent.EventMerchant("BetCrypto", "crypto")
            );

            // Historial hace 10 minutos en Nueva York (lat 40.71, lon -74.00) promedio de $100
            List<HistoricalTransaction> history = List.of(
                    new HistoricalTransaction("tx-h1", BigDecimal.valueOf(100.0), now.minusMinutes(10), BigDecimal.valueOf(40.7128), BigDecimal.valueOf(-74.0060)),
                    new HistoricalTransaction("tx-h2", BigDecimal.valueOf(100.0), now.minusMinutes(20), BigDecimal.valueOf(40.7128), BigDecimal.valueOf(-74.0060)),
                    new HistoricalTransaction("tx-h3", BigDecimal.valueOf(100.0), now.minusMinutes(30), BigDecimal.valueOf(40.7128), BigDecimal.valueOf(-74.0060))
            );

            Score result = service.executeScoring(transaction, history);

            // Score debe ser la suma de las 4 reglas activadas: 30 + 25 + 40 + 35 = 130
            assertThat(result.totalScore()).isEqualTo(130);
            assertThat(result.triggeredRules()).hasSize(4);

            // Inspeccionar detalle por cada regla activada
            for (RuleHit hit : result.triggeredRules()) {
                assertThat(hit.ruleId()).isNotBlank();
                assertThat(hit.ruleName()).isNotBlank();
                assertThat(hit.points()).isGreaterThan(0);

                // La regla contiene los valores concretos que la activaron, NO SOLO su id
                assertThat(hit.observedValues())
                        .isNotNull()
                        .isNotEmpty();
            }

            // Verificar valores concretos especificos por regla
            RuleHit velocityHit = result.triggeredRules().stream().filter(r -> r.ruleId().equals("velocity")).findFirst().orElseThrow();
            assertThat(velocityHit.observedValues()).containsEntry("countInWindow", 4);

            RuleHit amountHit = result.triggeredRules().stream().filter(r -> r.ruleId().equals("atypical-amount")).findFirst().orElseThrow();
            assertThat(amountHit.observedValues()).containsEntry("currentAmount", 5000.0).containsEntry("averageAmount", 100.0);

            RuleHit geoHit = result.triggeredRules().stream().filter(r -> r.ruleId().equals("geo-impossible")).findFirst().orElseThrow();
            assertThat(geoHit.observedValues()).containsKey("distanceKm").containsKey("timeMinutes");

            RuleHit merchantHit = result.triggeredRules().stream().filter(r -> r.ruleId().equals("risky-merchant")).findFirst().orElseThrow();
            assertThat(merchantHit.observedValues()).containsEntry("merchantName", "BetCrypto");
        }
    }
}
