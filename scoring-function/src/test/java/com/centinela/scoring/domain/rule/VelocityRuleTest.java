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
 * TEST-S2-010: Regla de velocidad se activa.
 */
class VelocityRuleTest {

    @Test
    @DisplayName("TEST-S2-010: Debe activarse cuando el conteo en la ventana supera el maximo permitido")
    void debeActivarseCuandoSuperaMaximoPermitido() {
        VelocityRule rule = new VelocityRule("velocity", "Velocidad", 30, 60, 3);

        OffsetDateTime now = OffsetDateTime.parse("2024-01-15T12:00:00Z");

        TransactionEvent current = new TransactionEvent(
                "tx-current",
                "acc-001",
                BigDecimal.valueOf(100.0),
                "USD",
                now,
                new TransactionEvent.EventLocation("US", "NYC", BigDecimal.valueOf(40.71), BigDecimal.valueOf(-74.00)),
                new TransactionEvent.EventMerchant("Store", "retail")
        );

        List<HistoricalTransaction> history = List.of(
                new HistoricalTransaction("tx-h1", BigDecimal.valueOf(50.0), now.minusMinutes(10), BigDecimal.valueOf(40.71), BigDecimal.valueOf(-74.00)),
                new HistoricalTransaction("tx-h2", BigDecimal.valueOf(50.0), now.minusMinutes(20), BigDecimal.valueOf(40.71), BigDecimal.valueOf(-74.00)),
                new HistoricalTransaction("tx-h3", BigDecimal.valueOf(50.0), now.minusMinutes(30), BigDecimal.valueOf(40.71), BigDecimal.valueOf(-74.00))
        );

        Optional<RuleHit> result = rule.evaluate(current, history);

        assertThat(result).isPresent();
        RuleHit hit = result.get();

        assertThat(hit.ruleId()).isEqualTo("velocity");
        assertThat(hit.ruleName()).isEqualTo("Velocidad");
        assertThat(hit.points()).isEqualTo(30);

        assertThat(hit.observedValues())
                .containsEntry("countInWindow", 4)
                .containsEntry("windowMinutes", 60)
                .containsEntry("maxAllowed", 3);
    }

    @Test
    @DisplayName("No debe activarse cuando las transacciones en la ventana son menores o iguales al limite")
    void noDebeActivarseCuandoEstaDentroDelLimite() {
        VelocityRule rule = new VelocityRule("velocity", "Velocidad", 30, 60, 3);

        OffsetDateTime now = OffsetDateTime.parse("2024-01-15T12:00:00Z");

        TransactionEvent current = new TransactionEvent(
                "tx-current",
                "acc-001",
                BigDecimal.valueOf(100.0),
                "USD",
                now,
                new TransactionEvent.EventLocation("US", "NYC", BigDecimal.valueOf(40.71), BigDecimal.valueOf(-74.00)),
                new TransactionEvent.EventMerchant("Store", "retail")
        );

        List<HistoricalTransaction> history = List.of(
                new HistoricalTransaction("tx-h1", BigDecimal.valueOf(50.0), now.minusMinutes(10), BigDecimal.valueOf(40.71), BigDecimal.valueOf(-74.00))
        );

        Optional<RuleHit> result = rule.evaluate(current, history);

        assertThat(result).isEmpty();
    }
}
