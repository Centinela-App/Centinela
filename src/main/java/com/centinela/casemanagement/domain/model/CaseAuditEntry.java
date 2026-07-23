package com.centinela.casemanagement.domain.model;

import jakarta.persistence.*;
import java.time.Instant;
import java.util.Objects;

/**
 * Entidad de dominio: Entrada de auditoría (append-only).
 * Historia: HU-S2-001 · Criterio: Auditoría inmutable
 */
@Entity
@Table(name = "case_audit")
public class CaseAuditEntry {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "case_id", nullable = false)
    private Long caseId;

    @Column(name = "field_name", nullable = false, length = 64)
    private String fieldName;

    @Column(name = "old_value", columnDefinition = "TEXT")
    private String oldValue;

    @Column(name = "new_value", columnDefinition = "TEXT")
    private String newValue;

    @Column(name = "changed_by", nullable = false)
    private String changedBy;

    @Column(name = "changed_at", nullable = false, updatable = false)
    private Instant changedAt;

    @Column(name = "change_type", nullable = false, length = 32)
    private String changeType;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "case_id", insertable = false, updatable = false)
    private FraudCase fraudCase;

    protected CaseAuditEntry() {
        // JPA
    }

    public CaseAuditEntry(Long caseId, String fieldName, String oldValue,
                          String newValue, String changedBy, String changeType) {
        this.caseId = Objects.requireNonNull(caseId);
        this.fieldName = Objects.requireNonNull(fieldName);
        this.oldValue = oldValue;
        this.newValue = newValue;
        this.changedBy = Objects.requireNonNull(changedBy);
        this.changeType = Objects.requireNonNull(changeType);
        this.changedAt = Instant.now();
    }

    @PrePersist
    protected void onCreate() {
        if (changedAt == null) changedAt = Instant.now();
    }

    // Getters (sin setters para mantener inmutabilidad)
    public Long getId() { return id; }
    public Long getCaseId() { return caseId; }
    public String getFieldName() { return fieldName; }
    public String getOldValue() { return oldValue; }
    public String getNewValue() { return newValue; }
    public String getChangedBy() { return changedBy; }
    public Instant getChangedAt() { return changedAt; }
    public String getChangeType() { return changeType; }
    public FraudCase getFraudCase() { return fraudCase; }
}
