package com.centinela.caseexplanation.domain.explanation;

/**
 * El registro del motor no alcanza para explicar la decision.
 *
 * <p>El enunciado de Semana 3 es explicito sobre a quien corresponde la correccion: si no
 * se puede producir una explicacion, el defecto esta en el motor de scoring, que no dejo
 * constancia suficiente de su propia decision. Esta excepcion existe para que ese
 * diagnostico quede escrito en el codigo y no se confunda con un fallo del explicador.
 */
public class InsufficientDecisionRecordException extends RuntimeException {

    public InsufficientDecisionRecordException(String message) {
        super(message);
    }
}
