package com.centinela.documentverification.application.port.in;

/** Caso de uso: extraer los datos de los documentos de verificacion pendientes. */
public interface ExtractVerificationDocumentUseCase {

    /**
     * Procesa un lote de documentos pendientes.
     *
     * @return cuantos documentos se procesaron, con exito o no; todos quedan en un estado
     *         terminal consultable
     */
    int processPending();
}
