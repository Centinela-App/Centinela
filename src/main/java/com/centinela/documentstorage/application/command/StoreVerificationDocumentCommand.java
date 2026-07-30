package com.centinela.documentstorage.application.command;

import java.util.Objects;

/**
 * Datos de entrada independientes de HTTP para almacenar un documento.
 *
 * @param originalFilename nombre tal como lo envio el cliente
 * @param content          bytes del archivo
 * @param contentType      tipo declarado; puede faltar o ser incorrecto, el extractor no
 *                         se fia de el sin comprobar el contenido
 * @param transactionId    transaccion cuyo caso recibe el documento; nulo cuando la carga
 *                         es puramente tecnica y no escala ningun caso
 */
public record StoreVerificationDocumentCommand(
        String originalFilename,
        byte[] content,
        String contentType,
        String transactionId) {

    public StoreVerificationDocumentCommand {
        content = Objects.requireNonNull(content, "content is required").clone();
    }

    /** Forma heredada de Semana 1, sin metadatos de escalamiento. */
    public StoreVerificationDocumentCommand(String originalFilename, byte[] content) {
        this(originalFilename, content, null, null);
    }

    @Override
    public byte[] content() {
        return content.clone();
    }
}
