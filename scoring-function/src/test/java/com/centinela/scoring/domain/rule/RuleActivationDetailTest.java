package com.centinela.scoring.domain.rule;

import com.centinela.scoring.domain.model.HistoricalTransaction;
import com.centinela.scoring.domain.model.RuleHit;
import com.centinela.scoring.domain.model.TransactionEvent;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Estas pruebas no verifican <b>si</b> una regla se activa — eso ya lo cubren las pruebas
 * de cada regla — sino <b>que deja registrado cuando lo hace</b>.
 *
 * <p>Existen porque el enunciado de Semana 3 es explicito: si el explicador no puede
 * producir la salida esperada, el defecto esta en el motor, no en el explicador. Cada
 * afirmacion de la explicacion objetivo se traduce aqui en un valor observado que debe
 * quedar persistido en el momento de la decision. Un dato que no se registra entonces no
 * se puede recuperar despues sin reprocesar la transaccion.
 */
class RuleActivationDetailTest {

    private static final OffsetDateTime NOW = OffsetDateTime.parse("2026-07-25T15:00:00Z");

    // "Se detectaron N transacciones de esta cuenta en los ultimos 4 minutos,
    //  cuando el promedio es de 1 cada 6 horas."
    // La regla exige superar maxAllowed=3, de modo que la rafaga minima que activa son
    // tres transacciones historicas mas la actual.
    @Test
    void velocity_records_the_real_elapsed_span_not_only_the_configured_window() {
        List<HistoricalTransaction> history = List.of(
                historical("tx-1", NOW.minusMinutes(1)),
                historical("tx-2", NOW.minusMinutes(2)),
                historical("tx-3", NOW.minusMinutes(4)),
                historical("tx-4", NOW.minusHours(24)));

        RuleHit hit = new VelocityRule().evaluate(transactionAt(NOW), history).orElseThrow();

        assertThat(hit.observedValues())
                .containsEntry("countInWindow", 4)
                .containsEntry("maxAllowed", 3)
                .containsEntry("windowMinutes", 60);
        // La ventana configurada son 60 minutos, pero la rafaga ocupo 4: describirla como
        // "en los ultimos 60 minutos" seria cierto y a la vez enganoso.
        assertThat(hit.observedValues().get("elapsedMinutesInWindow")).isEqualTo(4L);
    }

    @Test
    void velocity_records_the_account_baseline_cadence() {
        List<HistoricalTransaction> history = List.of(
                historical("tx-1", NOW.minusMinutes(1)),
                historical("tx-2", NOW.minusMinutes(2)),
                historical("tx-3", NOW.minusMinutes(4)),
                historical("tx-4", NOW.minusHours(24)));

        RuleHit hit = new VelocityRule().evaluate(transactionAt(NOW), history).orElseThrow();

        // 24 h de historial repartidas en 4 intervalos = 360 min, es decir "1 cada 6 horas".
        assertThat(hit.observedValues()).containsEntry("baselineAverageIntervalMinutes", 360.0);
        assertThat(hit.observedValues()).containsEntry("baselineSampleSize", 4);
    }

    @Test
    void velocity_omits_the_baseline_when_the_sample_is_too_small_to_support_it() {
        // Una sola transaccion historica no define ninguna cadencia. El motor debe
        // callarse en vez de dejar que el explicador invente un promedio.
        List<HistoricalTransaction> history = List.of(historical("tx-1", NOW.minusMinutes(1)));

        RuleHit hit = new VelocityRule(null, null, 30, 60, 1)
                .evaluate(transactionAt(NOW), history).orElseThrow();

        assertThat(hit.observedValues()).doesNotContainKey("baselineAverageIntervalMinutes");
    }

    // "El monto de $4.200.000 supera en 84x el promedio historico de la cuenta ($50.000)."
    @Test
    void atypical_amount_records_the_observed_multiplier_not_the_configured_one() {
        List<HistoricalTransaction> history = List.of(
                historicalAmount("tx-1", new BigDecimal("50000")),
                historicalAmount("tx-2", new BigDecimal("50000")));

        RuleHit hit = new AtypicalAmountRule()
                .evaluate(transactionAmount(new BigDecimal("4200000")), history)
                .orElseThrow();

        assertThat(hit.observedValues())
                .containsEntry("currentAmount", 4200000.0)
                .containsEntry("averageAmount", 50000.0)
                .containsEntry("multiplierThreshold", 3.0)
                .containsEntry("observedMultiplier", 84.0)
                .containsEntry("historySampleSize", 2)
                .containsEntry("currency", "COP");
    }

    // "La transaccion anterior se origino en Medellin hace 11 minutos;
    //  esta se origina en Madrid, a 8.000 km."
    @Test
    void geo_impossible_records_both_city_names() {
        List<HistoricalTransaction> history = List.of(new HistoricalTransaction(
                "tx-previous", new BigDecimal("10000"), NOW.minusMinutes(11),
                new BigDecimal("6.2442"), new BigDecimal("-75.5812"), "Medellin", "CO"));

        RuleHit hit = new GeoImpossibleRule().evaluate(madridTransaction(), history).orElseThrow();

        assertThat(hit.observedValues())
                .containsEntry("previousCity", "Medellin")
                .containsEntry("previousCountryCode", "CO")
                .containsEntry("previousTransactionId", "tx-previous")
                .containsEntry("currentCity", "Madrid")
                .containsEntry("currentCountryCode", "ES")
                .containsEntry("timeMinutes", 11L);
        assertThat((double) hit.observedValues().get("distanceKm")).isBetween(8000.0, 8600.0);
    }

    @Test
    void geo_impossible_omits_city_names_when_the_data_never_arrived() {
        // Historial sin ciudad: el explicador debe caer en la formulacion por distancia,
        // no fabricar un topónimo.
        List<HistoricalTransaction> history = List.of(new HistoricalTransaction(
                "tx-previous", new BigDecimal("10000"), NOW.minusMinutes(11),
                new BigDecimal("6.2442"), new BigDecimal("-75.5812")));

        RuleHit hit = new GeoImpossibleRule().evaluate(madridTransaction(), history).orElseThrow();

        assertThat(hit.observedValues()).doesNotContainKey("previousCity");
        assertThat(hit.observedValues()).containsKey("distanceKm");
    }

    private static TransactionEvent transactionAt(OffsetDateTime occurredAt) {
        return new TransactionEvent("tx-current", "acc-001", new BigDecimal("1000"), "COP", occurredAt,
                new TransactionEvent.EventLocation("CO", "Bogota", new BigDecimal("4.71"), new BigDecimal("-74.07")),
                new TransactionEvent.EventMerchant("Tienda", "retail"));
    }

    private static TransactionEvent transactionAmount(BigDecimal amount) {
        return new TransactionEvent("tx-current", "acc-001", amount, "COP", NOW,
                new TransactionEvent.EventLocation("CO", "Bogota", new BigDecimal("4.71"), new BigDecimal("-74.07")),
                new TransactionEvent.EventMerchant("Tienda", "retail"));
    }

    private static TransactionEvent madridTransaction() {
        return new TransactionEvent("tx-current", "acc-001", new BigDecimal("1000"), "COP", NOW,
                new TransactionEvent.EventLocation("ES", "Madrid", new BigDecimal("40.4168"), new BigDecimal("-3.7038")),
                new TransactionEvent.EventMerchant("Tienda", "retail"));
    }

    private static HistoricalTransaction historical(String id, OffsetDateTime occurredAt) {
        return new HistoricalTransaction(id, new BigDecimal("1000"), occurredAt, null, null);
    }

    private static HistoricalTransaction historicalAmount(String id, BigDecimal amount) {
        return new HistoricalTransaction(id, amount, NOW.minusDays(1), null, null);
    }
}
