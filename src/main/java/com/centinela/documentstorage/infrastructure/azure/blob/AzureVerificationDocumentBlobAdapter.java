package com.centinela.documentstorage.infrastructure.azure.blob;

import com.azure.core.util.BinaryData;
import com.azure.storage.blob.BlobContainerClient;
import com.centinela.documentstorage.application.exception.DocumentStorageUnavailableException;
import com.centinela.documentstorage.application.port.out.VerificationDocumentStoragePort;
import com.centinela.documentstorage.domain.model.VerificationDocument;

import java.time.Instant;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.Objects;

/**
 * Adaptador Azure Blob para documentos tecnicos de verificacion.
 */
public final class AzureVerificationDocumentBlobAdapter implements VerificationDocumentStoragePort {

    private static final DateTimeFormatter DATE_PATH_FORMAT =
            DateTimeFormatter.ofPattern("yyyy/MM/dd").withZone(ZoneOffset.UTC);

    private final BlobContainerClient containerClient;

    public AzureVerificationDocumentBlobAdapter(BlobContainerClient containerClient) {
        this.containerClient = Objects.requireNonNull(containerClient, "containerClient is required");
    }

    @Override
    public void store(VerificationDocument document, Instant receivedAt) {
        Objects.requireNonNull(document, "document is required");
        Objects.requireNonNull(receivedAt, "receivedAt is required");

        try {
            containerClient.getBlobClient(createBlobPath(receivedAt, document))
                    .upload(BinaryData.fromBytes(document.content()), true);
        } catch (RuntimeException exception) {
            throw new DocumentStorageUnavailableException(
                    "Verification document storage is unavailable",
                    exception);
        }
    }

    static String createBlobPath(Instant receivedAt, VerificationDocument document) {
        return DATE_PATH_FORMAT.format(receivedAt)
                + "/" + document.documentId()
                + "/" + document.storedFilename();
    }
}
