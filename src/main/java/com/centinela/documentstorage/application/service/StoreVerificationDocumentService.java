package com.centinela.documentstorage.application.service;

import com.centinela.documentstorage.application.command.StoreVerificationDocumentCommand;
import com.centinela.documentstorage.application.exception.InvalidVerificationDocumentException;
import com.centinela.documentstorage.application.port.in.StoreVerificationDocumentUseCase;
import com.centinela.documentstorage.application.port.in.StoreVerificationDocumentUseCase.StoredVerificationDocument;
import com.centinela.documentstorage.application.port.out.VerificationDocumentStoragePort;
import com.centinela.documentstorage.domain.model.VerificationDocument;

import java.text.Normalizer;
import java.time.Clock;
import java.util.Objects;
import java.util.UUID;
import java.util.function.Supplier;

/**
 * Valida, normaliza y almacena documentos tecnicos de verificacion.
 */
public final class StoreVerificationDocumentService implements StoreVerificationDocumentUseCase {

    private final VerificationDocumentStoragePort storagePort;
    private final Clock receptionClock;
    private final Supplier<String> documentIdSupplier;

    public StoreVerificationDocumentService(
            VerificationDocumentStoragePort storagePort,
            Clock receptionClock) {
        this(storagePort, receptionClock, () -> UUID.randomUUID().toString());
    }

    public StoreVerificationDocumentService(
            VerificationDocumentStoragePort storagePort,
            Clock receptionClock,
            Supplier<String> documentIdSupplier) {
        this.storagePort = Objects.requireNonNull(storagePort, "storagePort is required");
        this.receptionClock = Objects.requireNonNull(receptionClock, "receptionClock is required");
        this.documentIdSupplier = Objects.requireNonNull(documentIdSupplier, "documentIdSupplier is required");
    }

    @Override
    public StoredVerificationDocument store(StoreVerificationDocumentCommand command) {
        Objects.requireNonNull(command, "command is required");

        byte[] content = command.content();
        if (content.length == 0) {
            throw new InvalidVerificationDocumentException("Verification document must not be empty");
        }

        String storedFilename = normalizeFilename(command.originalFilename());
        String documentId = requireGeneratedId(documentIdSupplier.get());
        VerificationDocument document = new VerificationDocument(documentId, storedFilename, content);

        String blobPath = storagePort.store(document, receptionClock.instant());
        return new StoredVerificationDocument(documentId, blobPath);
    }

    static String normalizeFilename(String originalFilename) {
        if (originalFilename == null || originalFilename.isBlank()) {
            throw new InvalidVerificationDocumentException("Verification document filename is required");
        }

        String slashNormalized = originalFilename.trim().replace('\\', '/');
        String baseName = slashNormalized.substring(slashNormalized.lastIndexOf('/') + 1).trim();
        if (baseName.isBlank() || baseName.equals(".") || baseName.equals("..")) {
            throw new InvalidVerificationDocumentException("Verification document filename is invalid");
        }

        String unicodeNormalized = Normalizer.normalize(baseName, Normalizer.Form.NFKC);
        String safeName = unicodeNormalized
                .replaceAll("\\s+", "_")
                .replaceAll("[^A-Za-z0-9._-]", "_")
                .replaceAll("_+", "_");

        safeName = stripLeadingDots(safeName);
        if (safeName.isBlank() || safeName.equals(".") || safeName.equals("..")) {
            throw new InvalidVerificationDocumentException("Verification document filename is invalid");
        }

        return safeName;
    }

    private static String stripLeadingDots(String value) {
        int firstNonDot = 0;
        while (firstNonDot < value.length() && value.charAt(firstNonDot) == '.') {
            firstNonDot++;
        }
        return value.substring(firstNonDot);
    }

    private static String requireGeneratedId(String value) {
        if (value == null || value.isBlank()) {
            throw new IllegalStateException("documentIdSupplier returned an invalid value");
        }
        return value;
    }
}
