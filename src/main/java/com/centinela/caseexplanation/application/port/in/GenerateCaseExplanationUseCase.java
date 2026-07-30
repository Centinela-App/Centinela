package com.centinela.caseexplanation.application.port.in;

/** Caso de uso: generar las explicaciones de los casos que aun no la tienen. */
public interface GenerateCaseExplanationUseCase {

    /**
     * Procesa un lote de casos pendientes.
     *
     * @return cuantas explicaciones se generaron con exito en este lote
     */
    int generatePending();
}
