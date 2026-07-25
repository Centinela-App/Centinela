package com.centinela.casemanagement.application.service;

import com.centinela.casemanagement.application.port.in.OpenCaseUseCase;
import com.centinela.casemanagement.application.port.out.CaseRepositoryPort;
import com.centinela.casemanagement.domain.model.CaseAuditEntry;
import com.centinela.casemanagement.domain.model.Case_;
import com.centinela.shared.event.FlaggedCaseMessage;

import java.math.BigDecimal;
import java.time.Clock;
import java.time.OffsetDateTime;
import java.util.Objects;
import java.util.stream.Collectors;

/** Apertura idempotente de casos con auditoria atomica. */
public final class OpenCaseService implements OpenCaseUseCase {

    private static final String SYSTEM_USER = "system:queue-consumer";
    private final CaseRepositoryPort repositoryPort;
    private final Clock clock;

    public OpenCaseService(CaseRepositoryPort repositoryPort, Clock clock) {
        this.repositoryPort = Objects.requireNonNull(repositoryPort, "repositoryPort is required");
        this.clock = Objects.requireNonNull(clock, "clock is required");
    }

    @Override
    public Case_ openCase(FlaggedCaseMessage message) {
        if (message == null) {
            throw new IllegalArgumentException("message is required");
        }
        return repositoryPort.findByTransactionId(message.transactionId())
                .orElseGet(() -> createNewCase(message));
    }

    private Case_ createNewCase(FlaggedCaseMessage message) {
        OffsetDateTime now = OffsetDateTime.now(clock);
        Case_ newCase = new Case_(
                null,
                message.transactionId(),
                BigDecimal.valueOf(message.score()),
                Case_.CaseStatus.NEW,
                now,
                now);

        String rules = message.triggeredRules().stream()
                .map(rule -> rule.ruleId() + ":" + rule.points())
                .collect(Collectors.joining(","));
        String details = "accountId=" + message.accountId()
                + "; occurredAt=" + message.occurredAt()
                + "; scoredAt=" + message.scoredAt()
                + "; triggeredRules=" + rules;

        CaseAuditEntry auditEntry = new CaseAuditEntry(
                null,
                "state_code",
                null,
                Case_.CaseStatus.NEW.name(),
                SYSTEM_USER,
                "OPENED",
                details);

        return repositoryPort.saveCaseWithAudit(newCase, auditEntry);
    }
}
