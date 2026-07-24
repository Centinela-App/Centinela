package com.centinela.scoring.domain.model;

import java.time.Instant;
import java.util.List;
import java.util.Objects;

/**
 * Resultado del scoring de una transaccion.
 *
 * <p>Contiene el score total, las reglas activadas con su detalle,
 * y marcas temporales del procesamiento.
 */
public final class Score {

    private final String transactionId;
    private final String accountId;
    private final int totalScore;
    private final List<RuleHit> triggeredRules;
    private final Instant scoredAt;

    public Score(
            String transactionId,
            String accountId,
            int totalScore,
            List<RuleHit> triggeredRules,
            Instant scoredAt) {
        this.transactionId = Objects.requireNonNull(transactionId, "transactionId is required");
        this.accountId = Objects.requireNonNull(accountId, "accountId is required");
        this.totalScore = totalScore;
        this.triggeredRules = List.copyOf(Objects.requireNonNull(triggeredRules, "triggeredRules is required"));
        this.scoredAt = Objects.requireNonNull(scoredAt, "scoredAt is required");
    }

    /**
     * Identificador de la transaccion evaluada.
     */
    public String transactionId() {
        return transactionId;
    }

    /**
     * Identificador de la cuenta dueña de la transaccion.
     */
    public String accountId() {
        return accountId;
    }

    /**
     * Puntuacion total acumulada (suma de puntos de reglas activadas).
     */
    public int totalScore() {
        return totalScore;
    }

    /**
     * Lista de reglas activadas con su detalle de activacion.
     */
    public List<RuleHit> triggeredRules() {
        return triggeredRules;
    }

    /**
     * Instante en que se calculo el score.
     */
    public Instant scoredAt() {
        return scoredAt;
    }
}
