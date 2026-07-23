package com.centinela.casemanagement.domain.model;

import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.Table;

/**
 * Entrada de auditoría para un caso.
 *
 * <p>Registra todas las acciones realizadas sobre un caso para trazabilidad.
 */
@Entity
@Table(name = "case_audit_entries", indexes = {
        @Index(name = "idx_audit_case_id", columnList = "caseId"),
        @Index(name = "idx_audit_transaction_id", columnList = "transactionId")
})
public class CaseAuditEntry {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private String entryId;
    private String caseId;
    private String transactionId;

    @Enumerated(EnumType.STRING)
    private AuditAction action;

    private String performedBy;
    private String details;

    public CaseAuditEntry() {
    }

    public CaseAuditEntry(String entryId, String caseId, String transactionId,
                          AuditAction action, String performedBy, String details) {
        this.entryId = entryId;
        this.caseId = caseId;
        this.transactionId = transactionId;
        this.action = action;
        this.performedBy = performedBy;
        this.details = details;
    }

    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public String getEntryId() {
        return entryId;
    }

    public void setEntryId(String entryId) {
        this.entryId = entryId;
    }

    public String getCaseId() {
        return caseId;
    }

    public void setCaseId(String caseId) {
        this.caseId = caseId;
    }

    public String getTransactionId() {
        return transactionId;
    }

    public void setTransactionId(String transactionId) {
        this.transactionId = transactionId;
    }

    public AuditAction getAction() {
        return action;
    }

    public void setAction(AuditAction action) {
        this.action = action;
    }

    public String getPerformedBy() {
        return performedBy;
    }

    public void setPerformedBy(String performedBy) {
        this.performedBy = performedBy;
    }

    public String getDetails() {
        return details;
    }

    public void setDetails(String details) {
        this.details = details;
    }

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
