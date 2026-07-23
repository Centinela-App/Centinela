package com.centinela.casemanagement.application.service;

import java.time.Clock;
import java.time.OffsetDateTime;
import java.util.Objects;
import java.util.UUID;

import com.centinela.casemanagement.application.port.in.OpenCaseUseCase;
import com.centinela.casemanagement.application.port.out.CaseRepositoryPort;
import com.centinela.casemanagement.domain.model.CaseAuditEntry;
import com.centinela.casemanagement.domain.model.Case_;
import com.centinela.casemanagement.domain.model.FlaggedCaseMessage;

/**
 * Servicio de apertura de casos.
 *
 * <p>Implementa el caso de uso de crear un caso cuando se recibe un mensaje
 * flagged desde la cola. Es idempotente por transactionId: si el mismo
 * mensaje se procesa múltiples veces, solo se crea un caso.
 *
 * <p>La auditoría de apertura se registra junto con el caso en la misma
 * transacción de base de datos para garantizar consistencia.
 */
public final class OpenCaseService implements OpenCaseUseCase {

    private static final String SYSTEM_USER = "system:queue-consumer";

    private final CaseRepositoryPort repositoryPort;
    private final Clock instantiationClock;

    public OpenCaseService(CaseRepositoryPort repositoryPort, Clock instantiationClock) {
        this.repositoryPort = Objects.requireNonNull(repositoryPort, "repositoryPort is required");
        this.instantiationClock = Objects.requireNonNull(instantiationClock, "instantiationClock is required");
    }

    @Override
    public Case_ openCase(FlaggedCaseMessage message) {
        if (message == null) {
            throw new IllegalArgumentException("message is required");
        }

        // Idempotencia: si ya existe un caso para esta transacción, devolver el existente
        return repositoryPort.findByTransactionId(message.transactionId())
                .orElseGet(() -> createNewCase(message));
    }

    private Case_ createNewCase(FlaggedCaseMessage message) {
        OffsetDateTime now = OffsetDateTime.now(instantiationClock);
        String caseId = UUID.randomUUID().toString();

        Case_ newCase = new Case_(
                caseId,
                message.transactionId(),
                Case_.CaseStatus.OPEN,
                now,
                now);

        CaseAuditEntry auditEntry = new CaseAuditEntry(
                UUID.randomUUID().toString(),
                caseId,
                message.transactionId(),
                CaseAuditEntry.AuditAction.OPENED,
                SYSTEM_USER,
                buildAuditDetails(message));

        // Guardar caso y auditoría en la misma transacción
        repositoryPort.saveCaseWithAudit(newCase, auditEntry);

        return newCase;
    }

    private String buildAuditDetails(FlaggedCaseMessage message) {
        return String.format(
                "Case opened from flagged transaction. Reason: %s. Triggered rules: %s",
                message.reason(),
                message.triggeredRules());
    }
}
