package com.centinela.casemanagement.application.service;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneId;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.centinela.casemanagement.application.port.out.CaseRepositoryPort;
import com.centinela.casemanagement.domain.model.CaseAuditEntry;
import com.centinela.casemanagement.domain.model.Case_;
import com.centinela.casemanagement.domain.model.FlaggedCaseMessage;

/**
 * Tests para OpenCaseService.
 *
 * <p>Verifica:
 * <ul>
 *   <li>TEST-S2-019: Inserta caso + auditoría idempotente</li>
 *   <li>Idempotencia: reprocesar el mismo mensaje no duplica el caso</li>
 * </ul>
 */
@DisplayName("OpenCaseService")
class OpenCaseServiceTest {

    private static final String TX_ID = "tx-001";
    private static final String ACCOUNT_ID = "acc-123";
    private static final String REASON = "velocity exceeded";
    private static final String RULES = "RULE_VELOCITY_5MIN,RULE_AMOUNT_THRESHOLD";

    private CaseRepositoryPort repositoryPort;
    private Clock fixedClock;
    private OpenCaseService sut;

    @BeforeEach
    void setUp() {
        repositoryPort = mock(CaseRepositoryPort.class);
        fixedClock = Clock.fixed(Instant.parse("2025-07-23T12:00:00Z"), ZoneId.of("UTC"));
        sut = new OpenCaseService(repositoryPort, fixedClock);
    }

    @Nested
    @DisplayName("openCase")
    class OpenCaseTests {

        @Test
        @DisplayName("crea caso y auditoría cuando no existe caso previo")
        void createsCaseAndAudit_whenNoExistingCase() {
            // Given
            FlaggedCaseMessage message = new FlaggedCaseMessage(TX_ID, ACCOUNT_ID, REASON, RULES, "msg-1");
            when(repositoryPort.findByTransactionId(TX_ID)).thenReturn(Optional.empty());

            // When
            Case_ result = sut.openCase(message);

            // Then
            assertThat(result).isNotNull();
            assertThat(result.transactionId()).isEqualTo(TX_ID);
            assertThat(result.status()).isEqualTo(Case_.CaseStatus.OPEN);
            assertThat(result.caseId()).isNotNull();

            verify(repositoryPort).saveCaseWithAudit(any(Case_.class), any(CaseAuditEntry.class));
        }

        @Test
        @DisplayName("TEST-S2-019: inserta caso + auditoría idempotente")
        void insertsCaseWithAudit_idempotent() {
            // Given - mismo mensaje procesado antes
            FlaggedCaseMessage message = new FlaggedCaseMessage(TX_ID, ACCOUNT_ID, REASON, RULES, "msg-1");
            Case_ existingCase = new Case_(
                    "existing-case-id",
                    TX_ID,
                    Case_.CaseStatus.OPEN,
                    Instant.parse("2025-07-23T10:00:00Z").atZone(ZoneId.of("UTC")).toOffsetDateTime(),
                    Instant.parse("2025-07-23T10:00:00Z").atZone(ZoneId.of("UTC")).toOffsetDateTime());
            when(repositoryPort.findByTransactionId(TX_ID)).thenReturn(Optional.of(existingCase));

            // When
            Case_ result = sut.openCase(message);

            // Then - retorna el caso existente sin crear nuevo
            assertThat(result.caseId()).isEqualTo("existing-case-id");
            verify(repositoryPort, never()).saveCaseWithAudit(any(), any());
        }

        @Test
        @DisplayName("lanza excepción cuando mensaje es null")
        void throwsException_whenMessageIsNull() {
            assertThatThrownBy(() -> sut.openCase(null))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessage("message is required");
        }

        @Test
        @DisplayName("genera detalles de auditoría correctos")
        void generatesCorrectAuditDetails() {
            // Given
            FlaggedCaseMessage message = new FlaggedCaseMessage(TX_ID, ACCOUNT_ID, REASON, RULES, "msg-1");
            when(repositoryPort.findByTransactionId(TX_ID)).thenReturn(Optional.empty());

            // When
            sut.openCase(message);

            // Then - capturamos el argumento de auditoría
            verify(repositoryPort).saveCaseWithAudit(any(Case_.class), argThat(audit -> {
                assertThat(audit.action()).isEqualTo(CaseAuditEntry.AuditAction.OPENED);
                assertThat(audit.transactionId()).isEqualTo(TX_ID);
                assertThat(audit.details()).contains(REASON);
                assertThat(audit.details()).contains(RULES);
                return true;
            }));
        }
    }

    @Nested
    @DisplayName("idempotencia")
    class IdempotencyTests {

        @Test
        @DisplayName("no duplica caso cuando se procesa el mismo mensaje dos veces")
        void doesNotDuplicateCase_whenSameMessageProcessedTwice() {
            // Given
            FlaggedCaseMessage message = new FlaggedCaseMessage(TX_ID, ACCOUNT_ID, REASON, RULES, "msg-1");
            Case_ existingCase = new Case_(
                    "case-1",
                    TX_ID,
                    Case_.CaseStatus.OPEN,
                    Instant.parse("2025-07-23T10:00:00Z").atZone(ZoneId.of("UTC")).toOffsetDateTime(),
                    Instant.parse("2025-07-23T10:00:00Z").atZone(ZoneId.of("UTC")).toOffsetDateTime());
            when(repositoryPort.findByTransactionId(TX_ID)).thenReturn(Optional.of(existingCase));

            // When - primera y segunda llamada
            Case_ firstResult = sut.openCase(message);
            Case_ secondResult = sut.openCase(message);

            // Then
            assertThat(firstResult.caseId()).isEqualTo(secondResult.caseId());
            verify(repositoryPort, never()).saveCaseWithAudit(any(), any());
        }

        @Test
        @DisplayName("crea nuevo caso para diferente transactionId")
        void createsNewCase_forDifferentTransactionId() {
            // Given
            FlaggedCaseMessage message1 = new FlaggedCaseMessage("tx-001", ACCOUNT_ID, REASON, RULES, "msg-1");
            FlaggedCaseMessage message2 = new FlaggedCaseMessage("tx-002", ACCOUNT_ID, REASON, RULES, "msg-2");
            when(repositoryPort.findByTransactionId("tx-001")).thenReturn(Optional.empty());
            when(repositoryPort.findByTransactionId("tx-002")).thenReturn(Optional.empty());

            // When
            Case_ case1 = sut.openCase(message1);
            Case_ case2 = sut.openCase(message2);

            // Then
            assertThat(case1.caseId()).isNotEqualTo(case2.caseId());
            assertThat(case1.transactionId()).isNotEqualTo(case2.transactionId());
            // Se llama porque el mock no hace nada pero el código lo invoca
            verify(repositoryPort, times(2)).saveCaseWithAudit(any(), any());
        }
    }
}
