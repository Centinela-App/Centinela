package com.centinela.caseinquiry.application.port.in;

import com.centinela.caseinquiry.domain.model.CaseView;
import com.centinela.scoringrecord.domain.model.ScoringDecision;

import java.util.Optional;

/**
 * Consulta del resultado del analisis de una transaccion.
 *
 * <p>Son dos preguntas distintas y se responden por separado a proposito: "que decidio el
 * motor" tiene respuesta para <b>toda</b> transaccion puntuada, incluidas las que no se
 * marcaron; "que caso se abrio" solo la tiene para las marcadas. Fusionarlas obligaria a
 * devolver un caso vacio para una transaccion limpia, que es justo la confusion que la
 * demostracion de una transaccion normal debe evitar.
 */
public interface QueryCaseUseCase {

    /** Decision del motor: score, umbral y reglas activadas con sus valores. */
    Optional<ScoringDecision> findAnalysis(String transactionId);

    /** Caso abierto, con su explicacion y sus documentos. */
    Optional<CaseView> findCase(String transactionId);
}
