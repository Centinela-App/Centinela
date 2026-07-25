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

    public Score executeScoring(TransactionEvent transaction, List<HistoricalTransaction> history) {
        Objects.requireNonNull(transaction, "transaction is required");
        List<HistoricalTransaction> safeHistory = history == null ? List.of() : List.copyOf(history);

        Instant scoredAt = clock.instant();
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
                triggeredRules,
                transaction.occurredAt(),
                scoredAt);

        if (scorePersistencePort != null) {
            scorePersistencePort.persistScore(transaction, score);
        }
        if (flaggedCasePublisherPort != null
                && !score.triggeredRules().isEmpty()
                && score.totalScore() >= thresholdProvider.getThreshold()) {
            flaggedCasePublisherPort.publishFlaggedCase(score);
        }
        return score;
    }
}
