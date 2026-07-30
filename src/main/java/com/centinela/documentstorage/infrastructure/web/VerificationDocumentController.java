package com.centinela.documentstorage.infrastructure.web;

import com.centinela.documentstorage.application.command.StoreVerificationDocumentCommand;
import com.centinela.documentstorage.application.exception.InvalidVerificationDocumentException;
import com.centinela.documentstorage.application.port.in.StoreVerificationDocumentUseCase;
import com.centinela.documentstorage.infrastructure.web.dto.DocumentReceiptResponse;
import com.centinela.documentverification.application.port.out.VerificationDocumentRegistryPort;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.time.Instant;
import java.util.Optional;

/**
 * Adaptador HTTP para la carga tecnica de documentos de verificacion.
 *
 * <p>La respuesta se emite <b>en cuanto el archivo esta guardado</b>, sin esperar a la
 * extraccion de datos. Registrar el documento como pendiente y devolver {@code 201} es
 * deliberado: el analista no debe quedarse mirando una peticion colgada mientras se
 * procesa un PDF, y un fallo de extraccion no puede convertirse en un error de carga.
 */
@RestController
@RequestMapping(
        path = "/api/v1/verification-documents",
        produces = MediaType.APPLICATION_JSON_VALUE)
public class VerificationDocumentController {

    private static final Logger log = LoggerFactory.getLogger(VerificationDocumentController.class);

    private final StoreVerificationDocumentUseCase useCase;
    private final Optional<VerificationDocumentRegistryPort> registry;

    public VerificationDocumentController(
            StoreVerificationDocumentUseCase useCase,
            Optional<VerificationDocumentRegistryPort> registry) {
        this.useCase = useCase;
        this.registry = registry;
    }

    @PostMapping(consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public ResponseEntity<DocumentReceiptResponse> store(
            @RequestPart("file") MultipartFile file,
            @RequestParam(value = "transactionId", required = false) String transactionId) {

        StoreVerificationDocumentCommand command = new StoreVerificationDocumentCommand(
                file.getOriginalFilename(),
                readContent(file),
                file.getContentType(),
                transactionId);

        StoreVerificationDocumentUseCase.StoredVerificationDocument stored = useCase.store(command);

        if (transactionId != null && !transactionId.isBlank()) {
            registerForExtraction(stored.blobPath(), file.getContentType(), transactionId);
        }

        return ResponseEntity.status(HttpStatus.CREATED)
                .body(DocumentReceiptResponse.stored(stored.documentId()));
    }

    /**
     * El archivo ya esta a salvo en el contenedor cuando se llega aqui. Si el registro
     * falla, se pierde la extraccion automatica pero no el documento, y eso es preferible
     * a devolver un error que haga creer al analista que su carga no se guardo.
     */
    private void registerForExtraction(String blobPath, String contentType, String transactionId) {
        registry.ifPresent(port -> {
            try {
                port.registerReceived(transactionId, blobPath, contentType, Instant.now())
                        .ifPresentOrElse(
                                documentId -> log.info(
                                        "verification document registered documentId={} transactionId={}",
                                        documentId, transactionId),
                                () -> log.warn(
                                        "verification document {} stored but no case exists for transaction {}",
                                        blobPath, transactionId));
            } catch (RuntimeException exception) {
                log.error("verification document {} stored but could not be registered for transaction {}",
                        blobPath, transactionId, exception);
            }
        });
    }

    private static byte[] readContent(MultipartFile file) {
        try {
            return file.getBytes();
        } catch (IOException exception) {
            throw new InvalidVerificationDocumentException(
                    "Verification document could not be read",
                    exception);
        }
    }
}
