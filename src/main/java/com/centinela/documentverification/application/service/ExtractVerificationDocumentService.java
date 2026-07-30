package com.centinela.documentverification.application.service;

import com.centinela.documentverification.application.port.in.ExtractVerificationDocumentUseCase;
import com.centinela.documentverification.application.port.out.DocumentContentReaderPort;
import com.centinela.documentverification.application.port.out.IdentityDataExtractorPort;
import com.centinela.documentverification.application.port.out.VerificationDocumentRegistryPort;
import com.centinela.documentverification.domain.model.ExtractionOutcome;
import com.centinela.shared.telemetry.PipelineStage;
import com.centinela.shared.telemetry.StageTelemetry;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.time.Clock;
import java.util.List;
import java.util.Objects;
import java.util.Optional;

/**
 * Procesa los documentos pendientes de extraccion.
 *
 * <p>Toda la politica de fallos vive aqui, y se reduce a una regla: <b>ningun desenlace
 * interrumpe el flujo</b>. Documento ilegible, formato inesperado, blob desaparecido o
 * excepcion del motor terminan igual — una fila con estado, un mensaje para el analista y
 * el lote continuando con el siguiente documento. El caso permanece abierto y consultable
 * en todos los casos.
 */
public final class ExtractVerificationDocumentService implements ExtractVerificationDocumentUseCase {

    private static final Logger log = LoggerFactory.getLogger(ExtractVerificationDocumentService.class);

    private final VerificationDocumentRegistryPort registry;
    private final DocumentContentReaderPort contentReader;
    private final IdentityDataExtractorPort extractor;
    private final Clock clock;
    private final int batchSize;

    public ExtractVerificationDocumentService(
            VerificationDocumentRegistryPort registry,
            DocumentContentReaderPort contentReader,
            IdentityDataExtractorPort extractor,
            Clock clock,
            int batchSize) {
        this.registry = Objects.requireNonNull(registry, "registry is required");
        this.contentReader = Objects.requireNonNull(contentReader, "contentReader is required");
        this.extractor = Objects.requireNonNull(extractor, "extractor is required");
        this.clock = Objects.requireNonNull(clock, "clock is required");
        if (batchSize <= 0) throw new IllegalArgumentException("batchSize must be positive");
        this.batchSize = batchSize;
    }

    @Override
    public int processPending() {
        List<VerificationDocumentRegistryPort.PendingDocument> pending = registry.findPending(batchSize);
        int processed = 0;
        for (VerificationDocumentRegistryPort.PendingDocument document : pending) {
            process(document);
            processed++;
        }
        return processed;
    }

    private void process(VerificationDocumentRegistryPort.PendingDocument document) {
        long startedAt = StageTelemetry.startedAt();
        ExtractionOutcome outcome;
        try {
            Optional<byte[]> content = contentReader.read(document.blobPath());
            outcome = content
                    .map(bytes -> extractor.extract(bytes, document.contentType(), document.blobPath()))
                    .orElseGet(() -> ExtractionOutcome.failed(
                            "El documento no se encontro en el contenedor: " + document.blobPath(),
                            extractor.engineName()));
        } catch (RuntimeException exception) {
            // Red del ultimo recurso. El puerto se compromete a no lanzar, pero un
            // adaptador defectuoso no puede convertirse en un caso atascado sin explicacion.
            log.error("Unexpected failure extracting document {} ({})",
                    document.documentId(), document.blobPath(), exception);
            outcome = ExtractionOutcome.failed(
                    "Error inesperado durante la extraccion: " + exception.getMessage(),
                    extractor.engineName());
        }

        registry.recordOutcome(document.documentId(), outcome, clock.instant());

        long durationMs = StageTelemetry.elapsedMillis(startedAt);
        String documentReference = "document:" + document.documentId();
        if (outcome.state().yieldedData()) {
            StageTelemetry.success(PipelineStage.DOCUMENT_EXTRACTION, documentReference, null, durationMs);
        } else {
            // Un documento ilegible no es un fallo del sistema, pero si un desenlace que el
            // equipo debe poder contar y vigilar: una subida repentina de ilegibles suele
            // significar que algo cambio del lado de quien carga, no del extractor.
            StageTelemetry.failure(PipelineStage.DOCUMENT_EXTRACTION, documentReference, null,
                    durationMs, outcome.state() + ": " + outcome.failureReason());
        }

        log.info("verification document processed documentId={} caseId={} state={}",
                document.documentId(), document.caseId(), outcome.state());
    }
}
