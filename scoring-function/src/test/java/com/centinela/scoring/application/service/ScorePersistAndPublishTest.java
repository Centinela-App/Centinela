package com.centinela.scoring.application.service;

import com.centinela.scoring.application.config.ScoringThresholdProvider;
import com.centinela.scoring.application.port.out.FlaggedCasePublisherPort;
import com.centinela.scoring.application.port.out.ScorePersistencePort;
import com.centinela.scoring.domain.model.RuleHit;
import com.centinela.scoring.domain.model.Score;
import com.centinela.scoring.domain.model.TransactionEvent;
import com.centinela.scoring.domain.rule.ScoringRule;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.Clock;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

class ScorePersistAndPublishTest {
    private ScorePersistencePort persistence;
    private FlaggedCasePublisherPort publisher;
    private TransactionEvent transaction;
    private Clock clock;

    @BeforeEach
    void setUp() {
        persistence = mock(ScorePersistencePort.class);
        publisher = mock(FlaggedCasePublisherPort.class);
        clock = Clock.fixed(Instant.parse("2026-07-25T15:00:00Z"), ZoneOffset.UTC);
        transaction = new TransactionEvent(
                "tx-001", "acc-001", new BigDecimal("5000"), "USD",
                OffsetDateTime.parse("2026-07-25T14:59:00Z"),
                new TransactionEvent.EventLocation("CO", "Bogota", new BigDecimal("4.71"), new BigDecimal("-74.07")),
                new TransactionEvent.EventMerchant("Merchant", "retail"));
    }

    @Test
    void persists_score_and_publishes_when_threshold_is_reached() {
        ScoringRule rule = rule("ATYPICAL_AMOUNT", Optional.of(new RuleHit(
                "ATYPICAL_AMOUNT", "Monto atipico", 60, Map.of("amount", 5000))));
        ScoreTransactionService service = service(rule, 50);

        Score score = service.executeScoring(transaction, List.of());

        assertThat(score.totalScore()).isEqualTo(60);
        verify(persistence).persistScore(transaction, score);
        verify(publisher).publishFlaggedCase(score);
    }

    @Test
    void persists_but_does_not_publish_below_threshold() {
        ScoringRule rule = rule("VELOCITY", Optional.of(new RuleHit(
                "VELOCITY", "Velocidad", 20, Map.of("count", 2))));
        ScoreTransactionService service = service(rule, 50);

        Score score = service.executeScoring(transaction, List.of());

        verify(persistence).persistScore(transaction, score);
        verify(publisher, never()).publishFlaggedCase(any());
    }

    @Test
    void does_not_publish_empty_rule_set_even_with_zero_threshold() {
        ScoringRule rule = rule("NO_HIT", Optional.empty());
        ScoreTransactionService service = service(rule, 0);

        Score score = service.executeScoring(transaction, List.of());

        verify(persistence).persistScore(transaction, score);
        verify(publisher, never()).publishFlaggedCase(any());
    }

    private ScoringRule rule(String ruleId, Optional<RuleHit> result) {
        return new ScoringRule() {
            @Override
            public String ruleId() {
                return ruleId;
            }

            @Override
            public Optional<RuleHit> evaluate(
                    TransactionEvent transaction,
                    List<com.centinela.scoring.domain.model.HistoricalTransaction> history) {
                return result;
            }
        };
    }

    private ScoreTransactionService service(ScoringRule rule, int threshold) {
        return new ScoreTransactionService(
                List.of(rule),
                new ScoringThresholdProvider(() -> threshold, null, null),
                persistence,
                publisher,
                clock);
    }
}
