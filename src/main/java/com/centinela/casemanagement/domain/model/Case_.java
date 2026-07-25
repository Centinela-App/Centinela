package com.centinela.casemanagement.domain.model;

import java.math.BigDecimal;
import java.time.OffsetDateTime;

/** Caso generado a partir de un mensaje {@code flagged-case-v1}. */
public record Case_(
        Long caseId,
        String transactionId,
        BigDecimal score,
        CaseStatus status,
        OffsetDateTime createdAt,
        OffsetDateTime updatedAt) {

    public enum CaseStatus {
        NEW,
        UNDER_REVIEW,
        PENDING_INFO,
        ESCALATED,
        RESOLVED,
        DISMISSED
    }
}
