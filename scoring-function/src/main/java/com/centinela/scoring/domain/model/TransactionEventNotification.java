package com.centinela.scoring.domain.model;

import java.time.OffsetDateTime;
import java.util.UUID;

/** Contrato exacto {@code transaction-event-v1} recibido desde Event Grid. */
public record TransactionEventNotification(
        String eventId,
        String transactionId,
        String accountId,
        OffsetDateTime occurredAt,
        String blobPath,
        String schemaVersion) {

    public static final String SCHEMA_VERSION = "transaction-event-v1";

    public TransactionEventNotification {
        if (eventId == null || eventId.isBlank()) throw new IllegalArgumentException("eventId is required");
        try {
            UUID.fromString(eventId);
        } catch (IllegalArgumentException exception) {
            throw new IllegalArgumentException("eventId must be a UUID", exception);
        }
        if (transactionId == null || transactionId.isBlank()) throw new IllegalArgumentException("transactionId is required");
        if (accountId == null || accountId.isBlank()) throw new IllegalArgumentException("accountId is required");
        if (occurredAt == null) throw new IllegalArgumentException("occurredAt is required");
        if (blobPath == null || blobPath.isBlank()) throw new IllegalArgumentException("blobPath is required");
        if (!SCHEMA_VERSION.equals(schemaVersion)) throw new IllegalArgumentException("Unsupported schemaVersion: " + schemaVersion);
    }
}
