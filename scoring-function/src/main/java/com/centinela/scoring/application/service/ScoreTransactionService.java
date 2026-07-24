package com.centinela.scoring.application.service;

import com.centinela.scoring.application.config.ScoringThresholdProvider;
import com.centinela.scoring.application.port.out.FlaggedCasePublisherPort;
import com.centinela.scoring.application.port.out.ScorePersistencePort;
import com.centinela.scoring.domain.model.HistoricalTransaction;
import com.centinela.scoring.domain.model.RuleHit;
import com.centinela.scoring.domain.model.Score;
import com.centinela.scoring.domain.model.TransactionEvent;
import com.centinela.scoring.domain.rule.AtypicalAmountRule;
import com.centinela.scoring.domain.rule.GeoImpossibleRule;
import com.centinela.scoring.domain.rule.RiskyMerchantRule;
import com.centinela.scoring.domain.rule.ScoringRule;
import com.centinela.scoring.domain.rule.VelocityRule;

import java.time.Clock;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;
import java.util.Optional;

/**
 * Servicio de aplicacion que orquesta el scoring de transacciones.
 *
 * <p>Evalua las reglas puras de dominio (Velocidad, Monto Atipico,
 * Geo-Imposible, Comercio de Riesgo), suma sus puntos para calcular el score total,
 * registra los valores observados de activacion, y comprueba el umbral dinamico.
 */
public final class ScoreTransactionService {

    private final List<ScoringRule> rules;
    private final ScoringThresholdProvider thresholdProvider;
    private final ScorePersistencePort scorePersistencePort;
    private final FlaggedCasePublisherPort flaggedCasePublisherPort;
    private final Clock clock;
    private final ScoreCalculationPort customCalculationPort;

    public ScoreTransactionService(ScoringThresholdProvider thresholdProvider) {
        this(defaultRules(thresholdProvider), thresholdProvider, null, null, Clock.systemUTC());
    }

    public ScoreTransactionService(List<ScoringRule> rules, ScoringThresholdProvider thresholdProvider, Clock clock) {
        this(rules, thresholdProvider, null, null, clock);
    }

    public ScoreTransactionService(
            List<ScoringRule> rules,
            ScoringThresholdProvider thresholdProvider,
            ScorePersistencePort scorePersistencePort,
            FlaggedCasePublisherPort flaggedCasePublisherPort,
            Clock clock) {
        this.rules = rules != null ? List.copyOf(rules) : List.of();
        this.thresholdProvider = thresholdProvider != null ? thresholdProvider : new ScoringThresholdProvider();
        this.scorePersistencePort = scorePersistencePort;
        this.flaggedCasePublisherPort = flaggedCasePublisherPort;
        this.clock = clock != null ? clock : Clock.systemUTC();
        this.customCalculationPort = null;
    }

    public ScoreTransactionService(
            ScoreCalculationPort scoreCalculationPort,
            ScorePersistencePort scorePersistencePort,
            FlaggedCasePublisherPort flaggedCasePublisherPort,
            int scoringThreshold,
            Clock clock) {
        this.rules = List.of();
        this.thresholdProvider = new ScoringThresholdProvider(() -> scoringThreshold, null, null);
        this.scorePersistencePort = scorePersistencePort;
        this.flaggedCasePublisherPort = flaggedCasePublisherPort;
        this.clock = clock != null ? clock : Clock.systemUTC();
        this.customCalculationPort = scoreCalculationPort;
    }

    public static List<ScoringRule> defaultRules(ScoringThresholdProvider thresholdProvider) {
        ScoringThresholdProvider provider = thresholdProvider != null ? thresholdProvider : new ScoringThresholdProvider();
        return List.of(
                new VelocityRule(),
                new AtypicalAmountRule(),
                new GeoImpossibleRule(),
                new RiskyMerchantRule(provider.getRiskyMerchants(), provider.getRiskyCategories())
        );
    }

    /**
     * Evalua la transaccion y su historial devolviendo el {@link Score} calculado.
     */
    public Score scoreTransaction(TransactionEvent transaction, List<HistoricalTransaction> history) {
        return executeScoring(transaction, history);
    }

    /**
     * Ejecuta el scoring completo para una transaccion y su historial.
     */
    public Score executeScoring(TransactionEvent transaction, List<HistoricalTransaction> history) {
        Objects.requireNonNull(transaction, "transaction is required");
        List<HistoricalTransaction> safeHistory = history != null ? history : List.of();

        Instant scoredAt = clock.instant();
        List<RuleHit> triggeredRules = new ArrayList<>();
        int totalScore = 0;

        for (ScoringRule rule : rules) {
            Optional<RuleHit> hitOpt = rule.evaluate(transaction, safeHistory);
            if (hitOpt.isPresent()) {
                RuleHit hit = hitOpt.get();
                triggeredRules.add(hit);
                totalScore += hit.points();
            }
        }

        Score score = new Score(
                transaction.transactionId(),
                transaction.accountId(),
                totalScore,
                triggeredRules,
                scoredAt
        );

        if (scorePersistencePort != null) {
            scorePersistencePort.persistScore(score);
        }

        if (flaggedCasePublisherPort != null && score.totalScore() >= thresholdProvider.getThreshold()) {
            flaggedCasePublisherPort.publishFlaggedCase(score);
        }

        return score;
    }

    public Score executeScoring(String transactionId, String accountId) {
        if (customCalculationPort != null) {
            Score score = customCalculationPort.calculateScore(transactionId, accountId, clock.instant());
            if (scorePersistencePort != null) {
                scorePersistencePort.persistScore(score);
            }
            if (flaggedCasePublisherPort != null && score.totalScore() >= thresholdProvider.getThreshold()) {
                flaggedCasePublisherPort.publishFlaggedCase(score);
            }
            return score;
        }

        throw new UnsupportedOperationException("Requires TransactionEvent and history for domain rule evaluation");
    }

    public ScoringThresholdProvider getThresholdProvider() {
        return thresholdProvider;
    }

    @FunctionalInterface
    public interface ScoreCalculationPort {
        Score calculateScore(String transactionId, String accountId, Instant scoredAt);
    }
}
