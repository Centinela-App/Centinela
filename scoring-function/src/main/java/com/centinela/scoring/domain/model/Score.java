package com.centinela.scoring.domain.model;

import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Objects;

/** Resultado del scoring con las marcas temporales necesarias para {@code flagged-case-v1}. */
public final class Score {
    private final String transactionId;
    private final String accountId;
    private final int totalScore;
    private final List<RuleHit> triggeredRules;
    private final OffsetDateTime occurredAt;
    private final Instant scoredAt;

    public Score(String transactionId, String accountId, int totalScore,
                 List<RuleHit> triggeredRules, OffsetDateTime occurredAt, Instant scoredAt) {
        this.transactionId = Objects.requireNonNull(transactionId, "transactionId is required");
        this.accountId = Objects.requireNonNull(accountId, "accountId is required");
        if (totalScore < 0) throw new IllegalArgumentException("totalScore must be non-negative");
        this.totalScore = totalScore;
        this.triggeredRules = List.copyOf(Objects.requireNonNull(triggeredRules, "triggeredRules is required"));
        this.occurredAt = Objects.requireNonNull(occurredAt, "occurredAt is required");
        this.scoredAt = Objects.requireNonNull(scoredAt, "scoredAt is required");
    }

    /** Constructor conservado para pruebas unitarias existentes. */
    public Score(String transactionId, String accountId, int totalScore,
                 List<RuleHit> triggeredRules, Instant scoredAt) {
        this(transactionId, accountId, totalScore, triggeredRules,
                OffsetDateTime.ofInstant(scoredAt, ZoneOffset.UTC), scoredAt);
    }

    public String transactionId() { return transactionId; }
    public String accountId() { return accountId; }
    public int totalScore() { return totalScore; }
    public List<RuleHit> triggeredRules() { return triggeredRules; }
    public OffsetDateTime occurredAt() { return occurredAt; }
    public Instant scoredAt() { return scoredAt; }
}
