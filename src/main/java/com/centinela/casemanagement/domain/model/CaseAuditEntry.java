package com.centinela.casemanagement.domain.model;

import java.time.Instant;

/** Entrada append-only de auditoria de un caso. */
public class CaseAuditEntry {
    private Long id;
    private Long caseId;
    private final String fieldName;
    private final String oldValue;
    private final String newValue;
    private final String changedBy;
    private Instant changedAt;
    private final String changeType;
    private final String details;

    public CaseAuditEntry(Long caseId, String fieldName, String oldValue, String newValue,
                          String changedBy, String changeType) {
        this(caseId, fieldName, oldValue, newValue, changedBy, changeType, null);
    }

    public CaseAuditEntry(Long caseId, String fieldName, String oldValue, String newValue,
                          String changedBy, String changeType, String details) {
        this.caseId = caseId;
        this.fieldName = fieldName;
        this.oldValue = oldValue;
        this.newValue = newValue;
        this.changedBy = changedBy;
        this.changeType = changeType;
        this.details = details;
    }

    public Long getId() { return id; }
    public Long getCaseId() { return caseId; }
    public String getFieldName() { return fieldName; }
    public String getOldValue() { return oldValue; }
    public String getNewValue() { return newValue; }
    public String getChangedBy() { return changedBy; }
    public Instant getChangedAt() { return changedAt; }
    public String getChangeType() { return changeType; }
    public String getDetails() { return details; }

    public void assignId(Long id) { this.id = id; }
    public void assignCaseId(Long caseId) { this.caseId = caseId; }
    public void assignChangedAt(Instant changedAt) { this.changedAt = changedAt; }
}
