package com.centinela.casemanagement.domain.model;

import java.math.BigDecimal;
import java.time.OffsetDateTime;

/** Caso generado a partir de un mensaje {@code flagged-case-v1}. */
public record Case_(
        Long caseId,
        String transactionId,
        String accountId,
        BigDecimal score,
        CaseStatus status,
        String traceparent,
        ExplanationState explanationState,
        String explanation,
        OffsetDateTime createdAt,
        OffsetDateTime updatedAt) {

    /**
     * Forma heredada de Semana 2, sin correlacion ni explicacion.
     *
     * <p>Un caso creado asi nace {@link ExplanationState#PENDING}, que es exactamente lo
     * que ocurre en produccion: el caso se abre primero y se explica despues.
     */
    public Case_(
            Long caseId,
            String transactionId,
            BigDecimal score,
            CaseStatus status,
            OffsetDateTime createdAt,
            OffsetDateTime updatedAt) {
        this(caseId, transactionId, null, score, status, null,
                ExplanationState.PENDING, null, createdAt, updatedAt);
    }

    public enum CaseStatus {
        NEW,
        UNDER_REVIEW,
        PENDING_INFO,
        ESCALATED,
        RESOLVED,
        DISMISSED
    }

    /**
     * Estado de la explicacion, independiente del estado del caso.
     *
     * <p>Son dos ciclos de vida distintos: un caso puede estar RESUELTO y sin explicar, o
     * NUEVO y explicado. Mezclarlos obligaria a que la caida del explicador alterara el
     * flujo de trabajo del analista, que es justo lo que el enunciado prohibe.
     */
    public enum ExplanationState {
        /** Caso abierto; el explicador aun no lo ha procesado. */
        PENDING,
        /** Explicacion generada y disponible para el analista. */
        GENERATED,
        /** El explicador agoto sus reintentos. El caso sigue siendo valido y accionable. */
        FAILED
    }
}
