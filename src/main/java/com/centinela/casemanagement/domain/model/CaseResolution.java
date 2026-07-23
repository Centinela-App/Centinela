package com.centinela.casemanagement.domain.model;

import jakarta.persistence.*;
import java.time.Instant;
import java.util.Objects;

/**
 * Entidad de dominio: Resolución de caso.
 * Historia: HU-S2-001
 */
@Entity
@Table(name = "case_resolution")
public class CaseResolution {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @OneToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "case_id", nullable = false, unique = true)
    private FraudCase fraudCase;

    @Column(nullable = false, length = 32)
    private String decision;

    @Column(name = "analyst_id", nullable = false, length = 128)
    private String analystId;

    @Column(name = "resolved_at", nullable = false, updatable = false)
    private Instant resolvedAt;

    @Column(columnDefinition = "TEXT")
    private String observations;

    protected CaseResolution() {
        // JPA
    }

    public CaseResolution(FraudCase fraudCase, String decision, String analystId, String observations) {
        this.fraudCase = Objects.requireNonNull(fraudCase);
        this.decision = Objects.requireNonNull(decision);
        this.analystId = Objects.requireNonNull(analystId);
        this.observations = observations;
        this.resolvedAt = Instant.now();
    }

    @PrePersist
    protected void onCreate() {
        if (resolvedAt == null) resolvedAt = Instant.now();
    }

    // Getters
    public Long getId() { return id; }
    public FraudCase getFraudCase() { return fraudCase; }
    public String getDecision() { return decision; }
    public String getAnalystId() { return analystId; }
    public Instant getResolvedAt() { return resolvedAt; }
    public String getObservations() { return observations; }
}
