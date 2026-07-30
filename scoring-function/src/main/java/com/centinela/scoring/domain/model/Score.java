package com.centinela.scoring.domain.model;

import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Objects;

/**
 * Resultado del scoring con todo lo necesario para explicar la decision despues.
 *
 * <p>Semana 3 agrega dos datos que no existian en Semana 2:
 *
 * <ul>
 *   <li>{@code threshold}: el umbral <b>vigente en el instante de la decision</b>. El
 *       umbral es configurable en caliente, asi que guardarlo aparte del score convierte
 *       la explicacion en una afirmacion no verificable — "score 82 sobre umbral 60"
 *       solo es cierto si 60 era el umbral entonces, no el de ahora.</li>
 *   <li>{@code traceparent}: el contexto de traza heredado del evento, para que el
 *       recorrido de la transaccion no se corte al cruzar la cola de casos.</li>
 * </ul>
 */
public final class Score {
    private final String transactionId;
    private final String accountId;
    private final int totalScore;
    private final int threshold;
    private final List<RuleHit> triggeredRules;
    private final OffsetDateTime occurredAt;
    private final Instant scoredAt;
    private final String traceparent;

    public Score(String transactionId, String accountId, int totalScore, int threshold,
                 List<RuleHit> triggeredRules, OffsetDateTime occurredAt, Instant scoredAt,
                 String traceparent) {
        this.transactionId = Objects.requireNonNull(transactionId, "transactionId is required");
        this.accountId = Objects.requireNonNull(accountId, "accountId is required");
        if (totalScore < 0) throw new IllegalArgumentException("totalScore must be non-negative");
        if (threshold < 0) throw new IllegalArgumentException("threshold must be non-negative");
        this.totalScore = totalScore;
        this.threshold = threshold;
        this.triggeredRules = List.copyOf(Objects.requireNonNull(triggeredRules, "triggeredRules is required"));
        this.occurredAt = Objects.requireNonNull(occurredAt, "occurredAt is required");
        this.scoredAt = Objects.requireNonNull(scoredAt, "scoredAt is required");
        this.traceparent = Objects.requireNonNull(traceparent, "traceparent is required");
    }

    public Score(String transactionId, String accountId, int totalScore, int threshold,
                 List<RuleHit> triggeredRules, Instant scoredAt, String traceparent) {
        this(transactionId, accountId, totalScore, threshold, triggeredRules,
                OffsetDateTime.ofInstant(scoredAt, ZoneOffset.UTC), scoredAt, traceparent);
    }

    public String transactionId() { return transactionId; }
    public String accountId() { return accountId; }
    public int totalScore() { return totalScore; }

    /** Umbral vigente cuando se tomo la decision, no el configurado actualmente. */
    public int threshold() { return threshold; }

    public List<RuleHit> triggeredRules() { return triggeredRules; }
    public OffsetDateTime occurredAt() { return occurredAt; }
    public Instant scoredAt() { return scoredAt; }

    /** Contexto de traza W3C heredado del evento que origino este scoring. */
    public String traceparent() { return traceparent; }

    /** {@code true} si la transaccion debe abrir caso: alcanzo el umbral con reglas activadas. */
    public boolean isFlagged() {
        return !triggeredRules.isEmpty() && totalScore >= threshold;
    }
}
