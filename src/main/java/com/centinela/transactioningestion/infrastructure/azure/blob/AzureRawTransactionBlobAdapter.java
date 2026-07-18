package com.centinela.transactioningestion.infrastructure.azure.blob;

import com.azure.core.util.BinaryData;
import com.azure.storage.blob.BlobContainerClient;
import com.centinela.transactioningestion.application.exception.StorageUnavailableException;
import com.centinela.transactioningestion.application.port.out.RawTransactionStoragePort;
import com.centinela.transactioningestion.domain.model.Transaction;
import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;

import java.time.Instant;
import java.util.Objects;

/**
 * Adaptador Azure Blob para transacciones crudas.
 */
public final class AzureRawTransactionBlobAdapter implements RawTransactionStoragePort {

    private final BlobContainerClient containerClient;
    private final ObjectMapper objectMapper;
    private final BlobPathFactory pathFactory;

    public AzureRawTransactionBlobAdapter(
            BlobContainerClient containerClient,
            ObjectMapper objectMapper,
            BlobPathFactory pathFactory) {
        this.containerClient = Objects.requireNonNull(containerClient, "containerClient is required");
        this.objectMapper = Objects.requireNonNull(objectMapper, "objectMapper is required")
                .copy()
                .setSerializationInclusion(JsonInclude.Include.NON_NULL);
        this.pathFactory = Objects.requireNonNull(pathFactory, "pathFactory is required");
    }

    @Override
    public void store(Transaction transaction, Instant receivedAt) {
        Objects.requireNonNull(transaction, "transaction is required");
        String blobPath = pathFactory.create(receivedAt, transaction.transactionId());

        try {
            byte[] json = objectMapper.writeValueAsBytes(transaction);
            containerClient.getBlobClient(blobPath)
                    .upload(BinaryData.fromBytes(json), true);
        } catch (JsonProcessingException | RuntimeException exception) {
            throw new StorageUnavailableException("Raw transaction storage is unavailable", exception);
        }
    }
}
