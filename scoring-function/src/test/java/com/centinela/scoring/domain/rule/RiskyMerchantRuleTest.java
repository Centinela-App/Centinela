package com.centinela.scoring.domain.rule;

import com.centinela.scoring.domain.model.RuleHit;
import com.centinela.scoring.domain.model.TransactionEvent;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * TEST-S2-013: Regla de comercio de riesgo se activa.
 */
class RiskyMerchantRuleTest {

    @Test
    @DisplayName("TEST-S2-013: Debe activarse cuando el comercio coincide con la lista de riesgo")
    void debeActivarseCuandoComercioEsDeRiesgo() {
        Set<String> riskyMerchants = Set.of("Casino Royal", "Crypto Exchange");
        Set<String> riskyCategories = Set.of("gambling", "pawn_shop");

        RiskyMerchantRule rule = new RiskyMerchantRule("risky-merchant", "Comercio de Riesgo", 35, riskyMerchants, riskyCategories);

        TransactionEvent current = new TransactionEvent(
                "tx-001",
                "acc-001",
                BigDecimal.valueOf(1000.0),
                "USD",
                OffsetDateTime.parse("2024-01-15T12:00:00Z"),
                new TransactionEvent.EventLocation("US", "Vegas", BigDecimal.valueOf(36.1699), BigDecimal.valueOf(-115.1398)),
                new TransactionEvent.EventMerchant("Casino Royal", "entertainment")
        );

        Optional<RuleHit> result = rule.evaluate(current, List.of());

        assertThat(result).isPresent();
        RuleHit hit = result.get();

        assertThat(hit.ruleId()).isEqualTo("risky-merchant");
        assertThat(hit.points()).isEqualTo(35);

        assertThat(hit.observedValues())
                .containsEntry("merchantName", "Casino Royal")
                .containsEntry("matchedRiskFactor", "MERCHANT_NAME");
    }

    @Test
    @DisplayName("TEST-S2-013: Debe activarse cuando la categoria del comercio es de riesgo")
    void debeActivarseCuandoCategoriaEsDeRiesgo() {
        Set<String> riskyMerchants = Set.of("Casino Royal");
        Set<String> riskyCategories = Set.of("gambling");

        RiskyMerchantRule rule = new RiskyMerchantRule("risky-merchant", "Comercio de Riesgo", 35, riskyMerchants, riskyCategories);

        TransactionEvent current = new TransactionEvent(
                "tx-002",
                "acc-001",
                BigDecimal.valueOf(500.0),
                "USD",
                OffsetDateTime.parse("2024-01-15T12:00:00Z"),
                new TransactionEvent.EventLocation("US", "Vegas", BigDecimal.valueOf(36.1699), BigDecimal.valueOf(-115.1398)),
                new TransactionEvent.EventMerchant("Vegas Bet", "gambling")
        );

        Optional<RuleHit> result = rule.evaluate(current, List.of());

        assertThat(result).isPresent();
        RuleHit hit = result.get();

        assertThat(hit.observedValues())
                .containsEntry("merchantCategory", "gambling")
                .containsEntry("matchedRiskFactor", "MERCHANT_CATEGORY");
    }

    @Test
    @DisplayName("No debe activarse cuando el comercio y categoria son seguros")
    void noDebeActivarseCuandoComercioEsSeguro() {
        Set<String> riskyMerchants = Set.of("Casino Royal");
        Set<String> riskyCategories = Set.of("gambling");

        RiskyMerchantRule rule = new RiskyMerchantRule("risky-merchant", "Comercio de Riesgo", 35, riskyMerchants, riskyCategories);

        TransactionEvent current = new TransactionEvent(
                "tx-003",
                "acc-001",
                BigDecimal.valueOf(50.0),
                "USD",
                OffsetDateTime.parse("2024-01-15T12:00:00Z"),
                new TransactionEvent.EventLocation("US", "NYC", BigDecimal.valueOf(40.71), BigDecimal.valueOf(-74.00)),
                new TransactionEvent.EventMerchant("Supermarket", "groceries")
        );

        Optional<RuleHit> result = rule.evaluate(current, List.of());

        assertThat(result).isEmpty();
    }
}
