package com.centinela.transactioningestion.application.service;

import com.centinela.transactioningestion.application.command.IngestTransactionCommand;
import com.centinela.transactioningestion.application.port.in.IngestTransactionUseCase;
import com.centinela.transactioningestion.application.port.out.RawTransactionStoragePort;

import java.time.Clock;
import java.util.Objects;

/**
 * Caso de uso de ingesta cruda de transacciones.
 *
 * <p>Solo termina normalmente cuando el puerto de almacenamiento confirma la
 * escritura. No publica mensajes ni ejecuta scoring.
 */
public final class IngestTransactionService implements IngestTransactionUseCase {

    private final RawTransactionStoragePort storagePort;
    private final Clock receptionClock;

    public IngestTransactionService(RawTransactionStoragePort storagePort, Clock receptionClock) {
        this.storagePort = Objects.requireNonNull(storagePort, "storagePort is required");
        this.receptionClock = Objects.requireNonNull(receptionClock, "receptionClock is required");
    }

    @Override
    public void ingest(IngestTransactionCommand command) {
        Objects.requireNonNull(command, "command is required");
        storagePort.store(command.transaction(), receptionClock.instant());
    }
}
