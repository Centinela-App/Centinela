package com.centinela.caseexplanation.domain.explanation;

import com.centinela.scoringrecord.domain.model.RuleActivation;
import com.centinela.scoringrecord.domain.model.ScoringDecision;
import org.junit.jupiter.api.Test;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * El criterio de aceptacion no es "la explicacion se lee bien", sino que <b>se corresponde
 * estrictamente con las reglas que se activaron y con los valores que las activaron</b>.
 * Estas pruebas atacan las dos formas de incumplirlo: afirmar de mas (inventar un dato que
 * el motor no registro) y afirmar de menos (omitir una regla que si contribuyo al score).
 */
class ExplanationTemplateTest {

    @Test
    void renders_the_expected_shape_for_a_full_decision() {
        ScoringDecision decision = new ScoringDecision(
                "tx-001", "acc-001", 82, 60, traceparent(),
                List.of(velocity(35), atypicalAmount(30), geoImpossible(17)));

        String explanation = ExplanationTemplate.render(decision);

        assertThat(explanation).startsWith("Transacción marcada con score 82 (umbral: 60).");
        assertThat(explanation).contains(
                "Se detectaron 3 transacciones de esta cuenta en los últimos 4 minutos, "
                        + "cuando el promedio histórico de la cuenta es de 1 cada 6 horas");
        assertThat(explanation).contains(
                "El monto de COP 4.200.000 supera en 84× el promedio histórico de la cuenta (COP 50.000)");
        assertThat(explanation).contains(
                "La transacción anterior de esta cuenta se originó en Medellín hace 11 minutos; "
                        + "esta se origina en Madrid, a 8.000 km");
        assertThat(explanation).contains("(+35 puntos).", "(+30 puntos).", "(+17 puntos).");
    }

    @Test
    void orders_rules_by_contribution_so_the_analyst_reads_the_heaviest_first() {
        ScoringDecision decision = new ScoringDecision(
                "tx-001", "acc-001", 82, 60, traceparent(),
                List.of(geoImpossible(17), velocity(35), atypicalAmount(30)));

        String explanation = ExplanationTemplate.render(decision);

        assertThat(explanation.indexOf("Se detectaron"))
                .isLessThan(explanation.indexOf("El monto de"))
                .isLessThan(explanation.indexOf("La transacción anterior"));
    }

    @Test
    void is_deterministic_for_the_same_decision() {
        ScoringDecision decision = new ScoringDecision(
                "tx-001", "acc-001", 82, 60, traceparent(),
                List.of(velocity(35), atypicalAmount(30), geoImpossible(17)));

        assertThat(ExplanationTemplate.render(decision)).isEqualTo(ExplanationTemplate.render(decision));
    }

    @Test
    void never_mentions_a_rule_that_did_not_fire() {
        ScoringDecision decision = new ScoringDecision(
                "tx-001", "acc-001", 35, 30, traceparent(), List.of(velocity(35)));

        String explanation = ExplanationTemplate.render(decision);

        assertThat(explanation).doesNotContain("El monto de");
        assertThat(explanation).doesNotContain("La transacción anterior");
        assertThat(explanation).doesNotContain("comercio");
    }

    @Test
    void omits_the_baseline_clause_when_the_engine_did_not_measure_it() {
        Map<String, Object> observed = new LinkedHashMap<>();
        observed.put("countInWindow", 4);
        observed.put("windowMinutes", 60);
        observed.put("maxAllowed", 3);
        observed.put("elapsedMinutesInWindow", 4L);
        // Sin baselineAverageIntervalMinutes: el motor no lo pudo calcular.

        String explanation = ExplanationTemplate.render(new ScoringDecision(
                "tx-001", "acc-001", 30, 25, traceparent(),
                List.of(new RuleActivation("velocity", "Velocidad", 30, observed))));

        assertThat(explanation).contains("en los últimos 4 minutos");
        assertThat(explanation).doesNotContain("promedio");
    }

    @Test
    void falls_back_to_distance_when_the_city_was_never_recorded() {
        Map<String, Object> observed = new LinkedHashMap<>();
        observed.put("distanceKm", 8000.0);
        observed.put("timeMinutes", 11L);

        String explanation = ExplanationTemplate.render(new ScoringDecision(
                "tx-001", "acc-001", 40, 30, traceparent(),
                List.of(new RuleActivation("geo-impossible", "Geo-Imposible", 40, observed))));

        assertThat(explanation).contains("a 8.000 km");
        // Nada de "en Medellín": el dato no existe, la frase no lo afirma.
        assertThat(explanation).doesNotContain(" en ");
    }

    @Test
    void reports_an_unknown_rule_with_its_raw_values_instead_of_hiding_it() {
        // Omitir la regla dejaria un score que no cuadra con las frases mostradas y el
        // analista no tendria forma de advertirlo.
        String explanation = ExplanationTemplate.render(new ScoringDecision(
                "tx-001", "acc-001", 12, 10, traceparent(),
                List.of(new RuleActivation("brand-new-rule", "Regla nueva", 12,
                        Map.of("suspicionLevel", 3)))));

        assertThat(explanation).contains("Se activó la regla «Regla nueva»");
        assertThat(explanation).contains("suspicionLevel=3");
        assertThat(explanation).contains("(+12 puntos).");
    }

    @Test
    void refuses_to_explain_a_case_the_engine_did_not_justify() {
        assertThatThrownBy(() -> ExplanationTemplate.render(
                new ScoringDecision("tx-001", "acc-001", 82, 60, traceparent(), List.of())))
                .isInstanceOf(InsufficientDecisionRecordException.class)
                .hasMessageContaining("no registro ninguna regla activada");
    }

    private static String traceparent() {
        return "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01";
    }

    private static RuleActivation velocity(int points) {
        Map<String, Object> observed = new LinkedHashMap<>();
        observed.put("countInWindow", 3);
        observed.put("windowMinutes", 60);
        observed.put("maxAllowed", 3);
        observed.put("elapsedMinutesInWindow", 4L);
        observed.put("baselineAverageIntervalMinutes", 360.0);
        observed.put("baselineSampleSize", 4);
        return new RuleActivation("velocity", "Velocidad", points, observed);
    }

    private static RuleActivation atypicalAmount(int points) {
        Map<String, Object> observed = new LinkedHashMap<>();
        observed.put("currentAmount", 4200000.0);
        observed.put("averageAmount", 50000.0);
        observed.put("multiplierThreshold", 3.0);
        observed.put("observedMultiplier", 84.0);
        observed.put("historySampleSize", 12);
        observed.put("currency", "COP");
        return new RuleActivation("atypical-amount", "Monto Atípico", points, observed);
    }

    private static RuleActivation geoImpossible(int points) {
        Map<String, Object> observed = new LinkedHashMap<>();
        observed.put("distanceKm", 8000.0);
        observed.put("timeMinutes", 11L);
        observed.put("calculatedSpeedKmh", 43636.36);
        observed.put("previousCity", "Medellín");
        observed.put("previousCountryCode", "CO");
        observed.put("currentCity", "Madrid");
        observed.put("currentCountryCode", "ES");
        return new RuleActivation("geo-impossible", "Geo-Imposible", points, observed);
    }
}
