package com.centinela.caseinquiry.infrastructure.web.dto;

import com.centinela.caseinquiry.domain.model.CaseView;
import com.centinela.caseinquiry.domain.model.VerificationDocumentView;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;

/** Caso de fraude tal como lo consulta un analista o un cliente autorizado. */
public record CaseResponse(
        Long caseId,
        String transactionId,
        String accountId,
        BigDecimal score,
        String status,
        String explanationState,
        String explanation,
        String traceparent,
        Instant openedAt,
        Instant updatedAt,
        List<VerificationDocumentResponse> verificationDocuments) {

    public static CaseResponse from(CaseView view) {
        return new CaseResponse(
                view.caseId(),
                view.transactionId(),
                view.accountId(),
                view.score(),
                view.status(),
                view.explanationState(),
                view.explanation(),
                view.traceparent(),
                view.openedAt(),
                view.updatedAt(),
                view.documents().stream().map(VerificationDocumentResponse::from).toList());
    }

    /**
     * Documento adjunto con el desenlace de su extraccion.
     *
     * <p>{@code failureReason} se expone a proposito: un documento ilegible tiene que
     * poder consultarse con el motivo, no aparecer simplemente como un registro vacio.
     */
    public record VerificationDocumentResponse(
            Long documentId,
            String state,
            String contentType,
            String fullName,
            String documentNumber,
            LocalDate birthDate,
            LocalDate expiryDate,
            String extractionEngine,
            String failureReason,
            Instant receivedAt,
            Instant processedAt,
            Instant analystNotifiedAt) {

        static VerificationDocumentResponse from(VerificationDocumentView view) {
            return new VerificationDocumentResponse(
                    view.documentId(),
                    view.state(),
                    view.contentType(),
                    view.fullName(),
                    view.documentNumber(),
                    view.birthDate(),
                    view.expiryDate(),
                    view.extractionEngine(),
                    view.failureReason(),
                    view.receivedAt(),
                    view.processedAt(),
                    view.analystNotifiedAt());
        }
    }
}
