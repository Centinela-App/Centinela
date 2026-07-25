package com.centinela.casemanagement.application.service;

import com.centinela.casemanagement.application.port.out.CaseRepositoryPort;
import com.centinela.casemanagement.domain.model.CaseAuditEntry;
import com.centinela.casemanagement.domain.model.Case_;
import com.centinela.shared.event.FlaggedCaseMessage;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

import java.math.BigDecimal;
import java.time.Clock;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class OpenCaseServiceTest {
    private static final Instant NOW = Instant.parse("2026-07-25T15:00:00Z");
    private CaseRepositoryPort repository;
    private OpenCaseService service;

    @BeforeEach
    void setUp() {
        repository = mock(CaseRepositoryPort.class);
        service = new OpenCaseService(repository, Clock.fixed(NOW, ZoneOffset.UTC));
    }

    @Test
    void opens_case_and_audit_from_the_shared_contract() {
        FlaggedCaseMessage message = message();
        when(repository.findByTransactionId("tx-001")).thenReturn(Optional.empty());
        when(repository.saveCaseWithAudit(any(), any())).thenAnswer(invocation -> {
            Case_ pending = invocation.getArgument(0);
            return new Case_(1L, pending.transactionId(), pending.score(), pending.status(),
                    pending.createdAt(), pending.updatedAt());
        });

        Case_ result = service.openCase(message);

        assertThat(result.caseId()).isEqualTo(1L);
        assertThat(result.transactionId()).isEqualTo("tx-001");
        assertThat(result.score()).isEqualByComparingTo(new BigDecimal("85"));
        assertThat(result.status()).isEqualTo(Case_.CaseStatus.NEW);

        ArgumentCaptor<CaseAuditEntry> audit = ArgumentCaptor.forClass(CaseAuditEntry.class);
        verify(repository).saveCaseWithAudit(any(Case_.class), audit.capture());
        assertThat(audit.getValue().getChangeType()).isEqualTo("OPENED");
        assertThat(audit.getValue().getDetails())
                .contains("accountId=acc-001", "VELOCITY:35", "ATYPICAL_AMOUNT:50");
    }

    @Test
    void returns_existing_case_without_duplicate_insert() {
        Case_ existing = new Case_(7L, "tx-001", new BigDecimal("85"), Case_.CaseStatus.NEW,
                OffsetDateTime.ofInstant(NOW, ZoneOffset.UTC), OffsetDateTime.ofInstant(NOW, ZoneOffset.UTC));
        when(repository.findByTransactionId("tx-001")).thenReturn(Optional.of(existing));

        assertThat(service.openCase(message())).isSameAs(existing);
        verify(repository, never()).saveCaseWithAudit(any(), any());
    }

    @Test
    void rejects_null_message() {
        assertThatThrownBy(() -> service.openCase(null))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessage("message is required");
    }

    private static FlaggedCaseMessage message() {
        return new FlaggedCaseMessage(
                "tx-001",
                "acc-001",
                85,
                List.of(
                        new FlaggedCaseMessage.TriggeredRuleSummary("VELOCITY", 35),
                        new FlaggedCaseMessage.TriggeredRuleSummary("ATYPICAL_AMOUNT", 50)),
                OffsetDateTime.parse("2026-07-25T14:59:00Z"),
                OffsetDateTime.parse("2026-07-25T15:00:00Z"));
    }
}
