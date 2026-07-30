package com.centinela.caseexplanation.application.service;

import com.centinela.caseexplanation.application.port.out.PendingExplanationPort;
import com.centinela.scoringrecord.application.port.out.ScoringDecisionReaderPort;
import com.centinela.scoringrecord.domain.model.RuleActivation;
import com.centinela.scoringrecord.domain.model.ScoringDecision;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * El explicador procesa un backlog: su comportamiento ante un caso defectuoso determina si
 * el resto del backlog avanza o se atasca. Estas pruebas fijan ese comportamiento.
 */
class GenerateCaseExplanationServiceTest {

    private static final Instant NOW = Instant.parse("2026-07-29T12:00:00Z");
    private static final String TRACEPARENT = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01";

    private PendingExplanationPort pending;
    private ScoringDecisionReaderPort reader;
    private GenerateCaseExplanationService service;

    @BeforeEach
    void setUp() {
        pending = mock(PendingExplanationPort.class);
        reader = mock(ScoringDecisionReaderPort.class);
        service = new GenerateCaseExplanationService(
                pending, reader, Clock.fixed(NOW, ZoneOffset.UTC), 25, 5);
    }

    @Test
    void generates_and_attaches_the_explanation_of_a_pending_case() {
        when(pending.findPending(25)).thenReturn(List.of(pendingCase(1L, "tx-001")));
        when(reader.findByTransactionId("tx-001")).thenReturn(Optional.of(decision("tx-001")));

        assertThat(service.generatePending()).isEqualTo(1);

        verify(pending).attachExplanation(eq(1L), anyString(), eq(NOW));
    }

    @Test
    void processes_the_whole_backlog_when_the_explainer_comes_back_up() {
        // Escenario del criterio de aceptacion: con el explicador detenido los casos se
        // acumularon en PENDING; al restablecerse deben generarse todos.
        when(pending.findPending(25)).thenReturn(List.of(
                pendingCase(1L, "tx-001"), pendingCase(2L, "tx-002"), pendingCase(3L, "tx-003")));
        when(reader.findByTransactionId(anyString()))
                .thenAnswer(invocation -> Optional.of(decision(invocation.getArgument(0))));

        assertThat(service.generatePending()).isEqualTo(3);

        verify(pending).attachExplanation(eq(1L), anyString(), any());
        verify(pending).attachExplanation(eq(2L), anyString(), any());
        verify(pending).attachExplanation(eq(3L), anyString(), any());
    }

    @Test
    void one_unexplainable_case_does_not_block_the_rest_of_the_batch() {
        when(pending.findPending(25)).thenReturn(List.of(
                pendingCase(1L, "tx-broken"), pendingCase(2L, "tx-ok")));
        when(reader.findByTransactionId("tx-broken")).thenReturn(Optional.empty());
        when(reader.findByTransactionId("tx-ok")).thenReturn(Optional.of(decision("tx-ok")));

        assertThat(service.generatePending()).isEqualTo(1);

        verify(pending).recordFailure(eq(1L), eq(5), anyString());
        verify(pending).attachExplanation(eq(2L), anyString(), any());
    }

    @Test
    void records_a_failure_when_the_engine_left_no_rules_to_explain() {
        when(pending.findPending(25)).thenReturn(List.of(pendingCase(1L, "tx-001")));
        when(reader.findByTransactionId("tx-001")).thenReturn(Optional.of(
                new ScoringDecision("tx-001", "acc-001", 82, 60, TRACEPARENT, List.of())));

        assertThat(service.generatePending()).isZero();

        verify(pending).recordFailure(eq(1L), eq(5), anyString());
        verify(pending, never()).attachExplanation(any(), anyString(), any());
    }

    @Test
    void does_nothing_when_there_is_no_pending_work() {
        when(pending.findPending(anyInt())).thenReturn(List.of());

        assertThat(service.generatePending()).isZero();

        verify(pending, never()).attachExplanation(any(), anyString(), any());
        verify(pending, never()).recordFailure(any(), anyInt(), anyString());
    }

    private static PendingExplanationPort.PendingCase pendingCase(Long caseId, String transactionId) {
        return new PendingExplanationPort.PendingCase(caseId, transactionId, TRACEPARENT, 0);
    }

    private static ScoringDecision decision(String transactionId) {
        return new ScoringDecision(transactionId, "acc-001", 82, 60, TRACEPARENT,
                List.of(new RuleActivation("velocity", "Velocidad", 82, Map.of(
                        "countInWindow", 4,
                        "windowMinutes", 60,
                        "maxAllowed", 3,
                        "elapsedMinutesInWindow", 4L))));
    }
}
