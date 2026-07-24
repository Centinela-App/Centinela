package com.centinela.scoring.application.service;

import com.centinela.scoring.application.port.out.FlaggedCasePublisherPort;
import com.centinela.scoring.application.port.out.ScorePersistencePort;
import com.centinela.scoring.domain.model.Score;

import java.time.Clock;
import java.time.Instant;
import java.util.Objects;

/**
 * Servicio de aplicacion que orquesta el scoring de una transaccion.
 *
 * <p>Coordina:
 * <ul>
 *   <li>Calculo del score (delegado a dominio)</li>
 *   <li>Persistencia del score en Cosmos</li>
 *   <li>Publicacion del caso si supera el umbral</li>
 * </ul>
 *
 * <p>Este servicio cierra los pasos 5-6 de la secuencia de scoring:
 * - Paso 5: Persistir score + detalle en Cosmos
 * - Paso 6: Publicar caso en cola si score >= umbral
 */
public final class ScoreTransactionService {

    private final ScoreCalculationPort scoreCalculationPort;
    private final ScorePersistencePort scorePersistencePort;
    private final FlaggedCasePublisherPort flaggedCasePublisherPort;
    private final int scoringThreshold;
    private final Clock scoringClock;

    public ScoreTransactionService(
            ScoreCalculationPort scoreCalculationPort,
            ScorePersistencePort scorePersistencePort,
            FlaggedCasePublisherPort flaggedCasePublisherPort,
            int scoringThreshold,
            Clock scoringClock) {
        this.scoreCalculationPort = Objects.requireNonNull(scoreCalculationPort, "scoreCalculationPort is required");
        this.scorePersistencePort = Objects.requireNonNull(scorePersistencePort, "scorePersistencePort is required");
        this.flaggedCasePublisherPort = Objects.requireNonNull(flaggedCasePublisherPort, "flaggedCasePublisherPort is required");
        this.scoringThreshold = scoringThreshold;
        this.scoringClock = Objects.requireNonNull(scoringClock, "scoringClock is required");
    }

    /**
     * Ejecuta el flujo completo de scoring para una transaccion.
     *
     * <p>Flujo:
     * 1. Calcular score (delegado a puertos de reglas)
     * 2. Persistir score + detalle en Cosmos
     * 3. Si score >= umbral, publicar caso en cola
     *
     * @param transactionId identificador de la transaccion
     * @param accountId identificador de la cuenta
     * @return el score calculado
     */
    public Score executeScoring(String transactionId, String accountId) {
        Objects.requireNonNull(transactionId, "transactionId is required");
        Objects.requireNonNull(accountId, "accountId is required");

        // Paso 4: Calcular score
        Score score = scoreCalculationPort.calculateScore(transactionId, accountId, scoringClock.instant());

        // Paso 5: Persistir score + detalle en Cosmos
        scorePersistencePort.persistScore(score);

        // Paso 6: Publicar caso si supera el umbral
        if (score.totalScore() >= scoringThreshold) {
            flaggedCasePublisherPort.publishFlaggedCase(score);
        }

        return score;
    }

    /**
     * Puerto de entrada para calcular el score.
     *
     * <p>Implementaciones concretas usaran las reglas de ISS-S2-008.
     */
    @FunctionalInterface
    public interface ScoreCalculationPort {

        /**
         * Calcula el score para una transaccion.
         *
         * @param transactionId identificador de la transaccion
         * @param accountId identificador de la cuenta
         * @param scoredAt instante del scoring
         * @return el score calculado con detalle de activacion
         */
        Score calculateScore(String transactionId, String accountId, Instant scoredAt);
    }
}
