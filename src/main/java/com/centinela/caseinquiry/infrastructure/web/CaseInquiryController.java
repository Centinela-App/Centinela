package com.centinela.caseinquiry.infrastructure.web;

import com.centinela.caseinquiry.application.port.in.QueryCaseUseCase;
import com.centinela.caseinquiry.infrastructure.web.dto.CaseResponse;
import com.centinela.caseinquiry.infrastructure.web.dto.TransactionAnalysisResponse;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Objects;

/**
 * Consulta del resultado del analisis y del caso asociado.
 *
 * <p>Es la superficie de lectura que faltaba: la ingesta responde {@code 202} antes de que
 * exista veredicto — por diseno, para no bloquear al cliente — de modo que sin estos dos
 * recursos el resultado del analisis solo era observable entrando a la base de datos.
 *
 * <p>Un {@code 404} en {@code /cases} significa "esta transaccion no fue marcada", que es
 * una respuesta legitima y no un error: es exactamente lo que debe devolver una transaccion
 * normal.
 */
@RestController
@RequestMapping(path = "/api/v1", produces = MediaType.APPLICATION_JSON_VALUE)
@ConditionalOnProperty(name = "centinela.inquiry.enabled", havingValue = "true")
public class CaseInquiryController {

    private final QueryCaseUseCase queryCase;

    public CaseInquiryController(QueryCaseUseCase queryCase) {
        this.queryCase = Objects.requireNonNull(queryCase, "queryCase is required");
    }

    /** Decision del motor sobre una transaccion, se haya marcado o no. */
    @GetMapping("/transactions/{transactionId}/analysis")
    public ResponseEntity<TransactionAnalysisResponse> analysis(@PathVariable String transactionId) {
        return queryCase.findAnalysis(transactionId)
                .map(TransactionAnalysisResponse::from)
                .map(ResponseEntity::ok)
                .orElseGet(() -> ResponseEntity.notFound().build());
    }

    /** Caso abierto para una transaccion marcada, con explicacion y documentos. */
    @GetMapping("/cases/{transactionId}")
    public ResponseEntity<CaseResponse> caseByTransaction(@PathVariable String transactionId) {
        return queryCase.findCase(transactionId)
                .map(CaseResponse::from)
                .map(ResponseEntity::ok)
                .orElseGet(() -> ResponseEntity.notFound().build());
    }
}
