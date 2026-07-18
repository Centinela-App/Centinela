package com.centinela.transactioningestion.infrastructure.web;

import com.centinela.transactioningestion.application.command.IngestTransactionCommand;
import com.centinela.transactioningestion.application.port.in.IngestTransactionUseCase;
import com.centinela.transactioningestion.infrastructure.web.dto.TransactionReceiptResponse;
import com.centinela.transactioningestion.infrastructure.web.dto.TransactionRequest;
import com.centinela.transactioningestion.infrastructure.web.mapper.TransactionWebMapper;
import jakarta.validation.Valid;
import org.springframework.boot.autoconfigure.condition.ConditionalOnBean;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Adaptador HTTP para la ingesta de transacciones.
 *
 * <p>El bean se habilita cuando existe una implementacion del puerto de entrada.
 * Durante ISS-S1-007 el controller se prueba de forma aislada con ese puerto
 * simulado; ISS-S1-008 registra la implementacion real.
 */
@RestController
@RequestMapping(path = "/api/v1/transactions", produces = MediaType.APPLICATION_JSON_VALUE)
@ConditionalOnBean(IngestTransactionUseCase.class)
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
        IngestTransactionCommand command = mapper.toCommand(request);
        useCase.ingest(command);

        return ResponseEntity.accepted()
                .body(TransactionReceiptResponse.received(request.transactionId()));
    }
}
