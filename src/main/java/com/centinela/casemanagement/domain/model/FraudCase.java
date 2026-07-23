package com.centinela.casemanagement.domain.model;

import jakarta.persistence.*;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;

/**
 * Entidad de dominio: Caso de fraude.
 * Historia: HU-S2-001
 */
@Entity
@Table(name = "fraud_case")
public class FraudCase {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "transaction_id", nullable = false, unique = true)
    private String transactionId;

    @Column(precision = 5, scale = 2)
    private BigDecimal score;

    @Column(name = "state_code", nullable = false)
    private String stateCode;

    @Column(name = "opened_at", nullable = false, updatable = false)
    private Instant openedAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "state_code", insertable = false, updatable = false)
    private CaseState state;

    @OneToMany(mappedBy = "fraudCase", cascade = CascadeType.ALL, orphanRemoval = true)
    private List<CaseAssignment> assignments = new ArrayList<>();

    @OneToOne(mappedBy = "fraudCase", cascade = CascadeType.ALL)
    private CaseResolution resolution;

    protected FraudCase() {
        // JPA
    }

    public FraudCase(String transactionId, BigDecimal score, String stateCode) {
        this.transactionId = Objects.requireNonNull(transactionId);
        this.score = score;
        this.stateCode = Objects.requireNonNull(stateCode);
        this.openedAt = Instant.now();
        this.updatedAt = Instant.now();
    }

    @PrePersist
    protected void onCreate() {
        if (openedAt == null) openedAt = Instant.now();
        if (updatedAt == null) updatedAt = Instant.now();
    }

    @PreUpdate
    protected void onUpdate() {
        this.updatedAt = Instant.now();
    }

    // Getters
    public Long getId() { return id; }
    public String getTransactionId() { return transactionId; }
    public BigDecimal getScore() { return score; }
    public String getStateCode() { return stateCode; }
    public Instant getOpenedAt() { return openedAt; }
    public Instant getUpdatedAt() { return updatedAt; }
    public CaseState getState() { return state; }
    public List<CaseAssignment> getAssignments() { return assignments; }
    public CaseResolution getResolution() { return resolution; }

    public void changeState(String newStateCode) {
        this.stateCode = Objects.requireNonNull(newStateCode);
        this.updatedAt = Instant.now();
    }
}
