package com.centinela.caseinquiry.domain.model;

import java.time.Instant;
import java.time.LocalDate;

/**
 * Vista de un documento de verificacion adjunto al caso.
 *
 * <p>Expone tanto los datos extraidos como el motivo del fallo cuando no se pudieron
 * extraer. Es la superficie que hace cierto el requisito de que un documento ilegible
 * "quede en un estado consultable": el analista ve que cargo, que paso y que debe hacer.
 */
public record VerificationDocumentView(
        Long documentId,
        String blobPath,
        String contentType,
        String state,
        String fullName,
        String documentNumber,
        LocalDate birthDate,
        LocalDate expiryDate,
        String extractionEngine,
        String failureReason,
        Instant receivedAt,
        Instant processedAt,
        Instant analystNotifiedAt) {
}
