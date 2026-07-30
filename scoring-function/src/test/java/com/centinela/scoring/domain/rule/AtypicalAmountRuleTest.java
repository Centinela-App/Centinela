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
 * TEST-S2-011: Regla de monto atipico se activa.
 */
class AtypicalAmountRuleTest {

    @Test
    @DisplayName("TEST-S2-011: Debe activarse cuando el monto observado supera 3x el promedio historico")
    void debeActivarseCuandoMontoEsAtipico() {
        AtypicalAmountRule rule = new AtypicalAmountRule("atypical-amount", "Monto Atípico", 25, 3.0);

        OffsetDateTime now = OffsetDateTime.parse("2024-01-15T12:00:00Z");

        // Monto actual = 5000.0, promedio historico = (400 + 600) / 2 = 500.0 (5000 > 1500)
        TransactionEvent current = new TransactionEvent(
                "tx-current",
                "acc-001",
                BigDecimal.valueOf(5000.0),
                "USD",
                now,
                new TransactionEvent.EventLocation("US", "NYC", BigDecimal.valueOf(40.71), BigDecimal.valueOf(-74.00)),
                new TransactionEvent.EventMerchant("Luxury Store", "retail")
        );

        List<HistoricalTransaction> history = List.of(
                new HistoricalTransaction("tx-h1", BigDecimal.valueOf(400.0), now.minusDays(1), BigDecimal.valueOf(40.71), BigDecimal.valueOf(-74.00)),
                new HistoricalTransaction("tx-h2", BigDecimal.valueOf(600.0), now.minusDays(2), BigDecimal.valueOf(40.71), BigDecimal.valueOf(-74.00))
        );

        Optional<RuleHit> result = rule.evaluate(current, history);

        assertThat(result).isPresent();
        RuleHit hit = result.get();

        assertThat(hit.ruleId()).isEqualTo("atypical-amount");
        assertThat(hit.points()).isEqualTo(25);

        assertThat(hit.observedValues())
                .containsEntry("currentAmount", 5000.0)
                .containsEntry("averageAmount", 500.0)
                .containsEntry("multiplierThreshold", 3.0);
    }

    @Test
    @DisplayName("No debe activarse cuando el monto es similar al promedio historico")
    void noDebeActivarseCuandoMontoEsNormal() {
        AtypicalAmountRule rule = new AtypicalAmountRule("atypical-amount", "Monto Atípico", 25, 3.0);

        OffsetDateTime now = OffsetDateTime.parse("2024-01-15T12:00:00Z");

        TransactionEvent current = new TransactionEvent(
                "tx-current",
                "acc-001",
                BigDecimal.valueOf(600.0),
                "USD",
                now,
                new TransactionEvent.EventLocation("US", "NYC", BigDecimal.valueOf(40.71), BigDecimal.valueOf(-74.00)),
                new TransactionEvent.EventMerchant("Grocery", "retail")
        );

        List<HistoricalTransaction> history = List.of(
                new HistoricalTransaction("tx-h1", BigDecimal.valueOf(500.0), now.minusDays(1), BigDecimal.valueOf(40.71), BigDecimal.valueOf(-74.00)),
                new HistoricalTransaction("tx-h2", BigDecimal.valueOf(550.0), now.minusDays(2), BigDecimal.valueOf(40.71), BigDecimal.valueOf(-74.00))
        );

        Optional<RuleHit> result = rule.evaluate(current, history);

        assertThat(result).isEmpty();
    }
}
