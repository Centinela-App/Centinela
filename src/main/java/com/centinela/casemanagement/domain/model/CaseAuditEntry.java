package com.centinela.casemanagement.domain.model;

/**
 * Entrada de auditoría para un caso.
 *
 * <p>Registra todas las acciones realizadas sobre un caso para trazabilidad.
 */
public record CaseAuditEntry(
        String entryId,
        String caseId,
        String transactionId,
        AuditAction action,
        String performedBy,
        String details) {

    /**
     * Acciones auditables en un caso.
     */
    public enum AuditAction {
        /** Caso abierto/recibido desde la cola. */
        OPENED,

        /** Caso asignado a un analista. */
        ASSIGNED,

        /** Estado del caso actualizado. */
        STATUS_CHANGED,

        /** Resolución aplicada al caso. */
        RESOLVED
    }
}
