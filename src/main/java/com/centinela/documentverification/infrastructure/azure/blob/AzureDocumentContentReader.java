package com.centinela.documentverification.infrastructure.azure.blob;

import com.azure.storage.blob.BlobContainerClient;
import com.centinela.documentverification.application.port.out.DocumentContentReaderPort;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.Objects;
import java.util.Optional;

/** Lee el documento ya almacenado en el contenedor privado, mediante Managed Identity. */
public final class AzureDocumentContentReader implements DocumentContentReaderPort {

    private static final Logger log = LoggerFactory.getLogger(AzureDocumentContentReader.class);

    private final BlobContainerClient containerClient;

    public AzureDocumentContentReader(BlobContainerClient containerClient) {
        this.containerClient = Objects.requireNonNull(containerClient, "containerClient is required");
    }

    @Override
    public Optional<byte[]> read(String blobPath) {
        try {
            var blobClient = containerClient.getBlobClient(blobPath);
            if (!blobClient.exists()) {
                return Optional.empty();
            }
            return Optional.of(blobClient.downloadContent().toBytes());
        } catch (RuntimeException exception) {
            // El servicio de extraccion traduce el vacio a EXTRACTION_FAILED con motivo.
            // Propagar aqui detendria el lote por un fallo de un solo documento.
            log.error("Could not read verification document {}", blobPath, exception);
            return Optional.empty();
        }
    }
}
