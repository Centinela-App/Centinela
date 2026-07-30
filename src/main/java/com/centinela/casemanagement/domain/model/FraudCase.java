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

    @Column(name = "account_id", length = 128)
    private String accountId;

    @Column(nullable = false, precision = 5, scale = 2)
    private BigDecimal score;

    @Column(name = "state_code", nullable = false, length = 32)
    private String stateCode;

    @Column(name = "traceparent", length = 64)
    private String traceparent;

    @Column(name = "explanation", columnDefinition = "text")
    private String explanation;

    @Column(name = "explanation_state", nullable = false, length = 16)
    private String explanationState;

    @Column(name = "explained_at")
    private Instant explainedAt;

    @Column(name = "explanation_attempts", nullable = false)
    private int explanationAttempts;

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
        this.explanationState = Case_.ExplanationState.PENDING.name();
    }

    public static FraudCase fromDomain(Case_ case_) {
        FraudCase entity = new FraudCase(case_.transactionId(), case_.score(), case_.status().name());
        entity.accountId = case_.accountId();
        entity.traceparent = case_.traceparent();
        entity.explanation = case_.explanation();
        entity.explanationState = (case_.explanationState() == null
                ? Case_.ExplanationState.PENDING
                : case_.explanationState()).name();
        entity.openedAt = case_.createdAt().toInstant();
        entity.updatedAt = case_.updatedAt().toInstant();
        return entity;
    }

    public Case_ toDomain() {
        return new Case_(
                id,
                transactionId,
                accountId,
                score,
                Case_.CaseStatus.valueOf(stateCode),
                traceparent,
                Case_.ExplanationState.valueOf(
                        explanationState == null ? Case_.ExplanationState.PENDING.name() : explanationState),
                explanation,
                OffsetDateTime.ofInstant(openedAt, ZoneOffset.UTC),
                OffsetDateTime.ofInstant(updatedAt, ZoneOffset.UTC));
    }

    /**
     * Fija la explicacion generada.
     *
     * <p>Es la unica transicion a {@code GENERATED}: obliga a que el texto y el estado se
     * escriban juntos, de modo que no pueda existir un caso marcado como explicado con la
     * explicacion en blanco.
     */
    public void attachExplanation(String generatedExplanation, Instant generatedAt) {
        if (generatedExplanation == null || generatedExplanation.isBlank()) {
            throw new IllegalArgumentException("explanation must not be blank");
        }
        this.explanation = generatedExplanation;
        this.explanationState = Case_.ExplanationState.GENERATED.name();
        this.explainedAt = Objects.requireNonNull(generatedAt, "generatedAt is required");
        this.explanationAttempts++;
    }

    /**
     * Registra un intento fallido de explicacion.
     *
     * <p>El caso permanece abierto y accionable: la falta de explicacion degrada la
     * experiencia del analista, no la validez del caso.
     */
    public void recordFailedExplanationAttempt(int maxAttempts) {
        this.explanationAttempts++;
        if (this.explanationAttempts >= maxAttempts) {
            this.explanationState = Case_.ExplanationState.FAILED.name();
        }
    }

    @PrePersist
    protected void onCreate() {
        Instant now = Instant.now();
        if (openedAt == null) openedAt = now;
        if (updatedAt == null) updatedAt = now;
        if (explanationState == null) explanationState = Case_.ExplanationState.PENDING.name();
    }

    @PreUpdate
    protected void onUpdate() {
        updatedAt = Instant.now();
    }

    public Long getId() { return id; }
    public String getTransactionId() { return transactionId; }
    public String getAccountId() { return accountId; }
    public BigDecimal getScore() { return score; }
    public String getStateCode() { return stateCode; }
    public String getTraceparent() { return traceparent; }
    public String getExplanation() { return explanation; }
    public String getExplanationState() { return explanationState; }
    public Instant getExplainedAt() { return explainedAt; }
    public int getExplanationAttempts() { return explanationAttempts; }
    public Instant getOpenedAt() { return openedAt; }
    public Instant getUpdatedAt() { return updatedAt; }
    public CaseState getState() { return state; }
    public List<CaseAssignment> getAssignments() { return assignments; }
    public CaseResolution getResolution() { return resolution; }
}
