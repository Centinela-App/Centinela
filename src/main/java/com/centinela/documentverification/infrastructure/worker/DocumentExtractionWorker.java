package com.centinela.documentverification.infrastructure.worker;

import com.centinela.documentverification.application.port.in.ExtractVerificationDocumentUseCase;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.util.Objects;

/**
 * Dispara la extraccion documental en segundo plano.
 *
 * <p>La extraccion es asincrona respecto a la carga: el analista recibe su {@code 201} en
 * cuanto el archivo esta guardado, sin esperar a que se procese. Un documento grande, o un
 * motor lento, no se traducen en una peticion HTTP colgada.
 */
@Component
@ConditionalOnProperty(name = "centinela.document-verification.enabled", havingValue = "true")
public class DocumentExtractionWorker {

    private static final Logger log = LoggerFactory.getLogger(DocumentExtractionWorker.class);

    private final ExtractVerificationDocumentUseCase extractVerificationDocument;

    public DocumentExtractionWorker(ExtractVerificationDocumentUseCase extractVerificationDocument) {
        this.extractVerificationDocument =
                Objects.requireNonNull(extractVerificationDocument, "extractVerificationDocument is required");
        log.info("Document extraction worker enabled");
    }

    @Scheduled(
            fixedDelayString = "${centinela.document-verification.poll-interval-ms:5000}",
            initialDelayString = "${centinela.document-verification.initial-delay-ms:10000}")
    public void processPendingDocuments() {
        try {
            extractVerificationDocument.processPending();
        } catch (RuntimeException exception) {
            log.error("Document extraction batch failed; will retry on next cycle", exception);
        }
    }
}
