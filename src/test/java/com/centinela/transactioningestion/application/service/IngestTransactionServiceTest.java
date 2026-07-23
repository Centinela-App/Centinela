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
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertSame;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

class IngestTransactionServiceTest {

    private static final Instant RECEIVED_AT = Instant.parse("2026-07-18T15:30:00Z");
    private static final Clock FIXED_CLOCK = Clock.fixed(RECEIVED_AT, ZoneOffset.UTC);
    // La publicacion del evento se cubre en IngestPublishesEventTest; aqui basta un no-op.
    private static final TransactionEventPublisherPort NO_OP_PUBLISHER = (transaction, receivedAt) -> {
    };

    @Test
    void should_ack_only_after_blob_persistence() {
        Transaction transaction = transaction();
        AtomicBoolean stored = new AtomicBoolean(false);
        AtomicReference<Instant> capturedReception = new AtomicReference<>();

        RawTransactionStoragePort storagePort = (storedTransaction, receivedAt) -> {
            assertSame(transaction, storedTransaction);
            capturedReception.set(receivedAt);
            stored.set(true);
        };

        IngestTransactionService service = new IngestTransactionService(storagePort, NO_OP_PUBLISHER, FIXED_CLOCK);
        service.ingest(new IngestTransactionCommand(transaction));

        assertTrue(stored.get(), "The use case must persist before returning normally");
        assertEquals(RECEIVED_AT, capturedReception.get());
    }

    @Test
    void should_preserve_optional_coordinates_when_present() {
        Transaction transaction = transaction();
        AtomicReference<Transaction> captured = new AtomicReference<>();
        RawTransactionStoragePort storagePort = (storedTransaction, receivedAt) -> captured.set(storedTransaction);

        new IngestTransactionService(storagePort, NO_OP_PUBLISHER, FIXED_CLOCK)
                .ingest(new IngestTransactionCommand(transaction));

        assertEquals(new BigDecimal("4.7110"), captured.get().location().latitude());
        assertEquals(new BigDecimal("-74.0721"), captured.get().location().longitude());
    }

    @Test
    void should_not_return_success_when_storage_fails() {
        StorageUnavailableException expected = new StorageUnavailableException(
                "storage unavailable",
                new RuntimeException("synthetic failure"));
        RawTransactionStoragePort storagePort = (transaction, receivedAt) -> {
            throw expected;
        };

        IngestTransactionService service = new IngestTransactionService(storagePort, NO_OP_PUBLISHER, FIXED_CLOCK);

        StorageUnavailableException actual = assertThrows(
                StorageUnavailableException.class,
                () -> service.ingest(new IngestTransactionCommand(transaction())));

        assertSame(expected, actual);
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
