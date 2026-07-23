package com.centinela.casemanagement.domain.model;

import jakarta.persistence.*;
import java.time.Instant;
import java.util.Objects;

/**
 * Entidad de dominio: Asignación de caso a analista.
 * Historia: HU-S2-001
 */
@Entity
@Table(name = "case_assignment")
public class CaseAssignment {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "case_id", nullable = false)
    private FraudCase fraudCase;

    @Column(name = "analyst_id", nullable = false, length = 128)
    private String analystId;

    @Column(name = "analyst_email", nullable = false, length = 256)
    private String analystEmail;

    @Column(name = "assigned_at", nullable = false, updatable = false)
    private Instant assignedAt;

    @Column(name = "unassigned_at")
    private Instant unassignedAt;

    protected CaseAssignment() {
        // JPA
    }

    public CaseAssignment(FraudCase fraudCase, String analystId, String analystEmail) {
        this.fraudCase = Objects.requireNonNull(fraudCase);
        this.analystId = Objects.requireNonNull(analystId);
        this.analystEmail = Objects.requireNonNull(analystEmail);
        this.assignedAt = Instant.now();
    }

    @PrePersist
    protected void onCreate() {
        if (assignedAt == null) assignedAt = Instant.now();
    }

    // Getters
    public Long getId() { return id; }
    public FraudCase getFraudCase() { return fraudCase; }
    public String getAnalystId() { return analystId; }
    public String getAnalystEmail() { return analystEmail; }
    public Instant getAssignedAt() { return assignedAt; }
    public Instant getUnassignedAt() { return unassignedAt; }

    public boolean isActive() {
        return unassignedAt == null;
    }

    public void unassign() {
        this.unassignedAt = Instant.now();
    }
}
