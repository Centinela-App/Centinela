package com.centinela.casemanagement.domain.model;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.OneToMany;
import jakarta.persistence.OneToOne;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;

/** Entidad JPA alineada con la tabla {@code fraud_case}. */
@Entity
@Table(name = "fraud_case")
public class FraudCase {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "transaction_id", nullable = false, unique = true, length = 128)
    private String transactionId;

    @Column(nullable = false, precision = 5, scale = 2)
    private BigDecimal score;

    @Column(name = "state_code", nullable = false, length = 32)
    private String stateCode;

    @Column(name = "opened_at", nullable = false, updatable = false)
    private Instant openedAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "state_code", insertable = false, updatable = false)
    private CaseState state;

    @OneToMany(mappedBy = "fraudCase")
    private List<CaseAssignment> assignments = new ArrayList<>();

    @OneToOne(mappedBy = "fraudCase")
    private CaseResolution resolution;

    protected FraudCase() {
    }

    public FraudCase(String transactionId, BigDecimal score, String stateCode) {
        this.transactionId = Objects.requireNonNull(transactionId, "transactionId is required");
        this.score = Objects.requireNonNull(score, "score is required");
        this.stateCode = Objects.requireNonNull(stateCode, "stateCode is required");
    }

    public static FraudCase fromDomain(Case_ case_) {
        FraudCase entity = new FraudCase(case_.transactionId(), case_.score(), case_.status().name());
        entity.openedAt = case_.createdAt().toInstant();
        entity.updatedAt = case_.updatedAt().toInstant();
        return entity;
    }

    public Case_ toDomain() {
        return new Case_(
                id,
                transactionId,
                score,
                Case_.CaseStatus.valueOf(stateCode),
                OffsetDateTime.ofInstant(openedAt, ZoneOffset.UTC),
                OffsetDateTime.ofInstant(updatedAt, ZoneOffset.UTC));
    }

    @PrePersist
    protected void onCreate() {
        Instant now = Instant.now();
        if (openedAt == null) openedAt = now;
        if (updatedAt == null) updatedAt = now;
    }

    @PreUpdate
    protected void onUpdate() {
        updatedAt = Instant.now();
    }

    public Long getId() { return id; }
    public String getTransactionId() { return transactionId; }
    public BigDecimal getScore() { return score; }
    public String getStateCode() { return stateCode; }
    public Instant getOpenedAt() { return openedAt; }
    public Instant getUpdatedAt() { return updatedAt; }
    public CaseState getState() { return state; }
    public List<CaseAssignment> getAssignments() { return assignments; }
    public CaseResolution getResolution() { return resolution; }
}
