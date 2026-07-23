package com.centinela.casemanagement.infrastructure.persistence;

import com.centinela.casemanagement.domain.model.Case_;
import jakarta.persistence.*;

/**
 * Entidad JPA para persistencia de casos de fraude.
 */
@Entity
@Table(name = "fraud_cases", indexes = {
        @Index(name = "idx_fraud_case_transaction_id", columnList = "transactionId", unique = true)
})
public class FraudCaseEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "case_id", nullable = false)
    private String caseId;

    @Column(name = "transaction_id", nullable = false, unique = true)
    private String transactionId;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false)
    private CaseStatus status;

    @Column(name = "created_at", nullable = false)
    private java.time.OffsetDateTime createdAt;

    @Column(name = "updated_at", nullable = false)
    private java.time.OffsetDateTime updatedAt;

    protected FraudCaseEntity() {
    }

    public static FraudCaseEntity fromDomain(Case_ case_) {
        FraudCaseEntity entity = new FraudCaseEntity();
        entity.caseId = case_.caseId();
        entity.transactionId = case_.transactionId();
        entity.status = CaseStatus.valueOf(case_.status().name());
        entity.createdAt = case_.createdAt();
        entity.updatedAt = case_.updatedAt();
        return entity;
    }

    public Case_ toDomain() {
        return new Case_(
                caseId,
                transactionId,
                Case_.CaseStatus.valueOf(status.name()),
                createdAt,
                updatedAt);
    }

    public enum CaseStatus {
        OPEN,
        UNDER_REVIEW,
        CLOSED
    }

    // Getters
    public Long getId() { return id; }
    public String getCaseId() { return caseId; }
    public String getTransactionId() { return transactionId; }
    public CaseStatus getStatus() { return status; }
    public java.time.OffsetDateTime getCreatedAt() { return createdAt; }
    public java.time.OffsetDateTime getUpdatedAt() { return updatedAt; }
}
