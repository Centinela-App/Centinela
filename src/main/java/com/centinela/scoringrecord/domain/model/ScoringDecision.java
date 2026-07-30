package com.centinela.scoringrecord.domain.model;

import java.util.Comparator;
import java.util.List;
import java.util.Objects;

/**
 * Registro completo de la decision del motor sobre una transaccion.
 *
 * <p>Es la unica entrada del explicador. Todo lo que aparezca en el texto generado tiene
 * que poder rastrearse hasta un campo de este objeto; lo que no este aqui, no se dice.
 */
public record ScoringDecision(
        String transactionId,
        String accountId,
        int totalScore,
        int threshold,
        String traceparent,
        List<RuleActivation> triggeredRules) {

    public ScoringDecision {
        transactionId = Objects.requireNonNull(transactionId, "transactionId is required");
        triggeredRules = List.copyOf(Objects.requireNonNull(triggeredRules, "triggeredRules is required"));
    }

    /**
     * Reglas ordenadas por contribucion descendente, con el identificador como desempate.
     *
     * <p>El orden es parte del contrato de determinismo: la misma decision debe producir
     * el mismo texto, y Cosmos no garantiza el orden de un arreglo entre lecturas. Ademas
     * es el orden util para el analista — primero lo que mas peso tuvo.
     */
    public List<RuleActivation> rulesByContribution() {
        return triggeredRules.stream()
                .sorted(Comparator.comparingInt(RuleActivation::points).reversed()
                        .thenComparing(RuleActivation::ruleId))
                .toList();
    }

    public boolean exceededThreshold() {
        return !triggeredRules.isEmpty() && totalScore >= threshold;
    }
}
