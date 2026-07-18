package com.centinela.documentstorage.application.port.in;

import com.centinela.documentstorage.application.command.StoreVerificationDocumentCommand;

/**
 * Puerto de entrada para almacenar un documento tecnico de verificacion.
 */
@FunctionalInterface
public interface StoreVerificationDocumentUseCase {

    /**
     * Almacena el documento y devuelve el identificador generado.
     */
    String store(StoreVerificationDocumentCommand command);
}
