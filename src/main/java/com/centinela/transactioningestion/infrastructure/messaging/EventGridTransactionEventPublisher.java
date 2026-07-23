package com.centinela.transactioningestion.infrastructure.messaging;

import com.azure.core.util.BinaryData;
import com.azure.messaging.eventgrid.EventGridEvent;
import com.azure.messaging.eventgrid.EventGridPublisherClient;
import com.centinela.shared.event.TransactionEvent;
import com.centinela.transactioningestion.application.port.out.TransactionEventPublisherPort;
import com.centinela.transactioningestion.domain.model.Transaction;

import java.time.Instant;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.Objects;
import java.util.UUID;

/**
 * Adaptador de salida que publica {@code transaction-event-v1} en un Event Grid
 * Topic mediante Managed Identity.
 *
 * <p>Arma el contrato {@link TransactionEvent} a partir de la transaccion de dominio
 * y del instante de recepcion, calculando el {@code blobPath} con la misma convencion
 * que el adaptador de almacenamiento ({@code contenedor/yyyy/MM/dd/{transactionId}.json})
 * para que el evento apunte exactamente al JSON crudo persistido.
 *
 * <p>No incluye score ni decision: esos datos aun no existen cuando se publica el
 * evento.
 */
public final class EventGridTransactionEventPublisher implements TransactionEventPublisherPort {

    private static final DateTimeFormatter DATE_PATH_FORMAT =
            DateTimeFormatter.ofPattern("yyyy/MM/dd").withZone(ZoneOffset.UTC);
    private static final String EVENT_TYPE = "Centinela.Transaction.Ingested";
    private static final String DATA_VERSION = "1.0";

    private final EventGridPublisherClient<EventGridEvent> publisherClient;
    private final String containerName;

    public EventGridTransactionEventPublisher(
            EventGridPublisherClient<EventGridEvent> publisherClient,
            String containerName) {
        this.publisherClient = Objects.requireNonNull(publisherClient, "publisherClient is required");
        if (containerName == null || containerName.isBlank()) {
            throw new IllegalArgumentException("containerName is required");
        }
        this.containerName = containerName;
    }

    @Override
    public void publish(Transaction transaction, Instant receivedAt) {
        Objects.requireNonNull(transaction, "transaction is required");
        Objects.requireNonNull(receivedAt, "receivedAt is required");

        TransactionEvent payload = new TransactionEvent(
                UUID.randomUUID().toString(),
                transaction.transactionId(),
                transaction.accountId(),
                transaction.occurredAt(),
                blobPath(transaction.transactionId(), receivedAt),
                TransactionEvent.SCHEMA_VERSION);

        EventGridEvent event = new EventGridEvent(
                "transactions/" + transaction.transactionId(),
                EVENT_TYPE,
                BinaryData.fromObject(payload),
                DATA_VERSION);

        try {
            publisherClient.sendEvent(event);
        } catch (RuntimeException exception) {
            throw new PublicationFailedException(
                    "Transaction event could not be published to Event Grid", exception);
        }
    }

    private String blobPath(String transactionId, Instant receivedAt) {
        return containerName + "/" + DATE_PATH_FORMAT.format(receivedAt) + "/" + transactionId + ".json";
    }
}
