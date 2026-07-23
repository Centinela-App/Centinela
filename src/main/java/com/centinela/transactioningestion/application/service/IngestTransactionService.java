package com.centinela.transactioningestion.application.service;

import com.centinela.transactioningestion.application.command.IngestTransactionCommand;
import com.centinela.transactioningestion.application.port.in.IngestTransactionUseCase;
import com.centinela.transactioningestion.application.port.out.RawTransactionStoragePort;
import com.centinela.transactioningestion.application.port.out.TransactionEventPublisherPort;

import java.time.Clock;
import java.time.Instant;
import java.util.Objects;

/**
 * Caso de uso de ingesta cruda de transacciones.
 *
 * <p>Orquesta la secuencia <b>persistir &rarr; publicar evento &rarr; responder</b>:
 * primero confirma la escritura en el almacenamiento y solo despues publica el
 * evento {@code transaction-event-v1}. No invoca al motor de scoring ni espera su
 * resultado (desacoplamiento). Si la publicacion falla, la excepcion se propaga para
 * no afirmar un acuse falso.
 */
public final class IngestTransactionService implements IngestTransactionUseCase {

    private final RawTransactionStoragePort storagePort;
    private final TransactionEventPublisherPort eventPublisher;
    private final Clock receptionClock;

    public IngestTransactionService(
            RawTransactionStoragePort storagePort,
            TransactionEventPublisherPort eventPublisher,
            Clock receptionClock) {
        this.storagePort = Objects.requireNonNull(storagePort, "storagePort is required");
        this.eventPublisher = Objects.requireNonNull(eventPublisher, "eventPublisher is required");
        this.receptionClock = Objects.requireNonNull(receptionClock, "receptionClock is required");
    }

    @Override
    public void ingest(IngestTransactionCommand command) {
        Objects.requireNonNull(command, "command is required");
        Instant receivedAt = receptionClock.instant();

        storagePort.store(command.transaction(), receivedAt);
        eventPublisher.publish(command.transaction(), receivedAt);
    }
}
