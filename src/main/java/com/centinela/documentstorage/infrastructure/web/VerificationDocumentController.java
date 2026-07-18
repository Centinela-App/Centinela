package com.centinela.documentstorage.infrastructure.web;

import com.centinela.documentstorage.application.command.StoreVerificationDocumentCommand;
import com.centinela.documentstorage.application.exception.InvalidVerificationDocumentException;
import com.centinela.documentstorage.application.port.in.StoreVerificationDocumentUseCase;
import com.centinela.documentstorage.infrastructure.web.dto.DocumentReceiptResponse;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;

/**
 * Adaptador HTTP para la carga tecnica de documentos de verificacion.
 */
@RestController
@RequestMapping(
        path = "/api/v1/verification-documents",
        produces = MediaType.APPLICATION_JSON_VALUE)
public class VerificationDocumentController {

    private final StoreVerificationDocumentUseCase useCase;

    public VerificationDocumentController(StoreVerificationDocumentUseCase useCase) {
        this.useCase = useCase;
    }

    @PostMapping(consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public ResponseEntity<DocumentReceiptResponse> store(
            @RequestPart("file") MultipartFile file) {
        StoreVerificationDocumentCommand command = new StoreVerificationDocumentCommand(
                file.getOriginalFilename(),
                readContent(file));
        String documentId = useCase.store(command);

        return ResponseEntity.status(HttpStatus.CREATED)
                .body(DocumentReceiptResponse.stored(documentId));
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
