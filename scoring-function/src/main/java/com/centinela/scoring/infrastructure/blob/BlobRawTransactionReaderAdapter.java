package com.centinela.scoring.infrastructure.blob;

import com.azure.storage.blob.BlobServiceClient;
import com.centinela.scoring.application.port.out.RawTransactionReaderPort;
import com.centinela.scoring.domain.model.TransactionEvent;
import com.centinela.scoring.domain.model.TransactionEventNotification;
import com.fasterxml.jackson.databind.ObjectMapper;

import java.io.IOException;
import java.util.Objects;
import java.util.Set;

/** Descarga el JSON crudo señalado por {@code blobPath} y valida su identidad. */
public final class BlobRawTransactionReaderAdapter implements RawTransactionReaderPort {
    private final BlobServiceClient blobServiceClient;
    private final ObjectMapper objectMapper;
    private final Set<String> allowedContainers;

    public BlobRawTransactionReaderAdapter(
            BlobServiceClient blobServiceClient,
            ObjectMapper objectMapper,
            String expectedContainer) {
        this(blobServiceClient, objectMapper, Set.of(expectedContainer));
    }

    public BlobRawTransactionReaderAdapter(
            BlobServiceClient blobServiceClient,
            ObjectMapper objectMapper,
            Set<String> allowedContainers) {
        this.blobServiceClient = Objects.requireNonNull(blobServiceClient, "blobServiceClient is required");
        this.objectMapper = Objects.requireNonNull(objectMapper, "objectMapper is required");
        this.allowedContainers = Set.copyOf(Objects.requireNonNull(allowedContainers, "allowedContainers is required"));
        if (this.allowedContainers.isEmpty() || this.allowedContainers.stream().anyMatch(value -> value == null || value.isBlank())) {
            throw new IllegalArgumentException("allowedContainers must contain valid names");
        }
    }

    @Override
    public TransactionEvent read(TransactionEventNotification notification) {
        PathParts path = pathParts(notification.blobPath());
        if (!allowedContainers.contains(path.container())) {
            throw new IllegalArgumentException("blobPath points to an unauthorized container");
        }
        try {
            byte[] json = blobServiceClient
                    .getBlobContainerClient(path.container())
                    .getBlobClient(path.blobName())
                    .downloadContent()
                    .toBytes();
            TransactionEvent transaction = objectMapper.readValue(json, TransactionEvent.class);
            validateIdentity(notification, transaction);
            return transaction;
        } catch (IOException | RuntimeException exception) {
            throw new IllegalStateException("Unable to read raw transaction from Blob", exception);
        }
    }

    public static String containerFrom(String blobPath) {
        return pathParts(blobPath).container();
    }

    private static PathParts pathParts(String blobPath) {
        if (blobPath == null || blobPath.isBlank()) {
            throw new IllegalArgumentException("blobPath is required");
        }
        int separator = blobPath.indexOf('/');
        if (separator <= 0 || separator == blobPath.length() - 1) {
            throw new IllegalArgumentException("blobPath must use container/blob format");
        }
        return new PathParts(blobPath.substring(0, separator), blobPath.substring(separator + 1));
    }

    private static void validateIdentity(TransactionEventNotification notification, TransactionEvent transaction) {
        if (!notification.transactionId().equals(transaction.transactionId())) {
            throw new IllegalArgumentException("transactionId does not match raw Blob");
        }
        if (!notification.accountId().equals(transaction.accountId())) {
            throw new IllegalArgumentException("accountId does not match raw Blob");
        }
        if (!notification.occurredAt().equals(transaction.occurredAt())) {
            throw new IllegalArgumentException("occurredAt does not match raw Blob");
        }
    }

    private record PathParts(String container, String blobName) {
    }
}
