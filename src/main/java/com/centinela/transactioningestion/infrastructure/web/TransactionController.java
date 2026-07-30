package com.centinela.transactioningestion.infrastructure.web;

import com.centinela.shared.telemetry.PipelineStage;
import com.centinela.shared.telemetry.StageTelemetry;
import com.centinela.shared.trace.TraceContextHolder;
import com.centinela.transactioningestion.application.command.IngestTransactionCommand;
import com.centinela.transactioningestion.application.port.in.IngestTransactionUseCase;
import com.centinela.transactioningestion.infrastructure.web.dto.TransactionReceiptResponse;
import com.centinela.transactioningestion.infrastructure.web.dto.TransactionRequest;
import com.centinela.transactioningestion.infrastructure.web.mapper.TransactionWebMapper;
import jakarta.validation.Valid;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Adaptador HTTP para la ingesta de transacciones.
 *
 * <p>El acuse se construye unicamente despues de que el caso de uso confirma
 * la persistencia de la transaccion.
 *
 * <p>Mide la etapa {@code INGEST_API}: el tiempo que el <b>cliente</b> espera, de extremo a
 * extremo de la peticion. Es una medida distinta de la suma de sus etapas internas —incluye
 * deserializacion, validacion y serializacion de la respuesta— y es la unica que sustenta la
 * afirmacion de que el cliente recibio respuesta antes de que concluyera el analisis, que forma
 * parte de la sustentacion.
 */
@RestController
@RequestMapping(path = "/api/v1/transactions", produces = MediaType.APPLICATION_JSON_VALUE)
public class TransactionController {

    private final IngestTransactionUseCase useCase;
    private final TransactionWebMapper mapper;

    public TransactionController(IngestTransactionUseCase useCase, TransactionWebMapper mapper) {
        this.useCase = useCase;
        this.mapper = mapper;
    }

    @PostMapping(consumes = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<TransactionReceiptResponse> ingest(
            @Valid @RequestBody TransactionRequest request) {

        long startedAt = StageTelemetry.startedAt();
        String traceparent = TraceContextHolder.currentTraceparentOrNew();

        try {
            IngestTransactionCommand command = mapper.toCommand(request);
            useCase.ingest(command);

            StageTelemetry.success(PipelineStage.INGEST_API, request.transactionId(), traceparent,
                    StageTelemetry.elapsedMillis(startedAt));

            return ResponseEntity.accepted()
                    .body(TransactionReceiptResponse.received(request.transactionId()));

        } catch (RuntimeException exception) {
            // Sin esta linea, una transaccion rechazada aqui no aparece en ninguna traza y su
            // fallo se vuelve invisible: el punto exacto de fallo quedaria sin responder
            // justo en el caso mas temprano posible.
            StageTelemetry.failure(PipelineStage.INGEST_API, request.transactionId(), traceparent,
                    StageTelemetry.elapsedMillis(startedAt), exception.getMessage());
            throw exception;
        }
    }
}
