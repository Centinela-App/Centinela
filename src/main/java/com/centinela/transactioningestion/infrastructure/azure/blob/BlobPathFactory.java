package com.centinela.transactioningestion.infrastructure.azure.blob;

import java.time.Instant;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.Objects;

/**
 * Construye la ruta UTC de una transaccion cruda.
 */
public final class BlobPathFactory {

    private static final DateTimeFormatter DATE_PATH_FORMAT =
            DateTimeFormatter.ofPattern("yyyy/MM/dd").withZone(ZoneOffset.UTC);

    public String create(Instant receivedAt, String transactionId) {
        Objects.requireNonNull(receivedAt, "receivedAt is required");
        if (transactionId == null || transactionId.isBlank()) {
            throw new IllegalArgumentException("transactionId is required");
        }

        return DATE_PATH_FORMAT.format(receivedAt) + "/" + transactionId + ".json";
    }
}
