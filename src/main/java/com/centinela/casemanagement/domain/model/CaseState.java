package com.centinela.casemanagement.domain.model;

import jakarta.persistence.*;
import java.time.Instant;
import java.util.Objects;

/**
 * Entidad de dominio: Estado de caso (catálogo).
 * Historia: HU-S2-001
 */
@Entity
@Table(name = "case_state")
public class CaseState {

    @Id
    @Column(length = 32)
    private String code;

    @Column(nullable = false, length = 128)
    private String name;

    @Column(columnDefinition = "TEXT")
    private String description;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    protected CaseState() {
        // JPA
    }

    public CaseState(String code, String name, String description) {
        this.code = Objects.requireNonNull(code);
        this.name = Objects.requireNonNull(name);
        this.description = description;
        this.createdAt = Instant.now();
    }

    @PrePersist
    protected void onCreate() {
        if (createdAt == null) createdAt = Instant.now();
    }

    // Getters
    public String getCode() { return code; }
    public String getName() { return name; }
    public String getDescription() { return description; }
    public Instant getCreatedAt() { return createdAt; }
}
