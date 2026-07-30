package com.centinela.casemanagement.infrastructure.persistence;

import com.centinela.casemanagement.domain.model.CaseAuditEntry;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.Instant;

@Entity
@Table(name = "case_audit")
public class CaseAuditEntity {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "case_id", nullable = false)
    private Long caseId;

    @Column(name = "field_name", nullable = false, length = 64)
    private String fieldName;

    @Column(name = "old_value")
    private String oldValue;

    @Column(name = "new_value")
    private String newValue;

    @Column(name = "changed_by", nullable = false, length = 256)
    private String changedBy;

    @Column(name = "changed_at", nullable = false, updatable = false)
    private Instant changedAt;

    @Column(name = "change_type", nullable = false, length = 32)
    private String changeType;

    @Column(name = "details")
    private String details;

    protected CaseAuditEntity() {
    }

    static CaseAuditEntity fromDomain(CaseAuditEntry entry) {
        CaseAuditEntity entity = new CaseAuditEntity();
        entity.caseId = entry.getCaseId();
        entity.fieldName = entry.getFieldName();
        entity.oldValue = entry.getOldValue();
        entity.newValue = entry.getNewValue();
        entity.changedBy = entry.getChangedBy();
        entity.changedAt = entry.getChangedAt() != null ? entry.getChangedAt() : Instant.now();
        entity.changeType = entry.getChangeType();
        entity.details = entry.getDetails();
        return entity;
    }

    CaseAuditEntry toDomain() {
        CaseAuditEntry entry = new CaseAuditEntry(
                caseId, fieldName, oldValue, newValue, changedBy, changeType, details);
        entry.assignId(id);
        entry.assignChangedAt(changedAt);
        return entry;
    }
}
