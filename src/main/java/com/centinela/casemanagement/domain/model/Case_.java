package com.centinela.casemanagement.domain.model;

import java.time.OffsetDateTime;

/**
 * Caso generado a partir de una transacción flagged.
 *
 * <p>Representa el caso inicial creado cuando el motor de scoring detecta
 * comportamiento sospechoso y coloca un mensaje en la cola de casos.
 */
public record Case_(
        String caseId,
        String transactionId,
        CaseStatus status,
        OffsetDateTime createdAt,
        OffsetDateTime updatedAt) {

    /**
     * Estados posibles de un caso.
     */
    public enum CaseStatus {
        /** Caso recién creado, pendiente de revisión por analista. */
        OPEN,

        /** Caso en proceso de investigación. */
        UNDER_REVIEW,

        /** Caso cerrado con resolución. */
        CLOSED
    }
}
