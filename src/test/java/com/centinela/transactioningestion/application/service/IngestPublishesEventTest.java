package com.centinela.transactioningestion.application.service;

import com.centinela.transactioningestion.application.command.IngestTransactionCommand;
import com.centinela.transactioningestion.application.exception.StorageUnavailableException;
import com.centinela.transactioningestion.application.port.out.RawTransactionStoragePort;
import com.centinela.transactioningestion.application.port.out.TransactionEventPublisherPort;
import com.centinela.transactioningestion.domain.model.Location;
import com.centinela.transactioningestion.domain.model.Merchant;
import com.centinela.transactioningestion.domain.model.Transaction;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.Clock;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicReference;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertSame;
import static org.junit.jupiter.api.Assertions.assertThrows;

/**
 * TEST-S2-007: la ingesta persiste y luego publica el evento de transaccion, en ese
 * orden, sin ejecutar scoring. Verifica la secuencia persistir &rarr; publicar &rarr;
 * responder y la politica ante fallo de publicacion (propagar, sin acuse falso).
 */
class IngestPublishesEventTest {

    private static final Instant RECEIVED_AT = Instant.parse("2026-07-18T15:30:00Z");
    private static final Clock FIXED_CLOCK = Clock.fixed(RECEIVED_AT, ZoneOffset.UTC);

    @Test
    void should_persist_then_publish_event_in_order() {
        List<String> order = new ArrayList<>();
        AtomicReference<Transaction> publishedTransaction = new AtomicReference<>();
        AtomicReference<Instant> publishedInstant = new AtomicReference<>();
        Transaction transaction = transaction();

        RawTransactionStoragePort storagePort = (storedTransaction, receivedAt) -> order.add("store");
        TransactionEventPublisherPort publisher = (publishedTx, receivedAt) -> {
            order.add("publish");
            publishedTransaction.set(publishedTx);
            publishedInstant.set(receivedAt);
        };

        new IngestTransactionService(storagePort, publisher, FIXED_CLOCK)
                .ingest(new IngestTransactionCommand(transaction));

        // El evento se publica DESPUES de persistir y ANTES de que el caso de uso retorne.
        assertEquals(List.of("store", "publish"), order);
        assertSame(transaction, publishedTransaction.get());
        // Mismo instante de recepcion que el usado para persistir (blobPath coherente).
        assertEquals(RECEIVED_AT, publishedInstant.get());
    }

    @Test
    void should_not_publish_event_when_storage_fails() {
        AtomicReference<Boolean> published = new AtomicReference<>(false);
        RawTransactionStoragePort storagePort = (transaction, receivedAt) -> {
            throw new StorageUnavailableException("storage down", new RuntimeException("synthetic"));
        };
        TransactionEventPublisherPort publisher = (transaction, receivedAt) -> published.set(true);

        IngestTransactionService service =
                new IngestTransactionService(storagePort, publisher, FIXED_CLOCK);

        assertThrows(
                StorageUnavailableException.class,
                () -> service.ingest(new IngestTransactionCommand(transaction())));
        assertFalse(published.get(), "No debe publicarse el evento si la persistencia fallo");
    }

    @Test
    void should_propagate_and_not_ack_when_publication_fails() {
        TransactionEventPublisherPort.PublicationFailedException failure =
                new TransactionEventPublisherPort.PublicationFailedException(
                        "event grid unavailable", new RuntimeException("synthetic"));
        RawTransactionStoragePort storagePort = (transaction, receivedAt) -> {
            // persistencia exitosa
        };
        TransactionEventPublisherPort publisher = (transaction, receivedAt) -> {
            throw failure;
        };

        IngestTransactionService service =
                new IngestTransactionService(storagePort, publisher, FIXED_CLOCK);

        TransactionEventPublisherPort.PublicationFailedException actual = assertThrows(
                TransactionEventPublisherPort.PublicationFailedException.class,
                () -> service.ingest(new IngestTransactionCommand(transaction())));
        assertSame(failure, actual);
    }

    private static Transaction transaction() {
        return new Transaction(
                "tx-1001",
                "acct-2001",
                new BigDecimal("150000.50"),
                "COP",
                OffsetDateTime.parse("2026-07-18T10:00:00-05:00"),
                new Location("CO", "Bogota", new BigDecimal("4.7110"), new BigDecimal("-74.0721")),
                new Merchant("Comercio Demo", "RETAIL"));
    }
}
