package com.centinela.scoring.application.service;

import com.centinela.scoring.application.config.ScoringThresholdProvider;
import com.centinela.scoring.application.port.out.FlaggedCasePublisherPort;
import com.centinela.scoring.application.port.out.ScorePersistencePort;
import com.centinela.scoring.domain.model.HistoricalTransaction;
import com.centinela.scoring.domain.model.RuleHit;
import com.centinela.scoring.domain.model.Score;
import com.centinela.scoring.domain.model.TraceContext;
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

/** Orquesta reglas, persistencia idempotente y publicacion de casos. */
public final class ScoreTransactionService {
    private final List<ScoringRule> rules;
    private final ScoringThresholdProvider thresholdProvider;
    private final ScorePersistencePort scorePersistencePort;
    private final FlaggedCasePublisherPort flaggedCasePublisherPort;
    private final Clock clock;

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
        this.rules = List.copyOf(Objects.requireNonNull(rules, "rules is required"));
        this.thresholdProvider = Objects.requireNonNull(thresholdProvider, "thresholdProvider is required");
        this.scorePersistencePort = scorePersistencePort;
        this.flaggedCasePublisherPort = flaggedCasePublisherPort;
        this.clock = Objects.requireNonNull(clock, "clock is required");
    }

    public static List<ScoringRule> defaultRules(ScoringThresholdProvider thresholdProvider) {
        ScoringThresholdProvider provider = Objects.requireNonNull(thresholdProvider, "thresholdProvider is required");
        return List.of(
                new VelocityRule(),
                new AtypicalAmountRule(),
                new GeoImpossibleRule(),
                new RiskyMerchantRule(provider.getRiskyMerchants(), provider.getRiskyCategories()));
    }

    public Score scoreTransaction(TransactionEvent transaction, List<HistoricalTransaction> history) {
        return executeScoring(transaction, history);
    }

    /**
     * Puntua sin contexto de traza entrante: abre una traza nueva.
     *
     * <p>Solo deberia ocurrir en pruebas o si el evento llega sin {@code traceparent}. En
     * el pipeline real el contexto viene del evento y debe conservarse.
     */
    public Score executeScoring(TransactionEvent transaction, List<HistoricalTransaction> history) {
        return executeScoring(transaction, history, TraceContext.newRootTraceparent());
    }

    /**
     * Puntua la transaccion continuando la traza recibida.
     *
     * <p>El umbral se lee <b>una sola vez</b> y se guarda dentro del {@link Score}. Es
     * configurable en caliente: leerlo dos veces — una para decidir y otra para explicar —
     * abre la posibilidad de que un caso se abra con un umbral y se explique con otro.
     */
    public Score executeScoring(
            TransactionEvent transaction,
            List<HistoricalTransaction> history,
            String traceparent) {
        Objects.requireNonNull(transaction, "transaction is required");
        List<HistoricalTransaction> safeHistory = history == null ? List.of() : List.copyOf(history);

        Instant scoredAt = clock.instant();
        int threshold = thresholdProvider.getThreshold();

        List<RuleHit> triggeredRules = new ArrayList<>();
        int totalScore = 0;
        for (ScoringRule rule : rules) {
            Optional<RuleHit> hit = rule.evaluate(transaction, safeHistory);
            if (hit.isPresent()) {
                triggeredRules.add(hit.get());
                totalScore += hit.get().points();
            }
        }

        Score score = new Score(
                transaction.transactionId(),
                transaction.accountId(),
                totalScore,
                threshold,
                triggeredRules,
                transaction.occurredAt(),
                scoredAt,
                TraceContext.parseOrNewRoot(traceparent).toTraceparent());

        if (scorePersistencePort != null) {
            scorePersistencePort.persistScore(transaction, score);
        }
        if (flaggedCasePublisherPort != null && score.isFlagged()) {
            flaggedCasePublisherPort.publishFlaggedCase(score);
        }
        return score;
    }
}
