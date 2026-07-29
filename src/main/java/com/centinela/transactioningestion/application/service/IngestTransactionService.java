package com.centinela.transactioningestion.application.service;

import com.centinela.shared.telemetry.PipelineStage;
import com.centinela.shared.telemetry.StageTelemetry;
import com.centinela.shared.trace.TraceContextHolder;
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
 *
 * <p>Las dos etapas se instrumentan por separado. Una transaccion que se persistio pero
 * cuyo evento no se publico no genera caso, y la unica forma de distinguir ese fallo del
 * de una que ni siquiera llego a guardarse es tener un registro por etapa.
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

        String transactionId = command.transaction().transactionId();
        String traceparent = TraceContextHolder.currentTraceparentOrNew();

        long persistStarted = StageTelemetry.startedAt();
        try {
            storagePort.store(command.transaction(), receivedAt);
        } catch (RuntimeException exception) {
            StageTelemetry.failure(PipelineStage.RAW_PERSIST, transactionId, traceparent,
                    StageTelemetry.elapsedMillis(persistStarted), exception.getMessage());
            throw exception;
        }
        StageTelemetry.success(PipelineStage.RAW_PERSIST, transactionId, traceparent,
                StageTelemetry.elapsedMillis(persistStarted));

        long publishStarted = StageTelemetry.startedAt();
        try {
            eventPublisher.publish(command.transaction(), receivedAt);
        } catch (RuntimeException exception) {
            StageTelemetry.failure(PipelineStage.EVENT_PUBLISH, transactionId, traceparent,
                    StageTelemetry.elapsedMillis(publishStarted), exception.getMessage());
            throw exception;
        }
        StageTelemetry.success(PipelineStage.EVENT_PUBLISH, transactionId, traceparent,
                StageTelemetry.elapsedMillis(publishStarted));
    }
}
