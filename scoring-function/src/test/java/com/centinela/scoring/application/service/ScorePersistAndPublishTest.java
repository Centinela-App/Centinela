package com.centinela.scoring.application.service;

import com.centinela.scoring.application.port.out.FlaggedCasePublisherPort;
import com.centinela.scoring.application.port.out.ScorePersistencePort;
import com.centinela.scoring.domain.model.RuleHit;
import com.centinela.scoring.domain.model.Score;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

/**
 * Tests para ScoreTransactionService que verifican:
 * - TEST-S2-016: Score + detalle persistidos en Cosmos
 * - TEST-S2-017: Caso encolado solo si supera umbral
 */
@ExtendWith(MockitoExtension.class)
class ScorePersistAndPublishTest {

    @Mock
    private ScoreTransactionService.ScoreCalculationPort scoreCalculationPort;

    @Mock
    private ScorePersistencePort scorePersistencePort;

    @Mock
    private FlaggedCasePublisherPort flaggedCasePublisherPort;

    private ScoreTransactionService service;
    private Clock fixedClock;

    @BeforeEach
    void setUp() {
        fixedClock = Clock.fixed(
                Instant.parse("2024-01-15T10:30:00Z"),
                ZoneOffset.UTC
        );
        service = new ScoreTransactionService(
                scoreCalculationPort,
                scorePersistencePort,
                flaggedCasePublisherPort,
                50, // umbral
                fixedClock
        );
    }

    @Nested
    @DisplayName("TEST-S2-016: Score + detalle persistidos en Cosmos")
    class PersistenciaScore {

        @Test
        @DisplayName("Debe persistir el score con su detalle al ejecutar scoring")
        void debePersistirScoreConDetalle() {
            // Given
            String transactionId = "txn-001";
            String accountId = "acc-001";

            List<RuleHit> triggeredRules = List.of(
                    new RuleHit("velocity", "Velocidad", 20,
                            Map.of("countInWindow", 5, "windowMinutes", 60)),
                    new RuleHit("atypical-amount", "Monto Atípico", 15,
                            Map.of("currentAmount", 5000.00, "averageAmount", 500.00))
            );

            Score expectedScore = new Score(
                    transactionId,
                    accountId,
                    35,
                    triggeredRules,
                    fixedClock.instant()
            );

            when(scoreCalculationPort.calculateScore(eq(transactionId), eq(accountId), any()))
                    .thenReturn(expectedScore);

            // When
            Score result = service.executeScoring(transactionId, accountId);

            // Then
            assertThat(result.totalScore()).isEqualTo(35);
            assertThat(result.triggeredRules()).hasSize(2);

            // Verificar que se persistio el score
            ArgumentCaptor<Score> scoreCaptor = ArgumentCaptor.forClass(Score.class);
            verify(scorePersistencePort).persistScore(scoreCaptor.capture());

            Score persistedScore = scoreCaptor.getValue();
            assertThat(persistedScore.transactionId()).isEqualTo(transactionId);
            assertThat(persistedScore.accountId()).isEqualTo(accountId);
            assertThat(persistedScore.totalScore()).isEqualTo(35);
            assertThat(persistedScore.triggeredRules()).hasSize(2);
        }

        @Test
        @DisplayName("Debe incluir los valores observados en el detalle de activacion")
        void debeIncluirValoresObservados() {
            // Given
            String transactionId = "txn-002";
            String accountId = "acc-002";

            Map<String, Object> observedValues = Map.of(
                    "countInWindow", 8,
                    "windowMinutes", 60,
                    "maxAllowed", 5
            );

            List<RuleHit> triggeredRules = List.of(
                    new RuleHit("velocity", "Velocidad", 30, observedValues)
            );

            Score expectedScore = new Score(
                    transactionId,
                    accountId,
                    30,
                    triggeredRules,
                    fixedClock.instant()
            );

            when(scoreCalculationPort.calculateScore(eq(transactionId), eq(accountId), any()))
                    .thenReturn(expectedScore);

            // When
            service.executeScoring(transactionId, accountId);

            // Then
            ArgumentCaptor<Score> scoreCaptor = ArgumentCaptor.forClass(Score.class);
            verify(scorePersistencePort).persistScore(scoreCaptor.capture());

            Score persistedScore = scoreCaptor.getValue();
            RuleHit ruleHit = persistedScore.triggeredRules().get(0);

            assertThat(ruleHit.observedValues())
                    .containsEntry("countInWindow", 8)
                    .containsEntry("windowMinutes", 60)
                    .containsEntry("maxAllowed", 5);
        }
    }

    @Nested
    @DisplayName("TEST-S2-017: Caso encolado solo si supera umbral")
    class PublicacionCaso {

        @Test
        @DisplayName("Debe encolar caso cuando score supera el umbral")
        void debeEncolarCasoCuandoSuperaUmbral() {
            // Given
            String transactionId = "txn-003";
            String accountId = "acc-003";

            List<RuleHit> triggeredRules = List.of(
                    new RuleHit("velocity", "Velocidad", 30,
                            Map.of("countInWindow", 10)),
                    new RuleHit("risky-merchant", "Comercio de Riesgo", 25,
                            Map.of("merchantCategory", "gambling"))
            );

            // Score = 55, supera el umbral de 50
            Score expectedScore = new Score(
                    transactionId,
                    accountId,
                    55,
                    triggeredRules,
                    fixedClock.instant()
            );

            when(scoreCalculationPort.calculateScore(eq(transactionId), eq(accountId), any()))
                    .thenReturn(expectedScore);

            // When
            Score result = service.executeScoring(transactionId, accountId);

            // Then
            assertThat(result.totalScore()).isEqualTo(55);

            verify(flaggedCasePublisherPort).publishFlaggedCase(expectedScore);
        }

        @Test
        @DisplayName("No debe encolar caso cuando score no supera el umbral")
        void noDebeEncolarCasoCuandoNoSuperaUmbral() {
            // Given
            String transactionId = "txn-004";
            String accountId = "acc-004";

            List<RuleHit> triggeredRules = List.of(
                    new RuleHit("geo", "Geo-Imposible", 20,
                            Map.of("distanceKm", 100, "timeMinutes", 5))
            );

            // Score = 20, NO supera el umbral de 50
            Score expectedScore = new Score(
                    transactionId,
                    accountId,
                    20,
                    triggeredRules,
                    fixedClock.instant()
            );

            when(scoreCalculationPort.calculateScore(eq(transactionId), eq(accountId), any()))
                    .thenReturn(expectedScore);

            // When
            Score result = service.executeScoring(transactionId, accountId);

            // Then
            assertThat(result.totalScore()).isEqualTo(20);

            verify(flaggedCasePublisherPort, never()).publishFlaggedCase(any());
        }

        @Test
        @DisplayName("Debe encolar caso cuando score es exactamente igual al umbral")
        void debeEncolarCasoCuandoScoreIgualUmbral() {
            // Given
            String transactionId = "txn-005";
            String accountId = "acc-005";

            List<RuleHit> triggeredRules = List.of(
                    new RuleHit("velocity", "Velocidad", 50,
                            Map.of("countInWindow", 15))
            );

            // Score = 50, exactamente el umbral
            Score expectedScore = new Score(
                    transactionId,
                    accountId,
                    50,
                    triggeredRules,
                    fixedClock.instant()
            );

            when(scoreCalculationPort.calculateScore(eq(transactionId), eq(accountId), any()))
                    .thenReturn(expectedScore);

            // When
            Score result = service.executeScoring(transactionId, accountId);

            // Then
            assertThat(result.totalScore()).isEqualTo(50);
            verify(flaggedCasePublisherPort).publishFlaggedCase(expectedScore);
        }

        @Test
        @DisplayName("No debe encolar caso cuando no hay reglas activadas")
        void noDebeEncolarCasoSinReglasActivadas() {
            // Given
            String transactionId = "txn-006";
            String accountId = "acc-006";

            // Score = 0, ninguna regla activada
            Score expectedScore = new Score(
                    transactionId,
                    accountId,
                    0,
                    List.of(),
                    fixedClock.instant()
            );

            when(scoreCalculationPort.calculateScore(eq(transactionId), eq(accountId), any()))
                    .thenReturn(expectedScore);

            // When
            Score result = service.executeScoring(transactionId, accountId);

            // Then
            assertThat(result.totalScore()).isEqualTo(0);
            verify(flaggedCasePublisherPort, never()).publishFlaggedCase(any());
        }
    }

    @Nested
    @DisplayName("Idempotencia")
    class Idempotencia {

        @Test
        @DisplayName("Debe persistir score aunque no se publique caso")
        void debePersistirAunqueNoPubliqueCaso() {
            // Given
            String transactionId = "txn-007";
            String accountId = "acc-007";

            Score expectedScore = new Score(
                    transactionId,
                    accountId,
                    10,
                    List.of(new RuleHit("velocity", "Velocidad", 10,
                            Map.of("countInWindow", 2))),
                    fixedClock.instant()
            );

            when(scoreCalculationPort.calculateScore(eq(transactionId), eq(accountId), any()))
                    .thenReturn(expectedScore);

            // When
            service.executeScoring(transactionId, accountId);

            // Then - siempre persiste, aunque no publique caso
            verify(scorePersistencePort).persistScore(expectedScore);
            verify(flaggedCasePublisherPort, never()).publishFlaggedCase(any());
        }
    }
}
