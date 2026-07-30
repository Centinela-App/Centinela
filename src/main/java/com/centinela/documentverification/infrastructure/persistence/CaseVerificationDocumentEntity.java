package com.centinela.documentverification.infrastructure.persistence;

import com.centinela.documentverification.domain.model.DocumentState;
import com.centinela.documentverification.domain.model.ExtractedIdentityData;
import com.centinela.documentverification.domain.model.ExtractionOutcome;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.util.Objects;

/** Entidad JPA alineada con la tabla {@code case_verification_document}. */
@Entity
@Table(name = "case_verification_document")
public class CaseVerificationDocumentEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "case_id", nullable = false)
    private Long caseId;

    @Column(name = "blob_path", nullable = false, length = 512, unique = true)
    private String blobPath;

    @Column(name = "content_type", length = 128)
    private String contentType;

    @Column(name = "document_state", nullable = false, length = 32)
    private String documentState;

    @Column(name = "extracted_full_name", length = 256)
    private String extractedFullName;

    @Column(name = "extracted_document_number", length = 64)
    private String extractedDocumentNumber;

    @Column(name = "extracted_birth_date")
    private LocalDate extractedBirthDate;

    @Column(name = "extracted_expiry_date")
    private LocalDate extractedExpiryDate;

    @Column(name = "extraction_confidence", precision = 4, scale = 3)
    private BigDecimal extractionConfidence;

    @Column(name = "extraction_engine", length = 64)
    private String extractionEngine;

    @Column(name = "failure_reason", columnDefinition = "text")
    private String failureReason;

    @Column(name = "analyst_notified_at")
    private Instant analystNotifiedAt;

    @Column(name = "received_at", nullable = false, updatable = false)
    private Instant receivedAt;

    @Column(name = "processed_at")
    private Instant processedAt;

    protected CaseVerificationDocumentEntity() {
    }

    public CaseVerificationDocumentEntity(Long caseId, String blobPath, String contentType, Instant receivedAt) {
        this.caseId = Objects.requireNonNull(caseId, "caseId is required");
        this.blobPath = Objects.requireNonNull(blobPath, "blobPath is required");
        this.contentType = contentType;
        this.receivedAt = Objects.requireNonNull(receivedAt, "receivedAt is required");
        this.documentState = DocumentState.RECEIVED.name();
    }

    /**
     * Escribe el desenlace de la extraccion.
     *
     * <p>El instante de notificacion se fija en la misma operacion: un documento procesado
     * cuyo analista no fue avisado es, a efectos del requisito, un documento sin procesar.
     */
    public void applyOutcome(ExtractionOutcome outcome, Instant processedAt) {
        ExtractedIdentityData data = outcome.data();
        this.documentState = outcome.state().name();
        this.extractedFullName = data.fullName();
        this.extractedDocumentNumber = data.documentNumber();
        this.extractedBirthDate = data.birthDate();
        this.extractedExpiryDate = data.expiryDate();
        this.extractionConfidence = data.confidence() == null
                ? null
                : BigDecimal.valueOf(data.confidence()).setScale(3, java.math.RoundingMode.HALF_UP);
        this.extractionEngine = outcome.engine();
        this.failureReason = outcome.failureReason();
        this.processedAt = Objects.requireNonNull(processedAt, "processedAt is required");
        this.analystNotifiedAt = processedAt;
    }

    public Long getId() { return id; }
    public Long getCaseId() { return caseId; }
    public String getBlobPath() { return blobPath; }
    public String getContentType() { return contentType; }
    public String getDocumentState() { return documentState; }
    public String getExtractedFullName() { return extractedFullName; }
    public String getExtractedDocumentNumber() { return extractedDocumentNumber; }
    public LocalDate getExtractedBirthDate() { return extractedBirthDate; }
    public LocalDate getExtractedExpiryDate() { return extractedExpiryDate; }
    public String getExtractionEngine() { return extractionEngine; }
    public String getFailureReason() { return failureReason; }
    public Instant getAnalystNotifiedAt() { return analystNotifiedAt; }
    public Instant getReceivedAt() { return receivedAt; }
    public Instant getProcessedAt() { return processedAt; }
}
