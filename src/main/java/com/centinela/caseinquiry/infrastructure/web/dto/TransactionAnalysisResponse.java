package com.centinela.caseinquiry.infrastructure.web.dto;

import com.centinela.scoringrecord.domain.model.RuleActivation;
import com.centinela.scoringrecord.domain.model.ScoringDecision;

import java.util.List;
import java.util.Map;

/**
 * Resultado del analisis de una transaccion.
 *
 * <p>Expone {@code flagged} de forma explicita en vez de dejar que el cliente compare
 * score contra umbral. Es la misma comparacion que hizo el motor, con el umbral que regia
 * entonces; recalcularla del lado del cliente daria un resultado distinto en cuanto el
 * umbral cambiara.
 */
public record TransactionAnalysisResponse(
        String transactionId,
        String accountId,
        int score,
        int threshold,
        boolean flagged,
        String traceparent,
        List<TriggeredRuleResponse> triggeredRules) {

    public static TransactionAnalysisResponse from(ScoringDecision decision) {
        return new TransactionAnalysisResponse(
                decision.transactionId(),
                decision.accountId(),
                decision.totalScore(),
                decision.threshold(),
                decision.exceededThreshold(),
                decision.traceparent(),
                decision.rulesByContribution().stream()
                        .map(TriggeredRuleResponse::from)
                        .toList());
    }

    /** Regla activada con los valores exactos que la activaron. */
    public record TriggeredRuleResponse(
            String ruleId,
            String ruleName,
            int points,
            Map<String, Object> observedValues) {

        static TriggeredRuleResponse from(RuleActivation activation) {
            return new TriggeredRuleResponse(
                    activation.ruleId(),
                    activation.ruleName(),
                    activation.points(),
                    activation.observedValues());
        }
    }
}
