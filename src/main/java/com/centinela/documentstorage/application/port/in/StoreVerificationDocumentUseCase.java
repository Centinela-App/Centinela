package com.centinela.documentstorage.application.port.in;

import com.centinela.documentstorage.application.command.StoreVerificationDocumentCommand;

/**
 * Puerto de entrada para almacenar un documento tecnico de verificacion.
 */
@FunctionalInterface
public interface StoreVerificationDocumentUseCase {

    /**
     * Almacena el documento y devuelve su identificador y su ubicacion.
     *
     * <p>La ubicacion forma parte del acuse porque el flujo de verificacion documental
     * necesita volver a leer el archivo mas tarde para extraer sus datos.
     */
    StoredVerificationDocument store(StoreVerificationDocumentCommand command);

    /**
     * Acuse de la carga.
     *
     * @param documentId identificador generado
     * @param blobPath   ruta dentro del contenedor de documentos
     */
    record StoredVerificationDocument(String documentId, String blobPath) {
    }
}
