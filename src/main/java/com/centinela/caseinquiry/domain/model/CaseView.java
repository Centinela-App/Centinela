package com.centinela.caseinquiry.domain.model;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;

/**
 * Vista de un caso para quien lo consulta.
 *
 * <p>Incluye deliberadamente el <b>estado</b> de la explicacion y no solo su texto. Un caso
 * sin explicacion no es un caso incompleto: es un caso cuya explicacion todavia no se ha
 * generado, o cuya generacion fallo. Devolver un texto vacio sin decir cual de las dos
 * cosas ocurrio dejaria al analista sin saber si debe esperar o escalar.
 */
public record CaseView(
        Long caseId,
        String transactionId,
        String accountId,
        BigDecimal score,
        String status,
        String explanationState,
        String explanation,
        String traceparent,
        Instant openedAt,
        Instant updatedAt,
        List<VerificationDocumentView> documents) {

    public boolean hasExplanation() {
        return explanation != null && !explanation.isBlank();
    }
}
