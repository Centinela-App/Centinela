package com.centinela.shared.event;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Objects;

/**
 * Contrato {@code flagged-case-v1} compartido por el productor de scoring y el
 * consumidor de casos.
 */
public record FlaggedCaseMessage(
        String transactionId,
        String accountId,
        int score,
        List<TriggeredRuleSummary> triggeredRules,
        OffsetDateTime occurredAt,
        OffsetDateTime scoredAt) {

    public static final String SCHEMA_VERSION = "flagged-case-v1";

    public FlaggedCaseMessage {
        if (transactionId == null || transactionId.isBlank()) {
            throw new IllegalArgumentException("transactionId is required");
        }
        if (accountId == null || accountId.isBlank()) {
            throw new IllegalArgumentException("accountId is required");
        }
        if (score < 0) {
            throw new IllegalArgumentException("score must be non-negative");
        }
        triggeredRules = List.copyOf(Objects.requireNonNull(triggeredRules, "triggeredRules is required"));
        if (triggeredRules.isEmpty()) {
            throw new IllegalArgumentException("triggeredRules must not be empty");
        }
        Objects.requireNonNull(occurredAt, "occurredAt is required");
        Objects.requireNonNull(scoredAt, "scoredAt is required");
    }

    public record TriggeredRuleSummary(String ruleId, int points) {
        public TriggeredRuleSummary {
            if (ruleId == null || ruleId.isBlank()) {
                throw new IllegalArgumentException("ruleId is required");
            }
            if (points < 0) {
                throw new IllegalArgumentException("points must be non-negative");
            }
        }
    }
}
